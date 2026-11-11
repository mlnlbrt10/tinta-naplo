import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/github_updater_service.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';

/// Dedicated "Az alkalmazásról" (About App / Rendszer & Névjegy) screen with:
/// - App icon (`AppBrandIconBadge`), name ('reKRETA'), semantic version ('v1.2.1'),
///   and developer credits.
/// - Direct link to `https://github.com/mlnlbrt10/reKRETA`.
/// - Manual "Frissítések keresése" button (GitHub Releases OTA updater).
/// - 5-tap secret Easter egg on the version text to unlock "Fejlesztői beállítások"
///   with "UwU mód" and "Tsundere mód" toggles.
class AboutAppScreen extends StatefulWidget {
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;

  const AboutAppScreen({
    super.key,
    required this.prefs,
    required this.onPrefsChanged,
  });

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  String _version = GitHubUpdaterService.fallbackAppVersion;
  int _versionTapCount = 0;
  DateTime? _lastTapTime;
  bool _isCheckingUpdates = false;

  late UserProfilePrefs _currentPrefs;

  @override
  void initState() {
    super.initState();
    _currentPrefs = widget.prefs;
    _loadPackageVersion();
  }

  @override
  void didUpdateWidget(covariant AboutAppScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _currentPrefs = widget.prefs;
  }

  Future<void> _loadPackageVersion() async {
    final (ver, _) = await GitHubUpdaterService.getAppVersionInfo();
    if (!mounted) return;
    setState(() {
      _version = ver;
    });
  }

  void _updatePrefs(UserProfilePrefs nextPrefs) {
    setState(() => _currentPrefs = nextPrefs);
    widget.onPrefsChanged(nextPrefs);
  }

  void _handleVersionTap() {
    final now = DateTime.now();
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!) > const Duration(seconds: 3)) {
      _versionTapCount = 0;
    }
    _lastTapTime = now;
    _versionTapCount++;

    if (_currentPrefs.developerModeUnlocked) {
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(uwu('A fejlesztői mód már fel van oldva!')),
            duration: const Duration(milliseconds: 1400),
          ),
        );
      return;
    }

    if (_versionTapCount >= 5) {
      _versionTapCount = 0;
      HapticFeedback.heavyImpact();
      final unlocked = _currentPrefs.copyWith(developerModeUnlocked: true);
      _updatePrefs(unlocked);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: OledTheme.uwuPastelPink,
            content: Text(
              uwu('Fejlesztői mód feloldva!'),
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
    } else if (_versionTapCount >= 2) {
      HapticFeedback.lightImpact();
      final remaining = 5 - _versionTapCount;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              uwu('Még $remaining koppintás a fejlesztői módhoz...'),
            ),
            duration: const Duration(milliseconds: 900),
          ),
        );
    }
  }

  Future<void> _openGitHubRepo() async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse(GitHubUpdaterService.repoUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _triggerManualUpdateCheck() async {
    if (_isCheckingUpdates) return;
    setState(() => _isCheckingUpdates = true);
    await GitHubUpdaterService.checkForUpdates(context, manual: true);
    if (mounted) {
      setState(() => _isCheckingUpdates = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(uwu('Az alkalmazásról')),
      ),
      body: ChristmasAndBackgroundOverlay(
        prefs: _currentPrefs,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
          children: [
            _buildHeroIdentityCard(theme, scheme).staggeredEntrance(0),
            const SizedBox(height: 16),
            _buildUpdateAndLinksCard(theme, scheme).staggeredEntrance(1),
            if (_currentPrefs.developerModeUnlocked) ...[
              const SizedBox(height: 16),
              _buildDeveloperOptionsCard(theme, scheme).staggeredEntrance(2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeroIdentityCard(ThemeData theme, ColorScheme scheme) {
    final activeIcon = AppIconPresetInfo.resolve(_currentPrefs);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.largeRadius,
        border: Border.all(
          color: _currentPrefs.uwuModeEnabled
              ? OledTheme.uwuPastelPink
              : theme.dividerColor,
          width: _currentPrefs.uwuModeEnabled ? 1.6 : 1.0,
        ),
      ),
      child: Column(
        children: [
          AppBrandIconBadge(
            prefs: _currentPrefs,
            size: 88,
          ),
          const SizedBox(height: 16),
          Text(
            _currentPrefs.uwuModeEnabled ? 'weKWETA uwu' : 'reKRETA',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            uwu('Aktív ikon: ${activeIcon.label} (${activeIcon.subtitle})'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.68),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          TactileBounce(
            onTap: _handleVersionTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _currentPrefs.developerModeUnlocked
                        ? Icons.auto_awesome_rounded
                        : Icons.verified_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    uwu('v$_version'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateAndLinksCard(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.largeRadius,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.system_update_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                uwu('Frissítések és Forráskód'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TactileBounce(
            onTap: _isCheckingUpdates ? null : _triggerManualUpdateCheck,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isCheckingUpdates)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: scheme.onPrimary,
                      ),
                    )
                  else
                    Icon(
                      Icons.cloud_sync_rounded,
                      size: 20,
                      color: scheme.onPrimary,
                    ),
                  const SizedBox(width: 10),
                  Text(
                    uwu(
                      _isCheckingUpdates
                          ? 'Frissítések keresése...'
                          : 'Frissítések keresése',
                    ),
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TactileBounce(
            onTap: _openGitHubRepo,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.code_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          uwu('GitHub tároló megnyitása'),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          GitHubUpdaterService.repoUrl,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperOptionsCard(ThemeData theme, ColorScheme scheme) {
    final isUwu = _currentPrefs.uwuModeEnabled;
    final isTsundere = _currentPrefs.tsundereModeEnabled;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.largeRadius,
        border: Border.all(
          color: OledTheme.uwuPastelPink.withValues(alpha: 0.75),
          width: 1.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.terminal_rounded,
                size: 20,
                color: OledTheme.uwuPastelPink,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  uwu('Fejlesztői beállítások (Easter Egg)'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: OledTheme.uwuPastelPink,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _updatePrefs(
                    _currentPrefs.copyWith(
                      developerModeUnlocked: false,
                      uwuModeEnabled: false,
                      tsundereModeEnabled: false,
                    ),
                  );
                },
                child: Text(uwu('Elrejtés')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: OledTheme.uwuPastelPink.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: OledTheme.uwuPastelPink.withValues(alpha: 0.45),
              ),
            ),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: OledTheme.uwuPastelPink,
              title: const Text(
                'UwU mód',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                uwu(
                  'Cuki fonetikus átalakítás (r/l -> w, :3, uwu, >w<) és pasztell rózsaszín/levendula árnyalatok az egész appban!',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              value: isUwu,
              onChanged: (val) {
                HapticFeedback.mediumImpact();
                _updatePrefs(_currentPrefs.copyWith(uwuModeEnabled: val));
              },
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF7043).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFFF7043).withValues(alpha: 0.45),
              ),
            ),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: const Color(0xFFFF7043),
              title: const Text(
                'Tsundere mód',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              subtitle: Text(
                'Csípős tsundere beszólások és köszöntések („N-nem mintha érdekelne a házi feladatod, b-baka~!”, „M-megint egy hármas? Nem mintha figyeltem volna rád, h-hülye...~”)',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              value: isTsundere,
              onChanged: (val) {
                HapticFeedback.mediumImpact();
                _updatePrefs(_currentPrefs.copyWith(tsundereModeEnabled: val));
              },
            ),
          ),
          const SizedBox(height: 12),
          TactileBounce(
            onTap: () {
              GitHubUpdaterService.showFrostedUpdateDialog(
                context,
                currentVersion: _version,
                release: const GitHubReleaseInfo(
                  tagName: 'v1.2.0',
                  title: 'reKRETA v1.2.0 — OTA Frissítő Előnézet',
                  releaseNotes:
                      '• 120Hz-es fizikai animációk és Hero átmenetek\n'
                      '• Szellemjegy Számoló, Ösztöndíj Kalkulátor és egyedi kerekítési határok\n'
                      '• Titkos UwU mód és Tsundere mód :3\n'
                      '• Közvetlen GitHub Releases APK letöltés és telepítés (reKRETA-v1.2.0.apk)',
                  htmlUrl: GitHubUpdaterService.repoUrl,
                  apkDownloadUrl:
                      'https://github.com/mlnlbrt10/reKRETA/releases/latest/download/reKRETA-v1.2.0.apk',
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.preview_rounded,
                    size: 18,
                    color: OledTheme.uwuPastelLavender,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    uwu('OTA Frissítő ablak előnézete'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
