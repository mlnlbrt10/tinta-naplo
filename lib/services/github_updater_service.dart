import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/glass_card.dart';

/// Parsed metadata from `https://api.github.com/repos/mlnlbrt10/tinta-naplo/releases/latest`.
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
            'https://github.com/mlnlbrt10/tinta-naplo/releases')
        .toString()
        .trim();

    String? apkUrl;
    final assets = json['assets'];
    if (assets is List) {
      final cleanVer = GitHubUpdaterService._stripPrefix(tag).toLowerCase();
      final expectedVersionedApk = cleanVer.isNotEmpty
          ? 'tinta-naplo-v$cleanVer.apk'
          : GitHubUpdaterService.defaultApkFileName.toLowerCase();
      String? brandedApkUrl;
      String? appReleaseApkUrl;
      String? anyApkUrl;
      for (final item in assets) {
        if (item is Map<String, dynamic>) {
          final assetName = (item['name'] ?? '').toString().toLowerCase();
          final downloadUrl =
              (item['browser_download_url'] ?? '').toString().trim();
          if (downloadUrl.isEmpty) continue;
          if (assetName == expectedVersionedApk) {
            apkUrl = downloadUrl;
            break;
          }
          if ((assetName.startsWith('tinta-naplo-v') ||
                  assetName.startsWith('tinta_naplo') ||
                  assetName.startsWith('tinta')) &&
              assetName.endsWith('.apk')) {
            brandedApkUrl ??= downloadUrl;
          } else if (assetName == 'app-release.apk') {
            appReleaseApkUrl ??= downloadUrl;
          } else if (assetName.endsWith('.apk')) {
            anyApkUrl ??= downloadUrl;
          }
        }
      }
      apkUrl ??= brandedApkUrl ?? appReleaseApkUrl ?? anyApkUrl;
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

/// Service that checks GitHub Releases for `mlnlbrt10/tinta-naplo` and presents
/// an in-app frosted-glass OTA APK updater dialog for Tinta Napló.
class GitHubUpdaterService {
  static const String repoUrl = 'https://github.com/mlnlbrt10/tinta-naplo';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/mlnlbrt10/tinta-naplo/releases/latest';
  static const String fallbackAppVersion = '1.0.0';
  static const String fallbackBuildNumber = '11';
  static const String defaultApkFileName = 'Tinta-Naplo-v1.0.0.apk';

  static bool _hasCheckedOnStartup = false;

  /// Resolves the target APK file name for a given release tag (`Tinta-Naplo-v1.0.0.apk`).
  static String apkFileNameForTag(String tagName) {
    final clean = _stripPrefix(tagName);
    if (clean.isEmpty) return defaultApkFileName;
    return 'Tinta-Naplo-v$clean.apk';
  }

  /// Queries GitHub Releases API for the latest tag name, falling back to `v1.0.0`.
  static Future<String> fetchLatestReleaseTag({http.Client? httpClient}) async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse(latestReleaseApiUrl),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'TintaNaplo-Android-Updater',
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

  static bool _hasTintaBranding(GitHubReleaseInfo release) {
    final titleLower = release.title.toLowerCase();
    final notesLower = release.releaseNotes.toLowerCase();
    final apkLower = (release.apkDownloadUrl ?? '').toLowerCase();
    return titleLower.contains('tinta napl') ||
        notesLower.contains('tinta napl') ||
        apkLower.contains('tinta-naplo') ||
        apkLower.contains('tinta_naplo') ||
        apkLower.contains('tinta');
  }

  /// Returns `true` if [remoteTag] represents a strictly newer semantic version
  /// than [currentVersion].
  ///
  /// After the v1.0.0 rebrand to Tinta Napló, legacy pre-rebrand `v1.1.x` and
  /// `v1.2.x` releases (or unbranded `reKRETA-*.apk` releases) are ignored so
  /// `v1.0.0` users are not prompted to install legacy pre-rebrand builds.
  static bool isRemoteVersionNewer(
    String currentVersion,
    String remoteTag, {
    GitHubReleaseInfo? release,
  }) {
    final cleanCurrent = _stripPrefix(currentVersion);
    final cleanRemote = _stripPrefix(remoteTag);
    if (cleanRemote.isEmpty || cleanRemote == cleanCurrent) {
      return false;
    }

    final curParts = _parseNumericParts(cleanCurrent);
    final remParts = _parseNumericParts(cleanRemote);
    final curMajor = curParts.isNotEmpty ? curParts[0] : 0;
    final curMinor = curParts.length > 1 ? curParts[1] : 0;
    final remMajor = remParts.isNotEmpty ? remParts[0] : 0;
    final remMinor = remParts.length > 1 ? remParts[1] : 0;

    if (release != null) {
      final hasTinta = _hasTintaBranding(release);
      final titleLower = release.title.toLowerCase();
      final apkLower = (release.apkDownloadUrl ?? '').toLowerCase();
      final looksLegacyReKreta = !hasTinta &&
          (apkLower.contains('rekreta-v') ||
              (titleLower.contains('rekreta') &&
                  !titleLower.contains('tinta')));
      if (looksLegacyReKreta) {
        return false;
      }
    }

    final hasExplicitTintaRelease =
        release != null && _hasTintaBranding(release);
    if (!hasExplicitTintaRelease &&
        curMajor == 1 &&
        curMinor == 0 &&
        remMajor == 1 &&
        (remMinor == 1 || remMinor == 2)) {
      return false;
    }

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
              'User-Agent': 'TintaNaplo-Android-Updater',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (!context.mounted) return;

      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final release = GitHubReleaseInfo.fromJson(decoded);

        if (isRemoteVersionNewer(
          currentVersion,
          release.tagName,
          release: release,
        )) {
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
          final fadeCurved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final scaleCurved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInOutCubic,
          );
          final barrierBase = resolveSoftBlurBarrierColor(
            dialogContext,
            solidDarkAlpha: 0.56,
            solidLightAlpha: 0.40,
          );

          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: fadeCurved,
                  builder: (context, _) => ColoredBox(
                    color: barrierBase.withValues(
                      alpha: barrierBase.a * fadeCurved.value.clamp(0.0, 1.0),
                    ),
                  ),
                ),
              ),
              ScaleTransition(
                scale: Tween<double>(begin: 0.90, end: 1.0).animate(scaleCurved),
                child: _FrostedUpdateDialogContent(
                  release: release,
                  currentVersion: currentVersion,
                  contentOpacityAnimation: fadeCurved,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FrostedUpdateDialogContent extends StatefulWidget {
  final GitHubReleaseInfo release;
  final String currentVersion;
  final Animation<double>? contentOpacityAnimation;

  const _FrostedUpdateDialogContent({
    required this.release,
    required this.currentVersion,
    this.contentOpacityAnimation,
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

    final targetApkFileName =
        GitHubUpdaterService.apkFileNameForTag(widget.release.tagName);

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusMessage = uwu('$targetApkFileName letöltése...');
    });

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(apkUrl));
      request.headers.set('User-Agent', 'TintaNaplo-Android-Updater');
      final response = await request.close();
      if (response.statusCode != 200) {
        client.close();
        await _showInstallError(
            'A letöltés sikertelen (HTTP ${response.statusCode}).', apkUrl);
        return;
      }
      final total = response.contentLength;
      Directory cacheDir;
      try {
        cacheDir = await getTemporaryDirectory();
      } catch (_) {
        cacheDir = Directory.systemTemp;
      }
      final file = File('${cacheDir.path}/$targetApkFileName');
      if (await file.exists()) await file.delete();
      final sink = file.openWrite();
      var received = 0;
      var lastPct = -1;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && mounted) {
          final pct = (received * 100 / total).floor();
          if (pct != lastPct) {
            lastPct = pct;
            setState(() {
              _downloadProgress = (pct / 100.0).clamp(0.0, 1.0);
              _statusMessage = uwu('Letöltés folyamatban: $pct%');
            });
          }
        }
      }
      await sink.flush();
      await sink.close();
      client.close();
      if (!mounted) return;
      setState(() {
        _downloadProgress = 1.0;
        _statusMessage = uwu('Android csomagtelepítő indítása...');
      });
      final res = await const MethodChannel('hu.rekreta.rekreta_app/updater')
          .invokeMethod<String>('installApk', {'filePath': file.path});
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadProgress = null;
        _statusMessage = res == 'permission_required'
            ? uwu('Engedélyezd az ismeretlen források telepítését, majd próbáld újra.')
            : null;
      });
    } catch (e) {
      await _showInstallError('Hiba a frissítés közben: $e', apkUrl);
    }
  }

  bool _errorShown = false;

  Future<void> _showInstallError(String message, String apkUrl) async {
    if (!mounted || _errorShown) return;
    _errorShown = true;
    setState(() {
      _isDownloading = false;
      _downloadProgress = null;
      _statusMessage = null;
    });
    final openBrowser = await showSoftBlurDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Frissítés sikertelen',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$message\n\nEngedélyezd az ismeretlen forrásból származó '
              'alkalmazások telepítését, vagy töltsd le az APK-t böngészővel.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Bezár'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Letöltés böngészőben'),
                ),
              ],
            ),
          ],
        );
      },
    );
    _errorShown = false;
    if (openBrowser == true) {
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
    final isSoftBlur = resolveSoftBlurEnabled();
    final cardBg = isDark
        ? const Color(0xFF141418).withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.97);

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Material(
              color: Colors.transparent,
              child: LiquidGlassSurface(
                padding: const EdgeInsets.all(22),
                borderRadius: OledTheme.largeRadius,
                solidColor: cardBg,
                contentOpacityAnimation: widget.contentOpacityAnimation,
                border: isSoftBlur
                    ? null
                    : Border.all(
                        color: scheme.primary.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.42),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
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
                        color: isSoftBlur
                            ? Colors.black.withValues(alpha: isDark ? 0.18 : 0.05)
                            : scheme.surfaceContainerHighest
                                .withValues(alpha: 0.55),
                        borderRadius: OledTheme.cardRadius,
                        border: Border.all(
                          color: isSoftBlur
                              ? Colors.white
                                  .withValues(alpha: isDark ? 0.14 : 0.22)
                              : theme.dividerColor,
                        ),
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
