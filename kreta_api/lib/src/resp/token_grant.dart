class TokenGrantResponse {
  final String idToken;
  final String accessToken;
  final int expiresIn;
  final String tokenType;
  final String refreshToken;
  final String scope;

  TokenGrantResponse({
    required this.idToken,
    required this.accessToken,
    required this.expiresIn,
    required this.tokenType,
    required this.refreshToken,
    required this.scope,
  });

  factory TokenGrantResponse.fromJson(Map<String, dynamic> json) {
    return TokenGrantResponse(
      idToken: (json['id_token'] ?? '').toString(),
      accessToken: (json['access_token'] ?? '').toString(),
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 1800,
      tokenType: (json['token_type'] ?? 'Bearer').toString(),
      refreshToken: (json['refresh_token'] ?? '').toString(),
      scope: (json['scope'] ?? '').toString(),
    );
  }

  @override
  String toString() {
    return 'TokenGrant(idToken: "$idToken", accessToken: "$accessToken", '
        'expiresIn: $expiresIn, '
        'tokenType: "$tokenType", '
        'refreshToken: "$refreshToken", '
        'scope: "$scope"'
        ')';
  }
}
