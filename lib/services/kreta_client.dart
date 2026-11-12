import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show DateUtils;
import 'package:http/http.dart' as http;
import 'package:kreta_api/kreta_api.dart';
import 'package:path_provider/path_provider.dart';

import '../core/kreta_auth_config.dart';
import 'token_storage_service.dart';

/// Represents a downloadable file attachment on a Kréta e-Ügyintézés message.
class KretaMessageAttachment {
  final String id;
  final String fileName;

  const KretaMessageAttachment({
    required this.id,
    required this.fileName,
  });

  factory KretaMessageAttachment.fromJson(Map<String, dynamic> json) {
    final id = (json['azonosito'] ??
            json['Azonosito'] ??
            json['id'] ??
            json['Uid'] ??
            '')
        .toString()
        .trim();
    final fileName = (json['fajlNev'] ??
            json['FajlNev'] ??
            json['nev'] ??
            json['Nev'] ??
            json['fileName'] ??
            'csatolmany')
        .toString()
        .trim();
    return KretaMessageAttachment(
      id: id,
      fileName: fileName.isEmpty ? 'csatolmany' : fileName,
    );
  }

  Map<String, dynamic> toJson() => {
        'azonosito': id,
        'fajlNev': fileName,
      };
}

/// Represents a Kréta e-Ügyintézés message or school notice/system message.
class KretaMessage {
  final String uid;
  final String? messageId;
  final String sender;
  final String? senderTitle;
  final List<String> recipients;
  final String subject;
  final String body;
  final DateTime sentAt;
  final bool isRead;
  final bool isSent;
  final bool isSystemMessage;
  final bool hasAttachments;
  final List<KretaMessageAttachment> attachments;
  final bool detailsLoaded;

  const KretaMessage({
    required this.uid,
    this.messageId,
    required this.sender,
    this.senderTitle,
    this.recipients = const [],
    required this.subject,
    required this.body,
    required this.sentAt,
    this.isRead = false,
    this.isSent = false,
    this.isSystemMessage = false,
    this.hasAttachments = false,
    this.attachments = const [],
    this.detailsLoaded = true,
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
    String? messageId,
    String? sender,
    String? senderTitle,
    List<String>? recipients,
    String? subject,
    String? body,
    DateTime? sentAt,
    bool? isRead,
    bool? isSent,
    bool? isSystemMessage,
    bool? hasAttachments,
    List<KretaMessageAttachment>? attachments,
    bool? detailsLoaded,
  }) {
    return KretaMessage(
      uid: uid ?? this.uid,
      messageId: messageId ?? this.messageId,
      sender: sender ?? this.sender,
      senderTitle: senderTitle ?? this.senderTitle,
      recipients: recipients ?? this.recipients,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      sentAt: sentAt ?? this.sentAt,
      isRead: isRead ?? this.isRead,
      isSent: isSent ?? this.isSent,
      isSystemMessage: isSystemMessage ?? this.isSystemMessage,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      attachments: attachments ?? this.attachments,
      detailsLoaded: detailsLoaded ?? this.detailsLoaded,
    );
  }

  factory KretaMessage.fromJson(
    Map<String, dynamic> json, {
    bool? forceSent,
    bool isSystemMessage = false,
    bool? detailsLoaded,
  }) {
    final nestedMsg = json['uzenet'] is Map<String, dynamic>
        ? json['uzenet'] as Map<String, dynamic>
        : (json['Uzenet'] is Map<String, dynamic>
            ? json['Uzenet'] as Map<String, dynamic>
            : json);

    final uid = (json['Uid'] ??
            json['azonosito'] ??
            json['Azonosito'] ??
            nestedMsg['azonosito'] ??
            json['id'] ??
            DateTime.now().microsecondsSinceEpoch)
        .toString()
        .trim();

    final rawMsgId = json['uzenetAzonosito'] ??
        json['UzenetAzonosito'] ??
        (json.containsKey('uzenet') || json.containsKey('Uzenet')
            ? (nestedMsg['azonosito'] ?? nestedMsg['Azonosito'])
            : null);
    final parsedMsgId = rawMsgId?.toString().trim();
    final messageId =
        (parsedMsgId == null || parsedMsgId.isEmpty) ? null : parsedMsgId;

    final sender = (json['FeladoNev'] ??
            json['uzenetFeladoNev'] ??
            nestedMsg['feladoNev'] ??
            json['feladoNev'] ??
            json['RogzitoNeve'] ??
            json['KeszitoTanarNeve'] ??
            'Iskolai értesítés')
        .toString()
        .trim();

    final rawTitle = (json['uzenetFeladoTitulus'] ??
            nestedMsg['feladoTitulus'] ??
            json['feladoTitulus'] ??
            json['FeladoTitulus'] ??
            '')
        .toString()
        .trim();
    final senderTitle = rawTitle.isEmpty ? null : rawTitle;

    final recipients = <String>[];
    final rawRecips = json['CimzettLista'] ??
        nestedMsg['cimzettLista'] ??
        json['cimzettLista'] ??
        json['Cimzettek'];
    if (rawRecips is List) {
      for (final r in rawRecips) {
        if (r is Map) {
          final name =
              (r['Nev'] ?? r['nev'] ?? r['CimzettNev'] ?? '').toString().trim();
          if (name.isNotEmpty) recipients.add(name);
        } else if (r != null) {
          final name = r.toString().trim();
          if (name.isNotEmpty) recipients.add(name);
        }
      }
    }

    final subject = (json['Targy'] ??
            json['uzenetTargy'] ??
            nestedMsg['targy'] ??
            json['targy'] ??
            json['Cim'] ??
            'Üzenet')
        .toString()
        .trim();

    final body = (json['Szoveg'] ??
            nestedMsg['szoveg'] ??
            json['uzenetSzoveg'] ??
            json['TartalomFormazott'] ??
            json['TartalomText'] ??
            json['Tartalom'] ??
            '')
        .toString();

    final rawDate = (json['KuldesDatuma'] ??
            json['uzenetKuldesDatum'] ??
            nestedMsg['kuldesDatum'] ??
            json['kuldesDatum'] ??
            json['KeszitesDatuma'] ??
            json['Datum'] ??
            json['ErvenyessegKezdete'] ??
            '')
        .toString();
    final sentAt = DateTime.tryParse(rawDate)?.toLocal() ?? DateTime.now();

    final isRead = json['IsElolvasva'] == true ||
        json['isElolvasva'] == true ||
        json['elolvasva'] == true ||
        json['isOlvasott'] == true ||
        json['isRead'] == true;

    final tipusObj = json['tipus'] is Map
        ? json['tipus'] as Map
        : (json['Tipus'] is Map ? json['Tipus'] as Map : null);
    final rawType = [
      tipusObj?['kod'],
      tipusObj?['nev'],
      tipusObj?['Nev'],
      tipusObj?['Leiras'],
      json['Tipus'],
      json['tipus'],
      json['Mappa'],
      json['mappa'],
    ]
        .where((e) => e != null)
        .map((e) => e.toString().toLowerCase())
        .join(' ');
    final isSent = forceSent ??
        (json['isSent'] == true ||
            rawType.contains('elkuldott') ||
            rawType.contains('kuldott') ||
            rawType.contains('küldött') ||
            rawType.contains('sent'));

    final attachments = <KretaMessageAttachment>[];
    final rawAttachments = json['csatolmanyok'] ??
        nestedMsg['csatolmanyok'] ??
        json['Csatolmanyok'] ??
        nestedMsg['Csatolmanyok'];
    if (rawAttachments is List) {
      for (final a in rawAttachments) {
        if (a is Map<String, dynamic>) {
          final att = KretaMessageAttachment.fromJson(a);
          if (att.id.isNotEmpty || att.fileName.isNotEmpty) {
            attachments.add(att);
          }
        } else if (a is Map) {
          final att =
              KretaMessageAttachment.fromJson(Map<String, dynamic>.from(a));
          if (att.id.isNotEmpty || att.fileName.isNotEmpty) {
            attachments.add(att);
          }
        }
      }
    }

    final hasAttachments = json['hasCsatolmany'] == true ||
        json['HasCsatolmany'] == true ||
        nestedMsg['hasCsatolmany'] == true ||
        attachments.isNotEmpty;

    final isSummary = json.containsKey('uzenetTargy') ||
        json.containsKey('uzenetKuldesDatum') ||
        (json['uzenet'] is Map && json['detailsLoaded'] != true);
    final resolvedIsSystem =
        isSystemMessage || json['isSystemMessage'] == true;
    final resolvedDetailsLoaded =
        detailsLoaded ??
        (json['detailsLoaded'] is bool
            ? json['detailsLoaded'] as bool
            : (resolvedIsSystem || !isSummary));

    return KretaMessage(
      uid: uid,
      messageId: messageId,
      sender: sender,
      senderTitle: senderTitle,
      recipients: recipients,
      subject: subject,
      body: body,
      sentAt: sentAt,
      isRead: isRead,
      isSent: isSent,
      isSystemMessage: resolvedIsSystem,
      hasAttachments: hasAttachments,
      attachments: attachments,
      detailsLoaded: resolvedDetailsLoaded,
    );
  }

  Map<String, dynamic> toJson() => {
        'Uid': uid,
        if (messageId != null) 'uzenetAzonosito': messageId,
        'FeladoNev': sender,
        if (senderTitle != null) 'uzenetFeladoTitulus': senderTitle,
        'Cimzettek': recipients,
        'Targy': subject,
        'Szoveg': body,
        'KuldesDatuma': sentAt.toIso8601String(),
        'IsElolvasva': isRead,
        'isSent': isSent,
        if (isSystemMessage) 'isSystemMessage': true,
        'hasCsatolmany': hasAttachments,
        if (attachments.isNotEmpty)
          'csatolmanyok': attachments.map((a) => a.toJson()).toList(),
        'detailsLoaded': detailsLoaded,
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

  Map<String, dynamic> toJson() => {
        'cacheDate': DateUtils.dateOnly(DateTime.now()).toIso8601String(),
        if (student != null) 'student': student!.toJson(),
        'todaysLessons': todaysLessons.map((l) => l.toJson()).toList(),
        'allGrades': allGrades.map((g) => g.toJson()).toList(),
        'homeworks': homeworks.map((h) => h.toJson()).toList(),
        'tests': tests.map((t) => t.toJson()).toList(),
        'omissions': omissions.map((o) => o.toJson()).toList(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory DashboardData.fromJson(
    Map<String, dynamic> json,
    StoredSession session, {
    Set<String> readMessageIds = const {},
  }) {
    List<T> parseList<T>(
      Object? raw,
      T Function(Map<String, dynamic>) parser,
    ) {
      if (raw is! List) return <T>[];
      final out = <T>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          out.add(parser(item));
        } else if (item is Map) {
          out.add(parser(Map<String, dynamic>.from(item)));
        }
      }
      return out;
    }

    Student? student;
    final rawStudent = json['student'];
    if (rawStudent is Map<String, dynamic>) {
      student = Student.fromJson(rawStudent);
    } else if (rawStudent is Map) {
      student = Student.fromJson(Map<String, dynamic>.from(rawStudent));
    }

    final todayStr = DateUtils.dateOnly(DateTime.now()).toIso8601String();
    final cacheDateStr = json['cacheDate']?.toString();
    final isSameDay = cacheDateStr == todayStr;

    final allGrades = parseList(json['allGrades'], Grade.fromJson);
    final rawMessages = parseList(json['messages'], KretaMessage.fromJson);
    final messages = readMessageIds.isEmpty
        ? rawMessages
        : rawMessages
            .map((m) => (m.isRead ||
                    readMessageIds.contains(m.uid) ||
                    (m.messageId != null &&
                        readMessageIds.contains(m.messageId!)))
                ? (m.isRead ? m : m.copyWith(isRead: true))
                : m)
            .toList();

    return DashboardData(
      student: student,
      todaysLessons:
          isSameDay ? parseList(json['todaysLessons'], Lesson.fromJson) : const [],
      allGrades: allGrades,
      latestGrades: allGrades.take(5).toList(),
      homeworks: parseList(json['homeworks'], Homework.fromJson),
      tests: parseList(json['tests'], Test.fromJson),
      omissions: parseList(json['omissions'], Omission.fromJson),
      messages: messages,
      activeSession: session,
    );
  }
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

  Map<String, String> _eugyintezesHeaders(String accessToken) => {
        'Accept': 'application/json, text/plain, */*',
        'User-Agent': KretaAuthConfig.userAgent,
        'Authorization': 'Bearer $accessToken',
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

  Future<dynamic> _getEugyintezesJson(
    StoredSession session,
    String url,
  ) async {
    final response = await _sendWithRetryInterceptor(
      session,
      (accessToken) => _http.get(
        Uri.parse(url),
        headers: _eugyintezesHeaders(accessToken),
      ),
    );

    if (response.statusCode != 200) {
      return null;
    }

    final text = utf8.decode(response.bodyBytes).trim();
    if (text.isEmpty) {
      return const [];
    }
    return jsonDecode(text);
  }

  Future<bool> _postOrPutEugyintezes(
    StoredSession session,
    String url,
    Map<String, dynamic> payload,
  ) async {
    final encodedBody = utf8.encode(jsonEncode(payload));
    var response = await _sendWithRetryInterceptor(
      session,
      (accessToken) => _http.post(
        Uri.parse(url),
        headers: {
          ..._eugyintezesHeaders(accessToken),
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: encodedBody,
      ),
    );

    if (response.statusCode == 405) {
      response = await _sendWithRetryInterceptor(
        session,
        (accessToken) => _http.put(
          Uri.parse(url),
          headers: {
            ..._eugyintezesHeaders(accessToken),
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: encodedBody,
        ),
      );
    }

    return response.statusCode >= 200 && response.statusCode < 300;
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

  /// Returns September 1 of the current school year (matching Firka's `getFirstSchoolDay()`).
  static DateTime getFirstSchoolDay([DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final sept1 = DateTime(now.year, 9, 1);
    if (now.isBefore(sept1)) {
      return DateTime(now.year - 1, 9, 1);
    }
    return sept1;
  }

  /// Fetches all student evaluations via [KretaEndpoints.getGrades] sorted
  /// newest-first by `recordedAt` (`KeszitesDatuma` / `RogzitesDatuma`).
  Future<List<Grade>> fetchAllGrades(StoredSession session) async {
    final url = KretaEndpoints.getGrades(session.instituteCode);
    final raw = await _getAuthenticatedJson(session, url);
    if (raw is! List) {
      return const [];
    }

    final grades = <Grade>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        try {
          grades.add(Grade.fromJson(item));
        } catch (_) {}
      }
    }
    grades.sort((a, b) {
      final cmp = b.recordedAt.compareTo(a.recordedAt);
      if (cmp != 0) return cmp;
      return b.recordDate.compareTo(a.recordDate);
    });

    return grades;
  }

  /// Fetches homework assignments via [KretaEndpoints.getHomework] using
  /// Firka's exact query parameters (`datumTol` = first school day, `datumIg` = null),
  /// sorted newest-first.
  Future<List<Homework>> fetchHomeworks(
    StoredSession session, {
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      DateTime? effectiveFrom = from;
      final DateTime? effectiveTo = to;
      if (effectiveFrom == null && effectiveTo == null) {
        effectiveFrom = getFirstSchoolDay();
      }
      final url = KretaEndpoints.getHomework(
        session.instituteCode,
        effectiveFrom,
        effectiveTo,
      );
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is! List) return const [];

      final list = <Homework>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          try {
            list.add(Homework.fromJson(item));
          } catch (_) {}
        }
      }
      list.sort((a, b) => b.creationDate.compareTo(a.creationDate));
      return list;
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  /// Fetches a single homework entry by its `HaziFeladatUid` (`/ellenorzo/v3/sajat/HaziFeladatok/{uid}`)
  /// when referenced by a timetable [Lesson].
  Future<Homework?> fetchHomeworkByUid(
    StoredSession session,
    String homeworkUid,
  ) async {
    final trimmed = homeworkUid.trim();
    if (trimmed.isEmpty) return null;
    final cleanId = trimmed.split(',').first.trim();
    if (cleanId.isEmpty) return null;
    try {
      final base = KretaEndpoints.getHomework(session.instituteCode);
      final url = '$base/${Uri.encodeComponent(cleanId)}';
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is Map<String, dynamic>) {
        return Homework.fromJson(raw);
      }
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {}
    return null;
  }

  /// Matches a [Lesson] to its corresponding [Homework] from [homeworks]
  /// using Firka's `UidObj.id` (`homeworkUid`) or subject+date matching.
  static Homework? findHomeworkForLesson(
    Lesson lesson,
    Iterable<Homework> homeworks,
  ) {
    final hwUid = lesson.homeworkUid?.trim() ?? '';
    if (hwUid.isNotEmpty) {
      final targetId = UidObj(uid: hwUid).id;
      final targetLead = hwUid.split(',').first.trim();
      for (final hw in homeworks) {
        final hwLead = hw.uid.split(',').first.trim();
        if (hw.uid == hwUid ||
            (targetLead.isNotEmpty && hwLead == targetLead) ||
            hw.id == targetId) {
          return hw;
        }
      }
    }

    // Fallback: match by subject and lesson date (assigned on or due on this lesson's date)
    final lessonDay = DateUtils.dateOnly(lesson.start.toLocal());
    final lessonSubjUid = lesson.subject?.uid.trim() ?? '';
    final lessonSubjName =
        (lesson.subject?.name ?? lesson.name).trim().toLowerCase();
    if (lessonSubjUid.isEmpty && lessonSubjName.isEmpty) return null;

    for (final hw in homeworks) {
      final sameSubj = (lessonSubjUid.isNotEmpty &&
              hw.subject.uid.trim() == lessonSubjUid) ||
          (lessonSubjName.isNotEmpty &&
              (hw.subject.name.trim().toLowerCase() == lessonSubjName ||
                  hw.subjectName.trim().toLowerCase() == lessonSubjName));
      if (!sameSubj) continue;
      final startDay = DateUtils.dateOnly(hw.startDate.toLocal());
      final dueDay = DateUtils.dateOnly(hw.dueDate.toLocal());
      if (startDay == lessonDay || dueDay == lessonDay) {
        return hw;
      }
    }
    return null;
  }

  /// Fetches announced tests/exams via [KretaEndpoints.getTests], sorted newest-first.
  Future<List<Test>> fetchTests(StoredSession session) async {
    try {
      final url = KretaEndpoints.getTests(session.instituteCode);
      final raw = await _getAuthenticatedJson(session, url);
      if (raw is! List) return const [];

      final list = <Test>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          try {
            list.add(Test.fromJson(item));
          } catch (_) {}
        }
      }
      list.sort((a, b) => b.date.compareTo(a.date));
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

  List<Map<String, dynamic>> _extractMessageMaps(dynamic raw) {
    final Iterable<dynamic> items;
    if (raw is List) {
      items = raw;
    } else if (raw is Map) {
      final list = raw['lista'] ??
          raw['uzenetek'] ??
          raw['postaladaElemek'] ??
          raw['items'] ??
          raw['data'] ??
          raw['result'];
      items = list is List ? list : const [];
    } else {
      items = const [];
    }
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['isToroltElem'] != true)
        .toList();
  }

  KretaMessage _mergeMessages(KretaMessage existing, KretaMessage incoming) {
    final preferIncomingBody =
        incoming.cleanBody.length > existing.cleanBody.length ||
            (incoming.body.isNotEmpty && existing.body.isEmpty);
    return existing.copyWith(
      messageId: existing.messageId ?? incoming.messageId,
      sender: existing.sender == 'Iskolai értesítés' && incoming.sender.isNotEmpty
          ? incoming.sender
          : existing.sender,
      senderTitle:
          (existing.senderTitle == null || existing.senderTitle!.isEmpty)
              ? incoming.senderTitle
              : existing.senderTitle,
      recipients: incoming.recipients.length > existing.recipients.length
          ? incoming.recipients
          : existing.recipients,
      subject: (existing.subject == 'Üzenet' && incoming.subject.isNotEmpty)
          ? incoming.subject
          : existing.subject,
      body: preferIncomingBody ? incoming.body : existing.body,
      sentAt: incoming.sentAt.isAfter(existing.sentAt)
          ? incoming.sentAt
          : existing.sentAt,
      isRead: existing.isRead || incoming.isRead,
      isSent: existing.isSent || incoming.isSent,
      hasAttachments: existing.hasAttachments || incoming.hasAttachments,
      attachments: incoming.attachments.length > existing.attachments.length
          ? incoming.attachments
          : existing.attachments,
      detailsLoaded: existing.detailsLoaded || incoming.detailsLoaded,
    );
  }

  Future<List<KretaMessage>> _safeFetchEugyintezesFolder(
    StoredSession session,
    String url, {
    bool? forceSent,
    bool rethrowAuthErrors = false,
  }) async {
    try {
      final raw = await _getEugyintezesJson(session, url);
      if (raw == null) return const [];
      return _extractMessageMaps(raw)
          .map(
            (m) => KretaMessage.fromJson(
              m,
              forceSent: forceSent,
              detailsLoaded: false,
            ),
          )
          .toList();
    } on TokenExpiredException {
      if (rethrowAuthErrors) rethrow;
      return const [];
    } on InvalidGrantException {
      if (rethrowAuthErrors) rethrow;
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<KretaMessage>> _safeFetchSystemBoard(
    StoredSession session,
    String url,
  ) async {
    try {
      final raw = await _getAuthenticatedJson(session, url);
      return _extractMessageMaps(raw)
          .map(
            (m) => KretaMessage.fromJson(
              m,
              forceSent: false,
              isSystemMessage: true,
              detailsLoaded: true,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetches ALL student messages by combining Kréta e-Ügyintézés mailbox
  /// endpoints (`/postaladaelemek/sajat`, `/beerkezett`, `/elkuldott`) with
  /// school noticeboard and infoboard system messages (`FaliujsagElemek` and
  /// `Feljegyzesek`), deduplicating, applying local read persistence, and
  /// sorting newest-first chronologically.
  Future<List<KretaMessage>> fetchMessages(StoredSession session) async {
    final sources = await Future.wait<List<KretaMessage>>([
      _safeFetchEugyintezesFolder(
        session,
        KretaEndpoints.getEugyintezesSajatMessages(),
        rethrowAuthErrors: true,
      ),
      _safeFetchEugyintezesFolder(
        session,
        KretaEndpoints.getEugyintezesInboxMessages(),
        forceSent: false,
      ),
      _safeFetchEugyintezesFolder(
        session,
        KretaEndpoints.getEugyintezesSentMessages(),
        forceSent: true,
      ),
      _safeFetchSystemBoard(
        session,
        KretaEndpoints.getNoticeBoard(session.instituteCode),
      ),
      _safeFetchSystemBoard(
        session,
        KretaEndpoints.getInfoBoard(session.instituteCode),
      ),
    ]);

    final byKey = <String, KretaMessage>{};
    void putMessage(String key, KretaMessage msg) {
      final existing = byKey[key];
      byKey[key] = existing == null ? msg : _mergeMessages(existing, msg);
    }

    for (final msg in [...sources[0], ...sources[1], ...sources[2]]) {
      putMessage('msg:${msg.uid}', msg);
    }
    for (final sysMsg in [...sources[3], ...sources[4]]) {
      putMessage('sys:${sysMsg.uid}', sysMsg);
    }

    final accountKey = TokenStorageService.accountKeyForSession(session);
    final localReadIds =
        await _storage.loadReadMessageIds(accountKey: accountKey);

    final results = <KretaMessage>[];
    for (final msg in byKey.values) {
      final isLocallyRead = localReadIds.contains(msg.uid) ||
          (msg.messageId != null && localReadIds.contains(msg.messageId)) ||
          (msg.isSystemMessage && localReadIds.contains('sys:${msg.uid}'));
      results.add(
        isLocallyRead && !msg.isRead ? msg.copyWith(isRead: true) : msg,
      );
    }

    for (final sent in _localSentMessages) {
      if (!results.any((m) => m.uid == sent.uid)) {
        results.add(sent);
      }
    }

    results.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return results;
  }

  /// Fetches full body, recipients, and attachment metadata for a single
  /// e-Ügyintézés mailbox item (`/postaladaelemek/{id}`).
  Future<KretaMessage> fetchMessageDetail(
    StoredSession session,
    KretaMessage message,
  ) async {
    if (message.isSystemMessage) {
      return message.copyWith(detailsLoaded: true);
    }

    dynamic raw;
    try {
      raw = await _getEugyintezesJson(
        session,
        KretaEndpoints.getEugyintezesMessageDetail(message.uid),
      );
      if (raw is! Map) {
        raw = await _getEugyintezesJson(
          session,
          KretaEndpoints.getEugyintezesMessageDetailV1(message.uid),
        );
      }
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      raw = null;
    }

    if (raw is! Map) {
      return message;
    }

    final detailed = KretaMessage.fromJson(
      Map<String, dynamic>.from(raw),
      forceSent: message.isSent,
      detailsLoaded: true,
    );
    return _mergeMessages(
      message,
      detailed.copyWith(detailsLoaded: true),
    );
  }

  /// Marks [message] as read both locally in persistent secure storage and on
  /// the Kréta e-Ügyintézés server (`/kommunikacio/uzenetek/olvasott`).
  Future<void> markMessageAsRead(
    StoredSession session,
    KretaMessage message,
  ) async {
    final accountKey = TokenStorageService.accountKeyForSession(session);
    final localKeys = <String>[
      message.uid,
      if (message.messageId != null && message.messageId!.isNotEmpty)
        message.messageId!,
      if (message.isSystemMessage) 'sys:${message.uid}',
    ];
    await _storage.markMessagesReadLocally(
      localKeys,
      accountKey: accountKey,
    );

    if (message.isSystemMessage || message.isSent) {
      return;
    }

    final rawTargetId = (message.messageId?.trim().isNotEmpty == true)
        ? message.messageId!.trim()
        : message.uid.trim();
    if (rawTargetId.isEmpty) return;

    final serializedId = int.tryParse(rawTargetId) ?? rawTargetId;
    final payload = <String, dynamic>{
      'isOlvasott': true,
      'uzenetAzonositoLista': [serializedId],
    };

    try {
      final ok = await _postOrPutEugyintezes(
        session,
        KretaEndpoints.getMarkMessagesReadUrl(),
        payload,
      );
      if (!ok) {
        await _postOrPutEugyintezes(
          session,
          KretaEndpoints.getMarkMessagesReadV1Url(),
          payload,
        );
      }
    } on TokenExpiredException {
      rethrow;
    } on InvalidGrantException {
      rethrow;
    } catch (_) {
      // Persistent local read state already saved above.
    }
  }

  /// Downloads an attachment from Kréta e-Ügyintézés into temporary cache storage.
  Future<File> downloadMessageAttachment(
    StoredSession session,
    KretaMessageAttachment attachment, {
    Directory? targetDirectory,
  }) async {
    final urls = [
      KretaEndpoints.getEugyintezesAttachmentUrl(attachment.id),
      KretaEndpoints.getEugyintezesAttachmentMobileUrl(attachment.id),
    ];

    http.Response? successfulResponse;
    int lastStatus = 0;
    for (final url in urls) {
      final response = await _sendWithRetryInterceptor(
        session,
        (accessToken) => _http.get(
          Uri.parse(url),
          headers: _eugyintezesHeaders(accessToken),
        ),
      );
      lastStatus = response.statusCode;
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        successfulResponse = response;
        break;
      }
    }

    if (successfulResponse == null) {
      throw Exception(
        'Csatolmány letöltése sikertelen (HTTP $lastStatus)',
      );
    }

    final dir = targetDirectory ?? await getTemporaryDirectory();
    final rawName =
        attachment.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    final safeName = rawName.isEmpty ? 'csatolmany.bin' : rawName;
    final safeId =
        attachment.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final prefix = safeId.isEmpty ? 'att' : 'att_$safeId';
    final file = File('${dir.path}/${prefix}_$safeName');
    await file.writeAsBytes(successfulResponse.bodyBytes, flush: true);
    return file;
  }

  /// Sends a new message or reply via e-Ügyintézés and adds it to sent history.
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
      detailsLoaded: true,
    );

    final payload = <String, dynamic>{
      'targy': msg.subject,
      'szoveg': msg.body,
      'cimzettLista': const [],
      'csatolmanyok': const [],
    };
    try {
      final ok = await _postOrPutEugyintezes(
        session,
        KretaEndpoints.getSendEugyintezesMessageUrl(),
        payload,
      );
      if (!ok) {
        await _postOrPutEugyintezes(
          session,
          KretaEndpoints.getSendEugyintezesMessageV1Url(),
          payload,
        );
      }
    } catch (_) {
      // Retain in local sent messages if direct free-text POST is unsupported.
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

    final todaysLessons = results[0] as List<Lesson>;
    final allGrades = results[1] as List<Grade>;
    final homeworks = List<Homework>.from(results[3] as List<Homework>);

    // Ensure any homeworkUid referenced on today's lessons is hydrated
    final missingHwUids = <String>{};
    for (final lesson in todaysLessons) {
      final hwUid = lesson.homeworkUid?.trim() ?? '';
      if (hwUid.isNotEmpty && findHomeworkForLesson(lesson, homeworks) == null) {
        missingHwUids.add(hwUid);
      }
    }
    if (missingHwUids.isNotEmpty) {
      final fetched = await Future.wait(
        missingHwUids.map((uid) => fetchHomeworkByUid(session, uid)),
      );
      for (final hw in fetched) {
        if (hw != null && !homeworks.any((h) => h.uid == hw.uid || h.id == hw.id)) {
          homeworks.add(hw);
        }
      }
      homeworks.sort((a, b) => b.creationDate.compareTo(a.creationDate));
    }

    final payload = DashboardData(
      todaysLessons: todaysLessons,
      allGrades: allGrades,
      latestGrades: allGrades.take(5).toList(),
      student: results[2] as Student?,
      homeworks: homeworks,
      tests: results[4] as List<Test>,
      omissions: results[5] as List<Omission>,
      messages: results[6] as List<KretaMessage>,
      activeSession: _latestSession ?? session,
    );
    await saveCachedDashboard(payload);
    return payload;
  }

  /// Loads cached dashboard payload from secure local storage so Főoldal can
  /// render cached cards immediately while background API sync completes.
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async {
    try {
      final acctKey = TokenStorageService.accountKeyForSession(session);
      final raw = await _storage.loadDashboardCacheJson(acctKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final readIds = await _storage.loadReadMessageIds(accountKey: acctKey);
      return DashboardData.fromJson(
        Map<String, dynamic>.from(decoded),
        session,
        readMessageIds: readIds,
      );
    } catch (_) {
      return null;
    }
  }

  /// Persists [data] per account for zero-wait startup rendering.
  Future<void> saveCachedDashboard(DashboardData data) async {
    try {
      final acctKey =
          TokenStorageService.accountKeyForSession(data.activeSession);
      await _storage.saveDashboardCacheJson(acctKey, jsonEncode(data.toJson()));
    } catch (_) {}
  }
}
