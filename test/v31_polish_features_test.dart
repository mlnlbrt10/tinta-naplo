import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/developer_options_screen.dart';
import 'package:tinta_naplo/screens/home_screen.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/services/github_updater_service.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/menetrend_service.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/utils/greeting_utils.dart';
import 'package:tinta_naplo/widgets/animation_helpers.dart';
import 'package:tinta_naplo/widgets/bug_report_sheet.dart';
import 'package:tinta_naplo/widgets/frosted_inspection_modal.dart';

StoredSession _testSession() => StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik-test-99',
      userName: 'tesztdiak',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

Student _makeStudent({
  String fullName = 'Kovács Bence',
  String instituteName = 'Budapesti Fazekas Mihály Gimnázium',
}) =>
    Student(
      uid: 'stu-1',
      name: fullName,
      addressDataList: const [],
      bankAccount: const BankAccount(
        accountNumber: null,
        isReadOnly: true,
        ownerName: null,
        ownerType: null,
      ),
      birthdate: DateTime(2007, 5, 12),
      emailAddress: null,
      phoneNumber: null,
      schoolYearUID: '2026',
      guardianList: const [],
      instituteCode: 'klik-test-99',
      instituteName: instituteName,
      institution: Institution(
        uid: 'inst-1',
        shortName: 'Fazekas',
        customizationSettings: const CustomizationSettings(
          delayForNotifications: 0,
          isClassAverageVisible: true,
          isLessonsThemeVisible: true,
          nextServerDeployAsString: '',
        ),
        systemModuleList: const [],
      ),
    );

Lesson _makeLesson({
  required String uid,
  required DateTime start,
  required DateTime end,
  required String subjectName,
  int lessonNumber = 1,
  bool cancelled = false,
}) {
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
    teacher: 'Nagy Éva',
    roomName: '101',
    type: NameUidDesc(uid: 't', name: 'Tanora', description: 'Tanóra'),
    state: cancelled
        ? NameUidDesc(uid: 'elmaradt', name: 'elmaradt', description: 'Elmaradt')
        : NameUidDesc(uid: 'm', name: 'Megtartott', description: 'Megtartott'),
    canStudentEditHomework: false,
    isHomeworkComplete: false,
    attachments: const [],
    isDigitalLesson: false,
    digitalSupportDeviceTypeList: const [],
    createdAt: start,
    lastModifiedAt: start,
  );
}

Test _makeTest({
  required String uid,
  required DateTime date,
  required String subjectName,
  String theme = 'Témazáró',
}) =>
    Test(
      uid: uid,
      date: date,
      reportDate: date.subtract(const Duration(days: 2)),
      teacherName: 'Kiss Anna',
      lessonNumber: 2,
      subject: Subject(
        uid: 'sub_$subjectName',
        name: subjectName,
        category: NameUidDesc(uid: 'c', name: subjectName, description: ''),
        sortIndex: 0,
      ),
      subjectName: subjectName,
      theme: theme,
      method: NameUidDesc(uid: 'm', name: 'Dolgozat', description: 'Dolgozat'),
      classGroup: UidObj(uid: 'grp-1'),
    );

Grade _makeGrade({
  required String uid,
  required String subjectName,
  required int value,
  String topic = 'Dolgozat',
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
}) =>
    Homework(
      uid: uid,
      subject: Subject(
        uid: 'sub_$subjectName',
        name: subjectName,
        category: NameUidDesc(uid: 'c', name: subjectName, description: ''),
        sortIndex: 0,
      ),
      subjectName: subjectName,
      teacherName: 'Tanár',
      description: description,
      startDate: dueDate.subtract(const Duration(days: 2)),
      dueDate: dueDate,
      creationDate: dueDate.subtract(const Duration(days: 2)),
      isCreatedByTeacher: true,
      isDone: false,
      canBeSubmitted: false,
      classGroup: UidObj(uid: 'grp-1'),
      canAttach: false,
    );

class _StubHomeDashboardClient extends KretaClient {
  final DashboardData data;

  _StubHomeDashboardClient(this.data)
      : super(
          httpClient: MockClient((_) async => http.Response('[]', 200)),
          storage: const TokenStorageService(),
        );

  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async =>
      data;

  @override
  Future<DashboardData> fetchDashboardData(
    StoredSession session, {
    DateTime? date,
  }) async =>
      data;
}

Widget _wrapWithProviders({
  required UserProfilePrefs prefs,
  required Widget child,
  SettingsProvider? settingsOut,
}) {
  final settings = settingsOut ?? SettingsProvider(initialPrefs: prefs);
  if (settingsOut == null) addTearDown(settings.dispose);
  final theme = ThemeProvider(settings);
  addTearDown(theme.dispose);
  final commute = CommuteProvider(
    settings,
    menetrendService: MenetrendService(),
  );
  addTearDown(commute.dispose);
  return AppProvidersScope(
    settings: settings,
    theme: theme,
    commute: commute,
    child: MaterialApp(
      theme: OledTheme.buildTheme(prefs: prefs),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    GreetingUtils.resetForTesting();
  });

  group('GreetingSubtitleMode & GreetingUtils subtitle modes', () {
    test('UserProfilePrefs defaults to finishTime and round-trips all modes', () {
      const defaults = UserProfilePrefs();
      expect(defaults.greetingSubtitleMode, GreetingSubtitleMode.finishTime);

      for (final mode in GreetingSubtitleMode.values) {
        final updated = defaults.withGreetingSubtitleMode(mode);
        expect(updated.greetingSubtitleMode, mode);
        final decoded = UserProfilePrefs.fromJson(
          jsonDecode(updated.toExportJsonString()) as Map<String, dynamic>,
        );
        expect(decoded.greetingSubtitleMode, mode);
      }
    });

    test('finish_time computes end time, ignores cancelled lessons, and handles edge cases', () {
      final now = DateTime(2026, 11, 23, 10, 30);
      final lessons = [
        _makeLesson(
          uid: 'l1',
          start: DateTime(2026, 11, 23, 8, 0),
          end: DateTime(2026, 11, 23, 8, 45),
          subjectName: 'Matematika',
          lessonNumber: 1,
        ),
        _makeLesson(
          uid: 'l2',
          start: DateTime(2026, 11, 23, 13, 30),
          end: DateTime(2026, 11, 23, 14, 15),
          subjectName: 'Fizika',
          lessonNumber: 6,
        ),
        _makeLesson(
          uid: 'l3',
          start: DateTime(2026, 11, 23, 14, 25),
          end: DateTime(2026, 11, 23, 15, 10),
          subjectName: 'Testnevelés',
          lessonNumber: 7,
          cancelled: true,
        ),
      ];

      expect(
        GreetingUtils.buildFinishTimeSubtitle(lessons, now),
        'Ma 14:15-kor végzel',
      );
      expect(
        GreetingUtils.buildFinishTimeSubtitle(
          lessons,
          DateTime(2026, 11, 23, 14, 15),
        ),
        'Mára végeztél',
      );
      expect(
        GreetingUtils.buildFinishTimeSubtitle(
          [lessons.last],
          now,
        ),
        'Ma nincs tanítás',
      );
      expect(
        GreetingUtils.buildFinishTimeSubtitle(const [], now),
        'Ma nincs tanítás',
      );
    });

    test('date and tomorrow_exams subtitles format Hungarian text accurately', () {
      final now = DateTime(2026, 11, 23, 9, 0); // Monday
      expect(
        GreetingUtils.buildGreetingSubtitle(
          mode: GreetingSubtitleMode.date,
          now: now,
          uwuMode: false,
        ),
        'November 23., hétfő',
      );

      final tests = [
        _makeTest(
          uid: 't-today',
          date: DateTime(2026, 11, 23, 11, 0),
          subjectName: 'Fizika',
        ),
        _makeTest(
          uid: 't-tomorrow-1',
          date: DateTime(2026, 11, 24, 9, 0),
          subjectName: 'Matematika',
        ),
        _makeTest(
          uid: 't-tomorrow-2',
          date: DateTime(2026, 11, 24, 12, 0),
          subjectName: 'Biológia',
        ),
        _makeTest(
          uid: 't-later',
          date: DateTime(2026, 11, 25, 10, 0),
          subjectName: 'Kémia',
        ),
      ];

      expect(
        GreetingUtils.buildTomorrowExamsSubtitle(tests, now),
        'Holnap 2 számonkérésed lesz',
      );
      expect(
        GreetingUtils.buildTomorrowExamsSubtitle([tests.first, tests.last], now),
        'Holnap nincs számonkérés',
      );
      expect(
        GreetingUtils.buildGreetingSubtitle(
          mode: GreetingSubtitleMode.schoolName,
          now: now,
          schoolName: 'Fazekas',
          uwuMode: false,
        ),
        'Fazekas',
      );
      expect(
        GreetingUtils.buildGreetingSubtitle(
          mode: GreetingSubtitleMode.none,
          now: now,
          schoolName: 'Fazekas',
          uwuMode: false,
        ),
        isNull,
      );
    });

    testWidgets('useless_fun_facts.json asset bundles 500+ unique concise Hungarian facts', (
      tester,
    ) async {
      final raw = (await tester.runAsync(
        () => rootBundle.loadString(GreetingUtils.funFactsAssetPath),
      ))!;
      final decoded = (jsonDecode(raw) as List<dynamic>).cast<String>();
      expect(decoded.length, greaterThanOrEqualTo(500));

      final normalized = <String>{};
      for (final fact in decoded) {
        final trimmed = fact.trim();
        expect(trimmed, isNotEmpty);
        expect(trimmed.length, lessThanOrEqualTo(120));
        expect(normalized.add(trimmed.toLowerCase()), isTrue, reason: 'Duplicate: $trimmed');
      }

      GreetingUtils.resetForTesting(random: Random(42));
      final loaded = (await tester.runAsync(
        () => GreetingUtils.ensureFunFactsLoaded(),
      ))!;
      expect(loaded.length, decoded.length);

      final first = GreetingUtils.pickFunFact();
      final second = GreetingUtils.pickFunFact(forceRefresh: true);
      expect(first, isNot(second));
    });
  });

  group('HomeScreen configurable subtitle & fun fact cycling', () {
    testWidgets(
      'HomeScreen shows finish time by default and cycles fun facts on tap',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime(2026, 11, 23, 10, 0);
        final session = _testSession();
        final cached = DashboardData(
          student: _makeStudent(),
          todaysLessons: [
            _makeLesson(
              uid: 'hl-1',
              start: DateTime(2026, 11, 23, 13, 30),
              end: DateTime(2026, 11, 23, 14, 15),
              subjectName: 'Fizika',
            ),
          ],
          allGrades: [_makeGrade(uid: 'g1', subjectName: 'Matematika', value: 5)],
          latestGrades: [_makeGrade(uid: 'g1', subjectName: 'Matematika', value: 5)],
          homeworks: const [],
          tests: const [],
          activeSession: session,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: HomeScreen(
              initialSession: session,
              initialCachedData: cached,
              kretaClient: _StubHomeDashboardClient(cached),
              prefs: const UserProfilePrefs(),
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => now,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Ma 14:15-kor végzel'), findsOneWidget);
        expect(find.text('Budapesti Fazekas Mihály Gimnázium'), findsNothing);

        GreetingUtils.resetForTesting(
          random: Random(7),
          funFacts: const [
            'A méz sosem romlik meg az ókori edényekben sem.',
            'A polipoknak három dobogó szívük van a testükben.',
          ],
        );

        final funPrefs = const UserProfilePrefs().withGreetingSubtitleMode(
          GreetingSubtitleMode.funFacts,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: funPrefs),
            home: HomeScreen(
              initialSession: session,
              initialCachedData: cached,
              kretaClient: _StubHomeDashboardClient(cached),
              prefs: funPrefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => now,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final tapTarget = find.byKey(
          const ValueKey<String>('home-fun-fact-tap-target'),
        );
        expect(tapTarget, findsOneWidget);
        final firstFactText = tester
            .widget<Text>(
              find.descendant(of: tapTarget, matching: find.byType(Text)),
            )
            .data!;
        expect(
          tester
              .widget<Text>(
                find.descendant(of: tapTarget, matching: find.byType(Text)),
              )
              .maxLines,
          2,
        );

        await tester.tap(tapTarget);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final nextFactText = tester
            .widget<Text>(
              find.descendant(of: tapTarget, matching: find.byType(Text)),
            )
            .data!;
        expect(nextFactText, isNot(firstFactText));
      },
    );
  });

  group('LiquidBubbleTabBar drag release zero-snap-back', () {
    testWidgets(
      'Dragging Liquid Glass pill across HomeScreen tabs transitions smoothly without flashing back to previous tab',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime(2026, 11, 23, 10, 0);
        final session = _testSession();
        final cached = DashboardData(
          student: _makeStudent(),
          todaysLessons: [
            _makeLesson(
              uid: 'hl-1',
              start: DateTime(2026, 11, 23, 11, 0),
              end: DateTime(2026, 11, 23, 11, 45),
              subjectName: 'Fizika',
            ),
          ],
          allGrades: [_makeGrade(uid: 'g1', subjectName: 'Matematika', value: 5)],
          latestGrades: [_makeGrade(uid: 'g1', subjectName: 'Matematika', value: 5)],
          homeworks: [
            _makeHomework(
              uid: 'hw-1',
              dueDate: now.add(const Duration(days: 1)),
              subjectName: 'Biológia',
              description: 'Sejtbiológia',
            ),
          ],
          tests: const [],
          activeSession: session,
        );

        const prefs = UserProfilePrefs(liquidGlassEnabled: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: HomeScreen(
              initialSession: session,
              initialCachedData: cached,
              kretaClient: _StubHomeDashboardClient(cached),
              prefs: prefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => now,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final tabBarFinder = find.byType(LiquidBubbleTabBar);
        final pillFinder = find.descendant(
          of: tabBarFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width != null && w.height != null,
          ),
        );
        expect(pillFinder, findsOneWidget);
        final initialLeft = tester.widget<Positioned>(pillFinder).left!;

        final startCenter = tester.getCenter(find.text('Összes'));
        final destCenter = tester.getCenter(find.text('Házik'));
        expect(destCenter.dx, greaterThan(startCenter.dx + 120));

        final gesture = await tester.startGesture(startCenter);
        await tester.pump(const Duration(milliseconds: 110));
        const steps = 8;
        final totalDx = destCenter.dx - startCenter.dx;
        for (int i = 1; i <= steps; i++) {
          await gesture.moveTo(
            Offset(startCenter.dx + (totalDx * i / steps), startCenter.dy),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }

        final releasedLeft = tester.widget<Positioned>(pillFinder).left!;
        expect(releasedLeft, greaterThan(initialLeft + 100));

        await gesture.up();

        // Check early frames right after release: pill must NEVER flash back
        // toward initialLeft before moving/settling to the newly selected tab.
        for (final stepMs in [1, 4, 8, 16, 16, 16, 16, 16]) {
          await tester.pump(Duration(milliseconds: stepMs));
          final leftNow = tester.widget<Positioned>(pillFinder).left!;
          expect(
            leftNow,
            greaterThan(initialLeft + 90),
            reason: 'Pill snapped back toward initial tab after release ($leftNow vs $initialLeft)',
          );
        }

        await tester.pump(const Duration(milliseconds: 600));
        final swipeFinder = find.byKey(
          const ValueKey<String>('home-subtab-swipe'),
        );
        expect(
          tester.widget<HorizontalSubTabSwipeDetector>(swipeFinder).currentIndex,
          2,
        );
        final settledLeft = tester.widget<Positioned>(pillFinder).left!;
        expect(settledLeft, greaterThan(initialLeft + 120));
      },
    );
  });

  group('Appearance popups, preview removal, & Developer Options cleanup', () {
    testWidgets(
      'Appearance hides live preview, keeps Minimalista mód, and switches greeting subtitle via floating popup',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const initialPrefs = UserProfilePrefs(liquidGlassEnabled: true);
        final settings = SettingsProvider(initialPrefs: initialPrefs);
        addTearDown(settings.dispose);

        await tester.pumpWidget(
          _wrapWithProviders(
            prefs: initialPrefs,
            settingsOut: settings,
            child: MoreScreen(
              session: _testSession(),
              student: null,
              prefs: initialPrefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
              settingsOnly: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.text('Megjelenés és témák'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Élő megjelenési előnézet'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('appearance-liquid-glass-mode-row')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('appearance-backdrop-effect-row')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('appearance-animated-backdrop-row')),
          findsOneWidget,
        );

        final subtitleRow = find.byKey(
          const ValueKey<String>('appearance-greeting-subtitle-row'),
        );
        expect(subtitleRow, findsOneWidget);
        await tester.ensureVisible(subtitleRow);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Minimalista mód'), findsOneWidget);
        await tester.tap(subtitleRow);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(FrostedBottomSheetSurface), findsOneWidget);
        expect(find.text('Haszontalan fun factek'), findsOneWidget);
        await tester.tap(find.text('Haszontalan fun factek'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          settings.prefs.greetingSubtitleMode,
          GreetingSubtitleMode.funFacts,
        );
      },
    );

    testWidgets(
      'DeveloperAppearanceSubPage no longer duplicates Minimalista mód',
      (tester) async {
        const prefs = UserProfilePrefs();
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: DeveloperAppearanceSubPage(
              initialPrefs: prefs,
              onPrefsChanged: (_) {},
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Minimalista mód'), findsNothing);
        expect(find.text('Elrendezés és Sűrűség'), findsNothing);
      },
    );
  });

  group('v3.1 release asset resolution & BugReport version formatting', () {
    test('GitHubReleaseInfo.fromJson resolves v3.1 APK cleanly', () {
      final info = GitHubReleaseInfo.fromJson({
        'tag_name': 'v3.1',
        'name': 'Tinta Napló v3.1',
        'body': 'Tinta Napló v3.1 kiadás',
        'html_url': 'https://github.com/milu/tinta-naplo/releases/tag/v3.1',
        'assets': [
          {
            'name': 'tinta-naplo-wear-v3.1.apk',
            'browser_download_url':
                'https://example.com/tinta-naplo-wear-v3.1.apk',
          },
          {
            'name': 'tinta-naplo-android-v3.1-arm64-v8a.apk',
            'browser_download_url':
                'https://example.com/tinta-naplo-android-v3.1-arm64-v8a.apk',
          },
        ],
      });

      expect(
        info.apkDownloadUrl,
        'https://example.com/tinta-naplo-android-v3.1-arm64-v8a.apk',
      );
    });

    testWidgets('BugReportSheet strips trailing .0 to show Verzió: 3.1', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showBugReportSheet(
                  context,
                  prefs: const UserProfilePrefs(),
                  appVersionLoader: () async => '3.1.0+7002',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Verzió: 3.1'), findsOneWidget);
    });
  });
}
