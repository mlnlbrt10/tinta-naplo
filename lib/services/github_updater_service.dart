import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';

/// Parsed metadata from `https://api.github.com/repos/mlnlbrt10/reKRETA/releases/latest`.
class GitHubReleaseInfo {
  final String tagName;
  final String title;
  final String releaseNotes;
  final String htmlUrl;
  final String? apkDownloadUrl;

  const GitHubReleaseInfo({
    required this.tagName,
    required this.title,
    required this.releaseNotes,
    required this.htmlUrl,
    this.apkDownloadUrl,
  });

  factory GitHubReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] ?? '').toString().trim();
    final name = (json['name'] ?? tag).toString().trim();
    final body = (json['body'] ?? '').toString().trim();
    final html = (json['html_url'] ??
            'https://github.com/mlnlbrt10/reKRETA/releases')
        .toString()
        .trim();

    String? apkUrl;
    final assets = json['assets'];
    if (assets is List) {
      for (final item in assets) {
        if (item is Map<String, dynamic>) {
          final assetName = (item['name'] ?? '').toString().toLowerCase();
          final downloadUrl =
              (item['browser_download_url'] ?? '').toString().trim();
          if (downloadUrl.isEmpty) continue;
          if (assetName == 'app-release.apk') {
            apkUrl = downloadUrl;
            break;
          }
          if (assetName.endsWith('.apk')) {
            apkUrl ??= downloadUrl;
          }
        }
      }
    }

    return GitHubReleaseInfo(
      tagName: tag,
      title: name.isNotEmpty ? name : tag,
      releaseNotes: body.isNotEmpty
          ? body
          : 'Hibajavítások és teljesítménybeli fejlesztések.',
      htmlUrl: html,
      apkDownloadUrl: apkUrl,
    );
  }
}

/// Service that checks GitHub Releases for `mlnlbrt10/reKRETA` and presents
/// an in-app frosted-glass OTA APK updater dialog.
class GitHubUpdaterService {
  static const String repoUrl = 'https://github.com/mlnlbrt10/reKRETA';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/mlnlbrt10/reKRETA/releases/latest';
  static const String fallbackAppVersion = '1.0.2';
  static const String fallbackBuildNumber = '2';

  static bool _hasCheckedOnStartup = false;

  /// Queries GitHub Releases API for the latest tag name, falling back to `v1.0.2`.
  static Future<String> fetchLatestReleaseTag({http.Client? httpClient}) async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse(latestReleaseApiUrl),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'reKRETA-Android-Updater',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final release = GitHubReleaseInfo.fromJson(decoded);
        if (release.tagName.isNotEmpty) {
          return release.tagName.startsWith('v')
              ? release.tagName
              : 'v${release.tagName}';
        }
      }
    } catch (_) {
      // Fallback below
    }
    return 'v$fallbackAppVersion';
  }

  /// Resolves `(version, buildNumber)` from [PackageInfo] with safe fallback.
  static Future<(String, String)> getAppVersionInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final rawVer = info.version.trim();
      final ver = rawVer.isNotEmpty
          ? _stripPrefix(rawVer)
          : fallbackAppVersion;
      final build = info.buildNumber.trim().isNotEmpty
          ? info.buildNumber.trim()
          : fallbackBuildNumber;
      return (ver, build);
    } catch (_) {
      return (fallbackAppVersion, fallbackBuildNumber);
    }
  }

  /// Returns `true` if [remoteTag] represents a strictly newer semantic version
  /// than [currentVersion].
  static bool isRemoteVersionNewer(String currentVersion, String remoteTag) {
    final cleanCurrent = _stripPrefix(currentVersion);
    final cleanRemote = _stripPrefix(remoteTag);
    if (cleanRemote.isEmpty || cleanRemote == cleanCurrent) {
      return false;
    }

    final curParts = _parseNumericParts(cleanCurrent);
    final remParts = _parseNumericParts(cleanRemote);

    for (int i = 0; i < 3; i++) {
      final c = i < curParts.length ? curParts[i] : 0;
      final r = i < remParts.length ? remParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }

    // If numeric X.Y.Z are equal, stable release is newer than pre-release (-alpha/-beta)
    final curHasPre = cleanCurrent.contains('-');
    final remHasPre = cleanRemote.contains('-');
    if (curHasPre && !remHasPre) {
      return true;
    }
    if (!curHasPre && remHasPre) {
      return false;
    }

    // If both have build metadata (+N), compare build numbers strictly
    final curBuild = _extractBuildNumber(currentVersion);
    final remBuild = _extractBuildNumber(remoteTag);
    if (curBuild != null && remBuild != null && remBuild > curBuild) {
      return true;
    }
    return false;
  }

  static int? _extractBuildNumber(String v) {
    final idx = v.indexOf('+');
    if (idx == -1 || idx + 1 >= v.length) return null;
    return int.tryParse(v.substring(idx + 1).trim());
  }

  static String _stripPrefix(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    final plusIdx = s.indexOf('+');
    if (plusIdx != -1) {
      s = s.substring(0, plusIdx);
    }
    return s;
  }

  static List<int> _parseNumericParts(String version) {
    final mainPart = version.split('-').first;
    return mainPart
        .split('.')
        .map((seg) => int.tryParse(seg.trim()) ?? 0)
        .toList();
  }

  /// Queries GitHub Releases API once on startup (or immediately when [manual]
  /// is true) and prompts the user with the frosted-glass OTA dialog if a
  /// newer version is available.
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool manual = false,
    http.Client? httpClient,
  }) async {
    if (!manual) {
      if (_hasCheckedOnStartup) return;
      _hasCheckedOnStartup = true;
    }

    final client = httpClient ?? http.Client();
    final (currentVersion, _) = await getAppVersionInfo();

    try {
      final response = await client
          .get(
            Uri.parse(latestReleaseApiUrl),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'reKRETA-Android-Updater',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (!context.mounted) return;

      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final release = GitHubReleaseInfo.fromJson(decoded);

        if (isRemoteVersionNewer(currentVersion, release.tagName)) {
          await showFrostedUpdateDialog(
            context,
            release: release,
            currentVersion: currentVersion,
          );
          return;
        }

        if (manual) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                uwu('A legfrissebb verziót használod (v$currentVersion)!'),
              ),
            ),
          );
        }
      } else if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uwu(
                response.statusCode == 404
                    ? 'Még nincs közzétett kiadás a GitHubon (v$currentVersion a legújabb).'
                    : 'Nem sikerült lekérdezni a frissítéseket (HTTP ${response.statusCode}).',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (manual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uwu('Hálózati hiba a GitHub frissítések ellenőrzésekor.'),
            ),
          ),
        );
      }
    }
  }

  /// Displays the frosted-glass OTA update modal with release notes and a
  /// direct "Frissítés most" APK download & install button.
  static Future<void> showFrostedUpdateDialog(
    BuildContext context, {
    required GitHubReleaseInfo release,
    required String currentVersion,
  }) {
    HapticFeedback.lightImpact();

    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierLabel: 'Bezárás',
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInOutCubic,
          );

          return AnimatedBuilder(
            animation: curved,
            builder: (context, child) {
              final t = curved.value.clamp(0.0, 1.0);
              final sigma = 12.0 * t;
              final scale = 0.92 + (0.08 * t);
              return ColoredBox(
                color: Colors.black.withValues(alpha: 0.52 * t),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: scale,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: _FrostedUpdateDialogContent(
              release: release,
              currentVersion: currentVersion,
            ),
          );
        },
      ),
    );
  }
}

class _FrostedUpdateDialogContent extends StatefulWidget {
  final GitHubReleaseInfo release;
  final String currentVersion;

  const _FrostedUpdateDialogContent({
    required this.release,
    required this.currentVersion,
  });

  @override
  State<_FrostedUpdateDialogContent> createState() =>
      _FrostedUpdateDialogContentState();
}

class _FrostedUpdateDialogContentState
    extends State<_FrostedUpdateDialogContent> {
  bool _isDownloading = false;
  double? _downloadProgress;
  String? _statusMessage;

  Future<void> _startOtaUpdate() async {
    final apkUrl = widget.release.apkDownloadUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      await _openFallbackUrl(widget.release.htmlUrl);
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = uwu('app-release.apk letöltése...');
    });

    try {
      OtaUpdate()
          .execute(apkUrl, destinationFilename: 'app-release.apk')
          .listen(
        (OtaEvent event) {
          if (!mounted) return;
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              final pct = double.tryParse(event.value ?? '');
              setState(() {
                _downloadProgress = pct != null ? (pct / 100.0).clamp(0.0, 1.0) : null;
                _statusMessage = pct != null
                    ? uwu('Letöltés folyamatban: ${pct.toStringAsFixed(0)}%')
                    : uwu('Letöltés folyamatban...');
              });
              break;
            case OtaStatus.INSTALLING:
              setState(() {
                _downloadProgress = 1.0;
                _statusMessage = uwu('Android csomagtelepítő indítása...');
              });
              break;
            case OtaStatus.ALREADY_RUNNING_ERROR:
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
            case OtaStatus.INSTALLATION_DONE:
            case OtaStatus.INSTALLATION_ERROR:
            case OtaStatus.CANCELED:
              if (event.status != OtaStatus.INSTALLATION_DONE) {
                _openFallbackUrl(apkUrl);
              }
              break;
          }
        },
        onError: (_) {
          _openFallbackUrl(apkUrl);
        },
      );
    } catch (_) {
      await _openFallbackUrl(apkUrl);
    }
  }

  Future<void> _openFallbackUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? const Color(0xFF141418).withValues(alpha: 0.90)
        : Colors.white.withValues(alpha: 0.92);

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: OledTheme.largeRadius,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.2),
                            borderRadius: OledTheme.badgeRadius,
                          ),
                          child: Icon(
                            Icons.system_update_rounded,
                            color: scheme.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                uwu('Új verzió érhető el!'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'v${widget.currentVersion} → ${widget.release.tagName}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_isDownloading)
                          TactileBounce(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Padding(
                              padding: EdgeInsets.all(6.0),
                              child: Icon(Icons.close_rounded),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.55),
                        borderRadius: OledTheme.cardRadius,
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.release.title,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.release.releaseNotes,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isDownloading) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: _downloadProgress,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _statusMessage!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (!_isDownloading) ...[
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(22),
                                ),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(uwu('Később')),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          flex: 2,
                          child: TactileBounce(
                            onTap: _isDownloading ? null : _startOtaUpdate,
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.download_rounded,
                                    size: 18,
                                    color: scheme.onPrimary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    uwu('Frissítés most'),
                                    style: TextStyle(
                                      color: scheme.onPrimary,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
