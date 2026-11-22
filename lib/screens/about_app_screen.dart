import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../services/github_updater_service.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/privacy_legal_modal.dart';
import '../widgets/tinta_toast.dart';

/// Dedicated "Az alkalmazásról" (About App / Rendszer & Névjegy) screen with:
/// - App icon (`AppBrandIconBadge`), name ('Tinta Napló'), semantic version ('v3.0.2'),
///   and developer credits.
/// - Direct link to `https://github.com/mlnlbrt10/tinta-naplo`.
/// - Manual "Frissítések keresése" button (GitHub Releases OTA updater).
/// - 5-tap secret Easter egg on the version text to unlock "Fejlesztői beállítások"
///   inside the `Rendszer / Névjegy` Settings sub-screen.
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

  late UserProfilePrefs _currentPrefsStorage;
  SettingsProvider? _settingsProvider;

  UserProfilePrefs get _currentPrefs =>
      _settingsProvider?.prefs ?? _currentPrefsStorage;

  @override
  void initState() {
    super.initState();
    _currentPrefsStorage = widget.prefs;
    _loadPackageVersion();
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    final latest = _settingsProvider?.prefs;
    if (latest != null) {
      _currentPrefsStorage = latest;
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextProvider = AppProvidersScope.maybeOf(context)?.settings;
    if (_settingsProvider != nextProvider) {
      _settingsProvider?.removeListener(_handleSettingsChanged);
      _settingsProvider = nextProvider;
      _settingsProvider?.addListener(_handleSettingsChanged);
    }
    if (_settingsProvider != null) {
      _currentPrefsStorage = _settingsProvider!.prefs;
    }
  }

  @override
  void didUpdateWidget(covariant AboutAppScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_settingsProvider == null && widget.prefs != oldWidget.prefs) {
      _currentPrefsStorage = widget.prefs;
    }
  }

  @override
  void dispose() {
    _settingsProvider?.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  Future<void> _loadPackageVersion() async {
    try {
      final (ver, _) = await GitHubUpdaterService.getAppVersionInfo();
      if (!mounted) return;
      setState(() {
        _version = ver;
      });
    } catch (_) {}
  }

  void _updatePrefs(UserProfilePrefs nextPrefs) {
    UserProfilePrefs.syncActiveGlobals(nextPrefs);
    _currentPrefsStorage = nextPrefs;
    final provider = _settingsProvider ??
        (mounted ? context.getInheritedWidgetOfExactType<AppProvidersScope>()?.settings : null);
    if (provider != null) {
      unawaited(provider.updatePrefs(nextPrefs));
    } else {
      TokenStorageService.saveProfilePrefsToSharedPrefs(nextPrefs);
    }
    if (mounted) {
      setState(() => _currentPrefsStorage = nextPrefs);
    }
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
      TintaToast.info(
        context,
        uwu('A fejlesztői mód már fel van oldva!'),
        duration: const Duration(milliseconds: 1400),
      );
      return;
    }

    if (_versionTapCount >= 5) {
      _versionTapCount = 0;
      HapticFeedback.heavyImpact();
      final unlocked = _currentPrefs.copyWith(developerModeUnlocked: true);
      _updatePrefs(unlocked);
      TintaToast.success(
        context,
        uwu('Fejlesztői mód feloldva!'),
        accentColorOverride: OledTheme.uwuPastelPink,
      );
    } else if (_versionTapCount >= 2) {
      HapticFeedback.lightImpact();
      final remaining = 5 - _versionTapCount;
      TintaToast.info(
        context,
        uwu('Még $remaining koppintás a fejlesztői módhoz...'),
        duration: const Duration(milliseconds: 900),
      );
    }
  }

  Future<void> _openGitHubRepo() async {
    HapticFeedback.lightImpact();
    try {
      final uri = Uri.parse(GitHubUpdaterService.repoUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openFirkaWebsite() async {
    HapticFeedback.lightImpact();
    try {
      await launchUrl(
        Uri.parse('https://firka.app/'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  Future<void> _openPacukaTintaWebsite() async {
    HapticFeedback.lightImpact();
    try {
      await launchUrl(
        Uri.parse('https://tinta.pacuka.hu/'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  void _openPrivacyAndLegalModal() {
    HapticFeedback.selectionClick();
    unawaited(showPrivacyAndLegalModal(context, prefs: _currentPrefs));
  }

  void _openOpenSourceLicenses() {
    HapticFeedback.selectionClick();
    showLicensePage(
      context: context,
      applicationName: 'Tinta Napló',
      applicationVersion: 'v$_version',
      applicationIcon: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: AppBrandIconBadge(
          prefs: _currentPrefs,
          size: 56,
        ),
      ),
      applicationLegalese: '© Tinta Napló • GNU GPLv3 nyílt forráskódú projekt',
    );
  }

  Future<void> _triggerManualUpdateCheck() async {
    if (_isCheckingUpdates) return;
    setState(() => _isCheckingUpdates = true);
    try {
      await GitHubUpdaterService.checkForUpdates(context, manual: true);
    } catch (_) {
      if (mounted) {
        TintaToast.error(context, 'Frissítések ellenőrzése sikertelen');
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdates = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AdaptiveBackgroundScaffold(
      prefs: _currentPrefs,
      appBar: buildAdaptiveTransparentAppBar(
        context,
        title: uwu('Az alkalmazásról'),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          adaptiveAppBarTopPadding(context),
          16,
          36,
        ),
        children: [
          _buildHeroIdentityCard(theme, scheme).staggeredEntrance(0),
          const SizedBox(height: 16),
          _buildUpdateAndLinksCard(theme, scheme).staggeredEntrance(1),
          const SizedBox(height: 16),
          _buildLegalAndLicensesCard(theme, scheme).staggeredEntrance(2),
        ],
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
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _currentPrefs.fitymaModeEnabled
                ? const FitymaBrandIcon(size: 88)
                : Image.asset(
                    _currentPrefs.activeAppIconAsset,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            _currentPrefs.uwuModeEnabled
                ? uwu('Tinta Nyapló uwu')
                : uwu('Tinta Napló'),
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
          const SizedBox(height: 10),
          TactileBounce(
            onTap: _openFirkaWebsite,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.brush_rounded, size: 19, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          uwu('Ikonok inspirációja: Firka (QwIT)'),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          'https://firka.app/',
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
          const SizedBox(height: 10),
          TactileBounce(
            onTap: _openPacukaTintaWebsite,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 19, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          uwu('A Tinta Napló nem azonos a Tinta alkalmazással (tinta.pacuka.hu).'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'https://tinta.pacuka.hu/',
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

  Widget _buildLegalAndLicensesCard(ThemeData theme, ColorScheme scheme) {
    return Material(
      color: theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: OledTheme.largeRadius,
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined, color: scheme.primary),
            title: Text(
              uwu('Adatvédelmi tájékoztató'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              uwu('Adatvédelem és jogi nyilatkozat'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurface.withValues(alpha: 0.56),
            ),
            onTap: _openPrivacyAndLegalModal,
          ),
          Divider(height: 1, indent: 56, color: theme.dividerColor),
          ListTile(
            leading: Icon(Icons.description_outlined, color: scheme.primary),
            title: Text(
              uwu('Nyílt forráskódú licencek'),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              uwu('Függőségek és betűtípusok licencei'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurface.withValues(alpha: 0.56),
            ),
            onTap: _openOpenSourceLicenses,
          ),
        ],
      ),
    );
  }
}
