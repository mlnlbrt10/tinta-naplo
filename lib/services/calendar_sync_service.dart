import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_support.dart';
import 'kreta_client.dart';
import 'token_storage_service.dart';

const String kCalendarSyncChannelName = 'tinta_naplo/calendar_sync';

const String kCalendarSyncEnabledKey = 'calendar_sync_enabled_v1';
const String kCalendarSyncTargetIdKey = 'calendar_sync_target_calendar_id_v1';
const String kCalendarSyncTargetNameKey =
    'calendar_sync_target_calendar_name_v1';
const String kCalendarSyncTargetAccountKey =
    'calendar_sync_target_calendar_account_v1';
const String kCalendarSyncContentModeKey = 'calendar_sync_content_mode_v1';
const String kCalendarSyncEventMapKey = 'calendar_sync_event_map_v1';
const String kCalendarSyncLastSyncAtKey = 'calendar_sync_last_sync_at_v1';
const String kCalendarSyncEventColorsKey = 'calendar_sync_event_colors_v1';
const String kCalendarSyncTimetableKey = 'calendar_sync_timetable_v1';
const String kCalendarSyncForceRecreateKey = 'calendar_sync_force_recreate_v1';
const String kCalendarSyncFormatVersionKey = 'calendar_sync_format_version_v1';
const int kCurrentCalendarSyncFormatVersion = 2;

/// Fallback Google Calendar palette colors (ARGB) used when native calendar
/// color query returns no entries (e.g. local calendars or tests).
const List<int> kDefaultCalendarColorPalette = <int>[
  0xFFD50000, // Tomato
  0xFFE67C73, // Flamingo
  0xFFF4511E, // Tangerine
  0xFFF6BF26, // Banana
  0xFF33B679, // Sage
  0xFF0B8043, // Basil
  0xFF039BE5, // Peacock
  0xFF3F51B5, // Blueberry
  0xFF7986CB, // Lavender
  0xFF8E24AA, // Grape
  0xFF616161, // Graphite
];

/// Customizable event categories for Calendar Sync event coloring.
enum CalendarEventColorCategory {
  dolgozat('Dolgozat', 0xFFD50000),
  feleles('Felelés', 0xFFF4511E),
  temazaro('Témazáró', 0xFF8E24AA),
  hazi('Házi feladat', 0xFF0B8043),
  orarend('Órarend', 0xFF039BE5);

  final String label;
  final int defaultArgb;
  const CalendarEventColorCategory(this.label, this.defaultArgb);

  static CalendarEventColorCategory? fromStorageKey(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final cat in CalendarEventColorCategory.values) {
      if (cat.name == raw) return cat;
    }
    return null;
  }
}

/// Native event color swatch offered by a device calendar provider.
class CalendarEventColorOption {
  final String colorKey;
  final int color;

  const CalendarEventColorOption({
    required this.colorKey,
    required this.color,
  });

  factory CalendarEventColorOption.fromMap(Map<Object?, Object?> map) {
    return CalendarEventColorOption(
      colorKey: (map['colorKey'] ?? '').toString(),
      color: (map['color'] as num?)?.toInt() ?? 0xFF039BE5,
    );
  }
}

/// Content scope options for native Google Calendar synchronization.
enum CalendarSyncContentMode {
  examsOnly('Csak számonkérések'),
  homeworkOnly('Csak házi feladatok'),
  both('Mindkettő');

  final String label;
  const CalendarSyncContentMode(this.label);

  bool get includeExams => this == examsOnly || this == both;
  bool get includeHomework => this == homeworkOnly || this == both;

  static CalendarSyncContentMode fromStorageKey(String? raw) {
    if (raw == null || raw.isEmpty) return CalendarSyncContentMode.both;
    return CalendarSyncContentMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => CalendarSyncContentMode.both,
    );
  }
}

/// Metadata describing a writable device calendar returned by `CalendarContract`.
class DeviceCalendarInfo {
  final String id;
  final String displayName;
  final String accountName;
  final String accountType;
  final String ownerAccount;
  final bool isGoogle;
  final bool isPrimary;
  final int color;
  final bool visible;

  const DeviceCalendarInfo({
    required this.id,
    required this.displayName,
    required this.accountName,
    required this.accountType,
    required this.ownerAccount,
    required this.isGoogle,
    required this.isPrimary,
    required this.color,
    required this.visible,
  });

  factory DeviceCalendarInfo.fromMap(Map<Object?, Object?> map) {
    return DeviceCalendarInfo(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      accountName: (map['accountName'] ?? '').toString(),
      accountType: (map['accountType'] ?? '').toString(),
      ownerAccount: (map['ownerAccount'] ?? '').toString(),
      isGoogle: map['isGoogle'] == true,
      isPrimary: map['isPrimary'] == true,
      color: (map['color'] as num?)?.toInt() ?? 0xFF4285F4,
      visible: map['visible'] != false,
    );
  }
}

/// Persisted calendar sync configuration snapshot.
class CalendarSyncSettings {
  final bool enabled;
  final String? targetCalendarId;
  final String? targetCalendarName;
  final String? targetCalendarAccount;
  final CalendarSyncContentMode contentMode;
  final bool syncTimetable;
  final Map<CalendarEventColorCategory, int> eventColors;
  final int trackedEventCount;
  final DateTime? lastSyncAt;

  const CalendarSyncSettings({
    required this.enabled,
    required this.targetCalendarId,
    required this.targetCalendarName,
    required this.targetCalendarAccount,
    required this.contentMode,
    this.syncTimetable = false,
    this.eventColors = const {},
    required this.trackedEventCount,
    required this.lastSyncAt,
  });

  int colorFor(CalendarEventColorCategory category) =>
      eventColors[category] ?? category.defaultArgb;
}

/// Outcome summary of one calendar sync run.
class CalendarSyncResult {
  final bool performed;
  final int syncedCount;
  final int createdCount;
  final int updatedCount;
  final int deletedCount;
  final int skippedPastCount;
  final String? errorMessage;

  const CalendarSyncResult({
    required this.performed,
    this.syncedCount = 0,
    this.createdCount = 0,
    this.updatedCount = 0,
    this.deletedCount = 0,
    this.skippedPastCount = 0,
    this.errorMessage,
  });
}

class _TrackedCalendarRecord {
  final String eventId;
  final String signature;
  final String itemType; // 'exam' or 'homework'
  final String calendarId;
  final int startMillis;

  const _TrackedCalendarRecord({
    required this.eventId,
    required this.signature,
    required this.itemType,
    required this.calendarId,
    required this.startMillis,
  });

  factory _TrackedCalendarRecord.fromJson(Map<String, dynamic> json) {
    return _TrackedCalendarRecord(
      eventId: (json['eventId'] ?? '').toString(),
      signature: (json['signature'] ?? '').toString(),
      itemType: (json['itemType'] ?? '').toString(),
      calendarId: (json['calendarId'] ?? '').toString(),
      startMillis: (json['startMillis'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'signature': signature,
        'itemType': itemType,
        'calendarId': calendarId,
        'startMillis': startMillis,
      };
}

class _DesiredCalendarEvent {
  final String uniqueKey;
  final String syncTag;
  final String itemType; // 'exam', 'homework', or 'lesson'
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;
  final int eventColor;

  const _DesiredCalendarEvent({
    required this.uniqueKey,
    required this.syncTag,
    required this.itemType,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
    required this.eventColor,
  });

  String buildSignature(String calendarId) =>
      'v2|$calendarId|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}|$title|$description|$eventColor';
}

/// Optional native Android `CalendarContract` synchronization service for
/// upcoming Kréta exams and homework deadlines.
class CalendarSyncService {
  static final CalendarSyncService instance = CalendarSyncService();

  static const MethodChannel _defaultChannel =
      MethodChannel(kCalendarSyncChannelName);

  final MethodChannel _channel;
  final Future<SharedPreferences> Function() _prefsProvider;
  final DateTime Function() _nowProvider;

  Future<CalendarSyncResult>? _inFlightSync;

  CalendarSyncService({
    MethodChannel? channel,
    Future<SharedPreferences> Function()? prefsProvider,
    DateTime Function()? nowProvider,
  })  : _channel = channel ?? _defaultChannel,
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
        _nowProvider = nowProvider ?? DateTime.now;

  /// Loads persisted settings and tracking count from [SharedPreferences].
  Future<CalendarSyncSettings> loadSettings() async {
    final prefs = await _prefsProvider();
    final eventMap = _readTrackingMap(prefs);
    final lastMillis = prefs.getInt(kCalendarSyncLastSyncAtKey);
    return CalendarSyncSettings(
      enabled: prefs.getBool(kCalendarSyncEnabledKey) ?? false,
      targetCalendarId: prefs.getString(kCalendarSyncTargetIdKey),
      targetCalendarName: prefs.getString(kCalendarSyncTargetNameKey),
      targetCalendarAccount: prefs.getString(kCalendarSyncTargetAccountKey),
      contentMode: CalendarSyncContentMode.fromStorageKey(
        prefs.getString(kCalendarSyncContentModeKey),
      ),
      syncTimetable: prefs.getBool(kCalendarSyncTimetableKey) ?? false,
      eventColors: _readEventColors(prefs),
      trackedEventCount: eventMap.length,
      lastSyncAt: lastMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(lastMillis)
          : null,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await _prefsProvider();
    await prefs.setBool(kCalendarSyncEnabledKey, enabled);
  }

  Future<void> setContentMode(CalendarSyncContentMode mode) async {
    final prefs = await _prefsProvider();
    await prefs.setString(kCalendarSyncContentModeKey, mode.name);
  }

  Future<void> setSyncTimetable(bool enabled) async {
    final prefs = await _prefsProvider();
    await prefs.setBool(kCalendarSyncTimetableKey, enabled);
  }

  Future<void> setCategoryColor(
    CalendarEventColorCategory category,
    int argb,
  ) async {
    final prefs = await _prefsProvider();
    final current = Map<CalendarEventColorCategory, int>.from(
      _readEventColors(prefs),
    );
    current[category] = argb;
    await _writeEventColors(prefs, current);
    await prefs.setBool(kCalendarSyncForceRecreateKey, true);
  }

  Future<void> resetEventColors() async {
    final prefs = await _prefsProvider();
    await prefs.remove(kCalendarSyncEventColorsKey);
    await prefs.setBool(kCalendarSyncForceRecreateKey, true);
  }

  /// Queries available native event colors for [calendarId], returning an
  /// empty list if unsupported or if permission is missing.
  Future<List<CalendarEventColorOption>> getCalendarEventColors(
    String calendarId,
  ) async {
    if (!isAndroidPlatform || calendarId.isEmpty) return const [];
    try {
      final rawList = await _channel.invokeListMethod<dynamic>(
        'getCalendarEventColors',
        <String, Object?>{'calendarId': calendarId},
      );
      if (rawList == null) return const [];
      return rawList
          .whereType<Map<Object?, Object?>>()
          .map(CalendarEventColorOption.fromMap)
          .where((o) => o.colorKey.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> setTargetCalendar(DeviceCalendarInfo calendar) async {
    final prefs = await _prefsProvider();
    await prefs.setString(kCalendarSyncTargetIdKey, calendar.id);
    await prefs.setString(kCalendarSyncTargetNameKey, calendar.displayName);
    await prefs.setString(kCalendarSyncTargetAccountKey, calendar.accountName);
  }

  /// Checks whether both `READ_CALENDAR` and `WRITE_CALENDAR` are granted.
  Future<bool> hasCalendarPermissions() async {
    if (!isAndroidPlatform) return false;
    try {
      final granted = await _channel.invokeMethod<bool>('hasCalendarPermissions');
      return granted == true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Requests Android runtime calendar permissions via the native bridge.
  Future<bool> requestCalendarPermissions() async {
    if (!isAndroidPlatform) return false;
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestCalendarPermissions');
      return granted == true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Queries writable device calendars (prioritizing Google accounts).
  Future<List<DeviceCalendarInfo>> getAvailableCalendars() async {
    if (!isAndroidPlatform) return const [];
    try {
      final rawList =
          await _channel.invokeListMethod<dynamic>('getAvailableCalendars');
      if (rawList == null) return const [];
      return rawList
          .whereType<Map<Object?, Object?>>()
          .map(DeviceCalendarInfo.fromMap)
          .where((cal) => cal.id.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Picks the best writable Google calendar when no calendar is saved yet, or
  /// verifies the currently saved calendar still exists on the device.
  Future<DeviceCalendarInfo?> ensureTargetCalendarSelected(
    List<DeviceCalendarInfo> calendars,
  ) async {
    if (calendars.isEmpty) return null;
    final settings = await loadSettings();
    final currentId = settings.targetCalendarId;
    if (currentId != null && currentId.isNotEmpty) {
      for (final c in calendars) {
        if (c.id == currentId) {
          if (c.displayName != settings.targetCalendarName ||
              c.accountName != settings.targetCalendarAccount) {
            await setTargetCalendar(c);
          }
          return c;
        }
      }
    }
    DeviceCalendarInfo? preferred;
    for (final c in calendars) {
      if (c.isGoogle) {
        preferred = c;
        break;
      }
    }
    preferred ??= calendars.first;
    await setTargetCalendar(preferred);
    return preferred;
  }

  /// Synchronizes upcoming items from [dashboard] automatically only when the
  /// feature is enabled and permissions remain granted.
  Future<CalendarSyncResult> syncFromDashboardIfEnabled(
    DashboardData dashboard, {
    UserProfilePrefs? prefs,
    List<Lesson>? timetableLessons,
    Future<List<Lesson>> Function(DateTime from, DateTime to)?
        fetchLessonsForRange,
  }) async {
    final settings = await loadSettings();
    if (!settings.enabled) {
      return const CalendarSyncResult(performed: false);
    }
    return syncNow(
      dashboard: dashboard,
      profilePrefs: prefs,
      timetableLessons: timetableLessons,
      fetchLessonsForRange: fetchLessonsForRange,
    );
  }

  /// Synchronizes future exams and homework items into the target Google
  /// Calendar according to the saved configuration, deduplicating via
  /// [SharedPreferences] and deleting/recreating events cleanly on color or
  /// format updates.
  Future<CalendarSyncResult> syncNow({
    required DashboardData dashboard,
    UserProfilePrefs? profilePrefs,
    List<Lesson>? timetableLessons,
    Future<List<Lesson>> Function(DateTime from, DateTime to)?
        fetchLessonsForRange,
  }) {
    final pending = _inFlightSync;
    if (pending != null) return pending;
    final future = _performSync(
      dashboard: dashboard,
      profilePrefs: profilePrefs,
      timetableLessons: timetableLessons,
      fetchLessonsForRange: fetchLessonsForRange,
    );
    _inFlightSync = future;
    future.whenComplete(() {
      if (identical(_inFlightSync, future)) {
        _inFlightSync = null;
      }
    });
    return future;
  }

  Future<CalendarSyncResult> _performSync({
    required DashboardData dashboard,
    UserProfilePrefs? profilePrefs,
    List<Lesson>? timetableLessons,
    Future<List<Lesson>> Function(DateTime from, DateTime to)?
        fetchLessonsForRange,
  }) async {
    if (kIsWeb) {
      return const CalendarSyncResult(
        performed: false,
        errorMessage: 'Weben a naptár szinkronizálás nem támogatott.',
      );
    }

    final storage = await _prefsProvider();
    final mode = CalendarSyncContentMode.fromStorageKey(
      storage.getString(kCalendarSyncContentModeKey),
    );
    final enabled = storage.getBool(kCalendarSyncEnabledKey) ?? false;
    if (!enabled) {
      return const CalendarSyncResult(performed: false);
    }
    final syncTimetable = storage.getBool(kCalendarSyncTimetableKey) ?? false;
    final eventColors = _readEventColors(storage);
    int resolveColor(CalendarEventColorCategory cat) =>
        eventColors[cat] ?? cat.defaultArgb;

    final hasPerm = await hasCalendarPermissions();
    if (!hasPerm) {
      return const CalendarSyncResult(
        performed: false,
        errorMessage: 'Hiányzik a naptár hozzáférési engedély.',
      );
    }

    final calendars = await getAvailableCalendars();
    final targetCal = await ensureTargetCalendarSelected(calendars);
    if (targetCal == null) {
      return const CalendarSyncResult(
        performed: false,
        errorMessage:
            'Nem található írható naptár ezen az eszközön.',
      );
    }

    final localNow = _nowProvider().toLocal();
    final todayMidnight =
        DateTime(localNow.year, localNow.month, localNow.day);

    // Build unified timetable lesson pool & fetch upcoming weeks' timetables
    // whenever any upcoming exam/homework date lacks matching Kréta lessons.
    final lessonsByKey = <String, Lesson>{};
    void ingestLessons(Iterable<Lesson> items) {
      for (final l in items) {
        final key = l.uid.trim().isNotEmpty
            ? l.uid.trim()
            : '${l.start.millisecondsSinceEpoch}:${l.lessonNumber}:${l.name}';
        lessonsByKey[key] = l;
      }
    }

    ingestLessons(dashboard.todaysLessons);
    if (timetableLessons != null) {
      ingestLessons(timetableLessons);
    }

    if (fetchLessonsForRange != null) {
      final daysWithLessons = <DateTime>{
        for (final l in lessonsByKey.values)
          DateTime(
            l.start.toLocal().year,
            l.start.toLocal().month,
            l.start.toLocal().day,
          ),
      };
      final neededDates = <DateTime>[];
      if (mode.includeExams) {
        for (final t in dashboard.tests) {
          final d = t.date.toLocal();
          final day = DateTime(d.year, d.month, d.day);
          if (!day.isBefore(todayMidnight) && !daysWithLessons.contains(day)) {
            neededDates.add(day);
          }
        }
      }
      if (mode.includeHomework) {
        for (final hw in dashboard.homeworks) {
          final d = hw.dueDate.toLocal();
          final day = DateTime(d.year, d.month, d.day);
          if (!day.isBefore(todayMidnight) && !daysWithLessons.contains(day)) {
            neededDates.add(day);
          }
        }
      }
      if (syncTimetable) {
        for (var offset = 1; offset <= 7; offset++) {
          final day = todayMidnight.add(Duration(days: offset));
          if (!daysWithLessons.contains(day)) {
            neededDates.add(day);
          }
        }
      }
      if (neededDates.isNotEmpty) {
        neededDates.sort();
        final rangeFrom = neededDates.first;
        final maxAllowed = todayMidnight.add(const Duration(days: 35));
        final rangeTo = neededDates.last.isAfter(maxAllowed)
            ? maxAllowed
            : neededDates.last;
        if (!rangeTo.isBefore(rangeFrom)) {
          try {
            final fetched = await fetchLessonsForRange(rangeFrom, rangeTo);
            ingestLessons(fetched);
          } catch (_) {
            // Fall back gracefully to already loaded lessons / bell schedule.
          }
        }
      }
    }
    final allLessons = lessonsByKey.values.toList();

    var skippedPastCount = 0;
    final desired = <String, _DesiredCalendarEvent>{};

    if (mode.includeExams) {
      for (final test in dashboard.tests) {
        final match = resolveExamLessonDetails(test, allLessons);
        if (match.start.isBefore(todayMidnight) ||
            !match.start.isAfter(localNow)) {
          skippedPastCount++;
          continue;
        }
        final fullSubject = _resolveSubjectName(
          test.subjectName,
          test.subject.uid,
          profilePrefs,
          fallback: test.subject.name,
        );
        final shortSubject = abbreviateSubjectName(fullSubject);
        final meta = resolveAssessmentMetadata(test);
        final title = '$shortSubject - ${meta.label}';
        final key = test.uid.trim().isNotEmpty
            ? 'exam:${test.uid.trim()}'
            : 'exam:${match.start.millisecondsSinceEpoch}:$shortSubject';
        final syncTag = buildSyncTag(key);
        final baseDescription = _buildExamDescription(
          test: test,
          fullSubjectName: fullSubject,
          assessmentLabel: meta.label,
          matchedLesson: match.matchedLesson,
          resolvedStart: match.start,
          resolvedEnd: match.end,
          profilePrefs: profilePrefs,
        );
        final description = baseDescription.isNotEmpty
            ? '$baseDescription\n$syncTag'
            : syncTag;
        desired[key] = _DesiredCalendarEvent(
          uniqueKey: key,
          syncTag: syncTag,
          itemType: 'exam',
          title: title,
          description: description,
          start: match.start,
          end: match.end,
          eventColor: resolveColor(meta.colorCategory),
        );
      }
    }

    if (mode.includeHomework) {
      for (final hw in dashboard.homeworks) {
        final window = resolveHomeworkWindow(hw, allLessons);
        if (window.start.isBefore(todayMidnight) ||
            !window.start.isAfter(localNow)) {
          skippedPastCount++;
          continue;
        }
        final fullSubject = _resolveSubjectName(
          hw.subjectName,
          hw.subject.uid,
          profilePrefs,
          fallback: hw.subject.name,
        );
        final shortSubject = abbreviateSubjectName(fullSubject);
        final key = hw.uid.trim().isNotEmpty
            ? 'hw:${hw.uid.trim()}'
            : 'hw:${window.start.millisecondsSinceEpoch}:$shortSubject';
        final syncTag = buildSyncTag(key);
        final baseDescription = _buildHomeworkDescription(
          hw: hw,
          fullSubjectName: fullSubject,
          profilePrefs: profilePrefs,
        );
        final description = baseDescription.isNotEmpty
            ? '$baseDescription\n$syncTag'
            : syncTag;
        final title = '$shortSubject - Házi feladat';
        desired[key] = _DesiredCalendarEvent(
          uniqueKey: key,
          syncTag: syncTag,
          itemType: 'homework',
          title: title,
          description: description,
          start: window.start,
          end: window.end,
          eventColor: resolveColor(CalendarEventColorCategory.hazi),
        );
      }
    }

    if (syncTimetable) {
      final lessonsForSync = allLessons.where((l) {
        final d = l.start.toLocal();
        return !d.isBefore(todayMidnight) && d.isAfter(localNow);
      }).toList();
      for (final lesson in lessonsForSync) {
        if (_isLessonCancelledOrInactive(lesson)) {
          continue;
        }
        final startLocal = lesson.start.toLocal();
        final endLocal = lesson.end.toLocal().isAfter(startLocal)
            ? lesson.end.toLocal()
            : startLocal.add(const Duration(minutes: 45));
        final fullSubject = _resolveSubjectName(
          lesson.subject?.name ?? lesson.name,
          lesson.subject?.uid ?? '',
          profilePrefs,
          fallback: lesson.name,
        );
        final shortSubject = abbreviateSubjectName(fullSubject);
        final key = lesson.uid.trim().isNotEmpty
            ? 'lesson:${lesson.uid.trim()}'
            : 'lesson:${startLocal.millisecondsSinceEpoch}:$shortSubject';
        final syncTag = buildSyncTag(key);
        final lines = <String>[
          'Tantárgy: $fullSubject',
          if (lesson.lessonNumber != null && lesson.lessonNumber! > 0)
            'Óra: ${lesson.lessonNumber}. óra (${_formatTime(startLocal)}–${_formatTime(endLocal)})',
          if ((lesson.roomName ?? '').trim().isNotEmpty)
            'Terem: ${lesson.roomName!.trim()}',
          if ((lesson.teacher ?? '').trim().isNotEmpty)
            'Tanár: ${profilePrefs != null ? profilePrefs.resolveTeacherName(lesson.teacher) : lesson.teacher!.trim()}',
          if ((lesson.theme ?? '').trim().isNotEmpty)
            'Téma: ${lesson.theme!.trim()}',
          syncTag,
        ];
        desired[key] = _DesiredCalendarEvent(
          uniqueKey: key,
          syncTag: syncTag,
          itemType: 'lesson',
          title: '$shortSubject - Tanóra',
          description: lines.join('\n'),
          start: startLocal,
          end: endLocal,
          eventColor: resolveColor(CalendarEventColorCategory.orarend),
        );
      }
    }

    final forceRecreate =
        (storage.getBool(kCalendarSyncForceRecreateKey) ?? false) ||
            (storage.getInt(kCalendarSyncFormatVersionKey) ?? 1) !=
                kCurrentCalendarSyncFormatVersion;

    final trackingMap = _readTrackingMap(storage);
    var updatedMap = Map<String, _TrackedCalendarRecord>.from(trackingMap);

    var createdCount = 0;
    var updatedCount = 0;
    var deletedCount = 0;
    var activeSyncedCount = 0;
    final nowMillis = localNow.millisecondsSinceEpoch;

    // Query native calendar for existing Tinta Napló events (prevents duplicates
    // on reinstall / prefs reset / force recreate on color change).
    final nativeIdsByTag = <String, List<String>>{};
    final nativeIdsByFingerprint = <String, List<String>>{};
    final knownNativeIds = <String>{};

    var queryFromMs = todayMidnight
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    var queryToMs =
        todayMidnight.add(const Duration(days: 90)).millisecondsSinceEpoch;
    for (final item in desired.values) {
      final s = item.start.millisecondsSinceEpoch - 86400000;
      final e = item.end.millisecondsSinceEpoch + 86400000;
      if (s < queryFromMs) queryFromMs = s;
      if (e > queryToMs) queryToMs = e;
    }

    final nativeEvents = await _findExistingEventsNative(
      targetCal.id,
      fromMillis: queryFromMs,
      toMillis: queryToMs,
    );
    if (nativeEvents != null) {
      for (final ev in nativeEvents) {
        final id = ev.eventId;
        if (id.isEmpty) continue;
        knownNativeIds.add(id);
        final tag = extractSyncTag(ev.description);
        if (tag != null) {
          nativeIdsByTag.putIfAbsent(tag, () => <String>[]).add(id);
        }
        final fp = _eventFingerprint(ev.title, ev.startMillis, ev.endMillis);
        nativeIdsByFingerprint.putIfAbsent(fp, () => <String>[]).add(id);
      }
    }

    final previouslyTrackedKeys = <String>{...trackingMap.keys};
    if (forceRecreate) {
      // Delete every previously app-synced event (both tracked IDs and any
      // native tagged events) cleanly before recreating with new colors/format.
      final toDelete = <String>{
        for (final rec in trackingMap.values)
          if (rec.eventId.isNotEmpty) rec.eventId,
        for (final ids in nativeIdsByTag.values) ...ids,
      };
      if (toDelete.isNotEmpty) {
        deletedCount += await _deleteEventsBatchNative(toDelete.toList());
      }
      updatedMap = <String, _TrackedCalendarRecord>{};
      nativeIdsByTag.clear();
      nativeIdsByFingerprint.clear();
      knownNativeIds.clear();
    } else {
      // 1. Clean up out-of-scope events (e.g., mode changed from both -> examsOnly),
      // events moved from a different calendar, or cancelled upcoming items.
      for (final entry in trackingMap.entries) {
        final key = entry.key;
        final existing = entry.value;
        final desiredItem = desired[key];
        final scopeExcluded =
            (existing.itemType == 'exam' && !mode.includeExams) ||
                (existing.itemType == 'homework' && !mode.includeHomework) ||
                (existing.itemType == 'lesson' && !syncTimetable);
        final calendarChanged =
            desiredItem != null && existing.calendarId != targetCal.id;
        final cancelledUpcoming =
            desiredItem == null && existing.startMillis > nowMillis;

        if (scopeExcluded || calendarChanged || cancelledUpcoming) {
          if (existing.eventId.isNotEmpty) {
            await _deleteEventNative(existing.eventId);
          }
          updatedMap.remove(key);
          deletedCount++;
        }
      }
    }

    // 3. Create or cleanly delete-and-recreate modified events.
    for (final item in desired.values) {
      final signature = item.buildSignature(targetCal.id);
      final existing = updatedMap[item.uniqueKey];
      final tagMatches = nativeIdsByTag[item.syncTag] ?? const <String>[];
      final fpMatches = nativeIdsByFingerprint[_eventFingerprint(
            item.title,
            item.start.millisecondsSinceEpoch,
            item.end.millisecondsSinceEpoch,
          )] ??
          const <String>[];

      final hasTrackedEvent = existing != null &&
          existing.calendarId == targetCal.id &&
          existing.eventId.isNotEmpty;
      final trackedStillExists = !hasTrackedEvent ||
          (nativeIdsByTag.isEmpty && knownNativeIds.isEmpty) ||
          knownNativeIds.contains(existing.eventId);

      if (!forceRecreate &&
          hasTrackedEvent &&
          trackedStillExists &&
          existing.signature == signature) {
        // Delete any stray extra copies even when primary event matches.
        if (tagMatches.length > 1) {
          for (final dupId in tagMatches) {
            if (dupId != existing.eventId) {
              await _deleteEventNative(dupId);
              deletedCount++;
            }
          }
        }
        activeSyncedCount++;
        continue;
      }

      // Whenever an event changed (color, title, notes, time), delete ALL
      // existing native copies first and recreate cleanly so Android Calendar
      // providers apply eventColor immediately with zero duplicates.
      final idsToRemove = <String>{
        if (hasTrackedEvent && trackedStillExists) existing.eventId,
        ...tagMatches,
        ...fpMatches,
      };
      final hadPriorNativeCopy =
          idsToRemove.isNotEmpty || previouslyTrackedKeys.contains(item.uniqueKey);
      for (final oldId in idsToRemove) {
        await _deleteEventNative(oldId);
      }

      final savedEventId = await _upsertEventNative(
        calendarId: targetCal.id,
        existingEventId: null,
        title: item.title,
        description: item.description,
        startMillis: item.start.millisecondsSinceEpoch,
        endMillis: item.end.millisecondsSinceEpoch,
        reminderMinutes: 60,
        syncTag: item.syncTag,
        eventColor: item.eventColor,
      );

      if (savedEventId != null && savedEventId.isNotEmpty) {
        if (hadPriorNativeCopy) {
          updatedCount++;
        } else {
          createdCount++;
        }
        activeSyncedCount++;
        updatedMap[item.uniqueKey] = _TrackedCalendarRecord(
          eventId: savedEventId,
          signature: signature,
          itemType: item.itemType,
          calendarId: targetCal.id,
          startMillis: item.start.millisecondsSinceEpoch,
        );
      }
    }

    await _writeTrackingMap(storage, updatedMap);
    await storage.setInt(
      kCalendarSyncFormatVersionKey,
      kCurrentCalendarSyncFormatVersion,
    );
    await storage.setBool(kCalendarSyncForceRecreateKey, false);
    await storage.setInt(
      kCalendarSyncLastSyncAtKey,
      localNow.millisecondsSinceEpoch,
    );

    return CalendarSyncResult(
      performed: true,
      syncedCount: activeSyncedCount,
      createdCount: createdCount,
      updatedCount: updatedCount,
      deletedCount: deletedCount,
      skippedPastCount: skippedPastCount,
    );
  }

  /// Removes any tracked events whose item type is no longer included in the
  /// active [CalendarSyncContentMode] without needing dashboard data.
  Future<int> cleanupOutOfScopeEvents() async {
    if (kIsWeb) return 0;
    final storage = await _prefsProvider();
    final mode = CalendarSyncContentMode.fromStorageKey(
      storage.getString(kCalendarSyncContentModeKey),
    );
    final syncTimetable = storage.getBool(kCalendarSyncTimetableKey) ?? false;
    final trackingMap = _readTrackingMap(storage);
    if (trackingMap.isEmpty) return 0;
    final updatedMap = Map<String, _TrackedCalendarRecord>.from(trackingMap);
    var deletedCount = 0;
    for (final entry in trackingMap.entries) {
      final rec = entry.value;
      final scopeExcluded = (rec.itemType == 'exam' && !mode.includeExams) ||
          (rec.itemType == 'homework' && !mode.includeHomework) ||
          (rec.itemType == 'lesson' && !syncTimetable);
      if (scopeExcluded) {
        if (rec.eventId.isNotEmpty) {
          await _deleteEventNative(rec.eventId);
        }
        updatedMap.remove(entry.key);
        deletedCount++;
      }
    }
    if (deletedCount > 0) {
      await _writeTrackingMap(storage, updatedMap);
    }
    return deletedCount;
  }

  /// Removes every event previously inserted by Tinta Napló from the native
  /// calendar provider and clears persisted deduplication tracking keys.
  Future<int> clearAllSyncedEvents() async {
    final storage = await _prefsProvider();
    final trackingMap = _readTrackingMap(storage);
    final eventIdSet = trackingMap.values
        .map((r) => r.eventId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final targetId = storage.getString(kCalendarSyncTargetIdKey);
    if (!kIsWeb && targetId != null && targetId.isNotEmpty) {
      final now = _nowProvider().toLocal();
      final nativeEvents = await _findExistingEventsNative(
        targetId,
        fromMillis: now
            .subtract(const Duration(days: 365))
            .millisecondsSinceEpoch,
        toMillis: now.add(const Duration(days: 730)).millisecondsSinceEpoch,
      );
      if (nativeEvents != null) {
        for (final ev in nativeEvents) {
          if (extractSyncTag(ev.description) != null && ev.eventId.isNotEmpty) {
            eventIdSet.add(ev.eventId);
          }
        }
      }
    }

    final eventIds = eventIdSet.toList();
    var removedCount = 0;
    if (eventIds.isNotEmpty && isAndroidPlatform) {
      try {
        final nativeCount = await _channel.invokeMethod<int>(
          'deleteEvents',
          <String, Object?>{'eventIds': eventIds},
        );
        removedCount = nativeCount ?? eventIds.length;
      } on MissingPluginException {
        removedCount = 0;
      } catch (_) {
        removedCount = 0;
      }
    }

    await storage.remove(kCalendarSyncEventMapKey);
    await storage.remove(kCalendarSyncLastSyncAtKey);
    return removedCount > 0 ? removedCount : eventIds.length;
  }

  /// Builds a deterministic metadata tag stored inside synced event descriptions
  /// so native events survive app reinstalls and remain deduplicated.
  static String buildSyncTag(String uniqueKey) => '[TintaID:$uniqueKey]';

  static final RegExp _syncTagRegex = RegExp(r'\[TintaID:[^\]]+\]');

  /// Extracts the `[TintaID:...]` marker from a synced event description.
  static String? extractSyncTag(String? description) {
    if (description == null || description.isEmpty) return null;
    return _syncTagRegex.firstMatch(description)?.group(0);
  }

  /// Cleanly abbreviates Hungarian school subject names for compact calendar
  /// event titles (e.g. `Magyar nyelv és irodalom` -> `Magyar`, `Matematika` -> `Matek`).
  static String abbreviateSubjectName(String rawSubject) {
    final trimmed = rawSubject.trim();
    if (trimmed.isEmpty) return 'Tantárgy';

    // Strip parenthetical qualifiers and trailing Roman/Arabic numerals.
    var cleaned = trimmed
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(
          RegExp(
            r'\s+(?:IX|IV|V?I{0,3}|X|VI{1,3}|[0-9]{1,2})\.?$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[\s\-–—.:]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) cleaned = trimmed;

    final norm = _foldDiacritics(cleaned.toLowerCase());

    const exactOrPrefix = <String, String>{
      'magyar nyelv es irodalom': 'Magyar',
      'magyar nyelv': 'Magyar',
      'magyar irodalom': 'Magyar',
      'magyar': 'Magyar',
      'irodalom': 'Magyar',
      'nyelvtan': 'Magyar',
      'matematika': 'Matek',
      'matek': 'Matek',
      'tortenelem es allampolgari ismeretek': 'Töri',
      'tortenelem': 'Töri',
      'tori': 'Töri',
      'testneveles es sport': 'Tesi',
      'mindennapos testneveles': 'Tesi',
      'testneveles': 'Tesi',
      'tesi': 'Tesi',
      'biologia-egeszsegtan': 'Biosz',
      'biologia': 'Biosz',
      'biosz': 'Biosz',
      'foldrajz': 'Föci',
      'foldunk es kornyezetunk': 'Föci',
      'foci': 'Föci',
      'digitalis kultura': 'Digikult',
      'informatika': 'Digikult',
      'szamitastechnika': 'Digikult',
      'osztalyfonoki': 'Ofő',
      'ofo': 'Ofő',
      'angol nyelv': 'Angol',
      'angol': 'Angol',
      'nemet nyelv': 'Német',
      'nemet': 'Német',
      'francia nyelv': 'Francia',
      'francia': 'Francia',
      'spanyol nyelv': 'Spanyol',
      'spanyol': 'Spanyol',
      'olasz nyelv': 'Olasz',
      'olasz': 'Olasz',
      'orosz nyelv': 'Orosz',
      'orosz': 'Orosz',
      'latin nyelv': 'Latin',
      'latin': 'Latin',
      'fizika': 'Fizika',
      'kemia': 'Kémia',
      'enek-zene': 'Ének',
      'enek zene': 'Ének',
      'enek': 'Ének',
      'vizualis kultura': 'Rajz',
      'rajz es vizualis kultura': 'Rajz',
      'rajz': 'Rajz',
      'allampolgari ismeretek': 'Állampolgári',
      'etika': 'Etika',
      'erkolcstan': 'Etika',
      'hit- es erkolcstan': 'Hittan',
      'hittan': 'Hittan',
      'penzugyi es vallalkozoi ismeretek': 'Pénzügy',
      'komplex termeszettudomany': 'Termtud',
      'termeszettudomany': 'Termtud',
      'termeszetismeret': 'Termtud',
      'technika es tervezes': 'Technika',
      'technika': 'Technika',
      'ikt projektmunka': 'IKT',
      'programozas alapjai': 'Prog',
      'szoftverfejlesztes': 'Prog',
      'adatbazis-kezeles': 'Adatbázis',
      'halozatok': 'Hálózatok',
    };

    if (exactOrPrefix.containsKey(norm)) {
      return exactOrPrefix[norm]!;
    }
    for (final entry in exactOrPrefix.entries) {
      if (norm.startsWith('${entry.key} ') ||
          norm.startsWith('${entry.key}-')) {
        return entry.value;
      }
    }

    // Clean fallback shortening: remove redundant trailing descriptor nouns.
    var fallback = cleaned
        .replaceAll(
          RegExp(
            r'\s+(?:nyelv|alapismeretek|ismeretek|alapjai|gyakorlat)$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (fallback.isEmpty) fallback = cleaned;
    return fallback[0].toUpperCase() + fallback.substring(1);
  }

  /// Resolves the actual Hungarian Kréta assessment type label and default color
  /// category without legacy uppercase brackets.
  static ({String label, String tag, CalendarEventColorCategory colorCategory})
      resolveAssessmentMetadata(Test test) {
    final desc = test.method.description.trim();
    final name = test.method.name.trim();
    final raw = desc.isNotEmpty ? desc : name;
    final norm = _foldDiacritics(raw.toLowerCase());

    if (norm.contains('temazaro') || norm.contains('tz')) {
      return (
        label: 'Témazáró',
        tag: '[TÉMAZÁRÓ]',
        colorCategory: CalendarEventColorCategory.temazaro,
      );
    }
    if (norm.contains('ropdolgozat') ||
        norm.contains('roplabda') ||
        norm.contains('ropi') ||
        norm.contains('szodolgozat')) {
      return (
        label: 'Röpdolgozat',
        tag: '[RÖPDOLGOZAT]',
        colorCategory: CalendarEventColorCategory.dolgozat,
      );
    }
    if (norm.contains('felel') || norm.contains('szobeli')) {
      return (
        label: 'Felelés',
        tag: '[FELELÉS]',
        colorCategory: CalendarEventColorCategory.feleles,
      );
    }
    if (norm.contains('kiseloadas') ||
        norm.contains('prezent') ||
        norm.contains('beszamolo')) {
      return (
        label: 'Kiselőadás',
        tag: '[KISELŐADÁS]',
        colorCategory: CalendarEventColorCategory.feleles,
      );
    }
    if (norm.contains('hazi dolgozat') || norm.contains('projekt')) {
      return (
        label: 'Házi dolgozat',
        tag: '[HÁZI DOLGOZAT]',
        colorCategory: CalendarEventColorCategory.dolgozat,
      );
    }
    if (norm.contains('gyakorlat') || norm.contains('labor')) {
      return (
        label: 'Gyakorlat',
        tag: '[GYAKORLAT]',
        colorCategory: CalendarEventColorCategory.dolgozat,
      );
    }
    if (norm.contains('dolgozat') ||
        norm.contains('irasbeli') ||
        norm.contains('teszt')) {
      return (
        label: 'Dolgozat',
        tag: '[DOLGOZAT]',
        colorCategory: CalendarEventColorCategory.dolgozat,
      );
    }
    if (raw.isNotEmpty &&
        norm != 'szamonkeres' &&
        norm != 'egyeb' &&
        norm != 'nincs') {
      final capitalized = raw[0].toUpperCase() + raw.substring(1);
      return (
        label: capitalized,
        tag: '[${raw.toUpperCase()}]',
        colorCategory: CalendarEventColorCategory.dolgozat,
      );
    }
    return (
      label: 'Számonkérés',
      tag: '[SZÁMONKÉRÉS]',
      colorCategory: CalendarEventColorCategory.dolgozat,
    );
  }

  static String _foldDiacritics(String input) {
    const map = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ö': 'o',
      'ő': 'o',
      'ú': 'u',
      'ü': 'u',
      'ű': 'u',
    };
    final sb = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  static String _eventFingerprint(String title, int startMillis, int endMillis) =>
      '${title.trim().toLowerCase()}|$startMillis|$endMillis';

  static bool _isLessonCancelledOrInactive(Lesson lesson) {
    final stateName = lesson.state.name.toLowerCase().trim();
    final stateDesc = lesson.state.description.toLowerCase().trim();
    return lesson.uid.startsWith('inactive_period_') ||
        stateName == 'elmaradt' ||
        stateName.contains('elmarad') ||
        stateDesc.contains('elmarad');
  }

  static bool _subjectsMatch(
    String nameA,
    String uidA,
    String nameB,
    String uidB,
  ) {
    final cleanUidA = uidA.trim();
    final cleanUidB = uidB.trim();
    if (cleanUidA.isNotEmpty && cleanUidB.isNotEmpty && cleanUidA == cleanUidB) {
      return true;
    }
    final normA = _foldDiacritics(nameA.trim().toLowerCase());
    final normB = _foldDiacritics(nameB.trim().toLowerCase());
    if (normA.isEmpty || normB.isEmpty) return false;
    if (normA == normB) return true;
    final shortA = _foldDiacritics(abbreviateSubjectName(nameA).toLowerCase());
    final shortB = _foldDiacritics(abbreviateSubjectName(nameB).toLowerCase());
    if (shortA.isNotEmpty && shortA == shortB) return true;
    return normA.contains(normB) || normB.contains(normA);
  }

  static List<List<Lesson>> _groupConsecutiveLessons(List<Lesson> lessons) {
    if (lessons.isEmpty) return const [];
    final sorted = List<Lesson>.from(lessons)
      ..sort((a, b) => a.start.compareTo(b.start));
    final blocks = <List<Lesson>>[<Lesson>[sorted.first]];
    for (var i = 1; i < sorted.length; i++) {
      final prev = blocks.last.last;
      final curr = sorted[i];
      final prevNum = prev.lessonNumber ?? -1;
      final currNum = curr.lessonNumber ?? -1;
      final consecutiveByNumber = prevNum > 0 && currNum == prevNum + 1;
      final gapMin = curr.start.toLocal().difference(prev.end.toLocal()).inMinutes;
      final consecutiveByTime = gapMin >= -5 && gapMin <= 25;
      if (consecutiveByNumber || consecutiveByTime) {
        blocks.last.add(curr);
      } else {
        blocks.add(<Lesson>[curr]);
      }
    }
    return blocks;
  }

  /// Resolves the exact start/end timestamp window and matched Kréta [Lesson]
  /// for an exam, matching against the student's actual timetable on that day
  /// (by period number + subject/abbreviated subject, handling double lessons,
  /// or falling back to bell-schedule inference across known lessons).
  static ({DateTime start, DateTime end, Lesson? matchedLesson})
      resolveExamLessonDetails(
    Test test,
    List<Lesson> lessons,
  ) {
    final testLocal = test.date.toLocal();
    final sameDayLessons = lessons.where((lesson) {
      if (_isLessonCancelledOrInactive(lesson)) return false;
      final s = lesson.start.toLocal();
      return s.year == testLocal.year &&
          s.month == testLocal.month &&
          s.day == testLocal.day;
    }).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final testSubjectName =
        test.subjectName.trim().isNotEmpty ? test.subjectName : test.subject.name;
    final subjectMatchesOnDay = sameDayLessons
        .where(
          (l) => _subjectsMatch(
            testSubjectName,
            test.subject.uid,
            l.subject?.name ?? l.name,
            l.subject?.uid ?? '',
          ),
        )
        .toList();

    // 1. Exact match by lessonNumber + subject on that day.
    Lesson? exactMatch;
    if (test.lessonNumber > 0) {
      for (final l in subjectMatchesOnDay) {
        if (l.lessonNumber == test.lessonNumber) {
          exactMatch = l;
          break;
        }
      }
      // Merge consecutive same-subject lessons (e.g. double math lesson) so the
      // exam block spans the full real start-to-end window.
      if (exactMatch != null) {
        final blocks = _groupConsecutiveLessons(subjectMatchesOnDay);
        final matchedBlock = blocks.firstWhere(
          (b) => b.any((l) => l.uid == exactMatch!.uid),
          orElse: () => <Lesson>[exactMatch!],
        );
        final s = matchedBlock.first.start.toLocal();
        final lastEnd = matchedBlock.last.end.toLocal();
        final e = lastEnd.isAfter(s)
            ? lastEnd
            : s.add(const Duration(minutes: 45));
        return (start: s, end: e, matchedLesson: exactMatch);
      }

      // 2. Period number match alone (when group/subject label differs slightly).
      for (final l in sameDayLessons) {
        if (l.lessonNumber == test.lessonNumber) {
          final s = l.start.toLocal();
          final e = l.end.toLocal().isAfter(s)
              ? l.end.toLocal()
              : s.add(const Duration(minutes: 45));
          return (start: s, end: e, matchedLesson: l);
        }
      }
    }

    // 3. Subject match on that day (handles missing/offset lessonNumber and
    // merges consecutive double lessons into a clean single start-to-end span).
    if (subjectMatchesOnDay.isNotEmpty) {
      final blocks = _groupConsecutiveLessons(subjectMatchesOnDay);
      final chosenBlock = blocks.first;
      final s = chosenBlock.first.start.toLocal();
      final lastEnd = chosenBlock.last.end.toLocal();
      final e = lastEnd.isAfter(s) ? lastEnd : s.add(const Duration(minutes: 45));
      return (start: s, end: e, matchedLesson: chosenBlock.first);
    }

    // 4. Infer school's real bell schedule for `test.lessonNumber` from any
    // other known timetable day when that exact day's timetable isn't loaded.
    if (test.lessonNumber > 0) {
      for (final l in lessons) {
        if (_isLessonCancelledOrInactive(l)) continue;
        if (l.lessonNumber == test.lessonNumber) {
          final refS = l.start.toLocal();
          final refE = l.end.toLocal();
          final durationMin =
              refE.isAfter(refS) ? refE.difference(refS).inMinutes : 45;
          final start = DateTime(
            testLocal.year,
            testLocal.month,
            testLocal.day,
            refS.hour,
            refS.minute,
          );
          return (
            start: start,
            end: start.add(Duration(minutes: durationMin.clamp(25, 120))),
            matchedLesson: null,
          );
        }
      }
    }

    if (testLocal.hour != 0 || testLocal.minute != 0 || testLocal.second != 0) {
      return (
        start: testLocal,
        end: testLocal.add(const Duration(minutes: 45)),
        matchedLesson: null,
      );
    }

    final slot = _defaultLessonSlot(test.lessonNumber);
    final start = DateTime(
      testLocal.year,
      testLocal.month,
      testLocal.day,
      slot.$1,
      slot.$2,
    );
    return (
      start: start,
      end: start.add(const Duration(minutes: 45)),
      matchedLesson: null,
    );
  }

  /// Resolves the start/end timestamp window for an exam, matching against the
  /// timetable lessons on the same day when available.
  static ({DateTime start, DateTime end}) resolveExamWindow(
    Test test,
    List<Lesson> lessons,
  ) {
    final res = resolveExamLessonDetails(test, lessons);
    return (start: res.start, end: res.end);
  }

  /// Resolves the start/end timestamp window for a homework deadline, matching
  /// against the student's actual timetable lesson for that subject on the due date.
  static ({DateTime start, DateTime end}) resolveHomeworkWindow(
    Homework hw, [
    List<Lesson> lessons = const [],
  ]) {
    final dueLocal = hw.dueDate.toLocal();
    if (lessons.isNotEmpty) {
      final hwSubjectName =
          hw.subjectName.trim().isNotEmpty ? hw.subjectName : hw.subject.name;
      final matchesOnDueDay = lessons.where((l) {
        if (_isLessonCancelledOrInactive(l)) return false;
        final s = l.start.toLocal();
        final sameDay = s.year == dueLocal.year &&
            s.month == dueLocal.month &&
            s.day == dueLocal.day;
        if (!sameDay) return false;
        return _subjectsMatch(
          hwSubjectName,
          hw.subject.uid,
          l.subject?.name ?? l.name,
          l.subject?.uid ?? '',
        );
      }).toList();
      if (matchesOnDueDay.isNotEmpty) {
        final blocks = _groupConsecutiveLessons(matchesOnDueDay);
        final block = blocks.first;
        final start = block.first.start.toLocal();
        final end = block.last.end.toLocal().isAfter(start)
            ? block.last.end.toLocal()
            : start.add(const Duration(minutes: 45));
        return (start: start, end: end);
      }
    }
    if (dueLocal.hour == 0 && dueLocal.minute == 0 && dueLocal.second == 0) {
      final start = DateTime(
        dueLocal.year,
        dueLocal.month,
        dueLocal.day,
        8,
        0,
      );
      return (start: start, end: start.add(const Duration(minutes: 30)));
    }
    return (
      start: dueLocal,
      end: dueLocal.add(const Duration(minutes: 30)),
    );
  }

  static (int, int) _defaultLessonSlot(int lessonNumber) {
    switch (lessonNumber) {
      case 1:
        return (8, 0);
      case 2:
        return (8, 55);
      case 3:
        return (9, 55);
      case 4:
        return (10, 50);
      case 5:
        return (11, 45);
      case 6:
        return (12, 45);
      case 7:
        return (13, 40);
      case 8:
        return (14, 35);
      default:
        return (8, 0);
    }
  }

  String _resolveSubjectName(
    String rawName,
    String subjectUid,
    UserProfilePrefs? profilePrefs, {
    String fallback = '',
  }) {
    final base = rawName.trim().isNotEmpty ? rawName.trim() : fallback.trim();
    if (profilePrefs != null) {
      final resolved = profilePrefs.resolveSubjectName(base, subjectUid).trim();
      if (resolved.isNotEmpty) return resolved;
    }
    return base.isNotEmpty ? base : 'Tantárgy';
  }

  static String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _buildExamDescription({
    required Test test,
    required String fullSubjectName,
    required String assessmentLabel,
    Lesson? matchedLesson,
    required DateTime resolvedStart,
    required DateTime resolvedEnd,
    UserProfilePrefs? profilePrefs,
  }) {
    final lines = <String>[];
    final tema = (test.theme ?? '').trim();
    if (tema.isNotEmpty) {
      lines.add('Téma: $tema');
    }
    lines.add('Tantárgy: $fullSubjectName');
    final modeDesc = test.method.description.trim().isNotEmpty
        ? test.method.description.trim()
        : test.method.name.trim();
    if (modeDesc.isNotEmpty &&
        modeDesc.toLowerCase() != assessmentLabel.toLowerCase()) {
      lines.add('Mód: $assessmentLabel ($modeDesc)');
    } else {
      lines.add('Mód: $assessmentLabel');
    }
    final rawTeacher = test.teacherName.trim().isNotEmpty
        ? test.teacherName.trim()
        : (matchedLesson?.teacher ?? '').trim();
    final teacher = profilePrefs != null
        ? profilePrefs.resolveTeacherName(rawTeacher).trim()
        : rawTeacher;
    if (teacher.isNotEmpty) {
      lines.add('Tanár: $teacher');
    }
    final room = (matchedLesson?.roomName ?? '').trim();
    if (room.isNotEmpty) {
      lines.add('Terem: $room');
    }
    final periodNum = test.lessonNumber > 0
        ? test.lessonNumber
        : matchedLesson?.lessonNumber;
    if (periodNum != null && periodNum > 0) {
      lines.add(
        'Óra: $periodNum. óra (${_formatTime(resolvedStart)}–${_formatTime(resolvedEnd)})',
      );
    } else {
      lines.add(
        'Időpont: ${_formatTime(resolvedStart)}–${_formatTime(resolvedEnd)}',
      );
    }
    return lines.join('\n');
  }

  String _buildHomeworkDescription({
    required Homework hw,
    required String fullSubjectName,
    UserProfilePrefs? profilePrefs,
  }) {
    final lines = <String>[];
    final cleanHwText = Homework.stripHtmlTags(hw.description).trim();
    if (cleanHwText.isNotEmpty) {
      lines.add(cleanHwText);
    }
    lines.add('Tantárgy: $fullSubjectName');
    final rawTeacher = hw.teacherName.trim();
    final teacher = profilePrefs != null
        ? profilePrefs.resolveTeacherName(rawTeacher).trim()
        : rawTeacher;
    if (teacher.isNotEmpty) {
      lines.add('Tanár: $teacher');
    }
    return lines.join('\n');
  }

  Future<int> _deleteEventsBatchNative(List<String> eventIds) async {
    if (eventIds.isEmpty || !isAndroidPlatform) return 0;
    try {
      final nativeCount = await _channel.invokeMethod<int>(
        'deleteEvents',
        <String, Object?>{'eventIds': eventIds},
      );
      return nativeCount ?? eventIds.length;
    } on MissingPluginException {
      return 0;
    } catch (_) {
      var removed = 0;
      for (final id in eventIds) {
        if (await _deleteEventNative(id)) removed++;
      }
      return removed;
    }
  }

  Future<List<_NativeCalendarEvent>?> _findExistingEventsNative(
    String calendarId, {
    required int fromMillis,
    required int toMillis,
  }) async {
    if (!isAndroidPlatform) return null;
    try {
      final raw = await _channel.invokeListMethod<dynamic>(
        'findExistingEvents',
        <String, Object?>{
          'calendarId': calendarId,
          'fromMillis': fromMillis,
          'toMillis': toMillis,
        },
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(_NativeCalendarEvent.fromMap)
          .where((e) => e.eventId.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _upsertEventNative({
    required String calendarId,
    required String? existingEventId,
    required String title,
    required String description,
    required int startMillis,
    required int endMillis,
    int reminderMinutes = 60,
    String? syncTag,
    int? eventColor,
  }) async {
    if (!isAndroidPlatform) return null;
    try {
      final savedId = await _channel.invokeMethod<dynamic>(
        'upsertEvent',
        <String, Object?>{
          'calendarId': calendarId,
          if (existingEventId != null && existingEventId.isNotEmpty)
            'eventId': existingEventId,
          'title': title,
          'description': description,
          'startMillis': startMillis,
          'endMillis': endMillis,
          'reminderMinutes': reminderMinutes,
          'allDay': false,
          if (syncTag != null && syncTag.isNotEmpty) 'syncTag': syncTag,
          if (eventColor != null) 'eventColor': eventColor,
        },
      );
      return savedId?.toString();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Map<CalendarEventColorCategory, int> _readEventColors(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(kCalendarSyncEventColorsKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <CalendarEventColorCategory, int>{};
      for (final entry in decoded.entries) {
        final cat = CalendarEventColorCategory.fromStorageKey(
          entry.key.toString(),
        );
        if (cat != null && entry.value is num) {
          result[cat] = (entry.value as num).toInt();
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _writeEventColors(
    SharedPreferences prefs,
    Map<CalendarEventColorCategory, int> colors,
  ) async {
    final payload = <String, int>{
      for (final entry in colors.entries) entry.key.name: entry.value,
    };
    await prefs.setString(kCalendarSyncEventColorsKey, jsonEncode(payload));
  }

  Future<bool> _deleteEventNative(String eventId) async {
    if (!isAndroidPlatform) return false;
    try {
      final removed = await _channel.invokeMethod<bool>(
        'deleteEvent',
        <String, Object?>{'eventId': eventId},
      );
      return removed == true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Map<String, _TrackedCalendarRecord> _readTrackingMap(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(kCalendarSyncEventMapKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      final result = <String, _TrackedCalendarRecord>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map) {
          result[entry.key] = _TrackedCalendarRecord.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _writeTrackingMap(
    SharedPreferences prefs,
    Map<String, _TrackedCalendarRecord> map,
  ) async {
    final jsonMap = <String, dynamic>{
      for (final entry in map.entries) entry.key: entry.value.toJson(),
    };
    await prefs.setString(kCalendarSyncEventMapKey, jsonEncode(jsonMap));
  }
}

class _NativeCalendarEvent {
  final String eventId;
  final String title;
  final String description;
  final int startMillis;
  final int endMillis;

  const _NativeCalendarEvent({
    required this.eventId,
    required this.title,
    required this.description,
    required this.startMillis,
    required this.endMillis,
  });

  factory _NativeCalendarEvent.fromMap(Map<Object?, Object?> map) {
    return _NativeCalendarEvent(
      eventId: (map['eventId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      startMillis: (map['startMillis'] as num?)?.toInt() ?? 0,
      endMillis: (map['endMillis'] as num?)?.toInt() ?? 0,
    );
  }
}
