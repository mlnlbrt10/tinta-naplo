import 'package:flutter_test/flutter_test.dart';
import 'package:rekreta_app/core/kreta_auth_config.dart';
import 'package:rekreta_app/services/github_updater_service.dart';
import 'package:rekreta_app/utils/greeting_utils.dart';
import 'package:rekreta_app/utils/uwu_helper.dart';

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

  test('UwuHelper and GreetingUtils transform text in UwU / Kawaii mode', () {
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
        now: DateTime(2026, 11, 10, 23, 0),
        uwuMode: true,
      ),
      'Jó éccakát, Miwán! :3',
    );
    final transformed = UwuHelper.transform('Frissítések keresése', enabled: true);
    expect(transformed.startsWith('Fwissítések kewesése'), isTrue);
  });

  test('GitHubUpdaterService compares semantic versions and pre-release tags', () {
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
}
