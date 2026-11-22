import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart'
    show InvalidGrantException, TokenGrantResponse;
import 'package:tinta_naplo/screens/developer_options_screen.dart';
import 'package:tinta_naplo/services/demo_data_service.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/custom_skin_config.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/utils/uwu_helper.dart';
import 'package:tinta_naplo/widgets/christmas_snowfall_overlay.dart';
import 'package:tinta_naplo/widgets/tinta_error_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _makeJwt(Map<String, dynamic> claims) {
  final payload = base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll(
        '=',
        '',
      );
  return 'eyJhbGciOiJSUzI1NiJ9.$payload.sig';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    UwuHelper.isEnabled = false;
    UwuHelper.isFitymaEnabled = false;
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
    TokenStorageService.externalSessionFallbackLoader = null;
    TokenStorageService.invalidGrantRetryDelay = Duration.zero;
  });

  tearDown(() {
    UwuHelper.isEnabled = false;
    UwuHelper.isFitymaEnabled = false;
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
    TokenStorageService.externalSessionFallbackLoader = null;
    TokenStorageService.invalidGrantRetryDelay =
        const Duration(milliseconds: 400);
  });

  group('1. TintaErrorState & Offline Mapping', () {
    testWidgets(
      'maps SocketException / ClientException to friendly Hungarian card with Újrapróbálás button and zero raw stack traces',
      (tester) async {
        var retried = false;
        const socketErr = SocketException(
          'Failed host lookup: \'klik035225001.e-kreta.hu\'',
        );

        expect(TintaErrorState.isNetworkError(socketErr), isTrue);
        expect(
          TintaErrorState.isNetworkError(
            http.ClientException('Connection closed while receiving data'),
          ),
          isTrue,
        );
        expect(
          TintaErrorState.friendlyTitleFor(socketErr),
          'Nincs internetkapcsolat',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Scaffold(
              body: Center(
                child: TintaErrorState(
                  error: socketErr,
                  onRetry: () => retried = true,
                ),
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Nincs internetkapcsolat'), findsOneWidget);
        expect(
          find.text(
            'Nem sikerült betölteni az adatokat. Ellenőrizd a hálózati kapcsolatod, majd próbáld újra.',
          ),
          findsOneWidget,
        );
        expect(find.text('Újrapróbálás'), findsOneWidget);
        expect(find.textContaining('SocketException'), findsNothing);
        expect(find.textContaining('Failed host lookup'), findsNothing);

        await tester.tap(find.text('Újrapróbálás'));
        await tester.pump();
        expect(retried, isTrue);
      },
    );
  });

  group('2. Custom Skin Engine (CSS :root parser + Theme)', () {
    test(
      'CustomSkinConfig.parse parses :root CSS variables and applies overrides in OledTheme.buildTheme',
      () {
        const css = '''
:root {
  --bg: #101218;
  --surface: #1A1E29;
  --accent: #FF55AA;
  --text: #E2E8F0;
  --card-radius: 26px;
  --border-color: rgba(255, 85, 170, 0.40);
  --border-width: 1.5px;
  --glass-blur: 22;
  --card-opacity: 0.72;
  --font-scale: 1.1;
}
''';
        final parsed = CustomSkinConfig.parse(css, enabled: true);
        expect(parsed.enabled, isTrue);
        expect(parsed.bg, const Color(0xFF101218));
        expect(parsed.surface, const Color(0xFF1A1E29));
        expect(parsed.accent, const Color(0xFFFF55AA));
        expect(parsed.text, const Color(0xFFE2E8F0));
        expect(parsed.cardRadius, 26.0);
        expect(parsed.borderWidth, 1.5);
        expect(parsed.glassBlur, 22.0);
        expect(parsed.cardOpacity, closeTo(0.72, 0.001));
        expect(parsed.fontScale, closeTo(1.1, 0.001));
        expect(parsed.borderColor, isNotNull);
        expect(parsed.borderColor!.r, closeTo(1.0, 0.01));

        final prefs = const UserProfilePrefs().withCustomSkin(
          enabled: true,
          css: css,
        );
        UserProfilePrefs.syncActiveGlobals(prefs);
        final theme = OledTheme.buildTheme(prefs: prefs);
        expect(theme.scaffoldBackgroundColor, const Color(0xFF101218));
        expect(theme.colorScheme.primary, const Color(0xFFFF55AA));
        expect(theme.colorScheme.surface, const Color(0xFF101218));
        final surfaceApplied =
            theme.dialogTheme.backgroundColor ?? theme.cardColor;
        expect(surfaceApplied.r, closeTo(0x1A / 255.0, 0.01));
        expect(surfaceApplied.g, closeTo(0x1E / 255.0, 0.01));
        expect(surfaceApplied.b, closeTo(0x29 / 255.0, 0.01));
        expect(theme.textTheme.bodyMedium?.fontSize, greaterThan(14.5));
      },
    );
  });

  group('3 & 4 & 10. Developer Options UI, Fityma Napló & Now Bar Tutorial', () {
    testWidgets(
      'UwuHelper substitutes Fityma Napló, AppBrandIconBadge uses FitymaBrandIcon, and Dev Appearance/Integrations render controls & tutorial',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fitymaPrefs = const UserProfilePrefs().withFitymaMode(true);
        UserProfilePrefs.syncActiveGlobals(fitymaPrefs);
        expect(UwuHelper.isFitymaEnabled, isTrue);
        expect(AppIconPresetInfo.resolve(fitymaPrefs).id, 'icon_fityma');
        expect(
          AppIconPresetInfo.resolve(fitymaPrefs).activityAlias,
          '.MainActivityFityma',
        );
        expect(
          AppIconPresetInfo.resolve(fitymaPrefs).assetPath,
          'assets/images/fityma-icon.png',
        );
        expect(uwu('Tinta Napló'), 'Fityma Napló');
        expect(uwu('Tinta Napló v3.0.0'), 'Fityma Napló v3.0.0');

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: fitymaPrefs),
            home: Scaffold(
              body: Column(
                children: [
                  AppBrandIconBadge(prefs: fitymaPrefs, size: 40),
                  Text(uwu('Tinta Napló')),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(FitymaBrandIcon), findsOneWidget);
        expect(find.text('Fityma Napló'), findsOneWidget);

        UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: DeveloperAppearanceSubPage(
              initialPrefs: const UserProfilePrefs(),
              onPrefsChanged: (_) {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        await tester.scrollUntilVisible(
          find.text('Fityma Napló mód'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Fityma Napló mód'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Egyéni CSS Skin'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Egyéni CSS Skin'), findsOneWidget);
        expect(find.text('Alkalmaz'), findsOneWidget);
        expect(find.text('Alaphelyzet'), findsOneWidget);
        expect(find.text('Másolás'), findsOneWidget);
        expect(find.text('Beillesztés'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: const DeveloperIntegrationsSubPage(
              initialPrefs: UserProfilePrefs(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        await tester.scrollUntilVisible(
          find.text('Bekapcsolási útmutató (Samsung / Android 16+):'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text('Bekapcsolási útmutató (Samsung / Android 16+):'),
          findsOneWidget,
        );
      },
    );
  });

  group('5. Persistent Token Expiry & Refresh Resilience', () {
    test(
      'StoredSession.fromTokenGrant uses accessToken exp instead of expired idToken exp and preserves fallbacks',
      () {
        final futureExpSec =
            DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
                1000;
        final expiredIdJwt = _makeJwt({
          'exp': 1000000,
        });
        final validAccessJwt = _makeJwt({
          'exp': futureExpSec,
          'kreta:institute_code': 'klik0001',
        });

        final session = StoredSession.fromTokenGrant(
          TokenGrantResponse(
            accessToken: validAccessJwt,
            refreshToken: 'refresh-1',
            idToken: '',
            expiresIn: 1800,
            tokenType: 'Bearer',
            scope: 'openid',
          ),
          fallbackInstituteCode: 'klik0001',
          fallbackIdToken: expiredIdJwt,
          fallbackUserName: 'diak01',
        );

        expect(session.isExpired, isFalse);
        expect(
          session.expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 20))),
          isTrue,
        );
        expect(session.idToken, expiredIdJwt);
        expect(session.userName, 'diak01');
      },
    );

    test(
      'TokenStorageService.refreshToken never clears or throws InvalidGrantException on transient 400/500, but throws on explicit invalid_grant and retries 401 in KretaClient',
      () async {
        const storage = TokenStorageService();
        final futureExpSec =
            DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
                1000;
        final initialSession = StoredSession(
          accessToken: _makeJwt({
            'exp': 1000000,
            'kreta:institute_code': 'klik0001',
            'kreta:user_name': 'tanulo1',
          }),
          refreshToken: 'refresh-initial',
          idToken: 'id-initial',
          instituteCode: 'klik0001',
          userName: 'tanulo1',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        await storage.saveSession(initialSession);

        final generic400Client = MockClient(
          (_) async => http.Response('{"error":"temporarily_unavailable"}', 400),
        );
        await expectLater(
          () => storage.refreshToken(
            session: initialSession,
            httpClient: generic400Client,
          ),
          throwsA(
            allOf(
              isA<Exception>(),
              isNot(isA<InvalidGrantException>()),
            ),
          ),
        );
        expect(await storage.loadSession(), isNotNull);

        final server500Client = MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        );
        await expectLater(
          () => storage.refreshToken(
            session: initialSession,
            httpClient: server500Client,
          ),
          throwsA(
            allOf(
              isA<Exception>(),
              isNot(isA<InvalidGrantException>()),
            ),
          ),
        );
        expect(await storage.loadSession(), isNotNull);

        final explicitInvalidGrantClient = MockClient(
          (_) async => http.Response('{"error":"invalid_grant"}', 400),
        );
        await expectLater(
          () => storage.refreshToken(
            session: initialSession,
            httpClient: explicitInvalidGrantClient,
          ),
          throwsA(isA<InvalidGrantException>()),
        );

        final freshAccessJwt = _makeJwt({
          'exp': futureExpSec,
          'kreta:institute_code': 'klik0001',
          'kreta:user_name': 'tanulo1',
        });
        final notYetExpiredSession = StoredSession(
          accessToken: 'stale-but-not-locally-expired',
          refreshToken: 'refresh-initial',
          idToken: 'id-initial',
          instituteCode: 'klik0001',
          userName: 'tanulo1',
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        );
        await storage.saveSession(notYetExpiredSession);

        var apiCalls = 0;
        var refreshCalls = 0;
        final retryMockClient = MockClient((req) async {
          if (req.method == 'POST') {
            refreshCalls++;
            return http.Response(
              jsonEncode({
                'access_token': freshAccessJwt,
                'refresh_token': 'refresh-rotated',
                'expires_in': 1800,
                'token_type': 'Bearer',
              }),
              200,
            );
          }
          apiCalls++;
          if (req.headers['Authorization'] ==
              'Bearer stale-but-not-locally-expired') {
            return http.Response('Unauthorized', 401);
          }
          return http.Response('[]', 200);
        });

        final client = KretaClient(httpClient: retryMockClient, storage: storage);
        final grades = await client.fetchAllGrades(notYetExpiredSession);
        expect(grades, isEmpty);
        expect(apiCalls, 2);
        expect(refreshCalls, 1);
        final persisted = await storage.loadSession();
        expect(persisted?.accessToken, freshAccessJwt);
        expect(persisted?.refreshToken, 'refresh-rotated');
      },
    );
  });

  group('11. Demo Mode (Demó mód)', () {
    test(
      'buildDemoTests returns 1 upcoming exam and buildDemoGrades preserves all 28 grades with recent top entries',
      () {
        final now = DateTime(2026, 11, 19, 10, 0);
        final demo = DemoDataService.instance;
        final tests = demo.buildDemoTests(nowOverride: now);
        final grades = demo.buildDemoGrades(nowOverride: now);

        expect(tests.length, 1);
        expect(grades.length, 28);
        expect(
          grades.take(5).every(
                (g) => now.difference(g.recordDate).inDays <= 5,
              ),
          isTrue,
        );
      },
    );
  });

  group('12. Refresh Lock Safety, Watch Token Recovery & last_logout_reason', () {
    test(
      'refreshToken recovers rotated token from external watch fallback before declaring invalid_grant and unlocks single-flight Completer after errors',
      () async {
        const storage = TokenStorageService();
        final futureExpSec =
            DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
                1000;
        final initialSession = StoredSession(
          accessToken: 'old-access',
          refreshToken: 'old-refresh-consumed-by-watch',
          idToken: 'id-1',
          instituteCode: 'klik0001',
          userName: 'tanulo1',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        await storage.saveSession(initialSession);

        final watchRotatedSession = StoredSession(
          accessToken: _makeJwt({
            'exp': futureExpSec,
            'kreta:institute_code': 'klik0001',
            'kreta:user_name': 'tanulo1',
          }),
          refreshToken: 'fresh-watch-rotated-refresh',
          idToken: 'id-1',
          instituteCode: 'klik0001',
          userName: 'tanulo1',
          expiresAt: DateTime.now().add(const Duration(minutes: 25)),
        );

        var postAttempts = 0;
        final raceMock = MockClient((req) async {
          postAttempts++;
          if (postAttempts == 1) {
            // Simulate watch rotating the token right as phone tried old refresh token.
            TokenStorageService.externalSessionFallbackLoader =
                () async => watchRotatedSession;
            return http.Response('{"error":"invalid_grant"}', 400);
          }
          return http.Response('{"error":"invalid_grant"}', 400);
        });

        final recovered = await storage.refreshToken(
          session: initialSession,
          httpClient: raceMock,
        );
        expect(recovered.refreshToken, 'fresh-watch-rotated-refresh');
        expect(postAttempts, 1);

        // Now verify failed refresh unlocks single-flight Completer so next call runs cleanly.
        TokenStorageService.externalSessionFallbackLoader = null;
        await storage.saveSession(initialSession);
        final failingClient = MockClient(
          (_) async => http.Response('Gateway Timeout', 504),
        );
        await expectLater(
          () => storage.refreshToken(
            session: initialSession,
            httpClient: failingClient,
          ),
          throwsException,
        );

        final nextFreshJwt = _makeJwt({
          'exp': futureExpSec,
          'kreta:institute_code': 'klik0001',
          'kreta:user_name': 'tanulo1',
        });
        final succeedingClient = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'access_token': nextFreshJwt,
              'refresh_token': 'refresh-after-recovery',
              'expires_in': 1800,
              'token_type': 'Bearer',
            }),
            200,
          ),
        );
        final afterUnlock = await storage.refreshToken(
          session: initialSession,
          httpClient: succeedingClient,
        );
        expect(afterUnlock.refreshToken, 'refresh-after-recovery');
      },
    );

    testWidgets(
      'last_logout_reason persists in SharedPreferences across clearSession and renders inside DeveloperAuthNetworkSubPage',
      (tester) async {
        const storage = TokenStorageService();
        await TokenStorageService.recordLogoutReason(
          caller: 'HomeScreen._loadDashboard',
          reason: 'Verified permanent invalid_grant after retry',
          httpStatusCode: 400,
          errorBody: '{"error":"invalid_grant"}',
        );
        await storage.clearSession();

        final sp = await SharedPreferences.getInstance();
        expect(
          sp.getString(TokenStorageService.lastLogoutReasonKey),
          contains('HomeScreen._loadDashboard'),
        );

        final loaded = await TokenStorageService.loadLastLogoutReason();
        expect(loaded, isNotNull);
        expect(loaded!.caller, 'HomeScreen._loadDashboard');
        expect(loaded.httpStatusCode, 400);
        expect(loaded.errorBody, '{"error":"invalid_grant"}');

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: const DeveloperAuthNetworkSubPage(
              initialPrefs: UserProfilePrefs(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        await tester.scrollUntilVisible(
          find.text('Utolsó kijelentkezés oka (last_logout_reason)'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text('Utolsó kijelentkezés oka (last_logout_reason)'),
          findsOneWidget,
        );
        expect(find.text('HomeScreen._loadDashboard'), findsOneWidget);
        expect(find.text('400'), findsOneWidget);
        expect(find.text('{"error":"invalid_grant"}'), findsOneWidget);
      },
    );
  });
}
