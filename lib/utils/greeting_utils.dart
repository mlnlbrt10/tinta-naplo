import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' show DateUtils, visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:kreta_api/kreta_api.dart';

import '../services/token_storage_service.dart';
import '../widgets/period_countdown_badge.dart'
    show isInactivePlaceholderLesson, isLessonCancelled;
import 'uwu_helper.dart';

/// Time-based Hungarian greeting and student name resolution utilities.
class GreetingUtils {
  /// Weekdays 05:00 - 07:45 ONLY (9 items).
  static const List<String> earlyMorningPool = [
    'Jó reggelt, {name}!',
    'Korán keltél, {name}',
    'Kávé volt már, {name}?',
    'Szundi gomb nem nyert, {name}?',
    'Ébresztő, {name}!',
    'Kómás reggelt, {name}!',
    'Félálomban, {name}?',
    'Álompor még a szemben, {name}?',
    'Hideg víz az arcra, {name}!',
  ];

  /// Weekdays 07:46 - 09:59 ONLY (7 items).
  static const List<String> morningPool = [
    'Indul a műszak, {name}',
    'Első óra túlélve, {name}?',
    'Becsengettek, {name}',
    'Padban ülsz már, {name}?',
    'Reggeli túlélő mód, {name}',
    'Jó reggelt (vagy olyasmi), {name}',
    'Késésben vagy, {name}?',
  ];

  /// Weekdays 10:00 - 14:29 ONLY (18 items).
  static const List<String> schoolDayPool = [
    'Kitartást mára, {name}!',
    'Mikor lesz már szünet, {name}?',
    'Hány órád van még, {name}?',
    'Menza túlélve, {name}?',
    'Csak még pár óra, {name}...',
    'Utolsó pad, {name}?',
    'Óra alatt telózunk, {name}?',
    'Puskázni ér, {name}?',
    'Röpdoga veszély, {name}!',
    'Tanár nem látja, {name}?',
    'Büfébe mikor megyünk, {name}?',
    'Üres óra mikor, {name}?',
    'Táblánál ki áll, {name}?',
    'Kréta szag van, {name}...',
    'Füzet nyitva, agy pihen, {name}?',
    'Tart még az óra, {name}?',
    '45 perc örökké, {name}',
    'Csengő szól már, {name}?',
  ];

  /// Weekdays 14:30 - 18:29 ONLY (11 items).
  static const List<String> afternoonPool = [
    'Szép délutánt, {name}!',
    'Végre szabadon, {name}?',
    'Hazaértél már, {name}?',
    'Házi kész van már, {name}?',
    'Délutáni szundi, {name}?',
    'Suli pipa mára, {name}!',
    'Táska a sarokban, {name}?',
    'Ma már ne tanulj sokat, {name}',
    'Kimenő, {name}!',
    'Túlélted a mait is, {name}!',
    'Délutáni pihi, {name}?',
  ];

  /// Daily 18:30 - 21:59 (5 daily items).
  static const List<String> eveningDailyPool = [
    'Szép estét, {name}!',
    'Esti chill, {name}?',
    'Táska bepakolva, {name}?',
    'Mára elég a Krétából, {name}',
    'Jó pihenést, {name}!',
  ];

  /// Shown 18:30 - 21:59 ONLY on Mon-Thu & Sun (when tomorrow is a school day).
  static const String eveningSchoolTomorrowTemplate = 'Holnap suli, {name}...';

  /// Daily 22:00 - 04:59 ONLY (10 items).
  static const List<String> lateNightPool = [
    'Még ébren, {name}?',
    'Aludj már, {name}',
    'Éjszakai műszak, {name}?',
    'Holnap fáradt leszel, {name}',
    'Bagoly mód, {name}?',
    'Ilyenkor Krétázol, {name}?!',
    'Szép álmokat, {name}!',
    'Telefon le, szem becsuk, {name}',
    'Éjféli jegynézegetés, {name}?',
    'Alvás az gyengéknek való, {name}?',
  ];

  /// Monday 05:00 - 21:59 (6 items).
  static const List<String> mondayPool = [
    'Boldog hétfőt (nem), {name}',
    'Már megint hétfő, {name}...',
    'Túléled a hétfőt, {name}!',
    'Hétfő. Részvétem, {name}.',
    'Ki találta ki a hétfőt, {name}?',
    'Új hét, ugyanaz a fáradtság, {name}',
  ];

  /// Friday 05:00 - 21:59 (6 items).
  static const List<String> fridayPool = [
    'Végre péntek, {name}!',
    'Hétvége betöltése, {name}...',
    'Ma már csak félgőzzel, {name}!',
    'Péntek van, bírjuk ki, {name}!',
    'Utolsó hajrá a héten, {name}!',
    'Szabadság illata van, {name}!',
  ];

  /// Saturday 05:00 - 21:59 / Sunday 05:00 - 17:59 (8 items).
  static const List<String> weekendPool = [
    'Hétvégén Kréta, {name}?',
    'Pihenj inkább, {name}!',
    'Ma nincs suli, {name}!',
    'Jó hétvégét, {name}!',
    'Hétvége van, zárd be, {name}!',
    'Szabadnap van, {name}!',
    'Lusta hétvége, {name}?',
    'Hétvégi Krétázás, {name}?',
  ];

  /// Sunday 18:00 - 21:59 (5 items).
  static const List<String> sundayEveningPool = [
    'Vasárnap esti pánik, {name}?',
    'Holnap hétfő, {name}...',
    'Hétvége: elillant, {name}',
    'Most jutott eszedbe a házi, {name}?',
    'Vasárnapi melankólia, {name}?',
  ];

  /// Anytime / General / Random & Absurd (31 items).
  static const List<String> generalPool = [
    'Szia, {name}!',
    'Helló, {name}!',
    'Üdv újra, {name}!',
    'Mi újság, {name}?',
    'Hali, {name}!',
    'Na mizu, {name}?',
    'Csáó, {name}!',
    'Ötösökre fel, {name}!',
    'Remélem ötös lett, {name}!',
    'Csak semmi pánik, {name}',
    'Minden jó lesz, {name}',
    'Mered nézni a jegyeket, {name}?',
    'Nem én rontottam el, {name}',
    'Vajon beírták már, {name}?',
    'Mély levegő, {name}...',
    'Ne nézz az átlagodra, {name}',
    '4.51 az már ötös, {name}?',
    '1.51 az már kettes, {name}!',
    'Igazolásod van még, {name}?',
    'Elfogyott az igazolás, {name}?',
    'Félévkor javítunk, {name}!',
    'Jövő héttől tanulunk, {name}?',
    'A jegy csak egy szám, {name}',
    'Kréta szerver bírja, {name}',
    'Tinta > Kréta, ugye {name}?',
    'Megint itt, {name}?',
    'Újra itt vagy, {name}?',
    '2 perce semmi új, {name}',
    'Bárcsak szünet lenne, {name}',
    'Van még idő májusig, {name}',
    'Kettessel is élünk, {name}',
  ];

  /// Complete flat list of all 117 fun greeting templates (for auditing/tests).
  static List<String> get allFunTemplates => List<String>.unmodifiable([
        ...earlyMorningPool,
        ...morningPool,
        ...schoolDayPool,
        ...afternoonPool,
        ...eveningDailyPool,
        eveningSchoolTomorrowTemplate,
        ...lateNightPool,
        ...mondayPool,
        ...fridayPool,
        ...weekendPool,
        ...sundayEveningPool,
        ...generalPool,
      ]);

  static Random _random = Random();
  static String? _cachedTemplate;
  static String? _lastShownTemplate;

  static const String funFactsAssetPath = 'assets/data/useless_fun_facts.json';
  static List<String>? _cachedFunFacts;
  static Future<List<String>>? _loadingFunFactsFuture;
  static String? _currentFunFact;
  static final List<String> _recentFunFacts = <String>[];

  /// Lazily loads the offline Hungarian fun fact dataset from [funFactsAssetPath]
  /// and initializes a session random pick if none is active yet.
  static Future<List<String>> ensureFunFactsLoaded({
    AssetBundle? bundle,
  }) async {
    if (_cachedFunFacts != null && _cachedFunFacts!.isNotEmpty) {
      _currentFunFact ??= pickFunFact();
      return _cachedFunFacts!;
    }
    if (_loadingFunFactsFuture != null && bundle == null) {
      return _loadingFunFactsFuture!;
    }
    final loader = () async {
      try {
        final raw = await (bundle ?? rootBundle).loadString(funFactsAssetPath);
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final parsed = decoded
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(growable: false);
          if (parsed.isNotEmpty) {
            _cachedFunFacts = parsed;
            _currentFunFact ??= pickFunFact();
            return parsed;
          }
        }
      } catch (_) {}
      return const <String>[];
    }();
    if (bundle == null) {
      _loadingFunFactsFuture = loader.whenComplete(() {
        _loadingFunFactsFuture = null;
      });
      return _loadingFunFactsFuture!;
    }
    return loader;
  }

  /// Returns whether the fun facts dataset is currently loaded in memory.
  static bool get hasFunFactsLoaded =>
      _cachedFunFacts != null && _cachedFunFacts!.isNotEmpty;

  /// Returns the current session fun fact, or selects a fresh non-repeating
  /// random fact when [forceRefresh] is `true`.
  static String? pickFunFact({bool forceRefresh = false}) {
    final facts = _cachedFunFacts;
    if (facts == null || facts.isEmpty) return null;
    if (!forceRefresh && _currentFunFact != null) {
      return _currentFunFact;
    }
    if (facts.length == 1) {
      _currentFunFact = facts.first;
      return _currentFunFact;
    }
    final recentSet = _recentFunFacts.toSet();
    var candidates = facts
        .where((f) => f != _currentFunFact && !recentSet.contains(f))
        .toList();
    if (candidates.isEmpty) {
      _recentFunFacts.clear();
      candidates = facts.where((f) => f != _currentFunFact).toList();
    }
    final pool = candidates.isNotEmpty ? candidates : facts;
    final picked = pool[_random.nextInt(pool.length)];
    _currentFunFact = picked;
    _recentFunFacts.add(picked);
    if (_recentFunFacts.length > 30) {
      _recentFunFacts.removeAt(0);
    }
    return picked;
  }

  /// Clears the cached greeting for the current app session (called only when
  /// toggling Fun Greetings in Settings) while remembering the previous template
  /// so the next selection never repeats twice in a row.
  static void refreshSessionGreeting() {
    _cachedTemplate = null;
  }

  /// Resets in-memory session cache and optionally injects a deterministic [random].
  @visibleForTesting
  static void resetForTesting({
    Random? random,
    List<String>? funFacts,
  }) {
    _random = random ?? Random();
    _cachedTemplate = null;
    _lastShownTemplate = null;
    _currentFunFact = null;
    _recentFunFacts.clear();
    _loadingFunFactsFuture = null;
    _cachedFunFacts = funFacts;
  }

  static const List<String> _monthsHuCapitalized = [
    'Január',
    'Február',
    'Március',
    'Április',
    'Május',
    'Június',
    'Július',
    'Augusztus',
    'Szeptember',
    'Október',
    'November',
    'December',
  ];

  static const List<String> _weekdaysHuLower = [
    '',
    'hétfő',
    'kedd',
    'szerda',
    'csütörtök',
    'péntek',
    'szombat',
    'vasárnap',
  ];

  /// Formats [now] in clean Hungarian date notation (e.g., `"November 23., hétfő"`).
  static String formatHungarianDateSubtitle(DateTime now) {
    final local = now.toLocal();
    final month = _monthsHuCapitalized[(local.month - 1).clamp(0, 11)];
    final weekday = _weekdaysHuLower[local.weekday.clamp(1, 7)];
    return '$month ${local.day}., $weekday';
  }

  /// Builds the `"Mikor végzel ma"` subtitle from today's non-cancelled lessons.
  static String buildFinishTimeSubtitle(
    List<Lesson> lessons,
    DateTime now, {
    bool hasLoadedData = true,
  }) {
    final localNow = now.toLocal();
    final todayDate = DateUtils.dateOnly(localNow);
    final activeToday = lessons
        .where(
          (l) =>
              DateUtils.dateOnly(l.start.toLocal()) == todayDate &&
              !isLessonCancelled(l) &&
              !isInactivePlaceholderLesson(l),
        )
        .toList();
    if (activeToday.isEmpty) {
      return hasLoadedData
          ? 'Ma nincs tanítás'
          : formatHungarianDateSubtitle(localNow);
    }
    var lastEnd = activeToday.first.end.toLocal();
    for (final lesson in activeToday.skip(1)) {
      final candidate = lesson.end.toLocal();
      if (candidate.isAfter(lastEnd)) {
        lastEnd = candidate;
      }
    }
    if (!lastEnd.isAfter(localNow)) {
      return 'Mára végeztél';
    }
    final hh = lastEnd.hour.toString().padLeft(2, '0');
    final mm = lastEnd.minute.toString().padLeft(2, '0');
    return 'Ma $hh:$mm-kor végzel';
  }

  /// Builds the `"Holnapi számonkérések"` subtitle from Kréta tests scheduled for tomorrow.
  static String buildTomorrowExamsSubtitle(List<Test> tests, DateTime now) {
    final tomorrowDate =
        DateUtils.dateOnly(now.toLocal()).add(const Duration(days: 1));
    final seenIds = <String>{};
    var count = 0;
    for (final test in tests) {
      if (DateUtils.dateOnly(test.date.toLocal()) != tomorrowDate) continue;
      final uid = test.uid.trim();
      if (uid.isNotEmpty) {
        if (!seenIds.add(uid)) continue;
      }
      count++;
    }
    if (count == 0) return 'Holnap nincs számonkérés';
    return 'Holnap $count számonkérésed lesz';
  }

  /// Resolves the greeting subtitle text for the configured [mode], returning
  /// `null` when hidden or empty.
  static String? buildGreetingSubtitle({
    required GreetingSubtitleMode mode,
    required DateTime now,
    List<Lesson> todaysLessons = const <Lesson>[],
    List<Test> tests = const <Test>[],
    bool hasLoadedData = true,
    String? schoolName,
    bool? uwuMode,
  }) {
    final isUwu = uwuMode ?? UwuHelper.isEnabled;
    final String? raw;
    switch (mode) {
      case GreetingSubtitleMode.finishTime:
        raw = buildFinishTimeSubtitle(
          todaysLessons,
          now,
          hasLoadedData: hasLoadedData,
        );
      case GreetingSubtitleMode.date:
        raw = formatHungarianDateSubtitle(now);
      case GreetingSubtitleMode.tomorrowExams:
        raw = buildTomorrowExamsSubtitle(tests, now);
      case GreetingSubtitleMode.funFacts:
        raw = pickFunFact() ?? formatHungarianDateSubtitle(now);
      case GreetingSubtitleMode.schoolName:
        final clean = schoolName?.trim() ?? '';
        raw = clean.isEmpty ? null : clean;
      case GreetingSubtitleMode.none:
        raw = null;
    }
    if (raw == null || raw.isEmpty) return null;
    return isUwu ? UwuHelper.transform(raw, enabled: true) : raw;
  }

  /// Resolves the display name for the greeting:
  /// 1. Uses [customNickname] if non-empty.
  /// 2. Extracts the first/given name from [fullStudentName] if available
  ///    (in Hungarian "Vezetéknév Keresztnév" order, the given name is the second token).
  /// 3. Falls back to [defaultFirstName] ("Diák").
  static String resolveDisplayName({
    String? customNickname,
    String? fullStudentName,
    String defaultFirstName = 'Diák',
  }) {
    final trimmedNick = customNickname?.trim() ?? '';
    if (trimmedNick.isNotEmpty) {
      return trimmedNick;
    }

    final trimmedFull = fullStudentName?.trim() ?? '';
    if (trimmedFull.isNotEmpty) {
      final parts = trimmedFull
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty && !p.endsWith('.'))
          .toList();
      if (parts.length >= 2) {
        return parts[1];
      }
      if (parts.isNotEmpty) {
        return parts.first;
      }
    }

    return defaultFirstName;
  }

  /// Identifies the tight greeting bucket key for [now] so session caching
  /// automatically refreshes when entering a new time/day window.
  static String timeWindowBucketFor(DateTime now) {
    final local = now.toLocal();
    final mins = local.hour * 60 + local.minute;
    final weekday = local.weekday;
    final isWeekday = weekday >= DateTime.monday && weekday <= DateTime.friday;

    if (mins >= 22 * 60 || mins <= 4 * 60 + 59) {
      return 'late_night';
    }
    if (!isWeekday) {
      if (weekday == DateTime.sunday && mins >= 18 * 60) {
        return mins >= 18 * 60 + 30
            ? 'sunday_evening_late'
            : 'sunday_evening_early';
      }
      return mins >= 18 * 60 + 30 ? 'weekend_evening' : 'weekend_day';
    }
    if (mins <= 7 * 60 + 45) return 'early_morning';
    if (mins <= 9 * 60 + 59) return 'morning';
    if (mins <= 14 * 60 + 29) return 'school_day';
    if (mins <= 18 * 60 + 29) return 'afternoon';
    return 'evening';
  }

  /// Returns all fun greeting templates eligible for [now], enforcing the
  /// weekday-only school guard and tight time-of-day windows.
  static List<String> eligibleFunTemplatesFor(DateTime now) {
    final local = now.toLocal();
    final weekday = local.weekday;
    final isWeekday = weekday >= DateTime.monday && weekday <= DateTime.friday;
    final mins = local.hour * 60 + local.minute;

    final eligible = <String>[...generalPool];

    // Late Night (Daily 22:00 - 04:59 ONLY)
    if (mins >= 22 * 60 || mins <= 4 * 60 + 59) {
      eligible.addAll(lateNightPool);
      return eligible;
    }

    // Daytime & Evening (05:00 - 21:59)
    if (isWeekday) {
      if (mins <= 7 * 60 + 45) {
        eligible.addAll(earlyMorningPool);
      } else if (mins <= 9 * 60 + 59) {
        eligible.addAll(morningPool);
      } else if (mins <= 14 * 60 + 29) {
        eligible.addAll(schoolDayPool);
      } else if (mins <= 18 * 60 + 29) {
        eligible.addAll(afternoonPool);
      }
      if (weekday == DateTime.monday) {
        eligible.addAll(mondayPool);
      } else if (weekday == DateTime.friday) {
        eligible.addAll(fridayPool);
      }
    } else {
      if (weekday == DateTime.saturday) {
        eligible.addAll(weekendPool);
      } else if (weekday == DateTime.sunday) {
        if (mins <= 17 * 60 + 59) {
          eligible.addAll(weekendPool);
        } else {
          eligible.addAll(sundayEveningPool);
        }
      }
    }

    // Evening (Daily 18:30 - 21:59)
    if (mins >= 18 * 60 + 30 && mins <= 21 * 60 + 59) {
      eligible.addAll(eveningDailyPool);
      if (weekday != DateTime.friday && weekday != DateTime.saturday) {
        eligible.add(eveningSchoolTomorrowTemplate);
      }
    }

    return eligible;
  }

  /// Returns the dynamic Hungarian greeting based on [now].
  ///
  /// When [funGreetingsEnabled] is `false` (default):
  /// * 04:00 - 07:59: `"Szép reggelt, <name>!"`
  /// * 08:00 - 17:59: `"Szép napot, <name>!"`
  /// * 18:00 - 21:59: `"Szép estét, <name>!"`
  /// * 22:00 - 03:59: `"Jó éjszakát, <name>!"`
  ///
  /// When [funGreetingsEnabled] is `true`, selects from [eligibleFunTemplatesFor],
  /// stabilizes the greeting across rebuilds for the active session/time-window,
  /// and avoids repeating the previous greeting on refresh.
  ///
  /// Supports `UwU mód` dialogue overrides and `Fun üdvözlő üzenetek`.
  static String buildGreeting({
    required String name,
    DateTime? now,
    bool? uwuMode,
    bool funGreetingsEnabled = false,
    bool forceRefresh = false,
  }) {
    final cleanName = name.trim().isEmpty ? 'Diák' : name.trim();
    final isUwu = uwuMode ?? UwuHelper.isEnabled;
    final local = (now ?? DateTime.now()).toLocal();
    final hour = local.hour;

    if (funGreetingsEnabled) {
      final String template;
      if (!forceRefresh && _cachedTemplate != null) {
        template = _cachedTemplate!;
      } else {
        final candidates = eligibleFunTemplatesFor(local);
        final nonRepeating = candidates.length > 1 && _lastShownTemplate != null
            ? candidates.where((t) => t != _lastShownTemplate).toList()
            : candidates;
        final pool = nonRepeating.isNotEmpty ? nonRepeating : candidates;
        template = pool[_random.nextInt(pool.length)];
        _cachedTemplate = template;
        _lastShownTemplate = template;
      }
      final raw = template.replaceAll('{name}', cleanName);
      if (isUwu) {
        return UwuHelper.transform(raw, enabled: true);
      }
      return raw;
    }

    if (isUwu) {
      final uwuName =
          UwuHelper.transform(cleanName, enabled: true)
              .replaceAll(RegExp(r'\s+(uwu|:3|owo|>w<|nya~)$'), '');
      if (hour >= 4 && hour <= 7) {
        return 'Szép weggewt, $uwuName! nya~';
      } else if (hour >= 8 && hour <= 17) {
        return 'Szép nyapot, $uwuName! uwu';
      } else if (hour >= 18 && hour <= 21) {
        return 'Szép estét, $uwuName! >w<';
      } else {
        return 'Jó éccakát, $uwuName! :3';
      }
    }

    if (hour >= 4 && hour <= 7) {
      return 'Szép reggelt, $cleanName!';
    } else if (hour >= 8 && hour <= 17) {
      return 'Szép napot, $cleanName!';
    } else if (hour >= 18 && hour <= 21) {
      return 'Szép estét, $cleanName!';
    } else {
      return 'Jó éjszakát, $cleanName!';
    }
  }
}
