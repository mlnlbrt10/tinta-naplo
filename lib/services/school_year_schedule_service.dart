import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/kreta_auth_config.dart';
import 'demo_data_service.dart';

const String kSchoolYearScheduleCachePrefix = 'school_year_schedule_cache_v2_';
const String kSchoolYearCustomUrlPrefix = 'school_year_custom_url_v1_';
const String kSchoolYearCustomEventsPrefix = 'school_year_custom_events_v1_';
const String kSchoolYearHiddenCategoriesPrefix =
    'school_year_hidden_categories_v1_';
const String kSchoolYearPinnedCountdownPrefix =
    'school_year_pinned_countdown_v1_';

/// Rich user-facing categories for `Tanév rendje` filtering and compact badges.
enum SchoolYearEventCategory {
  szunetek(
    label: 'Szünetek',
    shortLabel: 'Szünet',
    icon: Icons.beach_access_rounded,
    color: Color(0xFF10B981),
  ),
  munkanapAthelyezesek(
    label: 'Munkanap-áthelyezések',
    shortLabel: 'Áthelyezés',
    icon: Icons.swap_horiz_rounded,
    color: Color(0xFFF59E0B),
  ),
  vizsgakErettsegi(
    label: 'Vizsgák / Érettségi',
    shortLabel: 'Vizsga',
    icon: Icons.school_rounded,
    color: Color(0xFFEF4444),
  ),
  szuloiFogadoora(
    label: 'Szülői / Fogadóóra',
    shortLabel: 'Szülői',
    icon: Icons.people_alt_rounded,
    color: Color(0xFF8B5CF6),
  ),
  iskolaiProgramok(
    label: 'Iskolai programok',
    shortLabel: 'Program',
    icon: Icons.celebration_rounded,
    color: Color(0xFF06B6D4),
  ),
  tanitasNelkuliNapok(
    label: 'Tanítás nélküli napok',
    shortLabel: 'Tanítás nélkül',
    icon: Icons.event_busy_rounded,
    color: Color(0xFFF97316),
  ),
  egyeb(
    label: 'Egyéb',
    shortLabel: 'Egyéb',
    icon: Icons.event_note_rounded,
    color: Color(0xFF3B82F6),
  );

  final String label;
  final String shortLabel;
  final IconData icon;
  final Color color;

  const SchoolYearEventCategory({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.color,
  });

  static SchoolYearEventCategory? fromNameOrNull(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final c in values) {
      if (c.name == raw) return c;
    }
    return null;
  }
}

/// Origin of a calendar entry (`Országos tanév rendje`, `Iskolai program`, or `Saját esemény`).
enum SchoolYearEventSource {
  national(
    label: 'Országos tanév rendje',
    shortLabel: 'Országos',
    icon: Icons.public_rounded,
  ),
  school(
    label: 'Iskolai program',
    shortLabel: 'Iskolai',
    icon: Icons.school_rounded,
  ),
  custom(
    label: 'Saját esemény',
    shortLabel: 'Saját',
    icon: Icons.person_rounded,
  );

  final String label;
  final String shortLabel;
  final IconData icon;

  const SchoolYearEventSource({
    required this.label,
    required this.shortLabel,
    required this.icon,
  });

  static SchoolYearEventSource fromName(
    String? raw, {
    bool isCustomFallback = false,
  }) {
    if (isCustomFallback) return SchoolYearEventSource.custom;
    return values.firstWhere(
      (s) => s.name == raw,
      orElse: () => SchoolYearEventSource.national,
    );
  }
}

/// Classification of school year calendar entries (`Tanév rendje`).
enum SchoolYearEventType {
  schoolBreak(
    label: 'Szünet',
    icon: Icons.beach_access_rounded,
    color: Color(0xFF10B981),
  ),
  nationalHoliday(
    label: 'Ünnepnap',
    icon: Icons.flag_rounded,
    color: Color(0xFF3B82F6),
  ),
  workingSaturday(
    label: 'Ledolgozós szombat',
    icon: Icons.work_history_rounded,
    color: Color(0xFFF59E0B),
  ),
  specialDay(
    label: 'Különleges nap',
    icon: Icons.event_note_rounded,
    color: Color(0xFFA855F7),
  );

  final String label;
  final IconData icon;
  final Color color;

  const SchoolYearEventType({
    required this.label,
    required this.icon,
    required this.color,
  });

  static SchoolYearEventType fromName(String? raw) {
    return values.firstWhere(
      (t) => t.name == raw,
      orElse: () => SchoolYearEventType.specialDay,
    );
  }
}

/// Single break, national holiday, working Saturday, or school event in a school year.
class SchoolYearEvent {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final SchoolYearEventType type;
  final String? description;
  final bool isCustom;
  final SchoolYearEventSource source;
  final SchoolYearEventCategory? categoryOverride;

  const SchoolYearEvent({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.type,
    this.description,
    this.isCustom = false,
    this.source = SchoolYearEventSource.national,
    this.categoryOverride,
  });

  SchoolYearEventSource get effectiveSource =>
      isCustom ? SchoolYearEventSource.custom : source;

  SchoolYearEventCategory get category =>
      categoryOverride ??
      SchoolYearScheduleService.classifyEventCategory(
        title: title,
        subtitle: description,
        legacyType: type,
        source: effectiveSource,
      );

  bool get isSchoolSpecific =>
      effectiveSource == SchoolYearEventSource.school ||
      effectiveSource == SchoolYearEventSource.custom;

  String get sourceBadgeLabel => effectiveSource.label;

  bool isOngoingOn(DateTime date) {
    final d = DateUtils.dateOnly(date.toLocal());
    final s = DateUtils.dateOnly(startDate.toLocal());
    final e = DateUtils.dateOnly(endDate.toLocal());
    return !d.isBefore(s) && !d.isAfter(e);
  }

  bool isPastOn(DateTime date) {
    final d = DateUtils.dateOnly(date.toLocal());
    final e = DateUtils.dateOnly(endDate.toLocal());
    return d.isAfter(e);
  }

  int daysUntil(DateTime date) {
    final d = DateUtils.dateOnly(date.toLocal());
    final s = DateUtils.dateOnly(startDate.toLocal());
    return s.difference(d).inDays;
  }

  int daysRemaining(DateTime date) {
    final d = DateUtils.dateOnly(date.toLocal());
    final e = DateUtils.dateOnly(endDate.toLocal());
    return e.difference(d).inDays + 1;
  }

  int get durationDays =>
      DateUtils.dateOnly(endDate.toLocal())
          .difference(DateUtils.dateOnly(startDate.toLocal()))
          .inDays +
      1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startDate': DateUtils.dateOnly(startDate).toIso8601String(),
        'endDate': DateUtils.dateOnly(endDate).toIso8601String(),
        'type': type.name,
        if (categoryOverride != null) 'category': categoryOverride!.name,
        if (description != null && description!.isNotEmpty)
          'description': description,
        if (isCustom) 'isCustom': true,
        'source': effectiveSource.name,
      };

  factory SchoolYearEvent.fromJson(Map<String, dynamic> json) {
    final start = DateTime.tryParse(json['startDate']?.toString() ?? '') ??
        DateTime.now();
    final end =
        DateTime.tryParse(json['endDate']?.toString() ?? '') ?? start;
    final custom = json['isCustom'] == true;
    return SchoolYearEvent(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Esemény').toString(),
      startDate: DateUtils.dateOnly(start),
      endDate: DateUtils.dateOnly(end.isBefore(start) ? start : end),
      type: SchoolYearEventType.fromName(json['type']?.toString()),
      categoryOverride: SchoolYearEventCategory.fromNameOrNull(
        json['category']?.toString(),
      ),
      description: json['description']?.toString(),
      isCustom: custom,
      source: SchoolYearEventSource.fromName(
        json['source']?.toString(),
        isCustomFallback: custom,
      ),
    );
  }
}

/// Complete resolved school year calendar (`Tanév rendje`) for a student's school.
class SchoolYearSchedule {
  final String schoolYearLabel;
  final String? schoolName;
  final String? sourceUrl;
  final String? pdfUrl;
  final String? icsUrl;
  final String sourceLabel;
  final DateTime fetchedAt;
  final List<SchoolYearEvent> events;

  const SchoolYearSchedule({
    required this.schoolYearLabel,
    this.schoolName,
    this.sourceUrl,
    this.pdfUrl,
    this.icsUrl,
    required this.sourceLabel,
    required this.fetchedAt,
    required this.events,
  });

  int get schoolEventsCount =>
      events.where((e) => e.isSchoolSpecific).length;

  SchoolYearEvent? activeEventOn(DateTime now) {
    for (final e in events) {
      if (e.isOngoingOn(now)) return e;
    }
    return null;
  }

  SchoolYearEvent? nextUpcomingEvent(
    DateTime now, {
    bool preferBreakOrHoliday = true,
  }) {
    final d = DateUtils.dateOnly(now.toLocal());
    final upcoming = events
        .where((e) => !e.isPastOn(d) && DateUtils.dateOnly(e.startDate).isAfter(d))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (upcoming.isEmpty) return null;
    if (preferBreakOrHoliday) {
      for (final e in upcoming) {
        if (e.type == SchoolYearEventType.schoolBreak ||
            e.type == SchoolYearEventType.nationalHoliday) {
          return e;
        }
      }
    }
    return upcoming.first;
  }

  /// Fraction (`0.0..1.0`) of elapsed school year between Sept 1 and June 15.
  double schoolYearProgress(DateTime now) {
    final parts = schoolYearLabel.split('/');
    final startYear = int.tryParse(parts.first) ??
        (now.month >= 9 ? now.year : now.year - 1);
    final start = DateTime(startYear, 9, 1);
    final end = DateTime(startYear + 1, 6, 15);
    final d = DateUtils.dateOnly(now.toLocal());
    if (!d.isAfter(start)) return 0.0;
    if (!d.isBefore(end)) return 1.0;
    final total = end.difference(start).inDays;
    if (total <= 0) return 0.0;
    return (d.difference(start).inDays / total).clamp(0.0, 1.0);
  }

  SchoolYearSchedule copyWith({
    String? schoolYearLabel,
    String? schoolName,
    String? sourceUrl,
    String? pdfUrl,
    String? icsUrl,
    String? sourceLabel,
    DateTime? fetchedAt,
    List<SchoolYearEvent>? events,
  }) {
    return SchoolYearSchedule(
      schoolYearLabel: schoolYearLabel ?? this.schoolYearLabel,
      schoolName: schoolName ?? this.schoolName,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      icsUrl: icsUrl ?? this.icsUrl,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      events: events ?? this.events,
    );
  }

  Map<String, dynamic> toJson() => {
        'schoolYearLabel': schoolYearLabel,
        if (schoolName != null) 'schoolName': schoolName,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
        if (pdfUrl != null) 'pdfUrl': pdfUrl,
        if (icsUrl != null) 'icsUrl': icsUrl,
        'sourceLabel': sourceLabel,
        'fetchedAt': fetchedAt.toIso8601String(),
        'events': events.map((e) => e.toJson()).toList(),
      };

  factory SchoolYearSchedule.fromJson(Map<String, dynamic> json) {
    final rawEvents = json['events'];
    var list = <SchoolYearEvent>[];
    if (rawEvents is List) {
      for (final item in rawEvents) {
        if (item is Map) {
          list.add(SchoolYearEvent.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    list = SchoolYearScheduleService.mergeConsecutiveScheduleEvents(list);
    list.sort((a, b) => a.startDate.compareTo(b.startDate));
    return SchoolYearSchedule(
      schoolYearLabel: (json['schoolYearLabel'] ?? '').toString(),
      schoolName: json['schoolName']?.toString(),
      sourceUrl: json['sourceUrl']?.toString(),
      pdfUrl: json['pdfUrl']?.toString(),
      icsUrl: json['icsUrl']?.toString(),
      sourceLabel:
          (json['sourceLabel'] ?? 'Országos tanév rendje').toString(),
      fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
          DateTime.now(),
      events: list,
    );
  }
}

/// Auto-fetches and parses the school's official "Tanév rendje" calendar from
/// the school website (discovered via Kréta institution metadata or custom URL),
/// falling back cleanly to the official Hungarian national schedule.
class SchoolYearScheduleService {
  static final SchoolYearScheduleService instance = SchoolYearScheduleService();

  final http.Client _http;
  final bool _ownsClient;
  final Future<SharedPreferences> Function() _prefsProvider;
  final DateTime Function() _nowProvider;

  SchoolYearScheduleService({
    http.Client? httpClient,
    Future<SharedPreferences> Function()? prefsProvider,
    DateTime Function()? nowProvider,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
        _nowProvider = nowProvider ?? DateTime.now;

  void close() {
    if (_ownsClient) _http.close();
  }

  static int resolveSchoolYearStart(DateTime now) {
    final local = now.toLocal();
    return local.month >= 9 ? local.year : local.year - 1;
  }

  static String _scopeKey(String? instituteCode) {
    final clean = (instituteCode ?? '').trim().toLowerCase();
    return clean.isEmpty ? 'default' : clean;
  }

  Future<String?> loadCustomUrlOverride(String? instituteCode) async {
    try {
      final sp = await _prefsProvider();
      final val = sp.getString('$kSchoolYearCustomUrlPrefix${_scopeKey(instituteCode)}');
      return (val != null && val.trim().isNotEmpty) ? val.trim() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCustomUrlOverride(String? instituteCode, String? url) async {
    final sp = await _prefsProvider();
    final key = '$kSchoolYearCustomUrlPrefix${_scopeKey(instituteCode)}';
    if (url == null || url.trim().isEmpty) {
      await sp.remove(key);
    } else {
      await sp.setString(key, url.trim());
    }
  }

  Future<List<SchoolYearEvent>> loadCustomEvents(String? instituteCode) async {
    try {
      final sp = await _prefsProvider();
      final raw = sp.getString(
        '$kSchoolYearCustomEventsPrefix${_scopeKey(instituteCode)}',
      );
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => SchoolYearEvent.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveCustomEvents(
    String? instituteCode,
    List<SchoolYearEvent> events,
  ) async {
    final sp = await _prefsProvider();
    await sp.setString(
      '$kSchoolYearCustomEventsPrefix${_scopeKey(instituteCode)}',
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> addCustomEvent(
    String? instituteCode,
    SchoolYearEvent event,
  ) async {
    final current = List<SchoolYearEvent>.from(
      await loadCustomEvents(instituteCode),
    );
    current.removeWhere((e) => e.id == event.id);
      current.add(
      SchoolYearEvent(
        id: event.id,
        title: event.title,
        startDate: DateUtils.dateOnly(event.startDate),
        endDate: DateUtils.dateOnly(event.endDate),
        type: event.type,
        description: event.description,
        isCustom: true,
        source: SchoolYearEventSource.custom,
      ),
    );
    await _saveCustomEvents(instituteCode, current);
  }

  Future<void> removeCustomEvent(String? instituteCode, String eventId) async {
    final current = List<SchoolYearEvent>.from(
      await loadCustomEvents(instituteCode),
    )..removeWhere((e) => e.id == eventId);
    await _saveCustomEvents(instituteCode, current);
  }

  Future<void> resetOverrides(String? instituteCode) async {
    final sp = await _prefsProvider();
    final scope = _scopeKey(instituteCode);
    await sp.remove('$kSchoolYearCustomUrlPrefix$scope');
    await sp.remove('$kSchoolYearCustomEventsPrefix$scope');
    await sp.remove('$kSchoolYearScheduleCachePrefix$scope');
    await sp.remove('$kSchoolYearHiddenCategoriesPrefix$scope');
    await sp.remove('$kSchoolYearPinnedCountdownPrefix$scope');
  }

  Future<Set<SchoolYearEventCategory>> loadHiddenCategories(
    String? instituteCode,
  ) async {
    try {
      final sp = await _prefsProvider();
      final raw = sp.getStringList(
        '$kSchoolYearHiddenCategoriesPrefix${_scopeKey(instituteCode)}',
      );
      if (raw == null || raw.isEmpty) return <SchoolYearEventCategory>{};
      return raw
          .map(SchoolYearEventCategory.fromNameOrNull)
          .whereType<SchoolYearEventCategory>()
          .toSet();
    } catch (_) {
      return <SchoolYearEventCategory>{};
    }
  }

  Future<void> saveHiddenCategories(
    String? instituteCode,
    Set<SchoolYearEventCategory> hidden,
  ) async {
    final sp = await _prefsProvider();
    final key = '$kSchoolYearHiddenCategoriesPrefix${_scopeKey(instituteCode)}';
    if (hidden.isEmpty) {
      await sp.remove(key);
    } else {
      await sp.setStringList(key, hidden.map((c) => c.name).toList());
    }
  }

  Future<String?> loadPinnedCountdownEventId(String? instituteCode) async {
    try {
      final sp = await _prefsProvider();
      final val = sp.getString(
        '$kSchoolYearPinnedCountdownPrefix${_scopeKey(instituteCode)}',
      );
      if (val == null || val.trim().isEmpty || val == 'auto') return null;
      return val.trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> savePinnedCountdownEventId(
    String? instituteCode,
    String? eventId,
  ) async {
    final sp = await _prefsProvider();
    final key = '$kSchoolYearPinnedCountdownPrefix${_scopeKey(instituteCode)}';
    if (eventId == null || eventId.trim().isEmpty || eventId == 'auto') {
      await sp.remove(key);
    } else {
      await sp.setString(key, eventId.trim());
    }
  }

  /// Resolves the target countdown event for the Hero card / Profile tile:
  /// uses [pinnedEventId] if that event still exists and hasn't ended yet,
  /// otherwise falls back automatically to the closest active/upcoming event.
  SchoolYearEvent? resolveCountdownEvent(
    SchoolYearSchedule schedule,
    DateTime now, {
    String? pinnedEventId,
    Set<SchoolYearEventCategory> hiddenCategories = const {},
  }) {
    final d = DateUtils.dateOnly(now.toLocal());
    if (pinnedEventId != null && pinnedEventId.isNotEmpty) {
      for (final e in schedule.events) {
        if (e.id == pinnedEventId && !e.isPastOn(d)) {
          return e;
        }
      }
    }
    final active = schedule.activeEventOn(d);
    if (active != null && !hiddenCategories.contains(active.category)) {
      return active;
    }
    final visibleUpcoming = schedule.events
        .where(
          (e) =>
              !e.isPastOn(d) &&
              DateUtils.dateOnly(e.startDate).isAfter(d) &&
              !hiddenCategories.contains(e.category),
        )
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (visibleUpcoming.isNotEmpty) {
      for (final e in visibleUpcoming) {
        if (e.category == SchoolYearEventCategory.szunetek ||
            e.type == SchoolYearEventType.schoolBreak ||
            e.type == SchoolYearEventType.nationalHoliday) {
          return e;
        }
      }
      return visibleUpcoming.first;
    }
    return schedule.activeEventOn(d) ?? schedule.nextUpcomingEvent(d);
  }

  /// Heuristic / NLP-style classifier mapping any event title & subtitle into
  /// one of the 7 curated categories.
  static SchoolYearEventCategory classifyEventCategory({
    required String title,
    String? subtitle,
    SchoolYearEventType? legacyType,
    SchoolYearEventSource? source,
  }) {
    final combined = _normalizeHu('$title ${subtitle ?? ''}');

    if (combined.contains('igazgatoi szunet') ||
        combined.contains('tanitas nelkul') ||
        combined.contains('nevelesi ertekezlet') ||
        combined.contains('tantestuleti ertekezlet') ||
        combined.contains('palyaorientacio') ||
        combined.contains('digitalis temahet') ||
        combined.contains('fenntarthatosagi temahet') ||
        combined.contains('penz7') ||
        combined.contains('projektnap') ||
        combined.contains('munkaertekelo')) {
      return SchoolYearEventCategory.tanitasNelkuliNapok;
    }

    if (combined.contains('erettsegi') ||
        combined.contains('vizsga') ||
        combined.contains('felveteli') ||
        combined.contains('kompetenciameres') ||
        combined.contains('orszagos meres') ||
        combined.contains('osztalyozo') ||
        combined.contains('javito') ||
        combined.contains('potvizsga') ||
        combined.contains('agazati alapvizsga') ||
        combined.contains('szakmai') && combined.contains('meres')) {
      return SchoolYearEventCategory.vizsgakErettsegi;
    }

    if (combined.contains('szuloi') ||
        combined.contains('fogadoora') ||
        combined.contains('fogado ora') ||
        combined.contains('nyilt nap') ||
        combined.contains('beiratkozas')) {
      return SchoolYearEventCategory.szuloiFogadoora;
    }

    if (combined.contains('munkanap-athelyez') ||
        combined.contains('munkanap athelyez') ||
        combined.contains('athelyezett') ||
        combined.contains('ledolgoz') ||
        combined.contains('szombati munkanap') ||
        combined.contains('szombati tanitas') ||
        combined.contains('pihenonap') ||
        legacyType == SchoolYearEventType.workingSaturday) {
      return SchoolYearEventCategory.munkanapAthelyezesek;
    }

    if (combined.contains('szunet') ||
        combined.contains('vakacio') ||
        legacyType == SchoolYearEventType.schoolBreak) {
      return SchoolYearEventCategory.szunetek;
    }

    if (combined.contains('elso tanitasi nap') ||
        combined.contains('utolso tanitasi nap') ||
        combined.contains('elso felev vege') ||
        combined.contains('felev zarasa') ||
        combined.contains('nemzeti unnep') ||
        combined.contains('mindenszentek') ||
        combined.contains('punkosd') ||
        combined.contains('munka unnepe') ||
        combined.contains('marcius 15') ||
        combined.contains('oktober 23') ||
        legacyType == SchoolYearEventType.nationalHoliday) {
      return SchoolYearEventCategory.egyeb;
    }

    const programKeywords = [
      'szalagavato',
      'ballagas',
      'diaknap',
      'sportnap',
      'golyatabor',
      'golyaavato',
      'golyabal',
      'kirandulas',
      'erdei iskola',
      'unnepely',
      'unnepseg',
      'megemlekezes',
      'farsang',
      'mikulas',
      'karacsony',
      'adventi',
      'vasar',
      'veradas',
      'fotozas',
      'koncert',
      'kiallitas',
      'szinhaz',
      'verseny',
      'vetelkedo',
      'egeszsegnap',
      'projekthet',
      'temahet',
      'tematikus',
      'program',
      'neumann',
    ];
    for (final kw in programKeywords) {
      if (combined.contains(kw)) {
        return SchoolYearEventCategory.iskolaiProgramok;
      }
    }

    if (source == SchoolYearEventSource.school) {
      return SchoolYearEventCategory.iskolaiProgramok;
    }
    return SchoolYearEventCategory.egyeb;
  }

  /// Filters out useless scraped HTML headers, navigation menus, contact lines,
  /// legal footers, and noisy boilerplate prose that frequently appear on school
  /// calendar web pages.
  static bool isNoiseOrBoilerplateTitle(String rawTitle, {String? rawLine}) {
    final trimmed = rawTitle.trim();
    if (trimmed.length < 3 || trimmed.length > 96) return true;
    final letterMatches =
        RegExp(r'[a-zA-ZáéíóöőúüűÁÉÍÓÖŐÚÜŰ]').allMatches(trimmed).length;
    if (letterMatches < 3) return true;
    if (RegExp(r'^[\d\.\-\–—\/\s:]+$').hasMatch(trimmed)) return true;

    final norm = _normalizeHu(trimmed);
    const junkTokens = [
      'http://',
      'https://',
      'www.',
      '@',
      'impresszum',
      'adatvedelmi',
      'adatvedelem',
      'adatkezelesi',
      'adatkezeles',
      'tajekoztato',
      'cookie',
      'sutik',
      'minden jog fenntartva',
      'copyright',
      'telefon:',
      'tel.:',
      'tel:',
      'fax:',
      'e-mail',
      'email',
      'om azonosito',
      'om:',
      'adoszam',
      'kozzeteteli lista',
      'kozerdeku adat',
      'oldal tetejere',
      'ugras a tartalomra',
      'belepes',
      'regisztracio',
      'kattintson ide',
      'tovabb olvasom',
      'reszletek itt',
      'dokumentumtar',
      'nyomtatas',
      'megosztas',
      'frissitve:',
      'utoljara frissitve',
      'szerkesztette:',
      'felelos:',
      'kormanyrendelet',
      'bm rendelet',
      'rendelete a',
    ];
    for (final junk in junkTokens) {
      if (norm.contains(junk)) return true;
    }

    const exactTableHeaders = {
      'datum',
      'idopont',
      'esemeny',
      'program',
      'megnevezes',
      'tanev rendje',
      'a tanev rendje',
      'felelos',
      'megjegyzes',
      'helyszin',
      'erintettek',
      'letoltes',
    };
    if (exactTableHeaders.contains(norm)) return true;

    // Multi-sentence prose snippets scraped from paragraphs are not compact event titles.
    final sentenceCount = '.!?'.split('').fold<int>(
          0,
          (sum, ch) => sum + trimmed.split(ch).length - 1,
        );
    if (trimmed.length > 68 && sentenceCount >= 2) return true;

    return false;
  }

  /// Immediately returns cached schedule (with custom events) or national fallback
  /// without performing network requests — ideal for Profile menu previews.
  Future<SchoolYearSchedule> loadCachedOrFallback({
    Student? student,
    String? instituteCode,
    DateTime? nowOverride,
  }) async {
    final now = nowOverride ?? _nowProvider();
    final startYear = resolveSchoolYearStart(now);
    final label = '$startYear/${startYear + 1}';
    final resolvedCode =
        (instituteCode ?? student?.instituteCode ?? '').trim();
    final scope = _scopeKey(resolvedCode);
    final customEvents = await loadCustomEvents(scope);

    try {
      final sp = await _prefsProvider();
      final raw = sp.getString('$kSchoolYearScheduleCachePrefix$scope');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final cached =
              SchoolYearSchedule.fromJson(Map<String, dynamic>.from(decoded));
          if (cached.schoolYearLabel == label && cached.events.isNotEmpty) {
            return _mergeWithCustomEvents(cached, customEvents);
          }
        }
      }
    } catch (_) {}

    final base = resolvedCode == DemoDataService.demoInstituteCode
        ? _buildDemoSchoolSchedule(
            startYear,
            schoolName: student?.instituteName ??
                'BMSZC Neumann János Informatikai Technikum',
            fetchedAt: now,
          )
        : buildNationalHungarianSchedule(
            startYear,
            schoolName: student?.instituteName,
            fetchedAt: now,
          );
    return _mergeWithCustomEvents(base, customEvents);
  }

  /// Fetches the school's official "Tanév rendje" from its website (discovered
  /// via Kréta institution API / modules, DuckDuckGo search, or [customUrlOverride])
  /// and caches it locally per school, merging school events with national dates.
  Future<SchoolYearSchedule> fetchSchedule({
    Student? student,
    String? instituteCode,
    String? customUrlOverride,
    bool forceRefresh = false,
    DateTime? nowOverride,
  }) async {
    final now = nowOverride ?? _nowProvider();
    final startYear = resolveSchoolYearStart(now);
    final label = '$startYear/${startYear + 1}';
    final resolvedCode =
        (instituteCode ?? student?.instituteCode ?? '').trim();
    final scope = _scopeKey(resolvedCode);
    final customEvents = await loadCustomEvents(scope);

    if (!forceRefresh) {
      try {
        final sp = await _prefsProvider();
        final raw = sp.getString('$kSchoolYearScheduleCachePrefix$scope');
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final cached = SchoolYearSchedule.fromJson(
              Map<String, dynamic>.from(decoded),
            );
            final age = now.difference(cached.fetchedAt);
            if (cached.schoolYearLabel == label &&
                cached.events.isNotEmpty &&
                age < const Duration(days: 7)) {
              return _mergeWithCustomEvents(cached, customEvents);
            }
          }
        }
      } catch (_) {}
    }

    final savedCustomUrl = (customUrlOverride != null &&
            customUrlOverride.trim().isNotEmpty)
        ? customUrlOverride.trim()
        : await loadCustomUrlOverride(scope);

    var resolvedSchoolName = (student?.instituteName ?? '').trim();
    String? candidateWebsite = savedCustomUrl;

    if (candidateWebsite == null || candidateWebsite.isEmpty) {
      final discovered = await _discoverSchoolWebsite(
        student: student,
        instituteCode: resolvedCode,
      );
      candidateWebsite = discovered.websiteUrl;
      if (resolvedSchoolName.isEmpty && discovered.resolvedSchoolName != null) {
        resolvedSchoolName = discovered.resolvedSchoolName!;
      }
    }

    SchoolYearSchedule? parsedFromSite;
    if (candidateWebsite != null && candidateWebsite.isNotEmpty) {
      parsedFromSite = await _tryFetchAndParseWebsite(
        baseUrl: candidateWebsite,
        startYear: startYear,
        schoolName: resolvedSchoolName.isNotEmpty ? resolvedSchoolName : null,
        now: now,
      );
    }

    final SchoolYearSchedule baseSchedule;
    if (parsedFromSite != null) {
      baseSchedule = parsedFromSite;
    } else if (resolvedCode == DemoDataService.demoInstituteCode &&
        (savedCustomUrl == null || savedCustomUrl.isEmpty)) {
      baseSchedule = _buildDemoSchoolSchedule(
        startYear,
        schoolName: resolvedSchoolName.isNotEmpty
            ? resolvedSchoolName
            : 'BMSZC Neumann János Informatikai Technikum',
        fetchedAt: now,
      );
    } else {
      baseSchedule = buildNationalHungarianSchedule(
        startYear,
        schoolName: resolvedSchoolName.isNotEmpty ? resolvedSchoolName : null,
        sourceUrl: candidateWebsite,
        fetchedAt: now,
      );
    }

    try {
      final sp = await _prefsProvider();
      await sp.setString(
        '$kSchoolYearScheduleCachePrefix$scope',
        jsonEncode(baseSchedule.toJson()),
      );
    } catch (_) {}

    return _mergeWithCustomEvents(baseSchedule, customEvents);
  }

  SchoolYearSchedule _mergeWithCustomEvents(
    SchoolYearSchedule base,
    List<SchoolYearEvent> customEvents,
  ) {
    final cleanedBase = mergeConsecutiveScheduleEvents(
      base.events
          .where(
            (e) =>
                e.effectiveSource == SchoolYearEventSource.national ||
                e.isCustom ||
                !isNoiseOrBoilerplateTitle(e.title),
          )
          .toList(),
    );
    if (customEvents.isEmpty && cleanedBase.length == base.events.length) {
      var changed = false;
      for (int i = 0; i < cleanedBase.length; i++) {
        if (cleanedBase[i].startDate != base.events[i].startDate ||
            cleanedBase[i].endDate != base.events[i].endDate ||
            cleanedBase[i].id != base.events[i].id) {
          changed = true;
          break;
        }
      }
      if (!changed) return base;
    }
    final byId = <String, SchoolYearEvent>{
      for (final e in cleanedBase) e.id: e,
    };
    for (final c in customEvents) {
      byId[c.id] = c;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return base.copyWith(events: merged);
  }

  SchoolYearSchedule _buildDemoSchoolSchedule(
    int startYear, {
    required String schoolName,
    required DateTime fetchedAt,
  }) {
    final nextYear = startYear + 1;
    final demoSchoolEvents = <SchoolYearEvent>[
      SchoolYearEvent(
        id: 'demo_school_parents_$startYear',
        title: 'Őszi szülői értekezlet és fogadóóra',
        startDate: DateTime(startYear, 11, 18),
        endDate: DateTime(startYear, 11, 18),
        type: SchoolYearEventType.specialDay,
        description: 'Tanévközi tájékoztató és egyéni fogadóórák 17:00-tól.',
        source: SchoolYearEventSource.school,
      ),
      SchoolYearEvent(
        id: 'demo_school_openday_$startYear',
        title: 'Nyílt nap a 8. osztályosoknak',
        startDate: DateTime(startYear, 11, 26),
        endDate: DateTime(startYear, 11, 26),
        type: SchoolYearEventType.specialDay,
        description: 'Bemutató órák, szakmai laborlátogatások és tájékoztató.',
        source: SchoolYearEventSource.school,
      ),
      SchoolYearEvent(
        id: 'demo_school_szalagavato_$nextYear',
        title: 'Szalagavató ünnepség',
        startDate: DateTime(nextYear, 1, 30),
        endDate: DateTime(nextYear, 1, 30),
        type: SchoolYearEventType.specialDay,
        description: 'Végzős évfolyam szalagavató bálja és ünnepi műsora.',
        source: SchoolYearEventSource.school,
      ),
      SchoolYearEvent(
        id: 'demo_school_neumann_$nextYear',
        title: 'Neumann Napok & Projekthét',
        startDate: DateTime(nextYear, 3, 2),
        endDate: DateTime(nextYear, 3, 4),
        type: SchoolYearEventType.specialDay,
        description: 'Iskolai tematikus napok, versenyek és IT projektbemutatók.',
        source: SchoolYearEventSource.school,
      ),
      SchoolYearEvent(
        id: 'demo_school_digital_$nextYear',
        title: 'Digitális Témahét és Pályaorientációs nap',
        startDate: DateTime(nextYear, 4, 15),
        endDate: DateTime(nextYear, 4, 16),
        type: SchoolYearEventType.specialDay,
        description: 'Tanítás nélküli tematikus munkanap és szakmai előadások.',
        source: SchoolYearEventSource.school,
      ),
      SchoolYearEvent(
        id: 'demo_school_ballagas_$nextYear',
        title: 'Ballagás',
        startDate: DateTime(nextYear, 4, 30),
        endDate: DateTime(nextYear, 4, 30),
        type: SchoolYearEventType.specialDay,
        description: 'A végzős osztályok ünnepélyes búcsúztatása.',
        source: SchoolYearEventSource.school,
      ),
    ];
    return _buildWebsiteSchedule(
      startYear: startYear,
      schoolName: schoolName,
      sourceUrl: 'https://www.njszki.hu/tanev-rendje',
      sourceLabel: 'Iskolai honlap',
      parsedEvents: demoSchoolEvents,
      fetchedAt: fetchedAt,
    );
  }

  Future<({String? websiteUrl, String? resolvedSchoolName})>
      _discoverSchoolWebsite({
    Student? student,
    required String instituteCode,
  }) async {
    // 1. Inspect institution system modules for an external non-kreta school URL.
    if (student != null) {
      for (final mod in student.institution.systemModuleList) {
        final raw = mod.url?.trim() ?? '';
        if (_isValidSchoolWebsiteCandidate(raw)) {
          return (websiteUrl: raw, resolvedSchoolName: student.instituteName);
        }
      }
    }

    var discoveredName = (student?.instituteName ?? '').trim();

    // 2. Query Kréta institute selector API using institute code and/or name.
    final queries = <String>{
      if (instituteCode.isNotEmpty) instituteCode,
      if (discoveredName.isNotEmpty) discoveredName,
    };
    for (final query in queries) {
      try {
        final url =
            '${KretaAuthConfig.idpBaseUrl}/instituteSelector/${Uri.encodeComponent(query)}?showOnlyLive=true';
        final resp = await _http
            .get(
              Uri.parse(url),
              headers: {'User-Agent': KretaAuthConfig.userAgent},
            )
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
          if (decoded is List) {
            for (final item in decoded) {
              if (item is! Map) continue;
              final code = (item['instituteCode'] ?? item['azonosito'] ?? '')
                  .toString()
                  .trim();
              if (instituteCode.isNotEmpty &&
                  code.isNotEmpty &&
                  code.toLowerCase() != instituteCode.toLowerCase()) {
                continue;
              }
              if (discoveredName.isEmpty) {
                for (final nk in const ['name', 'nev', 'instituteName']) {
                  final candidateName = item[nk]?.toString().trim() ?? '';
                  if (candidateName.isNotEmpty) {
                    discoveredName = candidateName;
                    break;
                  }
                }
              }
              for (final key in const [
                'website',
                'webUrl',
                'url',
                'honlap',
                'homepage',
                'intezmenyHonlap',
              ]) {
                final raw = item[key]?.toString().trim() ?? '';
                if (_isValidSchoolWebsiteCandidate(raw)) {
                  return (
                    websiteUrl: raw,
                    resolvedSchoolName:
                        discoveredName.isNotEmpty ? discoveredName : null,
                  );
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. Lightweight public search fallback via DuckDuckGo HTML if Kréta has no website URL.
    if (discoveredName.isNotEmpty) {
      final searchedUrl = await _searchSchoolWebsiteViaDuckDuckGo(discoveredName);
      if (searchedUrl != null) {
        return (
          websiteUrl: searchedUrl,
          resolvedSchoolName: discoveredName,
        );
      }
    }

    return (
      websiteUrl: null,
      resolvedSchoolName: discoveredName.isNotEmpty ? discoveredName : null,
    );
  }

  static bool _isValidSchoolWebsiteCandidate(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return false;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    const blockedDomains = [
      'e-kreta.hu',
      'kreta.hu',
      'duckduckgo.com',
      'google.',
      'bing.com',
      'yahoo.com',
      'facebook.com',
      'fb.com',
      'instagram.com',
      'youtube.com',
      'tiktok.com',
      'wikipedia.org',
      'oktatas.hu',
      'kir.hu',
      'eduline.hu',
    ];
    for (final blocked in blockedDomains) {
      if (host.contains(blocked)) return false;
    }
    return true;
  }

  Future<String?> _searchSchoolWebsiteViaDuckDuckGo(String schoolName) async {
    try {
      final query = '$schoolName tanév rendje hivatalos honlap';
      final searchUri = Uri.parse(
        'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}',
      );
      final resp = await _http
          .get(
            searchUri,
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126.0 Mobile Safari/537.36',
              'Accept-Language': 'hu-HU,hu;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final html = _decodeHtmlBytes(resp.bodyBytes);

      final candidates = <String>[];
      final uddgMatches =
          RegExp(r'uddg=([^&"\x27>]+)', caseSensitive: false).allMatches(html);
      for (final m in uddgMatches) {
        final raw = Uri.decodeFull(m.group(1) ?? '');
        if (_isValidSchoolWebsiteCandidate(raw)) {
          candidates.add(raw);
        }
      }

      final directMatches = RegExp(
        r'''href\s*=\s*["'](https?://[^"']+)["']''',
        caseSensitive: false,
      ).allMatches(html);
      for (final m in directMatches) {
        final raw = (m.group(1) ?? '').trim();
        if (_isValidSchoolWebsiteCandidate(raw)) {
          candidates.add(raw);
        }
      }

      if (candidates.isEmpty) return null;

      // Prefer .hu school pages or pages explicitly mentioning tanev/munkaterv.
      candidates.sort((a, b) {
        int score(String u) {
          final lower = _normalizeHu(u);
          var s = 0;
          if (lower.endsWith('.hu') || lower.contains('.hu/')) s += 4;
          if (lower.contains('tanev') ||
              lower.contains('munkaterv') ||
              lower.contains('naptar') ||
              lower.contains('esemeny')) {
            s += 5;
          }
          if (lower.endsWith('.pdf')) s += 2;
          return s;
        }

        return score(b).compareTo(score(a));
      });
      return candidates.first;
    } catch (_) {
      return null;
    }
  }

  Future<SchoolYearSchedule?> _tryFetchAndParseWebsite({
    required String baseUrl,
    required int startYear,
    String? schoolName,
    required DateTime now,
  }) async {
    final normalizedUri = Uri.tryParse(
      baseUrl.startsWith('http') ? baseUrl : 'https://$baseUrl',
    );
    if (normalizedUri == null) return null;

    final lowerBase = normalizedUri.toString().toLowerCase();
    if (lowerBase.endsWith('.ics') || lowerBase.contains('basic.ics')) {
      final icsSchedule = await _tryFetchIcsUri(
        icsUri: normalizedUri,
        startYear: startYear,
        schoolName: schoolName,
        now: now,
      );
      if (icsSchedule != null) return icsSchedule;
    }

    if (lowerBase.endsWith('.pdf')) {
      final pdfSchedule = await _tryFetchPdfUri(
        pdfUri: normalizedUri,
        startYear: startYear,
        schoolName: schoolName,
        pageUrl: normalizedUri.toString(),
        now: now,
      );
      if (pdfSchedule != null) return pdfSchedule;
    }

    final scoredCandidates = <({Uri uri, int score})>[];
    final seenUrls = <String>{normalizedUri.toString()};
    final icsCandidates = <Uri>[];
    final pdfCandidates = <Uri>[];

    String? bestPageUrl;
    var bestEvents = const <SchoolYearEvent>[];
    String? discoveredIcsUrl;
    String? discoveredPdfUrl;

    try {
      final homeResp = await _http
          .get(normalizedUri)
          .timeout(const Duration(seconds: 6));
      if (homeResp.statusCode == 200) {
        final contentType =
            (homeResp.headers['content-type'] ?? '').toLowerCase();
        if (contentType.contains('pdf')) {
          final pdfSchedule = _buildPdfFallbackSchedule(
            pdfBytes: homeResp.bodyBytes,
            pdfUri: normalizedUri,
            pageUrl: normalizedUri.toString(),
            startYear: startYear,
            schoolName: schoolName,
            now: now,
          );
          return pdfSchedule;
        }
        if (contentType.contains('calendar') ||
            contentType.contains('ics')) {
          final icsEvents = parseScheduleFromIcs(
            _decodeHtmlBytes(homeResp.bodyBytes),
            startYear,
          );
          if (icsEvents.isNotEmpty) {
            return _buildWebsiteSchedule(
              startYear: startYear,
              schoolName: schoolName,
              sourceUrl: normalizedUri.toString(),
              icsUrl: normalizedUri.toString(),
              sourceLabel: 'Iskolai naptár (.ics)',
              parsedEvents: icsEvents,
              fetchedAt: now,
            );
          }
        }

        final body = _decodeHtmlBytes(homeResp.bodyBytes);
        _collectLinksFromHtml(
          html: body,
          baseUri: normalizedUri,
          seenUrls: seenUrls,
          scoredHtmlCandidates: scoredCandidates,
          icsCandidates: icsCandidates,
          pdfCandidates: pdfCandidates,
        );

        final directEvents = parseScheduleFromHtml(body, startYear);
        final hasRichEvents = directEvents.length >= 2 ||
            directEvents.any((e) => e.isSchoolSpecific);
        if (hasRichEvents) {
          bestPageUrl = normalizedUri.toString();
          bestEvents = directEvents;
        }
      }
    } catch (_) {}

    // Prefer direct iCalendar feeds if present on the starting page.
    for (final icsUri in icsCandidates.take(2)) {
      final icsSchedule = await _tryFetchIcsUri(
        icsUri: icsUri,
        startYear: startYear,
        schoolName: schoolName,
        pageUrl: normalizedUri.toString(),
        now: now,
      );
      if (icsSchedule != null && icsSchedule.schoolEventsCount > 0) {
        return icsSchedule;
      }
    }

    // Add standard Hungarian school CMS slugs for site root / fallback crawling.
    if (bestEvents.isEmpty) {
      for (final slug in const [
        '/tanev-rendje',
        '/a-tanev-rendje',
        '/tanev_rendje',
        '/munkaterv',
        '/esemenynaptar',
        '/programok',
        '/naptar',
      ]) {
        final probe = normalizedUri.resolve(slug);
        if (seenUrls.add(probe.toString())) {
          scoredCandidates.add((uri: probe, score: 3));
        }
      }
    }

    scoredCandidates.sort((a, b) => b.score.compareTo(a.score));

    // Crawl top subpage candidates unless we already got rich events & links.
    if (bestEvents.length < 3) {
      for (final candidate in scoredCandidates.take(6)) {
        try {
          final resp = await _http
              .get(candidate.uri)
              .timeout(const Duration(seconds: 6));
          if (resp.statusCode != 200) continue;
          final cType = (resp.headers['content-type'] ?? '').toLowerCase();
          if (cType.contains('pdf') ||
              candidate.uri.toString().toLowerCase().endsWith('.pdf')) {
            discoveredPdfUrl ??= candidate.uri.toString();
            final extracted = extractEventsFromPdfBytes(resp.bodyBytes, startYear);
            if (extracted.length > bestEvents.length) {
              bestEvents = extracted;
              bestPageUrl = candidate.uri.toString();
            }
            continue;
          }
          final html = _decodeHtmlBytes(resp.bodyBytes);
          _collectLinksFromHtml(
            html: html,
            baseUri: candidate.uri,
            seenUrls: seenUrls,
            scoredHtmlCandidates: const [],
            icsCandidates: icsCandidates,
            pdfCandidates: pdfCandidates,
            collectHtmlLinks: false,
          );
          final parsed = parseScheduleFromHtml(html, startYear);
          final better = parsed.length > bestEvents.length ||
              (parsed.isNotEmpty && bestEvents.isEmpty);
          if (better) {
            bestEvents = parsed;
            bestPageUrl = candidate.uri.toString();
          }
          if (parsed.length >= 4) break;
        } catch (_) {}
      }
    }

    // Check any newly found .ics links from crawled subpages.
    for (final icsUri in icsCandidates.take(3)) {
      discoveredIcsUrl ??= icsUri.toString();
      final icsSchedule = await _tryFetchIcsUri(
        icsUri: icsUri,
        startYear: startYear,
        schoolName: schoolName,
        pageUrl: bestPageUrl ?? normalizedUri.toString(),
        pdfUrl: discoveredPdfUrl ??
            (pdfCandidates.isNotEmpty ? pdfCandidates.first.toString() : null),
        now: now,
      );
      if (icsSchedule != null &&
          icsSchedule.events.length > bestEvents.length) {
        return icsSchedule;
      }
    }

    // Check any discovered PDF links on the page or subpages.
    if (discoveredPdfUrl == null && pdfCandidates.isNotEmpty) {
      discoveredPdfUrl = pdfCandidates.first.toString();
    }
    if (discoveredPdfUrl != null && bestEvents.length < 4) {
      final pdfSchedule = await _tryFetchPdfUri(
        pdfUri: Uri.parse(discoveredPdfUrl),
        startYear: startYear,
        schoolName: schoolName,
        pageUrl: bestPageUrl ?? normalizedUri.toString(),
        existingEvents: bestEvents,
        now: now,
      );
      if (pdfSchedule != null) return pdfSchedule;
    }

    if (bestEvents.length >= 2 ||
        bestEvents.any((e) => e.isSchoolSpecific) ||
        discoveredPdfUrl != null) {
      return _buildWebsiteSchedule(
        startYear: startYear,
        schoolName: schoolName,
        sourceUrl: bestPageUrl ?? discoveredPdfUrl ?? normalizedUri.toString(),
        pdfUrl: discoveredPdfUrl,
        icsUrl: discoveredIcsUrl,
        sourceLabel:
            discoveredPdfUrl != null && bestEvents.isEmpty
                ? 'Iskolai PDF dokumentum'
                : 'Iskolai honlap',
        parsedEvents: bestEvents,
        fetchedAt: now,
      );
    }

    return null;
  }

  void _collectLinksFromHtml({
    required String html,
    required Uri baseUri,
    required Set<String> seenUrls,
    required List<({Uri uri, int score})> scoredHtmlCandidates,
    required List<Uri> icsCandidates,
    required List<Uri> pdfCandidates,
    bool collectHtmlLinks = true,
  }) {
    // 1. Anchors: <a href="...">label</a>
    final anchorRegex = RegExp(
      r'''<a[^>]+href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    );
    for (final m in anchorRegex.allMatches(html)) {
      final href = (m.group(1) ?? '').trim();
      if (href.isEmpty ||
          href.startsWith('#') ||
          href.startsWith('mailto:') ||
          href.startsWith('javascript:')) {
        continue;
      }
      final label = _normalizeHu(
        (m.group(2) ?? '').replaceAll(RegExp(r'<[^>]+>'), ' '),
      );
      final lowerHref = _normalizeHu(href);
      final combined = '$lowerHref $label';

      final Uri resolved;
      try {
        resolved = baseUri.resolve(href);
      } catch (_) {
        continue;
      }

      if (lowerHref.endsWith('.ics') || lowerHref.contains('.ics?')) {
        if (!icsCandidates.contains(resolved)) {
          icsCandidates.add(resolved);
        }
        continue;
      }
      if (lowerHref.endsWith('.pdf') || lowerHref.contains('.pdf?')) {
        if (combined.contains('tanev') ||
            combined.contains('munkaterv') ||
            combined.contains('naptar') ||
            combined.contains('rendje') ||
            combined.contains('esemeny') ||
            combined.contains('program')) {
          if (!pdfCandidates.contains(resolved)) {
            pdfCandidates.add(resolved);
          }
        }
        continue;
      }
      if (!collectHtmlLinks) continue;

      final score = _scoreScheduleLink(lowerHref, label);
      if (score > 0 && seenUrls.add(resolved.toString())) {
        scoredHtmlCandidates.add((uri: resolved, score: score));
      }
    }

    // 2. Plain href attributes not captured by anchor pair (e.g. Google Calendar embed or bare links)
    final iframeRegex = RegExp(
      r'''<(?:iframe|link)[^>]+(?:src|href)\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final m in iframeRegex.allMatches(html)) {
      final rawUrl = (m.group(1) ?? '').trim();
      if (rawUrl.isEmpty) continue;
      final lower = rawUrl.toLowerCase();
      if (lower.contains('calendar.google.com/calendar')) {
        final uri = Uri.tryParse(rawUrl.replaceAll('&amp;', '&'));
        final srcParam = uri?.queryParameters['src'];
        if (srcParam != null && srcParam.isNotEmpty) {
          final icsUri = Uri.parse(
            'https://calendar.google.com/calendar/ical/${Uri.encodeComponent(srcParam)}/public/basic.ics',
          );
          if (!icsCandidates.contains(icsUri)) {
            icsCandidates.add(icsUri);
          }
        }
      } else if (lower.endsWith('.ics')) {
        try {
          final resolved = baseUri.resolve(rawUrl);
          if (!icsCandidates.contains(resolved)) {
            icsCandidates.add(resolved);
          }
        } catch (_) {}
      }
    }
  }

  static int _scoreScheduleLink(String lowerHref, String normalizedLabel) {
    final text = '$lowerHref $normalizedLabel';
    var score = 0;
    if (text.contains('tanev')) score += 6;
    if (text.contains('rendje')) score += 5;
    if (text.contains('munkaterv')) score += 6;
    if (text.contains('esemenynaptar') || text.contains('esemeny')) score += 4;
    if (text.contains('naptar') || text.contains('calendar')) score += 3;
    if (text.contains('program')) score += 3;
    if (text.contains('szunet')) score += 2;
    return score;
  }

  Future<SchoolYearSchedule?> _tryFetchIcsUri({
    required Uri icsUri,
    required int startYear,
    String? schoolName,
    String? pageUrl,
    String? pdfUrl,
    required DateTime now,
  }) async {
    try {
      final resp =
          await _http.get(icsUri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final text = _decodeHtmlBytes(resp.bodyBytes);
      if (!text.contains('BEGIN:VCALENDAR') && !text.contains('BEGIN:VEVENT')) {
        return null;
      }
      final events = parseScheduleFromIcs(text, startYear);
      if (events.isEmpty) return null;
      return _buildWebsiteSchedule(
        startYear: startYear,
        schoolName: schoolName,
        sourceUrl: pageUrl ?? icsUri.toString(),
        pdfUrl: pdfUrl,
        icsUrl: icsUri.toString(),
        sourceLabel: 'Iskolai naptár (.ics)',
        parsedEvents: events,
        fetchedAt: now,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SchoolYearSchedule?> _tryFetchPdfUri({
    required Uri pdfUri,
    required int startYear,
    String? schoolName,
    required String pageUrl,
    List<SchoolYearEvent> existingEvents = const [],
    required DateTime now,
  }) async {
    try {
      final resp =
          await _http.get(pdfUri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) {
        // Still expose the PDF URL gracefully so the user can open it directly.
        return _buildWebsiteSchedule(
          startYear: startYear,
          schoolName: schoolName,
          sourceUrl: pageUrl,
          pdfUrl: pdfUri.toString(),
          sourceLabel: 'Iskolai PDF dokumentum',
          parsedEvents: existingEvents,
          fetchedAt: now,
        );
      }
      return _buildPdfFallbackSchedule(
        pdfBytes: resp.bodyBytes,
        pdfUri: pdfUri,
        pageUrl: pageUrl,
        startYear: startYear,
        schoolName: schoolName,
        existingEvents: existingEvents,
        now: now,
      );
    } catch (_) {
      return _buildWebsiteSchedule(
        startYear: startYear,
        schoolName: schoolName,
        sourceUrl: pageUrl,
        pdfUrl: pdfUri.toString(),
        sourceLabel: 'Iskolai PDF dokumentum',
        parsedEvents: existingEvents,
        fetchedAt: now,
      );
    }
  }

  SchoolYearSchedule _buildPdfFallbackSchedule({
    required List<int> pdfBytes,
    required Uri pdfUri,
    required String pageUrl,
    required int startYear,
    String? schoolName,
    List<SchoolYearEvent> existingEvents = const [],
    required DateTime now,
  }) {
    final extracted = extractEventsFromPdfBytes(pdfBytes, startYear);
    final merged = <SchoolYearEvent>[...existingEvents];
    final seen = <String>{
      for (final e in merged)
        '${_normalizeHu(e.title)}_${DateUtils.dateOnly(e.startDate).toIso8601String()}',
    };
    for (final e in extracted) {
      final k =
          '${_normalizeHu(e.title)}_${DateUtils.dateOnly(e.startDate).toIso8601String()}';
      if (seen.add(k)) {
        merged.add(e);
      }
    }
    return _buildWebsiteSchedule(
      startYear: startYear,
      schoolName: schoolName,
      sourceUrl: pageUrl,
      pdfUrl: pdfUri.toString(),
      sourceLabel: extracted.isNotEmpty
          ? 'Iskolai PDF tanév rendje'
          : 'Iskolai PDF dokumentum',
      parsedEvents: merged,
      fetchedAt: now,
    );
  }

  SchoolYearSchedule _buildWebsiteSchedule({
    required int startYear,
    String? schoolName,
    required String sourceUrl,
    String? pdfUrl,
    String? icsUrl,
    String sourceLabel = 'Iskolai honlap',
    required List<SchoolYearEvent> parsedEvents,
    required DateTime fetchedAt,
  }) {
    final national = buildNationalHungarianSchedule(
      startYear,
      schoolName: schoolName,
      fetchedAt: fetchedAt,
    );
    final combined = <SchoolYearEvent>[...parsedEvents];
    for (final nat in national.events) {
      final alreadyCovered = combined.any(
        (e) =>
            (e.type == nat.type &&
                DateUtils.dateOnly(e.startDate) ==
                    DateUtils.dateOnly(nat.startDate)) ||
            _normalizeHu(e.title) == _normalizeHu(nat.title),
      );
      if (!alreadyCovered) {
        combined.add(nat);
      }
    }
    final mergedCombined = mergeConsecutiveScheduleEvents(combined);
    mergedCombined.sort((a, b) => a.startDate.compareTo(b.startDate));
    return SchoolYearSchedule(
      schoolYearLabel: '$startYear/${startYear + 1}',
      schoolName: schoolName,
      sourceUrl: sourceUrl,
      pdfUrl: pdfUrl,
      icsUrl: icsUrl,
      sourceLabel: sourceLabel,
      fetchedAt: fetchedAt,
      events: mergedCombined,
    );
  }

  static String _decodeHtmlBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  static const Map<String, int> _huMonths = {
    'januar': 1,
    'jan': 1,
    'februar': 2,
    'feb': 2,
    'marcius': 3,
    'marc': 3,
    'aprilis': 4,
    'apr': 4,
    'majus': 5,
    'maj': 5,
    'junius': 6,
    'jun': 6,
    'julius': 7,
    'jul': 7,
    'augusztus': 8,
    'aug': 8,
    'szeptember': 9,
    'szept': 9,
    'oktober': 10,
    'okt': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  static const Map<String, int> _romanMonths = {
    'xii': 12,
    'xi': 11,
    'ix': 9,
    'x': 10,
    'viii': 8,
    'vii': 7,
    'vi': 6,
    'v': 5,
    'iv': 4,
    'iii': 3,
    'ii': 2,
    'i': 1,
  };

  /// Parses events from an iCalendar (`.ics`) feed (`VEVENT` blocks).
  static List<SchoolYearEvent> parseScheduleFromIcs(
    String icsContent,
    int startYear,
  ) {
    // Unfold RFC 5545 folded lines.
    final unfolded = icsContent
        .replaceAll('\r\n ', '')
        .replaceAll('\r\n\t', '')
        .replaceAll('\n ', '')
        .replaceAll('\n\t', '');
    final lines = unfolded.split(RegExp(r'\r?\n'));
    final events = <SchoolYearEvent>[];
    final minDate = DateTime(startYear, 8, 20);
    final maxDate = DateTime(startYear + 1, 9, 5);
    final seen = <String>{};

    bool inEvent = false;
    String? summary;
    String? description;
    String? dtStartRaw;
    String? dtEndRaw;

    void flushEvent() {
      final rawSummary = summary;
      final rawStart = dtStartRaw;
      if (rawSummary == null || rawSummary.trim().isEmpty || rawStart == null) {
        return;
      }
      final start = _parseIcsDate(rawStart);
      if (start == null) return;
      if (start.isBefore(minDate) || start.isAfter(maxDate)) return;

      final rawEnd = dtEndRaw;
      var end = rawEnd != null ? _parseIcsDate(rawEnd) : start;
      end ??= start;
      // In RFC 5545, VALUE=DATE DTEND is exclusive (next midnight).
      if (rawEnd != null && !rawEnd.contains('T') && end.isAfter(start)) {
        end = end.subtract(const Duration(days: 1));
      }
      if (end.isBefore(start)) end = start;

      final cleanTitle = _unescapeIcsText(rawSummary);
      final rawDesc = description;
      final cleanDesc = rawDesc != null ? _unescapeIcsText(rawDesc) : null;
      final classified = _classifyLine('$cleanTitle ${cleanDesc ?? ''}');
      final type = classified?.type ?? SchoolYearEventType.specialDay;
      final source = (classified?.isNational ?? false)
          ? SchoolYearEventSource.national
          : SchoolYearEventSource.school;
      final dedupeKey =
          '${_normalizeHu(cleanTitle)}_${DateUtils.dateOnly(start).toIso8601String()}';
      if (!seen.add(dedupeKey)) return;

      events.add(
        SchoolYearEvent(
          id: 'ics_${events.length}_${start.millisecondsSinceEpoch}',
          title: cleanTitle,
          startDate: start,
          endDate: end,
          type: type,
          description: (cleanDesc != null &&
                  cleanDesc.isNotEmpty &&
                  cleanDesc != cleanTitle &&
                  cleanDesc.length <= 180)
              ? cleanDesc
              : null,
          source: source,
        ),
      );
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line == 'BEGIN:VEVENT') {
        inEvent = true;
        summary = null;
        description = null;
        dtStartRaw = null;
        dtEndRaw = null;
        continue;
      }
      if (line == 'END:VEVENT') {
        if (inEvent) flushEvent();
        inEvent = false;
        continue;
      }
      if (!inEvent) continue;
      final colonIdx = line.indexOf(':');
      if (colonIdx <= 0) continue;
      final propName = line.substring(0, colonIdx).split(';').first.toUpperCase();
      final value = line.substring(colonIdx + 1).trim();
      switch (propName) {
        case 'SUMMARY':
          summary = value;
        case 'DESCRIPTION':
          description = value;
        case 'DTSTART':
          dtStartRaw = value;
        case 'DTEND':
          dtEndRaw = value;
      }
    }

    final merged = mergeConsecutiveScheduleEvents(events);
    merged.sort((a, b) => a.startDate.compareTo(b.startDate));
    return merged;
  }

  /// Merges consecutive or overlapping non-custom schedule events that share the
  /// same break/holiday/event name (within 1 calendar day of each other) into a
  /// single event spanning `min(startDate) – max(endDate)`.
  static List<SchoolYearEvent> mergeConsecutiveScheduleEvents(
    List<SchoolYearEvent> events,
  ) {
    if (events.length <= 1) return List<SchoolYearEvent>.from(events);
    final sorted = List<SchoolYearEvent>.from(events)
      ..sort((a, b) {
        final sCmp = DateUtils.dateOnly(a.startDate)
            .compareTo(DateUtils.dateOnly(b.startDate));
        if (sCmp != 0) return sCmp;
        return DateUtils.dateOnly(a.endDate)
            .compareTo(DateUtils.dateOnly(b.endDate));
      });

    final merged = <SchoolYearEvent>[];
    final lastIdxByKey = <String, int>{};

    for (final next in sorted) {
      final normTitle =
          _normalizeHu(next.title).replaceAll(RegExp(r'\s+'), ' ').trim();
      final nextStart = DateUtils.dateOnly(next.startDate.toLocal());
      final nextEnd = DateUtils.dateOnly(next.endDate.toLocal());
      final effectiveNextEnd = nextEnd.isBefore(nextStart) ? nextStart : nextEnd;

      if (next.isCustom || normTitle.isEmpty) {
        merged.add(next);
        continue;
      }

      final key = '$normTitle|${next.category.name}';
      final prevIdx = lastIdxByKey[key];
      if (prevIdx == null) {
        lastIdxByKey[key] = merged.length;
        merged.add(next);
        continue;
      }

      final prev = merged[prevIdx];
      final prevStart = DateUtils.dateOnly(prev.startDate.toLocal());
      final prevEnd = DateUtils.dateOnly(prev.endDate.toLocal());
      final prevEndUtc = DateTime.utc(prevEnd.year, prevEnd.month, prevEnd.day);
      final nextStartUtc =
          DateTime.utc(nextStart.year, nextStart.month, nextStart.day);
      final gapDays = nextStartUtc.difference(prevEndUtc).inDays;

      if (gapDays <= 1) {
        final mergedStart = prevStart.isBefore(nextStart) ? prevStart : nextStart;
        final mergedEnd =
            prevEnd.isAfter(effectiveNextEnd) ? prevEnd : effectiveNextEnd;
        final prevDesc = prev.description?.trim();
        final nextDesc = next.description?.trim();
        // Drop redundant raw scraped line descriptions if they only echoed the
        // single-day date alongside the title (e.g. "2027.01.03. • Téli szünet").
        String? resolvedDesc;
        if (prevDesc != null &&
            prevDesc.isNotEmpty &&
            !RegExp(r'\d{4}[.\-]\s*\d{1,2}[.\-]\s*\d{1,2}')
                .hasMatch(prevDesc) &&
            !RegExp(r'^\d{1,2}\.\s*\d{1,2}\.').hasMatch(prevDesc)) {
          resolvedDesc = prevDesc;
        } else if (nextDesc != null &&
            nextDesc.isNotEmpty &&
            !RegExp(r'\d{4}[.\-]\s*\d{1,2}[.\-]\s*\d{1,2}')
                .hasMatch(nextDesc) &&
            !RegExp(r'^\d{1,2}\.\s*\d{1,2}\.').hasMatch(nextDesc)) {
          resolvedDesc = nextDesc;
        }
        final resolvedSource =
            prev.source == SchoolYearEventSource.national ||
                    next.source == SchoolYearEventSource.national
                ? SchoolYearEventSource.national
                : prev.source;

        merged[prevIdx] = SchoolYearEvent(
          id: prev.id,
          title: prev.title,
          startDate: mergedStart,
          endDate: mergedEnd,
          type: prev.type,
          description: resolvedDesc,
          isCustom: false,
          source: resolvedSource,
          categoryOverride: prev.categoryOverride ?? next.categoryOverride,
        );
      } else {
        lastIdxByKey[key] = merged.length;
        merged.add(next);
      }
    }

    return merged;
  }

  static DateTime? _parseIcsDate(String raw) {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(raw.trim());
    if (m == null) return null;
    return _safeDate(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  static String _unescapeIcsText(String raw) {
    return raw
        .replaceAll(r'\n', ' ')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Extracts readable text lines from uncompressed/text PDF bytes and parses
  /// school calendar events via [parseScheduleFromHtml].
  static List<SchoolYearEvent> extractEventsFromPdfBytes(
    List<int> bytes,
    int startYear,
  ) {
    if (bytes.isEmpty) return const [];
    final utf8Candidate = utf8.decode(bytes, allowMalformed: true);
    final rawText = !utf8Candidate.contains('\uFFFD')
        ? utf8Candidate
        : latin1.decode(bytes, allowInvalid: true);
    final extractedSegments = <String>[];

    // Collect parenthesized PDF text literals `(...) Tj/TJ`
    final parenRegex = RegExp(r'\(([^\(\)\\]*(?:\\.[^\(\)\\]*)*)\)');
    for (final m in parenRegex.allMatches(rawText)) {
      final seg = (m.group(1) ?? '')
          .replaceAll(r'\(', '(')
          .replaceAll(r'\)', ')')
          .replaceAll(r'\\', r'\')
          .replaceAll(RegExp(r'[\x00-\x1F]+'), ' ')
          .trim();
      if (seg.length >= 2) {
        extractedSegments.add(seg);
      }
    }

    // Fall back to plain line scanning only when no PDF parenthesized literals existed.
    if (extractedSegments.isEmpty) {
      extractedSegments.addAll(
        rawText
            .split(RegExp(r'[\r\n]+'))
            .map((l) => l.replaceAll(RegExp(r'[\x00-\x1F]+'), ' ').trim())
            .where((l) =>
                l.length >= 6 && l.length <= 220 && !l.startsWith('%PDF-')),
      );
    }

    if (extractedSegments.isEmpty) return const [];
    final syntheticText = extractedSegments.map((s) => '• $s').join('\n');
    return parseScheduleFromHtml(syntheticText, startYear);
  }

  /// Extracts school year breaks, holidays, working Saturdays, and school-specific
  /// programs from an HTML page containing Hungarian "Tanév rendje" tables,
  /// lists, or structured paragraphs.
  static List<SchoolYearEvent> parseScheduleFromHtml(
    String html,
    int startYear,
  ) {
    final cleaned = html
        .replaceAll(
          RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '\n',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '\n',
        )
        // Preserve multi-column table rows as single `cell | cell` lines.
        .replaceAll(
          RegExp(r'</t[dh]>\s*<t[dh][^>]*>', caseSensitive: false),
          ' | ',
        )
        .replaceAll(
          RegExp(r'</(tr|p|div|li|h[1-6]|dt|dd)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&ndash;', '–')
        .replaceAll('&#8211;', '–')
        .replaceAll('&mdash;', '—')
        .replaceAll('&#8212;', '—')
        .replaceAll('&aacute;', 'á')
        .replaceAll('&Aacute;', 'Á')
        .replaceAll('&eacute;', 'é')
        .replaceAll('&Eacute;', 'É')
        .replaceAll('&iacute;', 'í')
        .replaceAll('&Iacute;', 'Í')
        .replaceAll('&oacute;', 'ó')
        .replaceAll('&Oacute;', 'Ó')
        .replaceAll('&ouml;', 'ö')
        .replaceAll('&Ouml;', 'Ö')
        .replaceAll('&odblac;', 'ő')
        .replaceAll('&Odblac;', 'Ő')
        .replaceAll('&uacute;', 'ú')
        .replaceAll('&Uacute;', 'Ú')
        .replaceAll('&uuml;', 'ü')
        .replaceAll('&Uuml;', 'Ü')
        .replaceAll('&udblac;', 'ű')
        .replaceAll('&Udblac;', 'Ű')
        .replaceAll('&amp;', '&');

    final lines = cleaned
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final events = <SchoolYearEvent>[];
    final seenKeys = <String>{};
    final minDate = DateTime(startYear, 8, 20);
    final maxDate = DateTime(startYear + 1, 9, 5);

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final nextLine = (i + 1 < lines.length && lines[i + 1].length < 100)
          ? lines[i + 1]
          : null;
      final combined = nextLine != null ? '$line $nextLine' : line;

      final lineRange = _extractDateRangeWithSpan(line, startYear) ??
          (_classifyLine(line, startYear: startYear) != null
              ? _extractShortNumericDateRangeWithSpan(line, startYear)
              : null);
      final nextLineSelfHasDateAndLabel = nextLine != null &&
          (_extractDateRangeWithSpan(nextLine, startYear) != null ||
              (_classifyLine(nextLine, startYear: startYear) != null &&
                  _extractShortNumericDateRangeWithSpan(nextLine, startYear) !=
                      null)) &&
          (_classifyLine(nextLine, startYear: startYear) != null ||
              nextLine.startsWith('•'));
      final combinedRange = (lineRange == null && !nextLineSelfHasDateAndLabel)
          ? (_extractDateRangeWithSpan(combined, startYear) ??
              (_classifyLine(combined, startYear: startYear) != null
                  ? _extractShortNumericDateRangeWithSpan(combined, startYear)
                  : null))
          : null;
      final range = lineRange ??
          (combinedRange == null
              ? null
              : (
                  start: combinedRange.start,
                  end: combinedRange.end,
                  matchStart: combinedRange.matchStart,
                  matchEnd: combinedRange.matchEnd,
                  fromCombined: true,
                ));
      if (range == null) continue;
      if (range.start.isBefore(minDate) || range.start.isAfter(maxDate)) {
        continue;
      }

      final sourceLine = range.fromCombined ? combined : line;
      final classified = _classifyLine(sourceLine, startYear: startYear) ??
          _classifyGenericScheduledLine(
            sourceLine,
            range.matchStart,
            range.matchEnd,
          );
      if (classified == null) continue;
      if (!classified.isNational &&
          isNoiseOrBoilerplateTitle(classified.title, rawLine: sourceLine)) {
        continue;
      }

      final key =
          '${_normalizeHu(classified.title)}_${DateUtils.dateOnly(range.start).toIso8601String()}';
      if (!seenKeys.add(key)) continue;

      final cleanDescription = sourceLine.replaceAll(' | ', ' • ').trim();
      events.add(
        SchoolYearEvent(
          id: 'web_${classified.type.name}_${events.length}',
          title: classified.title,
          startDate: range.start,
          endDate: range.end.isBefore(range.start) ? range.start : range.end,
          type: classified.type,
          description: (cleanDescription.length <= 180 &&
                  _normalizeHu(cleanDescription) !=
                      _normalizeHu(classified.title))
              ? cleanDescription
              : null,
          source: classified.isNational
              ? SchoolYearEventSource.national
              : SchoolYearEventSource.school,
        ),
      );
    }

    final merged = mergeConsecutiveScheduleEvents(events);
    merged.sort((a, b) => a.startDate.compareTo(b.startDate));
    return merged;
  }

  static ({
    DateTime start,
    DateTime end,
    int matchStart,
    int matchEnd,
    bool fromCombined,
  })? _extractShortNumericDateRangeWithSpan(String text, int startYear) {
    final norm = _normalizeHu(text);
    final shortRange = RegExp(
      r'\b(0?[1-9]|1[0-2])\.\s*(0?[1-9]|[12]\d|3[01])\.?\s*[-–—]\s*(?:(0?[1-9]|1[0-2])\.\s*)?(0?[1-9]|[12]\d|3[01])\.?',
    ).firstMatch(norm);
    if (shortRange != null) {
      final m1 = int.parse(shortRange.group(1)!);
      final d1 = int.parse(shortRange.group(2)!);
      final y1 = m1 >= 9 ? startYear : startYear + 1;
      final m2 = int.tryParse(shortRange.group(3) ?? '') ?? m1;
      final d2 = int.parse(shortRange.group(4)!);
      final y2 = m2 < m1 ? y1 + 1 : (m2 >= 9 ? startYear : startYear + 1);
      final start = _safeDate(y1, m1, d1);
      final end = _safeDate(y2, m2, d2);
      if (start != null && end != null) {
        return (
          start: start,
          end: end,
          matchStart: shortRange.start,
          matchEnd: shortRange.end,
          fromCombined: false,
        );
      }
    }
    final shortSingle = RegExp(
      r'\b(0?[1-9]|1[0-2])\.\s*(0?[1-9]|[12]\d|3[01])\.',
    ).firstMatch(norm);
    if (shortSingle != null) {
      final m = int.parse(shortSingle.group(1)!);
      final d = int.parse(shortSingle.group(2)!);
      final y = m >= 9 ? startYear : startYear + 1;
      final dt = _safeDate(y, m, d);
      if (dt != null) {
        return (
          start: dt,
          end: dt,
          matchStart: shortSingle.start,
          matchEnd: shortSingle.end,
          fromCombined: false,
        );
      }
    }
    return null;
  }

  static ({String title, SchoolYearEventType type, bool isNational})?
      _classifyLine(String raw, {int? startYear}) {
    final norm = _normalizeHu(raw);
    if (norm.contains('oszi szunet')) {
      return (
        title: 'Őszi szünet',
        type: SchoolYearEventType.schoolBreak,
        isNational: true,
      );
    }
    if (norm.contains('teli szunet')) {
      return (
        title: 'Téli szünet',
        type: SchoolYearEventType.schoolBreak,
        isNational: true,
      );
    }
    if (norm.contains('tavaszi szunet')) {
      return (
        title: 'Tavaszi szünet',
        type: SchoolYearEventType.schoolBreak,
        isNational: true,
      );
    }
    if (norm.contains('nyari szunet')) {
      return (
        title: 'Nyári szünet',
        type: SchoolYearEventType.schoolBreak,
        isNational: true,
      );
    }
    if (norm.contains('szombat') &&
        (norm.contains('munkanap') ||
            norm.contains('tanitasi nap') ||
            norm.contains('ledolgoz'))) {
      return (
        title: 'Ledolgozós szombat',
        type: SchoolYearEventType.workingSaturday,
        isNational: true,
      );
    }
    if (norm.contains('elso tanitasi nap') || norm.contains('tanevnyito')) {
      return (
        title: 'Első tanítási nap',
        type: SchoolYearEventType.specialDay,
        isNational: true,
      );
    }
    if (norm.contains('utolso tanitasi nap') || norm.contains('tanevzaro')) {
      return (
        title: 'Utolsó tanítási nap',
        type: SchoolYearEventType.specialDay,
        isNational: true,
      );
    }
    if (norm.contains('elso felev vege') || norm.contains('felev zarasa')) {
      return (
        title: 'Első félév vége',
        type: SchoolYearEventType.specialDay,
        isNational: true,
      );
    }
    if (norm.contains('nemzeti unnep') ||
        norm.contains('munkaszuneti') ||
        norm.contains('mindenszentek') ||
        norm.contains('punkosd')) {
      final range = _extractDateRangeWithSpan(
        raw,
        startYear ?? resolveSchoolYearStart(DateTime.now()),
      );
      final stripped = range != null
          ? '${raw.substring(0, range.matchStart)} ${raw.substring(range.matchEnd)}'
          : raw;
      return (
        title: _cleanEventTitle(stripped, fallback: 'Ünnepnap'),
        type: SchoolYearEventType.nationalHoliday,
        isNational: true,
      );
    }

    const schoolKeywords = [
      'szuloi ertekezlet',
      'fogadoora',
      'nyilt nap',
      'palyaorientacio',
      'projektnap',
      'projekthet',
      'temahet',
      'tematikus nap',
      'diaknap',
      'sportnap',
      'egeszsegnap',
      'szalagavato',
      'ballagas',
      'golyatabor',
      'golyaavato',
      'mikulas',
      'karacsony',
      'farsang',
      'kirandulas',
      'osztalykirandulas',
      'erettsegi',
      'felveteli',
      'verseny',
      'unnepely',
      'unnepseg',
      'adventi',
      'vasar',
      'megemlekezes',
      'beiratkozas',
      'bizonyitvany',
      'osztalyozo',
      'tanitas nelkuli munkanap',
      'nevelesi ertekezlet',
      'fotozas',
      'veradas',
      'eloadas',
      'kiallitas',
      'fordulo',
      'program',
      'esemeny',
      'het',
      'napja',
    ];
    for (final kw in schoolKeywords) {
      if (norm.contains(kw)) {
        final range = _extractDateRangeWithSpan(
          raw,
          startYear ?? resolveSchoolYearStart(DateTime.now()),
        );
        final stripped = range != null
            ? '${raw.substring(0, range.matchStart)} ${raw.substring(range.matchEnd)}'
            : raw;
        final title = _cleanEventTitle(stripped, fallback: _cleanEventTitle(raw));
        if (title.length >= 3) {
          return (
            title: title,
            type: SchoolYearEventType.specialDay,
            isNational: false,
          );
        }
      }
    }

    return null;
  }

  static ({String title, SchoolYearEventType type, bool isNational})?
      _classifyGenericScheduledLine(
    String raw,
    int matchStart,
    int matchEnd,
  ) {
    final before = raw.substring(0, matchStart);
    final after = raw.substring(matchEnd);
    final residual = _cleanEventTitle('$before $after');
    if (residual.length < 4 || residual.length > 95) return null;

    final hasStructure = raw.contains('|') ||
        raw.startsWith('•') ||
        raw.contains(':') ||
        raw.contains('–') ||
        raw.contains(' - ');
    if (!hasStructure) return null;

    final normRes = _normalizeHu(residual);
    const boilerplate = [
      'impresszum',
      'adatvedelem',
      'cookie',
      'kapcsolat',
      'koszont',
      'frissitve',
      'utoljara',
      'minden jog',
      'copyright',
      'telefon',
      'e-mail',
      'email',
      'cim:',
      'letoltes',
    ];
    for (final skip in boilerplate) {
      if (normRes.contains(skip)) return null;
    }

    return (
      title: residual,
      type: SchoolYearEventType.specialDay,
      isNational: false,
    );
  }

  static String _cleanEventTitle(String raw, {String fallback = 'Iskolai program'}) {
    var clean = raw
        .replaceAll('|', ' ')
        .replaceAll('•', ' ')
        .replaceAll(RegExp(r'^[\s\-–—:.,;•*#0-9\)]+'), '')
        .replaceAll(RegExp(r'[\s\-–—:.,;]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.length > 76) {
      clean = '${clean.substring(0, 73).trim()}...';
    }
    return clean.isEmpty ? fallback : clean;
  }

  static ({
    DateTime start,
    DateTime end,
    int matchStart,
    int matchEnd,
    bool fromCombined,
  })? _extractDateRangeWithSpan(String text, int startYear) {
    final norm = _normalizeHu(text);
    final monthNames = _huMonths.keys.join('|');
    final romanKeys = _romanMonths.keys.join('|');

    // Pattern 1: Named range "2026. november 14-15." or "okt. 23. - nov. 1."
    final namedRegex = RegExp(
      '(?:(\\d{4})\\.?\\s*)?($monthNames)\\.?\\s+(\\d{1,2})\\.?\\s*(?:[-–—]|(?:tol|-tol))\\s*(?:(\\d{4})\\.?\\s*)?(?:($monthNames)\\.?\\s+)?(\\d{1,2})\\.?(?:-?(?:ig))?',
    );
    final namedMatch = namedRegex.firstMatch(norm);
    if (namedMatch != null) {
      final m1 = _huMonths[namedMatch.group(2)!]!;
      final d1 = int.tryParse(namedMatch.group(3)!) ?? 1;
      final y1 = int.tryParse(namedMatch.group(1) ?? '') ??
          (m1 >= 9 ? startYear : startYear + 1);
      final m2 = namedMatch.group(5) != null
          ? _huMonths[namedMatch.group(5)!]!
          : m1;
      final d2 = int.tryParse(namedMatch.group(6)!) ?? d1;
      final y2 = int.tryParse(namedMatch.group(4) ?? '') ??
          (m2 < m1 ? y1 + 1 : (m2 >= 9 ? startYear : startYear + 1));
      final start = _safeDate(y1, m1, d1);
      final end = _safeDate(y2, m2, d2);
      if (start != null && end != null) {
        return (
          start: start,
          end: end,
          matchStart: namedMatch.start,
          matchEnd: namedMatch.end,
          fromCombined: false,
        );
      }
    }

    // Pattern 2: Roman month range e.g. "2026. XI. 14-15." or "X. 23. - XI. 1."
    final romanRangeRegex = RegExp(
      '(?:(\\d{4})\\.?\\s*)?\\b($romanKeys)\\.\\s*(\\d{1,2})\\.?\\s*[-–—]\\s*(?:(\\d{4})\\.?\\s*)?(?:\\b($romanKeys)\\.\\s*)?(\\d{1,2})\\.?',
    );
    final romanRangeMatch = romanRangeRegex.firstMatch(norm);
    if (romanRangeMatch != null) {
      final m1 = _romanMonths[romanRangeMatch.group(2)!]!;
      final d1 = int.tryParse(romanRangeMatch.group(3)!) ?? 1;
      final y1 = int.tryParse(romanRangeMatch.group(1) ?? '') ??
          (m1 >= 9 ? startYear : startYear + 1);
      final m2 = romanRangeMatch.group(5) != null
          ? _romanMonths[romanRangeMatch.group(5)!]!
          : m1;
      final d2 = int.tryParse(romanRangeMatch.group(6)!) ?? d1;
      final y2 = int.tryParse(romanRangeMatch.group(4) ?? '') ??
          (m2 < m1 ? y1 + 1 : (m2 >= 9 ? startYear : startYear + 1));
      final start = _safeDate(y1, m1, d1);
      final end = _safeDate(y2, m2, d2);
      if (start != null && end != null) {
        return (
          start: start,
          end: end,
          matchStart: romanRangeMatch.start,
          matchEnd: romanRangeMatch.end,
          fromCombined: false,
        );
      }
    }

    // Pattern 3: Numeric range "2026.10.23 - 2026.11.01", "2026. 11. 14-15.", "2026-11-14 - 2026-11-15"
    final numRangeRegex = RegExp(
      r'(\d{4})[.\-]\s*(\d{1,2})[.\-]\s*(\d{1,2})\.?\s*[-–—]\s*(?:(\d{4})[.\-]\s*)?(?:(\d{1,2})[.\-]\s*)?(\d{1,2})\.?',
    );
    final numRange = numRangeRegex.firstMatch(norm);
    if (numRange != null) {
      final y1 = int.parse(numRange.group(1)!);
      final m1 = int.parse(numRange.group(2)!);
      final d1 = int.parse(numRange.group(3)!);
      final y2 = int.tryParse(numRange.group(4) ?? '') ?? y1;
      final m2 = int.tryParse(numRange.group(5) ?? '') ?? m1;
      final d2 = int.parse(numRange.group(6)!);
      final start = _safeDate(y1, m1, d1);
      final end = _safeDate(y2, m2, d2);
      if (start != null && end != null) {
        return (
          start: start,
          end: end,
          matchStart: numRange.start,
          matchEnd: numRange.end,
          fromCombined: false,
        );
      }
    }

    // Pattern 4: Single named date "2026. szeptember 1." or "november 14."
    final singleNamed = RegExp(
      '(?:(\\d{4})\\.?\\s*)?($monthNames)\\.?\\s+(\\d{1,2})\\.?',
    ).firstMatch(norm);
    if (singleNamed != null) {
      final m = _huMonths[singleNamed.group(2)!]!;
      final d = int.tryParse(singleNamed.group(3)!) ?? 1;
      final y = int.tryParse(singleNamed.group(1) ?? '') ??
          (m >= 9 ? startYear : startYear + 1);
      final dt = _safeDate(y, m, d);
      if (dt != null) {
        return (
          start: dt,
          end: dt,
          matchStart: singleNamed.start,
          matchEnd: singleNamed.end,
          fromCombined: false,
        );
      }
    }

    // Pattern 5: Single Roman numeral date "2026. XI. 14." or "XI. 14."
    final singleRoman = RegExp(
      '(?:(\\d{4})\\.?\\s*)?\\b($romanKeys)\\.\\s*(\\d{1,2})\\.?',
    ).firstMatch(norm);
    if (singleRoman != null) {
      final m = _romanMonths[singleRoman.group(2)!]!;
      final d = int.tryParse(singleRoman.group(3)!) ?? 1;
      final y = int.tryParse(singleRoman.group(1) ?? '') ??
          (m >= 9 ? startYear : startYear + 1);
      final dt = _safeDate(y, m, d);
      if (dt != null) {
        return (
          start: dt,
          end: dt,
          matchStart: singleRoman.start,
          matchEnd: singleRoman.end,
          fromCombined: false,
        );
      }
    }

    // Pattern 6: Single numeric date "2026.09.01.", "2026. 11. 14.", "2026-11-14"
    final singleNum = RegExp(
      r'(\d{4})[.\-]\s*(\d{1,2})[.\-]\s*(\d{1,2})\.?',
    ).firstMatch(norm);
    if (singleNum != null) {
      final dt = _safeDate(
        int.parse(singleNum.group(1)!),
        int.parse(singleNum.group(2)!),
        int.parse(singleNum.group(3)!),
      );
      if (dt != null) {
        return (
          start: dt,
          end: dt,
          matchStart: singleNum.start,
          matchEnd: singleNum.end,
          fromCombined: false,
        );
      }
    }

    return null;
  }

  static DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    if (dt.month != m || dt.day != d) return null;
    return dt;
  }

  static String _normalizeHu(String input) {
    const map = {
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
    final out = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      out.write(map[ch] ?? ch);
    }
    return out.toString();
  }

  /// Official Hungarian national `Tanév rendje` schedule builder for any school
  /// year (`2025/2026`, `2026/2027`, `2027/2028`, or dynamically computed).
  static SchoolYearSchedule buildNationalHungarianSchedule(
    int startYear, {
    String? schoolName,
    String? sourceUrl,
    DateTime? fetchedAt,
  }) {
    final endYear = startYear + 1;
    final events = <SchoolYearEvent>[];

    if (startYear == 2025) {
      events.addAll([
        SchoolYearEvent(
          id: 'nat_2025_first_day',
          title: 'Első tanítási nap',
          startDate: DateTime(2025, 9, 1),
          endDate: DateTime(2025, 9, 1),
          type: SchoolYearEventType.specialDay,
        ),
        SchoolYearEvent(
          id: 'nat_2025_sat_1',
          title: 'Ledolgozós szombat (okt. 24. helyett)',
          startDate: DateTime(2025, 10, 18),
          endDate: DateTime(2025, 10, 18),
          type: SchoolYearEventType.workingSaturday,
        ),
        SchoolYearEvent(
          id: 'nat_2025_autumn',
          title: 'Őszi szünet',
          startDate: DateTime(2025, 10, 23),
          endDate: DateTime(2025, 11, 2),
          type: SchoolYearEventType.schoolBreak,
          description: 'Utolsó tanítási nap: okt. 22., első tanítási nap utána: nov. 3.',
        ),
        SchoolYearEvent(
          id: 'nat_2025_sat_2',
          title: 'Ledolgozós szombat (dec. 24. helyett)',
          startDate: DateTime(2025, 12, 13),
          endDate: DateTime(2025, 12, 13),
          type: SchoolYearEventType.workingSaturday,
        ),
        SchoolYearEvent(
          id: 'nat_2025_winter',
          title: 'Téli szünet',
          startDate: DateTime(2025, 12, 20),
          endDate: DateTime(2026, 1, 4),
          type: SchoolYearEventType.schoolBreak,
          description: 'Utolsó tanítási nap: dec. 19., első tanítási nap utána: jan. 5.',
        ),
        SchoolYearEvent(
          id: 'nat_2025_sat_3',
          title: 'Ledolgozós szombat (jan. 2. helyett)',
          startDate: DateTime(2026, 1, 10),
          endDate: DateTime(2026, 1, 10),
          type: SchoolYearEventType.workingSaturday,
        ),
        SchoolYearEvent(
          id: 'nat_2025_semester',
          title: 'Első félév vége',
          startDate: DateTime(2026, 1, 23),
          endDate: DateTime(2026, 1, 23),
          type: SchoolYearEventType.specialDay,
        ),
        SchoolYearEvent(
          id: 'nat_2025_mar15',
          title: 'Nemzeti ünnep (március 15.)',
          startDate: DateTime(2026, 3, 15),
          endDate: DateTime(2026, 3, 15),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_2025_spring',
          title: 'Tavaszi szünet',
          startDate: DateTime(2026, 4, 2),
          endDate: DateTime(2026, 4, 12),
          type: SchoolYearEventType.schoolBreak,
          description: 'Húsvéti és tavaszi tanítási szünet',
        ),
        SchoolYearEvent(
          id: 'nat_2025_may1',
          title: 'A munka ünnepe',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 1),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_2025_pentecost',
          title: 'Pünkösdhétfő',
          startDate: DateTime(2026, 5, 25),
          endDate: DateTime(2026, 5, 25),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_2025_last_day',
          title: 'Utolsó tanítási nap',
          startDate: DateTime(2026, 6, 19),
          endDate: DateTime(2026, 6, 19),
          type: SchoolYearEventType.specialDay,
        ),
        SchoolYearEvent(
          id: 'nat_2025_summer',
          title: 'Nyári szünet',
          startDate: DateTime(2026, 6, 20),
          endDate: DateTime(2026, 8, 31),
          type: SchoolYearEventType.schoolBreak,
        ),
      ]);
    } else if (startYear == 2026) {
      events.addAll([
        SchoolYearEvent(
          id: 'nat_2026_first_day',
          title: 'Első tanítási nap',
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 1),
          type: SchoolYearEventType.specialDay,
        ),
        SchoolYearEvent(
          id: 'nat_2026_oct23',
          title: 'Nemzeti ünnep (október 23.)',
          startDate: DateTime(2026, 10, 23),
          endDate: DateTime(2026, 10, 23),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_2026_autumn',
          title: 'Őszi szünet',
          startDate: DateTime(2026, 10, 24),
          endDate: DateTime(2026, 11, 1),
          type: SchoolYearEventType.schoolBreak,
          description: 'Utolsó tanítási nap: okt. 22., első tanítási nap utána: nov. 2.',
        ),
        SchoolYearEvent(
          id: 'nat_2026_nov1',
          title: 'Mindenszentek',
          startDate: DateTime(2026, 11, 1),
          endDate: DateTime(2026, 11, 1),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_2026_sat_1',
          title: 'Ledolgozós szombat (dec. 24. helyett)',
          startDate: DateTime(2026, 12, 12),
          endDate: DateTime(2026, 12, 12),
          type: SchoolYearEventType.workingSaturday,
        ),
        SchoolYearEvent(
          id: 'nat_2026_winter',
          title: 'Téli szünet',
          startDate: DateTime(2026, 12, 19),
          endDate: DateTime(2027, 1, 3),
          type: SchoolYearEventType.schoolBreak,
          description: 'Utolsó tanítási nap: dec. 18., első tanítási nap utána: jan. 4.',
        ),
        SchoolYearEvent(
          id: 'nat_2026_semester',
          title: 'Első félév vége',
          startDate: DateTime(2027, 1, 22),
          endDate: DateTime(2027, 1, 22),
          type: SchoolYearEventType.specialDay,
        ),
        SchoolYearEvent(
          id: 'nat_2026_mar15',
          title: 'Nemzeti ünnep (március 15.)',
          startDate: DateTime(2027, 3, 15),
          endDate: DateTime(2027, 3, 15),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_2026_spring',
          title: 'Tavaszi szünet',
          startDate: DateTime(2027, 3, 25),
          endDate: DateTime(2027, 4, 4),
          type: SchoolYearEventType.schoolBreak,
          description: 'Húsvéti és tavaszi tanítási szünet',
        ),
        SchoolYearEvent(
          id: 'nat_2026_may1',
          title: 'A munka ünnepe',
          startDate: DateTime(2027, 5, 1),
          endDate: DateTime(2027, 5, 1),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_2026_pentecost',
          title: 'Pünkösdhétfő',
          startDate: DateTime(2027, 5, 17),
          endDate: DateTime(2027, 5, 17),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_2026_last_day',
          title: 'Utolsó tanítási nap',
          startDate: DateTime(2027, 6, 18),
          endDate: DateTime(2027, 6, 18),
          type: SchoolYearEventType.specialDay,
        ),
        SchoolYearEvent(
          id: 'nat_2026_summer',
          title: 'Nyári szünet',
          startDate: DateTime(2027, 6, 19),
          endDate: DateTime(2027, 8, 31),
          type: SchoolYearEventType.schoolBreak,
        ),
      ]);
    } else {
      // Dynamic calculation for any future/past school year using Easter Sunday.
      final easter = _computeEasterSunday(endYear);
      final pentecostMonday = easter.add(const Duration(days: 50));
      final firstDay = _nextWeekdayIfWeekend(DateTime(startYear, 9, 1));
      final autumnStart = DateTime(startYear, 10, 26);
      final autumnEnd = DateTime(startYear, 11, 3);
      final winterStart = DateTime(startYear, 12, 21);
      final winterEnd = DateTime(endYear, 1, 3);
      final springStart = easter.subtract(const Duration(days: 3));
      final springEnd = easter.add(const Duration(days: 5));
      final june15 = DateTime(endYear, 6, 15);
      final lastSchoolDay = _prevWeekdayIfWeekend(june15);

      events.addAll([
        SchoolYearEvent(
          id: 'nat_${startYear}_first_day',
          title: 'Első tanítási nap',
          startDate: firstDay,
          endDate: firstDay,
          type: SchoolYearEventType.specialDay,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_oct23',
          title: 'Nemzeti ünnep (október 23.)',
          startDate: DateTime(startYear, 10, 23),
          endDate: DateTime(startYear, 10, 23),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_autumn',
          title: 'Őszi szünet',
          startDate: autumnStart,
          endDate: autumnEnd,
          type: SchoolYearEventType.schoolBreak,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_nov1',
          title: 'Mindenszentek',
          startDate: DateTime(startYear, 11, 1),
          endDate: DateTime(startYear, 11, 1),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_winter',
          title: 'Téli szünet',
          startDate: winterStart,
          endDate: winterEnd,
          type: SchoolYearEventType.schoolBreak,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_mar15',
          title: 'Nemzeti ünnep (március 15.)',
          startDate: DateTime(endYear, 3, 15),
          endDate: DateTime(endYear, 3, 15),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_spring',
          title: 'Tavaszi szünet',
          startDate: springStart,
          endDate: springEnd,
          type: SchoolYearEventType.schoolBreak,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_may1',
          title: 'A munka ünnepe',
          startDate: DateTime(endYear, 5, 1),
          endDate: DateTime(endYear, 5, 1),
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_pentecost',
          title: 'Pünkösdhétfő',
          startDate: pentecostMonday,
          endDate: pentecostMonday,
          type: SchoolYearEventType.nationalHoliday,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_last_day',
          title: 'Utolsó tanítási nap',
          startDate: lastSchoolDay,
          endDate: lastSchoolDay,
          type: SchoolYearEventType.specialDay,
        ),
        SchoolYearEvent(
          id: 'nat_${startYear}_summer',
          title: 'Nyári szünet',
          startDate: lastSchoolDay.add(const Duration(days: 1)),
          endDate: DateTime(endYear, 8, 31),
          type: SchoolYearEventType.schoolBreak,
        ),
      ]);
    }

    events.sort((a, b) => a.startDate.compareTo(b.startDate));
    return SchoolYearSchedule(
      schoolYearLabel: '$startYear/$endYear',
      schoolName: schoolName,
      sourceUrl: sourceUrl,
      sourceLabel: 'Országos tanév rendje',
      fetchedAt: fetchedAt ?? DateTime.now(),
      events: events,
    );
  }

  static DateTime _computeEasterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  static DateTime _nextWeekdayIfWeekend(DateTime d) {
    if (d.weekday == DateTime.saturday) return d.add(const Duration(days: 2));
    if (d.weekday == DateTime.sunday) return d.add(const Duration(days: 1));
    return d;
  }

  static DateTime _prevWeekdayIfWeekend(DateTime d) {
    if (d.weekday == DateTime.saturday) {
      return d.subtract(const Duration(days: 1));
    }
    if (d.weekday == DateTime.sunday) return d.subtract(const Duration(days: 2));
    return d;
  }
}
