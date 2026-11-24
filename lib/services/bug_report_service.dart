import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/oled_theme.dart';
import '../utils/platform_support.dart';
import '../utils/uwu_helper.dart';
import 'token_storage_service.dart';

/// Metadata describing an optional screenshot or screen recording attached to a
/// bug report.
class BugAttachment {
  final String path;
  final String name;
  final int sizeBytes;
  final bool isVideo;

  const BugAttachment({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.isVideo,
  });

  String get formattedSizeMb =>
      '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

/// Outcome of validating an optional media attachment on the client.
class AttachmentValidationResult {
  final BugAttachment? attachment;
  final String? errorMessage;

  const AttachmentValidationResult._({this.attachment, this.errorMessage});

  const AttachmentValidationResult.ok(BugAttachment value)
      : this._(attachment: value);

  const AttachmentValidationResult.error(String message)
      : this._(errorMessage: message);

  bool get isValid => attachment != null && errorMessage == null;
}

/// Outcome of submitting a bug report to `https://ticket.tintanaplo.hu/api/tickets`.
class BugReportSubmitResult {
  final bool success;
  final int? statusCode;
  final String? errorMessage;

  const BugReportSubmitResult._({
    required this.success,
    this.statusCode,
    this.errorMessage,
  });

  const BugReportSubmitResult.ok({int? statusCode})
      : this._(success: true, statusCode: statusCode);

  const BugReportSubmitResult.failure(
    String message, {
    int? statusCode,
  }) : this._(
          success: false,
          statusCode: statusCode,
          errorMessage: message,
        );
}

class _ProgressForwardingRequest extends http.BaseRequest {
  final Stream<List<int>> _stream;

  _ProgressForwardingRequest(
    super.method,
    super.url, {
    required Map<String, String> headers,
    required Stream<List<int>> stream,
    required int contentLength,
  }) : _stream = stream {
    this.headers.addAll(headers);
    this.contentLength = contentLength;
  }

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_stream);
  }
}

/// Privacy-first bug report serializer & uploader for `ticket.tintanaplo.hu`.
class BugReportService {
  BugReportService._();

  static const String endpointUrl = 'https://ticket.tintanaplo.hu/api/tickets';

  static const List<String> categories = <String>[
    'Hiba / Bug',
    'UI / Megjelenés',
    'Ötlet / Javaslat',
  ];

  static const int maxImageBytes = 10 * 1024 * 1024;
  static const int maxVideoBytes = 25 * 1024 * 1024;

  /// Privacy-masks the KRÉTA full student name so full surname and student
  /// identifiers are never sent: `"Albert Milán"` -> `"A. Milán"`,
  /// `"Nagy Anna Eszter"` -> `"N. Anna Eszter"`.
  static String maskReporterName(String? fullName) {
    final raw = fullName?.trim() ?? '';
    if (raw.isEmpty) return 'Névtelen felhasználó';
    final parts = raw.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Névtelen felhasználó';

    final firstRunes = parts.first.runes;
    if (firstRunes.isEmpty) return 'Névtelen felhasználó';
    final firstInitial = String.fromCharCode(firstRunes.first).toUpperCase();
    if (parts.length == 1) {
      return '$firstInitial.';
    }
    final givenNames = parts.sublist(1).join(' ');
    return '$firstInitial. $givenNames';
  }

  /// Concise description of the active theme, backdrop, and Liquid Glass mode.
  static String describeThemeMode(
    UserProfilePrefs prefs, {
    Brightness? platformBrightness,
  }) {
    final effective = prefs.effectiveForPlatform();
    if (isIOSPlatform) {
      final modeLabel = effective.followSystemTheme
          ? 'Rendszer'
          : (effective.themeStyle == AppThemeStyle.light
              ? 'Világos'
              : 'Sötét');
      return '$modeLabel • Liquid Glass';
    }
    final styleLabel = switch (effective.themeStyle) {
      AppThemeStyle.oledPureBlack => 'OLED Fekete',
      AppThemeStyle.standardDark => 'Sötét',
      AppThemeStyle.light => 'Világos',
    };
    final glassPart = effective.liquidGlassEnabled
        ? 'Liquid Glass (${effective.liquidGlassMode.label})'
        : 'Material mód';
    if (effective.hasAnimatedBackdrop) {
      return '$styleLabel • $glassPart • ${effective.animatedBackdropPreset.label}';
    }
    if (effective.hasCustomBackdrop) {
      return '$styleLabel • $glassPart • Saját háttér';
    }
    final preset = BackgroundPresetInfo.resolve(effective);
    if (preset.id != 'pure_oled') {
      return '$styleLabel • $glassPart • ${preset.label}';
    }
    return '$styleLabel • $glassPart';
  }

  /// Human-readable OS version label without collecting device serials or IDs.
  static String resolveOsVersionLabel() {
    if (kIsWeb) return 'Web';
    final osVer = Platform.operatingSystemVersion.trim();
    if (Platform.isIOS || isIOSPlatform) {
      return osVer.isNotEmpty ? 'iOS ($osVer)' : 'iOS';
    }
    if (Platform.isAndroid) {
      return osVer.isNotEmpty ? 'Android ($osVer)' : 'Android';
    }
    final osName = Platform.operatingSystem;
    return osVer.isNotEmpty ? '$osName ($osVer)' : osName;
  }

  /// Validates client-side size caps (`10 MB` images / `25 MB` videos).
  static AttachmentValidationResult validateAttachment({
    required String path,
    required String name,
    required int sizeBytes,
    required bool isVideo,
  }) {
    final limit = isVideo ? maxVideoBytes : maxImageBytes;
    final limitMb = isVideo ? 25 : 10;
    if (sizeBytes > limit) {
      final actualMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
      final mediaWord = isVideo ? 'videó' : 'kép';
      return AttachmentValidationResult.error(
        'A kiválasztott $mediaWord túl nagy ($actualMb MB). Maximum $limitMb MB csatolható.',
      );
    }
    return AttachmentValidationResult.ok(
      BugAttachment(
        path: path,
        name: name,
        sizeBytes: sizeBytes,
        isVideo: isVideo,
      ),
    );
  }

  /// Builds a clipboard-ready fallback summary if the user is offline or upload fails.
  static String buildCopyableDetails({
    required String reporter,
    required String category,
    required String description,
    required String appVersion,
    required String osVersion,
    required String themeMode,
    BugAttachment? attachment,
  }) {
    final buf = StringBuffer()
      ..writeln('${UwuHelper.brandName()} - Hibajelentés')
      ..writeln('Kategória: $category')
      ..writeln('Beküldő: $reporter')
      ..writeln('Verzió: $appVersion')
      ..writeln('Rendszer: $osVersion')
      ..writeln('Téma: $themeMode');
    if (attachment != null) {
      buf.writeln(
        'Csatolmány: ${attachment.name} (${attachment.formattedSizeMb})',
      );
    }
    buf
      ..writeln()
      ..writeln('Leírás:')
      ..writeln(description.trim());
    return buf.toString();
  }

  static bool _isTransientGatewayStatus(int code) =>
      code == 502 || code == 503 || code == 504 || (code >= 520 && code <= 524);

  /// Submits the bug report as `multipart/form-data` to [endpointUrl].
  ///
  /// Retries transient gateway errors (HTTP 502/503/504/52x) and temporary
  /// network/timeout failures up to [maxAttempts] times unless an immutable
  /// [attachmentFileOverride] stream is supplied.
  static Future<BugReportSubmitResult> submitTicket({
    required String reporter,
    required String category,
    required String description,
    required String appVersion,
    required String osVersion,
    required String themeMode,
    BugAttachment? attachment,
    void Function(double progress)? onProgress,
    http.Client? client,
    Duration timeout = const Duration(seconds: 25),
    int maxAttempts = 3,
    Duration retryDelay = const Duration(milliseconds: 600),
    http.MultipartFile? attachmentFileOverride,
  }) async {
    final ownClient = client == null;
    final httpClient = client ?? http.Client();
    final effectiveAttempts =
        attachmentFileOverride != null ? 1 : maxAttempts.clamp(1, 5);
    final endpointUri = Uri.parse(endpointUrl);

    try {
      for (int attempt = 1; attempt <= effectiveAttempts; attempt++) {
        try {
          final request = http.MultipartRequest('POST', endpointUri)
            ..headers['Accept'] = 'application/json'
            ..headers['X-Client'] = 'Tinta-Naplo'
            ..fields['reporter'] = reporter
            ..fields['category'] = category
            ..fields['description'] = description.trim()
            ..fields['app_version'] = appVersion
            ..fields['os_version'] = osVersion
            ..fields['theme_mode'] = themeMode;

          if (attachmentFileOverride != null) {
            request.files.add(attachmentFileOverride);
          } else if (attachment != null) {
            request.files.add(
              await http.MultipartFile.fromPath(
                'attachment',
                attachment.path,
                filename: attachment.name,
              ),
            );
          }

          final http.StreamedResponse streamed;
          if (onProgress != null && request.files.isNotEmpty) {
            final totalBytes = request.contentLength;
            final baseStream = request.finalize();
            var sentBytes = 0;
            final trackedStream = baseStream.transform(
              StreamTransformer<List<int>, List<int>>.fromHandlers(
                handleData: (chunk, sink) {
                  sentBytes += chunk.length;
                  if (totalBytes > 0) {
                    onProgress((sentBytes / totalBytes).clamp(0.0, 1.0));
                  }
                  sink.add(chunk);
                },
              ),
            );
            final forwarded = _ProgressForwardingRequest(
              request.method,
              request.url,
              headers: request.headers,
              stream: trackedStream,
              contentLength: totalBytes,
            );
            streamed = await httpClient.send(forwarded).timeout(timeout);
          } else {
            streamed = await httpClient.send(request).timeout(timeout);
          }

          await streamed.stream.drain<void>().timeout(timeout);
          if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
            return BugReportSubmitResult.ok(statusCode: streamed.statusCode);
          }
          if (_isTransientGatewayStatus(streamed.statusCode) &&
              attempt < effectiveAttempts) {
            if (retryDelay > Duration.zero) {
              await Future<void>.delayed(retryDelay * attempt);
            }
            continue;
          }
          return BugReportSubmitResult.failure(
            'A szerver hibát jelzett (HTTP ${streamed.statusCode}). Próbáld meg később, vagy másold ki a részleteket.',
            statusCode: streamed.statusCode,
          );
        } on TimeoutException {
          if (attempt < effectiveAttempts) {
            if (retryDelay > Duration.zero) {
              await Future<void>.delayed(retryDelay * attempt);
            }
            continue;
          }
          return const BugReportSubmitResult.failure(
            'A beküldés időtúllépés miatt megszakadt. Ellenőrizd az internetkapcsolatot.',
          );
        } on SocketException {
          if (attempt < effectiveAttempts) {
            if (retryDelay > Duration.zero) {
              await Future<void>.delayed(retryDelay * attempt);
            }
            continue;
          }
          return const BugReportSubmitResult.failure(
            'Nincs internetkapcsolat vagy a hibajelentő szerver nem elérhető.',
          );
        } on http.ClientException {
          if (attempt < effectiveAttempts) {
            if (retryDelay > Duration.zero) {
              await Future<void>.delayed(retryDelay * attempt);
            }
            continue;
          }
          return const BugReportSubmitResult.failure(
            'Hálózati hiba a beküldés közben. Másold ki a részleteket, hogy ne vesszen el.',
          );
        } catch (e) {
          return BugReportSubmitResult.failure(
            'Váratlan hiba történt: $e',
          );
        }
      }
      return const BugReportSubmitResult.failure(
        'Hálózati hiba a beküldés közben. Másold ki a részleteket, hogy ne vesszen el.',
      );
    } finally {
      if (ownClient) {
        httpClient.close();
      }
    }
  }
}
