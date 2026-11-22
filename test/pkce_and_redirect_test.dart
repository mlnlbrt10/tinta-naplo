import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:tinta_naplo/core/kreta_auth_config.dart';
import 'package:tinta_naplo/screens/grades_screen.dart';
import 'package:tinta_naplo/screens/timetable_screen.dart';
import 'package:tinta_naplo/services/github_updater_service.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/menetrend_service.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/utils/greeting_utils.dart';
import 'package:tinta_naplo/utils/uwu_helper.dart';

class _InMemoryTokenStorage extends TokenStorageService {
  StoredSession? savedSession;

  @override
  Future<void> saveSession(StoredSession session) async {
    savedSession = session;
  }

  @override
  Future<StoredSession?> loadSession() async => savedSession;
}

class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.0;

  @override
  int nextInt(int max) => 0;
}

Lesson _makeLesson({
  required int lessonNumber,
  required DateTime start,
  required DateTime end,
}) {
  return Lesson(
    uid: 'lesson_$lessonNumber',
    date: '2026-11-11',
    start: start,
    end: end,
    name: 'Matematika',
    lessonNumber: lessonNumber,
    lessonSeqNumber: lessonNumber,
    roomName: '101',
    teacher: 'Kovács Tanárnő',
    type: NameUidDesc(
      uid: 'tanora',
      name: 'Tanora',
      description: 'Tanóra',
    ),
    state: NameUidDesc(
      uid: 'megtartott',
      name: 'Megtartott',
      description: 'Megtartott',
    ),
    canStudentEditHomework: false,
    isHomeworkComplete: false,
    attachments: const [],
    isDigitalLesson: false,
    digitalSupportDeviceTypeList: const [],
    createdAt: start,
    lastModifiedAt: start,
  );
}

Grade _makeGrade({
  required String uid,
  required String subjectUid,
  required String subjectName,
  required int numericValue,
  required int weightPercentage,
}) {
  final now = DateTime(2026, 11, 10, 10, 0);
  return Grade(
    uid: uid,
    recordDate: now,
    creationDate: now,
    teacher: 'Kovács Tanárnő',
    type: NameUidDesc(uid: 't', name: 'MidYear', description: 'Évközi'),
    mode: NameUidDesc(uid: 'm', name: 'Written', description: 'Írásbeli'),
    subject: Subject(
      uid: subjectUid,
      name: subjectName,
      category: NameUidDesc(
        uid: 'cat',
        name: 'cat',
        description: subjectName,
      ),
      sortIndex: 1,
    ),
    classGroup: NameUidDesc(uid: 'cg', name: '11.A', description: '11.A'),
    valueType: NameUidDesc(uid: 'v', name: 'FiveScale', description: 'Ötfokozatú'),
    strValue: '$numericValue',
    numericValue: numericValue,
    weightPercentage: weightPercentage,
    sortIndex: 1,
  );
}

void main() {
  test('PkcePair generates distinct base64url verifier and S256 challenge', () {
    final pair = PkcePair.generate();
    expect(pair.codeVerifier.length, greaterThanOrEqualTo(43));
    expect(pair.codeChallenge.length, greaterThanOrEqualTo(43));
    expect(pair.codeVerifier.contains('='), isFalse);
    expect(pair.codeChallenge.contains('='), isFalse);
  });

  test('isOAuthRedirectUrl matches mobile oauthredirect callback', () {
    const callbackUrl =
        'https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect?code=abc123xyz&state=st1';
    expect(KretaAuthConfig.isOAuthRedirectUrl(callbackUrl), isTrue);
    expect(
      KretaAuthConfig.isOAuthRedirectUrl('https://idp.e-kreta.hu/Account/Login'),
      isFalse,
    );
  });

  test('GreetingUtils resolves nickname or falls back to first name', () {
    expect(
      GreetingUtils.resolveDisplayName(
        customNickname: 'Mili',
        fullStudentName: 'Kovács Milán',
      ),
      'Mili',
    );
    expect(
      GreetingUtils.resolveDisplayName(
        customNickname: '',
        fullStudentName: 'Kovács Milán',
      ),
      'Milán',
    );
    expect(
      GreetingUtils.resolveDisplayName(
        customNickname: null,
        fullStudentName: null,
      ),
      'Diák',
    );
    // 3-part names always use the 2nd token (primary first name).
    expect(
      GreetingUtils.resolveDisplayName(
        fullStudentName: 'Albert Alexa Nikolett',
      ),
      'Alexa',
    );
  });

  test('GreetingUtils builds time-based Hungarian greetings for all 4 windows', () {
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 6, 30),
      ),
      'Szép reggelt, Milán!',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 14, 0),
      ),
      'Szép napot, Milán!',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 19, 45),
      ),
      'Szép estét, Milán!',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 23, 15),
      ),
      'Jó éjszakát, Milán!',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 2, 10),
      ),
      'Jó éjszakát, Milán!',
    );
  });

  test('UwuHelper and GreetingUtils transform text in UwU mode without \$1 artifacts', () {
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 12, 0),
        uwuMode: true,
      ),
      'Szép nyapot, Miwán! uwu',
    );
    final transformed = UwuHelper.transform('Frissítések keresése', enabled: true);
    expect(transformed.startsWith('Fwissítések kewesése'), isTrue);

    final noDollar = UwuHelper.transform('Napló és óranapló 08:00 100% KRÉTA', enabled: true);
    expect(noDollar.contains(r'$1'), isFalse);
    expect(noDollar.contains('Nyapwó'), isTrue);
    expect(noDollar.contains('08:00'), isTrue);
    expect(noDollar.contains('100%'), isTrue);
    expect(noDollar.contains('KRÉTA'), isTrue);

    // Short labels should never receive spammed suffixes
    final shortLabel = UwuHelper.transform('Órarend', enabled: true);
    expect(shortLabel.contains('uwu'), isFalse);
    expect(shortLabel.contains(':3'), isFalse);
  });

  test('MenetrendService supports 3.0-8.0 km/h 0.5 steps and reworked notifications', () {
    expect(MenetrendService.normalizeWalkingSpeed(2.1), 3.0);
    expect(MenetrendService.normalizeWalkingSpeed(3.5), 3.5);
    expect(MenetrendService.normalizeWalkingSpeed(4.5), 4.5);
    expect(MenetrendService.normalizeWalkingSpeed(5.26), 5.5);
    expect(MenetrendService.normalizeWalkingSpeed(7.8), 8.0);
    expect(MenetrendService.walkingSpeedLabel(5.5), '5.5 km/h');

    final trip = MenetrendTripOption(
      routeShortName: 'S150',
      routeLongName: 'Személyvonat',
      mode: MenetrendTransportMode.rail,
      departureStation: 'Bodajk',
      arrivalStation: 'Székesfehérvár',
      scheduledDeparture: DateTime(2026, 11, 13, 7, 9),
      scheduledArrival: DateTime(2026, 11, 13, 7, 42),
      delayMinutes: 7,
      walkToStationMinutes: 13,
    );
    final eval = CommuteEvaluation(
      isMorningMode: true,
      targetLesson: null,
      targetPeriodNumber: 1,
      recommendedTrip: trip,
      alternatives: [trip],
      effectiveWalkMinutes: 13,
      alertBufferMinutes: 5,
      now: DateTime(2026, 11, 13, 6, 40),
    );
    expect(eval.departureNotificationTitle, 'Indulás 5 perc múlva • S150');
    expect(
      eval.departureNotificationBody,
      '07:09-es járat (Bodajk -> Székesfehérvár) • 13p séta az állomásra',
    );
    expect(eval.delayNotificationTitle, 'Késés (+7p) • S150');
    expect(
      eval.delayNotificationBody,
      'Menetrend szerint: 07:09 -> Várható indulás: 07:16 (Bodajk -> Székesfehérvár)',
    );
  });

  test('UserProfilePrefs.funGreetingsEnabled defaults false and round-trips JSON', () {
    const defaults = UserProfilePrefs();
    expect(defaults.funGreetingsEnabled, isFalse);

    final toggled = defaults.withFunGreetings(true);
    expect(toggled.funGreetingsEnabled, isTrue);
    final restored = UserProfilePrefs.fromJson(toggled.toJson());
    expect(restored.funGreetingsEnabled, isTrue);

    final viaCopy = defaults.copyWith(funGreetingsEnabled: true);
    expect(viaCopy.funGreetingsEnabled, isTrue);
    expect(viaCopy.copyWith(funGreetingsEnabled: false).funGreetingsEnabled, isFalse);
  });

  test('GreetingUtils fun greetings enforce tight time windows and weekday guard', () {
    // Audit all 117 templates and verify zero en-dashes or em-dashes.
    final all = GreetingUtils.allFunTemplates;
    expect(all.length, 117);
    for (final template in all) {
      expect(template.contains('\u2013'), isFalse, reason: 'En-dash in $template');
      expect(template.contains('\u2014'), isFalse, reason: 'Em-dash in $template');
      expect(template.contains('{name}'), isTrue, reason: 'Missing {name} in $template');
    }

    // Tuesday 2026-11-10
    final tuesdayEarly = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 10, 7, 30));
    expect(tuesdayEarly, contains('Kávé volt már, {name}?'));
    expect(tuesdayEarly, isNot(contains('Becsengettek, {name}')));
    expect(tuesdayEarly, isNot(contains('Még ébren, {name}?')));

    final tuesdayMorning = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 10, 9, 0));
    expect(tuesdayMorning, contains('Becsengettek, {name}'));
    expect(tuesdayMorning, isNot(contains('Kávé volt már, {name}?')));
    expect(tuesdayMorning, isNot(contains('Mikor lesz már szünet, {name}?')));

    final tuesdaySchool = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 10, 11, 30));
    expect(tuesdaySchool, contains('Mikor lesz már szünet, {name}?'));
    expect(tuesdaySchool, isNot(contains('Hazaértél már, {name}?')));

    final tuesdayAfternoon = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 10, 16, 0));
    expect(tuesdayAfternoon, contains('Hazaértél már, {name}?'));
    expect(tuesdayAfternoon, isNot(contains('Esti chill, {name}?')));

    final tuesdayEvening = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 10, 19, 0));
    expect(tuesdayEvening, contains('Esti chill, {name}?'));
    expect(tuesdayEvening, contains('Holnap suli, {name}...'));
    expect(tuesdayEvening, isNot(contains('Még ébren, {name}?')));

    final tuesdayLateNight = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 10, 23, 0));
    expect(tuesdayLateNight, contains('Még ébren, {name}?'));
    expect(tuesdayLateNight, isNot(contains('Esti chill, {name}?')));
    expect(tuesdayLateNight, isNot(contains('Kávé volt már, {name}?')));

    // Monday vs Friday pools & "Holnap suli..." exclusion on Friday/Saturday
    final mondayMorning = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 9, 8, 15));
    expect(mondayMorning, contains('Boldog hétfőt (nem), {name}'));
    expect(mondayMorning, isNot(contains('Végre péntek, {name}!')));

    final fridayEvening = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 13, 19, 30));
    expect(fridayEvening, contains('Végre péntek, {name}!'));
    expect(fridayEvening, contains('Esti chill, {name}?'));
    expect(fridayEvening, isNot(contains('Holnap suli, {name}...')));

    // Weekday-only school guard: Saturday 07:30 & Sunday 11:00 must NEVER include school pools
    final saturdayEarly = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 14, 7, 30));
    expect(saturdayEarly, contains('Hétvégén Kréta, {name}?'));
    expect(saturdayEarly, isNot(contains('Kávé volt már, {name}?')));
    expect(saturdayEarly, isNot(contains('Indul a műszak, {name}')));
    expect(saturdayEarly, isNot(contains('Kitartást mára, {name}!')));
    expect(saturdayEarly, isNot(contains('Szép délutánt, {name}!')));

    final sundayDay = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 15, 11, 0));
    expect(sundayDay, contains('Ma nincs suli, {name}!'));
    expect(sundayDay, isNot(contains('Mikor lesz már szünet, {name}?')));

    final sundayEvening = GreetingUtils.eligibleFunTemplatesFor(DateTime(2026, 11, 15, 19, 30));
    expect(sundayEvening, contains('Vasárnap esti pánik, {name}?'));
    expect(sundayEvening, contains('Holnap suli, {name}...'));
    expect(sundayEvening, contains('Esti chill, {name}?'));
    expect(sundayEvening, isNot(contains('Ma nincs suli, {name}!')));
  });

  test('GreetingUtils stabilizes fun greeting per session window and avoids back-to-back repeats', () {
    GreetingUtils.resetForTesting(random: Random(42));

    // Stock behavior unaffected when funGreetingsEnabled is false
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 9, 0),
        funGreetingsEnabled: false,
      ),
      'Szép napot, Milán!',
    );

    final first = GreetingUtils.buildGreeting(
      name: 'Milán',
      now: DateTime(2026, 11, 10, 9, 0),
      funGreetingsEnabled: true,
    );
    expect(first, contains('Milán'));
    expect(first.contains('{name}'), isFalse);

    // Repeated rebuilds across different times in the same app session keep the exact cold-start greeting.
    final secondSameSession = GreetingUtils.buildGreeting(
      name: 'Milán',
      now: DateTime(2026, 11, 10, 23, 15),
      funGreetingsEnabled: true,
    );
    expect(secondSameSession, equals(first));

    // Explicit settings toggle refresh (or app restart) picks a fresh non-repeating greeting.
    GreetingUtils.resetForTesting(random: _ZeroRandom());
    final r1 = GreetingUtils.buildGreeting(
      name: 'Bence',
      now: DateTime(2026, 11, 10, 9, 0),
      funGreetingsEnabled: true,
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Bence',
        now: DateTime(2026, 11, 10, 14, 0),
        funGreetingsEnabled: true,
      ),
      equals(r1),
    );
    GreetingUtils.refreshSessionGreeting();
    final r2 = GreetingUtils.buildGreeting(
      name: 'Bence',
      now: DateTime(2026, 11, 10, 9, 0),
      funGreetingsEnabled: true,
    );
    expect(r2, isNot(equals(r1)));
    expect(r2, contains('Bence'));
  });

  test('GitHubUpdaterService compares semantic versions and build tags accurately', () {
    expect(
      GitHubUpdaterService.repoUrl,
      'https://github.com/mlnlbrt10/tinta-naplo',
    );
    expect(
      GitHubUpdaterService.latestReleaseApiUrl,
      'https://api.github.com/repos/mlnlbrt10/tinta-naplo/releases/latest',
    );
    expect(GitHubUpdaterService.fallbackAppVersion, '3.0.1');
    expect(GitHubUpdaterService.fallbackBuildNumber, '20');
    expect(
      GitHubUpdaterService.defaultApkFileName,
      'tinta-naplo-v3.0.1-arm64-v8a.apk',
    );
    expect(
      GitHubUpdaterService.apkFileNameForTag('v3.0.0'),
      'tinta-naplo-v3.0.0-arm64-v8a.apk',
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('3.0.0', 'v3.0.1'),
      isTrue,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('3.0.0', 'v3.0.0'),
      isFalse,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('3.0.0-alpha', 'v3.0.0'),
      isTrue,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('3.0.0-alpha', 'v3.0.0-alpha'),
      isFalse,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('3.0.0', 'v1.2.0'),
      isFalse,
    );
    // Legacy pre-rebrand v1.2.x / v1.1.x tags must not prompt updates on v1.0.0.
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.0', 'v1.2.7'),
      isFalse,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.0', 'v1.1.9'),
      isFalse,
    );
    const unbrandedRelease = GitHubReleaseInfo(
      tagName: 'v3.9.9',
      title: 'Legacy Client v3.9.9',
      releaseNotes: 'Unbranded release',
      htmlUrl: GitHubUpdaterService.repoUrl,
      apkDownloadUrl: 'https://example.com/legacy-v3.9.9.apk',
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer(
        '3.0.0',
        'v3.9.9',
        release: unbrandedRelease,
      ),
      isFalse,
    );
    final brandedFutureRelease = GitHubReleaseInfo.fromJson({
      'tag_name': 'v3.0.0',
      'name': 'Tinta Napló v3.0.0',
      'body': 'Újdonságok',
      'html_url': 'https://github.com/mlnlbrt10/tinta-naplo/releases/tag/v3.0.0',
      'assets': [
        {
          'name': 'app-release.apk',
          'browser_download_url': 'https://example.com/app-release.apk',
        },
        {
          'name': 'app-armeabi-v7a-release.apk',
          'browser_download_url': 'https://example.com/app-armeabi-v7a-release.apk',
        },
        {
          'name': 'tinta-naplo-v3.0.0-arm64-v8a.apk',
          'browser_download_url': 'https://example.com/tinta-naplo-v3.0.0-arm64-v8a.apk',
        },
      ],
    });
    expect(
      brandedFutureRelease.apkDownloadUrl,
      'https://example.com/tinta-naplo-v3.0.0-arm64-v8a.apk',
    );
    final splitArm64FallbackRelease = GitHubReleaseInfo.fromJson({
      'tag_name': 'v3.0.1',
      'name': 'Tinta Napló v3.0.1',
      'assets': [
        {
          'name': 'app-armeabi-v7a-release.apk',
          'browser_download_url': 'https://example.com/app-armeabi-v7a-release.apk',
        },
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url': 'https://example.com/app-arm64-v8a-release.apk',
        },
      ],
    });
    expect(
      splitArm64FallbackRelease.apkDownloadUrl,
      'https://example.com/app-arm64-v8a-release.apk',
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer(
        '1.0.0',
        'v3.0.0',
        release: brandedFutureRelease,
      ),
      isTrue,
    );
    final fallbackApkRelease = GitHubReleaseInfo.fromJson({
      'tag_name': 'v1.0.1',
      'name': 'Tinta Napló v1.0.1',
      'assets': [
        {
          'name': 'custom-build.apk',
          'browser_download_url': 'https://example.com/custom-build.apk',
        },
      ],
    });
    expect(
      fallbackApkRelease.apkDownloadUrl,
      'https://example.com/custom-build.apk',
    );
    expect(
      fallbackApkRelease.htmlUrl,
      'https://github.com/mlnlbrt10/tinta-naplo/releases',
    );
  });

  test('MenetrendService builds evaluation from real trips only', () {
    final day = DateTime(2026, 11, 11);
    final lessons = <Lesson>[
      _makeLesson(
        lessonNumber: 1,
        start: DateTime(2026, 11, 11, 7, 50),
        end: DateTime(2026, 11, 11, 8, 35),
      ),
    ];
    const prefs = UserProfilePrefs(walkingDurationMinutes: 10);
    expect(prefs.transitConfigured, isFalse);
    expect(prefs.transitCardEnabled, isFalse);

    MenetrendTripOption trip(int h, int m) => MenetrendTripOption(
          routeShortName: 'X',
          routeLongName: 'Y',
          mode: MenetrendTransportMode.rail,
          departureStation: 'A',
          arrivalStation: 'B',
          scheduledDeparture: DateTime(day.year, day.month, day.day, h, m),
          scheduledArrival: DateTime(day.year, day.month, day.day, h, m + 30),
          walkToStationMinutes: 10,
        );

    expect(
      MenetrendService.buildEvaluation(
        trips: const [],
        isMorning: true,
        firstLesson: lessons.first,
        lastLesson: lessons.first,
        prefs: prefs,
        effectiveWalk: 10,
        now: DateTime(2026, 11, 11, 6, 30),
      ),
      isNull,
    );

    final eval = MenetrendService.buildEvaluation(
      trips: [trip(6, 0), trip(7, 9), trip(7, 40)],
      isMorning: true,
      firstLesson: lessons.first,
      lastLesson: lessons.first,
      prefs: prefs,
      effectiveWalk: 10,
      now: DateTime(2026, 11, 11, 6, 30),
    )!;
    expect(eval.recommendedTrip.departureTimeFormatted, '07:09');
  });

  test('Scholarship recommendations target cumulative weighted average without requiring every subject >= 4.00', () {
    final g1 = _makeGrade(
      uid: 'g1',
      subjectUid: 's1',
      subjectName: 'Szakmai tantárgy (200%)',
      numericValue: 3,
      weightPercentage: 200,
    );
    final g2 = _makeGrade(
      uid: 'g2',
      subjectUid: 's2',
      subjectName: 'Történelem',
      numericValue: 5,
      weightPercentage: 200,
    );
    final allGrades = <Grade>[g1, g2]; // cumulative average = (3*200 + 5*200)/400 = 4.00!

    final subjects = <SubjectGradeSummary>[
      SubjectGradeSummary(
        subjectUid: 's1',
        subjectName: 'Szakmai tantárgy (200%)',
        categoryDescription: 'Szakmai',
        grades: [g1],
        weightedAverage: 3.00,
        latestGrade: g1,
      ),
      SubjectGradeSummary(
        subjectUid: 's2',
        subjectName: 'Történelem',
        categoryDescription: 'Közismereti',
        grades: [g2],
        weightedAverage: 5.00,
        latestGrade: g2,
      ),
    ];

    // Overall weighted average is 4.00 -> target 4.00 is ALREADY reached
    // even though 'Szakmai tantárgy (200%)' has a 3.00 subject average (< 4.00)!
    final recsFor400 = SubjectGradeSummary.buildScholarshipRecommendations(
      allGrades: allGrades,
      subjects: subjects,
      targetAverage: 4.00,
    );
    expect(recsFor400, isEmpty);

    // Default (100% weight) target 4.50 -> calculates using strictly 100% grades
    final recsFor450Default = SubjectGradeSummary.buildScholarshipRecommendations(
      allGrades: allGrades,
      subjects: subjects,
      targetAverage: 4.50,
    );
    expect(recsFor450Default, isNotEmpty);
    expect(recsFor450Default.first.recommendedWeight, 100);
    expect(recsFor450Default.first.subjectName, 'Szakmai tantárgy (200%)');
    expect(recsFor450Default.first.explanation, contains('->'));
    expect(
      recsFor450Default.first.resultingOverallAverage,
      greaterThanOrEqualTo(4.50),
    );

    // When 200% témazáró is enabled -> uses 200% weight grades
    final recsFor450With200 = SubjectGradeSummary.buildScholarshipRecommendations(
      allGrades: allGrades,
      subjects: subjects,
      targetAverage: 4.50,
      allow200Weight: true,
    );
    expect(recsFor450With200, isNotEmpty);
    expect(recsFor450With200.first.recommendedWeight, 200);
    expect(recsFor450With200.first.subjectName, 'Szakmai tantárgy (200%)');
  });

  test('Timetable filterLessonsForDisplay synthesizes inactive 1st period when school starts later', () {
    final lessonsStartingAtPeriod2 = <Lesson>[
      _makeLesson(
        lessonNumber: 2,
        start: DateTime(2026, 11, 11, 8, 55),
        end: DateTime(2026, 11, 11, 9, 40),
      ),
    ];

    final shownWithToggleOn = filterLessonsForDisplay(
      lessonsStartingAtPeriod2,
      hideCancelled: false,
      hideFree: false,
    );
    expect(shownWithToggleOn.length, 2);
    expect(shownWithToggleOn.first.lessonNumber, 1);
    expect(isInactivePlaceholderLesson(shownWithToggleOn.first), isTrue);

    final shownWithToggleOff = filterLessonsForDisplay(
      lessonsStartingAtPeriod2,
      hideCancelled: false,
      hideFree: true,
    );
    expect(shownWithToggleOff.length, 1);
    expect(shownWithToggleOff.first.lessonNumber, 2);
  });

  test('UserProfilePrefs serializes MenetrendGO and ModalCloseButtonMode settings', () {
    const prefs = UserProfilePrefs(
      modalCloseMode: ModalCloseButtonMode.onlyX,
      transitHomeStation: 'Mór',
      transitSchoolStation: 'Székesfehérvár',
      walkingSpeedKmh: 5.5,
      walkingDurationMinutes: 12,
      transitAlertBufferMinutes: 6,
      favoriteRoute1stPeriod: '07:09',
    );
    final jsonStr = prefs.toExportJsonString();
    final restored = UserProfilePrefs.fromExportJsonString(jsonStr);
    expect(restored.modalCloseMode, ModalCloseButtonMode.onlyX);
    expect(restored.modalCloseMode.showTopX, isTrue);
    expect(restored.modalCloseMode.showBottomButton, isFalse);
    expect(restored.transitHomeStation, 'Mór');
    expect(restored.walkingSpeedKmh, 5.5);
    expect(restored.walkingDurationMinutes, 12);
    expect(restored.transitAlertBufferMinutes, 6);
    expect(restored.favoriteRoute1stPeriod, '07:09');
  });

  test('KretaClient transparent token refresh interceptor retries HTTP 401 and replays request', () async {
    int apiCalls = 0;
    int tokenRefreshCalls = 0;

    final mockHttp = MockClient((request) async {
      if (request.url.toString().contains('/connect/token')) {
        tokenRefreshCalls++;
        return http.Response(
          '{"access_token":"fresh_token_123","refresh_token":"fresh_refresh_456","id_token":"id_123","token_type":"Bearer","expires_in":1800}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      apiCalls++;
      final authHeader = request.headers['Authorization'] ?? '';
      if (authHeader == 'Bearer expired_token') {
        return http.Response('Unauthorized', 401);
      }
      if (authHeader == 'Bearer fresh_token_123') {
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('Unexpected token: $authHeader', 500);
    });

    final storage = _InMemoryTokenStorage();
    final initialSession = StoredSession(
      accessToken: 'expired_token',
      refreshToken: 'old_refresh',
      idToken: 'old_id',
      instituteCode: 'klik123456',
      userName: 'Teszt Elek',
      expiresAt: DateTime.now().add(const Duration(minutes: 20)),
    );
    storage.savedSession = initialSession;

    final client = KretaClient(httpClient: mockHttp, storage: storage);
    final grades = await client.fetchAllGrades(initialSession);

    expect(grades, isEmpty);
    expect(tokenRefreshCalls, 1);
    expect(apiCalls, 2);
    expect(storage.savedSession?.accessToken, 'fresh_token_123');
    expect(storage.savedSession?.refreshToken, 'fresh_refresh_456');
    expect(const TokenExpiredException().toString(), isNot(contains('Instance of')));
  });

  test('Grade.recordedAt uses KeszitesDatuma real timestamp instead of 00:00 RogzitesDatuma', () {
    final grade = Grade.fromJson({
      'Uid': 'g_time_1',
      'RogzitesDatuma': '2026-11-12T00:00:00',
      'KeszitesDatuma': '2026-11-12T13:42:00',
      'Tantargy': {
        'Uid': 'sub_math',
        'Nev': 'Matematika',
        'Kategoria': {'Uid': 'c1', 'Nev': 'Matematika', 'Leiras': 'Matematika'},
        'SortIndex': 1,
      },
      'Tema': 'Röpdolgozat',
      'Tipus': {
        'Uid': 'evkozi_jegy_ertekeles',
        'Nev': 'evkozi_jegy_ertekeles',
        'Leiras': 'Évközi jegy',
      },
      'Mod': {'Uid': 'm1', 'Nev': 'Írásbeli', 'Leiras': 'Írásbeli'},
      'ErtekFajta': {'Uid': '1', 'Nev': 'Otfokozatu', 'Leiras': 'Ötfokozatú'},
      'ErtekeloTanarNeve': 'Teszt Tanár',
      'SzamErtek': 5,
      'SzovegesErtek': 'Jeles(5)',
      'SulySzazalekErteke': 100,
      'OsztalyCsoport': {'Uid': 'g1'},
      'SortIndex': 1,
    });

    expect(grade.recordedAt.hour, 13);
    expect(grade.recordedAt.minute, 42);
  });

  test('Homework.fromJson handles null TantargyNeve & HTML Szoveg and links to Lesson', () {
    final hw = Homework.fromJson({
      'Uid': '987654,TanarHaziFeladat',
      'Tantargy': {
        'Uid': 'sub_hist',
        'Nev': 'Történelem',
        'Kategoria': {'Uid': 'c2', 'Nev': 'Történelem', 'Leiras': 'Történelem'},
        'SortIndex': 2,
      },
      'TantargyNeve': null,
      'RogzitoTanarNeve': 'Kovács Tanárnő',
      'Szoveg': '<p>Olvasd el a <b>45. oldalt</b>!&nbsp;</p>',
      'FeladasDatuma': '2026-11-11T00:00:00Z',
      'HataridoDatuma': '2026-11-13T23:59:00Z',
      'RogzitesIdopontja': '2026-11-11T10:15:00Z',
      'IsTanarRogzitette': true,
      'IsMegoldva': false,
      'IsBeadhato': false,
      'OsztalyCsoport': {'Uid': 'cg1'},
      'IsCsatolasEngedelyezes': false,
    });

    expect(hw.subject.name, 'Történelem');
    expect(hw.subjectName, 'Történelem');
    expect(hw.description, 'Olvasd el a 45. oldalt!');

    final lesson = _makeLesson(
      lessonNumber: 3,
      start: DateTime(2026, 11, 11, 10, 0),
      end: DateTime(2026, 11, 11, 10, 45),
    );
    final lessonWithHwUid = Lesson.fromJson({
      ...lesson.toJson(),
      'HaziFeladatUid': '987654',
    });

    final matched = KretaClient.findHomeworkForLesson(lessonWithHwUid, [hw]);
    expect(matched, isNotNull);
    expect(matched!.uid, hw.uid);
    expect(
      KretaClient.getFirstSchoolDay(DateTime(2026, 11, 12)),
      DateTime(2026, 9, 1),
    );
  });

  test('KretaClient single-flight lock serializes concurrent expired-token refreshes', () async {
    int tokenRefreshCalls = 0;

    final mockHttp = MockClient((request) async {
      if (request.url.toString().contains('/connect/token')) {
        tokenRefreshCalls++;
        if (tokenRefreshCalls > 1) {
          return http.Response('{"error":"invalid_grant"}', 400);
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final bodyParams = Uri.splitQueryString(request.body);
        expect(bodyParams['refresh_token'], 'rotate_tok_1');
        return http.Response(
          '{"access_token":"rotated_acc_2","refresh_token":"rotate_tok_2","id_token":"id_2","token_type":"Bearer","expires_in":1800}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.headers['Authorization'] == 'Bearer rotated_acc_2') {
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('Unauthorized', 401);
    });

    final storage = _InMemoryTokenStorage();
    final initialSession = StoredSession(
      accessToken: 'expired_acc_1',
      refreshToken: 'rotate_tok_1',
      idToken: 'id_1',
      instituteCode: 'klik123456',
      userName: 'Single Flight User',
      // Within the 2-minute proactive refresh window
      expiresAt: DateTime.now().add(const Duration(seconds: 90)),
    );
    storage.savedSession = initialSession;

    final client = KretaClient(httpClient: mockHttp, storage: storage);
    final results = await Future.wait([
      client.fetchAllGrades(initialSession),
      client.fetchTests(initialSession),
      client.fetchOmissions(initialSession),
    ]);

    expect(results.length, 3);
    expect(tokenRefreshCalls, 1);
    expect(storage.savedSession?.accessToken, 'rotated_acc_2');
    expect(storage.savedSession?.refreshToken, 'rotate_tok_2');
  });

  test('Transient HTTP 503 during token refresh does NOT throw InvalidGrantException', () async {
    final mockHttp = MockClient((request) async {
      if (request.url.toString().contains('/connect/token')) {
        return http.Response('Service Unavailable', 503);
      }
      return http.Response('[]', 200);
    });

    final storage = _InMemoryTokenStorage();
    final session = StoredSession(
      accessToken: 'expired_acc',
      refreshToken: 'still_valid_refresh',
      idToken: 'id',
      instituteCode: 'klik123456',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );
    storage.savedSession = session;

    expect(
      () => storage.refreshToken(session: session, httpClient: mockHttp),
      throwsA(isNot(isA<InvalidGrantException>())),
    );
  });
}
