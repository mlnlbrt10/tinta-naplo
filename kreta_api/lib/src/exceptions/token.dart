class TokenExpiredException implements Exception {
  const TokenExpiredException();

  @override
  String toString() => 'A munkamenet lejárt, kérjük frissítsd vagy jelentkezz be újra.';
}

class InvalidGrantException implements Exception {
  const InvalidGrantException();

  @override
  String toString() => 'Érvénytelen vagy lejárt hitelesítési token.';
}
