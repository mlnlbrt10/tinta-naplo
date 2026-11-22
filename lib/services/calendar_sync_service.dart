import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final int trackedEventCount;
  final DateTime? lastSyncAt;

  const CalendarSyncSettings({
    required this.enabled,
    required this.targetCalendarId,
    required this.targetCalendarName,
    required this.targetCalendarAccount,
    required this.contentMode,
    required this.trackedEventCount,
    required this.lastSyncAt,
  });
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
  final String itemType; // 'exam' or 'homework'
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;

  const _DesiredCalendarEvent({
    required this.uniqueKey,
    required this.itemType,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });

  String buildSignature(String calendarId) =>
      'v1|$calendarId|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}|$title|$description';
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

  Future<void> setTargetCalendar(DeviceCalendarInfo calendar) async {
    final prefs = await _prefsProvider();
    await prefs.setString(kCalendarSyncTargetIdKey, calendar.id);
    await prefs.setString(kCalendarSyncTargetNameKey, calendar.displayName);
    await prefs.setString(kCalendarSyncTargetAccountKey, calendar.accountName);
  }

  /// Checks whether both `READ_CALENDAR` and `WRITE_CALENDAR` are granted.
  Future<bool> hasCalendarPermissions() async {
    if (kIsWeb) return false;
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
    if (kIsWeb) return false;
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
    if (kIsWeb) return const [];
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
  }) async {
    final settings = await loadSettings();
    if (!settings.enabled) {
      return const CalendarSyncResult(performed: false);
    }
    return syncNow(dashboard: dashboard, profilePrefs: prefs);
  }

  /// Synchronizes future exams and homework items into the target Google
  /// Calendar according to the saved configuration, deduplicating via
  /// [SharedPreferences] and removing out-of-scope events when settings change.
  Future<CalendarSyncResult> syncNow({
    required DashboardData dashboard,
    UserProfilePrefs? profilePrefs,
  }) {
    final pending = _inFlightSync;
    if (pending != null) return pending;
    final future = _performSync(
      dashboard: dashboard,
      profilePrefs: profilePrefs,
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

    var skippedPastCount = 0;
    final desired = <String, _DesiredCalendarEvent>{};

    if (mode.includeExams) {
      for (final test in dashboard.tests) {
        final window = resolveExamWindow(test, dashboard.todaysLessons);
        if (window.start.isBefore(todayMidnight) ||
            !window.start.isAfter(localNow)) {
          skippedPastCount++;
          continue;
        }
        final subjectName = _resolveSubjectName(
          test.subjectName,
          test.subject.uid,
          profilePrefs,
          fallback: test.subject.name,
        );
        final tema = (test.theme ?? '').trim();
        final title = tema.isNotEmpty
            ? '[Dolgozat] $subjectName - $tema'
            : '[Számonkérés] $subjectName';
        final description = _buildExamDescription(
          test: test,
          profilePrefs: profilePrefs,
        );
        final key = test.uid.trim().isNotEmpty
            ? 'exam:${test.uid.trim()}'
            : 'exam:${window.start.millisecondsSinceEpoch}:$subjectName';
        desired[key] = _DesiredCalendarEvent(
          uniqueKey: key,
          itemType: 'exam',
          title: title,
          description: description,
          start: window.start,
          end: window.end,
        );
      }
    }

    if (mode.includeHomework) {
      for (final hw in dashboard.homeworks) {
        final window = resolveHomeworkWindow(hw);
        if (window.start.isBefore(todayMidnight) ||
            !window.start.isAfter(localNow)) {
          skippedPastCount++;
          continue;
        }
        final subjectName = _resolveSubjectName(
          hw.subjectName,
          hw.subject.uid,
          profilePrefs,
          fallback: hw.subject.name,
        );
        final cleanHwText = Homework.stripHtmlTags(hw.description).trim();
        final description =
            cleanHwText.isNotEmpty ? cleanHwText : 'Házi feladat ($subjectName)';
        final title = '[Házi] $subjectName';
        final key = hw.uid.trim().isNotEmpty
            ? 'hw:${hw.uid.trim()}'
            : 'hw:${window.start.millisecondsSinceEpoch}:$subjectName';
        desired[key] = _DesiredCalendarEvent(
          uniqueKey: key,
          itemType: 'homework',
          title: title,
          description: description,
          start: window.start,
          end: window.end,
        );
      }
    }

    final trackingMap = _readTrackingMap(storage);
    final updatedMap = Map<String, _TrackedCalendarRecord>.from(trackingMap);

    var createdCount = 0;
    var updatedCount = 0;
    var deletedCount = 0;
    var activeSyncedCount = 0;
    final nowMillis = localNow.millisecondsSinceEpoch;

    // 1. Clean up out-of-scope events (e.g., mode changed from both -> examsOnly),
    // events moved from a different calendar, or cancelled upcoming items.
    for (final entry in trackingMap.entries) {
      final key = entry.key;
      final existing = entry.value;
      final desiredItem = desired[key];
      final scopeExcluded = (existing.itemType == 'exam' && !mode.includeExams) ||
          (existing.itemType == 'homework' && !mode.includeHomework);
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

    // 2. Upsert desired upcoming items (create new or update changed content/date).
    for (final item in desired.values) {
      final signature = item.buildSignature(targetCal.id);
      final existing = updatedMap[item.uniqueKey];

      if (existing != null &&
          existing.calendarId == targetCal.id &&
          existing.signature == signature &&
          existing.eventId.isNotEmpty) {
        activeSyncedCount++;
        continue;
      }

      final existingEventId =
          (existing != null && existing.calendarId == targetCal.id)
              ? existing.eventId
              : null;

      final savedEventId = await _upsertEventNative(
        calendarId: targetCal.id,
        existingEventId: existingEventId,
        title: item.title,
        description: item.description,
        startMillis: item.start.millisecondsSinceEpoch,
        endMillis: item.end.millisecondsSinceEpoch,
        reminderMinutes: 60,
      );

      if (savedEventId != null && savedEventId.isNotEmpty) {
        if (existingEventId != null && savedEventId == existingEventId) {
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
    final trackingMap = _readTrackingMap(storage);
    if (trackingMap.isEmpty) return 0;
    final updatedMap = Map<String, _TrackedCalendarRecord>.from(trackingMap);
    var deletedCount = 0;
    for (final entry in trackingMap.entries) {
      final rec = entry.value;
      final scopeExcluded = (rec.itemType == 'exam' && !mode.includeExams) ||
          (rec.itemType == 'homework' && !mode.includeHomework);
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
    final eventIds = trackingMap.values
        .map((r) => r.eventId)
        .where((id) => id.isNotEmpty)
        .toList();

    var removedCount = 0;
    if (eventIds.isNotEmpty && !kIsWeb) {
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

  /// Resolves the start/end timestamp window for an exam, matching against the
  /// timetable lessons on the same day when available.
  static ({DateTime start, DateTime end}) resolveExamWindow(
    Test test,
    List<Lesson> lessons,
  ) {
    final testLocal = test.date.toLocal();
    for (final lesson in lessons) {
      final lessonStart = lesson.start.toLocal();
      final sameDay = lessonStart.year == testLocal.year &&
          lessonStart.month == testLocal.month &&
          lessonStart.day == testLocal.day;
      if (!sameDay) continue;
      final numberMatches =
          test.lessonNumber > 0 && lesson.lessonNumber == test.lessonNumber;
      final subjectMatches = test.subject.uid.isNotEmpty &&
          lesson.subject?.uid == test.subject.uid;
      if (numberMatches ||
          (test.lessonNumber <= 0 && subjectMatches)) {
        final end = lesson.end.toLocal().isAfter(lessonStart)
            ? lesson.end.toLocal()
            : lessonStart.add(const Duration(minutes: 45));
        return (start: lessonStart, end: end);
      }
    }

    if (testLocal.hour != 0 || testLocal.minute != 0 || testLocal.second != 0) {
      return (
        start: testLocal,
        end: testLocal.add(const Duration(minutes: 45)),
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
    return (start: start, end: start.add(const Duration(minutes: 45)));
  }

  /// Resolves the start/end timestamp window for a homework deadline.
  static ({DateTime start, DateTime end}) resolveHomeworkWindow(Homework hw) {
    final dueLocal = hw.dueDate.toLocal();
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

  String _buildExamDescription({
    required Test test,
    UserProfilePrefs? profilePrefs,
  }) {
    final lines = <String>[];
    final modeDesc = test.method.description.trim().isNotEmpty
        ? test.method.description.trim()
        : test.method.name.trim();
    if (modeDesc.isNotEmpty) {
      lines.add('Mód: $modeDesc');
    }
    final rawTeacher = test.teacherName.trim();
    final teacher = profilePrefs != null
        ? profilePrefs.resolveTeacherName(rawTeacher).trim()
        : rawTeacher;
    if (teacher.isNotEmpty) {
      lines.add('Tanár: $teacher');
    }
    final tema = (test.theme ?? '').trim();
    if (tema.isNotEmpty) {
      lines.add('Téma: $tema');
    }
    if (test.lessonNumber > 0) {
      lines.add('Óra: ${test.lessonNumber}. óra');
    }
    return lines.join('\n');
  }

  Future<String?> _upsertEventNative({
    required String calendarId,
    required String? existingEventId,
    required String title,
    required String description,
    required int startMillis,
    required int endMillis,
    int reminderMinutes = 60,
  }) async {
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
        },
      );
      return savedId?.toString();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<bool> _deleteEventNative(String eventId) async {
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
