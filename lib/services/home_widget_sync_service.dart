import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter/services.dart';
import 'package:kreta_api/kreta_api.dart';

import '../theme/oled_theme.dart';
import '../widgets/period_countdown_badge.dart';
import 'demo_data_service.dart';
import 'kreta_client.dart';
import 'token_storage_service.dart';

/// Shared bridge synchronizing Tinta Napló's active timetable, theme accent,
/// and Live Activity toggle state to Android `"tinta_home_widget_prefs"` so
/// the `2x1` / `2x2` Home Screen Widgets and Samsung Now Bar / Live Activity
/// stay aligned in real time (including in Demó mód).
class HomeWidgetSyncService {
  HomeWidgetSyncService._({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('hu.mlnlbrt.tintanaplo/home_widget');

  @visibleForTesting
  factory HomeWidgetSyncService.forTest(MethodChannel channel) =>
      HomeWidgetSyncService._(channel: channel);

  static final HomeWidgetSyncService instance = HomeWidgetSyncService._();

  /// Fallback Tinta cyan accent (`#38BDF8`) when no seed color override is active.
  static const int defaultAccentColorArgb = 0xFF38BDF8;

  final MethodChannel _channel;
  final Map<DateTime, List<Lesson>> _cachedLessonsByDate =
      <DateTime, List<Lesson>>{};
  bool? _cachedDemoMode;
  DateTime? _lastUpcomingFetchAt;
  bool? _lastUpcomingFetchDemo;
  Future<void>? _inFlightUpcomingFetch;
  bool _initialized = false;

  /// Increments whenever the native widget or Live Activity asks to open `Órarend`.
  final ValueNotifier<int> openTimetableSignal = ValueNotifier<int>(0);

  /// Binds incoming native-to-Flutter callbacks (e.g., notification tap on a
  /// warm instance opening `Órarend`). Safe to call repeatedly.
  void initialize() {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openTimetableTab') {
        openTimetableSignal.value++;
      }
    });
  }

  /// Resolves the active accent ARGB color aligned with Tinta Napló themes.
  static int resolveAccentColorArgb(
    UserProfilePrefs prefs, {
    Color? themePrimary,
  }) {
    if (prefs.uwuModeEnabled) return OledTheme.uwuPastelPink.toARGB32();
    if (themePrimary != null) return themePrimary.toARGB32();
    return prefs.seedColorValue;
  }

  int _cacheGeneration = 0;

  /// Clears in-memory lesson buckets (e.g. during logout or mode switch).
  void clearMemoryCache() {
    _cacheGeneration++;
    _cachedLessonsByDate.clear();
    _cachedDemoMode = null;
    _lastUpcomingFetchAt = null;
    _lastUpcomingFetchDemo = null;
    _inFlightUpcomingFetch = null;
  }

  /// Synchronizes [lessons] immediately into Android `"tinta_home_widget_prefs"`
  /// and broadcasts `ACTION_TINTA_LIVE_UPDATE`.
  Future<bool> syncFromLessons(
    List<Lesson> lessons, {
    required UserProfilePrefs prefs,
    Color? themeAccent,
    bool mergeWithExisting = true,
    DateTime? nowOverride,
  }) async {
    final now = (nowOverride ?? DateTime.now()).toLocal();
    final today = DateUtils.dateOnly(now);

    if (!mergeWithExisting ||
        (_cachedDemoMode != null && _cachedDemoMode != prefs.demoModeEnabled)) {
      _cachedLessonsByDate.clear();
    }
    _cachedDemoMode = prefs.demoModeEnabled;

    // Group incoming lessons by local calendar date and replace per-day buckets
    // cleanly so cancelled/rescheduled shifts overwrite stale slots on that day.
    final grouped = <DateTime, List<Lesson>>{};
    for (final lesson in lessons) {
      if (isInactivePlaceholderLesson(lesson)) continue;
      final day = DateUtils.dateOnly(lesson.start.toLocal());
      grouped.putIfAbsent(day, () => <Lesson>[]).add(lesson);
    }
    for (final entry in grouped.entries) {
      _cachedLessonsByDate[entry.key] = entry.value;
    }

    // Prune days outside `[today .. today + 10 days]`.
    final horizon = today.add(const Duration(days: 10));
    _cachedLessonsByDate.removeWhere(
      (date, _) => date.isBefore(today) || date.isAfter(horizon),
    );

    final consolidated = <Lesson>[];
    final sortedDays = _cachedLessonsByDate.keys.toList()..sort();
    for (final d in sortedDays) {
      consolidated.addAll(_cachedLessonsByDate[d]!);
    }

    final payload = buildTimetablePayload(
      consolidated,
      prefs: prefs,
      themeAccent: themeAccent,
      now: now,
    );
    return _pushTimetablePayload(payload);
  }

  /// Synchronizes immediately using [dashboard.todaysLessons], and asynchronously
  /// fetches today + next 7 days so the widget/Live Activity knows the next school
  /// day (even on Friday afternoon or Sunday evening).
  Future<void> syncFromDashboard({
    required DashboardData dashboard,
    required KretaClient kretaClient,
    required UserProfilePrefs prefs,
    Color? themeAccent,
    DateTime? nowOverride,
    bool forceUpcomingRefresh = false,
  }) async {
    final now = (nowOverride ?? DateTime.now()).toLocal();
    final isDemo =
        prefs.demoModeEnabled || DemoDataService.isDemoSession(dashboard.activeSession);

    await syncFromLessons(
      dashboard.todaysLessons,
      prefs: prefs,
      themeAccent: themeAccent,
      mergeWithExisting: _cachedDemoMode == isDemo,
      nowOverride: now,
    );

    final recentlyFetched = _lastUpcomingFetchAt != null &&
        _lastUpcomingFetchDemo == isDemo &&
        now.difference(_lastUpcomingFetchAt!).abs() <
            const Duration(minutes: 10);
    if (!forceUpcomingRefresh && recentlyFetched) {
      return;
    }

    if (_inFlightUpcomingFetch != null) {
      return;
    }

    final today = DateUtils.dateOnly(now);
    final futureEnd = today.add(const Duration(days: 7));
    final fetchGen = _cacheGeneration;
    late final Future<void> fetchFuture;
    fetchFuture = () async {
      try {
        // Skip background network fetch if session already requires re-auth
        // so widget prefetch never spams token refreshes or triggers auth errors.
        if (!isDemo && TokenStorageService.reauthRequiredNotifier.value != null) {
          return;
        }
        final rangeLessons = isDemo
            ? DemoDataService.instance.buildTimetableForRange(
                today,
                futureEnd,
                nowOverride: now,
              )
            : await kretaClient.fetchTimetableForRange(
                dashboard.activeSession,
                from: today,
                to: futureEnd,
              );
        // Abort if logout or demo toggle happened while in flight.
        if (_cacheGeneration != fetchGen) return;
        _lastUpcomingFetchAt = now;
        _lastUpcomingFetchDemo = isDemo;
        await syncFromLessons(
          rangeLessons,
          prefs: prefs,
          themeAccent: themeAccent,
          mergeWithExisting: true,
          nowOverride: now,
        );
      } catch (_) {
        // Non-critical background enrichment for next school day; keep today's data.
      } finally {
        if (identical(_inFlightUpcomingFetch, fetchFuture)) {
          _inFlightUpcomingFetch = null;
        }
      }
    }();
    _inFlightUpcomingFetch = fetchFuture;
  }

  /// Pushes updated theme/Live Activity prefs using already-cached lessons
  /// (and regenerates Demo lessons if Demó mód is active and cache is empty).
  Future<bool> syncPreferencesWithCachedLessons({
    required UserProfilePrefs prefs,
    Color? themeAccent,
    DateTime? nowOverride,
  }) async {
    final now = (nowOverride ?? DateTime.now()).toLocal();
    final today = DateUtils.dateOnly(now);
    if (prefs.demoModeEnabled &&
        (_cachedDemoMode != true || _cachedLessonsByDate.isEmpty)) {
      final demoRange = DemoDataService.instance.buildTimetableForRange(
        today,
        today.add(const Duration(days: 7)),
        nowOverride: now,
      );
      return syncFromLessons(
        demoRange,
        prefs: prefs,
        themeAccent: themeAccent,
        mergeWithExisting: false,
        nowOverride: now,
      );
    }

    final consolidated = <Lesson>[];
    final sortedDays = _cachedLessonsByDate.keys.toList()..sort();
    for (final d in sortedDays) {
      consolidated.addAll(_cachedLessonsByDate[d]!);
    }
    final payload = buildTimetablePayload(
      consolidated,
      prefs: prefs,
      themeAccent: themeAccent,
      now: now,
    );
    return _pushTimetablePayload(payload);
  }

  /// Builds the serialized JSON payload for Android `"tinta_home_widget_prefs"`.
  ///
  /// Includes today's lessons and the upcoming school day's lessons (up to 7 days
  /// ahead), preserving cancelled & substituted flags and custom subject renames.
  static Map<String, Object?> buildTimetablePayload(
    List<Lesson> lessons, {
    required UserProfilePrefs prefs,
    Color? themeAccent,
    DateTime? now,
  }) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final today = DateUtils.dateOnly(localNow);
    final accentArgb = resolveAccentColorArgb(prefs, themePrimary: themeAccent);

    final deduped = <String, Lesson>{};
    for (final lesson in lessons) {
      if (isInactivePlaceholderLesson(lesson)) continue;
      final startLocal = lesson.start.toLocal();
      final day = DateUtils.dateOnly(startLocal);
      if (day.isBefore(today)) continue;
      final key =
          '${day.toIso8601String()}_${lesson.uid}_${startLocal.millisecondsSinceEpoch}';
      deduped[key] = lesson;
    }

    final sorted = deduped.values.toList()
      ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));

    // Keep today's lessons + all lessons of the next school day (or up to 64 total
    // lessons across upcoming days so weekends and holiday gaps stay populated).
    DateTime? nextSchoolDay;
    for (final l in sorted) {
      final d = DateUtils.dateOnly(l.start.toLocal());
      if (d.isAfter(today)) {
        nextSchoolDay = d;
        break;
      }
    }

    final scoped = <Lesson>[];
    for (final l in sorted) {
      final d = DateUtils.dateOnly(l.start.toLocal());
      if (d == today ||
          (nextSchoolDay != null && d == nextSchoolDay) ||
          scoped.length < 36) {
        scoped.add(l);
      }
      if (scoped.length >= 80) break;
    }

    final serializedLessons = scoped
        .map((lesson) => serializeLesson(lesson, prefs: prefs))
        .toList(growable: false);

    return <String, Object?>{
      'updatedAtMs': localNow.millisecondsSinceEpoch,
      'accentColorArgb': accentArgb,
      'liveActivityEnabled': prefs.liveActivityEnabled,
      'hideCancelledLessons': prefs.hideCancelledLessons,
      'isDemoMode': prefs.demoModeEnabled,
      'lessons': serializedLessons,
    };
  }

  /// Serializes a single [Lesson] with resolved subject name and status flags.
  static Map<String, Object?> serializeLesson(
    Lesson lesson, {
    required UserProfilePrefs prefs,
  }) {
    final startLocal = lesson.start.toLocal();
    final endLocal = lesson.end.toLocal();
    final rawSubject = (lesson.subject?.name ?? lesson.name).trim();
    final subject =
        prefs.resolveSubjectName(rawSubject, lesson.subject?.uid).trim();
    final subTeacher =
        prefs.resolveTeacherName(lesson.substituteTeacher).trim();
    final teacher = prefs.resolveTeacherName(lesson.teacher).trim();
    final stateName = lesson.state.name.toLowerCase();
    final stateDesc = lesson.state.description.toLowerCase();
    final cancelled = isLessonCancelled(lesson);
    final substituted = !cancelled &&
        (subTeacher.isNotEmpty ||
            stateName.contains('helyettes') ||
            stateDesc.contains('helyettes'));
    final day = DateUtils.dateOnly(startLocal);
    final dateKey =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    return <String, Object?>{
      'uid': lesson.uid,
      'period': lesson.lessonNumber ?? 0,
      'subject': subject.isEmpty ? 'Óra' : subject,
      'room': lesson.roomName?.trim() ?? '',
      'teacher': substituted && subTeacher.isNotEmpty ? subTeacher : teacher,
      'originalTeacher': teacher,
      'substituteTeacher': subTeacher,
      'startMs': startLocal.millisecondsSinceEpoch,
      'endMs': endLocal.millisecondsSinceEpoch,
      'cancelled': cancelled,
      'substituted': substituted,
      'dateKey': dateKey,
    };
  }

  Future<bool> _pushTimetablePayload(Map<String, Object?> payload) async {
    if (kIsWeb) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'syncTimetableData',
        <String, Object?>{
          'timetableJson': jsonEncode(payload),
          'accentColorArgb': payload['accentColorArgb'],
          'liveActivityEnabled': payload['liveActivityEnabled'],
          'updatedAtMs': payload['updatedAtMs'],
        },
      );
      return ok ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Toggles `"Élő tevékenység (Now Bar)"`, requesting `POST_NOTIFICATIONS` on
  /// Android 13+ when turning ON, persisting `"live_activity_enabled"` in
  /// `"tinta_home_widget_prefs"`, and triggering `ACTION_TINTA_LIVE_UPDATE`.
  Future<bool> setLiveActivityEnabled(
    bool enabled, {
    bool requestPermissionIfNeeded = true,
  }) async {
    if (kIsWeb) return enabled;
    try {
      final result = await _channel.invokeMethod<bool>(
        'setLiveActivityEnabled',
        <String, Object?>{
          'enabled': enabled,
          'requestPermission': requestPermissionIfNeeded,
        },
      );
      return result ?? enabled;
    } on MissingPluginException {
      return enabled;
    } on PlatformException {
      return false;
    }
  }

  /// Triggers an immediate diagnostic refresh broadcast (`ACTION_TINTA_LIVE_UPDATE`).
  Future<bool> refreshLiveUpdateNow() async {
    if (kIsWeb) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('refreshLiveUpdateNow');
      return ok ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Checks whether the app may post Android 16+ promoted ongoing Live
  /// Updates / Samsung Now Bar notifications (`NotificationManager.canPostPromotedNotifications`).
  Future<bool> canPostPromotedNotifications() async {
    if (kIsWeb) return true;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'canPostPromotedNotifications',
      );
      return ok ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  /// Launches Android's per-app Live Notification / Now Bar promotion settings
  /// (`Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS`).
  Future<bool> openPromotedNotificationSettings() async {
    if (kIsWeb) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'openPromotedNotificationSettings',
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Checks whether the app was launched from a Home Widget or Live Activity
  /// notification to open the `Órarend` tab directly.
  Future<bool> consumePendingOpenTimetableTab() async {
    if (kIsWeb) return false;
    try {
      final pending = await _channel.invokeMethod<bool>(
        'consumePendingOpenTimetableTab',
      );
      return pending ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
