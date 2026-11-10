import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// OAuth2 PKCE parameters generated for a single authorization request.
class PkcePair {
  final String codeVerifier;
  final String codeChallenge;
  final String state;
  final String nonce;

  const PkcePair({
    required this.codeVerifier,
    required this.codeChallenge,
    required this.state,
    required this.nonce,
  });

  /// Generates a cryptographically secure RFC 7636 PKCE `code_verifier`
  /// and its S256 `code_challenge` (base64url-encoded without `=` padding).
  factory PkcePair.generate() {
    final random = Random.secure();

    final verifierBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final codeVerifier = _base64UrlNoPadding(verifierBytes);

    final digest = sha256.convert(ascii.encode(codeVerifier));
    final codeChallenge = _base64UrlNoPadding(digest.bytes);

    final stateBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final state = _base64UrlNoPadding(stateBytes);

    final nonceBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = _base64UrlNoPadding(nonceBytes);

    return PkcePair(
      codeVerifier: codeVerifier,
      codeChallenge: codeChallenge,
      state: state,
      nonce: nonce,
    );
  }

  static String _base64UrlNoPadding(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

/// Constants and URL builders for E-Kréta IDP OAuth2 PKCE authentication.
class KretaAuthConfig {
  static const String idpBaseUrl = 'https://idp.e-kreta.hu';
  static const String authorizeEndpoint = '$idpBaseUrl/connect/authorize';
  static const String loginEndpoint = '$idpBaseUrl/Account/Login';
  static const String tokenEndpoint = '$idpBaseUrl/connect/token';

  /// Registered E-Kréta Student Mobile OAuth2 client IDs.
  static const String clientIdIos = 'kreta-ellenorzo-student-mobile-ios';
  static const String clientIdAndroid = 'kreta-ellenorzo-student-mobile-android';

  /// Registered OAuth2 redirect URI intercepted by the in-app WebView.
  static const String redirectUri =
      'https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect';

  /// Standard OIDC + Kréta v3 API scopes.
  static const String scopes =
      'openid email offline_access '
      'kreta-ellenorzo-webapi.public '
      'kreta-eugyintezes-webapi.public '
      'kreta-fileservice-webapi.public '
      'kreta-mobile-global-webapi.public '
      'kreta-dkt-webapi.public '
      'kreta-ier-webapi.public';

  /// Required API headers for `/ellenorzo/v3/sajat/*` requests.
  static const String userAgent =
      'eKretaStudent/264745 CFNetwork/1494.0.7 Darwin/23.4.0';
  static const String apiKey = '21ff6c25-d1da-4a68-a811-c881a6057463';

  /// Constructs the IDP authorization URL that opens `/Account/Login` with the
  /// signed `/connect/authorize/callback` ReturnUrl and PKCE challenge.
  static Uri buildAuthorizationUri({
    required PkcePair pkce,
    String clientId = clientIdIos,
    String? instituteCode,
    String? loginHint,
  }) {
    final callbackParams = <String, String>{
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'response_type': 'code',
      'prompt': 'login',
      'state': pkce.state,
      'nonce': pkce.nonce,
      'scope': scopes,
      'code_challenge': pkce.codeChallenge,
      'code_challenge_method': 'S256',
      'suppressed_prompt': 'login',
    };

    if (instituteCode != null && instituteCode.trim().isNotEmpty) {
      callbackParams['institute_code'] = instituteCode.trim();
    }
    if (loginHint != null && loginHint.trim().isNotEmpty) {
      callbackParams['login_hint'] = loginHint.trim();
    }

    final callbackQuery = callbackParams.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    final returnUrl = '/connect/authorize/callback?$callbackQuery';
    return Uri.parse(loginEndpoint).replace(
      queryParameters: {'ReturnUrl': returnUrl},
    );
  }

  /// Checks whether a navigation URL matches the mobile OAuth2 redirect URI.
  static bool isOAuthRedirectUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    return rawUrl.startsWith(redirectUri) ||
        uri.path.contains('/ellenorzo-student/prod/oauthredirect');
  }

  /// Decodes the JSON payload of a 3-part JWT without external packages.
  static Map<String, dynamic> decodeJwtPayload(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) {
      return const {};
    }
    final normalized = base64Url.normalize(parts[1]);
    final payloadString = utf8.decode(base64Url.decode(normalized));
    final decoded = jsonDecode(payloadString);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}
