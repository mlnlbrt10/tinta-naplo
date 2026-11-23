import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/screens/grades_screen.dart';
import 'package:tinta_naplo/screens/home_screen.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/screens/notifications_settings_screen.dart';
import 'package:tinta_naplo/screens/school_year_schedule_screen.dart';
import 'package:tinta_naplo/screens/timetable_screen.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/kreta_notification_service.dart';
import 'package:tinta_naplo/services/school_year_schedule_service.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/minimalist_tokens.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/widgets/animation_helpers.dart';
import 'package:tinta_naplo/widgets/expandable_profile_card.dart';
import 'package:tinta_naplo/widgets/frosted_inspection_modal.dart';

StoredSession _testSession() => StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik-test-99',
      userName: 'tesztdiak',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

Grade _makeGrade({
  required String uid,
  required String subjectName,
  required int value,
  String topic = 'Témazáró',
  int weight = 200,
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
    'SulySzazalekErteke': weight,
    'SortIndex': 1,
  });
}

Test _makeTest({
  required String uid,
  required DateTime date,
  required String subjectName,
  String? theme,
  String methodDesc = 'Dolgozat',
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
      name: methodDesc,
      description: methodDesc,
    ),
    classGroup: UidObj(uid: 'grp-1'),
  );
}

Lesson _makeLesson({
  required String uid,
  required DateTime start,
  required String subjectName,
  int lessonNumber = 2,
  bool cancelled = false,
  String? substituteTeacher,
  String? homeworkUid,
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
    substituteTeacher: substituteTeacher,
    roomName: '204',
    type: NameUidDesc(uid: 't', name: 'Tanora', description: 'Tanóra'),
    state: cancelled
        ? NameUidDesc(uid: 'elmaradt', name: 'elmaradt', description: 'Elmaradt')
        : NameUidDesc(uid: 'm', name: 'Megtartott', description: 'Megtartott'),
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

class _StubTimetableClient extends KretaClient {
  final List<Lesson> lessons;

  _StubTimetableClient(this.lessons)
      : super(
          httpClient: MockClient((_) async => http.Response('[]', 200)),
          storage: const TokenStorageService(),
        );

  @override
  Future<List<Lesson>> fetchTimetableForRange(
    StoredSession session, {
    required DateTime from,
    required DateTime to,
  }) async =>
      lessons;
}

class _StubMessagesClient extends KretaClient {
  final List<KretaMessage> refreshedMessages;
  int markAllCalls = 0;

  _StubMessagesClient({
    required this.refreshedMessages,
    super.httpClient,
  }) : super(storage: const TokenStorageService());

  @override
  Future<List<KretaMessage>> fetchMessages(StoredSession session) async =>
      refreshedMessages;

  @override
  Future<int> markAllMessagesAsRead(
    StoredSession session,
    Iterable<KretaMessage> messages,
  ) async {
    markAllCalls++;
    return super.markAllMessagesAsRead(session, messages);
  }
}

Omission _makeOmission({
  required String uid,
  required String subjectName,
  required DateTime date,
  required OmissionState state,
  int? lateForMin,
  int classNo = 2,
}) {
  return Omission(
    uid: uid,
    subject: Subject(
      uid: 'sub_$subjectName',
      name: subjectName,
      category: NameUidDesc(uid: 'cat', name: subjectName, description: ''),
      sortIndex: 0,
    ),
    lesson: OmittedLesson(
      start: date,
      end: date.add(const Duration(minutes: 45)),
      classNo: classNo,
    ),
    date: date,
    teacher: 'Teszt Tanár',
    type: lateForMin != null
        ? NameUidDesc(uid: 'kes', name: 'Keses', description: 'Késés')
        : NameUidDesc(
            uid: 'hiany',
            name: 'OrarolValoHianyzas',
            description: 'Hiányzás',
          ),
    mode: NameUidDesc(uid: 'm', name: 'Tantargyi', description: 'Tanóra'),
    lateForMin: lateForMin,
    createdAt: date,
    state: state,
    proofType: state == OmissionState.excused
        ? NameUidDesc(uid: 'orv', name: 'Orvosi', description: 'Orvosi igazolás')
        : null,
  );
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feature 1: Instant Kréta Notifications & Customization Screen', () {
    test('renderTemplate substitutes all placeholders cleanly and collapses blank bullets', () {
      const template =
          '{subject} ({grade}) • Súly: {weight} • {teacher} • {room} • {date} • {topic} • {substitute_teacher} • {lesson_number}. óra';
      final rendered = KretaNotificationService.renderTemplate(template, {
        '{subject}': 'Matematika',
        '{grade}': '5',
        '{weight}': '200%',
        '{teacher}': 'Nagy Anna',
        '{room}': 'B-12',
        '{date}': '11. 24.',
        '{topic}': 'Logaritmus',
        '{substitute_teacher}': 'Kiss Béla',
        '{lesson_number}': '3',
      });
      expect(
        rendered,
        'Matematika (5) • Súly: 200% • Nagy Anna • B-12 • 11. 24. • Logaritmus • Kiss Béla • 3. óra',
      );

      final sparse = KretaNotificationService.renderTemplate(
        '{topic} • {teacher} • {room}',
        {'{topic}': 'Felelet', '{teacher}': '', '{room}': '105'},
      );
      expect(sparse, 'Felelet • 105');
    });

    test('processDashboardDiff baselines first sync and fires alerts only on real diffs', () async {
      SharedPreferences.setMockInitialValues({});
      final sentCalls = <MethodCall>[];
      const channel = MethodChannel('test_kreta_notifs');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        sentCalls.add(call);
        if (call.method == 'hasNotificationPermissions' ||
            call.method == 'requestNotificationPermissions') {
          return true;
        }
        return true;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = KretaNotificationService(channel: channel);
      final customCfg = KretaNotificationConfig.defaults().withCategory(
        KretaNotificationCategory.newGrade,
        const NotificationCategoryConfig(
          enabled: true,
          titleTemplate: 'Jegy jött: {subject} -> {grade}',
          bodyTemplate: 'Súly {weight}, {teacher}',
        ),
      );
      await service.saveConfig(customCfg);

      final session = _testSession();
      final baseDash = DashboardData(
        student: null,
        todaysLessons: [
          _makeLesson(
            uid: 'l-1',
            start: DateTime(2026, 11, 23, 8, 0),
            subjectName: 'Fizika',
            lessonNumber: 1,
          ),
        ],
        allGrades: [
          _makeGrade(uid: 'g-1', subjectName: 'Fizika', value: 4),
        ],
        latestGrades: const [],
        homeworks: const [],
        tests: const [],
        activeSession: session,
      );

      // Baseline sync: 0 alerts
      final initialAlerts = await service.processDashboardDiff(dashboard: baseDash);
      expect(initialAlerts, isEmpty);

      // Next sync: +1 grade, +1 exam, 1 cancelled lesson, 1 substitution
      final diffDash = DashboardData(
        student: null,
        todaysLessons: [
          _makeLesson(
            uid: 'l-1',
            start: DateTime(2026, 11, 23, 8, 0),
            subjectName: 'Fizika',
            lessonNumber: 1,
            cancelled: true,
          ),
          _makeLesson(
            uid: 'l-2',
            start: DateTime(2026, 11, 23, 8, 55),
            subjectName: 'Angol',
            lessonNumber: 2,
            substituteTeacher: 'Tóth Gábor',
          ),
        ],
        allGrades: [
          _makeGrade(uid: 'g-1', subjectName: 'Fizika', value: 4),
          _makeGrade(uid: 'g-2', subjectName: 'Matematika', value: 5, weight: 200),
        ],
        latestGrades: const [],
        homeworks: const [],
        tests: [
          _makeTest(
            uid: 't-1',
            date: DateTime(2026, 11, 26, 10, 0),
            subjectName: 'Történelem',
            theme: 'Szabadságharc',
            lessonNumber: 3,
          ),
        ],
        activeSession: session,
      );

      final alerts = await service.processDashboardDiff(dashboard: diffDash);
      expect(alerts.length, 4);
      final gradeAlert = alerts.firstWhere(
        (a) => a.category == KretaNotificationCategory.newGrade,
      );
      expect(gradeAlert.title, 'Jegy jött: Matematika -> 5');
      expect(gradeAlert.body, 'Súly 200%, Dr. Nagy Béla');

      expect(
        alerts.any((a) => a.category == KretaNotificationCategory.newExam),
        isTrue,
      );
      expect(
        alerts.any((a) => a.category == KretaNotificationCategory.cancelledLesson),
        isTrue,
      );
      expect(
        alerts.any((a) => a.category == KretaNotificationCategory.substitution),
        isTrue,
      );

      // Immediate repeat sync with same snapshot produces ZERO duplicate alerts
      final repeat = await service.processDashboardDiff(dashboard: diffDash);
      expect(repeat, isEmpty);
    });

    test(
      'Extended notifications (Késés, Hiányzás, Új üzenet): template placeholders, diff alerts & upgrade-safe baseline',
      () async {
        SharedPreferences.setMockInitialValues({});
        final sentCalls = <MethodCall>[];
        const channel = MethodChannel('test_kreta_notifs_ext');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          sentCalls.add(call);
          if (call.method == 'hasNotificationPermissions' ||
              call.method == 'requestNotificationPermissions') {
            return true;
          }
          return true;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        expect(
          KretaNotificationService.renderTemplate(
            '{subject} ({lesson_number}. óra) • {minutes} perc • {excused_status} • {type}',
            {
              '{subject}': 'Fizika',
              '{lesson_number}': '3',
              '{minutes}': '9 perc',
              '{excused_status}': 'Igazolatlan',
              '{type}': 'Orvosi igazolás',
            },
          ),
          'Fizika (3. óra) • 9 perc perc • Igazolatlan • Orvosi igazolás',
        );
        expect(
          KretaNotificationService.renderTemplate(
            'Üzenet: {sender} - {title}: {preview}',
            {
              '{sender}': 'Kiss Anna',
              '{title}': 'Osztályfőnöki',
              '{preview}': 'Holnap kirándulás',
            },
          ),
          'Üzenet: Kiss Anna - Osztályfőnöki: Holnap kirándulás',
        );

        final service = KretaNotificationService(channel: channel);
        final session = _testSession();

        // Seed a legacy v1 snapshot (initialized: true without omissions/messages flags)
        final accountKey = TokenStorageService.accountKeyForSession(session);
        final sp = await SharedPreferences.getInstance();
        await sp.setString(
          kKretaNotificationSnapshotPrefsKey,
          jsonEncode({
            accountKey: {
              'initialized': true,
              'gradeIds': ['g-1'],
            },
          }),
        );

        // First omission/message sync after upgrade seeds baseline without spamming historical items
        final historicOmission = _makeOmission(
          uid: 'om-old',
          subjectName: 'Biológia',
          date: DateTime(2026, 11, 18, 9, 0),
          state: OmissionState.excused,
        );
        final historicUnreadMsg = KretaMessage(
          uid: 'msg-old',
          sender: 'Igazgató',
          subject: 'Régi értesítés',
          body: 'Régi szöveg',
          sentAt: DateTime(2026, 11, 18, 8, 0),
          isRead: false,
        );
        final upgradeAlerts = await service.processOmissionsAndMessagesDiff(
          session: session,
          omissions: [historicOmission],
          messages: [historicUnreadMsg],
        );
        expect(upgradeAlerts, isEmpty);

        // Real subsequent additions fire Késés, Hiányzás, and Új üzenet
        // while read/sent messages do NOT notify.
        final newLate = _makeOmission(
          uid: 'om-late-1',
          subjectName: 'Fizika',
          date: DateTime(2026, 11, 23, 8, 55),
          state: OmissionState.unexcused,
          lateForMin: 7,
          classNo: 2,
        );
        final newAbsence = _makeOmission(
          uid: 'om-abs-1',
          subjectName: 'Történelem',
          date: DateTime(2026, 11, 23, 10, 50),
          state: OmissionState.pending,
          classNo: 4,
        );
        final newUnreadMsg = KretaMessage(
          uid: 'msg-new-unread',
          sender: 'Kovács Tanárnő',
          subject: 'Dolgozat időpont',
          body: 'Pénteken témazárót írunk a 2. órán.',
          sentAt: DateTime(2026, 11, 23, 11, 0),
          isRead: false,
        );
        final newReadMsg = KretaMessage(
          uid: 'msg-new-read',
          sender: 'Titkárság',
          subject: 'Olvasott',
          body: 'Már elolvasva',
          sentAt: DateTime(2026, 11, 23, 11, 5),
          isRead: true,
        );
        final newSentMsg = KretaMessage(
          uid: 'msg-new-sent',
          sender: 'Én',
          subject: 'Elküldött',
          body: 'Kimenő',
          sentAt: DateTime(2026, 11, 23, 11, 6),
          isRead: false,
          isSent: true,
        );

        final alerts = await service.processOmissionsAndMessagesDiff(
          session: session,
          omissions: [historicOmission, newLate, newAbsence],
          messages: [
            historicUnreadMsg,
            newUnreadMsg,
            newReadMsg,
            newSentMsg,
          ],
        );

        expect(alerts.length, 3);
        final lateAlert = alerts.firstWhere(
          (a) => a.category == KretaNotificationCategory.lateArrival,
        );
        expect(lateAlert.title, contains('Késés'));
        expect(lateAlert.title, contains('Fizika'));
        expect(lateAlert.title, contains('7 perc'));
        expect(lateAlert.body, contains('2. óra'));

        final absAlert = alerts.firstWhere(
          (a) => a.category == KretaNotificationCategory.absence,
        );
        expect(absAlert.title, contains('Történelem'));
        expect(absAlert.body, contains('Igazolandó'));

        final msgAlert = alerts.firstWhere(
          (a) => a.category == KretaNotificationCategory.newMessage,
        );
        expect(msgAlert.title, contains('Kovács Tanárnő'));
        expect(msgAlert.body, contains('Dolgozat időpont'));

        // Repeat sync emits zero duplicates
        final secondPass = await service.processOmissionsAndMessagesDiff(
          session: session,
          omissions: [historicOmission, newLate, newAbsence],
          messages: [
            historicUnreadMsg,
            newUnreadMsg,
            newReadMsg,
            newSentMsg,
          ],
        );
        expect(secondPass, isEmpty);
      },
    );

    testWidgets(
      'NotificationsSettingsScreen displays all 7 categories, edits template, resets default & triggers test notification',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final invokedCalls = <MethodCall>[];
        const channel = MethodChannel('test_notif_screen_chan');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          invokedCalls.add(call);
          if (call.method == 'hasNotificationPermissions' ||
              call.method == 'requestNotificationPermissions') {
            return true;
          }
          return true;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final service = KretaNotificationService(channel: channel);
        const prefs = UserProfilePrefs();

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: NotificationsSettingsScreen(
              prefs: prefs,
              notificationService: service,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final listScrollable = find.byType(Scrollable).first;
        for (final label in const [
          'Új jegy',
          'Új számonkérés',
          'Elmaradt óra',
          'Helyettesítés',
          'Késés',
          'Hiányzás',
          'Új üzenet',
        ]) {
          await tester.scrollUntilVisible(
            find.text(label),
            260,
            scrollable: listScrollable,
          );
          expect(find.text(label), findsOneWidget);
        }

        // Scroll UP back to Késés card, edit its title, then Reset to default
        final lateTitleFinder = find.byKey(
          const ValueKey<String>('notification-title-lateArrival'),
        );
        await tester.scrollUntilVisible(
          lateTitleFinder,
          -260,
          scrollable: listScrollable,
        );
        await tester.enterText(lateTitleFinder, 'Egyedi késés: {subject}');
        await tester.pumpAndSettle();

        final lateResetFinder = find.byKey(
          const ValueKey<String>('notification-reset-lateArrival'),
        );
        await tester.scrollUntilVisible(
          lateResetFinder,
          160,
          scrollable: listScrollable,
        );
        await tester.tap(lateResetFinder);
        await tester.pumpAndSettle();

        final resetCfg = await service.loadConfig();
        expect(
          resetCfg.forCategory(KretaNotificationCategory.lateArrival).titleTemplate,
          KretaNotificationCategory.lateArrival.defaultTitle,
        );

        // Scroll UP back to Új jegy test button and trigger test alert
        final newGradeTestBtn = find.byKey(
          const ValueKey<String>('notification-test-newGrade'),
        );
        await tester.scrollUntilVisible(
          newGradeTestBtn,
          -300,
          scrollable: listScrollable,
        );
        await tester.ensureVisible(newGradeTestBtn);
        await tester.pumpAndSettle();
        await tester.tap(newGradeTestBtn);
        await tester.pumpAndSettle();

        expect(
          invokedCalls.any((c) => c.method == 'showNotification'),
          isTrue,
        );
      },
    );
  });

  group('Feature 2: School Year Schedule (Tanév rendje) & Profile Integration', () {
    test('parseScheduleFromHtml extracts Hungarian breaks & working Saturdays and falls back gracefully', () async {
      SharedPreferences.setMockInitialValues({});
      const html = '''
        <html><body>
          <h1>A 2026/2027. tanév rendje</h1>
          <ul>
            <li>Őszi szünet: 2026. október 23. - november 1.</li>
            <li>Téli szünet: 2026. december 19. - 2027. január 3.</li>
            <li>Munkanap-áthelyezés (szombati munkanap): 2026. december 12.</li>
          </ul>
        </body></html>
      ''';
      final parsed = SchoolYearScheduleService.parseScheduleFromHtml(html, 2026);
      expect(parsed.length, greaterThanOrEqualTo(3));
      expect(
        parsed.any((e) => e.type == SchoolYearEventType.schoolBreak),
        isTrue,
      );
      expect(
        parsed.any((e) => e.type == SchoolYearEventType.workingSaturday),
        isTrue,
      );

      final service = SchoolYearScheduleService(
        httpClient: MockClient((_) async => http.Response('err', 500)),
        nowProvider: () => DateTime(2026, 10, 10),
      );
      final schedule = await service.fetchSchedule(
        student: null,
        instituteCode: 'klik01',
      );
      expect(schedule.schoolYearLabel, '2026/2027');
      expect(schedule.events, isNotEmpty);

      await service.addCustomEvent(
        'klik01',
        SchoolYearEvent(
          id: 'custom-1',
          title: 'DÖK Nap',
          startDate: DateTime(2026, 11, 27),
          endDate: DateTime(2026, 11, 27),
          type: SchoolYearEventType.specialDay,
          isCustom: true,
        ),
      );
      final withCustom = await service.loadCachedOrFallback(
        student: null,
        instituteCode: 'klik01',
        nowOverride: DateTime(2026, 10, 10),
      );
      expect(withCustom.events.any((e) => e.title == 'DÖK Nap'), isTrue);
    });

    testWidgets('Profile modal includes Tanév rendje tile opening SchoolYearScheduleScreen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      const prefs = UserProfilePrefs();
      final session = _testSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: prefs),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showStreamlinedProfileSheet(
                  context: context,
                  session: session,
                  student: null,
                  prefs: prefs,
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

      final tile = find.byKey(const ValueKey<String>('profile-school-year-tile'));
      expect(tile, findsOneWidget);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.byType(SchoolYearScheduleScreen), findsOneWidget);
      expect(find.textContaining('Tanév rendje'), findsAtLeastNWidgets(1));
    });
  });

  group('Feature 4: Minimalist Mode UI Density Overhaul', () {
    test('MinimalistTokens reduces horizontal padding, card radii, and badge sizes', () {
      const normal = MinimalistTokens(false);
      const compact = MinimalistTokens(true);

      expect(compact.horizontalPagePadding, lessThan(normal.horizontalPagePadding));
      expect(compact.cardGap, lessThan(normal.cardGap));
      expect(compact.badgeSize, lessThan(normal.badgeSize));
      expect(compact.tabBarHeight, lessThan(normal.tabBarHeight));
    });

    testWidgets('GradesScreen uses mini FAB and compact density in Minimalist Mode', (tester) async {
      SharedPreferences.setMockInitialValues({});
      const minPrefs = UserProfilePrefs(
        extras: <String, dynamic>{'minimalistModeEnabled': true},
      );
      final grades = [
        _makeGrade(uid: 'g1', subjectName: 'Matematika', value: 5),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: minPrefs),
          home: GradesScreen(
            allGrades: grades,
            prefs: minPrefs,
            onPrefsChanged: (_) {},
            onRefresh: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.mini, isTrue);
    });
  });

  group('Feature 6: Messages Pinned Olvasatlan, Mark All Read & Zero Flicker', () {
    testWidgets(
      'Pins unread messages in Olvasatlan section, marks all read on tap, and refreshes without flicker',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});

        final session = _testSession();
        final initialMessages = [
          KretaMessage(
            uid: '101',
            messageId: '9101',
            sender: 'Kovács Tanárnő',
            subject: 'Olvasatlan Dolgozat',
            body: 'Holnap dolgozat.',
            sentAt: DateTime(2026, 11, 20, 10, 0),
            isRead: false,
          ),
          KretaMessage(
            uid: '102',
            messageId: '9102',
            sender: 'Nagy Tanár Úr',
            subject: 'Régi olvasott üzenet',
            body: 'Rendben.',
            sentAt: DateTime(2026, 11, 18, 9, 0),
            isRead: true,
          ),
        ];

        final stubClient = _StubMessagesClient(
          refreshedMessages: initialMessages,
          httpClient: MockClient((req) async {
            if (req.url.path.endsWith('/uzenetek/olvasott')) {
              return http.Response('', 200);
            }
            return http.Response('[]', 200);
          }),
        );

        const prefs = UserProfilePrefs();
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: Scaffold(
              body: MoreScreen(
                session: session,
                student: null,
                kretaClient: stubClient,
                prefs: prefs,
                onPrefsChanged: (_) {},
                onLogout: () {},
                messagesOnly: true,
                initialMessages: initialMessages,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Pinned Olvasatlan header sits above Olvasott header
        final unreadHdr = find.byKey(
          const ValueKey<String>('messages-unread-section-header'),
        );
        final readHdr = find.byKey(
          const ValueKey<String>('messages-read-section-header'),
        );
        expect(unreadHdr, findsOneWidget);
        expect(readHdr, findsOneWidget);
        expect(
          tester.getTopLeft(unreadHdr).dy,
          lessThan(tester.getTopLeft(readHdr).dy),
        );

        // Unread message tile appears above read message tile
        expect(
          tester.getTopLeft(find.text('Olvasatlan Dolgozat')).dy,
          lessThan(tester.getTopLeft(find.text('Régi olvasott üzenet')).dy),
        );

        // One-tap Mark All as Read button
        final markAllBtn = find.byKey(
          const ValueKey<String>('messages-mark-all-read-btn'),
        );
        expect(markAllBtn, findsOneWidget);
        await tester.tap(markAllBtn);
        await tester.pumpAndSettle();

        expect(stubClient.markAllCalls, 1);
        expect(unreadHdr, findsNothing);
        expect(markAllBtn, findsNothing);

        // Horizontal swipe switches between Beérkezett and Elküldött folders
        final msgSwipe = find.byKey(const ValueKey<String>('messages-subtab-swipe'));
        expect(msgSwipe, findsOneWidget);
        await tester.drag(msgSwipe, const Offset(-160, 0));
        await tester.pumpAndSettle();
        expect(
          find.text('Még nincs elküldött üzenet. Koppints az „Új üzenet” gombra!'),
          findsOneWidget,
        );

        await tester.drag(msgSwipe, const Offset(160, 0));
        await tester.pumpAndSettle();
        expect(find.text('Olvasatlan Dolgozat'), findsOneWidget);
      },
    );
  });

  group('Feature 7: Exams on Timetable Days + Filter Toggles', () {
    testWidgets(
      'Shows scheduled exams on matching day & lesson, and toggles hide exams/homework independently',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final monday = DateTime(2026, 11, 23); // Monday
        final lessonStart = DateTime(2026, 11, 23, 8, 55);
        final lessons = [
          _makeLesson(
            uid: 'les-2',
            start: lessonStart,
            subjectName: 'Fizika',
            lessonNumber: 2,
            homeworkUid: 'hw-fiz-1',
          ),
        ];
        final tests = [
          _makeTest(
            uid: 'test-fiz-1',
            date: lessonStart,
            subjectName: 'Fizika',
            theme: 'Kinematika dolgozat',
            methodDesc: 'Írásbeli dolgozat',
            lessonNumber: 2,
          ),
        ];
        final homeworks = [
          _makeHomework(
            uid: 'hw-fiz-1',
            dueDate: lessonStart,
            subjectName: 'Fizika',
            description: 'Oldd meg a feladatokat',
          ),
        ];

        final stubClient = _StubTimetableClient(lessons);
        final session = _testSession();
        var prefs = const UserProfilePrefs();

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: TimetableScreen(
                  session: session,
                  kretaClient: stubClient,
                  initialTodaysLessons: lessons,
                  homeworks: homeworks,
                  tests: tests,
                  prefs: prefs,
                  onPrefsChanged: (next) => setState(() => prefs = next),
                  clock: () => DateTime(2026, 11, 23, 7, 30),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Day summary exam banner was removed; only lesson-level Számonkérés & Házi badges appear
        expect(
          find.byKey(const ValueKey<String>('timetable-day-exam-test-fiz-1')),
          findsNothing,
        );
        expect(find.text('Számonkérés'), findsOneWidget);
        expect(find.text('Házi'), findsOneWidget);

        // Open Timetable Settings / Filter panel
        await tester.tap(find.byIcon(Icons.tune_rounded));
        await tester.pumpAndSettle();

        final examsToggle = find.byKey(
          const ValueKey<String>('timetable-toggle-show-exams'),
        );
        final homeworkToggle = find.byKey(
          const ValueKey<String>('timetable-toggle-show-homework'),
        );
        expect(examsToggle, findsOneWidget);
        expect(homeworkToggle, findsOneWidget);
        expect(find.text('Számonkérések mutatása az órarenden'), findsOneWidget);
        expect(find.text('Házik mutatása az órarenden'), findsOneWidget);

        // Toggle OFF exams => lesson Számonkérés disappears, Házi remains
        await tester.tap(examsToggle);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('timetable-day-exam-test-fiz-1')),
          findsNothing,
        );
        expect(find.text('Számonkérés'), findsNothing);
        expect(find.text('Házi'), findsOneWidget);

        // Toggle OFF homework => Házi badge disappears too
        await tester.tap(homeworkToggle);
        await tester.pumpAndSettle();
        expect(find.text('Házi'), findsNothing);

        // Toggle ON exams => lesson-level Számonkérés reappears immediately (no top banner)
        await tester.tap(examsToggle);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('timetable-day-exam-test-fiz-1')),
          findsNothing,
        );
        expect(find.text('Számonkérés'), findsOneWidget);
        expect(monday.weekday, DateTime.monday);
      },
    );
  });

  group('Feature 8: Ösztöndíj kalkulátor Bottom Sheet Scroll Behavior', () {
    testWidgets(
      'Scrolling down through Ajánlott lépések stays scrolled without snapping back to top',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(420, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const prefs = UserProfilePrefs();
        final grades = [
          _makeGrade(uid: 'g-1', subjectName: 'Matematika', value: 3),
          _makeGrade(uid: 'g-2', subjectName: 'Fizika', value: 3),
          _makeGrade(uid: 'g-3', subjectName: 'Kémia', value: 3),
          _makeGrade(uid: 'g-4', subjectName: 'Biológia', value: 3),
          _makeGrade(uid: 'g-5', subjectName: 'Történelem', value: 3),
          _makeGrade(uid: 'g-6', subjectName: 'Irodalom', value: 3),
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

        await tester.tap(find.text('Összesített súlyozott átlag'));
        await tester.pumpAndSettle();

        expect(find.text('Ösztöndíj kalkulátor'), findsOneWidget);
        final scrollViewFinder = find.byKey(
          const ValueKey<String>('scholarship-scroll-view'),
        );
        expect(scrollViewFinder, findsOneWidget);

        final scrollView = tester.widget<SingleChildScrollView>(scrollViewFinder);
        final ctrl = scrollView.controller!;
        expect(ctrl.offset, 0.0);
        expect(ctrl.position.maxScrollExtent, greaterThan(120.0));

        // Drag upward repeatedly to scroll down to Ajánlott lépések
        await tester.drag(scrollViewFinder, const Offset(0, -340));
        await tester.pumpAndSettle();
        final afterFirstDrag = ctrl.offset;
        expect(afterFirstDrag, greaterThan(100.0));

        // Second drag down & mild bottom overscroll must stay scrolled down
        await tester.drag(scrollViewFinder, const Offset(0, -340));
        await tester.pumpAndSettle();
        expect(ctrl.offset, greaterThanOrEqualTo(afterFirstDrag));
        expect(find.text('Ösztöndíj kalkulátor'), findsOneWidget);

        // Return to top, then downward swipe dismisses sheet normally
        ctrl.jumpTo(0.0);
        await tester.pump();
        await tester.drag(scrollViewFinder, const Offset(0, 320));
        await tester.pumpAndSettle();
        expect(find.text('Ösztöndíj kalkulátor'), findsNothing);
      },
    );
  });

  group('Feature 9: Horizontal Swipe Between In-Screen Sub-Tabs', () {
    testWidgets(
      'HomeScreen horizontal swipe cycles Összes -> Jegyek -> Házik -> Számonkérések without switching bottom tabs',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final session = _testSession();
        final now = DateTime(2026, 11, 23, 10, 0);
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
            _makeGrade(
              uid: 'hg-1',
              subjectName: 'Matematika',
              value: 5,
              topic: 'Algebra dolgozat',
            ),
          ],
          latestGrades: [
            _makeGrade(
              uid: 'hg-1',
              subjectName: 'Matematika',
              value: 5,
              topic: 'Algebra dolgozat',
            ),
          ],
          homeworks: [
            _makeHomework(
              uid: 'hhw-1',
              dueDate: now.add(const Duration(days: 1)),
              subjectName: 'Biológia',
              description: 'Sejtbiológia feladatlap',
            ),
          ],
          tests: [
            _makeTest(
              uid: 'ht-1',
              date: now.add(const Duration(days: 2)),
              subjectName: 'Kémia',
              theme: 'Savak és bázisok témazáró',
            ),
          ],
          activeSession: session,
        );

        const prefs = UserProfilePrefs();
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
        await tester.pump(const Duration(milliseconds: 500));

        final swipeArea = find.byKey(const ValueKey<String>('home-subtab-swipe'));
        expect(swipeArea, findsOneWidget);
        expect(
          tester.widget<HorizontalSubTabSwipeDetector>(swipeArea).currentIndex,
          0, // Összes
        );
        expect(find.text('Algebra dolgozat'), findsOneWidget);
        expect(find.text('Sejtbiológia feladatlap'), findsOneWidget);

        // Swipe left: Összes (0) -> Jegyek (1)
        await tester.drag(swipeArea, const Offset(-180, 0));
        await tester.pumpAndSettle();
        expect(
          tester.widget<HorizontalSubTabSwipeDetector>(swipeArea).currentIndex,
          1,
        );
        expect(find.text('Algebra dolgozat'), findsOneWidget);
        expect(swipeArea, findsOneWidget); // Bottom nav stayed on Főoldal

        // Swipe left: Jegyek (1) -> Házik (2)
        await tester.drag(swipeArea, const Offset(-180, 0));
        await tester.pumpAndSettle();
        expect(
          tester.widget<HorizontalSubTabSwipeDetector>(swipeArea).currentIndex,
          2,
        );
        expect(find.text('Sejtbiológia feladatlap'), findsOneWidget);
        expect(find.text('Összes házi megjelölése készként'), findsOneWidget);

        // Swipe left: Házik (2) -> Számonkérések (3)
        await tester.drag(swipeArea, const Offset(-180, 0));
        await tester.pumpAndSettle();
        expect(
          tester.widget<HorizontalSubTabSwipeDetector>(swipeArea).currentIndex,
          3,
        );
        expect(find.text('Savak és bázisok témazáró'), findsOneWidget);

        // Swipe right: Számonkérések (3) -> Házik (2)
        await tester.drag(swipeArea, const Offset(180, 0));
        await tester.pumpAndSettle();
        expect(
          tester.widget<HorizontalSubTabSwipeDetector>(swipeArea).currentIndex,
          2,
        );
        expect(find.text('Összes házi megjelölése készként'), findsOneWidget);
      },
    );

    testWidgets(
      'GradesScreen horizontal swipe switches sort sub-tabs A-Z <-> Átlag ↑',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        const prefs = UserProfilePrefs();
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

        expect(
          tester.getTopLeft(find.text('Algebra')).dy,
          lessThan(tester.getTopLeft(find.text('Biológia')).dy),
        );

        final gradesSwipe = find.byKey(
          const ValueKey<String>('grades-subtab-swipe'),
        );
        expect(gradesSwipe, findsOneWidget);

        // Swipe left: A-Z -> Átlag ↑ (Javítandó) => 2.00 Biológia rises above 5.00 Algebra
        await tester.drag(gradesSwipe, const Offset(-180, 0));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Biológia')).dy,
          lessThan(tester.getTopLeft(find.text('Algebra')).dy),
        );

        // Swipe right back to A-Z
        await tester.drag(gradesSwipe, const Offset(180, 0));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Algebra')).dy,
          lessThan(tester.getTopLeft(find.text('Biológia')).dy),
        );
      },
    );

    testWidgets(
      'MoreScreen Attendance horizontal swipe cycles Összes -> Igazolt -> Igazolatlan',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        const prefs = UserProfilePrefs();
        final omissions = [
          _makeOmission(
            uid: 'om-exc',
            subjectName: 'Irodalom',
            date: DateTime(2026, 11, 20, 8, 0),
            state: OmissionState.excused,
          ),
          _makeOmission(
            uid: 'om-unc',
            subjectName: 'Fizika',
            date: DateTime(2026, 11, 19, 9, 0),
            state: OmissionState.unexcused,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: Scaffold(
              body: MoreScreen(
                session: _testSession(),
                student: null,
                prefs: prefs,
                onPrefsChanged: (_) {},
                onLogout: () {},
                initialOmissions: omissions,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Irodalom'), findsOneWidget);
        expect(find.text('Fizika'), findsOneWidget);

        final attSwipe = find.byKey(
          const ValueKey<String>('attendance-subtab-swipe'),
        );
        expect(attSwipe, findsOneWidget);

        // Swipe left: Összes -> Igazolt
        await tester.drag(attSwipe, const Offset(-180, 0));
        await tester.pumpAndSettle();
        expect(find.text('Irodalom'), findsOneWidget);
        expect(find.text('Fizika'), findsNothing);

        // Swipe left: Igazolt -> Igazolatlan
        await tester.drag(attSwipe, const Offset(-180, 0));
        await tester.pumpAndSettle();
        expect(find.text('Irodalom'), findsNothing);
        expect(find.text('Fizika'), findsOneWidget);

        // Swipe right back twice -> Összes
        await tester.drag(attSwipe, const Offset(180, 0));
        await tester.pumpAndSettle();
        await tester.drag(attSwipe, const Offset(180, 0));
        await tester.pumpAndSettle();
        expect(find.text('Irodalom'), findsOneWidget);
        expect(find.text('Fizika'), findsOneWidget);
      },
    );
  });

  group('Absences Banner, Bottom Nav Dot, Orange Igazolandó, Timetable & Felszereléshiány', () {
    testWidgets(
      'HomeScreen shows dismissible unexcused banner above next lesson, keeps bottom nav dot, and persists dismiss until a new omission arrives',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = const Size(420, 920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final session = _testSession();
        final now = DateTime(2026, 11, 23, 10, 0);
        final omPending = _makeOmission(
          uid: 'om-pend-1',
          subjectName: 'Matematika',
          date: DateTime(2026, 11, 23, 8, 0),
          state: OmissionState.pending,
          classNo: 1,
        );
        final omLate = _makeOmission(
          uid: 'om-late-1',
          subjectName: 'Fizika',
          date: DateTime(2026, 11, 23, 8, 55),
          state: OmissionState.unexcused,
          lateForMin: 6,
          classNo: 2,
        );

        final dash1 = DashboardData(
          student: null,
          todaysLessons: [
            _makeLesson(
              uid: 'l-next',
              start: DateTime(2026, 11, 23, 11, 0),
              subjectName: 'Történelem',
              lessonNumber: 4,
            ),
          ],
          allGrades: const [],
          latestGrades: const [],
          homeworks: const [],
          tests: const [],
          omissions: [omPending, omLate],
          activeSession: session,
        );

        const prefs = UserProfilePrefs();
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: HomeScreen(
              initialSession: session,
              initialCachedData: dash1,
              kretaClient: _StubHomeDashboardClient(dash1),
              prefs: prefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => now,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final banner = find.byKey(const ValueKey<String>('home-unexcused-banner'));
        final nextCard = find.byKey(const ValueKey('home-next'));
        final navDot = find.byKey(const ValueKey<String>('bottom-nav-absences-dot'));
        expect(banner, findsOneWidget);
        expect(navDot, findsOneWidget);
        expect(
          tester.getTopLeft(banner).dy,
          lessThan(tester.getTopLeft(nextCard).dy),
        );

        // Dismiss banner: banner hides, bottom nav indicator dot stays visible
        await tester.tap(
          find.byKey(const ValueKey<String>('home-unexcused-banner-dismiss')),
        );
        await tester.pumpAndSettle();
        expect(banner, findsNothing);
        expect(navDot, findsOneWidget);

        // Rebuild with same unexcused omissions: banner stays dismissed
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: HomeScreen(
              key: const ValueKey<String>('home-rebuilt-same'),
              initialSession: session,
              initialCachedData: dash1,
              kretaClient: _StubHomeDashboardClient(dash1),
              prefs: prefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => now,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(banner, findsNothing);
        expect(navDot, findsOneWidget);

        // New unexcused omission arrives -> banner reappears and tapping it opens Hiányzások tab
        final dash2 = DashboardData(
          student: null,
          todaysLessons: dash1.todaysLessons,
          allGrades: const [],
          latestGrades: const [],
          homeworks: const [],
          tests: const [],
          omissions: [
            omPending,
            omLate,
            _makeOmission(
              uid: 'om-new-2',
              subjectName: 'Kémia',
              date: DateTime(2026, 11, 23, 9, 50),
              state: OmissionState.pending,
              classNo: 3,
            ),
          ],
          activeSession: session,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: HomeScreen(
              key: const ValueKey<String>('home-rebuilt-new'),
              initialSession: session,
              initialCachedData: dash2,
              kretaClient: _StubHomeDashboardClient(dash2),
              prefs: prefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => now,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(banner, findsOneWidget);
        expect(find.textContaining('Kémia'), findsWidgets);

        await tester.tap(banner);
        await tester.pumpAndSettle();
        expect(find.text('Hiányzások és Késések'), findsOneWidget);
      },
    );

    testWidgets(
      'Igazolandó omissions are highlighted distinctly in orange across Hiányzások and Timetable-style day popup',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        const prefs = UserProfilePrefs();
        final darkOrange = OledTheme.omissionPendingOrangeColor(Brightness.dark);
        final darkRed = OledTheme.omissionUnexcusedRedColor(Brightness.dark);
        final darkGreen = OledTheme.omissionExcusedColor(Brightness.dark);
        expect(darkOrange, const Color(0xFFF97316));

        final day = DateTime(2026, 11, 20, 8, 0);
        final omPending = _makeOmission(
          uid: 'om-o-1',
          subjectName: 'Matematika',
          date: day,
          state: OmissionState.pending,
          classNo: 1,
        );
        final omUnexcused = _makeOmission(
          uid: 'om-r-1',
          subjectName: 'Fizika',
          date: day.add(const Duration(minutes: 55)),
          state: OmissionState.unexcused,
          classNo: 2,
        );
        final omExcused = _makeOmission(
          uid: 'om-g-1',
          subjectName: 'Irodalom',
          date: day.add(const Duration(minutes: 110)),
          state: OmissionState.excused,
          classNo: 3,
        );

        final group = DailyOmissionGroup(
          day: DateUtils.dateOnly(day),
          entries: [omPending],
        );
        expect(group.resolveAccentColor(Brightness.dark), darkOrange);

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: Scaffold(
              body: MoreScreen(
                session: _testSession(),
                student: null,
                prefs: prefs,
                onPrefsChanged: (_) {},
                onLogout: () {},
                initialOmissions: [omPending, omUnexcused, omExcused],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pendingBadgeFinder = find.byKey(
          const ValueKey<String>('subject-pending-badge-sub_Matematika'),
        );
        await tester.scrollUntilVisible(
          pendingBadgeFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(pendingBadgeFinder, findsOneWidget);
        final pendingBadgeText = tester.widget<Text>(
          find.descendant(
            of: pendingBadgeFinder,
            matching: find.text('Igazolandó'),
          ),
        );
        expect(pendingBadgeText.style?.color, darkOrange);

        // Open timetable-style absence popup for day containing pending, unexcused & excused slots
        await tester.runAsync(() async {});
        showDayTimetableOmissionsSheet(
          tester.element(find.byType(MoreScreen)),
          group: DailyOmissionGroup(
            day: DateUtils.dateOnly(day),
            entries: [omPending, omUnexcused, omExcused],
          ),
          prefs: prefs,
          dateFormat: DateFormat('yyyy. MM. dd.'),
          dayLessons: [
            _makeLesson(uid: 'dl1', start: day, subjectName: 'Matematika', lessonNumber: 1),
            _makeLesson(
              uid: 'dl2',
              start: day.add(const Duration(minutes: 55)),
              subjectName: 'Fizika',
              lessonNumber: 2,
            ),
            _makeLesson(
              uid: 'dl3',
              start: day.add(const Duration(minutes: 110)),
              subjectName: 'Irodalom',
              lessonNumber: 3,
            ),
          ],
        );
        await tester.pumpAndSettle();

        final slot1BadgeText = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('day-timetable-slot-1')),
            matching: find.text('Hiányzás • Igazolandó'),
          ),
        );
        expect(slot1BadgeText.style?.color, darkOrange);

        final slot2BadgeText = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('day-timetable-slot-2')),
            matching: find.text('Hiányzás • Igazolatlan'),
          ),
        );
        expect(slot2BadgeText.style?.color, darkRed);

        final slot3BadgeText = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('day-timetable-slot-3')),
            matching: find.text('Hiányzás • Igazolt'),
          ),
        );
        expect(slot3BadgeText.style?.color, darkGreen);
      },
    );

    testWidgets(
      'Main TimetableScreen cross-references lessons with absences & late arrivals with semantic colors',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final monday = DateTime(2026, 11, 23);
        final lessons = [
          _makeLesson(
            uid: 'tt-1',
            start: DateTime(2026, 11, 23, 8, 0),
            subjectName: 'Matematika',
            lessonNumber: 1,
          ),
          _makeLesson(
            uid: 'tt-2',
            start: DateTime(2026, 11, 23, 8, 55),
            subjectName: 'Fizika',
            lessonNumber: 2,
          ),
          _makeLesson(
            uid: 'tt-3',
            start: DateTime(2026, 11, 23, 9, 50),
            subjectName: 'Kémia',
            lessonNumber: 3,
          ),
          _makeLesson(
            uid: 'tt-4',
            start: DateTime(2026, 11, 23, 10, 45),
            subjectName: 'Történelem',
            lessonNumber: 4,
          ),
        ];
        final omissions = [
          _makeOmission(
            uid: 'om-tt-1',
            subjectName: 'Matematika',
            date: DateTime(2026, 11, 23, 8, 0),
            state: OmissionState.pending,
            classNo: 1,
          ),
          _makeOmission(
            uid: 'om-tt-2',
            subjectName: 'Fizika',
            date: DateTime(2026, 11, 23, 8, 55),
            state: OmissionState.unexcused,
            classNo: 2,
          ),
          _makeOmission(
            uid: 'om-tt-3',
            subjectName: 'Kémia',
            date: DateTime(2026, 11, 23, 9, 50),
            state: OmissionState.excused,
            classNo: 3,
          ),
          _makeOmission(
            uid: 'om-tt-4',
            subjectName: 'Történelem',
            date: DateTime(2026, 11, 23, 10, 45),
            state: OmissionState.pending,
            lateForMin: 5,
            classNo: 4,
          ),
        ];

        const prefs = UserProfilePrefs();
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: Scaffold(
              body: TimetableScreen(
                session: _testSession(),
                kretaClient: _StubTimetableClient(lessons),
                initialTodaysLessons: lessons,
                omissions: omissions,
                prefs: prefs,
                onPrefsChanged: (_) {},
                clock: () => monday,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final badge1 = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('timetable-lesson-omission-tt-1')),
            matching: find.text('Hiányzás • Igazolandó'),
          ),
        );
        expect(badge1.style?.color, OledTheme.omissionPendingOrangeColor(Brightness.dark));

        final badge2 = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('timetable-lesson-omission-tt-2')),
            matching: find.text('Hiányzás • Igazolatlan'),
          ),
        );
        expect(badge2.style?.color, OledTheme.omissionUnexcusedRedColor(Brightness.dark));

        final badge3 = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('timetable-lesson-omission-tt-3')),
            matching: find.text('Hiányzás • Igazolt'),
          ),
        );
        expect(badge3.style?.color, OledTheme.omissionExcusedColor(Brightness.dark));

        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('timetable-lesson-omission-tt-4')),
            matching: find.text('Késés (5p) • Igazolandó'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'MissingEquipmentItem extracts Felszereléshiány records and HomeScreen renders them on Főoldal',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = const Size(420, 920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime(2026, 11, 23, 10, 0);
        final parsed = MissingEquipmentItem.extractMissingEquipments(
          rawNotes: [
            {
              'Uid': 'felj-1',
              'Cim': 'Felszereléshiány',
              'Tartalom': 'Körző és vonalzó hiányzott',
              'KeszitoTanarNeve': 'Nagy Béla',
              'Tantargy': {'Nev': 'Matematika'},
              'Datum': '2026-11-23T08:15:00Z',
              'Tipus': {'Nev': 'Felszereleshiany', 'Leiras': 'Felszereléshiány'},
            },
          ],
        );
        expect(parsed.length, 1);
        expect(parsed.first.subjectName, 'Matematika');
        expect(parsed.first.note, 'Körző és vonalzó hiányzott');
        expect(parsed.first.teacher, 'Nagy Béla');

        final session = _testSession();
        final dash = DashboardData(
          student: null,
          todaysLessons: const [],
          allGrades: const [],
          latestGrades: const [],
          homeworks: const [],
          tests: const [],
          missingEquipments: parsed,
          activeSession: session,
        );

        const prefs = UserProfilePrefs();
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: HomeScreen(
              initialSession: session,
              initialCachedData: dash,
              kretaClient: _StubHomeDashboardClient(dash),
              prefs: prefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => now,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('home-missing-equipment-card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('home-equipment-item-felj-1')),
          findsOneWidget,
        );
        expect(find.textContaining('Felszereléshiány'), findsWidgets);
        expect(find.text('Körző és vonalzó hiányzott'), findsWidgets);
      },
    );
  });

  group('v3.2 UI/UX & Logic Fixes', () {
    test(
      'groupOmissionsBySubject reflects true Mon-Fri per-subject lesson counts instead of identical denominators',
      () {
        final monday = DateTime(2026, 11, 16);
        final referenceLessons = <Lesson>[
          _makeLesson(
            uid: 'ref-ofo-mon',
            start: DateTime(monday.year, monday.month, monday.day, 8, 0),
            subjectName: 'Osztályfőnöki',
            lessonNumber: 1,
          ),
          _makeLesson(
            uid: 'ref-pe-mon',
            start: DateTime(monday.year, monday.month, monday.day, 9, 0),
            subjectName: 'Testnevelés',
            lessonNumber: 2,
          ),
          _makeLesson(
            uid: 'ref-mat-tue',
            start: DateTime(monday.year, monday.month, monday.day + 1, 8, 0),
            subjectName: 'Matematika',
            lessonNumber: 1,
          ),
          _makeLesson(
            uid: 'ref-pe-wed',
            start: DateTime(monday.year, monday.month, monday.day + 2, 10, 0),
            subjectName: 'Testnevelés',
            lessonNumber: 3,
          ),
          _makeLesson(
            uid: 'ref-mat-thu',
            start: DateTime(monday.year, monday.month, monday.day + 3, 8, 0),
            subjectName: 'Matematika',
            lessonNumber: 1,
          ),
          _makeLesson(
            uid: 'ref-pe-fri',
            start: DateTime(monday.year, monday.month, monday.day + 4, 11, 0),
            subjectName: 'Testnevelés',
            lessonNumber: 4,
          ),
        ];

        final groups = groupOmissionsBySubject(
          [
            _makeOmission(
              uid: 'om-ofo-1',
              subjectName: 'Osztályfőnöki',
              date: DateTime(2026, 11, 16, 8, 0),
              state: OmissionState.excused,
              classNo: 1,
            ),
            _makeOmission(
              uid: 'om-pe-1',
              subjectName: 'Testnevelés',
              date: DateTime(2026, 11, 16, 9, 0),
              state: OmissionState.excused,
              classNo: 2,
            ),
          ],
          referenceLessons: referenceLessons,
          referenceDate: DateTime(2026, 11, 23),
        );

        final ofo = groups.firstWhere((g) => g.subjectName == 'Osztályfőnöki');
        final pe = groups.firstWhere((g) => g.subjectName == 'Testnevelés');
        expect(ofo.totalHeldLessons, lessThan(pe.totalHeldLessons));
        expect(pe.totalHeldLessons, greaterThanOrEqualTo(ofo.totalHeldLessons * 2));
      },
    );

    test(
      'NotificationCategoryConfig supports per-grade templates (1..5) with default fallback',
      () {
        final cfg = NotificationCategoryConfig.defaultsFor(
          KretaNotificationCategory.newGrade,
        ).withGradeTemplate(
          5,
          const GradeNotificationTemplate(
            titleTemplate: 'Jeles: {subject}',
            bodyTemplate: 'Szuper {grade} jegy ({teacher})',
          ),
        );

        expect(cfg.titleTemplateForGrade(5), 'Jeles: {subject}');
        expect(cfg.bodyTemplateForGrade(5), 'Szuper {grade} jegy ({teacher})');
        expect(cfg.titleTemplateForGrade(3), KretaNotificationCategory.newGrade.defaultTitle);
        expect(cfg.bodyTemplateForGrade(3), KretaNotificationCategory.newGrade.defaultBody);
        expect(cfg.hasCustomGradeTemplate(5), isTrue);
        expect(cfg.hasCustomGradeTemplate(2), isFalse);
      },
    );

    test(
      'computeSheetDownwardDampedOffset applies progressive resistance without early snap cliff',
      () {
        expect(computeSheetDownwardDampedOffset(0), 0.0);
        final d1 = computeSheetDownwardDampedOffset(100);
        final d2 = computeSheetDownwardDampedOffset(400);
        final d3 = computeSheetDownwardDampedOffset(700);
        expect(d1, inInclusiveRange(50.0, 90.0));
        expect(d2, greaterThan(d1));
        expect(d3, greaterThan(d2));
        expect(d3 - d2, lessThan(d2 - d1));
      },
    );

    test(
      'MinimalistTokens keeps modern rounded corners and Liquid Glass while compacting spacing',
      () {
        const normal = UserProfilePrefs();
        final minimal = normal.withMinimalistMode(true);
        final normalTok = MinimalistTokens.of(normal);
        final minimalTok = MinimalistTokens.of(minimal);

        expect(normal.modalCloseMode, ModalCloseButtonMode.onlyX);
        expect(minimalTok.enabled, isTrue);
        expect(minimalTok.radiusValue, greaterThanOrEqualTo(18.0));
        expect(minimalTok.tilePadding.vertical, lessThan(normalTok.tilePadding.vertical));
        expect(minimalTok.cardGap, lessThan(normalTok.cardGap));
      },
    );

    testWidgets(
      'PopupTopCloseButton renders centered close icon and NotificationsSettingsScreen exposes per-grade chips and top live preview',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: PopupTopCloseButton(onTap: () {}),
              ),
            ),
          ),
        );
        final btnRect = tester.getRect(find.byType(PopupTopCloseButton));
        final iconRect = tester.getRect(find.byIcon(Icons.close_rounded));
        expect(
          (btnRect.center.dx - iconRect.center.dx).abs(),
          lessThanOrEqualTo(0.5),
        );
        expect(
          (btnRect.center.dy - iconRect.center.dy).abs(),
          lessThanOrEqualTo(0.5),
        );

        SharedPreferences.setMockInitialValues({});
        const channel = MethodChannel('test_notif_v32_chan');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => true);
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final service = KretaNotificationService(channel: channel);
        const prefs = UserProfilePrefs();
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: NotificationsSettingsScreen(
              prefs: prefs,
              notificationService: service,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('notification-preview-newGrade')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('notification-grade-tab-5')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('notification-grade-tab-1')),
          findsOneWidget,
        );
        final titleField = find.byKey(
          const ValueKey<String>('notification-title-newGrade'),
        );
        final bodyField = find.byKey(
          const ValueKey<String>('notification-body-newGrade'),
        );
        expect(titleField, findsOneWidget);
        expect(bodyField, findsOneWidget);

        // Select grade 1, tap a quick preset & test multi-subject live Hungarian preview
        final verticalScroll = find.byType(Scrollable).first;
        final gradeTab1 = find.byKey(
          const ValueKey<String>('notification-grade-tab-1'),
        );
        await tester.ensureVisible(gradeTab1);
        await tester.tap(gradeTab1);
        await tester.pumpAndSettle();
        final presetBadBoy = find.byKey(
          const ValueKey<String>('notification-preset-newGrade-bad boy'),
        );
        await tester.scrollUntilVisible(
          presetBadBoy,
          160,
          scrollable: verticalScroll,
        );
        await tester.ensureVisible(presetBadBoy);
        await tester.pumpAndSettle();
        await tester.tap(presetBadBoy);
        await tester.pumpAndSettle();

        final previewCard = find.byKey(
          const ValueKey<String>('notification-preview-newGrade'),
        );
        await tester.scrollUntilVisible(
          previewCard,
          -160,
          scrollable: verticalScroll,
        );
        await tester.ensureVisible(previewCard);
        await tester.pumpAndSettle();
        expect(find.text('Bad boy voltál Történelemből'), findsOneWidget);

        final mathChip = find.byKey(
          const ValueKey<String>(
            'notification-preview-subject-newGrade-Matematika',
          ),
        );
        await tester.ensureVisible(mathChip);
        await tester.tap(mathChip);
        await tester.pumpAndSettle();
        await tester.ensureVisible(previewCard);
        await tester.pumpAndSettle();

        expect(find.text('Bad boy voltál Matematikából'), findsOneWidget);
      },
    );
  });

  group('Tanév rendje v2: School Discovery, Smart Parsing & Merged UI', () {
    Student buildSchoolStudent({
      required String code,
      required String name,
      List<Map<String, dynamic>> modules = const [],
    }) =>
        Student.fromJson({
          'Uid': 'stu-$code',
          'Nev': 'Teszt Diák',
          'Cimek': ['Budapest'],
          'Bankszamla': {
            'BankszamlaSzam': null,
            'IsReadOnly': false,
            'BankszamlaTulajdonosNeve': null,
            'BankszamlaTulajdonosTipusId': null,
          },
          'SzuletesiEv': 2008,
          'SzuletesiHonap': 5,
          'SzuletesiNap': 12,
          'EmailCim': 'diak@example.com',
          'Telefonszam': '+36301234567',
          'TanevUid': 'tanev-1',
          'Gondviselok': [],
          'IntezmenyAzonosito': code,
          'IntezmenyNev': name,
          'Intezmeny': {
            'Uid': 'inst-$code',
            'RovidNev': 'TS',
            'TestreszabasBeallitasok': {
              'ErtekelesekMegjelenitesenekKesleltetesenekMerteke': 0,
              'IsOsztalyAtlagMegjeleniteseEllenorzoben': true,
              'IsTanorakTemajaMegtekinthetoEllenorzoben': true,
              'KovetkezoTelepitesDatuma': '2026-12-01',
            },
            'Rendszermodulok': modules,
          },
        });

    test(
      'Parses Hungarian HTML tables, lists, Roman numeral months, date ranges, and .ics calendars as school events',
      () {
        const html = '''
          <html><body>
            <table>
              <tr><td>2026. XI. 14–15.</td><td>Neumann Napok &amp; Projekthét</td></tr>
              <tr><td>2026.12.04.</td><td>Nyílt nap</td></tr>
            </table>
            <ul>
              <li>2027. február 12.: Szalagavató ünnepség</li>
            </ul>
            <p>Őszi szünet: 2026. október 24. – november 1.</p>
          </body></html>
        ''';
        final parsed = SchoolYearScheduleService.parseScheduleFromHtml(html, 2026);
        final neumann = parsed.firstWhere((e) => e.title.contains('Neumann'));
        expect(neumann.startDate, DateTime(2026, 11, 14));
        expect(neumann.endDate, DateTime(2026, 11, 15));
        expect(neumann.effectiveSource, SchoolYearEventSource.school);

        final openDay = parsed.firstWhere((e) => e.title.contains('Nyílt nap'));
        expect(openDay.startDate, DateTime(2026, 12, 4));
        expect(openDay.isSchoolSpecific, isTrue);

        final szalagavato =
            parsed.firstWhere((e) => e.title.contains('Szalagavató'));
        expect(szalagavato.startDate, DateTime(2027, 2, 12));

        const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
DTSTART;VALUE=DATE:20261125
DTEND;VALUE=DATE:20261127
SUMMARY:Iskolai Diáknap és Sportnap
DESCRIPTION:Közös programok a tornateremben
END:VEVENT
END:VCALENDAR
''';
        final icsEvents =
            SchoolYearScheduleService.parseScheduleFromIcs(ics, 2026);
        expect(icsEvents.length, 1);
        expect(icsEvents.first.title, 'Iskolai Diáknap és Sportnap');
        expect(icsEvents.first.startDate, DateTime(2026, 11, 25));
        expect(icsEvents.first.endDate, DateTime(2026, 11, 26));
        expect(icsEvents.first.effectiveSource, SchoolYearEventSource.school);
      },
    );

    test(
      'Auto-discovers school website via DuckDuckGo fallback, follows munkaterv links & handles PDF links gracefully',
      () async {
        SharedPreferences.setMockInitialValues({});
        final student = buildSchoolStudent(
          code: 'teszt-gimi',
          name: 'Minta Városi Gimnázium',
        );

        final client = MockClient((req) async {
          final url = req.url.toString();
          if (url.contains('instituteSelector')) {
            return http.Response('[]', 200);
          }
          if (url.contains('html.duckduckgo.com')) {
            return http.Response(
              '<a href="https://duckduckgo.com/l/?uddg=https%3A%2F%2Fmintagimi.hu">Minta</a>',
              200,
            );
          }
          if (url == 'https://mintagimi.hu') {
            return http.Response(
              '<nav><a href="/munkaterv-2026">Éves Munkaterv és Tanév rendje</a></nav>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          if (url == 'https://mintagimi.hu/munkaterv-2026') {
            return http.Response(
              '<html><body>'
              '<a href="/files/tanev-rendje-2026.pdf">Tanév rendje PDF letöltése</a>'
              '<ul><li>2026. november 28.: Szülői értekezlet</li></ul>'
              '</body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          if (url == 'https://mintagimi.hu/files/tanev-rendje-2026.pdf') {
            return http.Response.bytes(
              utf8.encode('%PDF-1.4\n(2026. december 5. Adventi vásár) Tj\n'),
              200,
              headers: {'content-type': 'application/pdf'},
            );
          }
          return http.Response('Not found', 404);
        });

        final service = SchoolYearScheduleService(
          httpClient: client,
          nowProvider: () => DateTime(2026, 11, 20),
        );

        final fetched = await service.fetchSchedule(
          student: student,
          instituteCode: 'teszt-gimi',
        );
        expect(fetched.pdfUrl, 'https://mintagimi.hu/files/tanev-rendje-2026.pdf');
        expect(
          fetched.events.any((e) =>
              e.title.contains('Adventi') &&
              e.effectiveSource == SchoolYearEventSource.school),
          isTrue,
        );
        expect(
          fetched.events.any((e) =>
              e.effectiveSource == SchoolYearEventSource.national &&
              e.type == SchoolYearEventType.schoolBreak),
          isTrue,
        );
      },
    );

    testWidgets(
      'SchoolYearScheduleScreen renders merged timeline filters, PDF banner, bottom source card & custom URL override',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final student = buildSchoolStudent(
          code: 'demo-gimi',
          name: 'Teszt Neumann Gimnázium',
        );

        final client = MockClient((req) async {
          final url = req.url.toString();
          if (url.contains('instituteSelector')) {
            return http.Response(
              jsonEncode([
                {'instituteCode': 'demo-gimi', 'website': 'https://tesztgimi.hu'},
              ]),
              200,
            );
          }
          if (url == 'https://tesztgimi.hu') {
            return http.Response(
              '<html><body>'
              '<a href="/tanev.pdf">Hivatalos Tanév rendje PDF</a>'
              '<ul>'
              '<li>2026. december 5.: Mikulás és Pályaorientációs nap</li>'
              '<li>2027. február 14.: Szalagavató ünnepség</li>'
              '</ul>'
              '</body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          if (url == 'https://tesztgimi.hu/tanev.pdf') {
            return http.Response('binary', 200, headers: {'content-type': 'application/pdf'});
          }
          if (url == 'https://custom-iskola.hu/programok') {
            return http.Response(
              '<html><body><ul><li>2026. december 9.: Egyedi Suliprogram</li></ul></body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          return http.Response('', 404);
        });

        final service = SchoolYearScheduleService(
          httpClient: client,
          nowProvider: () => DateTime(2026, 11, 20),
        );

        const prefs = UserProfilePrefs();
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: SchoolYearScheduleScreen(
              student: student,
              instituteCode: 'demo-gimi',
              prefs: prefs,
              scheduleService: service,
              clock: () => DateTime(2026, 11, 20),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey<String>('school-year-filter-all')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('school-year-filter-school')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('school-year-filter-national')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('school-year-open-pdf-btn')), findsOneWidget);

        // Filter to Iskolai programok only
        await tester.tap(find.byKey(const ValueKey<String>('school-year-filter-school')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Pályaorientációs nap'), findsWidgets);
        expect(find.text('Iskolai program'), findsWidgets);

        // Scroll to bottom source card and open manual URL override sheet
        final sourceCard = find.byKey(const ValueKey<String>('school-year-source-card'));
        final listScroll = find
            .descendant(
              of: find.byKey(const ValueKey<String>('school-year-subtab-swipe')),
              matching: find.byType(Scrollable),
            )
            .last;
        await tester.scrollUntilVisible(sourceCard, 300, scrollable: listScroll);
        expect(sourceCard, findsOneWidget);
        expect(find.text('https://tesztgimi.hu'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey<String>('school-year-bottom-url-btn')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey<String>('school-year-custom-url-input')),
          'https://custom-iskola.hu/programok',
        );
        await tester.tap(find.byKey(const ValueKey<String>('school-year-save-url-btn')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Egyedi Suliprogram'), findsWidgets);
        expect(await service.loadCustomUrlOverride('demo-gimi'), 'https://custom-iskola.hu/programok');
      },
    );

    test('HungarianNotificationLinguistics builds idiomatic Hungarian grade sentences & elative subjects', () {
      expect(
        HungarianNotificationLinguistics.formatSubjectElative('Matematika'),
        'Matematikából',
      );
      expect(
        HungarianNotificationLinguistics.formatSubjectElative('Fizika'),
        'Fizikából',
      );
      expect(
        HungarianNotificationLinguistics.formatSubjectElative('Történelem'),
        'Történelemből',
      );
      expect(
        HungarianNotificationLinguistics.formatSubjectElative('Testnevelés'),
        'Testnevelésből',
      );
      expect(
        HungarianNotificationLinguistics.formatSubjectElative('Hálózatok I.'),
        'Hálózatokból',
      );
      expect(
        HungarianNotificationLinguistics.formatSubjectElative('Földrajz'),
        'Földrajzból',
      );

      expect(
        HungarianNotificationLinguistics.buildGradeNotificationBody(
          labelOrTemplate: 'bad boy',
          subjectName: 'Történelem',
          gradeValue: 1,
        ),
        'Bad boy voltál Történelemből',
      );
      expect(
        HungarianNotificationLinguistics.buildGradeNotificationBody(
          labelOrTemplate: 'király',
          subjectName: 'Matematika',
          gradeValue: 5,
        ),
        'Király voltál Matematikából!',
      );
      expect(
        HungarianNotificationLinguistics.buildGradeNotificationBody(
          labelOrTemplate: 'karó',
          subjectName: 'Történelem',
          gradeValue: 1,
        ),
        'Karót kaptál Történelemből',
      );
      expect(
        HungarianNotificationLinguistics.buildGradeNotificationBody(
          labelOrTemplate: 'ötös',
          subjectName: 'Matematika',
          gradeValue: 5,
        ),
        'Ötöst kaptál Matematikából',
      );
      expect(
        HungarianNotificationLinguistics.buildGradeNotificationBody(
          labelOrTemplate: 'ez nem jött össze',
          subjectName: 'Történelem',
          gradeValue: 1,
        ),
        'Ez nem jött össze Történelemből',
      );
      expect(
        HungarianNotificationLinguistics.buildGradeNotificationBody(
          labelOrTemplate: 'főztem',
          subjectName: 'Történelem',
          gradeValue: 5,
        ),
        'Történelem: főztem',
      );
      expect(
        HungarianNotificationLinguistics.buildGradeNotificationBody(
          labelOrTemplate: 'cooked vagyok',
          subjectName: 'Történelem',
          gradeValue: 1,
        ),
        'Történelem: cooked vagyok',
      );
    });

    test('SchoolYearScheduleService classifies 7 categories, filters noise, persists toggles & countdown pin', () async {
      SharedPreferences.setMockInitialValues({});
      final svc = SchoolYearScheduleService();

      expect(
        SchoolYearScheduleService.isNoiseOrBoilerplateTitle('Tovább olvasom'),
        isTrue,
      );
      expect(
        SchoolYearScheduleService.isNoiseOrBoilerplateTitle('Adatvédelmi tájékoztató'),
        isTrue,
      );
      expect(
        SchoolYearScheduleService.classifyEventCategory(
          title: 'Őszi szünet',
          subtitle: 'Tavaszi/őszi szünet',
          legacyType: SchoolYearEventType.schoolBreak,
        ),
        SchoolYearEventCategory.szunetek,
      );
      expect(
        SchoolYearScheduleService.classifyEventCategory(
          title: 'Szombati munkanap-áthelyezés',
          subtitle: 'ledolgozás',
          legacyType: SchoolYearEventType.workingSaturday,
        ),
        SchoolYearEventCategory.munkanapAthelyezesek,
      );
      expect(
        SchoolYearScheduleService.classifyEventCategory(
          title: 'Szóbeli érettségi vizsga',
          subtitle: 'Vizsgaidőszak',
          legacyType: SchoolYearEventType.specialDay,
        ),
        SchoolYearEventCategory.vizsgakErettsegi,
      );

      await svc.saveHiddenCategories(
        'demo-gimi',
        {SchoolYearEventCategory.szuloiFogadoora},
      );
      final loadedHidden = await svc.loadHiddenCategories('demo-gimi');
      expect(loadedHidden, {SchoolYearEventCategory.szuloiFogadoora});

      final first = SchoolYearEvent(
        id: 'ev-1',
        title: 'Közelebbi',
        description: '',
        startDate: DateTime(2026, 12, 1),
        endDate: DateTime(2026, 12, 1),
        type: SchoolYearEventType.specialDay,
      );
      final second = SchoolYearEvent(
        id: 'ev-2',
        title: 'Kiválasztott távolabbi',
        description: '',
        startDate: DateTime(2027, 3, 15),
        endDate: DateTime(2027, 3, 15),
        type: SchoolYearEventType.schoolBreak,
      );
      final schedule = SchoolYearSchedule(
        schoolYearLabel: '2026/2027',
        sourceLabel: 'Teszt',
        fetchedAt: DateTime(2026, 11, 15),
        events: [first, second],
      );
      await svc.savePinnedCountdownEventId('demo-gimi', 'ev-2');
      expect(await svc.loadPinnedCountdownEventId('demo-gimi'), 'ev-2');

      final pinned = svc.resolveCountdownEvent(
        schedule,
        DateTime(2026, 11, 15),
        pinnedEventId: 'ev-2',
      );
      expect(pinned?.id, 'ev-2');
    });
  });
}
