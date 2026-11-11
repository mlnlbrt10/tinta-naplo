import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:rekreta_app/core/kreta_auth_config.dart';
import 'package:rekreta_app/screens/grades_screen.dart';
import 'package:rekreta_app/screens/timetable_screen.dart';
import 'package:rekreta_app/services/github_updater_service.dart';
import 'package:rekreta_app/services/kreta_client.dart';
import 'package:rekreta_app/services/menetrend_service.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/utils/greeting_utils.dart';
import 'package:rekreta_app/utils/uwu_helper.dart';

class _InMemoryTokenStorage extends TokenStorageService {
  StoredSession? savedSession;

  @override
  Future<void> saveSession(StoredSession session) async {
    savedSession = session;
  }

  @override
  Future<StoredSession?> loadSession() async => savedSession;
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

  test('GreetingUtils resolves nickname or falls back to Milán / first name', () {
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
      'Milán',
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

  test('UwuHelper and GreetingUtils transform text in UwU mode and Tsundere mode', () {
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 12, 0),
        uwuMode: true,
      ),
      'Szép nyapot, Miwán! uwu',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 12, 0),
        tsundereMode: true,
      ),
      contains('b-baka'),
    );
    expect(
      UwuHelper.tsundereCommentForGrade(3),
      contains('M-megint egy hármas? Nem mintha figyeltem volna rád'),
    );
    expect(
      UwuHelper.tsundereCommentForGrade(null),
      contains('N-nem mintha érdekelne a házi feladatod, b-baka~!'),
    );
    expect(
      UwuHelper.transform(
        'Házi feladatok',
        enabled: false,
        tsundere: true,
      ),
      contains('b-baka~!'),
    );
    final transformed = UwuHelper.transform('Frissítések keresése', enabled: true);
    expect(transformed.startsWith('Fwissítések kewesése'), isTrue);
  });

  test('GitHubUpdaterService compares semantic versions and build tags accurately', () {
    expect(GitHubUpdaterService.fallbackAppVersion, '1.2.0');
    expect(GitHubUpdaterService.fallbackBuildNumber, '4');
    expect(GitHubUpdaterService.defaultApkFileName, 'reKRETA-v1.2.0.apk');
    expect(GitHubUpdaterService.apkFileNameForTag('v1.2.0'), 'reKRETA-v1.2.0.apk');
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.2.0', 'v1.2.1'),
      isTrue,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.2.0', 'v1.2.0'),
      isFalse,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.0-alpha', 'v1.0.0'),
      isTrue,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.0-alpha', 'v1.2.0-alpha'),
      isTrue,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.0-alpha', 'v1.0.0-alpha'),
      isFalse,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.2.0', 'v1.1.9'),
      isFalse,
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

    // Target 4.50 requires lifting cumulative average -> prioritizes 200% subject
    final recsFor450 = SubjectGradeSummary.buildScholarshipRecommendations(
      allGrades: allGrades,
      subjects: subjects,
      targetAverage: 4.50,
    );
    expect(recsFor450, isNotEmpty);
    expect(recsFor450.first.steps.first.weight, 200);
    expect(recsFor450.first.steps.first.subjectName, 'Szakmai tantárgy (200%)');
    expect(recsFor450.first.resultingOverallAverage, greaterThanOrEqualTo(4.50));
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
      showCancelledLessons: true,
    );
    expect(shownWithToggleOn.length, 2);
    expect(shownWithToggleOn.first.lessonNumber, 1);
    expect(isInactivePlaceholderLesson(shownWithToggleOn.first), isTrue);

    final shownWithToggleOff = filterLessonsForDisplay(
      lessonsStartingAtPeriod2,
      showCancelledLessons: false,
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
}
