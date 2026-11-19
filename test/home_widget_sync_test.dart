import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/developer_options_screen.dart';
import 'package:tinta_naplo/services/home_widget_sync_service.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/services/wear_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Lesson _makeLesson({
  required String uid,
  required int period,
  required String subjectName,
  required DateTime start,
  required DateTime end,
  String? room = 'Lab-3',
  String? teacher = 'Nagy Péter',
  String? substituteTeacher,
  bool cancelled = false,
}) {
  return Lesson(
    uid: uid,
    date: start.toIso8601String(),
    start: start,
    end: end,
    name: subjectName,
    lessonNumber: period,
    teacher: teacher,
    substituteTeacher: substituteTeacher,
    subject: Subject(
      uid: 'subj_$uid',
      name: subjectName,
      category: NameUidDesc(uid: 'cat', name: 'cat', description: 'cat'),
      sortIndex: period,
    ),
    roomName: room,
    type: NameUidDesc(uid: 'type', name: 'Tanóra', description: 'Tanóra'),
    state: NameUidDesc(
      uid: 'st',
      name: cancelled ? 'Elmaradt' : 'Megtartott',
      description: cancelled ? 'Elmaradt' : 'Megtartott',
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

class _FakeWearSync extends WearSyncService {
  _FakeWearSync() : super();

  @override
  Future<WearConnectionStatus> getConnectionStatus() async =>
      WearConnectionStatus.disconnected;
}

class _MockHomeWidgetBridge {
  final List<MethodCall> calls = <MethodCall>[];
  bool permissionGranted = true;
  bool canPromoteNotifications = true;
  bool openedPromotionSettings = false;
  bool pendingOpenTimetable = false;

  late final MethodChannel channel = MethodChannel(
    'hu.mlnlbrt.tintanaplo/home_widget_test_${identityHashCode(this)}',
  );

  void attach() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'syncTimetableData':
          return true;
        case 'setLiveActivityEnabled':
          final args = call.arguments as Map<Object?, Object?>;
          final enabled = args['enabled'] == true;
          return enabled ? permissionGranted : true;
        case 'refreshLiveUpdateNow':
          return true;
        case 'canPostPromotedNotifications':
          return canPromoteNotifications;
        case 'openPromotedNotificationSettings':
          openedPromotionSettings = true;
          return true;
        case 'consumePendingOpenTimetableTab':
          final res = pendingOpenTimetable;
          pendingOpenTimetable = false;
          return res;
      }
      return null;
    });
  }

  void detach() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('HomeWidgetSyncService serialization & bridge', () {
    test('serializes today and next school day lessons cleanly', () async {
      final bridge = _MockHomeWidgetBridge()..attach();
      addTearDown(bridge.detach);

      final service = HomeWidgetSyncService.forTest(bridge.channel);
      final now = DateTime(2026, 11, 18, 9, 55);
      final todayLesson = _makeLesson(
        uid: 'l_today_1',
        period: 2,
        subjectName: 'Adatbázis-kezelés',
        start: DateTime(2026, 11, 18, 9, 40),
        end: DateTime(2026, 11, 18, 10, 25),
        room: 'Lab-3',
        teacher: 'Kovács Anna',
        substituteTeacher: 'Szabó Béla',
      );
      final nextDayLesson = _makeLesson(
        uid: 'l_tomorrow_1',
        period: 1,
        subjectName: 'Matematika',
        start: DateTime(2026, 11, 19, 8, 0),
        end: DateTime(2026, 11, 19, 8, 45),
        room: '204',
        cancelled: true,
      );
      final staleYesterday = _makeLesson(
        uid: 'l_past',
        period: 1,
        subjectName: 'Történelem',
        start: DateTime(2026, 11, 17, 8, 0),
        end: DateTime(2026, 11, 17, 8, 45),
      );

      final prefs = const UserProfilePrefs(
        seedColorValue: 0xFF22C55E,
      ).withLiveActivityEnabled(true);

      final ok = await service.syncFromLessons(
        [staleYesterday, todayLesson, nextDayLesson],
        prefs: prefs,
        nowOverride: now,
      );

      expect(ok, isTrue);
      expect(bridge.calls, hasLength(1));
      expect(bridge.calls.single.method, 'syncTimetableData');

      final args = bridge.calls.single.arguments as Map<Object?, Object?>;
      expect(args['accentColorArgb'], 0xFF22C55E);
      expect(args['liveActivityEnabled'], isTrue);

      final decoded =
          jsonDecode(args['timetableJson'] as String) as Map<String, dynamic>;
      final lessons = (decoded['lessons'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      // Yesterday's lesson excluded; today's & tomorrow's lessons present
      expect(lessons, hasLength(2));
      expect(lessons[0]['period'], 2);
      expect(lessons[0]['subject'], 'Adatbázis-kezelés');
      expect(lessons[0]['room'], 'Lab-3');
      expect(lessons[0]['teacher'], 'Szabó Béla');
      expect(lessons[0]['substituted'], isTrue);
      expect(lessons[0]['cancelled'], isFalse);

      expect(lessons[1]['period'], 1);
      expect(lessons[1]['subject'], 'Matematika');
      expect(lessons[1]['cancelled'], isTrue);
    });

    test('setLiveActivityEnabled respects permission denial', () async {
      final bridge = _MockHomeWidgetBridge()
        ..permissionGranted = false
        ..attach();
      addTearDown(bridge.detach);

      final service = HomeWidgetSyncService.forTest(bridge.channel);
      final denied = await service.setLiveActivityEnabled(true);
      expect(denied, isFalse);

      bridge.permissionGranted = true;
      final granted = await service.setLiveActivityEnabled(true);
      expect(granted, isTrue);
    });
  });

  group('Developer Options Live Activity toggle & hub badge', () {
    testWidgets(
      'shows Aktív badge on hub tile and toggles + refreshes Now Bar in Demo Mode',
      (WidgetTester tester) async {
        final bridge = _MockHomeWidgetBridge()..attach();
        addTearDown(bridge.detach);
        final widgetSync = HomeWidgetSyncService.forTest(bridge.channel);

        final settingsProvider = SettingsProvider(
          storage: const TokenStorageService(),
        );
        addTearDown(settingsProvider.dispose);
        await settingsProvider.updatePrefs(
          const UserProfilePrefs().withDemoMode(true),
        );

        await tester.pumpWidget(
          AppProvidersScope(
            settings: settingsProvider,
            theme: ThemeProvider(settingsProvider),
            commute: CommuteProvider(settingsProvider),
            child: MaterialApp(
              home: Scaffold(
                body: ListenableBuilder(
                  listenable: settingsProvider,
                  builder: (context, _) => SingleChildScrollView(
                    child: DeveloperOptionsMenuList(
                      prefs: settingsProvider.prefs,
                      onPrefsChanged: (_) {},
                      wearSyncService: _FakeWearSync(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        // Wait bounded frames (AdaptiveBackgroundScaffold + TintaToast animate continuously)
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Initially Live Activity is OFF -> no 'Aktív' pill on integrations tile
        final integrationsTile = find.byKey(
          const ValueKey<String>('dev-hub-tile-integrations'),
        );
        expect(integrationsTile, findsOneWidget);
        expect(
          find.descendant(of: integrationsTile, matching: find.text('Aktív')),
          findsNothing,
        );

        // Render Integrations SubPage directly with test bridge
        await tester.pumpWidget(
          AppProvidersScope(
            settings: settingsProvider,
            theme: ThemeProvider(settingsProvider),
            commute: CommuteProvider(settingsProvider),
            child: MaterialApp(
              home: DeveloperIntegrationsSubPage(
                initialPrefs: settingsProvider.prefs,
                wearSyncService: _FakeWearSync(),
                homeWidgetSyncService: widgetSync,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Élő tevékenység (Now Bar)'), findsOneWidget);
        expect(
          find.text(
            'Aktuális óra és visszaszámláló megjelenítése a zárolási képernyőn és az állapotsoron',
          ),
          findsOneWidget,
        );
        expect(find.text('Élő értesítés frissítése most'), findsOneWidget);

        // Toggle Live Activity ON (when promotion permission is pending, prompts Settings launch)
        bridge.canPromoteNotifications = false;
        final liveSwitch = find.byKey(
          const ValueKey<String>('dev-live-activity-switch'),
        );
        await tester.tap(liveSwitch);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(settingsProvider.prefs.liveActivityEnabled, isTrue);
        expect(
          bridge.calls.map((c) => c.method),
          containsAll(<String>[
            'setLiveActivityEnabled',
            'syncTimetableData',
            'refreshLiveUpdateNow',
            'canPostPromotedNotifications',
          ]),
        );
        expect(find.text('Beállítások megnyitása'), findsOneWidget);
        await tester.tap(find.text('Beállítások megnyitása'));
        await tester.pump();
        expect(bridge.openedPromotionSettings, isTrue);
        expect(
          find.byKey(const ValueKey<String>('dev-live-activity-promotion-banner')),
          findsOneWidget,
        );

        // Tap diagnostic refresh button
        bridge.calls.clear();
        await tester.tap(
          find.byKey(const ValueKey<String>('dev-live-activity-refresh-btn')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          bridge.calls.map((c) => c.method),
          containsAll(<String>['syncTimetableData', 'refreshLiveUpdateNow']),
        );

        // Hub tile reflects 'Aktív' badge when enabled
        await tester.pumpWidget(
          AppProvidersScope(
            settings: settingsProvider,
            theme: ThemeProvider(settingsProvider),
            commute: CommuteProvider(settingsProvider),
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: DeveloperOptionsMenuList(
                    prefs: settingsProvider.prefs,
                    onPrefsChanged: (_) {},
                    wearSyncService: _FakeWearSync(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('dev-hub-tile-integrations')),
            matching: find.text('Aktív'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
