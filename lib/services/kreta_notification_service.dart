import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/period_countdown_badge.dart';
import 'demo_data_service.dart';
import 'kreta_client.dart';
import 'token_storage_service.dart';

const String kKretaNotificationChannelName =
    'hu.mlnlbrt.tintanaplo/notifications';
const String kKretaNotificationConfigPrefsKey = 'kreta_notification_config_v1';
const String kKretaNotificationSnapshotPrefsKey =
    'kreta_notification_snapshot_v1';

/// Supported instant Kréta change notification categories.
enum KretaNotificationCategory {
  newGrade(
    keyName: 'newGrade',
    label: 'Új jegy',
    subtitle: 'Értesítés új érdemjegy vagy értékelés beírásakor',
    icon: Icons.star_rounded,
    accentColor: Color(0xFF22C55E),
    defaultTitle: 'Új jegy: {grade} ({subject})',
    defaultBody: '{topic} • Súly: {weight} • {teacher}',
  ),
  newExam(
    keyName: 'newExam',
    label: 'Új számonkérés',
    subtitle: 'Értesítés új bejelentett dolgozatról vagy felelésről',
    icon: Icons.assignment_outlined,
    accentColor: Color(0xFFF59E0B),
    defaultTitle: 'Új számonkérés: {subject}',
    defaultBody: '{topic} • {date} ({lesson_number}. óra) • {teacher}',
  ),
  cancelledLesson(
    keyName: 'cancelledLesson',
    label: 'Elmaradt óra',
    subtitle: 'Értesítés elmaradó vagy törölt tanóra esetén',
    icon: Icons.event_busy_rounded,
    accentColor: Color(0xFFEF4444),
    defaultTitle: 'Elmaradt óra: {subject}',
    defaultBody: '{date} • {lesson_number}. óra • Terem: {room}',
  ),
  substitution(
    keyName: 'substitution',
    label: 'Helyettesítés',
    subtitle: 'Értesítés helyettesítő tanár beírásakor',
    icon: Icons.swap_horiz_rounded,
    accentColor: Color(0xFF3B82F6),
    defaultTitle: 'Helyettesítés: {subject}',
    defaultBody:
        '{lesson_number}. óra • Helyettesítő: {substitute_teacher} • Terem: {room}',
  ),
  lateArrival(
    keyName: 'lateArrival',
    label: 'Késés',
    subtitle: 'Értesítés új késés rögzítésekor',
    icon: Icons.schedule_rounded,
    accentColor: Color(0xFFF97316),
    defaultTitle: 'Késés: {subject} ({minutes} perc)',
    defaultBody: '{date} • {lesson_number}. óra • {teacher}',
  ),
  absence(
    keyName: 'absence',
    label: 'Hiányzás',
    subtitle: 'Értesítés új órai hiányzás rögzítésekor',
    icon: Icons.person_off_rounded,
    accentColor: Color(0xFFEC4899),
    defaultTitle: 'Hiányzás: {subject}',
    defaultBody: '{date} • {lesson_number}. óra • {excused_status} ({type})',
  ),
  newMessage(
    keyName: 'newMessage',
    label: 'Új üzenet',
    subtitle: 'Értesítés új olvasatlan KRÉTA üzenet érkezésekor',
    icon: Icons.mark_email_unread_rounded,
    accentColor: Color(0xFF8B5CF6),
    defaultTitle: 'Új üzenet: {sender}',
    defaultBody: '{title} • {preview}',
  );

  final String keyName;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final String defaultTitle;
  final String defaultBody;

  const KretaNotificationCategory({
    required this.keyName,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.defaultTitle,
    required this.defaultBody,
  });

  List<String> get recommendedPlaceholderTokens {
    switch (this) {
      case KretaNotificationCategory.newGrade:
        return const [
          '{subject}',
          '{grade}',
          '{weight}',
          '{teacher}',
          '{date}',
          '{topic}',
        ];
      case KretaNotificationCategory.newExam:
        return const [
          '{subject}',
          '{topic}',
          '{date}',
          '{lesson_number}',
          '{teacher}',
        ];
      case KretaNotificationCategory.cancelledLesson:
        return const [
          '{subject}',
          '{date}',
          '{lesson_number}',
          '{room}',
          '{teacher}',
          '{topic}',
        ];
      case KretaNotificationCategory.substitution:
        return const [
          '{subject}',
          '{substitute_teacher}',
          '{lesson_number}',
          '{room}',
          '{date}',
          '{teacher}',
        ];
      case KretaNotificationCategory.lateArrival:
        return const [
          '{subject}',
          '{minutes}',
          '{date}',
          '{lesson_number}',
          '{excused_status}',
          '{teacher}',
        ];
      case KretaNotificationCategory.absence:
        return const [
          '{subject}',
          '{date}',
          '{lesson_number}',
          '{excused_status}',
          '{type}',
          '{teacher}',
        ];
      case KretaNotificationCategory.newMessage:
        return const [
          '{sender}',
          '{title}',
          '{preview}',
          '{date}',
        ];
    }
  }

  static KretaNotificationCategory? fromKey(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final cat in values) {
      if (cat.keyName == raw || cat.name == raw) return cat;
    }
    return null;
  }
}

/// Supported template placeholders and their Hungarian descriptions.
class NotificationPlaceholderSpec {
  final String token;
  final String label;

  const NotificationPlaceholderSpec(this.token, this.label);
}

const List<NotificationPlaceholderSpec> kNotificationPlaceholders = [
  NotificationPlaceholderSpec('{subject}', 'Tantárgy'),
  NotificationPlaceholderSpec('{grade}', 'Jegy'),
  NotificationPlaceholderSpec('{weight}', 'Súlyozás'),
  NotificationPlaceholderSpec('{teacher}', 'Tanár'),
  NotificationPlaceholderSpec('{room}', 'Terem'),
  NotificationPlaceholderSpec('{date}', 'Dátum'),
  NotificationPlaceholderSpec('{topic}', 'Téma / Típus'),
  NotificationPlaceholderSpec('{substitute_teacher}', 'Helyettesítő tanár'),
  NotificationPlaceholderSpec('{lesson_number}', 'Óraszám'),
  NotificationPlaceholderSpec('{minutes}', 'Késés (perc)'),
  NotificationPlaceholderSpec('{excused_status}', 'Igazolás állapota'),
  NotificationPlaceholderSpec('{type}', 'Típus'),
  NotificationPlaceholderSpec('{sender}', 'Feladó'),
  NotificationPlaceholderSpec('{title}', 'Üzenet tárgya'),
  NotificationPlaceholderSpec('{preview}', 'Előnézet'),
];

/// Optional per-grade (`1`..`5`) custom notification template overrides.
/// Blank fields automatically fall back to the default `newGrade` template.
enum GradeLabelKind {
  personaOrAdjective,
  gradeObject,
  miniPhrase,
}

/// Hungarian linguistic & grammatical context engine for notification labels.
///
/// Turns brief custom grade labels (`"bad boy"`, `"király"`, `"karó"`,
/// `"ötös"`, `"ez nem jött össze"`, `"főztem"`) plus arbitrary school subject
/// names (`"Matematika"`, `"Történelem"`, `"Hálózatok I."`) into natural,
/// grammatically inflected Hungarian notification sentences.
class HungarianNotificationLinguistics {
  HungarianNotificationLinguistics._();

  static const Set<String> _frontVowels = {'e', 'é', 'i', 'í', 'ö', 'ő', 'ü', 'ű'};
  static const Set<String> _frontRoundedVowels = {'ö', 'ő', 'ü', 'ű'};
  static const Set<String> _backVowels = {'a', 'á', 'o', 'ó', 'u', 'ú'};

  static const List<String> _frontCompoundTails = [
    'nevelés',
    'kezelés',
    'fejlesztés',
    'tesztelés',
    'tervezés',
    'szerkesztés',
    'elemzés',
    'mérés',
    'képzés',
    'védelem',
    'elmélet',
    'történet',
    'történelem',
    'ismeret',
    'ismeretek',
    'rendszer',
    'rendszerek',
    'főnöki',
    'főnökök',
    'főnök',
    'nyelvek',
    'nyelvi',
    'nyelv',
    'kör',
    'ügy',
    'zene',
  ];

  static const List<String> _backCompoundTails = [
    'rajz',
    'tan',
    'tudomány',
    'gyakorlat',
    'munka',
    'irodalom',
    'programozás',
    'adatbázis',
    'alkalmazás',
    'technika',
    'elektronika',
    'informatika',
    'matematika',
    'fizika',
    'kémia',
    'biológia',
    'grafika',
    'statisztika',
    'etika',
    'dráma',
    'média',
    'kultúra',
    'hálózatok',
    'hálózat',
    'szolgálat',
    'számtan',
    'mértan',
  ];

  static const Set<String> _personaKeywords = {
    'bad boy',
    'király',
    'zseni',
    'profi',
    'legenda',
    'clutch',
    'béna',
    'gyenge',
    'bot',
    'npc',
    'goat',
    'császár',
    'mágus',
    'ász',
    'bajnok',
    'hős',
    'szuperhős',
    'főnök',
    'boss',
    'king',
    'queen',
    'god',
    'sigma',
    'alpha',
    'gigachad',
    'chad',
    'lúzer',
    'kuka',
    'amatőr',
    'kezdő',
    'menő',
    'brutál',
    'kemény',
    'erős',
    'top',
    'elit',
    'elite',
    'sztár',
    'star',
    'zseniális',
    'szuper',
    'tökéletes',
    'mester',
    'isten',
    'best',
    'mvp',
    'carry',
    'okos',
    'ügyes',
    'bátor',
    'lusta',
    'rosszfiú',
    'gengszter',
    'noob',
    'pro',
    'gyilkos',
    'terminátor',
    'monstre',
    'monsta',
    'nagyon jó',
    'szép',
    'csúnya',
  };

  static const Set<String> _positivePersonas = {
    'király',
    'zseni',
    'profi',
    'legenda',
    'clutch',
    'goat',
    'császár',
    'mágus',
    'ász',
    'bajnok',
    'hős',
    'szuperhős',
    'boss',
    'king',
    'queen',
    'god',
    'sigma',
    'alpha',
    'gigachad',
    'chad',
    'menő',
    'brutál',
    'top',
    'elit',
    'elite',
    'sztár',
    'star',
    'zseniális',
    'szuper',
    'tökéletes',
    'mester',
    'isten',
    'best',
    'mvp',
    'carry',
    'okos',
    'ügyes',
    'pro',
    'nagyon jó',
  };

  static const Set<String> _gradeObjectKeywords = {
    'karó',
    'ötös',
    'négyes',
    'hármas',
    'kettes',
    'egyes',
    'csillagos ötös',
    'kampó',
    'bukta',
    'bukó',
    'pipa',
    'jeles',
    'jó',
    'közepes',
    'elégséges',
    'elégtelen',
    'dicséret',
    'százalék',
    'jegy',
    'pont',
    'piros pont',
    'fekete pont',
    'pacsi',
    'medál',
    'arany',
    'ezüst',
    'bronz',
    'trófea',
    'serleg',
    'kupa',
    'korona',
    'jutalom',
    'bomba',
    'rakéta',
    'intő',
    'szaktanári',
    'nyakleves',
    'csillag',
    'szívecske',
    'nulla',
    'nullás',
    '1',
    '2',
    '3',
    '4',
    '5',
    '1-es',
    '2-es',
    '3-as',
    '4-es',
    '5-ös',
    'w',
    'l',
  };

  static const Map<String, String> _digitToGradeWord = {
    '1': 'egyes',
    '2': 'kettes',
    '3': 'hármas',
    '4': 'négyes',
    '5': 'ötös',
  };

  static const Map<String, String> _accusativeIrregulars = {
    'ötös': 'ötöst',
    'négyes': 'négyest',
    'hármas': 'hármast',
    'kettes': 'kettest',
    'egyes': 'egyest',
    'jeles': 'jelest',
    'közepes': 'közepest',
    'elégséges': 'elégségest',
    'elégtelen': 'elégtelent',
    'százalék': 'százalékot',
    'jegy': 'jegyet',
    'pont': 'pontot',
    'dicséret': 'dicséretet',
    'csillag': 'csillagot',
    'nullás': 'nullást',
    'nyakleves': 'nyaklevest',
    'játék': 'játékot',
    'w': 'W-t',
    'l': 'L-t',
  };

  /// Strips parenthetical tags and trailing Roman/Arabic course numerals
  /// (`Hálózatok I.` -> `Hálózatok`, `Matematika (emelt)` -> `Matematika`).
  static String cleanSubjectStem(String rawSubject) {
    var s = rawSubject.trim();
    if (s.isEmpty) return 'tantárgy';

    // Strip parenthetical clarifications such as "(emelt)", "(szakmai)".
    s = s.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();

    // Strip trailing Roman numerals preceded by space (e.g. "Hálózatok I.", "Angol II").
    s = s.replaceAll(
      RegExp(r'\s+(?:X{0,2}(?:IX|IV|V?I{0,3}))\.?$', caseSensitive: true),
      '',
    ).trim();

    // Strip trailing Arabic module/year numbers preceded by space (e.g. "IKT 2.").
    s = s.replaceAll(RegExp(r'\s+\d+\.?$'), '').trim();

    // Strip leftover trailing punctuation.
    s = s.replaceAll(RegExp(r'[.,:;/-]+\s*$'), '').trim();
    return s.isEmpty ? 'tantárgy' : s;
  }

  /// Determines `-ból` vs `-ből` for the final constituent word of a Hungarian
  /// subject name, respecting compound tails and neutral/front harmony.
  static bool _usesBackHarmony(String wordLower) {
    if (wordLower.isEmpty) return true;

    for (final tail in _frontCompoundTails) {
      if (wordLower == tail || wordLower.endsWith(tail)) {
        return false;
      }
    }
    for (final tail in _backCompoundTails) {
      if (wordLower == tail || wordLower.endsWith(tail)) {
        return true;
      }
    }

    var hasBack = false;
    var hasFrontRounded = false;
    var lastSignificantIsBack = false;
    var sawSignificant = false;

    for (var i = 0; i < wordLower.length; i++) {
      final ch = wordLower[i];
      if (_backVowels.contains(ch)) {
        hasBack = true;
        lastSignificantIsBack = true;
        sawSignificant = true;
      } else if (_frontRoundedVowels.contains(ch)) {
        hasFrontRounded = true;
        lastSignificantIsBack = false;
        sawSignificant = true;
      } else if (_frontVowels.contains(ch)) {
        // Unrounded front/neutral vowel (`e, é, i, í`): don't override a
        // previously seen back vowel in mixed words like `matek` or `fizika`
        // unless there are NO back vowels at all.
      }
    }

    if (sawSignificant) return lastSignificantIsBack;
    if (hasFrontRounded) return false;
    if (hasBack) return true;
    return false;
  }

  /// Applies Hungarian elative (`-ból` / `-ből`) suffixation with vowel
  /// lengthening (`a→á`, `e→é`) to a school subject name.
  static String formatSubjectElative(String rawSubject) {
    final stem = cleanSubjectStem(rawSubject);
    final parts = stem.split(RegExp(r'[\s-]+'));
    final lastWord = parts.isNotEmpty ? parts.last.toLowerCase() : stem.toLowerCase();
    final isBack = _usesBackHarmony(lastWord);
    final suffix = isBack ? 'ból' : 'ből';

    if (stem.isEmpty) return 'tantárgyból';

    // Handle all-caps short acronyms without vowels like "IT" or "PE".
    final lettersOnly = stem.toLowerCase().replaceAll(RegExp(r'[^a-zA-ZáéíóöőúüűÁÉÍÓÖŐÚÜŰ]'), '');
    final hasAnyVowel = lettersOnly.split('').any(
      (c) => _backVowels.contains(c) || _frontVowels.contains(c),
    );
    if (!hasAnyVowel) {
      // e.g. "C#" or "PE"-style edge case without vowels.
      final lastCh = lettersOnly.isNotEmpty ? lettersOnly[lettersOnly.length - 1] : '';
      final frontAcronym = lastCh == 'b' || lastCh == 'c' || lastCh == 'd' || lastCh == 'e' ||
          lastCh == 'g' || lastCh == 'p' || lastCh == 't' || lastCh == 'v' || lastCh == 'w' ||
          lastCh == 'y' || lastCh == 'z' || lastCh == 'f' || lastCh == 'l' || lastCh == 'm' ||
          lastCh == 'n' || lastCh == 'r' || lastCh == 's' || lastCh == 'x';
      return '$stem-${frontAcronym ? 'ből' : 'ból'}';
    }

    final lastChar = stem.substring(stem.length - 1);
    final prefix = stem.substring(0, stem.length - 1);
    if (lastChar == 'a') return '$prefix' 'á$suffix';
    if (lastChar == 'A') return '$prefix' 'Á$suffix';
    if (lastChar == 'e') return '$prefix' 'é$suffix';
    if (lastChar == 'E') return '$prefix' 'É$suffix';
    return '$stem$suffix';
  }

  /// Applies Hungarian accusative (`-t/-ot/-et/-öt`) with final vowel
  /// lengthening (`a→át`, `e→ét`) to a grade noun or noun phrase.
  static String formatAccusative(String rawPhrase) {
    var clean = rawPhrase.trim().replaceAll(RegExp(r'[.!?]+$'), '').trim();
    if (clean.isEmpty) return clean;

    final lowerWhole = clean.toLowerCase();
    if (_digitToGradeWord.containsKey(lowerWhole)) {
      clean = _digitToGradeWord[lowerWhole]!;
    } else if (lowerWhole == '1-es') {
      return '1-est';
    } else if (lowerWhole == '2-es') {
      return '2-est';
    } else if (lowerWhole == '3-as') {
      return '3-ast';
    } else if (lowerWhole == '4-es') {
      return '4-est';
    } else if (lowerWhole == '5-ös') {
      return '5-öst';
    }

    final words = clean.split(RegExp(r'\s+'));
    final lastOrig = words.last;
    final lastLower = lastOrig.toLowerCase();

    String inflectedLast;
    if (_accusativeIrregulars.containsKey(lastLower)) {
      final base = _accusativeIrregulars[lastLower]!;
      inflectedLast = _preserveLeadingCase(lastOrig, base);
    } else if (lastLower.endsWith('a')) {
      inflectedLast = '${lastOrig.substring(0, lastOrig.length - 1)}${lastOrig.endsWith('A') ? 'Át' : 'át'}';
    } else if (lastLower.endsWith('e')) {
      inflectedLast = '${lastOrig.substring(0, lastOrig.length - 1)}${lastOrig.endsWith('E') ? 'Ét' : 'ét'}';
    } else if (RegExp(r'[áéíiíoóöőuúüű]$', caseSensitive: false).hasMatch(lastLower)) {
      inflectedLast = '${lastOrig}t';
    } else if (RegExp(r'(?:ly|ny|sz|zs|j|l|n|r|s|z)$', caseSensitive: false).hasMatch(lastLower)) {
      inflectedLast = '${lastOrig}t';
    } else {
      final isBack = _usesBackHarmony(lastLower);
      if (isBack) {
        inflectedLast = '${lastOrig}ot';
      } else {
        // Check last vowel for front-rounded harmony (`ö, ő, ü, ű` -> `-öt`).
        var rounded = false;
        for (var i = lastLower.length - 1; i >= 0; i--) {
          final ch = lastLower[i];
          if (_frontRoundedVowels.contains(ch)) {
            rounded = true;
            break;
          }
          if (_frontVowels.contains(ch) || _backVowels.contains(ch)) {
            break;
          }
        }
        inflectedLast = '$lastOrig${rounded ? 'öt' : 'et'}';
      }
    }

    if (words.length == 1) return inflectedLast;
    return '${words.sublist(0, words.length - 1).join(' ')} $inflectedLast';
  }

  /// Classifies a custom grade label into persona/adjective, grade-object noun,
  /// or full mini-phrase / exclamation.
  static GradeLabelKind classifyGradeLabel(String rawLabel) {
    final normalized = rawLabel
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return GradeLabelKind.gradeObject;

    if (_gradeObjectKeywords.contains(normalized)) {
      return GradeLabelKind.gradeObject;
    }
    if (_personaKeywords.contains(normalized)) {
      return GradeLabelKind.personaOrAdjective;
    }

    // Verbs / clauses / exclamations -> miniPhrase.
    final words = normalized.split(' ');
    final looksLikeVerbOrClause = RegExp(
      r'\b(vagyok|vagy|volt|lett|lettem|voltál|főztem|buktam|jött|össze|sikerült|megvan|meglett|ez|nem|jaj|rip|gg|bro)\b',
    ).hasMatch(normalized);
    if (looksLikeVerbOrClause || words.length >= 3) {
      return GradeLabelKind.miniPhrase;
    }
    if (words.length == 2) {
      // Second word ending in a grade noun -> gradeObject (e.g. "dupla karó").
      if (_gradeObjectKeywords.contains(words.last)) {
        return GradeLabelKind.gradeObject;
      }
      if (_personaKeywords.contains(words.last)) {
        return GradeLabelKind.personaOrAdjective;
      }
      // Common two-word slang/phrases default to miniPhrase unless adj+noun persona.
      if (RegExp(r'(?:em|am|om|tem|tam|tál|tél|ok|ek|ök)$').hasMatch(words.last)) {
        return GradeLabelKind.miniPhrase;
      }
      return GradeLabelKind.personaOrAdjective;
    }

    // Single unknown word heuristics:
    // Adjectives in `-os/-es/-ös/-as/-telen/-talan` except grade nouns -> personaOrAdjective.
    if (RegExp(r'(?:telen|talan|ságos|séges|iális|ális|i)$').hasMatch(normalized)) {
      return GradeLabelKind.personaOrAdjective;
    }
    if (RegExp(r'(?:tem|tam|tál|tél|sz|ok|ek|ök)$').hasMatch(normalized) &&
        normalized.length > 4) {
      return GradeLabelKind.miniPhrase;
    }
    // Single concrete nouns ending in -ó / -ő / -a / -e / -t / -gy are likely objects
    // if user uses them as grade nicknames ("karó", "bomba", "csillag"), while
    // persona words were already caught above.
    if (RegExp(r'(?:ó|ő|a|e)$').hasMatch(normalized)) {
      return GradeLabelKind.gradeObject;
    }
    return GradeLabelKind.personaOrAdjective;
  }

  /// Generates natural idiomatic Hungarian body copy from a user's label (or
  /// legacy `{placeholder}` template) and subject name.
  static String buildGradeNotificationBody({
    required String labelOrTemplate,
    required String subjectName,
    int? gradeValue,
    Map<String, String>? legacyValues,
  }) {
    final trimmed = labelOrTemplate.trim();
    if (trimmed.contains('{') && trimmed.contains('}')) {
      return KretaNotificationService.renderTemplate(
        trimmed,
        legacyValues ?? const <String, String>{},
      );
    }

    final effectiveLabel = trimmed.isEmpty
        ? _defaultLabelForGrade(gradeValue)
        : trimmed;
    final elative = formatSubjectElative(subjectName);
    final cleanSubject = cleanSubjectStem(subjectName);

    // Preserve explicit trailing ! or ? written by user.
    final explicitPunctMatch = RegExp(r'([!?]+)$').firstMatch(effectiveLabel);
    final explicitPunct = explicitPunctMatch?.group(1) ?? '';
    final labelNoPunct = effectiveLabel.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    if (labelNoPunct.isEmpty) {
      return 'Új értékelés érkezett $elative';
    }

    final normalized = labelNoPunct.toLowerCase();
    final kind = classifyGradeLabel(labelNoPunct);
    final celebratory = explicitPunct.isNotEmpty ||
        _positivePersonas.contains(normalized) ||
        (gradeValue != null &&
            gradeValue >= 5 &&
            kind == GradeLabelKind.personaOrAdjective);

    switch (kind) {
      case GradeLabelKind.personaOrAdjective:
        final cap = _capitalizeFirst(labelNoPunct);
        final punct = explicitPunct.isNotEmpty
            ? explicitPunct
            : (celebratory ? '!' : '');
        return '$cap voltál $elative$punct';

      case GradeLabelKind.gradeObject:
        final acc = _capitalizeFirst(formatAccusative(labelNoPunct));
        return '$acc kaptál $elative$explicitPunct';

      case GradeLabelKind.miniPhrase:
        // Outcome clauses like "ez nem jött össze" / "összejött" flow best as
        // `"Ez nem jött össze Történelemből"`, while verbs/exclamations like
        // `"főztem"` / `"cooked vagyok"` / `"gg ez"` flow cleanly as `"Történelem: főztem"`.
        final fitsOutcomeClause = RegExp(
          r'^(?:ez\s+|nem\s+|összejött|sikerült|megvan|meglett|bevált)',
        ).hasMatch(normalized);
        if (fitsOutcomeClause && !normalized.contains('vagyok')) {
          return '${_capitalizeFirst(labelNoPunct)} $elative$explicitPunct';
        }
        return '$cleanSubject: $labelNoPunct$explicitPunct';
    }
  }

  /// Renders a non-grade category body, supporting both legacy `{tokens}` and
  /// simple user phrases (`"dolgozat lesz"` -> `"Matematika: dolgozat lesz"`).
  static String buildGenericNotificationBody({
    required String labelOrTemplate,
    required String subjectName,
    Map<String, String>? legacyValues,
  }) {
    final trimmed = labelOrTemplate.trim();
    if (trimmed.contains('{') && trimmed.contains('}')) {
      return KretaNotificationService.renderTemplate(
        trimmed,
        legacyValues ?? const <String, String>{},
      );
    }
    if (trimmed.isEmpty) {
      return KretaNotificationService.renderTemplate(
        KretaNotificationCategory.newExam.defaultBody,
        legacyValues ?? const <String, String>{},
      );
    }
    final cleanSubject = cleanSubjectStem(subjectName);
    if (cleanSubject.isEmpty || cleanSubject == 'tantárgy') {
      return _capitalizeFirst(trimmed);
    }
    return '$cleanSubject: $trimmed';
  }

  static String _defaultLabelForGrade(int? gradeValue) {
    switch (gradeValue) {
      case 5:
        return 'ötös';
      case 4:
        return 'négyes';
      case 3:
        return 'hármas';
      case 2:
        return 'kettes';
      case 1:
        return 'egyes';
      default:
        return 'értékelés';
    }
  }

  static String _capitalizeFirst(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }

  static String _preserveLeadingCase(String original, String replacement) {
    if (original.isEmpty || replacement.isEmpty) return replacement;
    if (original == original.toUpperCase() && original.length > 1) {
      return replacement.toUpperCase();
    }
    final first = original[0];
    if (first == first.toUpperCase() && first != first.toLowerCase()) {
      return _capitalizeFirst(replacement);
    }
    return replacement;
  }
}

class GradeNotificationTemplate {
  final String titleTemplate;
  final String bodyTemplate;

  const GradeNotificationTemplate({
    this.titleTemplate = '',
    this.bodyTemplate = '',
  });

  bool get isEmpty =>
      titleTemplate.trim().isEmpty && bodyTemplate.trim().isEmpty;

  GradeNotificationTemplate copyWith({
    String? titleTemplate,
    String? bodyTemplate,
  }) {
    return GradeNotificationTemplate(
      titleTemplate: titleTemplate ?? this.titleTemplate,
      bodyTemplate: bodyTemplate ?? this.bodyTemplate,
    );
  }

  Map<String, dynamic> toJson() => {
        'titleTemplate': titleTemplate,
        'bodyTemplate': bodyTemplate,
      };

  factory GradeNotificationTemplate.fromJson(Map<String, dynamic> json) {
    return GradeNotificationTemplate(
      titleTemplate: json['titleTemplate']?.toString() ?? '',
      bodyTemplate: json['bodyTemplate']?.toString() ?? '',
    );
  }
}

/// Per-category notification toggle and title/body template configuration.
class NotificationCategoryConfig {
  final bool enabled;
  final String titleTemplate;
  final String bodyTemplate;
  final Map<int, GradeNotificationTemplate> gradeTemplates;

  const NotificationCategoryConfig({
    required this.enabled,
    required this.titleTemplate,
    required this.bodyTemplate,
    this.gradeTemplates = const <int, GradeNotificationTemplate>{},
  });

  factory NotificationCategoryConfig.defaultsFor(
    KretaNotificationCategory category,
  ) =>
      NotificationCategoryConfig(
        enabled: true,
        titleTemplate: category.defaultTitle,
        bodyTemplate: category.defaultBody,
      );

  /// Resolves the effective title template for [gradeValue] (`1..5`), falling
  /// back to [titleTemplate] if no per-grade override is set.
  String titleTemplateForGrade(int? gradeValue) {
    if (gradeValue != null) {
      final custom = gradeTemplates[gradeValue]?.titleTemplate;
      if (custom != null && custom.trim().isNotEmpty) {
        return custom;
      }
    }
    return titleTemplate;
  }

  /// Resolves the effective body template for [gradeValue] (`1..5`), falling
  /// back to [bodyTemplate] if no per-grade override is set.
  String bodyTemplateForGrade(int? gradeValue) {
    if (gradeValue != null) {
      final custom = gradeTemplates[gradeValue]?.bodyTemplate;
      if (custom != null && custom.trim().isNotEmpty) {
        return custom;
      }
    }
    return bodyTemplate;
  }

  bool hasCustomGradeTemplate(int gradeValue) {
    final t = gradeTemplates[gradeValue];
    return t != null && !t.isEmpty;
  }

  NotificationCategoryConfig withGradeTemplate(
    int gradeValue,
    GradeNotificationTemplate template,
  ) {
    final next = Map<int, GradeNotificationTemplate>.from(gradeTemplates);
    if (template.isEmpty) {
      next.remove(gradeValue);
    } else {
      next[gradeValue] = template;
    }
    return copyWith(gradeTemplates: next);
  }

  NotificationCategoryConfig copyWith({
    bool? enabled,
    String? titleTemplate,
    String? bodyTemplate,
    Map<int, GradeNotificationTemplate>? gradeTemplates,
  }) {
    return NotificationCategoryConfig(
      enabled: enabled ?? this.enabled,
      titleTemplate: titleTemplate ?? this.titleTemplate,
      bodyTemplate: bodyTemplate ?? this.bodyTemplate,
      gradeTemplates: gradeTemplates ?? this.gradeTemplates,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'titleTemplate': titleTemplate,
        'bodyTemplate': bodyTemplate,
        if (gradeTemplates.isNotEmpty)
          'gradeTemplates': {
            for (final entry in gradeTemplates.entries)
              entry.key.toString(): entry.value.toJson(),
          },
      };

  factory NotificationCategoryConfig.fromJson(
    Map<String, dynamic>? json,
    KretaNotificationCategory category,
  ) {
    final fallback = NotificationCategoryConfig.defaultsFor(category);
    if (json == null) return fallback;
    final rawTitle = json['titleTemplate']?.toString();
    final rawBody = json['bodyTemplate']?.toString();
    final parsedGrades = <int, GradeNotificationTemplate>{};
    final rawGradeMap = json['gradeTemplates'];
    if (rawGradeMap is Map) {
      rawGradeMap.forEach((k, v) {
        final gradeNum = int.tryParse(k.toString());
        if (gradeNum != null && gradeNum >= 1 && gradeNum <= 5 && v is Map) {
          final tpl = GradeNotificationTemplate.fromJson(
            Map<String, dynamic>.from(v),
          );
          if (!tpl.isEmpty) {
            parsedGrades[gradeNum] = tpl;
          }
        }
      });
    }
    return NotificationCategoryConfig(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      titleTemplate:
          (rawTitle == null || rawTitle.trim().isEmpty)
              ? fallback.titleTemplate
              : rawTitle,
      bodyTemplate:
          (rawBody == null || rawBody.trim().isEmpty)
              ? fallback.bodyTemplate
              : rawBody,
      gradeTemplates: Map<int, GradeNotificationTemplate>.unmodifiable(
        parsedGrades,
      ),
    );
  }
}

/// Complete persisted configuration for instant + periodic Kréta notifications.
class KretaNotificationConfig {
  final bool masterEnabled;
  final int backgroundIntervalMinutes;
  final Map<KretaNotificationCategory, NotificationCategoryConfig> categories;

  const KretaNotificationConfig({
    required this.masterEnabled,
    required this.backgroundIntervalMinutes,
    required this.categories,
  });

  factory KretaNotificationConfig.defaults() => KretaNotificationConfig(
        masterEnabled: true,
        backgroundIntervalMinutes: 15,
        categories: {
          for (final cat in KretaNotificationCategory.values)
            cat: NotificationCategoryConfig.defaultsFor(cat),
        },
      );

  NotificationCategoryConfig forCategory(KretaNotificationCategory category) =>
      categories[category] ?? NotificationCategoryConfig.defaultsFor(category);

  bool get anyCategoryEnabled =>
      masterEnabled && categories.values.any((c) => c.enabled);

  KretaNotificationConfig copyWith({
    bool? masterEnabled,
    int? backgroundIntervalMinutes,
    Map<KretaNotificationCategory, NotificationCategoryConfig>? categories,
  }) {
    return KretaNotificationConfig(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      backgroundIntervalMinutes:
          backgroundIntervalMinutes ?? this.backgroundIntervalMinutes,
      categories: categories ?? this.categories,
    );
  }

  KretaNotificationConfig withCategory(
    KretaNotificationCategory category,
    NotificationCategoryConfig config,
  ) {
    final next =
        Map<KretaNotificationCategory, NotificationCategoryConfig>.from(
      categories,
    );
    next[category] = config;
    return copyWith(categories: next);
  }

  Map<String, dynamic> toJson() => {
        'masterEnabled': masterEnabled,
        'backgroundIntervalMinutes': backgroundIntervalMinutes,
        'categories': {
          for (final cat in KretaNotificationCategory.values)
            cat.keyName: forCategory(cat).toJson(),
        },
      };

  factory KretaNotificationConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return KretaNotificationConfig.defaults();
    final rawCats = json['categories'];
    final catsMap = rawCats is Map ? Map<String, dynamic>.from(rawCats) : null;
    final resolved = <KretaNotificationCategory, NotificationCategoryConfig>{};
    for (final cat in KretaNotificationCategory.values) {
      final rawCat = catsMap?[cat.keyName];
      resolved[cat] = NotificationCategoryConfig.fromJson(
        rawCat is Map ? Map<String, dynamic>.from(rawCat) : null,
        cat,
      );
    }
    final rawInterval = (json['backgroundIntervalMinutes'] as num?)?.toInt() ?? 15;
    final safeInterval = rawInterval < 15 ? 15 : rawInterval;
    return KretaNotificationConfig(
      masterEnabled:
          json['masterEnabled'] is bool ? json['masterEnabled'] as bool : true,
      backgroundIntervalMinutes: safeInterval,
      categories: resolved,
    );
  }
}

/// Represents a notification fired during foreground/background diff evaluation.
class TriggeredKretaNotification {
  final int notificationId;
  final KretaNotificationCategory category;
  final String title;
  final String body;

  const TriggeredKretaNotification({
    required this.notificationId,
    required this.category,
    required this.title,
    required this.body,
  });
}

class _AccountNotificationSnapshot {
  final bool initialized;
  final bool omissionsInitialized;
  final bool messagesInitialized;
  final Set<String> gradeIds;
  final Set<String> testIds;
  final Set<String> cancelledLessonIds;
  final Set<String> substitutedLessonIds;
  final Set<String> lateArrivalIds;
  final Set<String> absenceIds;
  final Set<String> messageIds;

  const _AccountNotificationSnapshot({
    required this.initialized,
    required this.omissionsInitialized,
    required this.messagesInitialized,
    required this.gradeIds,
    required this.testIds,
    required this.cancelledLessonIds,
    required this.substitutedLessonIds,
    required this.lateArrivalIds,
    required this.absenceIds,
    required this.messageIds,
  });

  const _AccountNotificationSnapshot.empty()
      : initialized = false,
        omissionsInitialized = false,
        messagesInitialized = false,
        gradeIds = const <String>{},
        testIds = const <String>{},
        cancelledLessonIds = const <String>{},
        substitutedLessonIds = const <String>{},
        lateArrivalIds = const <String>{},
        absenceIds = const <String>{},
        messageIds = const <String>{};

  factory _AccountNotificationSnapshot.fromJson(Map<String, dynamic> json) {
    Set<String> readSet(String key) {
      final raw = json[key];
      if (raw is! List) return <String>{};
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }

    return _AccountNotificationSnapshot(
      initialized: json['initialized'] == true,
      omissionsInitialized: json['omissionsInitialized'] == true ||
          json.containsKey('lateArrivalIds'),
      messagesInitialized: json['messagesInitialized'] == true ||
          json.containsKey('messageIds'),
      gradeIds: readSet('gradeIds'),
      testIds: readSet('testIds'),
      cancelledLessonIds: readSet('cancelledLessonIds'),
      substitutedLessonIds: readSet('substitutedLessonIds'),
      lateArrivalIds: readSet('lateArrivalIds'),
      absenceIds: readSet('absenceIds'),
      messageIds: readSet('messageIds'),
    );
  }

  Map<String, dynamic> toJson() => {
        'initialized': initialized,
        'omissionsInitialized': omissionsInitialized,
        'messagesInitialized': messagesInitialized,
        'gradeIds': gradeIds.toList()..sort(),
        'testIds': testIds.toList()..sort(),
        'cancelledLessonIds': cancelledLessonIds.toList()..sort(),
        'substitutedLessonIds': substitutedLessonIds.toList()..sort(),
        'lateArrivalIds': lateArrivalIds.toList()..sort(),
        'absenceIds': absenceIds.toList()..sort(),
        'messageIds': messageIds.toList()..sort(),
      };
}

/// Manages instant Kréta change diffing, customizable templates, and native
/// Android WorkManager / local notification dispatch.
class KretaNotificationService {
  static final KretaNotificationService instance = KretaNotificationService();

  static const MethodChannel _defaultChannel =
      MethodChannel(kKretaNotificationChannelName);

  final MethodChannel _channel;
  final Future<SharedPreferences> Function() _prefsProvider;
  Future<void> _writeQueue = Future<void>.value();

  KretaNotificationService({
    MethodChannel? channel,
    Future<SharedPreferences> Function()? prefsProvider,
  })  : _channel = channel ?? _defaultChannel,
        _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  /// Replaces `{placeholder}` tokens in [template] with [values] and tidies
  /// up empty bullet separators cleanly.
  static String renderTemplate(
    String template,
    Map<String, String> values,
  ) {
    var result = template;
    for (final spec in kNotificationPlaceholders) {
      final token = spec.token;
      final val = (values[token] ?? '').trim();
      result = result.replaceAll(token, val);
    }
    // Collapse redundant bullet separators when optional placeholders are blank.
    result = result.replaceAll(RegExp(r'\s*•\s*(?:•\s*)+'), ' • ');
    result = result.replaceAll(RegExp(r'^\s*•\s*|\s*•\s*$'), '');
    result = result.replaceAll(RegExp(r'\(\s*\)'), '');
    result = result.replaceAll(RegExp(r'\(\s*perc\s*\)'), '');
    result = result.replaceAll(RegExp(r'\(\s*\.\s*óra\s*\)'), '');
    result = result.replaceAll(RegExp(r' {2,}'), ' ').trim();
    return result;
  }

  /// Realistic Hungarian sample values used for live preview and test alerts.
  static Map<String, String> sampleValuesFor(
    KretaNotificationCategory category, {
    int? gradeValue,
  }) {
    switch (category) {
      case KretaNotificationCategory.newGrade:
        final g = (gradeValue ?? 5).clamp(1, 5);
        final topicByGrade = <int, String>{
          5: 'Függvények témazáró',
          4: 'Deriválás röpdolgozat',
          3: 'Szöveges feladatok',
          2: 'Geometria számonkérés',
          1: 'Algebrai egyenletek',
        };
        return {
          '{subject}': 'Matematika',
          '{grade}': '$g',
          '{weight}': '200%',
          '{teacher}': 'Dr. Nagy Péter',
          '{room}': 'B-204',
          '{date}': '11. 24.',
          '{topic}': topicByGrade[g] ?? 'Függvények témazáró',
          '{substitute_teacher}': 'Kiss Gábor',
          '{lesson_number}': '3',
          '{minutes}': '',
          '{excused_status}': '',
          '{type}': '',
          '{sender}': '',
          '{title}': '',
          '{preview}': '',
        };
      case KretaNotificationCategory.newExam:
        return const {
          '{subject}': 'Történelem',
          '{grade}': '5',
          '{weight}': '200%',
          '{teacher}': 'Szabó Katalin',
          '{room}': 'A-108',
          '{date}': '11. 28.',
          '{topic}': 'Reformkor dolgozat',
          '{substitute_teacher}': 'Kiss Gábor',
          '{lesson_number}': '2',
          '{minutes}': '',
          '{excused_status}': '',
          '{type}': '',
          '{sender}': '',
          '{title}': '',
          '{preview}': '',
        };
      case KretaNotificationCategory.cancelledLesson:
        return const {
          '{subject}': 'Fizika',
          '{grade}': '',
          '{weight}': '',
          '{teacher}': 'Horváth Zoltán',
          '{room}': 'Lab-2',
          '{date}': '11. 24.',
          '{topic}': 'Elmaradó tanóra',
          '{substitute_teacher}': '',
          '{lesson_number}': '6',
          '{minutes}': '',
          '{excused_status}': '',
          '{type}': '',
          '{sender}': '',
          '{title}': '',
          '{preview}': '',
        };
      case KretaNotificationCategory.substitution:
        return const {
          '{subject}': 'Angol nyelv',
          '{grade}': '',
          '{weight}': '',
          '{teacher}': 'Varga Katalin',
          '{room}': 'A-112',
          '{date}': '11. 24.',
          '{topic}': 'Helyettesítés',
          '{substitute_teacher}': 'Tóth Eszter',
          '{lesson_number}': '4',
          '{minutes}': '',
          '{excused_status}': '',
          '{type}': '',
          '{sender}': '',
          '{title}': '',
          '{preview}': '',
        };
      case KretaNotificationCategory.lateArrival:
        return const {
          '{subject}': 'Matematika',
          '{grade}': '',
          '{weight}': '',
          '{teacher}': 'Dr. Nagy Péter',
          '{room}': 'B-204',
          '{date}': '11. 24.',
          '{topic}': 'Késés',
          '{substitute_teacher}': '',
          '{lesson_number}': '1',
          '{minutes}': '7',
          '{excused_status}': 'Igazolandó',
          '{type}': 'Késés',
          '{sender}': '',
          '{title}': '',
          '{preview}': '',
        };
      case KretaNotificationCategory.absence:
        return const {
          '{subject}': 'Biológia',
          '{grade}': '',
          '{weight}': '',
          '{teacher}': 'Molnár Éva',
          '{room}': 'A-201',
          '{date}': '11. 24.',
          '{topic}': 'Hiányzás',
          '{substitute_teacher}': '',
          '{lesson_number}': '5',
          '{minutes}': '',
          '{excused_status}': 'Igazolandó',
          '{type}': 'Órai hiányzás',
          '{sender}': '',
          '{title}': '',
          '{preview}': '',
        };
      case KretaNotificationCategory.newMessage:
        return const {
          '{subject}': '',
          '{grade}': '',
          '{weight}': '',
          '{teacher}': 'Kovács Ágnes',
          '{room}': '',
          '{date}': '11. 24.',
          '{topic}': '',
          '{substitute_teacher}': '',
          '{lesson_number}': '',
          '{minutes}': '',
          '{excused_status}': '',
          '{type}': '',
          '{sender}': 'Kovács Ágnes (Osztályfőnök)',
          '{title}': 'Osztálykirándulás befizetés',
          '{preview}': 'Kedves Szülők és Diákok! Kérjük péntekig...',
        };
    }
  }

  Future<KretaNotificationConfig> loadConfig() async {
    try {
      final sp = await _prefsProvider();
      final raw = sp.getString(kKretaNotificationConfigPrefsKey);
      if (raw == null || raw.isEmpty) {
        return KretaNotificationConfig.defaults();
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return KretaNotificationConfig.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
    return KretaNotificationConfig.defaults();
  }

  Future<void> saveConfig(KretaNotificationConfig config) async {
    final serialized = jsonEncode(config.toJson());
    final queued = _writeQueue.then((_) async {
      final sp = await _prefsProvider();
      await sp.setString(kKretaNotificationConfigPrefsKey, serialized);
    }).catchError((_) {});
    _writeQueue = queued;
    await queued;
    await syncBackgroundSchedule(configOverride: config);
  }

  Future<void> syncBackgroundSchedule({
    KretaNotificationConfig? configOverride,
  }) async {
    if (kIsWeb) return;
    final config = configOverride ?? await loadConfig();
    try {
      await _channel.invokeMethod<bool>(
        'configureBackgroundSync',
        <String, Object?>{
          'enabled': config.anyCategoryEnabled,
          'intervalMinutes': config.backgroundIntervalMinutes,
        },
      );
    } on MissingPluginException {
      // Safe no-op in tests / non-Android hosts.
    } catch (_) {}
  }

  Future<bool> hasNotificationPermissions() async {
    if (kIsWeb) return false;
    try {
      final granted =
          await _channel.invokeMethod<bool>('hasNotificationPermissions');
      return granted == true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestNotificationPermissions() async {
    if (kIsWeb) return false;
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestNotificationPermissions');
      return granted == true;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> showNotification({
    required int notificationId,
    required KretaNotificationCategory category,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>(
        'showNotification',
        <String, Object?>{
          'notificationId': notificationId,
          'category': category.keyName,
          'title': title,
          'body': body,
        },
      );
    } on MissingPluginException {
      // Safe no-op in widget/unit tests without native channel handler.
    } catch (_) {}
  }

  /// Renders the title and body for any notification category, automatically
  /// applying the smart Hungarian linguistic engine when plain custom labels
  /// (without `{token}` placeholders) are provided.
  static ({String title, String body}) renderSmartNotification({
    required KretaNotificationCategory category,
    required String titleTemplate,
    required String bodyTemplate,
    required Map<String, String> values,
    String? subjectName,
    int? gradeValue,
  }) {
    final resolvedSubject =
        subjectName ?? values['{subject}'] ?? 'Matematika';
    final effectiveTitle = renderTemplate(titleTemplate, values);
    String body;
    if (category == KretaNotificationCategory.newGrade) {
      body = HungarianNotificationLinguistics.buildGradeNotificationBody(
        labelOrTemplate: bodyTemplate,
        subjectName: resolvedSubject,
        gradeValue: gradeValue,
        legacyValues: values,
      );
    } else if (bodyTemplate.trim().isNotEmpty &&
        !(bodyTemplate.contains('{') && bodyTemplate.contains('}'))) {
      body = category == KretaNotificationCategory.newMessage
          ? bodyTemplate.trim()
          : HungarianNotificationLinguistics.buildGenericNotificationBody(
              labelOrTemplate: bodyTemplate,
              subjectName: resolvedSubject,
              legacyValues: values,
            );
    } else {
      body = renderTemplate(bodyTemplate, values);
    }
    return (title: effectiveTitle, body: body);
  }

  Future<TriggeredKretaNotification> sendTestNotification(
    KretaNotificationCategory category, {
    KretaNotificationConfig? configOverride,
    int? gradeValue,
    String? subjectOverride,
  }) async {
    final config = configOverride ?? await loadConfig();
    final catCfg = config.forCategory(category);
    final effectiveGrade =
        category == KretaNotificationCategory.newGrade ? gradeValue : null;
    final values = Map<String, String>.from(
      sampleValuesFor(category, gradeValue: effectiveGrade),
    );
    if (subjectOverride != null && subjectOverride.trim().isNotEmpty) {
      values['{subject}'] = subjectOverride.trim();
    }
    final rendered = renderSmartNotification(
      category: category,
      titleTemplate: catCfg.titleTemplateForGrade(effectiveGrade),
      bodyTemplate: catCfg.bodyTemplateForGrade(effectiveGrade),
      values: values,
      subjectName: values['{subject}'],
      gradeValue: effectiveGrade,
    );
    final title = rendered.title;
    final body = rendered.body;
    final resolvedTitle = title.isEmpty ? category.label : title;
    final id = 8100 + category.index;
    await requestNotificationPermissions();
    await showNotification(
      notificationId: id,
      category: category,
      title: resolvedTitle,
      body: body,
    );
    return TriggeredKretaNotification(
      notificationId: id,
      category: category,
      title: resolvedTitle,
      body: body,
    );
  }

  static String _gradeKey(Grade g) {
    final uid = g.uid.trim();
    if (uid.isNotEmpty) return uid;
    return '${g.subject.name}_${g.recordedAt.toUtc().toIso8601String()}_${g.numericValue ?? g.strValue}';
  }

  static String _testKey(Test t) {
    final uid = t.uid.trim();
    if (uid.isNotEmpty) return uid;
    return '${t.subjectName}_${t.date.toUtc().toIso8601String()}_${t.lessonNumber}';
  }

  static String _cancelledLessonKey(Lesson l) {
    final uid = l.uid.trim();
    if (uid.isNotEmpty) return uid;
    return '${l.start.toUtc().toIso8601String()}_${l.lessonNumber ?? ''}_${l.name}';
  }

  static String _substitutionKey(Lesson l) {
    final sub = (l.substituteTeacher ?? '').trim();
    final uid = l.uid.trim().isNotEmpty
        ? l.uid.trim()
        : '${l.start.toUtc().toIso8601String()}_${l.lessonNumber ?? ''}_${l.name}';
    return '$uid::$sub';
  }

  static String _omissionKey(Omission o) {
    final uid = o.uid.trim();
    if (uid.isNotEmpty) return uid;
    return '${o.subject.name}_${o.date.toUtc().toIso8601String()}_${o.lesson?.classNo ?? 0}_${o.lateForMin ?? 0}';
  }

  static String _messageKey(KretaMessage m) {
    final uid = m.uid.trim();
    final kind = m.isSystemMessage ? 'sys' : 'msg';
    if (uid.isNotEmpty) return '$kind:$uid';
    return '$kind:${m.sender}_${m.sentAt.toUtc().toIso8601String()}_${m.subject}';
  }

  static String _formatOmissionStateHu(OmissionState state) {
    switch (state) {
      case OmissionState.excused:
        return 'Igazolt';
      case OmissionState.unexcused:
        return 'Igazolatlan';
      case OmissionState.pending:
        return 'Igazolandó';
      case OmissionState.unknown:
        return 'Ismeretlen';
    }
  }

  static String _truncatePreview(String text, {int maxLen = 110}) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxLen) return compact;
    return '${compact.substring(0, maxLen - 3).trim()}...';
  }

  Future<Map<String, _AccountNotificationSnapshot>> _loadAllSnapshots(
    SharedPreferences sp,
  ) async {
    final raw = sp.getString(kKretaNotificationSnapshotPrefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, _AccountNotificationSnapshot>{};
      decoded.forEach((key, val) {
        if (val is Map) {
          out[key.toString()] = _AccountNotificationSnapshot.fromJson(
            Map<String, dynamic>.from(val),
          );
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Diffs fresh Kréta [dashboard] (and optional [extraLessons]) against the
  /// persisted per-account baseline, firing local notifications for newly
  /// observed items when enabled in [KretaNotificationConfig].
  Future<List<TriggeredKretaNotification>> processDashboardDiff({
    required DashboardData dashboard,
    UserProfilePrefs? profilePrefs,
    List<Lesson>? extraLessons,
  }) async {
    if (DemoDataService.isDemoSession(dashboard.activeSession) ||
        profilePrefs?.demoModeEnabled == true) {
      return const [];
    }

    final config = await loadConfig();
    final sp = await _prefsProvider();
    final accountKey =
        TokenStorageService.accountKeyForSession(dashboard.activeSession);
    final allSnapshots = await _loadAllSnapshots(sp);
    final prev =
        allSnapshots[accountKey] ?? const _AccountNotificationSnapshot.empty();

    final lessonsByKey = <String, Lesson>{};
    for (final l in [...dashboard.todaysLessons, ...?extraLessons]) {
      if (isInactivePlaceholderLesson(l)) continue;
      lessonsByKey[_cancelledLessonKey(l)] = l;
    }
    final allLessons = lessonsByKey.values.toList();

    final currentGradeIds = dashboard.allGrades.map(_gradeKey).toSet();
    final currentTestIds = dashboard.tests.map(_testKey).toSet();
    final currentCancelled = allLessons
        .where(isLessonCancelled)
        .map(_cancelledLessonKey)
        .toSet();
    final currentSubstituted = allLessons
        .where(
          (l) =>
              !isLessonCancelled(l) &&
              (l.substituteTeacher?.trim().isNotEmpty == true),
        )
        .map(_substitutionKey)
        .toSet();
    final currentLateIds = <String>{};
    final currentAbsenceIds = <String>{};
    for (final o in dashboard.omissions) {
      final key = _omissionKey(o);
      if (OmissionsSummary.isTardiness(o)) {
        currentLateIds.add(key);
      } else {
        currentAbsenceIds.add(key);
      }
    }
    final currentMessageIds = dashboard.messages
        .where((m) => !m.isSent && !m.isRead)
        .map(_messageKey)
        .toSet();

    // First sync establishes baseline cleanly without spamming historical items.
    if (!prev.initialized) {
      final baseline = _AccountNotificationSnapshot(
        initialized: true,
        omissionsInitialized: true,
        messagesInitialized: true,
        gradeIds: currentGradeIds,
        testIds: currentTestIds,
        cancelledLessonIds: currentCancelled,
        substitutedLessonIds: currentSubstituted,
        lateArrivalIds: currentLateIds,
        absenceIds: currentAbsenceIds,
        messageIds: currentMessageIds,
      );
      allSnapshots[accountKey] = baseline;
      await sp.setString(
        kKretaNotificationSnapshotPrefsKey,
        jsonEncode(
          allSnapshots.map((k, v) => MapEntry(k, v.toJson())),
        ),
      );
      return const [];
    }

    final dateFmt = DateFormat('MM. dd.');
    final triggered = <TriggeredKretaNotification>[];
    var nextId = 8200;

    if (config.masterEnabled) {
      final gradeCfg = config.forCategory(KretaNotificationCategory.newGrade);
      if (gradeCfg.enabled) {
        for (final g in dashboard.allGrades) {
          final key = _gradeKey(g);
          if (prev.gradeIds.contains(key)) continue;
          final subject = profilePrefs != null
              ? profilePrefs.resolveSubjectName(g.subject.name, g.subject.uid)
              : g.subject.name;
          final teacher = profilePrefs != null
              ? profilePrefs.resolveTeacherName(g.teacher)
              : g.teacher;
          final weightStr =
              (g.weightPercentage != null && g.weightPercentage! > 0)
                  ? '${g.weightPercentage}%'
                  : '100%';
          final topic = (g.topic ?? '').trim().isNotEmpty
              ? g.topic!.trim()
              : (g.mode?.description.trim().isNotEmpty == true
                  ? g.mode!.description.trim()
                  : g.type.description.trim());
          final gradeText = g.numericValue?.toString() ??
              (g.shortStrValue?.trim().isNotEmpty == true
                  ? g.shortStrValue!.trim()
                  : g.strValue);
          final values = <String, String>{
            '{subject}': subject,
            '{grade}': gradeText,
            '{weight}': weightStr,
            '{teacher}': teacher,
            '{room}': '',
            '{date}': dateFmt.format(g.recordedAt.toLocal()),
            '{topic}': topic,
            '{substitute_teacher}': '',
            '{lesson_number}': '',
          };
          final rendered = renderSmartNotification(
            category: KretaNotificationCategory.newGrade,
            titleTemplate: gradeCfg.titleTemplateForGrade(g.numericValue),
            bodyTemplate: gradeCfg.bodyTemplateForGrade(g.numericValue),
            values: values,
            subjectName: subject,
            gradeValue: g.numericValue,
          );
          final title = rendered.title;
          final body = rendered.body;
          final item = TriggeredKretaNotification(
            notificationId: nextId++,
            category: KretaNotificationCategory.newGrade,
            title: title.isEmpty ? 'Új jegy: $subject' : title,
            body: body,
          );
          triggered.add(item);
          await showNotification(
            notificationId: item.notificationId,
            category: item.category,
            title: item.title,
            body: item.body,
          );
        }
      }

      final examCfg = config.forCategory(KretaNotificationCategory.newExam);
      if (examCfg.enabled) {
        for (final t in dashboard.tests) {
          final key = _testKey(t);
          if (prev.testIds.contains(key)) continue;
          final rawSubj =
              t.subject.name.isNotEmpty ? t.subject.name : t.subjectName;
          final subject = profilePrefs != null
              ? profilePrefs.resolveSubjectName(rawSubj, t.subject.uid)
              : rawSubj;
          final teacher = profilePrefs != null
              ? profilePrefs.resolveTeacherName(t.teacherName)
              : t.teacherName;
          final topic = (t.theme ?? '').trim().isNotEmpty
              ? t.theme!.trim()
              : t.method.description.trim();
          final values = <String, String>{
            '{subject}': subject,
            '{grade}': '',
            '{weight}': '',
            '{teacher}': teacher,
            '{room}': '',
            '{date}': dateFmt.format(t.date.toLocal()),
            '{topic}': topic,
            '{substitute_teacher}': '',
            '{lesson_number}': t.lessonNumber > 0 ? '${t.lessonNumber}' : '',
          };
          final title = renderTemplate(examCfg.titleTemplate, values);
          final body = renderTemplate(examCfg.bodyTemplate, values);
          final item = TriggeredKretaNotification(
            notificationId: nextId++,
            category: KretaNotificationCategory.newExam,
            title: title.isEmpty ? 'Új számonkérés: $subject' : title,
            body: body,
          );
          triggered.add(item);
          await showNotification(
            notificationId: item.notificationId,
            category: item.category,
            title: item.title,
            body: item.body,
          );
        }
      }

      final cancelCfg =
          config.forCategory(KretaNotificationCategory.cancelledLesson);
      if (cancelCfg.enabled) {
        for (final l in allLessons) {
          if (!isLessonCancelled(l)) continue;
          final key = _cancelledLessonKey(l);
          if (prev.cancelledLessonIds.contains(key)) continue;
          final rawSubj = l.subject?.name ?? l.name;
          final subject = profilePrefs != null
              ? profilePrefs.resolveSubjectName(rawSubj, l.subject?.uid)
              : rawSubj;
          final teacher = profilePrefs != null
              ? profilePrefs.resolveTeacherName(l.teacher)
              : (l.teacher ?? '');
          final values = <String, String>{
            '{subject}': subject,
            '{grade}': '',
            '{weight}': '',
            '{teacher}': teacher,
            '{room}': (l.roomName ?? '').trim(),
            '{date}': dateFmt.format(l.start.toLocal()),
            '{topic}': (l.theme ?? '').trim(),
            '{substitute_teacher}': '',
            '{lesson_number}':
                l.lessonNumber != null ? '${l.lessonNumber}' : '',
          };
          final title = renderTemplate(cancelCfg.titleTemplate, values);
          final body = renderTemplate(cancelCfg.bodyTemplate, values);
          final item = TriggeredKretaNotification(
            notificationId: nextId++,
            category: KretaNotificationCategory.cancelledLesson,
            title: title.isEmpty ? 'Elmaradt óra: $subject' : title,
            body: body,
          );
          triggered.add(item);
          await showNotification(
            notificationId: item.notificationId,
            category: item.category,
            title: item.title,
            body: item.body,
          );
        }
      }

      final subCfg =
          config.forCategory(KretaNotificationCategory.substitution);
      if (subCfg.enabled) {
        for (final l in allLessons) {
          if (isLessonCancelled(l)) continue;
          final subTeacherRaw = l.substituteTeacher?.trim() ?? '';
          if (subTeacherRaw.isEmpty) continue;
          final key = _substitutionKey(l);
          if (prev.substitutedLessonIds.contains(key)) continue;
          final rawSubj = l.subject?.name ?? l.name;
          final subject = profilePrefs != null
              ? profilePrefs.resolveSubjectName(rawSubj, l.subject?.uid)
              : rawSubj;
          final teacher = profilePrefs != null
              ? profilePrefs.resolveTeacherName(l.teacher)
              : (l.teacher ?? '');
          final subTeacher = profilePrefs != null
              ? profilePrefs.resolveTeacherName(subTeacherRaw)
              : subTeacherRaw;
          final values = <String, String>{
            '{subject}': subject,
            '{grade}': '',
            '{weight}': '',
            '{teacher}': teacher,
            '{room}': (l.roomName ?? '').trim(),
            '{date}': dateFmt.format(l.start.toLocal()),
            '{topic}': (l.theme ?? '').trim(),
            '{substitute_teacher}': subTeacher,
            '{lesson_number}':
                l.lessonNumber != null ? '${l.lessonNumber}' : '',
          };
          final title = renderTemplate(subCfg.titleTemplate, values);
          final body = renderTemplate(subCfg.bodyTemplate, values);
          final item = TriggeredKretaNotification(
            notificationId: nextId++,
            category: KretaNotificationCategory.substitution,
            title: title.isEmpty ? 'Helyettesítés: $subject' : title,
            body: body,
          );
          triggered.add(item);
          await showNotification(
            notificationId: item.notificationId,
            category: item.category,
            title: item.title,
            body: item.body,
          );
        }
      }

      if (prev.omissionsInitialized) {
        final lateCfg =
            config.forCategory(KretaNotificationCategory.lateArrival);
        if (lateCfg.enabled) {
          for (final o in dashboard.omissions) {
            if (!OmissionsSummary.isTardiness(o)) continue;
            final key = _omissionKey(o);
            if (prev.lateArrivalIds.contains(key)) continue;
            final subject = profilePrefs != null
                ? profilePrefs.resolveSubjectName(o.subject.name, o.subject.uid)
                : o.subject.name;
            final teacher = profilePrefs != null
                ? profilePrefs.resolveTeacherName(o.teacher)
                : o.teacher;
            final minutes = '${o.lateForMin ?? 0}';
            final typeLabel = o.type?.description.trim().isNotEmpty == true
                ? o.type!.description.trim()
                : (o.mode?.description.trim().isNotEmpty == true
                    ? o.mode!.description.trim()
                    : 'Késés');
            final values = <String, String>{
              '{subject}': subject,
              '{grade}': '',
              '{weight}': '',
              '{teacher}': teacher,
              '{room}': '',
              '{date}': dateFmt.format(o.date.toLocal()),
              '{topic}': typeLabel,
              '{substitute_teacher}': '',
              '{lesson_number}':
                  o.lesson?.classNo != null ? '${o.lesson!.classNo}' : '',
              '{minutes}': minutes,
              '{excused_status}': _formatOmissionStateHu(o.state),
              '{type}': typeLabel,
              '{sender}': '',
              '{title}': '',
              '{preview}': '',
            };
            final title = renderTemplate(lateCfg.titleTemplate, values);
            final body = renderTemplate(lateCfg.bodyTemplate, values);
            final item = TriggeredKretaNotification(
              notificationId: nextId++,
              category: KretaNotificationCategory.lateArrival,
              title: title.isEmpty ? 'Késés: $subject' : title,
              body: body,
            );
            triggered.add(item);
            await showNotification(
              notificationId: item.notificationId,
              category: item.category,
              title: item.title,
              body: item.body,
            );
          }
        }

        final absenceCfg =
            config.forCategory(KretaNotificationCategory.absence);
        if (absenceCfg.enabled) {
          for (final o in dashboard.omissions) {
            if (OmissionsSummary.isTardiness(o)) continue;
            final key = _omissionKey(o);
            if (prev.absenceIds.contains(key)) continue;
            final subject = profilePrefs != null
                ? profilePrefs.resolveSubjectName(o.subject.name, o.subject.uid)
                : o.subject.name;
            final teacher = profilePrefs != null
                ? profilePrefs.resolveTeacherName(o.teacher)
                : o.teacher;
            final typeLabel = o.type?.description.trim().isNotEmpty == true
                ? o.type!.description.trim()
                : (o.mode?.description.trim().isNotEmpty == true
                    ? o.mode!.description.trim()
                    : 'Hiányzás');
            final values = <String, String>{
              '{subject}': subject,
              '{grade}': '',
              '{weight}': '',
              '{teacher}': teacher,
              '{room}': '',
              '{date}': dateFmt.format(o.date.toLocal()),
              '{topic}': typeLabel,
              '{substitute_teacher}': '',
              '{lesson_number}':
                  o.lesson?.classNo != null ? '${o.lesson!.classNo}' : '',
              '{minutes}': '',
              '{excused_status}': _formatOmissionStateHu(o.state),
              '{type}': typeLabel,
              '{sender}': '',
              '{title}': '',
              '{preview}': '',
            };
            final title = renderTemplate(absenceCfg.titleTemplate, values);
            final body = renderTemplate(absenceCfg.bodyTemplate, values);
            final item = TriggeredKretaNotification(
              notificationId: nextId++,
              category: KretaNotificationCategory.absence,
              title: title.isEmpty ? 'Hiányzás: $subject' : title,
              body: body,
            );
            triggered.add(item);
            await showNotification(
              notificationId: item.notificationId,
              category: item.category,
              title: item.title,
              body: item.body,
            );
          }
        }
      }

      if (prev.messagesInitialized) {
        final msgCfg =
            config.forCategory(KretaNotificationCategory.newMessage);
        if (msgCfg.enabled) {
          for (final m in dashboard.messages) {
            if (m.isSent || m.isRead) continue;
            final key = _messageKey(m);
            if (prev.messageIds.contains(key)) continue;
            final sender = profilePrefs != null
                ? profilePrefs.resolveTeacherName(m.sender)
                : m.sender;
            final msgTitle = m.subject.trim();
            final preview = _truncatePreview(m.cleanBody);
            final values = <String, String>{
              '{subject}': msgTitle,
              '{grade}': '',
              '{weight}': '',
              '{teacher}': sender,
              '{room}': '',
              '{date}': dateFmt.format(m.sentAt.toLocal()),
              '{topic}': msgTitle,
              '{substitute_teacher}': '',
              '{lesson_number}': '',
              '{minutes}': '',
              '{excused_status}': '',
              '{type}': m.isSystemMessage ? 'Rendszerüzenet' : 'Üzenet',
              '{sender}': sender,
              '{title}': msgTitle,
              '{preview}': preview,
            };
            final title = renderTemplate(msgCfg.titleTemplate, values);
            final body = renderTemplate(msgCfg.bodyTemplate, values);
            final item = TriggeredKretaNotification(
              notificationId: nextId++,
              category: KretaNotificationCategory.newMessage,
              title: title.isEmpty ? 'Új üzenet: $sender' : title,
              body: body,
            );
            triggered.add(item);
            await showNotification(
              notificationId: item.notificationId,
              category: item.category,
              title: item.title,
              body: item.body,
            );
          }
        }
      }
    }

    // Always merge newly seen keys into the baseline so disabled periods don't
    // later replay stale alerts when re-enabled.
    final updated = _AccountNotificationSnapshot(
      initialized: true,
      omissionsInitialized: true,
      messagesInitialized: true,
      gradeIds: <String>{...prev.gradeIds, ...currentGradeIds},
      testIds: <String>{...prev.testIds, ...currentTestIds},
      cancelledLessonIds: <String>{
        ...prev.cancelledLessonIds,
        ...currentCancelled,
      },
      substitutedLessonIds: <String>{
        ...prev.substitutedLessonIds,
        ...currentSubstituted,
      },
      lateArrivalIds: <String>{...prev.lateArrivalIds, ...currentLateIds},
      absenceIds: <String>{...prev.absenceIds, ...currentAbsenceIds},
      messageIds: <String>{...prev.messageIds, ...currentMessageIds},
    );
    allSnapshots[accountKey] = updated;
    await sp.setString(
      kKretaNotificationSnapshotPrefsKey,
      jsonEncode(
        allSnapshots.map((k, v) => MapEntry(k, v.toJson())),
      ),
    );
    return triggered;
  }

  /// Evaluates fresh [omissions] and/or [messages] fetched outside a full
  /// dashboard reload (e.g., pulling to refresh Absences or Messages tabs).
  Future<List<TriggeredKretaNotification>> processOmissionsAndMessagesDiff({
    required StoredSession session,
    List<Omission>? omissions,
    List<KretaMessage>? messages,
    UserProfilePrefs? profilePrefs,
  }) async {
    if (DemoDataService.isDemoSession(session) ||
        profilePrefs?.demoModeEnabled == true) {
      return const [];
    }
    if (omissions == null && messages == null) return const [];

    final config = await loadConfig();
    final sp = await _prefsProvider();
    final accountKey = TokenStorageService.accountKeyForSession(session);
    final allSnapshots = await _loadAllSnapshots(sp);
    final prev =
        allSnapshots[accountKey] ?? const _AccountNotificationSnapshot.empty();

    final dateFmt = DateFormat('MM. dd.');
    final triggered = <TriggeredKretaNotification>[];
    var nextId = 8350;

    final currentLateIds = <String>{};
    final currentAbsenceIds = <String>{};
    if (omissions != null) {
      for (final o in omissions) {
        final key = _omissionKey(o);
        if (OmissionsSummary.isTardiness(o)) {
          currentLateIds.add(key);
        } else {
          currentAbsenceIds.add(key);
        }
      }
    }
    final currentMessageIds = messages != null
        ? messages
            .where((m) => !m.isSent && !m.isRead)
            .map(_messageKey)
            .toSet()
        : const <String>{};

    if (config.masterEnabled && prev.initialized) {
      if (omissions != null && prev.omissionsInitialized) {
        final lateCfg =
            config.forCategory(KretaNotificationCategory.lateArrival);
        if (lateCfg.enabled) {
          for (final o in omissions) {
            if (!OmissionsSummary.isTardiness(o)) continue;
            final key = _omissionKey(o);
            if (prev.lateArrivalIds.contains(key)) continue;
            final subject = profilePrefs != null
                ? profilePrefs.resolveSubjectName(o.subject.name, o.subject.uid)
                : o.subject.name;
            final teacher = profilePrefs != null
                ? profilePrefs.resolveTeacherName(o.teacher)
                : o.teacher;
            final typeLabel = o.type?.description.trim().isNotEmpty == true
                ? o.type!.description.trim()
                : 'Késés';
            final values = <String, String>{
              '{subject}': subject,
              '{grade}': '',
              '{weight}': '',
              '{teacher}': teacher,
              '{room}': '',
              '{date}': dateFmt.format(o.date.toLocal()),
              '{topic}': typeLabel,
              '{substitute_teacher}': '',
              '{lesson_number}':
                  o.lesson?.classNo != null ? '${o.lesson!.classNo}' : '',
              '{minutes}': '${o.lateForMin ?? 0}',
              '{excused_status}': _formatOmissionStateHu(o.state),
              '{type}': typeLabel,
              '{sender}': '',
              '{title}': '',
              '{preview}': '',
            };
            final title = renderTemplate(lateCfg.titleTemplate, values);
            final body = renderTemplate(lateCfg.bodyTemplate, values);
            final item = TriggeredKretaNotification(
              notificationId: nextId++,
              category: KretaNotificationCategory.lateArrival,
              title: title.isEmpty ? 'Késés: $subject' : title,
              body: body,
            );
            triggered.add(item);
            await showNotification(
              notificationId: item.notificationId,
              category: item.category,
              title: item.title,
              body: item.body,
            );
          }
        }

        final absenceCfg =
            config.forCategory(KretaNotificationCategory.absence);
        if (absenceCfg.enabled) {
          for (final o in omissions) {
            if (OmissionsSummary.isTardiness(o)) continue;
            final key = _omissionKey(o);
            if (prev.absenceIds.contains(key)) continue;
            final subject = profilePrefs != null
                ? profilePrefs.resolveSubjectName(o.subject.name, o.subject.uid)
                : o.subject.name;
            final teacher = profilePrefs != null
                ? profilePrefs.resolveTeacherName(o.teacher)
                : o.teacher;
            final typeLabel = o.type?.description.trim().isNotEmpty == true
                ? o.type!.description.trim()
                : 'Hiányzás';
            final values = <String, String>{
              '{subject}': subject,
              '{grade}': '',
              '{weight}': '',
              '{teacher}': teacher,
              '{room}': '',
              '{date}': dateFmt.format(o.date.toLocal()),
              '{topic}': typeLabel,
              '{substitute_teacher}': '',
              '{lesson_number}':
                  o.lesson?.classNo != null ? '${o.lesson!.classNo}' : '',
              '{minutes}': '',
              '{excused_status}': _formatOmissionStateHu(o.state),
              '{type}': typeLabel,
              '{sender}': '',
              '{title}': '',
              '{preview}': '',
            };
            final title = renderTemplate(absenceCfg.titleTemplate, values);
            final body = renderTemplate(absenceCfg.bodyTemplate, values);
            final item = TriggeredKretaNotification(
              notificationId: nextId++,
              category: KretaNotificationCategory.absence,
              title: title.isEmpty ? 'Hiányzás: $subject' : title,
              body: body,
            );
            triggered.add(item);
            await showNotification(
              notificationId: item.notificationId,
              category: item.category,
              title: item.title,
              body: item.body,
            );
          }
        }
      }

      if (messages != null && prev.messagesInitialized) {
        final msgCfg =
            config.forCategory(KretaNotificationCategory.newMessage);
        if (msgCfg.enabled) {
          for (final m in messages) {
            if (m.isSent || m.isRead) continue;
            final key = _messageKey(m);
            if (prev.messageIds.contains(key)) continue;
            final sender = profilePrefs != null
                ? profilePrefs.resolveTeacherName(m.sender)
                : m.sender;
            final msgTitle = m.subject.trim();
            final preview = _truncatePreview(m.cleanBody);
            final values = <String, String>{
              '{subject}': msgTitle,
              '{grade}': '',
              '{weight}': '',
              '{teacher}': sender,
              '{room}': '',
              '{date}': dateFmt.format(m.sentAt.toLocal()),
              '{topic}': msgTitle,
              '{substitute_teacher}': '',
              '{lesson_number}': '',
              '{minutes}': '',
              '{excused_status}': '',
              '{type}': m.isSystemMessage ? 'Rendszerüzenet' : 'Üzenet',
              '{sender}': sender,
              '{title}': msgTitle,
              '{preview}': preview,
            };
            final title = renderTemplate(msgCfg.titleTemplate, values);
            final body = renderTemplate(msgCfg.bodyTemplate, values);
            final item = TriggeredKretaNotification(
              notificationId: nextId++,
              category: KretaNotificationCategory.newMessage,
              title: title.isEmpty ? 'Új üzenet: $sender' : title,
              body: body,
            );
            triggered.add(item);
            await showNotification(
              notificationId: item.notificationId,
              category: item.category,
              title: item.title,
              body: item.body,
            );
          }
        }
      }
    }

    final updated = _AccountNotificationSnapshot(
      initialized: prev.initialized,
      omissionsInitialized:
          prev.omissionsInitialized || omissions != null,
      messagesInitialized: prev.messagesInitialized || messages != null,
      gradeIds: prev.gradeIds,
      testIds: prev.testIds,
      cancelledLessonIds: prev.cancelledLessonIds,
      substitutedLessonIds: prev.substitutedLessonIds,
      lateArrivalIds: omissions != null
          ? <String>{...prev.lateArrivalIds, ...currentLateIds}
          : prev.lateArrivalIds,
      absenceIds: omissions != null
          ? <String>{...prev.absenceIds, ...currentAbsenceIds}
          : prev.absenceIds,
      messageIds: messages != null
          ? <String>{...prev.messageIds, ...currentMessageIds}
          : prev.messageIds,
    );
    allSnapshots[accountKey] = updated;
    await sp.setString(
      kKretaNotificationSnapshotPrefsKey,
      jsonEncode(
        allSnapshots.map((k, v) => MapEntry(k, v.toJson())),
      ),
    );
    return triggered;
  }
}
