import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:kreta_api/kreta_api.dart';

import 'token_storage_service.dart';

class WearDeviceNode {
  final String id;
  final String displayName;
  final bool isNearby;

  const WearDeviceNode({
    required this.id,
    required this.displayName,
    this.isNearby = false,
  });

  factory WearDeviceNode.fromMap(Map<Object?, Object?> map) {
    return WearDeviceNode(
      id: (map['id'] ?? '').toString(),
      displayName: (map['displayName'] ?? 'Wear OS óra').toString(),
      isNearby: map['isNearby'] == true,
    );
  }
}

class WearConnectionStatus {
  final bool isConnected;
  final List<WearDeviceNode> nodes;
  final String? primaryDeviceName;
  final DateTime? lastSyncedAt;

  const WearConnectionStatus({
    required this.isConnected,
    this.nodes = const [],
    this.primaryDeviceName,
    this.lastSyncedAt,
  });

  static const WearConnectionStatus disconnected = WearConnectionStatus(
    isConnected: false,
  );

  String? get resolvedDeviceName {
    final primary = primaryDeviceName?.trim();
    if (primary != null && primary.isNotEmpty) return primary;
    if (nodes.isNotEmpty) {
      final first = nodes.first.displayName.trim();
      if (first.isNotEmpty) return first;
    }
    return null;
  }

  factory WearConnectionStatus.fromMap(Map<Object?, Object?> map) {
    final rawNodes = map['nodes'];
    final nodes = <WearDeviceNode>[];
    if (rawNodes is List) {
      for (final item in rawNodes) {
        if (item is Map<Object?, Object?>) {
          nodes.add(WearDeviceNode.fromMap(item));
        }
      }
    }
    final rawLastSync = map['lastSyncedAtMs'];
    DateTime? lastSynced;
    if (rawLastSync is num && rawLastSync > 0) {
      lastSynced = DateTime.fromMillisecondsSinceEpoch(rawLastSync.toInt());
    }
    final primary = map['primaryNodeName']?.toString().trim();
    return WearConnectionStatus(
      isConnected: map['isConnected'] == true || nodes.isNotEmpty,
      nodes: nodes,
      primaryDeviceName:
          (primary != null && primary.isNotEmpty) ? primary : null,
      lastSyncedAt: lastSynced,
    );
  }
}

/// Bridges the Flutter phone app (`:app`) with the native Android Wearable
/// Data Layer (`WearSessionBridge`) to push active KRÉTA sessions, student
/// profile metadata, recent grades (~5), and upcoming exams (~3) to the paired
/// Wear OS watch over `/tinta/auth_session` and `/tinta/dashboard_sync`.
class WearSyncService {
  static const String channelName = 'hu.mlnlbrt.tintanaplo/wear_sync';
  static const MethodChannel defaultChannel = MethodChannel(channelName);

  static final WearSyncService instance = WearSyncService();

  final MethodChannel _channel;
  VoidCallback? _onWatchAuthRequested;
  ValueChanged<StoredSession>? _onSessionUpdatedFromWatch;
  bool _handlerRegistered = false;

  WearSyncService({MethodChannel? channel})
      : _channel = channel ?? defaultChannel;

  MethodChannel get channel => _channel;

  static StoredSession? _parseNativeSessionMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final accessToken = raw['accessToken']?.toString().trim() ?? '';
    final refreshToken = raw['refreshToken']?.toString().trim() ?? '';
    final instituteCode = raw['instituteCode']?.toString().trim() ?? '';
    if (accessToken.isEmpty || refreshToken.isEmpty || instituteCode.isEmpty) {
      return null;
    }
    final userName = raw['userName']?.toString().trim();
    final rawExp = raw['expiresAtMs'];
    final expiresAtMs = rawExp is num
        ? rawExp.toInt()
        : int.tryParse(rawExp?.toString() ?? '') ?? 0;
    return StoredSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: raw['idToken']?.toString() ?? '',
      instituteCode: instituteCode,
      userName: (userName != null && userName.isNotEmpty) ? userName : null,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
    );
  }

  void initialize({
    VoidCallback? onWatchAuthRequested,
    ValueChanged<StoredSession>? onSessionUpdatedFromWatch,
  }) {
    _onWatchAuthRequested = onWatchAuthRequested;
    _onSessionUpdatedFromWatch = onSessionUpdatedFromWatch;
    if (_handlerRegistered) return;
    try {
      _channel.setMethodCallHandler((call) async {
        try {
          if (call.method == 'onWatchAuthRequested') {
            _onWatchAuthRequested?.call();
          } else if (call.method == 'onSessionUpdatedFromWatch') {
            final parsed = _parseNativeSessionMap(call.arguments);
            if (parsed != null) {
              _onSessionUpdatedFromWatch?.call(parsed);
            }
          }
        } catch (_) {}
        return null;
      });
      _handlerRegistered = true;
    } catch (_) {}
  }

  void disposeListener() {
    _onWatchAuthRequested = null;
    _onSessionUpdatedFromWatch = null;
    if (_handlerRegistered) {
      try {
        _channel.setMethodCallHandler(null);
      } catch (_) {}
      _handlerRegistered = false;
    }
  }

  Future<StoredSession?> loadCachedSessionFromNative() async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'getCachedSessionForPhone',
      );
      return _parseNativeSessionMap(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool> consumePendingWatchAuthRequest() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'consumePendingWatchAuthRequest',
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<WearConnectionStatus> getConnectionStatus() async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'getWearConnectionStatus',
      );
      if (raw is Map<Object?, Object?>) {
        return WearConnectionStatus.fromMap(raw);
      }
    } catch (_) {}
    return WearConnectionStatus.disconnected;
  }

  /// Selects the latest [limit] grades sorted newest-first and serializes them
  /// using KRÉTA JSON fields for the Wear OS companion cache.
  static String serializeRecentGradesJson(
    List<Grade> grades, {
    int limit = 5,
  }) {
    final sorted = List<Grade>.from(grades)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final recent = sorted.take(limit).map((g) => g.toJson()).toList();
    return jsonEncode(recent);
  }

  /// Selects the nearest [limit] upcoming exams (today or future) sorted
  /// chronologically and serializes them using KRÉTA JSON fields.
  static String serializeUpcomingExamsJson(
    List<Test> tests, {
    DateTime? now,
    int limit = 3,
  }) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final upcoming = tests.where((t) {
      final d = t.date.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(today);
    }).toList()
      ..sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        if (cmp != 0) return cmp;
        return a.lessonNumber.compareTo(b.lessonNumber);
      });
    return jsonEncode(upcoming.take(limit).map((t) => t.toJson()).toList());
  }

  Map<String, Object?> _buildSessionPayload({
    required StoredSession session,
    Student? student,
    String? nickname,
    bool forceSync = false,
    List<Grade>? recentGrades,
    List<Test>? upcomingExams,
  }) {
    final resolvedStudentName = (student?.name.trim().isNotEmpty ?? false)
        ? student!.name.trim()
        : (nickname?.trim() ?? '');
    return <String, Object?>{
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'idToken': session.idToken,
      'instituteCode': session.instituteCode,
      'userName': session.userName ?? '',
      'expiresAtMs': session.expiresAt.millisecondsSinceEpoch,
      'studentName': resolvedStudentName,
      'studentUid': student?.uid ?? '',
      'instituteName': student?.instituteName ?? '',
      'schoolYearUid': student?.schoolYearUID ?? '',
      'forceSync': forceSync,
      if (recentGrades != null)
        'recentGradesJson': serializeRecentGradesJson(recentGrades),
      if (upcomingExams != null)
        'upcomingExamsJson': serializeUpcomingExamsJson(upcomingExams),
    };
  }

  Future<bool> cacheSessionSnapshot({
    required StoredSession session,
    Student? student,
    String? nickname,
    List<Grade>? recentGrades,
    List<Test>? upcomingExams,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'cacheSessionForWear',
        _buildSessionPayload(
          session: session,
          student: student,
          nickname: nickname,
          recentGrades: recentGrades,
          upcomingExams: upcomingExams,
        ),
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> syncSessionToWatch({
    required StoredSession session,
    Student? student,
    String? nickname,
    bool forceSync = false,
    List<Grade>? recentGrades,
    List<Test>? upcomingExams,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'pushSessionToWatch',
        _buildSessionPayload(
          session: session,
          student: student,
          nickname: nickname,
          forceSync: forceSync,
          recentGrades: recentGrades,
          upcomingExams: upcomingExams,
        ),
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> syncDashboardToWatch({
    required StoredSession session,
    Student? student,
    String? nickname,
    required List<Grade> recentGrades,
    required List<Test> upcomingExams,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'pushDashboardToWatch',
        _buildSessionPayload(
          session: session,
          student: student,
          nickname: nickname,
          recentGrades: recentGrades,
          upcomingExams: upcomingExams,
        ),
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearWatchSession() async {
    try {
      await _channel.invokeMethod<bool>('clearWearSession');
    } catch (_) {}
  }
}
