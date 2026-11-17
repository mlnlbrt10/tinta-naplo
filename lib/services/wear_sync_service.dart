import 'dart:async';

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
/// Data Layer (`WearSessionBridge`) to push active KRÉTA sessions and student
/// profile metadata to the paired Wear OS watch over `/tinta/auth_session`.
class WearSyncService {
  static const String channelName = 'hu.rekreta.rekreta_app/wear_sync';
  static const MethodChannel defaultChannel = MethodChannel(channelName);

  static final WearSyncService instance = WearSyncService();

  final MethodChannel _channel;
  VoidCallback? _onWatchAuthRequested;
  bool _handlerRegistered = false;

  WearSyncService({MethodChannel? channel})
      : _channel = channel ?? defaultChannel;

  MethodChannel get channel => _channel;

  void initialize({VoidCallback? onWatchAuthRequested}) {
    _onWatchAuthRequested = onWatchAuthRequested;
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onWatchAuthRequested') {
          _onWatchAuthRequested?.call();
        }
        return null;
      });
    } catch (_) {}
  }

  void disposeListener() {
    _onWatchAuthRequested = null;
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

  Map<String, Object?> _buildSessionPayload({
    required StoredSession session,
    Student? student,
    String? nickname,
    bool forceSync = false,
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
    };
  }

  Future<bool> cacheSessionSnapshot({
    required StoredSession session,
    Student? student,
    String? nickname,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'cacheSessionForWear',
        _buildSessionPayload(
          session: session,
          student: student,
          nickname: nickname,
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
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'pushSessionToWatch',
        _buildSessionPayload(
          session: session,
          student: student,
          nickname: nickname,
          forceSync: forceSync,
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
