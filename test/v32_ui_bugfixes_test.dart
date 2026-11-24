import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/screens/grades_screen.dart';
import 'package:tinta_naplo/screens/home_screen.dart';
import 'package:tinta_naplo/screens/school_year_schedule_screen.dart';
import 'package:tinta_naplo/services/demo_data_service.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/school_year_schedule_service.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/widgets/animation_helpers.dart';
import 'package:tinta_naplo/widgets/expandable_profile_card.dart';

StoredSession _testSession() => StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik-v32-test',
      userName: 'tesztdiak',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

Grade _makeGrade({
  required String uid,
  required String subjectName,
  required int value,
  String topic = 'Témazáró',
}) {
  final iso = DateTime(2026, 11, 20, 10, 0).toUtc().toIso8601String();
  return Grade.fromJson({
    'Uid': uid,
    'RogzitesDatuma': iso,
    'KeszitesDatuma': iso,
    'LattamozasDatuma': iso,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'c', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': 1,
    },
    'Tema': topic,
    'Tipus': {'Uid': 'ev', 'Nev': 'Evkozi', 'Leiras': 'Évközi'},
    'Mod': {'Uid': 'm', 'Nev': 'Irasbeli', 'Leiras': 'Írásbeli'},
    'ErtekFajta': {'Uid': 'j', 'Nev': 'Jegy', 'Leiras': 'Jegy'},
    'ErtekeloTanarNeve': 'Dr. Nagy Béla',
    'SzamErtek': value,
    'SzovegesErtek': '$value',
    'SzovegesErtekelesRovidNev': '$value',
    'SulySzazalekErteke': 100,
    'SortIndex': 1,
  });
}

Homework _makeHomework({
  required String uid,
  required DateTime dueDate,
  required String subjectName,
  required String description,
}) {
  return Homework(
    uid: uid,
    subject: Subject(
      uid: 'sub_$subjectName',
      name: subjectName,
      category: NameUidDesc(uid: 'cat', name: subjectName, description: ''),
      sortIndex: 0,
    ),
    subjectName: subjectName,
    teacherName: 'Teszt Tanár',
    description: description,
    startDate: dueDate.subtract(const Duration(days: 1)),
    dueDate: dueDate,
    creationDate: dueDate.subtract(const Duration(days: 1)),
    isCreatedByTeacher: true,
    isDone: false,
    canBeSubmitted: false,
    classGroup: UidObj(uid: 'grp-1'),
    canAttach: false,
  );
}

Test _makeTest({
  required String uid,
  required DateTime date,
  required String subjectName,
  String? theme,
  int lessonNumber = 2,
}) {
  return Test(
    uid: uid,
    date: date,
    reportDate: date.subtract(const Duration(days: 3)),
    teacherName: 'Kiss Anna',
    lessonNumber: lessonNumber,
    subject: Subject(
      uid: 'sub_$subjectName',
      name: subjectName,
      category: NameUidDesc(uid: 'cat', name: subjectName, description: ''),
      sortIndex: 0,
    ),
    subjectName: subjectName,
    theme: theme,
    method: NameUidDesc(
      uid: 'm_$uid',
      name: 'Dolgozat',
      description: 'Dolgozat',
    ),
    classGroup: UidObj(uid: 'grp-1'),
  );
}

Lesson _makeLesson({
  required String uid,
  required DateTime start,
  required String subjectName,
  int lessonNumber = 1,
}) {
  final end = start.add(const Duration(minutes: 45));
  final dayIso = '${start.toIso8601String().split('T').first}T00:00:00Z';
  return Lesson(
    uid: uid,
    date: dayIso,
    start: start,
    end: end,
    name: subjectName,
    subject: Subject(
      uid: 'sub_$subjectName',
      name: subjectName,
      category: NameUidDesc(uid: 'c', name: subjectName, description: ''),
      sortIndex: lessonNumber,
    ),
    lessonNumber: lessonNumber,
    lessonSeqNumber: lessonNumber,
    teacher: 'Eredeti Tanár',
    roomName: '204',
    type: NameUidDesc(uid: 't', name: 'Tanora', description: 'Tanóra'),
    state: NameUidDesc(uid: 'm', name: 'Megtartott', description: 'Megtartott'),
    canStudentEditHomework: false,
    isHomeworkComplete: false,
    attachments: const [],
    isDigitalLesson: false,
    digitalSupportDeviceTypeList: const [],
    createdAt: start,
    lastModifiedAt: start,
  );
}

Omission _makeOmission({
  required String uid,
  required String subjectName,
  required DateTime date,
  required OmissionState state,
}) {
  final start = DateTime(date.year, date.month, date.day, 8, 0);
  final end = start.add(const Duration(minutes: 45));
  return Omission.fromJson({
    'Uid': uid,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'cat', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': 1,
    },
    'Ora': {
      'KezdoDatum': start.toUtc().toIso8601String(),
      'VegDatum': end.toUtc().toIso8601String(),
      'Oraszam': 1,
    },
    'Datum': date.toUtc().toIso8601String(),
    'RogzitoTanarNeve': 'Teszt Tanár',
    'Tipus': {
      'Uid': 'hiany',
      'Nev': 'OrarolValoHianyzas',
      'Leiras': 'Óráról való hiányzás',
    },
    'KesesPercben': null,
    'KeszitesDatuma': start.toUtc().toIso8601String(),
    'IgazolasAllapota': state.key,
  });
}

class _CountingHomeKretaClient extends KretaClient {
  final DashboardData data;
  int fetchCount = 0;

  _CountingHomeKretaClient(this.data)
      : super(
          httpClient: MockClient((_) async => http.Response('[]', 200)),
          storage: const TokenStorageService(),
        );

  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async =>
      data;

  @override
  Future<DashboardData> fetchDashboardData(
    StoredSession initialSession, {
    DateTime? date,
  }) async {
    fetchCount++;
    return data;
  }
}

void main() {
  group('Bug 1 (#MWUU47WJ): Unified Főoldal pull-to-refresh scroll view', () {
    testWidgets(
      'Főoldal uses a single unified CustomScrollView with AlwaysScrollableScrollPhysics(BouncingScrollPhysics) and pulls the igazolandó hiányzás card down with the lower list',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime(2026, 11, 23, 10, 0);
        final session = _testSession();
        final cached = DashboardData(
          student: null,
          todaysLessons: [
            _makeLesson(
              uid: 'l-1',
              start: DateTime(2026, 11, 23, 11, 0),
              subjectName: 'Fizika',
            ),
          ],
          allGrades: [
            _makeGrade(
              uid: 'g-1',
              subjectName: 'Matematika',
              value: 5,
              topic: 'Integrálszámítás',
            ),
          ],
          latestGrades: [
            _makeGrade(
              uid: 'g-1',
              subjectName: 'Matematika',
              value: 5,
              topic: 'Integrálszámítás',
            ),
          ],
          homeworks: [
            _makeHomework(
              uid: 'hw-1',
              dueDate: now.add(const Duration(days: 1)),
              subjectName: 'Biológia',
              description: 'Házi feladat teszt',
            ),
          ],
          tests: const [],
          omissions: [
            _makeOmission(
              uid: 'om-pending-1',
              subjectName: 'Történelem',
              date: now.subtract(const Duration(days: 1)),
              state: OmissionState.pending,
            ),
          ],
          activeSession: session,
        );

        final client = _CountingHomeKretaClient(cached);
        const prefs = UserProfilePrefs();
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: HomeScreen(
              initialSession: session,
              initialCachedData: cached,
              kretaClient: client,
              prefs: prefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => now,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NestedScrollView), findsNothing);
        final loadedScrollFinder = find.byKey(
          const ValueKey<String>('home-loaded-content'),
        );
        expect(loadedScrollFinder, findsOneWidget);
        final customScroll = tester.widget<CustomScrollView>(loadedScrollFinder);
        expect(customScroll.physics, isA<AlwaysScrollableScrollPhysics>());
        expect(
          (customScroll.physics as AlwaysScrollableScrollPhysics).parent,
          isA<BouncingScrollPhysics>(),
        );

        final bannerFinder = find.byKey(
          const ValueKey<String>('home-unexcused-banner'),
        );
        expect(bannerFinder, findsOneWidget);
        final initialBannerTop = tester.getTopLeft(bannerFinder).dy;
        final swipeFeedFinder = find.byKey(
          const ValueKey<String>('home-subtab-swipe'),
        );
        expect(swipeFeedFinder, findsOneWidget);
        final initialFeedTop = tester.getTopLeft(swipeFeedFinder).dy;

        // Pull down starting on the lower feed list and hold mid-drag:
        // BOTH the top igazolandó banner AND the lower list must move downward together.
        final initialFetches = client.fetchCount;
        final pullStart = tester.getCenter(swipeFeedFinder);
        final gesture = await tester.startGesture(pullStart);
        for (int i = 0; i < 10; i++) {
          await gesture.moveBy(const Offset(0, 36));
          await tester.pump(const Duration(milliseconds: 16));
        }

        final pulledBannerTop = tester.getTopLeft(bannerFinder).dy;
        final pulledFeedTop = tester.getTopLeft(swipeFeedFinder).dy;
        expect(pulledBannerTop, greaterThan(initialBannerTop + 100));
        expect(pulledFeedTop, greaterThan(initialFeedTop + 100));
        expect(
          pulledBannerTop - initialBannerTop,
          closeTo(pulledFeedTop - initialFeedTop, 20.0),
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(client.fetchCount, greaterThan(initialFetches));
      },
    );
  });

  group('Bug 2 (#MWUU6KOT): Profile avatar camera icon Hero isolation', () {
    testWidgets(
      'Hero wraps only the circular avatar and camera badge appears strictly after the route transition completes',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const prefs = UserProfilePrefs(liquidGlassEnabled: true);
        final student = DemoDataService.instance.buildDemoStudent();
        final session = StoredSession(
          accessToken: 'acc',
          refreshToken: 'ref',
          idToken: 'id',
          instituteCode: 'real-school',
          userName: 'teszt',
          expiresAt: DateTime.now().add(const Duration(hours: 2)),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  actions: [
                    ProfileTopBarAvatar(
                      prefs: prefs,
                      onTap: () => showStreamlinedProfileSheet(
                        context: context,
                        student: student,
                        session: session,
                        prefs: prefs,
                        onPrefsChanged: (_) {},
                        onOpenFullSettings: () {},
                      ),
                    ),
                  ],
                ),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.pump();

        // Tap top-bar avatar to start Hero route transition (340ms duration)
        await tester.tap(find.byType(ProfileTopBarAvatar));
        await tester.pump();
        // At 260ms (~76% through the 340ms route transition), camera badge must
        // still be hidden so it never detaches or glitches during Hero flight.
        await tester.pump(const Duration(milliseconds: 260));
        expect(
          find.byKey(const ValueKey<String>('profile-avatar-camera-badge')),
          findsNothing,
        );

        // Once route transition completes and badge reveal runs, camera badge is visible
        // and sits OUTSIDE the Hero widget.
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('profile-floating-sheet-surface')),
          findsOneWidget,
        );
        final camBadgeFinder = find.byKey(
          const ValueKey<String>('profile-avatar-camera-badge'),
        );
        expect(camBadgeFinder, findsOneWidget);
        final heroAncestorOfBadge = find.ancestor(
          of: camBadgeFinder,
          matching: find.byType(Hero),
        );
        expect(heroAncestorOfBadge, findsNothing);

        // Dismiss via top scrim tap -> badge disappears immediately on reverse
        await tester.tapAt(const Offset(20, 80));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(camBadgeFinder, findsNothing);

        await tester.pumpAndSettle();
      },
    );
  });

  group('Bug 3 (#MWUU7WM7): Tanév rendje header clipping & SafeArea', () {
    for (final liquidGlass in [true, false]) {
      testWidgets(
        'Tanév rendje pins AppBar cleanly above ClipRect body so scrolled hero card never bleeds into title or status bar (liquidGlass: $liquidGlass)',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final prefs = UserProfilePrefs(liquidGlassEnabled: liquidGlass);
          final service = SchoolYearScheduleService(
            httpClient: MockClient((_) async => http.Response('err', 500)),
            nowProvider: () => DateTime(2026, 11, 20),
          );

          await tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(
                size: Size(412, 850),
                padding: EdgeInsets.only(top: 24),
              ),
              child: MaterialApp(
                theme: OledTheme.buildTheme(prefs: prefs),
                home: SchoolYearScheduleScreen(
                  student: null,
                  instituteCode: 'klik-clip-test',
                  prefs: prefs,
                  scheduleService: service,
                  clock: () => DateTime(2026, 11, 20),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final appBarFinder = find.byType(AppBar);
          final titleFinder = find.text('Tanév rendje');
          final nestedFinder = find.byType(NestedScrollView);
          expect(appBarFinder, findsOneWidget);
          expect(titleFinder, findsOneWidget);
          expect(nestedFinder, findsOneWidget);

          final appBarRect = tester.getRect(appBarFinder);
          expect(appBarRect.top, closeTo(0.0, 0.5));
          expect(tester.getTopLeft(titleFinder).dy, greaterThanOrEqualTo(24.0));

          final bodyClipRect = tester.getRect(
            find
                .ancestor(
                  of: nestedFinder,
                  matching: find.byType(ClipRect),
                )
                .first,
          );
          expect(
            bodyClipRect.top,
            greaterThanOrEqualTo(appBarRect.bottom - 0.5),
          );

          // Scroll down aggressively; AppBar stays pinned and body ClipRect
          // remains strictly below AppBar.bottom.
          final countdownBtn = find.byKey(
            const ValueKey<String>('school-year-countdown-target-btn'),
          );
          expect(
            tester.getTopLeft(countdownBtn).dy,
            greaterThanOrEqualTo(appBarRect.bottom),
          );
          await tester.fling(nestedFinder, const Offset(0, -500), 1800);
          await tester.pumpAndSettle();

          expect(tester.getRect(appBarFinder), appBarRect);
          final afterClipRect = tester.getRect(
            find
                .ancestor(
                  of: nestedFinder,
                  matching: find.byType(ClipRect),
                )
                .first,
          );
          expect(
            afterClipRect.top,
            greaterThanOrEqualTo(appBarRect.bottom - 0.5),
          );
        },
      );
    }
  });

  group('Bug 4 (#MWUVC0U2): Tanév rendje event popups & holiday range merging', () {
    test(
      'Merges consecutive single-day break/holiday rows (HTML, short MM. dd., ICS, and cached JSON) into single startDate–endDate range',
      () {
        const htmlWithDuplicateDays = '''
          <html><body>
            <table>
              <tr><td>2027.01.03.</td><td>Téli szünet</td></tr>
              <tr><td>2027.01.04.</td><td>Téli szünet</td></tr>
              <tr><td>04. 02.</td><td>Tavaszi szünet</td></tr>
              <tr><td>04. 03.</td><td>Tavaszi szünet</td></tr>
            </table>
          </body></html>
        ''';
        final parsedHtml = SchoolYearScheduleService.parseScheduleFromHtml(
          htmlWithDuplicateDays,
          2026,
        );
        final winterBreaks =
            parsedHtml.where((e) => e.title == 'Téli szünet').toList();
        expect(winterBreaks.length, 1);
        expect(winterBreaks.first.startDate, DateTime(2027, 1, 3));
        expect(winterBreaks.first.endDate, DateTime(2027, 1, 4));
        expect(winterBreaks.first.durationDays, 2);

        final springBreaks =
            parsedHtml.where((e) => e.title == 'Tavaszi szünet').toList();
        expect(springBreaks.length, 1);
        expect(springBreaks.first.startDate, DateTime(2027, 4, 2));
        expect(springBreaks.first.endDate, DateTime(2027, 4, 3));

        // ICS feed with another holiday interleaved + consecutive days around March DST
        const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART;VALUE=DATE:20270102
DTEND;VALUE=DATE:20270103
SUMMARY:Téli szünet
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20270103
DTEND;VALUE=DATE:20270104
SUMMARY:Újév pótnap
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20270103
DTEND;VALUE=DATE:20270104
SUMMARY:Téli szünet
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20270104
DTEND;VALUE=DATE:20270105
SUMMARY:Téli szünet
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20270328
DTEND;VALUE=DATE:20270329
SUMMARY:Tavaszi szünet
END:VEVENT
BEGIN:VEVENT
DTSTART;VALUE=DATE:20270329
DTEND;VALUE=DATE:20270330
SUMMARY:Tavaszi szünet
END:VEVENT
END:VCALENDAR
''';
        final parsedIcs =
            SchoolYearScheduleService.parseScheduleFromIcs(ics, 2026);
        final icsWinter =
            parsedIcs.where((e) => e.title == 'Téli szünet').toList();
        expect(icsWinter.length, 1);
        expect(icsWinter.first.startDate, DateTime(2027, 1, 2));
        expect(icsWinter.first.endDate, DateTime(2027, 1, 4));
        expect(icsWinter.first.durationDays, 3);

        final icsSpring =
            parsedIcs.where((e) => e.title == 'Tavaszi szünet').toList();
        expect(icsSpring.length, 1);
        expect(icsSpring.first.startDate, DateTime(2027, 3, 28));
        expect(icsSpring.first.endDate, DateTime(2027, 3, 29));

        // Cached v3.1 JSON with separate duplicate day entries auto-heals on deserialize
        final legacyJson = {
          'schoolYearLabel': '2026/2027',
          'sourceLabel': 'Cache',
          'fetchedAt': '2026-11-20T10:00:00.000',
          'events': [
            {
              'id': 'w1',
              'title': 'Téli szünet',
              'startDate': '2027-01-03T00:00:00.000',
              'endDate': '2027-01-03T00:00:00.000',
              'type': 'schoolBreak',
            },
            {
              'id': 'w2',
              'title': 'Téli szünet',
              'startDate': '2027-01-04T00:00:00.000',
              'endDate': '2027-01-04T00:00:00.000',
              'type': 'schoolBreak',
            },
          ],
        };
        final healed = SchoolYearSchedule.fromJson(legacyJson);
        expect(healed.events.length, 1);
        expect(healed.events.first.startDate, DateTime(2027, 1, 3));
        expect(healed.events.first.endDate, DateTime(2027, 1, 4));
      },
    );

    testWidgets(
      'Tapping any Tanév rendje event card opens a Liquid Glass detail popup with title, date range, category, days remaining, and interactive pin toggle',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        const prefs = UserProfilePrefs(liquidGlassEnabled: true);
        final service = SchoolYearScheduleService(
          httpClient: MockClient((_) async => http.Response('err', 500)),
          nowProvider: () => DateTime(2026, 11, 20),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: SchoolYearScheduleScreen(
              student: null,
              instituteCode: 'klik-popup-test',
              prefs: prefs,
              scheduleService: service,
              clock: () => DateTime(2026, 11, 20),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final springCard = find.byKey(
          const ValueKey<String>('school-year-event-card-nat_2026_spring'),
        );
        final listScroll = find
            .descendant(
              of: find.byKey(const ValueKey<String>('school-year-subtab-swipe')),
              matching: find.byType(Scrollable),
            )
            .last;
        await tester.scrollUntilVisible(
          springCard,
          240,
          scrollable: listScroll,
        );
        expect(springCard, findsOneWidget);
        await tester.tap(springCard);
        await tester.pumpAndSettle();

        final detailSheet = find.byKey(
          const ValueKey<String>(
            'school-year-event-detail-sheet-nat_2026_spring',
          ),
        );
        expect(detailSheet, findsOneWidget);
        expect(
          find.descendant(of: detailSheet, matching: find.byType(BackdropFilter)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: detailSheet,
            matching: find.text('Tavaszi szünet'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: detailSheet, matching: find.text('Szünetek')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: detailSheet,
            matching: find.textContaining('2027. 03. 25.'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: detailSheet,
            matching: find.textContaining('nap múlva'),
          ),
          findsOneWidget,
        );

        final pinToggle = find.byKey(
          const ValueKey<String>('school-year-detail-pin-toggle'),
        );
        expect(pinToggle, findsOneWidget);
        await tester.tap(pinToggle);
        await tester.pumpAndSettle();

        expect(
          await service.loadPinnedCountdownEventId('klik-popup-test'),
          'nat_2026_spring',
        );
        expect(
          find.descendant(
            of: detailSheet,
            matching: find.text('Kitűzve a visszaszámlálóra'),
          ),
          findsOneWidget,
        );

        // Close popup, scroll back to top Hero card, and confirm it reflects the pinned event
        await tester.tapAt(const Offset(20, 80));
        await tester.pumpAndSettle();
        await tester.fling(listScroll, const Offset(0, 700), 1800);
        await tester.pumpAndSettle();
        expect(find.text('Kitűzött célpont • Váltás'), findsOneWidget);
      },
    );
  });

  group('Bug 5 & 6 (#MWUW2475, #MWUU8IBU): PageView swipe & top pill slider sync', () {
    testWidgets(
      'Short horizontal swipe on Főoldal snaps directly forward without bouncing back, and rapid pill taps/interrupts never glitch the top pill slider',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime(2026, 11, 23, 10, 0);
        final session = _testSession();
        final cached = DashboardData(
          student: null,
          todaysLessons: [
            _makeLesson(
              uid: 'hl-1',
              start: DateTime(2026, 11, 23, 11, 0),
              subjectName: 'Fizika',
            ),
          ],
          allGrades: [
            _makeGrade(uid: 'hg-1', subjectName: 'Matematika', value: 5),
          ],
          latestGrades: [
            _makeGrade(uid: 'hg-1', subjectName: 'Matematika', value: 5),
          ],
          homeworks: [
            _makeHomework(
              uid: 'hhw-1',
              dueDate: now.add(const Duration(days: 1)),
              subjectName: 'Biológia',
              description: 'Sejtbiológia',
            ),
          ],
          tests: [
            _makeTest(
              uid: 'ht-1',
              date: now.add(const Duration(days: 2)),
              subjectName: 'Kémia',
              theme: 'Savak és bázisok',
            ),
          ],
          activeSession: session,
        );

        const prefs = UserProfilePrefs(liquidGlassEnabled: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: HomeScreen(
              initialSession: session,
              initialCachedData: cached,
              kretaClient: _CountingHomeKretaClient(cached),
              prefs: prefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => now,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final swipeArea = find.byKey(const ValueKey<String>('home-subtab-swipe'));
        final pageViewFinder = find.descendant(
          of: swipeArea,
          matching: find.byType(PageView),
        );
        final tabBarFinder = find.byType(LiquidBubbleTabBar);
        final pillFinder = find.descendant(
          of: tabBarFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width != null && w.height != null,
          ),
        );

        final initialPillLeft = tester.widget<Positioned>(pillFinder).left!;

        // 1. Short ~120px (< 50% of 420px) horizontal drag left, release slowly:
        // PageView & top pill must progress monotonically forward to page 1 (never bounce back to 0 first!)
        final start = tester.getCenter(swipeArea);
        final drag = await tester.startGesture(start);
        for (int i = 1; i <= 6; i++) {
          await drag.moveBy(const Offset(-20, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final controller = tester.widget<PageView>(pageViewFinder).controller!;
        final pageAtRelease = controller.page!;
        expect(pageAtRelease, greaterThan(0.12));
        expect(pageAtRelease, lessThan(0.50));
        await drag.up();

        double prevPage = pageAtRelease;
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 24));
          final cur = controller.page!;
          expect(
            cur,
            greaterThanOrEqualTo(prevPage - 0.01),
            reason: 'PageView snapped back toward 0 after short swipe release ($cur < $prevPage)',
          );
          prevPage = cur;
        }
        await tester.pumpAndSettle();
        expect(
          tester.widget<HorizontalSubTabSwipeDetector>(swipeArea).currentIndex,
          1,
        );
        expect(tester.widget<LiquidBubbleTabBar>(tabBarFinder).selectedIndex, 1);

        // 2. Rapidly tap Számonkérések (3), then 40ms later tap Házik (2):
        // The earlier cancelled animateToPage must NOT clear ignorePageController early
        // or snap the pill backward.
        await tester.tap(find.text('Számonkérések'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.text('Házik'));
        await tester.pump();

        for (int i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          final pillLeftNow = tester.widget<Positioned>(pillFinder).left!;
          expect(
            pillLeftNow,
            greaterThan(initialPillLeft + 40),
            reason: 'Top pill glitched back toward index 0 during rapid tab tap',
          );
        }
        await tester.pumpAndSettle();
        expect(
          tester.widget<HorizontalSubTabSwipeDetector>(swipeArea).currentIndex,
          2,
        );
        expect(tester.widget<LiquidBubbleTabBar>(tabBarFinder).selectedIndex, 2);

        // 3. Interrupt a programmatic tap (2 -> 0) mid-flight with a manual drag:
        await tester.tap(find.text('Összes'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final interruptDrag = await tester.startGesture(start);
        for (int i = 0; i < 6; i++) {
          await interruptDrag.moveBy(const Offset(-28, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await interruptDrag.up();
        await tester.pumpAndSettle();
        expect(
          tester.widget<LiquidBubbleTabBar>(tabBarFinder).selectedIndex,
          tester.widget<HorizontalSubTabSwipeDetector>(swipeArea).currentIndex,
        );
      },
    );

    testWidgets(
      'GradesScreen Tantárgyak sorting stays synced across rapid sort tab taps and horizontal swipes',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        const prefs = UserProfilePrefs(liquidGlassEnabled: true);
        final grades = [
          _makeGrade(uid: 'ga', subjectName: 'Algebra', value: 5),
          _makeGrade(uid: 'gb', subjectName: 'Biológia', value: 2),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: Scaffold(
              body: GradesScreen(
                allGrades: grades,
                prefs: prefs,
                onPrefsChanged: (_) {},
                onRefresh: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final tabBarFinder = find.byType(LiquidBubbleTabBar);
        await tester.tap(find.text('Átlag ↓ (Legjobb)'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(find.text('Átlag ↑ (Javítandó)'));
        await tester.pumpAndSettle();

        expect(tester.widget<LiquidBubbleTabBar>(tabBarFinder).selectedIndex, 1);
        expect(
          tester.getTopLeft(find.text('Biológia')).dy,
          lessThan(tester.getTopLeft(find.text('Algebra')).dy),
        );

        await tester.drag(
          find.byKey(const ValueKey<String>('grades-subtab-swipe')),
          const Offset(180, 0),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<LiquidBubbleTabBar>(tabBarFinder).selectedIndex, 0);
        expect(
          tester.getTopLeft(find.text('Algebra')).dy,
          lessThan(tester.getTopLeft(find.text('Biológia')).dy),
        );
      },
    );
  });
}
