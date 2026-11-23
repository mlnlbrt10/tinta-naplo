import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/developer_options_screen.dart';
import 'package:tinta_naplo/screens/grades_screen.dart';
import 'package:tinta_naplo/services/demo_data_service.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/widgets/expandable_profile_card.dart';
import 'package:tinta_naplo/widgets/frosted_inspection_modal.dart';
import 'package:tinta_naplo/widgets/period_countdown_badge.dart';
import 'package:tinta_naplo/widgets/tinta_toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  tearDown(() {
    TintaToast.dismissCurrent(immediate: true);
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  group('1. Profile Menu: Hibajelentés Icon Bubble', () {
    testWidgets(
      'Profile sheet wraps Hibajelentés leading icon inside 40x40 BorderRadius 13 bubble with 1px border',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showStreamlinedProfileSheet(
                    context: context,
                    student: DemoDataService.instance.buildDemoStudent(),
                    session: DemoDataService.instance.buildDemoSession(),
                    prefs: const UserProfilePrefs(),
                    onPrefsChanged: (_) {},
                    onOpenFullSettings: () {},
                  ),
                  child: const Text('OpenProfile'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OpenProfile'));
        await tester.pumpAndSettle();

        final bugTileFinder = find.byKey(
          const ValueKey<String>('profile-bug-report-tile'),
        );
        expect(bugTileFinder, findsOneWidget);

        final iconFinder = find.descendant(
          of: bugTileFinder,
          matching: find.byIcon(Icons.bug_report_rounded),
        );
        expect(iconFinder, findsOneWidget);
        final iconWidget = tester.widget<Icon>(iconFinder);
        expect(iconWidget.size, 20);

        final bubbleFinder = find.ancestor(
          of: iconFinder,
          matching: find.byWidgetPredicate((w) {
            if (w is! Container) return false;
            final deco = w.decoration;
            if (deco is! BoxDecoration) return false;
            return deco.borderRadius == BorderRadius.circular(13);
          }),
        );
        expect(bubbleFinder, findsOneWidget);
        final bubbleSize = tester.getSize(bubbleFinder);
        expect(bubbleSize, const Size(40, 40));
      },
    );
  });

  group('2. Multi-Page Developer Options Hub', () {
    testWidgets(
      'Navigates to all 5 standalone sub-pages and reflects Aktív badges on return',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final settings = SettingsProvider(
          initialPrefs: const UserProfilePrefs(developerModeUnlocked: true),
        );
        addTearDown(settings.dispose);
        final theme = ThemeProvider(settings);
        addTearDown(theme.dispose);
        final commute = CommuteProvider(settings);
        addTearDown(commute.dispose);

        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: theme,
            commute: commute,
            child: ListenableBuilder(
              listenable: settings,
              builder: (_, __) => MaterialApp(
                home: DeveloperOptionsHubScreen(
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Fejlesztői beállítások'), findsOneWidget);
        expect(find.text('Megjelenés és UI'), findsOneWidget);
        expect(find.text('Demó mód és Tesztadatok'), findsOneWidget);
        expect(find.text('KRÉTA Auth és Hálózat'), findsOneWidget);
        expect(find.text('Wear OS és Külső Integrációk'), findsOneWidget);
        expect(find.text('Rendszer, Cache és Naplók'), findsOneWidget);
        expect(find.text('Aktív'), findsNothing);

        // Push Demó mód és Tesztadatok and toggle Demó mód ON
        await tester.tap(find.text('Demó mód és Tesztadatok'));
        await tester.pumpAndSettle();
        expect(find.byType(DeveloperDemoModeSubPage), findsOneWidget);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();
        TintaToast.dismissCurrent(immediate: true);
        expect(settings.prefs.demoModeEnabled, isTrue);

        // Navigate back to Hub and confirm "Aktív" status badge appears
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Aktív'), findsOneWidget);

        // Push the remaining 4 sub-pages to verify each standalone Scaffold works
        for (final entry in <(String, Type)>[
          ('Megjelenés és UI', DeveloperAppearanceSubPage),
          ('KRÉTA Auth és Hálózat', DeveloperAuthNetworkSubPage),
          ('Wear OS és Külső Integrációk', DeveloperIntegrationsSubPage),
          ('Rendszer, Cache és Naplók', DeveloperSystemCacheSubPage),
        ]) {
          await tester.tap(find.text(entry.$1));
          await tester.pumpAndSettle();
          expect(find.byType(entry.$2), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
      },
    );
  });

  group('3. Isolated Showcase Demo Mode', () {
    test('DemoDataService dataset accuracy: Kovács Bence, 28 grades (4.58 avg), live lessons, exams, homework & omissions', () {
      final service = DemoDataService.instance;
      final now = DateTime(2026, 11, 18, 22, 15);
      final dashboard = service.buildDashboardData(nowOverride: now);

      expect(dashboard.student?.name, 'Kovács Bence');
      expect(
        dashboard.student?.instituteName,
        'Budapesti Műszaki SZC Neumann János Informatikai Technikum',
      );
      expect(dashboard.student?.institution.shortName, contains('11.B'));

      expect(dashboard.allGrades.length, 28);
      final subjects = dashboard.allGrades.map((g) => g.subject.name).toSet();
      expect(subjects.length, 8);
      final weightedAvg = SubjectGradeSummary.computeWeightedAverage(
        dashboard.allGrades,
      );
      expect(weightedAvg, closeTo(4.58, 0.005));

      // Ongoing lesson at `now`, plus substituted & cancelled entries
      expect(
        dashboard.todaysLessons.any(
          (l) => !l.start.isAfter(now) && l.end.isAfter(now),
        ),
        isTrue,
      );
      expect(
        dashboard.todaysLessons.any(
          (l) => (l.substituteTeacher ?? '').trim().isNotEmpty,
        ),
        isTrue,
      );
      expect(
        dashboard.todaysLessons.any(isLessonCancelled),
        isTrue,
      );

      // Monday–Friday weekly schedule
      final mon = DateTime(2026, 11, 16);
      final fri = DateTime(2026, 11, 20);
      final week = service.buildTimetableForRange(mon, fri, nowOverride: now);
      expect(week.map((l) => l.start.weekday).toSet(), {1, 2, 3, 4, 5});

      expect(dashboard.tests.length, 1);
      expect(dashboard.homeworks.length, 4);
      expect(dashboard.omissions.length, 2);
      expect(
        dashboard.omissions.every((o) => o.state == OmissionState.excused),
        isTrue,
      );
    });

    test('Demo Mode short-circuits KretaClient without network requests and preserves real storage tokens', () async {
      const storage = TokenStorageService();
      final realSession = StoredSession(
        accessToken: 'real_acc_token',
        refreshToken: 'real_ref_token',
        idToken: 'real_id_token',
        instituteCode: 'klik999999',
        userName: 'Real Student',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
      );
      await storage.saveSession(realSession);

      int networkCalls = 0;
      final client = KretaClient(
        storage: storage,
        httpClient: MockClient((_) async {
          networkCalls++;
          return http.Response('unexpected network call', 500);
        }),
      );

      UserProfilePrefs.syncActiveGlobals(
        const UserProfilePrefs().withDemoMode(true),
      );
      final data = await client.fetchDashboardData(realSession);

      expect(networkCalls, 0);
      expect(data.student?.name, 'Kovács Bence');
      expect(data.allGrades.length, 28);

      // Verify real stored session is completely intact after turning Demo Mode off
      UserProfilePrefs.syncActiveGlobals(
        const UserProfilePrefs().withDemoMode(false),
      );
      final storedAfter = await storage.loadSession();
      expect(storedAfter, isNotNull);
      expect(storedAfter!.accessToken, 'real_acc_token');
      expect(storedAfter.refreshToken, 'real_ref_token');
      expect(storedAfter.instituteCode, 'klik999999');
    });
  });

  group('4. Minimalist Mode Standard Labels & Hero Boomerang Preservation', () {
    testWidgets(
      'Órarend, Jegyek & Számonkérések minimalist modals reuse standard labels and preserve Hero + óraszám badge',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final minimalistPrefs = const UserProfilePrefs().withMinimalistMode(true);
        final lessons = DemoDataService.instance.buildLessonsForDay(
          DateTime(2026, 11, 18),
          nowOverride: DateTime(2026, 11, 18, 10, 0),
        );
        final targetLesson = lessons[2]; // 3. óra
        final targetGrade = DemoDataService.instance.buildDemoGrades().first;
        final targetTest = DemoDataService.instance.buildDemoTests().first;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => showLessonInspectionModal(
                        context,
                        targetLesson,
                        heroTag: 'lesson_num_demo-hero-test',
                        prefs: minimalistPrefs,
                      ),
                      child: const Text('OpenLesson'),
                    ),
                    ElevatedButton(
                      onPressed: () => showGradeInspectionModal(
                        context,
                        targetGrade,
                        prefs: minimalistPrefs,
                      ),
                      child: const Text('OpenGrade'),
                    ),
                    ElevatedButton(
                      onPressed: () => showTestInspectionModal(
                        context,
                        targetTest,
                        prefs: minimalistPrefs,
                      ),
                      child: const Text('OpenTest'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // 1. Lesson modal in Minimalista mód
        await tester.tap(find.text('OpenLesson'));
        await tester.pumpAndSettle();

        expect(find.text('Mikor'), findsNothing);
        expect(find.text('Hol'), findsNothing);
        expect(find.text('Kivel'), findsNothing);
        expect(find.text('Időpont'), findsOneWidget);
        expect(find.text('Tanterem'), findsNothing);
        expect(find.text('Terem'), findsOneWidget);
        expect(find.text('Tanár'), findsOneWidget);
        expect(find.text('3.'), findsOneWidget);
        final heroFinder = find.byWidgetPredicate(
          (w) => w is Hero && w.tag == 'lesson_num_demo-hero-test',
        );
        expect(heroFinder, findsOneWidget);

        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        // 2. Grade modal in Minimalista mód
        await tester.tap(find.text('OpenGrade'));
        await tester.pumpAndSettle();

        expect(find.text('Értékelés / Jegy'), findsNothing);
        expect(find.text('Tantárgy'), findsNothing);
        expect(find.text('Átlagra hatás'), findsNothing);
        expect(find.text('Típus'), findsOneWidget);
        expect(find.text('Tanár'), findsOneWidget);
        expect(find.text('Dátum'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        // 3. Test modal in Minimalista mód
        await tester.tap(find.text('OpenTest'));
        await tester.pumpAndSettle();

        expect(find.text('Bejelentett számonkérés'), findsNothing);
        expect(find.text('Bejelentve'), findsNothing);
        expect(find.text('Időpont'), findsOneWidget);
        expect(find.text('Típus'), findsOneWidget);
        expect(find.text('Tanár'), findsOneWidget);
      },
    );
  });
}
