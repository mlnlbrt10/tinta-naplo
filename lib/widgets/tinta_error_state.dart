import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import 'glass_card.dart';

/// Sleek, human-readable error & offline state card replacing raw Dart
/// `ClientException` / `SocketException` / stack-trace dumps across screens.
class TintaErrorState extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;
  final UserProfilePrefs? prefs;
  final String? titleOverride;
  final String? subtitleOverride;
  final bool compact;

  const TintaErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.prefs,
    this.titleOverride,
    this.subtitleOverride,
    this.compact = false,
  });

  /// Returns `true` when [error] represents an offline, DNS lookup, timeout,
  /// or HTTP socket failure rather than an unexpected server payload issue.
  static bool isNetworkError(Object? error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    final msg = (error?.toString() ?? '').toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('clientexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('connection closed') ||
        msg.contains('timed out') ||
        msg.contains('timeoutexception') ||
        msg.contains('handshakeexception') ||
        msg.contains('errno = 7') ||
        msg.contains('errno = 101') ||
        msg.contains('errno = 104');
  }

  /// Friendly Hungarian headline mapped from [error].
  static String friendlyTitleFor(Object? error) =>
      isNetworkError(error) ? 'Nincs internetkapcsolat' : 'Nem sikerült a betöltés';

  /// Friendly Hungarian description never exposing raw stack traces or URLs.
  static String friendlySubtitleFor(Object? error) =>
      'Nem sikerült betölteni az adatokat. Ellenőrizd a hálózati kapcsolatod, majd próbáld újra.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activePrefs = prefs ?? const UserProfilePrefs();
    final networkErr = isNetworkError(error);
    final iconAccent = networkErr ? const Color(0xFFF59E0B) : scheme.primary;
    final title = uwu(titleOverride ?? friendlyTitleFor(error));
    final subtitle = uwu(subtitleOverride ?? friendlySubtitleFor(error));

    return SoftGlassCard(
      prefs: activePrefs,
      borderRadius: OledTheme.cardRadius,
      padding: EdgeInsets.symmetric(
        horizontal: 18,
        vertical: compact ? 14 : 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: iconAccent.withValues(alpha: 0.30),
                  ),
                ),
                child: Icon(
                  networkErr ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
                  size: compact ? 20 : 22,
                  color: iconAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        height: 1.35,
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            SizedBox(height: compact ? 12 : 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  visualDensity: compact ? VisualDensity.compact : null,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  uwu('Újrapróbálás'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
