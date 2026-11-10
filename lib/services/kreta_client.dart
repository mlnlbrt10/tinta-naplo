import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kreta_api/kreta_api.dart';

import '../core/kreta_auth_config.dart';
import 'token_storage_service.dart';

/// Aggregated payload for the Home, Grades, and Timetable screens.
class DashboardData {
  final Student? student;
  final List<Lesson> todaysLessons;
  final List<Grade> allGrades;
  final List<Grade> latestGrades;
  final List<Homework> homeworks;
  final List<Test> tests;
  final StoredSession activeSession;

  const DashboardData({
    required this.student,
    required this.todaysLessons,
    required this.allGrades,
    required this.latestGrades,
    required this.homeworks,
    required this.tests,
    required this.activeSession,
  });
}

/// Client for E-Kréta OAuth2 token exchange, token refresh, and v3 API queries
/// backed by models and endpoints from `package:kreta_api/kreta_api.dart`.
class KretaClient {
  final http.Client _http;
  final TokenStorageService _storage;
  final String clientId;

  KretaClient({
    http.Client? httpClient,
    TokenStorageService? storage,
    this.clientId = KretaAuthConfig.clientIdIos,
  })  : _http = httpClient ?? http.Client(),
        _storage = storage ?? const TokenStorageService();

  TokenStorageService get storage => _storage;

  Map<String, String> get _idpHeaders => const {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Accept': '*/*',
        'User-Agent': KretaAuthConfig.userAgent,
      };

  Map<String, String> _apiHeaders(String accessToken) => {
        'Accept': 'application/json, */*',
        'User-Agent': KretaAuthConfig.userAgent,
        'Authorization': 'Bearer $accessToken',
        'apiKey': KretaAuthConfig.apiKey,
      };

  /// Exchanges the intercepted OAuth2 authorization [code] and PKCE
  /// [codeVerifier] at `/connect/token` and persists the resulting tokens.
  Future<StoredSession> exchangeCodeForTokens({
    required String code,
    required String codeVerifier,
    String? fallbackInstituteCode,
  }) async {
    final response = await _http.post(
      Uri.parse(KretaAuthConfig.tokenEndpoint),
      headers: _idpHeaders,
      body: {
        'code': code,
        'code_verifier': codeVerifier,
        'redirect_uri': KretaAuthConfig.redirectUri,
        'client_id': clientId,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode == 400) {
      throw TokenExpiredException();
    }
    if (response.statusCode == 401) {
      throw InvalidGrantException();
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Token exchange failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final jsonMap =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final grant = TokenGrantResponse.fromJson(jsonMap);
    final session = StoredSession.fromTokenGrant(
      grant,
      fallbackInstituteCode: fallbackInstituteCode,
    );
    await _storage.saveSession(session);
    return session;
  }

  /// Refreshes an expired [StoredSession] using `grant_type=refresh_token`.
  Future<StoredSession> refreshSession(StoredSession current) async {
    final response = await _http.post(
      Uri.parse(KretaAuthConfig.tokenEndpoint),
      headers: _idpHeaders,
      body: {
        'institute_code': current.instituteCode,
        'refresh_token': current.refreshToken,
        'grant_type': 'refresh_token',
        'client_id': clientId,
      },
    );

    if (response.statusCode == 400) {
      throw TokenExpiredException();
    }
    if (response.statusCode == 401) {
      throw InvalidGrantException();
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Token refresh failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final jsonMap =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final grant = TokenGrantResponse.fromJson(jsonMap);
    final refreshed = StoredSession.fromTokenGrant(
      grant,
      fallbackInstituteCode: current.instituteCode,
    );
    await _storage.saveSession(refreshed);
    return refreshed;
  }

  /// Ensures the session has a valid (non-expired) access token, refreshing if needed.
  Future<StoredSession> ensureValidSession(StoredSession session) async {
    if (!session.isExpired) {
      return session;
    }
    return refreshSession(session);
  }

  Future<dynamic> _getAuthenticatedJson(
    StoredSession session,
    String url,
  ) async {
    final response = await _http.get(
      Uri.parse(url),
      headers: _apiHeaders(session.accessToken),
    );

    if (response.statusCode == 401) {
      throw InvalidGrantException();
    }
    if (response.statusCode != 200) {
      throw Exception('GET $url failed (HTTP ${response.statusCode})');
    }

    final text = utf8.decode(response.bodyBytes).trim();
    if (text.isEmpty) {
      return const [];
    }
    return jsonDecode(text);
  }

  /// Fetches timetable lessons between [from] and [to] (inclusive) using
  /// [KretaEndpoints.getTimeTable] and parses each item with [Lesson.fromJson].
  Future<List<Lesson>> fetchTimetableForRange(
    StoredSession session, {
    required DateTime from,
    required DateTime to,
  }) async {
    final startDay = DateTime(from.year, from.month, from.day);
    final endDay = DateTime(to.year, to.month, to.day);
    final url = KretaEndpoints.getTimeTable(
      session.instituteCode,
      startDay,
      endDay,
    );

    final raw = await _getAuthenticatedJson(session, url);
    if (raw is! List) {
      return const [];
    }

    final lessons = raw
        .whereType<Map<String, dynamic>>()
        .map(Lesson.fromJson)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    return lessons;
  }

  /// Fetches today's timetable lessons using [KretaEndpoints.getTimeTable].
  Future<List<Lesson>> fetchTodaysTimetable(
    StoredSession session, {
    DateTime? date,
  }) async {
    final target = date ?? DateTime.now();
    return fetchTimetableForRange(session, from: target, to: target);
  }

  /// Fetches all student evaluations via [KretaEndpoints.getGrades] sorted
  /// newest-first by `recordDate` / `creationDate`.
  Future<List<Grade>> fetchAllGrades(StoredSession session) async {
    final url = KretaEndpoints.getGrades(session.instituteCode);
    final raw = await _getAuthenticatedJson(session, url);
    if (raw is! List) {
      return const [];
    }

    final grades = raw
        .whereType<Map<String, dynamic>>()
        .map(Grade.fromJson)
        .toList()
      ..sort((a, b) {
        final cmp = b.recordDate.compareTo(a.recordDate);
        return cmp != 0 ? cmp : b.creationDate.compareTo(a.creationDate);
      });

    return grades;
  }

  /// Fetches homework assignments via [KretaEndpoints.getHomework] for the
  /// recent/upcoming 45-day window, sorted newest-first.
  Future<List<Homework>> fetchHomeworks(StoredSession session) async {
    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 30));
      final to = now.add(const Duration(days: 30));
      final url = KretaEndpoints.getHomework(session.instituteCode, from, to);
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is! List) return const [];

      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(Homework.fromJson)
          .toList()
        ..sort((a, b) => b.creationDate.compareTo(a.creationDate));
      return list;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  /// Fetches announced tests/exams via [KretaEndpoints.getTests], sorted newest-first.
  Future<List<Test>> fetchTests(StoredSession session) async {
    try {
      final url = KretaEndpoints.getTests(session.instituteCode);
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is! List) return const [];

      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(Test.fromJson)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return list;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  /// Fetches the student profile via [KretaEndpoints.getStudent].
  Future<Student?> fetchStudentProfile(StoredSession session) async {
    try {
      final url = KretaEndpoints.getStudent(session.instituteCode);
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is Map<String, dynamic>) {
        return Student.fromJson(raw);
      }
    } catch (_) {
      // Student profile is supplementary if endpoint fails.
    }
    return null;
  }

  /// Fetches today's timetable, all grades, homeworks, announced tests, and
  /// student profile in parallel, refreshing the token once if expired or 401.
  Future<DashboardData> fetchDashboardData(
    StoredSession initialSession, {
    DateTime? date,
  }) async {
    StoredSession session = await ensureValidSession(initialSession);

    Future<DashboardData> loadWith(StoredSession active) async {
      final results = await Future.wait<Object?>([
        fetchTodaysTimetable(active, date: date),
        fetchAllGrades(active),
        fetchStudentProfile(active),
        fetchHomeworks(active),
        fetchTests(active),
      ]);

      final allGrades = results[1] as List<Grade>;
      return DashboardData(
        todaysLessons: results[0] as List<Lesson>,
        allGrades: allGrades,
        latestGrades: allGrades.take(5).toList(),
        student: results[2] as Student?,
        homeworks: results[3] as List<Homework>,
        tests: results[4] as List<Test>,
        activeSession: active,
      );
    }

    try {
      return await loadWith(session);
    } on InvalidGrantException {
      session = await refreshSession(session);
      return await loadWith(session);
    }
  }
}
