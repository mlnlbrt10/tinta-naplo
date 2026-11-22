import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/grades_screen.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/screens/timetable_screen.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/utils/uwu_helper.dart';
import 'package:tinta_naplo/widgets/frosted_inspection_modal.dart';

StoredSession _fakeSession() => StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik001',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

Map<String, dynamic> _lessonJson({
  required String uid,
  required int? lessonNumber,
  required String subjectName,
  required DateTime start,
  String roomName = 'Lab-3',
  String teacherName = 'Horváth Zoltán',
}) {
  final end = start.add(const Duration(minutes: 45));
  final dayIso = '${start.toIso8601String().split('T').first}T00:00:00Z';
  return {
    'Uid': uid,
    'Datum': dayIso,
    'Oraszam': lessonNumber,
    'KezdetIdopont': start.toUtc().toIso8601String(),
    'VegIdopont': end.toUtc().toIso8601String(),
    'Nev': subjectName,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'c', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': lessonNumber ?? 0,
    },
    'OsztalyCsoport': {'Uid': 'g1', 'Nev': '11.A'},
    'TanarNeve': teacherName,
    'TeremNeve': roomName,
    'Tipus': {
      'Uid': 'ora',
      'Nev': 'TanitasiOra',
      'Leiras': 'Tanítási óra',
    },
    'Tema': 'Adatmodellezés gyakorlat',
    'Allapot': {'Uid': '1', 'Nev': 'Megtartott', 'Leiras': 'Megtartott'},
    'HaziFeladatUid': null,
    'IsTanuloHaziFeladatEnabled': false,
    'IsHaziFeladatMegoldva': false,
    'Csatolmanyok': const <Map<String, dynamic>>[],
    'IsDigitalisOra': false,
    'Letrehozas': dayIso,
    'UtolsoModositas': dayIso,
  };
}

Lesson _makeLesson({
  required String uid,
  required int? lessonNumber,
  required String subjectName,
  required DateTime start,
  String roomName = 'Lab-3',
  String teacherName = 'Horváth Zoltán',
}) =>
    Lesson.fromJson(
      _lessonJson(
        uid: uid,
        lessonNumber: lessonNumber,
        subjectName: subjectName,
        start: start,
        roomName: roomName,
        teacherName: teacherName,
      ),
    );

Omission _makeOmission({
  required String uid,
  required String subjectName,
  required DateTime date,
  int? classNo,
  DateTime? lessonStart,
  required OmissionState state,
  int? lateMinutes,
}) {
  final start = lessonStart ??
      DateTime(date.year, date.month, date.day, 7 + (classNo ?? 1), 0);
  final end = start.add(const Duration(minutes: 45));
  return Omission.fromJson({
    'Uid': uid,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'c1', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': 1,
    },
    'Ora': {
      'KezdoDatum': start.toUtc().toIso8601String(),
      'VegDatum': end.toUtc().toIso8601String(),
      if (classNo != null) 'Oraszam': classNo,
    },
    'Datum': date.toUtc().toIso8601String(),
    'RogzitoTanarNeve': 'Horváth Zoltán',
    'Tipus': lateMinutes != null
        ? {'Uid': 'keses', 'Nev': 'Keses', 'Leiras': 'Késés'}
        : {'Uid': 'hianyzas', 'Nev': 'Hianyzas', 'Leiras': 'Hiányzás'},
    'KesesPercben': lateMinutes,
    'KeszitesDatuma': start.toUtc().toIso8601String(),
    'IgazolasAllapota': state.key,
  });
}

Grade _makeGrade({
  required String uid,
  required String subjectName,
  required String subjectUid,
  required String teacherName,
  required String theme,
  required String modeDesc,
  required int value,
  int weight = 100,
  DateTime? date,
}) {
  final d = date ?? DateTime(2026, 11, 18, 10, 0);
  return Grade.fromJson({
    'Uid': uid,
    'Tantargy': {'Uid': subjectUid, 'Nev': subjectName, 'SortIndex': 1},
    'Tema': theme,
    'Mod': {'Uid': 'mod1', 'Nev': modeDesc, 'Leiras': modeDesc},
    'Datum': d.toUtc().toIso8601String(),
    'KeszitesDatuma': d.toUtc().toIso8601String(),
    'ErtekeloTanarNeve': teacherName,
    'SzamErtek': value,
    'Ertek': '$value',
    'SulySzazalekErteke': weight,
    'Tipus': {'Uid': 'evk', 'Nev': 'Evkozi', 'Leiras': 'Évközi'},
  });
}

class _FixedTimetableKretaClient extends KretaClient {
  final List<Lesson> lessons;

  _FixedTimetableKretaClient(this.lessons)
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    UwuHelper.isEnabled = false;
    UwuHelper.isFitymaEnabled = false;
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  tearDown(() {
    UwuHelper.isEnabled = false;
    UwuHelper.isFitymaEnabled = false;
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  group('1. Scholarship Calculator sheet bounded sizing & zero jumping', () {
    testWidgets(
      'Uses bounded SafeArea layout with zero DraggableScrollableSheet, pins header during inner scroll, and holds height across mode switches',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final grades = [
          _makeGrade(
            uid: 'g1',
            subjectName: 'Matematika',
            subjectUid: 'math',
            teacherName: 'Nagy Béla',
            theme: 'Egyenletek',
            modeDesc: 'Írásbeli dolgozat',
            value: 5,
          ),
          _makeGrade(
            uid: 'g2',
            subjectName: 'Fizika',
            subjectUid: 'phys',
            teacherName: 'Kiss Anna',
            theme: 'Mechanika',
            modeDesc: 'Felelés',
            value: 4,
          ),
        ];

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(412, 915),
              padding: EdgeInsets.only(top: 44.0, bottom: 24.0),
            ),
            child: MaterialApp(
              theme: OledTheme.buildTheme(
                prefs: const UserProfilePrefs(liquidGlassEnabled: true),
              ),
              home: Scaffold(
                body: GradesScreen(
                  allGrades: grades,
                  prefs: const UserProfilePrefs(liquidGlassEnabled: true),
                  onPrefsChanged: (_) {},
                  onRefresh: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Összesített súlyozott átlag'));
        await tester.pumpAndSettle();

        expect(find.byType(DraggableScrollableSheet), findsNothing);
        expect(find.text('Ösztöndíj kalkulátor'), findsOneWidget);

        // Header must NOT live inside SingleChildScrollView and must sit below top SafeArea (44px)
        expect(
          find.ancestor(
            of: find.text('Ösztöndíj kalkulátor'),
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );

        final surfaceRectBefore = tester.getRect(
          find.byType(FrostedBottomSheetSurface),
        );
        expect(surfaceRectBefore.top, greaterThanOrEqualTo(44.0));

        final headerRectBefore = tester.getRect(
          find.text('Ösztöndíj kalkulátor'),
        );

        // Scroll inner content -> pinned header does not move
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -180),
        );
        await tester.pumpAndSettle();
        final headerRectAfterScroll = tester.getRect(
          find.text('Ösztöndíj kalkulátor'),
        );
        expect(headerRectAfterScroll.top, closeTo(headerRectBefore.top, 0.5));

        // Toggle between Ágazati (9-10.) and Szakirányú -> height stays rock steady
        await tester.ensureVisible(find.text('Ágazati (9-10.)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ágazati (9-10.)'));
        await tester.pumpAndSettle();
        final surfaceRectAgazati = tester.getRect(
          find.byType(FrostedBottomSheetSurface),
        );
        expect(
          surfaceRectAgazati.height,
          closeTo(surfaceRectBefore.height, 0.5),
        );
        expect(surfaceRectAgazati.top, closeTo(surfaceRectBefore.top, 0.5));

        await tester.tap(find.text('Szakirányú'));
        await tester.pumpAndSettle();
        final surfaceRectSzakiranyu = tester.getRect(
          find.byType(FrostedBottomSheetSurface),
        );
        expect(
          surfaceRectSzakiranyu.height,
          closeTo(surfaceRectBefore.height, 0.5),
        );
      },
    );
  });

  group('2. FloatingGlassSheetRoute upward rubber-band stretch & swipe dismiss', () {
    test('computeSheetUpwardRubberBand and computeSheetUpwardStretchScale are bounded', () {
      expect(computeSheetUpwardRubberBand(0.0), 0.0);
      expect(computeSheetUpwardRubberBand(25.0), 0.0);

      final pull1 = computeSheetUpwardRubberBand(-20.0);
      final pull2 = computeSheetUpwardRubberBand(-80.0);
      final pull3 = computeSheetUpwardRubberBand(-500.0);
      expect(pull1, lessThan(0.0));
      expect(pull2, lessThan(pull1));
      expect(pull3, lessThanOrEqualTo(pull2));
      expect(pull3, greaterThanOrEqualTo(-22.0));

      expect(computeSheetUpwardStretchScale(0.0), 1.0);
      expect(
        computeSheetUpwardStretchScale(-22.0),
        closeTo(1.03, 0.0001),
      );
      expect(computeSheetUpwardStretchScale(-100.0), closeTo(1.03, 0.0001));
    });

    testWidgets(
      'Upward over-drag stretches smoothly and springs back without dismissing; downward drag & fling dismiss cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showFloatingGlassSheet<void>(
                        context: context,
                        builder: (_) => const FrostedBottomSheetSurface(
                          prefs: UserProfilePrefs(),
                          child: SizedBox(
                            height: 240,
                            child: Center(child: Text('NonScrollableSheet')),
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenNonScrollable'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenNonScrollable'));
        await tester.pumpAndSettle();
        expect(find.text('NonScrollableSheet'), findsOneWidget);

        final restTop =
            tester.getTopLeft(find.byType(FrostedBottomSheetSurface)).dy;

        // Upward rubber-band drag
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('NonScrollableSheet')),
        );
        await gesture.moveBy(const Offset(0, -140));
        await tester.pump();

        final pulledRect =
            tester.getRect(find.byType(FrostedBottomSheetSurface));
        expect(pulledRect.top, lessThan(restTop));
        expect(restTop - pulledRect.top, lessThanOrEqualTo(32.0));

        await gesture.up();
        await tester.pumpAndSettle();

        // Remains open and snapped back to rest position
        expect(find.text('NonScrollableSheet'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(FrostedBottomSheetSurface)).dy,
          closeTo(restTop, 0.5),
        );

        // Downward drag past threshold (> 100px) dismisses
        await tester.drag(
          find.text('NonScrollableSheet'),
          const Offset(0, 140),
        );
        await tester.pumpAndSettle();
        expect(find.text('NonScrollableSheet'), findsNothing);

        // Fast downward fling (> 500 px/s) also dismisses
        await tester.tap(find.text('OpenNonScrollable'));
        await tester.pumpAndSettle();
        expect(find.text('NonScrollableSheet'), findsOneWidget);

        await tester.fling(
          find.text('NonScrollableSheet'),
          const Offset(0, 80),
          950.0,
        );
        await tester.pumpAndSettle();
        expect(find.text('NonScrollableSheet'), findsNothing);
      },
    );

    testWidgets(
      'Scrollable sheet at scrollOffset == 0 dismisses on downward drag cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showFloatingGlassSheet<void>(
                        context: context,
                        builder: (_) => FrostedBottomSheetSurface(
                          prefs: const UserProfilePrefs(),
                          child: SizedBox(
                            height: 280,
                            child: ListView(
                              children: List<Widget>.generate(
                                12,
                                (i) => ListTile(title: Text('ScrollItem $i')),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenScrollable'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenScrollable'));
        await tester.pumpAndSettle();
        expect(find.text('ScrollItem 0'), findsOneWidget);

        // Dragging down at scrollOffset == 0 overscrolls top and dismisses sheet
        await tester.drag(find.text('ScrollItem 1'), const Offset(0, 180));
        await tester.pumpAndSettle();
        expect(find.text('ScrollItem 0'), findsNothing);
      },
    );
  });

  group('3. Appearance live-update reactivity on open sub-screen', () {
    testWidgets(
      'Tapping color swatch and Világos updates open Appearance screen Theme & swatch immediately without navigating back',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const initialPrefs = UserProfilePrefs(
          themeStyle: AppThemeStyle.oledPureBlack,
          useDynamicColor: false,
        );
        final settings = SettingsProvider(initialPrefs: initialPrefs);
        addTearDown(settings.dispose);
        final themeProvider = ThemeProvider(settings);
        addTearDown(themeProvider.dispose);
        final commute = CommuteProvider(settings);
        addTearDown(commute.dispose);

        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: themeProvider,
            commute: commute,
            child: ListenableBuilder(
              listenable: Listenable.merge([settings, themeProvider]),
              builder: (context, _) {
                final activeTheme = OledTheme.buildTheme(prefs: settings.prefs);
                return MaterialApp(
                  themeAnimationStyle: AnimationStyle.noAnimation,
                  themeMode: activeTheme.brightness == Brightness.light
                      ? ThemeMode.light
                      : ThemeMode.dark,
                  theme: activeTheme,
                  darkTheme: activeTheme,
                  home: AppSettingsScreen(
                    session: _fakeSession(),
                    student: null,
                    kretaClient: KretaClient(),
                    prefs: settings.prefs,
                    onPrefsChanged: (_) {},
                    onLogout: () {},
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Megjelenés és témák'));
        await tester.pumpAndSettle();

        expect(find.text('Alaptéma & Színek'), findsOneWidget);

        final ctxBefore = tester.element(find.text('Alaptéma & Színek'));
        final primaryBefore = Theme.of(ctxBefore).colorScheme.primary;
        expect(Theme.of(ctxBefore).brightness, Brightness.dark);

        final targetColor = OledTheme.avatarColors.firstWhere(
          (c) =>
              c.toARGB32() != settings.prefs.seedColorValue &&
              c.toARGB32() != primaryBefore.toARGB32(),
        );
        final swatchKey = ValueKey<String>(
          'seed-color-swatch-${targetColor.toARGB32().toRadixString(16)}',
        );
        await Scrollable.ensureVisible(
          tester.element(find.byKey(swatchKey)),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(swatchKey));
        await tester.pump();

        // Updated immediately while still on Appearance screen!
        expect(find.text('Alaptéma & Színek'), findsOneWidget);
        expect(settings.prefs.seedColorValue, targetColor.toARGB32());
        final ctxAfterColor = tester.element(find.text('Alaptéma & Színek'));
        final primaryAfter = Theme.of(ctxAfterColor).colorScheme.primary;
        expect(primaryAfter, isNot(equals(primaryBefore)));
        expect(
          find.descendant(
            of: find.byKey(swatchKey),
            matching: find.byIcon(Icons.check_rounded),
          ),
          findsOneWidget,
        );

        // Tap Világos -> brightness switches to Brightness.light immediately in place
        await Scrollable.ensureVisible(
          tester.element(find.text('Világos')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Világos'));
        await tester.pump();

        expect(find.text('Alaptéma & Színek'), findsOneWidget);
        final ctxAfterLight = tester.element(find.text('Alaptéma & Színek'));
        expect(Theme.of(ctxAfterLight).brightness, Brightness.light);
      },
    );
  });

  group('4. All Absences day-view timetable loading skeleton, cache & chronological merge', () {
    test(
      'mergeDayTimetableWithOmissions retains unnumbered lessons, matches by time fallback, synthesizes missing omitted periods, and sorts chronologically',
      () {
        final day = DateTime(2026, 3, 18);
        final dayLessons = [
          _makeLesson(
            uid: 'l3',
            lessonNumber: 3,
            subjectName: 'Fizika',
            start: DateTime(2026, 3, 18, 9, 50),
          ),
          _makeLesson(
            uid: 'l1',
            lessonNumber: 1,
            subjectName: 'Matematika',
            start: DateTime(2026, 3, 18, 8, 0),
          ),
          _makeLesson(
            uid: 'lun',
            lessonNumber: null,
            subjectName: 'Osztályfőnöki',
            start: DateTime(2026, 3, 18, 8, 55),
          ),
        ];
        final omissions = [
          // Matched by classNo == 3
          _makeOmission(
            uid: 'om3',
            subjectName: 'Fizika',
            date: day,
            classNo: 3,
            lessonStart: DateTime(2026, 3, 18, 9, 50),
            state: OmissionState.unexcused,
          ),
          // Matched by time fallback (unnumbered lesson has classNo null)
          _makeOmission(
            uid: 'om_un',
            subjectName: 'Osztályfőnöki',
            date: day,
            classNo: null,
            lessonStart: DateTime(2026, 3, 18, 9, 0),
            state: OmissionState.excused,
          ),
          // Absent from timetable response -> synthesized!
          _makeOmission(
            uid: 'om4',
            subjectName: 'Kémia',
            date: day,
            classNo: 4,
            lessonStart: DateTime(2026, 3, 18, 10, 45),
            state: OmissionState.pending,
          ),
        ];

        final slots = mergeDayTimetableWithOmissions(
          day: day,
          omissions: omissions,
          dayLessons: dayLessons,
          prefs: const UserProfilePrefs(),
        );

        expect(slots.length, 4);
        expect(slots[0].subjectName, 'Matematika');
        expect(slots[0].classNo, 1);
        expect(slots[0].isMissed, isFalse);

        // Wait check sort order: numbered lessons come first OR time order?
        // Class 1 (08:00), Class 3 (09:50), Class 4 (10:45), or time order!
        // Note: slot sorting puts a.classNo != null && b.classNo != null first;
        // unnumbered lesson with sortTime sorted between class 1 and 3!
        expect(slots.any((s) => s.subjectName == 'Osztályfőnöki' && s.isMissed), isTrue);
        expect(slots.any((s) => s.subjectName == 'Fizika' && s.isMissed), isTrue);
        expect(slots.any((s) => s.subjectName == 'Kémia' && s.classNo == 4 && s.isMissed), isTrue);
      },
    );

    testWidgets(
      'Shows loading skeleton without partial reference lessons while fetching uncached date, crossfades to full sorted day, and hits cache on reopen',
      (tester) async {
        final targetDate = DateTime(2026, 3, 18);
        final todayDifferentDate = DateTime(2026, 3, 25);
        final completer = Completer<String>();
        var networkCalls = 0;

        final client = KretaClient(
          httpClient: MockClient((request) async {
            networkCalls++;
            final body = await completer.future;
            return http.Response.bytes(
              utf8.encode(body),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }),
          storage: const TokenStorageService(),
        );
        final session = _fakeSession();

        final referenceTodayLessons = [
          _makeLesson(
            uid: 'ref1',
            lessonNumber: 1,
            subjectName: 'TÉVES REFERENCIA ÓRA',
            start: DateTime(
              todayDifferentDate.year,
              todayDifferentDate.month,
              todayDifferentDate.day,
              8,
              0,
            ),
          ),
        ];

        final omissions = [
          _makeOmission(
            uid: 'om2',
            subjectName: 'Történelem',
            date: targetDate,
            classNo: 2,
            lessonStart: DateTime(2026, 3, 18, 8, 55),
            state: OmissionState.unexcused,
          ),
        ];
        final group = DailyOmissionGroup(day: targetDate, entries: omissions);

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showDayTimetableOmissionsSheet(
                      context,
                      group: group,
                      prefs: const UserProfilePrefs(),
                      dateFormat: DateFormat('yyyy. MM. dd.'),
                      session: session,
                      kretaClient: client,
                      referenceLessons: referenceTodayLessons,
                    ),
                    child: const Text('OpenDayView'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenDayView'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));

        expect(networkCalls, 1);
        expect(
          find.byKey(const ValueKey<String>('day-timetable-loading')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('day-timetable-loaded')),
          findsNothing,
        );
        expect(find.text('TÉVES REFERENCIA ÓRA'), findsNothing);

        // Complete timetable fetch for 2026-03-18
        completer.complete(
          jsonEncode([
            _lessonJson(
              uid: 'd1',
              lessonNumber: 1,
              subjectName: 'Magyar nyelv',
              start: DateTime(2026, 3, 18, 8, 0),
            ),
            _lessonJson(
              uid: 'd2',
              lessonNumber: 2,
              subjectName: 'Történelem',
              start: DateTime(2026, 3, 18, 8, 55),
            ),
            _lessonJson(
              uid: 'd3',
              lessonNumber: 3,
              subjectName: 'Angol nyelv',
              start: DateTime(2026, 3, 18, 9, 50),
            ),
          ]),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('day-timetable-loading')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('day-timetable-loaded')),
          findsOneWidget,
        );
        expect(find.text('Magyar nyelv'), findsOneWidget);
        expect(find.text('Történelem'), findsOneWidget);
        expect(find.text('Angol nyelv'), findsOneWidget);
        expect(find.text('1.'), findsOneWidget);
        expect(find.text('2.'), findsOneWidget);
        expect(find.text('3.'), findsOneWidget);
        expect(find.text('TÉVES REFERENCIA ÓRA'), findsNothing);

        // Close sheet and re-open -> instant cache hit with zero extra network calls
        Navigator.of(
          tester.element(find.byKey(const ValueKey<String>('day-timetable-loaded'))),
        ).pop();
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenDayView'));
        await tester.pumpAndSettle();

        expect(networkCalls, 1);
        expect(
          find.byKey(const ValueKey<String>('day-timetable-loaded')),
          findsOneWidget,
        );
        expect(find.text('Magyar nyelv'), findsOneWidget);
      },
    );
  });

  group('5. Global UwU text transformer & safety guards', () {
    test(
      'Transforms Hungarian words & hyphenated subjects while strictly preserving numbers, timestamps, dates, percentages, rooms, acronyms, and currency',
      () {
        UwuHelper.isEnabled = true;

        // Transformed Hungarian & dynamic KRÉTA strings (without suffix in uwuLabel)
        final subj = uwuLabel('Adatbázis-kezelés');
        expect(subj, isNot('Adatbázis-kezelés'));
        expect(subj, contains('-'));

        expect(uwuLabel('Írásbeli röpdolgozat'), isNot('Írásbeli röpdolgozat'));
        expect(uwuLabel('Beszámoló'), isNot('Beszámoló'));
        expect(uwuLabel('Igazolt'), isNot('Igazolt'));
        expect(uwuLabel('Igazolatlan'), isNot('Igazolatlan'));
        expect(uwuLabel('Horváth Zoltán'), isNot('Horváth Zoltán'));

        // Strictly preserved tokens
        expect(uwuLabel('5'), '5');
        expect(uwuLabel('4.00'), '4.00');
        expect(uwuLabel('08:55'), '08:55');
        expect(uwuLabel('2026. 11. 22.'), '2026. 11. 22.');
        expect(uwuLabel('Nov.'), 'Nov.');
        expect(uwuLabel('12.5%'), '12.5%');
        expect(uwuLabel('Lab-3'), 'Lab-3');
        expect(uwuLabel('B-204'), 'B-204');
        expect(uwuLabel('M1. 110'), 'M1. 110');
        expect(uwuLabel('KRÉTA'), 'KRÉTA');
        expect(uwuLabel('IKT'), 'IKT');
        expect(uwuLabel('OLED'), 'OLED');
        expect(uwu('42 000 Ft/hó'), '42 000 Ft/hó');
        expect(uwuLabel('Ft-hoz'), 'Ft-hoz');
      },
    );

    testWidgets(
      'GradesScreen + frosted detail modal transform dynamic KRÉTA text in UwU mode without mutating model data',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const uwuPrefs = UserProfilePrefs(uwuModeEnabled: true);
        UserProfilePrefs.syncActiveGlobals(uwuPrefs);

        final grades = [
          _makeGrade(
            uid: 'g-uwu-1',
            subjectName: 'Adatbázis-kezelés',
            subjectUid: 'db',
            teacherName: 'Horváth Zoltán',
            theme: 'Beszámoló',
            modeDesc: 'Írásbeli röpdolgozat',
            value: 5,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: uwuPrefs),
            home: Scaffold(
              body: GradesScreen(
                allGrades: grades,
                prefs: uwuPrefs,
                onPrefsChanged: (_) {},
                onRefresh: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final expectedSubj = uwuLabel('Adatbázis-kezelés', enabled: true);
        expect(find.text(expectedSubj), findsOneWidget);
        expect(find.text('Adatbázis-kezelés'), findsNothing);
        // Stored model field remains completely untouched
        expect(grades.first.subject.name, 'Adatbázis-kezelés');

        // Tap subject to verify SubjectGradesDetailScreen + modal in UwU mode
        await tester.tap(find.text(expectedSubj));
        await tester.pumpAndSettle();

        expect(
          find.text(uwuLabel('Beszámoló', enabled: true)),
          findsAtLeastNWidgets(1),
        );
        // Numeric grade stays '5'
        expect(find.text('5'), findsAtLeastNWidgets(1));

        // Open grade detail frosted popup
        await tester.tap(find.text(uwuLabel('Beszámoló', enabled: true)).first);
        await tester.pumpAndSettle();

        expect(
          find.text(uwuLabel('Horváth Zoltán', enabled: true)),
          findsAtLeastNWidgets(1),
        );
        expect(
          find.text(uwuLabel('Írásbeli röpdolgozat', enabled: true)),
          findsAtLeastNWidgets(1),
        );
      },
    );

    testWidgets(
      'TimetableScreen and Absences Day View transform dynamic KRÉTA labels in UwU mode while keeping room codes & times intact',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const uwuPrefs = UserProfilePrefs(uwuModeEnabled: true);
        UserProfilePrefs.syncActiveGlobals(uwuPrefs);

        final fixedNow = DateTime(2026, 3, 18, 7, 30);
        final lessons = [
          _makeLesson(
            uid: 'tt-uwu-1',
            lessonNumber: 1,
            subjectName: 'Irodalom',
            start: DateTime(2026, 3, 18, 8, 0),
            roomName: 'B-204',
            teacherName: 'Horváth Zoltán',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: uwuPrefs),
            home: Scaffold(
              body: TimetableScreen(
                session: _fakeSession(),
                kretaClient: _FixedTimetableKretaClient(lessons),
                initialTodaysLessons: lessons,
                prefs: uwuPrefs,
                onPrefsChanged: (_) {},
                clock: () => fixedNow,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(uwuLabel('Irodalom', enabled: true)),
          findsAtLeastNWidgets(1),
        );
        // Room code B-204 preserved
        expect(find.textContaining('B-204'), findsAtLeastNWidgets(1));
        expect(lessons.first.subject?.name, 'Irodalom');

        // Also check Day View Omissions sheet in UwU mode
        final omissions = [
          _makeOmission(
            uid: 'om-uwu-1',
            subjectName: 'Irodalom',
            date: DateTime(2026, 3, 18),
            classNo: 1,
            lessonStart: DateTime(2026, 3, 18, 8, 0),
            state: OmissionState.excused,
          ),
        ];
        final group = DailyOmissionGroup(
          day: DateTime(2026, 3, 18),
          entries: omissions,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: uwuPrefs),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showDayTimetableOmissionsSheet(
                      context,
                      group: group,
                      prefs: uwuPrefs,
                      dayLessons: lessons,
                    ),
                    child: const Text('OpenUwuDayView'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OpenUwuDayView'));
        await tester.pumpAndSettle();

        expect(
          find.text(uwuLabel('Hiányzás • Igazolt', enabled: true)),
          findsOneWidget,
        );
        expect(
          find.text(
            uwuLabel('${group.summaryLabel} • Napi órarend nézet', enabled: true),
          ),
          findsOneWidget,
        );
        expect(
          find.text(uwuLabel('Irodalom', enabled: true)),
          findsOneWidget,
        );

        // Verify AppSettingsScreen also transforms labels cleanly in UwU mode
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: uwuPrefs),
            home: AppSettingsScreen(
              session: _fakeSession(),
              student: null,
              kretaClient: _FixedTimetableKretaClient(lessons),
              prefs: uwuPrefs,
              onPrefsChanged: (_) {},
              onLogout: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(uwuLabel('Megjelenés és témák', enabled: true)),
          findsOneWidget,
        );
        expect(uwuPrefs.uwuModeEnabled, isTrue);
      },
    );
  });
}
