import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/core/kreta_auth_config.dart';
import 'package:tinta_naplo/screens/developer_options_screen.dart';
import 'package:tinta_naplo/screens/home_screen.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/custom_skin_config.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/widgets/period_countdown_badge.dart';

StoredSession _makeSession({
  String accessToken = 'acc_1',
  String refreshToken = 'ref_1',
  String instituteCode = 'klik035277001',
  DateTime? expiresAt,
}) {
  return StoredSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    idToken: 'id_1',
    instituteCode: instituteCode,
    userName: '71234567890',
    expiresAt: expiresAt ?? DateTime.now().add(const Duration(hours: 1)),
  );
}

class _InvalidGrantKretaClient extends KretaClient {
  final DashboardData cached;
  bool shouldThrowInvalidGrant = true;

  _InvalidGrantKretaClient({
    required this.cached,
  });

  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async =>
      cached;

  @override
  Future<DashboardData> fetchDashboardData(
    StoredSession session, {
    DateTime? date,
  }) async {
    if (shouldThrowInvalidGrant) {
      throw const VerifiedInvalidGrantException(
        httpStatusCode: 400,
        responseBody: '{"error":"invalid_grant"}',
        caller: 'test',
      );
    }
    return cached.copyWith(activeSession: session);
  }
}

extension on DashboardData {
  DashboardData copyWith({StoredSession? activeSession}) => DashboardData(
        student: student,
        todaysLessons: todaysLessons,
        allGrades: allGrades,
        latestGrades: latestGrades,
        homeworks: homeworks,
        tests: tests,
        omissions: omissions,
        messages: messages,
        activeSession: activeSession ?? this.activeSession,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Duration origInvalidGrantDelay;
  late List<Duration> origTransientDelays;
  late List<Duration> origKeyStoreDelays;

  setUp(() {
    origInvalidGrantDelay = TokenStorageService.invalidGrantRetryDelay;
    origTransientDelays = TokenStorageService.transientRefreshRetryDelays;
    origKeyStoreDelays = TokenStorageService.keyStoreRetryDelays;

    TokenStorageService.invalidGrantRetryDelay = Duration.zero;
    TokenStorageService.transientRefreshRetryDelays = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ];
    TokenStorageService.keyStoreRetryDelays = const [Duration.zero];
    TokenStorageService.externalSessionFallbackLoader = null;
    TokenStorageService.clearReauthRequired();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() async {
    TokenStorageService.invalidGrantRetryDelay = origInvalidGrantDelay;
    TokenStorageService.transientRefreshRetryDelays = origTransientDelays;
    TokenStorageService.keyStoreRetryDelays = origKeyStoreDelays;
    TokenStorageService.externalSessionFallbackLoader = null;
    TokenStorageService.clearReauthRequired();
    await const TokenStorageService().clearSession(
      caller: 'test.tearDown',
      reason: 'cleanup',
      isUserInitiated: true,
    );
  });

  group('Zero Auto-Kick Auth & Refresh Resilience', () {
    test(
      'refreshToken retries up to 3 times with backoff on transient 503/network glitches and succeeds on 4th attempt',
      () async {
        const storage = TokenStorageService();
        final initial = _makeSession(
          accessToken: 'old_acc',
          refreshToken: 'old_rt',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        await storage.saveSession(initial);

        int attempts = 0;
        final mockClient = MockClient((request) async {
          attempts++;
          if (attempts <= 3) {
            return http.Response('Service Unavailable', 503);
          }
          return http.Response(
            jsonEncode({
              'access_token': 'new_acc_after_retries',
              'refresh_token': 'new_rt_after_retries',
              'id_token': 'id_new',
              'expires_in': 3600,
              'token_type': 'Bearer',
            }),
            200,
          );
        });

        final refreshed = await storage.refreshToken(
          session: initial,
          httpClient: mockClient,
        );

        expect(attempts, 4);
        expect(refreshed.accessToken, 'new_acc_after_retries');
        expect(refreshed.refreshToken, 'new_rt_after_retries');
        expect(TokenStorageService.reauthRequiredNotifier.value, isNull);
      },
    );

    test(
      'permanent invalid_grant marks reauthRequiredNotifier WITHOUT clearing persisted tokens',
      () async {
        const storage = TokenStorageService();
        final initial = _makeSession(
          accessToken: 'old_acc',
          refreshToken: 'revoked_rt',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        await storage.saveSession(initial);

        final mockClient = MockClient((request) async {
          return http.Response('{"error":"invalid_grant"}', 400);
        });

        await expectLater(
          () => storage.refreshToken(session: initial, httpClient: mockClient),
          throwsA(isA<VerifiedInvalidGrantException>()),
        );

        // ZERO AUTO-KICK: reauth banner flag is set, but tokens remain intact!
        expect(TokenStorageService.reauthRequiredNotifier.value, isNotNull);
        final stillStored = await storage.loadSession();
        expect(stillStored, isNotNull);
        expect(stillStored!.refreshToken, 'revoked_rt');
      },
    );

    test(
      'clearSession during in-flight refreshToken prevents session resurrection',
      () async {
        const storage = TokenStorageService();
        final initial = _makeSession(
          accessToken: 'acc_pre_logout',
          refreshToken: 'rt_pre_logout',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        await storage.saveSession(initial);

        final gate = Completer<void>();
        final mockClient = MockClient((request) async {
          await gate.future;
          return http.Response(
            jsonEncode({
              'access_token': 'resurrected_acc',
              'refresh_token': 'resurrected_rt',
              'id_token': 'id_res',
              'expires_in': 3600,
              'token_type': 'Bearer',
            }),
            200,
          );
        });

        final refreshFuture = storage.refreshToken(
          session: initial,
          httpClient: mockClient,
        );

        // User explicitly clicks Kijelentkezés while refresh is in flight.
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await storage.clearSession(
          caller: 'MoreScreen.logoutButton',
          reason: 'Explicit logout',
          isUserInitiated: true,
        );
        gate.complete();

        await expectLater(refreshFuture, throwsA(isA<Exception>()));
        expect(TokenStorageService.latestSession, isNull);
        expect(await storage.loadSession(), isNull);
      },
    );

    testWidgets(
      'HomeScreen NEVER calls onLogout on VerifiedInvalidGrantException; keeps cached data visible and shows re-auth banner with in-place recovery',
      (tester) async {
        final session = _makeSession(accessToken: 'expired_acc');
        final cached = DashboardData(
          student: null,
          todaysLessons: const [],
          allGrades: [
            Grade.fromJson({
              'Uid': 'g-cached',
              'KeszitesDatuma': '2026-11-12T10:15:00',
              'RogzitesDatuma': '2026-11-12T00:00:00',
              'Tantargy': {
                'Uid': 'sub-m',
                'Nev': 'Történelem',
                'Kategoria': {'Uid': 'm', 'Nev': 'm', 'Leiras': 'm'},
              },
              'Tipus': {'Uid': '1', 'Nev': 'Evkozi', 'Leiras': 'Évközi'},
              'ErtekFajta': {'Uid': '1', 'Nev': 'Jegy', 'Leiras': 'Jegy'},
              'ErtekeloTanarNeve': 'Tanár',
              'SzamErtek': 5,
              'SzovegesErtek': 'Jeles(5)',
            }),
          ],
          latestGrades: const [],
          homeworks: const [],
          tests: const [],
          omissions: const [],
          messages: const [],
          activeSession: session,
        );

        int logoutCalls = 0;
        int reauthCalls = 0;
        final client = _InvalidGrantKretaClient(cached: cached);

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: HomeScreen(
              initialSession: session,
              initialCachedData: cached,
              kretaClient: client,
              prefs: const UserProfilePrefs(),
              onPrefsChanged: (_) {},
              onLogout: () => logoutCalls++,
              onReauthenticate: () async {
                reauthCalls++;
                client.shouldThrowInvalidGrant = false;
                return _makeSession(
                  accessToken: 'reauthed_acc',
                  refreshToken: 'reauthed_rt',
                );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Zero Auto-Kick: onLogout MUST NOT be called!
        expect(logoutCalls, 0);
        // Cached grade remains visible!
        expect(find.text('Történelem'), findsOneWidget);
        // Non-destructive re-auth banner is displayed!
        expect(
          find.byKey(const ValueKey<String>('home-session-expired-banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('A munkamenet lejárt'),
          findsOneWidget,
        );

        // Tap in-place re-auth button -> restores live sync and clears banner!
        await tester.tap(
          find.byKey(const ValueKey<String>('home-reauth-button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(reauthCalls, 1);
        expect(logoutCalls, 0);
        expect(TokenStorageService.reauthRequiredNotifier.value, isNull);
        expect(
          find.byKey(const ValueKey<String>('home-session-expired-banner')),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 16));
      },
    );
  });

  group('Rolling 25-Entry Auth Event Timeline & Developer Options UI', () {
    test(
      'persists at most 25 entries and redacts raw OAuth tokens in error snippets',
      () async {
        for (int i = 1; i <= 30; i++) {
          await TokenStorageService.recordAuthEvent(
            caller: 'TestCaller.$i',
            action: 'event_$i',
            httpStatus: i == 30 ? 400 : 200,
            errorSnippet: i == 30
                ? 'access_token="SECRET_TOK_123" Bearer SECRET_BEARER_XYZ'
                : null,
          );
        }

        final entries = await TokenStorageService.loadAuthEventTimeline();
        expect(entries.length, TokenStorageService.maxAuthEventTimelineEntries);
        expect(entries.first.action, 'event_6');
        expect(entries.last.action, 'event_30');
        expect(entries.last.httpStatus, 400);
        expect(entries.last.errorSnippet, isNot(contains('SECRET_TOK_123')));
        expect(entries.last.errorSnippet, isNot(contains('SECRET_BEARER_XYZ')));
        expect(entries.last.errorSnippet, contains('[REDACTED]'));
      },
    );

    testWidgets(
      'DeveloperAuthNetworkSubPage displays the rolling Auth Event Timeline and Copy button',
      (tester) async {
        await TokenStorageService.recordAuthEvent(
          caller: 'TokenStorageService.refreshToken',
          action: 'transient_retry_1/3',
          httpStatus: 503,
          errorSnippet: 'upstream unavailable',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: const DeveloperAuthNetworkSubPage(
              initialPrefs: UserProfilePrefs(developerModeUnlocked: true),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        final timelineCard = find.byKey(
          const ValueKey<String>('dev-auth-timeline-card'),
        );
        await tester.scrollUntilVisible(
          timelineCard,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(timelineCard, findsOneWidget);
        expect(
          find.textContaining('transient_retry_1/3'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('dev-auth-timeline-copy')),
          findsOneWidget,
        );
      },
    );
  });

  group('Full-Repo Audit Regression Checks', () {
    test('decodeJwtPayload handles malformed JWT safely without throwing', () {
      expect(KretaAuthConfig.decodeJwtPayload('not-a-jwt'), isEmpty);
      expect(KretaAuthConfig.decodeJwtPayload('a.!!!invalid_base64!!!.c'), isEmpty);
    });

    test('CustomSkinConfig parses 8-digit CSS #RRGGBBAA hex in correct ARGB order', () {
      final cfg = CustomSkinConfig.parse(
        '''
        :root {
          --accent: #11223380;
        }
        ''',
        enabled: true,
      );
      expect(cfg.accent, const Color(0x80112233));
    });

    testWidgets(
      'LiveCountdownProgressScope mounts safely during the final 60 seconds without initState TickerMode crash',
      (tester) async {
        final now = DateTime.now();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LiveCountdownProgressScope(
                startTime: now.subtract(const Duration(minutes: 44, seconds: 30)),
                endTime: now.add(const Duration(seconds: 30)),
                builder: (_, snap) => Text(snap.formattedRemaining()),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
