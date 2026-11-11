import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:rekreta_app/core/kreta_auth_config.dart';
import 'package:rekreta_app/services/github_updater_service.dart';
import 'package:rekreta_app/services/kreta_client.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/utils/greeting_utils.dart';
import 'package:rekreta_app/utils/uwu_helper.dart';

class _InMemoryTokenStorage extends TokenStorageService {
  StoredSession? savedSession;

  @override
  Future<void> saveSession(StoredSession session) async {
    savedSession = session;
  }

  @override
  Future<StoredSession?> loadSession() async => savedSession;
}

void main() {
  test('PkcePair generates distinct base64url verifier and S256 challenge', () {
    final pair = PkcePair.generate();
    expect(pair.codeVerifier.length, greaterThanOrEqualTo(43));
    expect(pair.codeChallenge.length, greaterThanOrEqualTo(43));
    expect(pair.codeVerifier.contains('='), isFalse);
    expect(pair.codeChallenge.contains('='), isFalse);
  });

  test('isOAuthRedirectUrl matches mobile oauthredirect callback', () {
    const callbackUrl =
        'https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect?code=abc123xyz&state=st1';
    expect(KretaAuthConfig.isOAuthRedirectUrl(callbackUrl), isTrue);
    expect(
      KretaAuthConfig.isOAuthRedirectUrl('https://idp.e-kreta.hu/Account/Login'),
      isFalse,
    );
  });

  test('GreetingUtils resolves nickname or falls back to Milán / first name', () {
    expect(
      GreetingUtils.resolveDisplayName(
        customNickname: 'Mili',
        fullStudentName: 'Kovács Milán',
      ),
      'Mili',
    );
    expect(
      GreetingUtils.resolveDisplayName(
        customNickname: '',
        fullStudentName: 'Kovács Milán',
      ),
      'Milán',
    );
    expect(
      GreetingUtils.resolveDisplayName(
        customNickname: null,
        fullStudentName: null,
      ),
      'Milán',
    );
  });

  test('GreetingUtils builds time-based Hungarian greetings for all 4 windows', () {
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 6, 30),
      ),
      'Szép reggelt, Milán!',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 14, 0),
      ),
      'Szép napot, Milán!',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 19, 45),
      ),
      'Szép estét, Milán!',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 23, 15),
      ),
      'Jó éjszakát, Milán!',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 2, 10),
      ),
      'Jó éjszakát, Milán!',
    );
  });

  test('UwuHelper and GreetingUtils transform text in UwU mode and Tsundere mode', () {
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 12, 0),
        uwuMode: true,
      ),
      'Szép nyapot, Miwán! uwu',
    );
    expect(
      GreetingUtils.buildGreeting(
        name: 'Milán',
        now: DateTime(2026, 11, 10, 12, 0),
        tsundereMode: true,
      ),
      contains('b-baka'),
    );
    expect(
      UwuHelper.tsundereCommentForGrade(3),
      contains('Megint hármas? Nem mintha figyeltem volna'),
    );
    final transformed = UwuHelper.transform('Frissítések keresése', enabled: true);
    expect(transformed.startsWith('Fwissítések kewesése'), isTrue);
  });

  test('GitHubUpdaterService compares semantic versions and build tags accurately', () {
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.2', 'v1.0.3'),
      isTrue,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.2', 'v1.0.2'),
      isFalse,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.0-alpha', 'v1.0.0'),
      isTrue,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.0-alpha', 'v1.1.0-alpha'),
      isTrue,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.0.0-alpha', 'v1.0.0-alpha'),
      isFalse,
    );
    expect(
      GitHubUpdaterService.isRemoteVersionNewer('1.2.0', 'v1.1.9'),
      isFalse,
    );
  });

  test('KretaClient transparent token refresh interceptor retries HTTP 401 and replays request', () async {
    int apiCalls = 0;
    int tokenRefreshCalls = 0;

    final mockHttp = MockClient((request) async {
      if (request.url.toString().contains('/connect/token')) {
        tokenRefreshCalls++;
        return http.Response(
          '{"access_token":"fresh_token_123","refresh_token":"fresh_refresh_456","id_token":"id_123","token_type":"Bearer","expires_in":1800}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      apiCalls++;
      final authHeader = request.headers['Authorization'] ?? '';
      if (authHeader == 'Bearer expired_token') {
        return http.Response('Unauthorized', 401);
      }
      if (authHeader == 'Bearer fresh_token_123') {
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('Unexpected token: $authHeader', 500);
    });

    final storage = _InMemoryTokenStorage();
    final initialSession = StoredSession(
      accessToken: 'expired_token',
      refreshToken: 'old_refresh',
      idToken: 'old_id',
      instituteCode: 'klik123456',
      userName: 'Teszt Elek',
      expiresAt: DateTime.now().add(const Duration(minutes: 20)),
    );
    storage.savedSession = initialSession;

    final client = KretaClient(httpClient: mockHttp, storage: storage);
    final grades = await client.fetchAllGrades(initialSession);

    expect(grades, isEmpty);
    expect(tokenRefreshCalls, 1);
    expect(apiCalls, 2);
    expect(storage.savedSession?.accessToken, 'fresh_token_123');
    expect(storage.savedSession?.refreshToken, 'fresh_refresh_456');
    expect(const TokenExpiredException().toString(), isNot(contains('Instance of')));
  });
}
