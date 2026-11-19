import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:tinta_naplo/screens/grades_screen.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/services/calendar_sync_service.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Grade _testGrade({
  required String uid,
  required String subjectName,
  required int value,
  required int weightPercentage,
}) {
  final nowIso = DateTime(2026, 11, 10, 10, 0).toUtc().toIso8601String();
  return Grade.fromJson({
    'Uid': uid,
    'RogzitesDatuma': nowIso,
    'KeszitesDatuma': nowIso,
    'LattamozasDatuma': nowIso,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'cat1', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': 1,
    },
    'Tema': 'Dolgozat',
    'Tipus': {
      'Uid': 'evkozi_jegy_ertekeles',
      'Nev': 'evkozi_jegy_ertekeles',
      'Leiras': 'Évközi jegy',
    },
    'Mod': {'Uid': 'm1', 'Nev': 'Írásbeli', 'Leiras': 'Írásbeli'},
    'ErtekFajta': {
      'Uid': '1,Szazalekos',
      'Nev': 'Szazalekos',
      'Leiras': 'Százalékos',
    },
    'ErtekeloTanarNeve': 'Teszt Tanár',
    'Jelleg': 'Ertekeles',
    'SzamErtek': value,
    'SzovegesErtek': '$value',
    'SulySzazalekErteke': weightPercentage,
    'SzovegesErtekelesRovidNev': '$value',
    'OsztalyCsoport': {'Uid': 'g1'},
    'SortIndex': 1,
  });
}

Test _makeExam({
  required String uid,
  required DateTime date,
  required String subjectName,
  String? theme,
  String teacherName = 'Kiss Anna',
  String methodDesc = 'Írásbeli',
  int lessonNumber = 2,
}) {
  return Test(
    uid: uid,
    date: date,
    reportDate: date.subtract(const Duration(days: 3)),
    teacherName: teacherName,
    lessonNumber: lessonNumber,
    subject: Subject(
      uid: 'subj-$subjectName',
      name: subjectName,
      category: NameUidDesc(uid: 'cat', name: subjectName, description: ''),
      sortIndex: 0,
    ),
    subjectName: subjectName,
    theme: theme,
    method: NameUidDesc(
      uid: 'm-$uid',
      name: methodDesc,
      description: methodDesc,
    ),
    classGroup: UidObj(uid: 'grp-1'),
  );
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
      uid: 'subj-$subjectName',
      name: subjectName,
      category: NameUidDesc(uid: 'cat', name: subjectName, description: ''),
      sortIndex: 0,
    ),
    subjectName: subjectName,
    teacherName: 'Nagy Béla',
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
}

class _DummyKretaClient extends KretaClient {
  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async =>
      null;
}

class _FakeNativeCalendarPlatform {
  bool permissionGranted = true;
  final List<MethodCall> calls = [];
  final Map<String, Map<String, Object?>> storedEvents = {};
  int _nextId = 100;

  List<Map<String, Object?>> calendars = const [
    {
      'id': '1',
      'displayName': 'Google Naptár',
      'accountName': 'diak@gmail.com',
      'accountType': 'com.google',
      'ownerAccount': 'diak@gmail.com',
      'isGoogle': true,
      'isPrimary': true,
      'color': 0xFF4285F4,
      'visible': true,
    },
    {
      'id': '2',
      'displayName': 'Másodlagos Google Naptár',
      'accountName': 'school@gmail.com',
      'accountType': 'com.google',
      'ownerAccount': 'school@gmail.com',
      'isGoogle': true,
      'isPrimary': false,
      'color': 0xFF0F9D58,
      'visible': true,
    },
  ];

  Future<Object?> handleCall(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'hasCalendarPermissions':
        return permissionGranted;
      case 'requestCalendarPermissions':
        return permissionGranted;
      case 'getAvailableCalendars':
        return permissionGranted ? calendars : <Map<String, Object?>>[];
      case 'upsertEvent':
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final existingId = args['eventId']?.toString();
        final id = (existingId != null &&
                existingId.isNotEmpty &&
                storedEvents.containsKey(existingId))
            ? existingId
            : '${_nextId++}';
        storedEvents[id] = {
          'calendarId': args['calendarId']?.toString(),
          'title': args['title']?.toString(),
          'description': args['description']?.toString(),
          'startMillis': args['startMillis'],
          'endMillis': args['endMillis'],
        };
        return id;
      case 'deleteEvent':
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final id = args['eventId']?.toString() ?? '';
        return storedEvents.remove(id) != null;
      case 'deleteEvents':
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        final ids = (args['eventIds'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();
        var count = 0;
        for (final id in ids) {
          if (storedEvents.remove(id) != null) count++;
        }
        return count;
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feature 1: Cumulative Average & Scholarship Goal in Subject Simulator',
      () {
    test('computeSimulatedOverallAverage & resolveScholarshipTarget work cleanly',
        () {
      final mathGrades = [
        _testGrade(uid: 'g1', subjectName: 'Matematika', value: 3, weightPercentage: 100),
      ];
      final historyGrades = [
        _testGrade(uid: 'g2', subjectName: 'Történelem', value: 4, weightPercentage: 100),
      ];
      final subjects = SubjectGradeSummary.groupBySubject(
        [...mathGrades, ...historyGrades],
      );
      final mathSummary =
          subjects.firstWhere((s) => s.subjectName == 'Matematika');

      final prefs = const UserProfilePrefs(
        extras: {
          'scholarshipTargetTierIdx': 2,
          'scholarshipTargetAverage': 4.00,
        },
      );

      final simOverall = SubjectGradeSummary.computeSimulatedOverallAverage(
        subjects,
        simulatedSubject: mathSummary,
        simulatedSubjectRawAverage: 4.0, // +5 100% flips math 3.0 -> 4.0
        prefs: prefs,
      );
      expect(simOverall, closeTo(4.0, 0.001));

      final resolved = SubjectGradeSummary.resolveScholarshipTarget(3.5, prefs);
      expect(resolved.targetAverage, closeTo(4.0, 0.001));
      expect(resolved.tierIndex, 2);
    });

    testWidgets(
      'SubjectGradesDetailScreen updates side-by-side averages, delta, and scholarship goal on add/edit/remove without persisting',
      (tester) async {
        final mathGrades = [
          _testGrade(uid: 'm1', subjectName: 'Matematika', value: 3, weightPercentage: 100),
        ];
        final historyGrades = [
          _testGrade(uid: 'h1', subjectName: 'Történelem', value: 4, weightPercentage: 100),
        ];
        final subjects = SubjectGradeSummary.groupBySubject(
          [...mathGrades, ...historyGrades],
        );
        final mathSummary =
            subjects.firstWhere((s) => s.subjectName == 'Matematika');
        final prefs = const UserProfilePrefs(
          extras: {
            'scholarshipTargetTierIdx': 2,
            'scholarshipTargetAverage': 4.00,
          },
        );
        var prefsChangedCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: SubjectGradesDetailScreen(
              summary: mathSummary,
              allSubjects: subjects,
              prefs: prefs,
              onPrefsChanged: (_) => prefsChangedCalled = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Target grade box is always visible & strictly 100%-only (never 200%),
        // while ghost simulator inputs stay hidden behind the toggle button.
        expect(find.text('Cél érdemjegy'), findsOneWidget);
        expect(find.textContaining('200%'), findsNothing);
        expect(find.text('+5'), findsNothing);
        expect(find.text('Szellemjegyek'), findsOneWidget);

        // Expand ghost simulator via toggle button
        await tester.tap(find.text('Szellemjegyek'));
        await tester.pumpAndSettle();

        // Both labels side-by-side and initial target gap & 0.00 delta
        expect(find.text('Tantárgyi átlag'), findsOneWidget);
        expect(find.text('Összesített tanulmányi átlag'), findsOneWidget);
        expect(find.text('Ösztöndíj cél'), findsOneWidget);
        expect(find.text('0.00'), findsNWidgets(2));
        expect(find.text('Cél: 4.00 • Még +0.50 kell'), findsOneWidget);

        // Add ghost +5 (100%): math becomes 4.00, overall becomes 4.00 (+0.50), goal achieved!
        await tester.ensureVisible(find.text('+5'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('+5'));
        await tester.pumpAndSettle();

        expect(find.text('5 · 100%'), findsOneWidget);
        expect(find.text('+0.50'), findsOneWidget);
        expect(
          find.text('Elérted a kitűzött 4.00-es ösztöndíj célt!'),
          findsOneWidget,
        );

        // Edit ghost grade chip (5 -> 1 at 200% weight) => math drops (300+200)/300=1.67 (rounded 2)
        // Overall becomes (2+4)/2 = 3.00 => delta -0.50, gap +1.00
        await tester.ensureVisible(find.text('5 · 100%'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('5 · 100%'));
        await tester.pumpAndSettle();
        expect(find.text('Szellemjegy szerkesztése'), findsOneWidget);
        await tester.tap(find.text('1').last);
        await tester.pump();
        await tester.tap(find.text('200%').last);
        await tester.pump();
        await tester.tap(find.text('Mentés'));
        await tester.pumpAndSettle();

        expect(find.text('1 · 200%'), findsOneWidget);
        expect(find.text('-0.50'), findsOneWidget);
        expect(find.text('Cél: 4.00 • Még +1.00 kell'), findsOneWidget);

        // Remove via close icon => back to initial 0.00 delta & real grades untouched
        await tester.ensureVisible(find.byIcon(Icons.close_rounded).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.close_rounded).last);
        await tester.pumpAndSettle();
        expect(find.text('1 · 200%'), findsNothing);
        expect(find.text('Cél: 4.00 • Még +0.50 kell'), findsOneWidget);
        expect(mathSummary.grades.length, 1);
        expect(prefsChangedCalled, isFalse);
      },
    );
  });

  group('Feature 2: CalendarSyncService & Settings UI', () {
    test(
      'Strict future-only filter, clean formatting, deduplication, update, scope cleanup & clearAll',
      () async {
        SharedPreferences.setMockInitialValues({
          kCalendarSyncEnabledKey: true,
          kCalendarSyncContentModeKey: CalendarSyncContentMode.both.name,
        });

        final fakeNative = _FakeNativeCalendarPlatform();
        const testChannel = MethodChannel('test_calendar_sync_unit');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(testChannel, fakeNative.handleCall);

        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(testChannel, null);
        });

        final fixedNow = DateTime(2026, 11, 13, 12, 0);
        final service = CalendarSyncService(
          channel: testChannel,
          nowProvider: () => fixedNow,
        );

        final session = StoredSession(
          accessToken: 'a',
          refreshToken: 'r',
          idToken: 'i',
          instituteCode: 'klik001',
          expiresAt: DateTime(2026, 11, 14),
        );

        final initialDash = DashboardData(
          student: null,
          todaysLessons: const [],
          allGrades: const [],
          latestGrades: const [],
          tests: [
            _makeExam(
              uid: 'past-exam-yesterday',
              date: DateTime(2026, 11, 12, 9, 0),
              subjectName: 'Biológia',
              theme: 'Régi dolgozat',
            ),
            _makeExam(
              uid: 'past-exam-earlier-today',
              date: DateTime(2026, 11, 13, 8, 0),
              subjectName: 'Földrajz',
              theme: 'Ma reggeli',
            ),
            _makeExam(
              uid: 'future-exam-1',
              date: DateTime(2026, 11, 16, 10, 0),
              subjectName: 'Fizika',
              theme: 'Newton törvényei',
              methodDesc: 'Írásbeli',
              teacherName: 'Kiss Anna',
            ),
            _makeExam(
              uid: 'future-exam-2',
              date: DateTime(2026, 11, 17, 9, 0),
              subjectName: 'Kémia',
              theme: null,
            ),
          ],
          homeworks: [
            _makeHomework(
              uid: 'past-hw',
              dueDate: DateTime(2026, 11, 12, 8, 0),
              subjectName: 'Angol',
              description: 'Régi házi',
            ),
            _makeHomework(
              uid: 'future-hw-1',
              dueDate: DateTime(2026, 11, 15, 16, 0),
              subjectName: 'Magyar',
              description: '<p>Elemzés <b>írása</b></p>',
            ),
          ],
          activeSession: session,
        );

        // 1. Initial sync: ONLY 3 future items inserted, ZERO past items
        final res1 = await service.syncNow(dashboard: initialDash);
        expect(res1.performed, isTrue);
        expect(res1.syncedCount, 3);
        expect(res1.createdCount, 3);
        expect(res1.skippedPastCount, 3);
        expect(fakeNative.storedEvents.length, 3);

        final titles = fakeNative.storedEvents.values
            .map((e) => e['title'])
            .toSet();
        expect(
          titles,
          containsAll([
            '[Dolgozat] Fizika – Newton törvényei',
            '[Számonkérés] Kémia',
            '[Házi] Magyar',
          ]),
        );
        final hwEvent = fakeNative.storedEvents.values
            .firstWhere((e) => e['title'] == '[Házi] Magyar');
        expect(hwEvent['description'], 'Elemzés írása');

        // 2. Repeated sync with identical data => ZERO duplicate upsert calls
        fakeNative.calls.clear();
        final res2 = await service.syncNow(dashboard: initialDash);
        expect(res2.createdCount, 0);
        expect(res2.updatedCount, 0);
        expect(res2.syncedCount, 3);
        expect(
          fakeNative.calls.where((c) => c.method == 'upsertEvent'),
          isEmpty,
        );
        expect(fakeNative.storedEvents.length, 3);

        // 3. Modify future exam => updates existing eventId without duplicate
        final updatedDash = DashboardData(
          student: null,
          todaysLessons: const [],
          allGrades: const [],
          latestGrades: const [],
          tests: [
            _makeExam(
              uid: 'future-exam-1',
              date: DateTime(2026, 11, 16, 11, 0),
              subjectName: 'Fizika',
              theme: 'Mechanika frissítve',
            ),
            _makeExam(
              uid: 'future-exam-2',
              date: DateTime(2026, 11, 17, 9, 0),
              subjectName: 'Kémia',
              theme: null,
            ),
          ],
          homeworks: initialDash.homeworks,
          activeSession: session,
        );
        final res3 = await service.syncNow(dashboard: updatedDash);
        expect(res3.updatedCount, 1);
        expect(res3.createdCount, 0);
        expect(fakeNative.storedEvents.length, 3);
        expect(
          fakeNative.storedEvents.values.any(
            (e) => e['title'] == '[Dolgozat] Fizika – Mechanika frissítve',
          ),
          isTrue,
        );

        // 4. Scope change: switch to examsOnly => removes previously synced homework
        await service.setContentMode(CalendarSyncContentMode.examsOnly);
        final res4 = await service.syncNow(dashboard: updatedDash);
        expect(res4.deletedCount, 1);
        expect(res4.syncedCount, 2);
        expect(fakeNative.storedEvents.length, 2);
        expect(
          fakeNative.storedEvents.values
              .any((e) => e['title'] == '[Házi] Magyar'),
          isFalse,
        );

        // 5. Clear all synced events => deletes all events and clears SharedPreferences map
        final cleared = await service.clearAllSyncedEvents();
        expect(cleared, 2);
        expect(fakeNative.storedEvents, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(kCalendarSyncEventMapKey), isNull);
      },
    );

    testWidgets(
      'AppSettingsScreen renders Google Naptár szinkronizálás card, toggles OFF by default, switches scope & clears events',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final fakeNative = _FakeNativeCalendarPlatform();
        const channel = MethodChannel(kCalendarSyncChannelName);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, fakeNative.handleCall);
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final session = StoredSession(
          accessToken: 'acc',
          refreshToken: 'ref',
          idToken: 'id',
          instituteCode: 'klik001',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
        final futureExamDate = DateTime.now().add(const Duration(days: 3));
        final futureHwDate = DateTime.now().add(const Duration(days: 4));
        final dashboard = DashboardData(
          student: null,
          todaysLessons: const [],
          allGrades: const [],
          latestGrades: const [],
          tests: [
            _makeExam(
              uid: 'ui-exam-1',
              date: DateTime(
                futureExamDate.year,
                futureExamDate.month,
                futureExamDate.day,
                10,
                0,
              ),
              subjectName: 'Fizika',
              theme: 'Optika',
            ),
          ],
          homeworks: [
            _makeHomework(
              uid: 'ui-hw-1',
              dueDate: DateTime(
                futureHwDate.year,
                futureHwDate.month,
                futureHwDate.day,
                16,
                0,
              ),
              subjectName: 'Történelem',
              description: 'Esszé megírása',
            ),
          ],
          activeSession: session,
        );

        const prefs = UserProfilePrefs();
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: AppSettingsScreen(
              session: session,
              student: null,
              kretaClient: _DummyKretaClient(),
              dashboardData: dashboard,
              prefs: prefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Google Naptár szinkronizálás'), findsOneWidget);
        await tester.tap(find.text('Google Naptár szinkronizálás'));
        await tester.pumpAndSettle();

        // Default OFF
        final switchFinder = find.byType(SwitchListTile);
        expect(switchFinder, findsOneWidget);
        expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

        // Toggle ON => asks permission, discovers Google calendar, syncs 2 future events
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
        expect(find.text('Google Naptár'), findsOneWidget);
        expect(find.text('diak@gmail.com'), findsOneWidget);
        expect(find.text('Csak számonkérések'), findsOneWidget);
        expect(find.text('Csak házi feladatok'), findsOneWidget);
        expect(find.text('Mindkettő'), findsOneWidget);
        expect(find.text('Szinkronizálás most'), findsOneWidget);
        expect(find.text('Szinkronizált események törlése'), findsOneWidget);
        expect(fakeNative.storedEvents.length, 2);

        // Switch scope to 'Csak számonkérések' => deletes synced homework event
        await tester.tap(find.text('Csak számonkérések'));
        await tester.pumpAndSettle();
        expect(fakeNative.storedEvents.length, 1);
        final sharedPrefs = await SharedPreferences.getInstance();
        expect(
          sharedPrefs.getString(kCalendarSyncContentModeKey),
          CalendarSyncContentMode.examsOnly.name,
        );

        // Tap clear button => deletes remaining synced events
        final clearFinder = find.text('Szinkronizált események törlése');
        ScaffoldMessenger.of(tester.element(clearFinder)).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await tester.ensureVisible(clearFinder);
        await tester.pumpAndSettle();
        await tester.tap(clearFinder);
        await tester.pumpAndSettle();
        expect(fakeNative.storedEvents, isEmpty);
      },
    );
  });
}
