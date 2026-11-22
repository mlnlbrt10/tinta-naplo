import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/about_app_screen.dart';
import 'package:tinta_naplo/screens/grades_screen.dart';
import 'package:tinta_naplo/screens/home_screen.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/screens/timetable_screen.dart';
import 'package:tinta_naplo/services/bug_report_service.dart';
import 'package:tinta_naplo/services/github_updater_service.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/utils/greeting_utils.dart';
import 'package:tinta_naplo/widgets/bug_report_sheet.dart';
import 'package:tinta_naplo/widgets/christmas_snowfall_overlay.dart';
import 'package:tinta_naplo/widgets/expandable_profile_card.dart';
import 'package:tinta_naplo/widgets/frosted_inspection_modal.dart';
import 'package:tinta_naplo/widgets/glass_card.dart';
import 'package:tinta_naplo/widgets/tinta_splash_overlay.dart';

class _FakeKretaClient extends KretaClient {
  final DashboardData dashboard;
  final List<Lesson> weekLessons;

  _FakeKretaClient({
    required this.dashboard,
    required this.weekLessons,
  });

  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async =>
      dashboard;

  @override
  Future<DashboardData> fetchDashboardData(
    StoredSession session, {
    DateTime? date,
  }) async =>
      dashboard;

  @override
  Future<List<Lesson>> fetchTimetableForRange(
    StoredSession session, {
    required DateTime from,
    required DateTime to,
  }) async =>
      weekLessons;
}

StoredSession _fakeSession() => StoredSession(
      instituteCode: 'TEST',
      accessToken: 'tok',
      refreshToken: 'ref',
      idToken: 'id',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

class _DelayedErrorHttpOverrides extends HttpOverrides {
  final Completer<void> proceedCompleter = Completer<void>();

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeDelayedHttpClient(proceedCompleter);
}

class _FakeDelayedHttpClient implements HttpClient {
  final Completer<void> _proceed;

  _FakeDelayedHttpClient(this._proceed);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(_proceed);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  final Completer<void> _proceed;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();

  _FakeHttpClientRequest(this._proceed);

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async {
    await _proceed.future;
    throw const SocketException('Simulated network failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Student _makeStudent(String fullName) => Student(
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
      instituteCode: 'TEST',
      instituteName: 'Teszt Gimnázium',
      institution: Institution(
        uid: 'inst-1',
        shortName: 'TG',
        customizationSettings: const CustomizationSettings(
          delayForNotifications: 0,
          isClassAverageVisible: true,
          isLessonsThemeVisible: true,
          nextServerDeployAsString: '',
        ),
        systemModuleList: const [],
      ),
    );

Grade _makeGrade(DateTime when) {
  final iso = when.toUtc().toIso8601String();
  return Grade.fromJson({
    'Uid': 'g-1',
    'RogzitesDatuma': iso,
    'KeszitesDatuma': iso,
    'LattamozasDatuma': iso,
    'Tantargy': {
      'Uid': 'subj-fiz',
      'Nev': 'Fizika',
      'Kategoria': {'Uid': 'c', 'Nev': 'Fizika', 'Leiras': 'Fizika'},
      'SortIndex': 1,
    },
    'Tema': 'Felelet',
    'Tipus': {'Uid': 't', 'Nev': 'Evkozi', 'Leiras': 'Évközi'},
    'Mod': {'Uid': 'm', 'Nev': 'Dolgozat', 'Leiras': 'Dolgozat'},
    'ErtekFajta': {'Uid': 'v', 'Nev': 'Jegy', 'Leiras': 'Jegy'},
    'ErtekeloTanarNeve': 'Tanár Béla',
    'SzamErtek': 5,
    'SzovegesErtek': 'Jeles (5)',
    'SzovegesErtekelesRovidNev': '5',
    'SulySzazalekErteke': 100,
    'SortIndex': 1,
  });
}

Homework _makeHomework({
  required String uid,
  required String subjectName,
  required String description,
  required DateTime dueDate,
}) {
  return Homework(
    uid: uid,
    subject: Subject(
      uid: 'subj-$uid',
      name: subjectName,
      category: NameUidDesc(uid: 'cat', name: subjectName, description: subjectName),
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
    classGroup: UidObj(uid: 'cg-1'),
    canAttach: false,
  );
}

Lesson _makeLesson({
  required String uid,
  required String subjectName,
  required DateTime start,
  required DateTime end,
  required int periodNumber,
  String? room,
  String? teacher,
  String? homeworkUid,
}) {
  return Lesson(
    uid: uid,
    date: DateFormat('yyyy-MM-dd').format(start),
    start: start,
    end: end,
    name: subjectName,
    lessonNumber: periodNumber,
    teacher: teacher,
    subject: Subject(
      uid: 'subj-$uid',
      name: subjectName,
      category: NameUidDesc(uid: 'cat', name: subjectName, description: subjectName),
      sortIndex: 0,
    ),
    roomName: room,
    type: NameUidDesc(uid: '1', name: 'Tanóra', description: 'Tanóra'),
    state: NameUidDesc(uid: '1', name: 'Megtartott', description: 'Megtartott'),
    homeworkUid: homeworkUid,
    canStudentEditHomework: false,
    isHomeworkComplete: false,
    attachments: const [],
    isDigitalLesson: false,
    digitalSupportDeviceTypeList: const [],
    createdAt: start,
    lastModifiedAt: start,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  group('1. Card Background Blur in Liquid Glass Mode vs Material Mode', () {
    testWidgets(
      'SoftGlassCard renders zero-lag frosted gradient (without BackdropFilter) in Liquid Glass mode and solid surface in Material mode',
      (tester) async {
        // Liquid Glass ON + collapsed card -> zero-lag clipped translucent gradient card (zero BackdropFilter)
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SoftGlassCard(
                prefs: const UserProfilePrefs(liquidGlassEnabled: true),
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.all(14),
                child: const Text('Collapsed Glass'),
              ),
            ),
          ),
        );
        expect(find.byType(ClipRRect), findsOneWidget);
        expect(find.byType(BackdropFilter), findsNothing);
        final glassContainer = tester.widget<Container>(
          find.descendant(
            of: find.byType(ClipRRect),
            matching: find.byType(Container),
          ),
        );
        expect((glassContainer.decoration as BoxDecoration).gradient, isNotNull);

        // Liquid Glass ON + expanded card -> high-contrast solid without double blur
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SoftGlassCard(
                prefs: UserProfilePrefs(liquidGlassEnabled: true),
                isExpanded: true,
                padding: EdgeInsets.all(14),
                child: Text('Expanded Solid'),
              ),
            ),
          ),
        );
        expect(find.byType(BackdropFilter), findsNothing);

        // Liquid Glass OFF (Material mode) -> zero BackdropFilter
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SoftGlassCard(
                prefs: UserProfilePrefs(liquidGlassEnabled: false),
                padding: EdgeInsets.all(14),
                child: Text('Material Card'),
              ),
            ),
          ),
        );
        expect(find.byType(BackdropFilter), findsNothing);

        // LiquidGlassSurface expanded modal skips double-blur stacking even when ON
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LiquidGlassSurface(
                prefs: UserProfilePrefs(liquidGlassEnabled: true),
                highContrastExpanded: true,
                child: Text('Expanded Sheet'),
              ),
            ),
          ),
        );
        expect(find.byType(BackdropFilter), findsNothing);
      },
    );

    testWidgets(
      'BreakCountdownCard renders cleanly in both Liquid Glass and Material modes without heavy per-card BackdropFilter',
      (tester) async {
        final baseNow = DateTime(2026, 11, 16, 8, 50);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BreakCountdownCard(
                breakStart: DateTime(2026, 11, 16, 8, 45),
                breakEnd: DateTime(2026, 11, 16, 8, 55),
                now: baseNow,
                prefs: const UserProfilePrefs(liquidGlassEnabled: true),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Szünet'), findsOneWidget);
        expect(find.byType(BackdropFilter), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BreakCountdownCard(
                breakStart: DateTime(2026, 11, 16, 8, 45),
                breakEnd: DateTime(2026, 11, 16, 8, 55),
                now: baseNow,
                prefs: const UserProfilePrefs(liquidGlassEnabled: false),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('Szünet'), findsOneWidget);
        expect(find.byType(BackdropFilter), findsNothing);
      },
    );
  });

  group('2. Privacy-Masked Bug Report Service & Profile Sheet Flow', () {
    test('masks Hungarian student names without exposing full surname', () {
      expect(BugReportService.maskReporterName('Albert Milán'), 'A. Milán');
      expect(
        BugReportService.maskReporterName('Nagy Anna Eszter'),
        'N. Anna Eszter',
      );
      expect(BugReportService.maskReporterName('  '), 'Névtelen felhasználó');
      expect(BugReportService.maskReporterName(null), 'Névtelen felhasználó');
    });

    test('enforces client-side image (10 MB) and video (25 MB) caps', () {
      final okImage = BugReportService.validateAttachment(
        path: '/tmp/a.png',
        name: 'a.png',
        sizeBytes: 2 * 1024 * 1024,
        isVideo: false,
      );
      expect(okImage.isValid, isTrue);

      final bigImage = BugReportService.validateAttachment(
        path: '/tmp/big.png',
        name: 'big.png',
        sizeBytes: 11 * 1024 * 1024,
        isVideo: false,
      );
      expect(bigImage.isValid, isFalse);
      expect(bigImage.errorMessage, contains('Maximum 10 MB'));

      final bigVideo = BugReportService.validateAttachment(
        path: '/tmp/big.mp4',
        name: 'big.mp4',
        sizeBytes: 26 * 1024 * 1024,
        isVideo: true,
      );
      expect(bigVideo.isValid, isFalse);
      expect(bigVideo.errorMessage, contains('Maximum 25 MB'));
    });

    test('submitTicket posts multipart payload to ticket.mlnlbrt.hu/api/tickets',
        () async {
      late http.BaseRequest capturedRequest;
      late String capturedBody;

      final mockClient = MockClient.streaming((request, bodyStream) async {
        capturedRequest = request;
        final bytes = await bodyStream.toBytes();
        capturedBody = utf8.decode(bytes, allowMalformed: true);
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"ok":true}')),
          201,
        );
      });

      final tempFile = File(
        '${Directory.systemTemp.path}/tinta_bug_test_${DateTime.now().microsecondsSinceEpoch}.png',
      )..writeAsBytesSync(const [137, 80, 78, 71]);
      addTearDown(() {
        if (tempFile.existsSync()) tempFile.deleteSync();
      });

      final res = await BugReportService.submitTicket(
        reporter: 'A. Milán',
        category: 'UI / Megjelenés',
        description: 'Gomb igazítás hiba az órarendben',
        appVersion: '3.0.0+19',
        osVersion: 'Android (14)',
        themeMode: 'OLED Fekete • Liquid Glass',
        attachment: BugAttachment(
          path: tempFile.path,
          name: 'screen.png',
          sizeBytes: 4,
          isVideo: false,
        ),
        client: mockClient,
      );

      expect(res.success, isTrue, reason: res.errorMessage);
      expect(
        capturedRequest.url.toString(),
        'https://ticket.mlnlbrt.hu/api/tickets',
      );
      expect(capturedRequest.method, 'POST');
      expect(capturedBody, contains('name="reporter"'));
      expect(capturedBody, contains('A. Milán'));
      expect(capturedBody, contains('name="category"'));
      expect(capturedBody, contains('UI / Megjelenés'));
      expect(capturedBody, contains('Gomb igazítás hiba az órarendben'));
      expect(capturedBody, contains('name="attachment"; filename="screen.png"'));

      // Also verify progress-tracked multipart stream forwards chunks & reaches 1.0
      double maxProgress = 0.0;
      final resWithProgress = await BugReportService.submitTicket(
        reporter: 'A. Milán',
        category: 'Hiba / Bug',
        description: 'Progress test',
        appVersion: '3.0.0+19',
        osVersion: 'Android (14)',
        themeMode: 'OLED Fekete',
        attachment: BugAttachment(
          path: tempFile.path,
          name: 'screen.png',
          sizeBytes: 4,
          isVideo: false,
        ),
        onProgress: (p) {
          if (p > maxProgress) maxProgress = p;
        },
        client: mockClient,
      );
      expect(resWithProgress.success, isTrue, reason: resWithProgress.errorMessage);
      expect(maxProgress, closeTo(1.0, 0.01));
    });

    testWidgets(
      'Profile card displays top-right bug button and opens Hibajelentés küldése sheet',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showStreamlinedProfileSheet(
                      context: context,
                      student: _makeStudent('Albert Milán'),
                      session: _fakeSession(),
                      prefs: const UserProfilePrefs(),
                      onPrefsChanged: (_) {},
                      onOpenFullSettings: () {},
                    ),
                    child: const Text('OpenProfile'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OpenProfile'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byIcon(Icons.bug_report_rounded), findsOneWidget);
        expect(find.text('Hibajelentés'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.bug_report_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Hibajelentés küldése'), findsOneWidget);
        expect(find.text('Beküldő: A. Milán'), findsOneWidget);
      },
    );

    testWidgets(
      'BugReportSheet validates, previews attachment, and submits multipart payload',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final tempImg = File(
          '${Directory.systemTemp.path}/tinta_picker_${DateTime.now().microsecondsSinceEpoch}.png',
        )..writeAsBytesSync(const [1, 2, 3, 4]);
        addTearDown(() {
          if (tempImg.existsSync()) tempImg.deleteSync();
        });

        late http.BaseRequest sentReq;
        final requestDone = Completer<void>();
        final mockClient = MockClient.streaming((req, body) async {
          sentReq = req;
          await body.drain<void>();
          if (!requestDone.isCompleted) requestDone.complete();
          return http.StreamedResponse(const Stream.empty(), 200);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showBugReportSheet(
                      context,
                      student: _makeStudent('Nagy Anna Eszter'),
                      prefs: const UserProfilePrefs(),
                      httpClient: mockClient,
                      pickImageOverride: () async => XFile(tempImg.path),
                      appVersionLoader: () async => '3.0.0+19',
                    ),
                    child: const Text('OpenBug'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OpenBug'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Hibajelentés küldése'), findsOneWidget);
        expect(find.textContaining('ticket.mlnlbrt.hu'), findsNothing);
        expect(find.text('Beküldő: N. Anna Eszter'), findsOneWidget);
        expect(find.text('Verzió: 3.0.0+19'), findsOneWidget);

        await tester.tap(find.text('Képernyőkép csatolása'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
        expect(find.byTooltip('Csatolmány eltávolítása'), findsOneWidget);

        await tester.enterText(
          find.byType(TextField),
          'Teszt hibaleírás v3.0.0',
        );
        await tester.tap(find.text('UI / Megjelenés'));
        await tester.pump();

        await tester.tap(find.text('Küldés'));
        for (int i = 0; i < 6 && !requestDone.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(requestDone.isCompleted, isTrue);
        await tester.pump(const Duration(milliseconds: 350));

        expect(sentReq.url.toString(), 'https://ticket.mlnlbrt.hu/api/tickets');
        expect(
          find.text('Köszönjük! A hibajelentés sikeresen elküldve.'),
          findsOneWidget,
        );
      },
    );
  });

  group('3 & 4. Timetable Compact Header, Decluttered Cards & Checkable Homework with Undo', () {
    testWidgets(
      'HomeScreen hides completed homework on Főoldal with Undo SnackBar while keeping it checked & visible in Házik',
      (tester) async {
        final fixedNow = DateTime(2026, 11, 16, 10, 0);
        final dueFuture = DateTime(2026, 11, 17, 14, 0);
        final hw = _makeHomework(
          uid: 'hw-math-1',
          subjectName: 'Matematika',
          description: 'Oldd meg az 1-5. feladatot.',
          dueDate: dueFuture,
        );
        final grade = _makeGrade(fixedNow);
        final session = _fakeSession();
        final dashboard = DashboardData(
          student: _makeStudent('Albert Milán'),
          todaysLessons: const [],
          allGrades: [grade],
          latestGrades: [grade],
          homeworks: [hw],
          tests: const [],
          omissions: const [],
          messages: const [],
          activeSession: session,
        );
        final settings = SettingsProvider();
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
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: settings.prefs),
              home: HomeScreen(
                initialSession: session,
                initialCachedData: dashboard,
                kretaClient: _FakeKretaClient(
                  dashboard: dashboard,
                  weekLessons: const [],
                ),
                prefs: settings.prefs,
                onPrefsChanged: (_) {},
                onLogout: () {},
                clock: () => fixedNow,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Homework appears on Főoldal initially
        expect(find.text('Matematika'), findsOneWidget);

        // Tap complete checkbox
        await tester.tap(find.byTooltip('Megjelölés készként'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(settings.isHomeworkCompleted(hw), isTrue);
        expect(find.text('Visszavonás'), findsOneWidget);

        // Check SharedPreferences persisted immediately
        final sp = await SharedPreferences.getInstance();
        expect(
          sp.getStringList(SettingsProvider.completedHomeworkPrefsKey),
          contains('hw-math-1'),
        );

        // Completed homework is automatically hidden (0px, non-hit-testable) in 'Összes' Főoldal feed
        expect(find.text('Matematika').hitTestable(), findsNothing);

        // Switch to dedicated 'Házik' tab -> completed homework IS visible with Undo toggle
        await tester.tap(find.text('Házik'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Matematika').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Visszavonás (aktívvá tétel)'), findsOneWidget);

        // Switch back to Összes and tap SnackBar Visszavonás -> reappears on Főoldal
        await tester.tap(find.text('Összes'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(find.text('Visszavonás'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(settings.isHomeworkCompleted(hw), isFalse);
        expect(find.text('Matematika').hitTestable(), findsOneWidget);
      },
    );

    testWidgets(
      'TimetableScreen renders single-row compact bubble week switcher with Ma jump pill and interactive lesson Házi checkbox',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mondayMorning = DateTime(2026, 11, 16, 8, 30);
        final lesson = _makeLesson(
          uid: 'l-1',
          subjectName: 'Történelem',
          start: DateTime(2026, 11, 16, 8, 0),
          end: DateTime(2026, 11, 16, 8, 45),
          periodNumber: 1,
          room: '204',
          teacher: 'Kovács Ádám',
          homeworkUid: 'hw-hist-1',
        );
        final hw = _makeHomework(
          uid: 'hw-hist-1',
          subjectName: 'Történelem',
          description: 'Olvasd el a 34. oldalt!',
          dueDate: DateTime(2026, 11, 18, 8, 0),
        );

        final settings = SettingsProvider();
        addTearDown(settings.dispose);
        final theme = ThemeProvider(settings);
        addTearDown(theme.dispose);
        final commute = CommuteProvider(settings);
        addTearDown(commute.dispose);

        final timetableSession = _fakeSession();
        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: theme,
            commute: commute,
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: settings.prefs),
              home: Scaffold(
                body: TimetableScreen(
                  session: timetableSession,
                  kretaClient: _FakeKretaClient(
                    dashboard: DashboardData(
                      student: _makeStudent('Albert Milán'),
                      todaysLessons: [lesson],
                      allGrades: const [],
                      latestGrades: const [],
                      homeworks: [hw],
                      tests: const [],
                      omissions: const [],
                      messages: const [],
                      activeSession: timetableSession,
                    ),
                    weekLessons: [lesson],
                  ),
                  initialTodaysLessons: [lesson],
                  homeworks: [hw],
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                  clock: () => mondayMorning,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));

        // Zero overflow at 360px narrow width + single-row controls
        expect(find.byTooltip('Előző hét'), findsOneWidget);
        expect(find.byTooltip('Következő hét'), findsOneWidget);
        expect(find.text('Ma'), findsOneWidget);
        expect(find.byTooltip('Napi nézet'), findsOneWidget);
        expect(find.byTooltip('Heti nézet'), findsOneWidget);

        // Concise card omits duplicate 3rd-line summary and has interactive Házi pill
        expect(find.text('Olvasd el a 34. oldalt!'), findsNothing);
        expect(find.text('Házi'), findsOneWidget);

        await tester.tap(find.text('Házi'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(settings.isHomeworkCompleted(hw), isTrue);
        // Re-tapping toggles completion back off cleanly.
        await tester.tap(find.text('Házi'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(settings.isHomeworkCompleted(hw), isFalse);
      },
    );
  });

  group('5. OTA Update Popup hides action buttons during download', () {
    testWidgets(
      'Hides Később and Frissítés most while download is in progress and restores retry on error',
      (tester) {
        final httpOverride = _DelayedErrorHttpOverrides();
        return HttpOverrides.runZoned(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => GitHubUpdaterService.showFrostedUpdateDialog(
                        context,
                        release: const GitHubReleaseInfo(
                          tagName: 'v3.0.1',
                          title: 'v3.0.1',
                          releaseNotes: 'Teszt frissítés',
                          htmlUrl: 'https://github.com/mlnlbrt10/tinta-naplo',
                          apkDownloadUrl: 'https://example.com/app.apk',
                        ),
                        currentVersion: '3.0.0+19',
                      ),
                      child: const Text('ShowUpdate'),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.tap(find.text('ShowUpdate'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));

          expect(find.text('Később'), findsOneWidget);
          expect(find.text('Frissítés most'), findsOneWidget);

          // Tap 'Frissítés most' -> both action buttons vanish immediately while downloading
          await tester.tap(find.text('Frissítés most'));
          await tester.pump();
          expect(find.text('Később'), findsNothing);
          expect(find.text('Frissítés most'), findsNothing);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);

          // Simulate download failure -> error dialog + 'Újrapróbálás' restored
          httpOverride.proceedCompleter.complete();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Frissítés sikertelen'), findsOneWidget);
          await tester.tap(find.text('Bezár'));
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('Később'), findsOneWidget);
          expect(find.text('Újrapróbálás'), findsOneWidget);
        }, createHttpClient: httpOverride.createHttpClient);
      },
    );
  });

  group('6. 2026 UI/UX Overhaul Regression Suite', () {
    testWidgets(
      'HomeScreen swaps grade/test card hierarchy, limits homework preview to 1 line, applies top ShaderMask, and marks all homeworks completed',
      (tester) async {
        final fixedNow = DateTime(2026, 11, 16, 10, 0);
        final dueFuture = DateTime(2026, 11, 17, 14, 0);
        final hw1 = _makeHomework(
          uid: 'hw-1',
          subjectName: 'Angol nyelv',
          description:
              'Nagyon hosszú házi feladat leírás sok részlettel ami nem fér ki egyetlen sorba.',
          dueDate: dueFuture,
        );
        final hw2 = _makeHomework(
          uid: 'hw-2',
          subjectName: 'Biológia',
          description: 'Tankönyv 12. oldal',
          dueDate: dueFuture,
        );
        final grade = _makeGrade(fixedNow); // topic: 'Felelet', subject: 'Fizika'
        final announcedTest = Test(
          uid: 'test-overhaul-1',
          date: dueFuture,
          reportDate: fixedNow,
          teacherName: 'Kovács Béla',
          lessonNumber: 3,
          subject: Subject(
            uid: 'subj-chem',
            name: 'Kémia',
            category: NameUidDesc(
              uid: 'c',
              name: 'Kémia',
              description: 'Kémia',
            ),
            sortIndex: 2,
          ),
          subjectName: 'Kémia',
          theme: 'Optika',
          method: NameUidDesc(
            uid: 'm-tz',
            name: 'Témazáró',
            description: 'Írásbeli témazáró dolgozat',
          ),
          classGroup: UidObj(uid: 'cg-1'),
        );

        final session = _fakeSession();
        final dashboard = DashboardData(
          student: _makeStudent('Albert Milán'),
          todaysLessons: const [],
          allGrades: [grade],
          latestGrades: [grade],
          homeworks: [hw1, hw2],
          tests: [announcedTest],
          omissions: const [],
          messages: const [],
          activeSession: session,
        );

        final settings = SettingsProvider();
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
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: settings.prefs),
              home: HomeScreen(
                initialSession: session,
                initialCachedData: dashboard,
                kretaClient: _FakeKretaClient(
                  dashboard: dashboard,
                  weekLessons: const [],
                ),
                prefs: settings.prefs,
                onPrefsChanged: (_) {},
                onLogout: () {},
                clock: () => fixedNow,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));

        // Top & bottom scroll edge fade overlay present on HomeScreen
        expect(find.byType(VerticalScrollEdgeFades), findsOneWidget);

        // Card Hierarchy Swap: Grade shows topic ('Felelet') above subject ('Fizika')
        final gradeTopicRect = tester.getRect(find.text('Felelet').first);
        final gradeSubjectRect = tester.getRect(find.text('Fizika').first);
        expect(gradeTopicRect.top, lessThan(gradeSubjectRect.top));

        // Exam card shows auto-capitalized topic ('Optika') above concise 'Kémia • 3. óra'
        final examTopicRect = tester.getRect(find.text('Optika').first);
        final examSubRect = tester.getRect(find.text('Kémia • 3. óra').first);
        expect(examTopicRect.top, lessThan(examSubRect.top));

        // Homework description preview capped to maxLines: 1
        final hwPreviewWidget = tester.widget<Text>(
          find.text(
            'Nagyon hosszú házi feladat leírás sok részlettel ami nem fér ki egyetlen sorba.',
          ),
        );
        expect(hwPreviewWidget.maxLines, equals(1));

        // Switch to 'Házik' tab -> "Összes házi megjelölése készként" completes both homeworks in one tap
        await tester.tap(find.text('Házik'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        final markAllBtn = find.text('Összes házi megjelölése készként');
        expect(markAllBtn, findsOneWidget);
        await tester.tap(markAllBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(settings.isHomeworkCompleted(hw1), isTrue);
        expect(settings.isHomeworkCompleted(hw2), isTrue);
      },
    );

    testWidgets(
      'AppSettingsScreen fuzzy search matches Hungarian terms & synonyms and rounding slider snaps to 0.05 increments',
      (tester) async {
        final settings = SettingsProvider();
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
              builder: (context, _) => MaterialApp(
                theme: OledTheme.buildTheme(prefs: settings.prefs),
                home: AppSettingsScreen(
                  session: _fakeSession(),
                  student: _makeStudent('Albert Milán'),
                  kretaClient: KretaClient(),
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                  onLogout: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final searchField = find.byKey(
          const ValueKey<String>('settings-fuzzy-search-field'),
        );
        expect(searchField, findsOneWidget);
        final searchFieldWidget = tester.widget<TextField>(searchField);
        expect(searchFieldWidget.decoration?.filled, isFalse);
        expect(searchFieldWidget.decoration?.border, InputBorder.none);
        expect(searchFieldWidget.decoration?.enabledBorder, InputBorder.none);
        expect(searchFieldWidget.decoration?.focusedBorder, InputBorder.none);

        Future<void> searchAndExpect(String query, String expectedTitle) async {
          await tester.enterText(searchField, query);
          await tester.pump();
          expect(find.textContaining(expectedTitle), findsWidgets,
              reason: 'Query "$query" should match "$expectedTitle"');
        }

        await searchAndExpect('üveg', 'Liquid Glass effekt');
        await searchAndExpect('ikon', 'Indítóikon stílusa');
        await searchAndExpect('óra', 'Órarend megjelenítése');
        await searchAndExpect('fityma', 'Fityma Napló mód');
        await searchAndExpect('átlag', 'Átlagszámítás és kerekítési határok');

        // Navigate straight from fuzzy search into Órarend / Átlagszámítás and drag slider
        await tester.tap(find.text('Átlagszámítás és kerekítési határok'));
        await tester.pumpAndSettle();

        final sliders = find.byType(Slider);
        expect(sliders, findsWidgets);
        final firstSlider = tester.widget<Slider>(sliders.first);
        // min=4.00, max=4.95 -> 19 exact 0.05 divisions
        expect(firstSlider.divisions, equals(19));

        await tester.drag(sliders.first, const Offset(-80, 0));
        await tester.pumpAndSettle();

        final updatedT5 = settings.prefs.roundingConfig.threshold5;
        expect((updatedT5 * 20).round() / 20.0, closeTo(updatedT5, 0.0001));
      },
    );

    testWidgets(
      'TimetableScreen Ma button in Material 3 mode renders high-contrast onPrimary text on solid primary fill when not viewing today',
      (tester) async {
        final fixedNow = DateTime(2026, 11, 16, 8, 30);
        final settings = SettingsProvider();
        await settings.updatePrefs(
          const UserProfilePrefs(liquidGlassEnabled: false),
        );
        addTearDown(settings.dispose);
        final theme = ThemeProvider(settings);
        addTearDown(theme.dispose);
        final commute = CommuteProvider(settings);
        addTearDown(commute.dispose);

        final session = _fakeSession();
        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: theme,
            commute: commute,
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: settings.prefs),
              home: Scaffold(
                body: TimetableScreen(
                  session: session,
                  kretaClient: _FakeKretaClient(
                    dashboard: DashboardData(
                      student: _makeStudent('Albert Milán'),
                      todaysLessons: const [],
                      allGrades: const [],
                      latestGrades: const [],
                      homeworks: const [],
                      tests: const [],
                      omissions: const [],
                      messages: const [],
                      activeSession: session,
                    ),
                    weekLessons: const [],
                  ),
                  initialTodaysLessons: const [],
                  homeworks: const [],
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                  clock: () => fixedNow,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));

        // Move to next week so isViewingToday == false
        await tester.tap(find.byTooltip('Következő hét'));
        await tester.pump(const Duration(milliseconds: 200));

        final maFinder = find.text('Ma');
        expect(maFinder, findsOneWidget);
        final maText = tester.widget<Text>(maFinder);
        final maCard = tester.widget<SoftGlassCard>(
          find.ancestor(of: maFinder, matching: find.byType(SoftGlassCard)).first,
        );
        final scheme =
            OledTheme.buildTheme(prefs: settings.prefs).colorScheme;
        expect(maCard.color, equals(scheme.primary));
        expect(maText.style?.color, equals(scheme.onPrimary));
      },
    );

    testWidgets(
      'App icon switcher switches to classic icon reactively across Settings, AboutAppScreen, TintaSplashOverlay, and invokes DynamicIconService channel with Firka (QwIT) attribution',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        final iconChannelCalls = <MethodCall>[];
        const channel = MethodChannel('hu.mlnlbrt.tintanaplo/dynamic_icon');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          iconChannelCalls.add(call);
          return (call.arguments as Map?)?['alias']?.toString() ??
              '.MainActivityClassic';
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final settings = SettingsProvider();
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
              builder: (context, _) => MaterialApp(
                theme: OledTheme.buildTheme(prefs: settings.prefs),
                home: AppSettingsScreen(
                  session: _fakeSession(),
                  student: _makeStudent('Albert Milán'),
                  kretaClient: KretaClient(),
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                  onLogout: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Megjelenés és témák'));
        await tester.pumpAndSettle();

        final classicOption = find.byKey(
          const ValueKey<String>('app-icon-option-classic'),
        );
        await tester.scrollUntilVisible(
          classicOption,
          240,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .last,
        );
        await tester.pumpAndSettle();

        expect(find.text('Alkalmazás ikon'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('app-icon-option-default')),
            matching: find.text('Alapértelmezett'),
          ),
          findsOneWidget,
        );
        expect(find.text('Klasszikus'), findsOneWidget);
        expect(
          find.text('Az ikonokat a Firka (QwIT) inspirálta.'),
          findsOneWidget,
        );

        await tester.tap(classicOption);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(settings.prefs.isClassicAppIcon, isTrue);
        expect(
          settings.activeAppIconAsset,
          'assets/images/tinta_icon_classic.png',
        );
        expect(iconChannelCalls, isNotEmpty);
        expect(iconChannelCalls.last.method, 'setAppIcon');
        expect(
          (iconChannelCalls.last.arguments as Map)['alias'],
          '.MainActivityClassic',
        );

        // Verify AboutAppScreen dynamically renders classic icon and Firka (QwIT) attribution
        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: theme,
            commute: commute,
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: settings.prefs),
              home: AboutAppScreen(
                prefs: settings.prefs,
                onPrefsChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Image &&
                w.image is AssetImage &&
                (w.image as AssetImage).assetName ==
                    'assets/images/tinta_icon_classic.png',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Ikonok inspirációja: Firka (QwIT)'),
          findsOneWidget,
        );
        expect(find.text('https://firka.app/'), findsOneWidget);

        // Verify AboutAppScreen exposes Privacy Policy & Legal modal and Open-Source Licenses page
        await tester.scrollUntilVisible(
          find.text('Nyílt forráskódú licencek'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Adatvédelmi tájékoztató'), findsOneWidget);
        expect(find.text('Nyílt forráskódú licencek'), findsOneWidget);

        await tester.tap(find.text('Adatvédelmi tájékoztató'));
        await tester.pumpAndSettle();
        expect(find.text('Adatvédelem és jogi nyilatkozat'), findsNWidgets(2));
        expect(find.text('Nem hivatalos kliens'), findsOneWidget);
        expect(find.text('Adatkezelés & Biztonság'), findsOneWidget);
        expect(find.text('Hibajelentések'), findsOneWidget);
        await tester.tap(find.text('Rendben'));
        await tester.pumpAndSettle();
        expect(find.text('Adatvédelem és jogi nyilatkozat'), findsOneWidget);

        await tester.tap(find.text('Nyílt forráskódú licencek'));
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsOneWidget);
        Navigator.of(tester.element(find.byType(LicensePage))).pop();
        await tester.pumpAndSettle();

        // Verify TintaSplashOverlay dynamically renders classic icon
        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: theme,
            commute: commute,
            child: const MaterialApp(
              home: TintaSplashOverlay(isLoading: true),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Image &&
                w.image is AssetImage &&
                (w.image as AssetImage).assetName ==
                    'assets/images/tinta_icon_classic.png',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('Inter Typography, Chronological Grade Impact Delta & Redesigned Cards', () {
    test(
      'OledTheme uses Inter fontFamily across theme modes and capitalizeFirst handles Hungarian text',
      () {
        for (final prefs in const [
          UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
          UserProfilePrefs(themeStyle: AppThemeStyle.standardDark),
          UserProfilePrefs(themeStyle: AppThemeStyle.light),
          UserProfilePrefs(
            themeStyle: AppThemeStyle.oledPureBlack,
            liquidGlassEnabled: true,
          ),
        ]) {
          final theme = OledTheme.buildTheme(prefs: prefs);
          expect(theme.textTheme.titleMedium?.fontFamily, 'Inter');
          expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
          expect(theme.textTheme.titleLarge?.letterSpacing, lessThan(0));
          expect(
            theme.textTheme.bodyMedium?.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
          expect(theme.appBarTheme.titleTextStyle?.fontFamily, 'Inter');
        }

        expect(OledTheme.capitalizeFirst('középtávfutás'), 'Középtávfutás');
        expect(
          OledTheme.capitalizeFirst('  írásbeli témazáró  '),
          'Írásbeli témazáró',
        );
        expect(OledTheme.capitalizeFirst('1. rész - elmélet'), '1. rész - elmélet');
        expect(OledTheme.capitalizeFirst('   '), '');
      },
    );

    test(
      'SubjectGradeSummary.computeChronologicalGradeImpacts computes first-grade, weighted delta, and non-numeric safety',
      () {
        final mathSubj = Subject(
          uid: 'subj-math',
          name: 'Matematika',
          category: NameUidDesc(
            uid: 'cat-m',
            name: 'Matematika',
            description: 'Matematika',
          ),
          sortIndex: 1,
        );
        Grade makeNumGrade({
          required String uid,
          required int? val,
          required int weight,
          required DateTime date,
        }) =>
            Grade(
              uid: uid,
              recordDate: date,
              creationDate: date,
              subject: mathSubj,
              topic: 'teszt témakör',
              type: NameUidDesc(uid: 't', name: 'EvKoziJegy', description: 'Évközi'),
              mode: NameUidDesc(uid: 'm', name: 'Irasbeli', description: 'Írásbeli'),
              valueType: NameUidDesc(
                uid: 'vt',
                name: 'Osztalyzat',
                description: 'Osztályzat',
              ),
              teacher: 'Tanár',
              numericValue: val,
              strValue: val != null ? 'Jegy($val)' : 'Dicséret',
              shortStrValue: val == null ? 'D' : null,
              weightPercentage: weight,
              classGroup: UidObj(uid: 'cg'),
              sortIndex: 0,
            );

        // First: 4 (100%) -> avg 4.00
        // Second: 5 (100%) -> avg (4+5)/2 = 4.50 => delta +0.50
        // Non-numeric text grade in between -> delta null, doesn't alter average
        // Third: 3 (200%) -> avg (4*100 + 5*100 + 3*200)/400 = 1500/400 = 3.75 => delta -0.75
        final g1 = makeNumGrade(
          uid: 'g1',
          val: 4,
          weight: 100,
          date: DateTime(2026, 10, 1),
        );
        final g2 = makeNumGrade(
          uid: 'g2',
          val: 5,
          weight: 100,
          date: DateTime(2026, 10, 10),
        );
        final gText = makeNumGrade(
          uid: 'g-text',
          val: null,
          weight: 100,
          date: DateTime(2026, 10, 12),
        );
        final g3 = makeNumGrade(
          uid: 'g3',
          val: 3,
          weight: 200,
          date: DateTime(2026, 10, 20),
        );

        // Pass in shuffled order to verify chronological sorting works
        final impacts = SubjectGradeSummary.computeChronologicalGradeImpacts([
          g3,
          gText,
          g2,
          g1,
        ]);

        expect(impacts['g1']!.isFirstNumericGrade, isTrue);
        expect(impacts['g1']!.delta, 0.0);
        expect(impacts['g1']!.formattedDelta, '0.00');
        expect(impacts['g1']!.displayLabel, '-');

        expect(impacts['g2']!.isFirstNumericGrade, isFalse);
        expect(impacts['g2']!.averageBefore, closeTo(4.0, 1e-6));
        expect(impacts['g2']!.averageAfter, closeTo(4.5, 1e-6));
        expect(impacts['g2']!.delta, closeTo(0.5, 1e-6));
        expect(impacts['g2']!.formattedDelta, '+0.50');

        expect(impacts['g-text']!.isNumeric, isFalse);
        expect(impacts['g-text']!.delta, isNull);

        expect(impacts['g3']!.averageBefore, closeTo(4.5, 1e-6));
        expect(impacts['g3']!.averageAfter, closeTo(3.75, 1e-6));
        expect(impacts['g3']!.delta, closeTo(-0.75, 1e-6));
        expect(impacts['g3']!.formattedDelta, '-0.75');
        expect(impacts['g3']!.weightPercentage, 200);
      },
    );

    testWidgets(
      'HomeScreen grade card renders translucent badge, auto-capitalized topic, impact delta + weight, and omits redundant date',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final fixedNow = DateTime(2026, 11, 20, 10, 0);
        final peSubj = Subject(
          uid: 'subj-pe',
          name: 'Testnevelés',
          category: NameUidDesc(
            uid: 'c-pe',
            name: 'Testnevelés',
            description: 'Testnevelés',
          ),
          sortIndex: 1,
        );
        final olderGrade = Grade(
          uid: 'pe-1',
          recordDate: DateTime(2026, 11, 10, 9, 0),
          creationDate: DateTime(2026, 11, 10, 9, 0),
          subject: peSubj,
          topic: 'páros lefutás',
          type: NameUidDesc(uid: 't', name: 'EvKoziJegy', description: 'Évközi'),
          mode: NameUidDesc(uid: 'm', name: 'Gyakorlati', description: 'gyakorlati'),
          valueType: NameUidDesc(uid: 'v', name: 'Osztalyzat', description: '5'),
          teacher: 'Edző',
          numericValue: 4,
          strValue: 'Jó(4)',
          weightPercentage: 100,
          classGroup: UidObj(uid: 'cg'),
          sortIndex: 0,
        );
        final newerWeightedGrade = Grade(
          uid: 'pe-2',
          recordDate: DateTime(2026, 11, 19, 11, 0),
          creationDate: DateTime(2026, 11, 19, 11, 0),
          subject: peSubj,
          topic: 'középtávfutás',
          type: NameUidDesc(uid: 't', name: 'EvKoziJegy', description: 'Évközi'),
          mode: NameUidDesc(uid: 'm', name: 'Gyakorlati', description: 'gyakorlati'),
          valueType: NameUidDesc(uid: 'v', name: 'Osztalyzat', description: '5'),
          teacher: 'Edző',
          numericValue: 5,
          strValue: 'Jeles(5)',
          weightPercentage: 200,
          classGroup: UidObj(uid: 'cg'),
          sortIndex: 0,
        );
        final noTopicExam = Test(
          uid: 'test-no-topic',
          date: DateTime(2026, 11, 25, 10, 0),
          reportDate: fixedNow,
          teacherName: 'Kovács Béla',
          lessonNumber: 2,
          subject: peSubj,
          subjectName: 'Testnevelés',
          theme: null,
          method: NameUidDesc(
            uid: 'm-tz',
            name: 'Dolgozat',
            description: 'írásbeli témazáró',
          ),
          classGroup: UidObj(uid: 'cg'),
        );

        final session = _fakeSession();
        final dashboard = DashboardData(
          student: _makeStudent('Albert Milán'),
          todaysLessons: const [],
          allGrades: [olderGrade, newerWeightedGrade],
          latestGrades: [newerWeightedGrade, olderGrade],
          homeworks: const [],
          tests: [noTopicExam],
          omissions: const [],
          messages: const [],
          activeSession: session,
        );

        final settings = SettingsProvider();
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
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: settings.prefs),
              home: HomeScreen(
                initialSession: session,
                initialCachedData: dashboard,
                kretaClient: _FakeKretaClient(
                  dashboard: dashboard,
                  weekLessons: const [],
                ),
                prefs: settings.prefs,
                onPrefsChanged: (_) {},
                onLogout: () {},
                clock: () => fixedNow,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));

        // Lowercase topics auto-capitalized
        expect(find.text('Középtávfutás'), findsOneWidget);
        expect(find.text('Páros lefutás'), findsOneWidget);

        // Weighted impact delta: (4*100 + 5*200)/300 = 4.6667 => +0.67 from 4.00
        expect(find.text('+0.67'), findsOneWidget);
        expect(find.text('200%'), findsOneWidget);

        // First numeric grade shows neutral baseline marker rather than '+0.00'
        expect(find.text('-'), findsOneWidget);

        // Redundant date ('nov. 19.' / 'nov. 10.') removed inside feed grade cards
        expect(find.text('nov. 19.'), findsNothing);
        expect(find.text('nov. 10.'), findsNothing);

        // Exam card fallback auto-capitalizes method on top, clean 2-line subtitle
        expect(find.text('Írásbeli témazáró'), findsOneWidget);
        expect(find.text('Testnevelés • 2. óra'), findsOneWidget);
      },
    );

    testWidgets(
      'Fun greetings toggle updates HomeScreen greeting and MoreScreen appearance switch',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        GreetingUtils.resetForTesting(random: Random(7));
        addTearDown(() => GreetingUtils.resetForTesting());

        final fixedNow = DateTime(2026, 11, 10, 9, 0);
        final session = _fakeSession();
        final dashboard = DashboardData(
          student: _makeStudent('Albert Milán'),
          todaysLessons: const [],
          allGrades: const [],
          latestGrades: const [],
          homeworks: const [],
          tests: const [],
          omissions: const [],
          messages: const [],
          activeSession: session,
        );

        final settings = SettingsProvider();
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
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: settings.prefs),
              home: HomeScreen(
                initialSession: session,
                initialCachedData: dashboard,
                kretaClient: _FakeKretaClient(
                  dashboard: dashboard,
                  weekLessons: const [],
                ),
                prefs: settings.prefs,
                onPrefsChanged: (_) {},
                onLogout: () {},
                clock: () => fixedNow,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));

        expect(find.text('Szép napot, Milán!'), findsOneWidget);

        await settings.setFunGreetingsEnabled(true);
        await tester.pump(const Duration(milliseconds: 80));

        expect(find.text('Szép napot, Milán!'), findsNothing);
        final expectedPossibilities = GreetingUtils.eligibleFunTemplatesFor(
          fixedNow,
        ).map((t) => t.replaceAll('{name}', 'Milán')).toSet();
        expect(
          expectedPossibilities.any((g) => find.text(g).evaluate().isNotEmpty),
          isTrue,
        );

        // Verify Settings -> Megjelenés switch toggles funGreetingsEnabled cleanly
        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: theme,
            commute: commute,
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: settings.prefs),
              home: Scaffold(
                body: MoreScreen(
                  session: session,
                  student: dashboard.student,
                  kretaClient: _FakeKretaClient(
                    dashboard: dashboard,
                    weekLessons: const [],
                  ),
                  initialOmissions: const [],
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                  onLogout: () {},
                  settingsOnly: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('Megjelenés és témák'));
        await tester.pumpAndSettle();

        final switchFinder = find.byKey(
          const ValueKey<String>('appearance-fun-greetings-switch'),
        );
        await tester.scrollUntilVisible(
          switchFinder,
          240,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .last,
        );
        await tester.pumpAndSettle();

        expect(find.text('Fun üdvözlő üzenetek'), findsOneWidget);
        expect(
          find.text('Laza, vicces és napszakhoz illő köszönések a főoldalon'),
          findsOneWidget,
        );
        expect(settings.funGreetingsEnabled, isTrue);

        await tester.tap(switchFinder);
        await tester.pumpAndSettle();
        expect(settings.funGreetingsEnabled, isFalse);
      },
    );

    testWidgets(
      'Redesigned inspection modals render clean vertical hairline key-value lists with zero redundancy',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final peSubj = Subject(
          uid: 's-pe',
          name: 'Testnevelés',
          category: NameUidDesc(uid: 'cat', name: 'PE', description: 'PE'),
          sortIndex: 1,
        );
        final grade = Grade(
          uid: 'g-pe-1',
          recordDate: DateTime(2026, 11, 20, 9, 36),
          creationDate: DateTime(2026, 11, 20, 9, 36),
          valueType: NameUidDesc(
            uid: 'vt',
            name: 'Osztalyzat',
            description: 'Ötfokozatú',
          ),
          teacher: 'Márton Zsuzsanna Éva',
          subject: peSubj,
          type: NameUidDesc(
            uid: 't-evkozi',
            name: 'evkozi_jegy_ertekeles',
            description: 'Évközi jegy/értékelés',
          ),
          mode: NameUidDesc(
            uid: 'm-besz',
            name: 'Beszamolo',
            description: 'beszámoló',
          ),
          weightPercentage: 100,
          strValue: 'Jeles (5)',
          shortStrValue: '5',
          numericValue: 5,
          topic: '2000m futás',
          classGroup: UidObj(uid: 'cg-1'),
          sortIndex: 0,
        );

        final hw = Homework(
          uid: 'hw-modal-1',
          subject: peSubj,
          subjectName: 'Testnevelés',
          teacherName: '',
          description: 'Olvasd el a szabálykönyv 4. fejezetét.',
          startDate: DateTime(2026, 11, 20, 8, 0),
          dueDate: DateTime(2026, 11, 24, 8, 0),
          creationDate: DateTime(2026, 11, 20, 8, 0),
          isDone: false,
          isCreatedByTeacher: true,
          canBeSubmitted: false,
          canAttach: false,
          classGroup: UidObj(uid: 'cg-1'),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => showGradeInspectionModal(
                        context,
                        grade,
                        impactDeltaText: '+0.14',
                        impactDeltaColor: const Color(0xFF4ADE80),
                      ),
                      child: const Text('OpenGrade'),
                    ),
                    ElevatedButton(
                      onPressed: () => showHomeworkInspectionModal(
                        context,
                        hw,
                      ),
                      child: const Text('OpenHw'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // 1. Grade modal: header + 4 key-value rows, no category pill, no redundant rows
        await tester.tap(find.text('OpenGrade'));
        await tester.pumpAndSettle();

        expect(find.text('Értékelés / Jegy'), findsNothing);
        expect(find.text('Tantárgy'), findsNothing);
        expect(find.text('Érdemjegy'), findsNothing);
        expect(find.text('Súlyozás'), findsNothing);
        expect(find.text('5'), findsOneWidget);
        expect(find.text('2000m futás'), findsOneWidget);
        expect(find.text('Testnevelés • Jeles (100%)'), findsOneWidget);
        expect(find.text('Típus'), findsOneWidget);
        expect(find.text('Beszámoló'), findsOneWidget);
        expect(find.text('Átlagra hatás'), findsOneWidget);
        expect(find.text('+0.14'), findsOneWidget);
        expect(find.text('Tanár'), findsOneWidget);
        expect(find.text('Márton Zsuzsanna Éva'), findsOneWidget);
        expect(find.text('Dátum'), findsOneWidget);
        expect(find.text('2026. 11. 20. 09:36'), findsOneWidget);

        await tester.tap(find.text('Bezárás'));
        await tester.pumpAndSettle();

        // 2. Homework modal: empty Tanár auto-hidden, readable body text without Feladat leírása box
        await tester.tap(find.text('OpenHw'));
        await tester.pumpAndSettle();

        expect(find.text('Feladat leírása'), findsNothing);
        expect(find.text('Tantárgy'), findsNothing);
        expect(find.text('Tanár'), findsNothing);
        expect(find.text('Testnevelés'), findsOneWidget);
        expect(find.text('Házi feladat'), findsOneWidget);
        expect(find.text('Határidő'), findsOneWidget);
        expect(find.text('Státusz'), findsOneWidget);
        expect(find.text('Aktív'), findsOneWidget);
        expect(
          find.text('Olvasd el a szabálykönyv 4. fejezetét.'),
          findsOneWidget,
        );
      },
    );
  });
}
