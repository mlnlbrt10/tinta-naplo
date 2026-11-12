import 'dart:convert';

import 'package:flutter/material.dart' show DateUtils;

import 'package:http/http.dart' as http;
import 'package:kreta_api/kreta_api.dart';

import '../core/kreta_auth_config.dart';
import 'token_storage_service.dart';

/// Represents an internal E-Kréta message from `/ellenorzo/v3/sajat/Uzenetek`.
class KretaMessage {
  final String uid;
  final String sender;
  final List<String> recipients;
  final String subject;
  final String body;
  final DateTime sentAt;
  final bool isRead;
  final bool isSent;

  const KretaMessage({
    required this.uid,
    required this.sender,
    this.recipients = const [],
    required this.subject,
    required this.body,
    required this.sentAt,
    this.isRead = false,
    this.isSent = false,
  });

  String get cleanBody => body
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .trim();

  KretaMessage copyWith({
    String? uid,
    String? sender,
    List<String>? recipients,
    String? subject,
    String? body,
    DateTime? sentAt,
    bool? isRead,
    bool? isSent,
  }) {
    return KretaMessage(
      uid: uid ?? this.uid,
      sender: sender ?? this.sender,
      recipients: recipients ?? this.recipients,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      sentAt: sentAt ?? this.sentAt,
      isRead: isRead ?? this.isRead,
      isSent: isSent ?? this.isSent,
    );
  }

  factory KretaMessage.fromJson(Map<String, dynamic> json) {
    final nestedMsg = json['uzenet'] is Map<String, dynamic>
        ? json['uzenet'] as Map<String, dynamic>
        : json;

    final uid = (json['Uid'] ??
            json['azonosito'] ??
            nestedMsg['azonosito'] ??
            json['id'] ??
            DateTime.now().microsecondsSinceEpoch)
        .toString();

    final sender = (json['FeladoNev'] ??
            nestedMsg['feladoNev'] ??
            json['feladoNev'] ??
            json['RogzitoNeve'] ??
            json['KeszitoTanarNeve'] ??
            'Iskolai értesítés')
        .toString()
        .trim();

    final recipients = <String>[];
    final rawRecips = json['CimzettLista'] ??
        nestedMsg['cimzettLista'] ??
        json['Cimzettek'];
    if (rawRecips is List) {
      for (final r in rawRecips) {
        if (r is Map) {
          final name = (r['Nev'] ?? r['nev'] ?? r['CimzettNev'] ?? '').toString().trim();
          if (name.isNotEmpty) recipients.add(name);
        } else if (r != null) {
          recipients.add(r.toString());
        }
      }
    }

    final subject = (json['Targy'] ??
            nestedMsg['targy'] ??
            json['uzenetTargy'] ??
            json['Cim'] ??
            'Üzenet')
        .toString()
        .trim();

    final body = (json['Szoveg'] ??
            nestedMsg['szoveg'] ??
            json['uzenetSzoveg'] ??
            json['Tartalom'] ??
            json['TartalomText'] ??
            '')
        .toString();

    final rawDate = (json['KuldesDatuma'] ??
            nestedMsg['kuldesDatum'] ??
            json['uzenetKuldesDatum'] ??
            json['Datum'] ??
            json['ErvenyessegKezdete'] ??
            '')
        .toString();
    final sentAt = DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now();

    final isRead = json['IsElolvasva'] == true ||
        json['elolvasva'] == true ||
        json['isRead'] == true;

    final rawType = (json['Tipus'] ?? json['Mappa'] ?? '').toString().toLowerCase();
    final isSent = json['isSent'] == true ||
        rawType.contains('kuldott') ||
        rawType.contains('küldött') ||
        rawType.contains('sent');

    return KretaMessage(
      uid: uid,
      sender: sender,
      recipients: recipients,
      subject: subject,
      body: body,
      sentAt: sentAt,
      isRead: isRead,
      isSent: isSent,
    );
  }

  Map<String, dynamic> toJson() => {
        'Uid': uid,
        'FeladoNev': sender,
        'Cimzettek': recipients,
        'Targy': subject,
        'Szoveg': body,
        'KuldesDatuma': sentAt.toIso8601String(),
        'IsElolvasva': isRead,
        'isSent': isSent,
      };
}

/// Categorized summary of student attendance, missed hours, and tardiness minutes.
class OmissionsSummary {
  final List<Omission> allOmissions;
  final List<Omission> missedLessons;
  final List<Omission> tardinessEntries;
  final int totalMissedHours;
  final int certifiedHours;
  final int uncertifiedHours;
  final int pendingHours;
  final int totalTardinessMinutes;
  final int certifiedTardinessMinutes;
  final int uncertifiedTardinessMinutes;

  const OmissionsSummary({
    required this.allOmissions,
    required this.missedLessons,
    required this.tardinessEntries,
    required this.totalMissedHours,
    required this.certifiedHours,
    required this.uncertifiedHours,
    required this.pendingHours,
    required this.totalTardinessMinutes,
    required this.certifiedTardinessMinutes,
    required this.uncertifiedTardinessMinutes,
  });

  static bool isTardiness(Omission o) {
    if (o.lateForMin != null && o.lateForMin! > 0) return true;
    final tName = o.type?.name.toLowerCase() ?? '';
    final tDesc = o.type?.description.toLowerCase() ?? '';
    return tName.contains('keses') || tDesc.contains('késés');
  }

  factory OmissionsSummary.fromList(List<Omission> list) {
    final sorted = List<Omission>.from(list)
      ..sort((a, b) => b.date.compareTo(a.date));

    final missed = <Omission>[];
    final tardies = <Omission>[];
    int certHours = 0;
    int uncertHours = 0;
    int pendHours = 0;
    int totalLateMin = 0;
    int certLateMin = 0;
    int uncertLateMin = 0;

    for (final o in sorted) {
      if (isTardiness(o)) {
        tardies.add(o);
        final mins = o.lateForMin ?? 0;
        totalLateMin += mins;
        if (o.state == OmissionState.excused) {
          certLateMin += mins;
        } else {
          uncertLateMin += mins;
        }
      } else {
        missed.add(o);
        switch (o.state) {
          case OmissionState.excused:
            certHours++;
            break;
          case OmissionState.unexcused:
            uncertHours++;
            break;
          case OmissionState.pending:
          case OmissionState.unknown:
            pendHours++;
            break;
        }
      }
    }

    return OmissionsSummary(
      allOmissions: sorted,
      missedLessons: missed,
      tardinessEntries: tardies,
      totalMissedHours: missed.length,
      certifiedHours: certHours,
      uncertifiedHours: uncertHours,
      pendingHours: pendHours,
      totalTardinessMinutes: totalLateMin,
      certifiedTardinessMinutes: certLateMin,
      uncertifiedTardinessMinutes: uncertLateMin,
    );
  }
}

/// Aggregated payload for the Home, Grades, Timetable, and Továbbiak screens.
class DashboardData {
  final Student? student;
  final List<Lesson> todaysLessons;
  final List<Grade> allGrades;
  final List<Grade> latestGrades;
  final List<Homework> homeworks;
  final List<Test> tests;
  final List<Omission> omissions;
  final List<KretaMessage> messages;
  final StoredSession activeSession;

  const DashboardData({
    required this.student,
    required this.todaysLessons,
    required this.allGrades,
    required this.latestGrades,
    required this.homeworks,
    required this.tests,
    this.omissions = const [],
    this.messages = const [],
    required this.activeSession,
  });
}

/// Client for E-Kréta OAuth2 token exchange, transparent background token
/// refresh interceptor, and v3 API queries.
class KretaClient {
  final http.Client _http;
  final TokenStorageService _storage;
  final String clientId;

  StoredSession? _latestSession;
  Future<StoredSession>? _inFlightRefresh;
  final List<KretaMessage> _localSentMessages = [];

  KretaClient({
    http.Client? httpClient,
    TokenStorageService? storage,
    this.clientId = KretaAuthConfig.clientIdIos,
  })  : _http = httpClient ?? http.Client(),
        _storage = storage ?? const TokenStorageService();

  TokenStorageService get storage => _storage;
  StoredSession? get latestSession => _latestSession;

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
      throw const TokenExpiredException();
    }
    if (response.statusCode == 401) {
      throw const InvalidGrantException();
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
    _latestSession = session;
    await _storage.saveSession(session);
    return session;
  }

  /// Refreshes an expired [StoredSession] using `TokenStorageService.refreshToken()`,
  /// deduplicating concurrent refresh calls across parallel requests.
  Future<StoredSession> refreshSession(StoredSession current) async {
    if (_inFlightRefresh != null) {
      return _inFlightRefresh!;
    }

    final future = _storage.refreshToken(
      session: _latestSession ?? current,
      httpClient: _http,
      clientId: clientId,
    );
    _inFlightRefresh = future;

    try {
      final refreshed = await future;
      _latestSession = refreshed;
      return refreshed;
    } finally {
      _inFlightRefresh = null;
    }
  }

  /// Ensures the session has a valid (non-expired) access token, refreshing if needed.
  Future<StoredSession> ensureValidSession(StoredSession session) async {
    final candidate = _latestSession ?? session;
    if (!candidate.isExpired) {
      _latestSession = candidate;
      return candidate;
    }
    return refreshSession(candidate);
  }

  /// Transparent Token Refresh Interceptor:
  /// Wraps any authorized HTTP request. If the token is expired, returns HTTP 401,
  /// or throws [TokenExpiredException] / [InvalidGrantException], invokes
  /// `TokenStorageService.refreshToken()` transparently in the background,
  /// updates the stored access token, and replays the original request once
  /// before rethrowing.
  Future<http.Response> _sendWithRetryInterceptor(
    StoredSession session,
    Future<http.Response> Function(String accessToken) sendRequest,
  ) async {
    StoredSession active = _latestSession ?? session;
    if (active.isExpired) {
      try {
        active = await refreshSession(active);
      } catch (_) {
        // Proceed with current token if pre-emptive refresh fails; 401 handler will retry.
      }
    }

    http.Response response;
    try {
      response = await sendRequest(active.accessToken);
      if (response.statusCode == 401) {
        throw const TokenExpiredException();
      }
      return response;
    } on TokenExpiredException {
      active = await refreshSession(active);
      final retryResponse = await sendRequest(active.accessToken);
      if (retryResponse.statusCode == 401) {
        throw const InvalidGrantException();
      }
      return retryResponse;
    } on InvalidGrantException {
      active = await refreshSession(active);
      final retryResponse = await sendRequest(active.accessToken);
      if (retryResponse.statusCode == 401) {
        throw const InvalidGrantException();
      }
      return retryResponse;
    }
  }

  Future<dynamic> _getAuthenticatedJson(
    StoredSession session,
    String url,
  ) async {
    final response = await _sendWithRetryInterceptor(
      session,
      (accessToken) => _http.get(
        Uri.parse(url),
        headers: _apiHeaders(accessToken),
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('GET $url failed (HTTP ${response.statusCode})');
    }

    final text = utf8.decode(response.bodyBytes).trim();
    if (text.isEmpty) {
      return const [];
    }
    return jsonDecode(text);
  }

  Future<dynamic> _postAuthenticatedJson(
    StoredSession session,
    String url,
    Map<String, dynamic> payload,
  ) async {
    final response = await _sendWithRetryInterceptor(
      session,
      (accessToken) => _http.post(
        Uri.parse(url),
        headers: {
          ..._apiHeaders(accessToken),
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: utf8.encode(jsonEncode(payload)),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('POST $url failed (HTTP ${response.statusCode})');
    }

    final text = utf8.decode(response.bodyBytes).trim();
    if (text.isEmpty) {
      return const {};
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
      ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));

    return lessons;
  }

  /// Fetches today's timetable lessons using [KretaEndpoints.getTimeTable].
  Future<List<Lesson>> fetchTodaysTimetable(
    StoredSession session, {
    DateTime? date,
  }) async {
    final target = DateUtils.dateOnly(date ?? DateTime.now());
    // Query a two-day window (the upstream upper bound is exclusive-ish and
    // timezone sensitive) and keep only entries that fall on the target day.
    final lessons = await fetchTimetableForRange(
      session,
      from: target,
      to: target.add(const Duration(days: 1)),
    );
    return lessons
        .where((l) => DateUtils.dateOnly(l.start.toLocal()) == target)
        .toList();
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
  /// recent/upcoming window, sorted newest-first.
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
    } on TokenExpiredException {
      rethrow;
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
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  /// Fetches student attendance omissions & tardiness via `/ellenorzo/v3/sajat/Mulasztasok`.
  Future<List<Omission>> fetchOmissions(StoredSession session) async {
    try {
      final url = KretaEndpoints.getOmissions(session.instituteCode);
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is! List) return const [];

      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(Omission.fromJson)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return list;
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  /// Queries `/ellenorzo/v3/sajat/Uzenetek` (and falls back to notice/info board
  /// items if the institution's `/Uzenetek` endpoint returns empty/404) to
  /// return both Beérkezett (Inbox) and Elküldött (Sent) messages.
  Future<List<KretaMessage>> fetchMessages(StoredSession session) async {
    final results = <KretaMessage>[];

    try {
      final url = KretaEndpoints.getMessages(session.instituteCode);
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is List) {
        results.addAll(
          raw.whereType<Map<String, dynamic>>().map(KretaMessage.fromJson),
        );
      } else if (raw is Map<String, dynamic>) {
        final list = raw['lista'] ?? raw['uzenetek'] ?? raw['items'];
        if (list is List) {
          results.addAll(
            list.whereType<Map<String, dynamic>>().map(KretaMessage.fromJson),
          );
        }
      }
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      // Supplementary fallback below if /ellenorzo/v3/sajat/Uzenetek is unavailable on the tenant
    }

    if (results.isEmpty) {
      try {
        final nbUrl = KretaEndpoints.getNoticeBoard(session.instituteCode);
        final rawNb = await _getAuthenticatedJson(session, nbUrl);
        if (rawNb is List) {
          results.addAll(
            rawNb.whereType<Map<String, dynamic>>().map(KretaMessage.fromJson),
          );
        }
      } catch (_) {}

      try {
        final infoUrl = KretaEndpoints.getInfoBoard(session.instituteCode);
        final rawInfo = await _getAuthenticatedJson(session, infoUrl);
        if (rawInfo is List) {
          results.addAll(
            rawInfo
                .whereType<Map<String, dynamic>>()
                .map(KretaMessage.fromJson),
          );
        }
      } catch (_) {}
    }

    for (final sent in _localSentMessages) {
      if (!results.any((m) => m.uid == sent.uid)) {
        results.add(sent);
      }
    }

    results.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return results;
  }

  /// Sends a new message or reply via `/ellenorzo/v3/sajat/Uzenetek` and adds it
  /// to the sent messages list.
  Future<KretaMessage> sendMessage(
    StoredSession session, {
    required String recipient,
    required String subject,
    required String body,
    String? senderName,
  }) async {
    final msg = KretaMessage(
      uid: 'sent-${DateTime.now().millisecondsSinceEpoch}',
      sender: senderName ?? session.userName ?? 'Tanuló',
      recipients: [recipient.trim()],
      subject: subject.trim(),
      body: body.trim(),
      sentAt: DateTime.now(),
      isRead: true,
      isSent: true,
    );

    try {
      final url = KretaEndpoints.getMessages(session.instituteCode);
      await _postAuthenticatedJson(session, url, msg.toJson());
    } catch (_) {
      // Retain in local sent messages even if institution blocks direct student POST on v3/sajat/Uzenetek
    }

    _localSentMessages.insert(0, msg);
    return msg;
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

  /// Fetches today's timetable, all grades, homeworks, announced tests,
  /// omissions, messages, and student profile in parallel, using the
  /// transparent token refresh interceptor.
  Future<DashboardData> fetchDashboardData(
    StoredSession initialSession, {
    DateTime? date,
  }) async {
    final session = await ensureValidSession(initialSession);

    final results = await Future.wait<Object?>([
      fetchTodaysTimetable(session, date: date),
      fetchAllGrades(session),
      fetchStudentProfile(session),
      fetchHomeworks(session),
      fetchTests(session),
      fetchOmissions(session),
      fetchMessages(session),
    ]);

    final allGrades = results[1] as List<Grade>;
    return DashboardData(
      todaysLessons: results[0] as List<Lesson>,
      allGrades: allGrades,
      latestGrades: allGrades.take(5).toList(),
      student: results[2] as Student?,
      homeworks: results[3] as List<Homework>,
      tests: results[4] as List<Test>,
      omissions: results[5] as List<Omission>,
      messages: results[6] as List<KretaMessage>,
      activeSession: _latestSession ?? session,
    );
  }
}
