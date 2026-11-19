import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:tinta_naplo/main.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/services/wear_sync_service.dart';
import 'package:tinta_naplo/widgets/expandable_profile_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

StoredSession _sampleSession() {
  return StoredSession(
    accessToken: 'access_tok_123',
    refreshToken: 'refresh_tok_456',
    idToken: 'id_tok_789',
    instituteCode: 'klik035277001',
    userName: '71234567890',
    expiresAt: DateTime.now().add(const Duration(minutes: 30)),
  );
}

Student _sampleStudent() {
  return Student(
    uid: 'student_uid_1',
    name: 'Kovács Milán',
    addressDataList: const ['Budapest'],
    bankAccount: const BankAccount(
      accountNumber: null,
      isReadOnly: true,
      ownerName: null,
      ownerType: null,
    ),
    birthdate: DateTime(2008, 5, 12),
    emailAddress: 'milan@example.com',
    phoneNumber: '+36301234567',
    schoolYearUID: '2026',
    guardianList: const [],
    instituteCode: 'klik035277001',
    instituteName: 'Fazekas Mihály Gimnázium',
    institution: Institution(
      uid: 'inst_1',
      shortName: 'Fazekas',
      systemModuleList: const [],
      customizationSettings: const CustomizationSettings(
        delayForNotifications: 0,
        isClassAverageVisible: true,
        isLessonsThemeVisible: true,
        nextServerDeployAsString: '',
      ),
    ),
  );
}

class _FakeTokenStorage extends TokenStorageService {
  final StoredSession? sessionToLoad;
  const _FakeTokenStorage({this.sessionToLoad});

  @override
  Future<StoredSession?> loadSession() async => sessionToLoad;

  @override
  Future<UserProfilePrefs> loadProfilePrefs() async =>
      const UserProfilePrefs();
}

class _FakeKretaClient extends KretaClient {
  final DashboardData cached;
  _FakeKretaClient({required super.storage, required this.cached});

  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async =>
      cached;

  @override
  Future<DashboardData> fetchDashboardData(
    StoredSession initialSession, {
    DateTime? date,
  }) async =>
      cached;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WearSyncService serializes session + student metadata and parses status', () async {
    const channel = MethodChannel('test.wear.sync');
    final service = WearSyncService(channel: channel);
    final recordedCalls = <MethodCall>[];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      recordedCalls.add(call);
      switch (call.method) {
        case 'getWearConnectionStatus':
          return {
            'isConnected': true,
            'primaryNodeName': 'Galaxy Watch6',
            'nodes': [
              {'id': 'n1', 'displayName': 'Galaxy Watch6', 'isNearby': true},
            ],
            'lastSyncedAtMs': 1700000000000,
          };
        case 'pushSessionToWatch':
          return true;
        case 'consumePendingWatchAuthRequest':
          return true;
        default:
          return true;
      }
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    bool authRequested = false;
    service.initialize(onWatchAuthRequested: () => authRequested = true);

    final status = await service.getConnectionStatus();
    expect(status.isConnected, isTrue);
    expect(status.resolvedDeviceName, 'Galaxy Watch6');
    expect(status.lastSyncedAt, isNotNull);

    final pushed = await service.syncSessionToWatch(
      session: _sampleSession(),
      student: _sampleStudent(),
      forceSync: true,
    );
    expect(pushed, isTrue);
    final pushCall = recordedCalls.last;
    expect(pushCall.method, 'pushSessionToWatch');
    final args = pushCall.arguments as Map<Object?, Object?>;
    expect(args['refreshToken'], 'refresh_tok_456');
    expect(args['accessToken'], 'access_tok_123');
    expect(args['instituteCode'], 'klik035277001');
    expect(args['studentName'], 'Kovács Milán');
    expect(args['instituteName'], 'Fazekas Mihály Gimnázium');
    expect(args['forceSync'], isTrue);

    expect(await service.consumePendingWatchAuthRequest(), isTrue);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('onWatchAuthRequested')),
      (_) {},
    );
    expect(authRequested, isTrue);
  });

  testWidgets('Profile sheet shows Szinkronizálás órával only when a Wear watch is connected',
      (tester) async {
    const channel = MethodChannel('test.profile.wear');
    final service = WearSyncService(channel: channel);
    var connected = false;
    Map<Object?, Object?>? pushedArgs;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWearConnectionStatus') {
        return {
          'isConnected': connected,
          'primaryNodeName': connected ? 'Galaxy Watch6' : null,
          'nodes': connected
              ? [
                  {'id': 'n1', 'displayName': 'Galaxy Watch6', 'isNearby': true},
                ]
              : <Map<String, Object?>>[],
        };
      }
      if (call.method == 'pushSessionToWatch') {
        pushedArgs = call.arguments as Map<Object?, Object?>?;
        return true;
      }
      return true;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> pumpHost(WidgetTester t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showStreamlinedProfileSheet(
                    context: ctx,
                    student: _sampleStudent(),
                    session: _sampleSession(),
                    wearSyncService: service,
                    prefs: const UserProfilePrefs(),
                    onPrefsChanged: (_) {},
                    onOpenFullSettings: () {},
                  );
                },
                child: const Text('OpenProfile'),
              ),
            ),
          ),
        ),
      );
    }

    // 1. Disconnected -> hidden
    connected = false;
    await pumpHost(tester);
    await tester.tap(find.text('OpenProfile'));
    await tester.pumpAndSettle();
    expect(find.text('Szinkronizálás órával'), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 2. Connected -> shows watch name + Szinkronizálás órával button and pushes on tap
    connected = true;
    await tester.tap(find.text('OpenProfile'));
    await tester.pumpAndSettle();
    expect(find.text('Galaxy Watch6'), findsOneWidget);
    expect(find.text('Szinkronizálás órával'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('profile-wear-sync-button')));
    await tester.pumpAndSettle();
    expect(pushedArgs, isNotNull);
    expect(pushedArgs!['refreshToken'], 'refresh_tok_456');
    expect(pushedArgs!['instituteCode'], 'klik035277001');
    expect(pushedArgs!['studentName'], 'Kovács Milán');
  });

  testWidgets('AppSettingsScreen shows Wear OS indicator and sync button inside Fiók és munkamenet',
      (tester) async {
    const channel = MethodChannel('test.settings.wear');
    final service = WearSyncService(channel: channel);
    Map<Object?, Object?>? pushedArgs;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getWearConnectionStatus') {
        return {
          'isConnected': true,
          'primaryNodeName': 'Pixel Watch 3',
          'nodes': [
            {'id': 'n1', 'displayName': 'Pixel Watch 3', 'isNearby': true},
          ],
        };
      }
      if (call.method == 'pushSessionToWatch') {
        pushedArgs = call.arguments as Map<Object?, Object?>?;
        return true;
      }
      return true;
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsScreen(
          session: _sampleSession(),
          student: _sampleStudent(),
          kretaClient: KretaClient(),
          prefs: const UserProfilePrefs(),
          onPrefsChanged: (_) {},
          onLogout: () {},
          wearSyncService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Expand "Fiók és munkamenet" accordion
    await tester.tap(find.text('Fiók és munkamenet'));
    await tester.pumpAndSettle();

    expect(find.text('Wear OS óra'), findsOneWidget);
    expect(find.text('Csatlakozva (Pixel Watch 3)'), findsOneWidget);
    expect(find.text('Szinkronizálás órával'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('settings-wear-sync-button')));
    await tester.pumpAndSettle();
    expect(pushedArgs, isNotNull);
    expect(pushedArgs!['refreshToken'], 'refresh_tok_456');
    expect(pushedArgs!['forceSync'], isTrue);
  });

  testWidgets('TintaNaploApp immediately pushes active session on watch auth request when logged in',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = _sampleSession();
    final student = _sampleStudent();
    final cached = DashboardData(
      student: student,
      todaysLessons: const [],
      allGrades: const [],
      latestGrades: const [],
      homeworks: const [],
      tests: const [],
      omissions: const [],
      messages: const [],
      activeSession: session,
    );
    final storage = _FakeTokenStorage(sessionToLoad: session);
    final client = _FakeKretaClient(storage: storage, cached: cached);

    Map<Object?, Object?>? cachedSnapshotArgs;
    Map<Object?, Object?>? pushedArgs;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WearSyncService.defaultChannel, (call) async {
      switch (call.method) {
        case 'consumePendingWatchAuthRequest':
          return true;
        case 'cacheSessionForWear':
          cachedSnapshotArgs = call.arguments as Map<Object?, Object?>?;
          return true;
        case 'pushSessionToWatch':
          pushedArgs = call.arguments as Map<Object?, Object?>?;
          return true;
        case 'getWearConnectionStatus':
          return {'isConnected': false, 'nodes': <Map<String, Object?>>[]};
        default:
          return true;
      }
    });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WearSyncService.defaultChannel, null);
    });

    await tester.pumpWidget(
      TintaNaploApp(tokenStorage: storage, kretaClient: client),
    );
    await tester.pumpAndSettle();

    expect(cachedSnapshotArgs, isNotNull);
    expect(cachedSnapshotArgs!['refreshToken'], 'refresh_tok_456');
    expect(pushedArgs, isNotNull);
    expect(pushedArgs!['refreshToken'], 'refresh_tok_456');
    expect(pushedArgs!['accessToken'], 'access_tok_123');
    expect(pushedArgs!['instituteCode'], 'klik035277001');
    expect(pushedArgs!['studentName'], 'Kovács Milán');
    expect(pushedArgs!['instituteName'], 'Fazekas Mihály Gimnázium');
    expect(pushedArgs!['forceSync'], isTrue);
  });
}
