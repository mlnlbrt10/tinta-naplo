import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../services/github_updater_service.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';

/// Dedicated "Az alkalmazásról" (About App / Rendszer & Névjegy) screen with:
/// - App icon (`AppBrandIconBadge`), name ('Tinta Napló'), semantic version ('v1.1.1'),
///   and developer credits.
/// - Direct link to `https://github.com/mlnlbrt10/tinta-naplo`.
/// - Manual "Frissítések keresése" button (GitHub Releases OTA updater).
/// - 5-tap secret Easter egg on the version text to unlock "Fejlesztői beállítások"
///   with Liquid Glass Modes, Studio & Custom Image Backdrops, UwU & Tsundere modes.
class AboutAppScreen extends StatefulWidget {
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final Future<Uint8List?> Function()? customImagePicker;
  final Future<Directory> Function()? backdropDirectoryProvider;

  const AboutAppScreen({
    super.key,
    required this.prefs,
    required this.onPrefsChanged,
    this.customImagePicker,
    this.backdropDirectoryProvider,
  });

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  String _version = GitHubUpdaterService.fallbackAppVersion;
  int _versionTapCount = 0;
  DateTime? _lastTapTime;
  bool _isCheckingUpdates = false;
  bool _isPickingBackdrop = false;

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
    final (ver, _) = await GitHubUpdaterService.getAppVersionInfo();
    if (!mounted) return;
    setState(() {
      _version = ver;
    });
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

  Future<void> _pickCustomBackdropImage() async {
    if (_isPickingBackdrop) return;
    setState(() => _isPickingBackdrop = true);
    try {
      final Uint8List? bytes;
      if (widget.customImagePicker != null) {
        bytes = await widget.customImagePicker!();
      } else {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        bytes = picked != null ? await picked.readAsBytes() : null;
      }
      if (bytes == null || bytes.isEmpty) return;

      final docsDir = await (widget.backdropDirectoryProvider != null
          ? widget.backdropDirectoryProvider!()
          : getApplicationDocumentsDirectory());
      final targetFile = File('${docsDir.path}/custom_backdrop.jpg');
      await targetFile.writeAsBytes(bytes, flush: true);

      // Evict stale image cache so replacing custom_backdrop.jpg updates immediately.
      await FileImage(targetFile).evict();
      await ResizeImage(FileImage(targetFile), width: 1440).evict();

      final lum = await AdaptiveContrastTokens.computeImageLuminance(bytes);
      if (!mounted) return;
      _updatePrefs(
        _currentPrefs.copyWith(
          customBackdropPath: targetFile.path,
          customBackdropLuminance: lum,
        ),
      );
    } catch (_) {
      // Ignore canceled picker or transient IO errors cleanly.
    } finally {
      if (mounted) {
        setState(() => _isPickingBackdrop = false);
      }
    }
  }

  Future<void> _clearCustomBackdropImage() async {
    final existingPath = _currentPrefs.customBackdropPath;
    _updatePrefs(_currentPrefs.copyWith(clearCustomBackdropPath: true));
    if (existingPath != null && existingPath.trim().isNotEmpty) {
      try {
        final f = File(existingPath);
        await FileImage(f).evict();
        await ResizeImage(FileImage(f), width: 1440).evict();
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
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
          if (_currentPrefs.developerModeUnlocked) ...[
            const SizedBox(height: 16),
            _buildDeveloperOptionsCard(theme, scheme).staggeredEntrance(2),
          ],
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
            child: Image.asset(
              'assets/images/tinta_icon.png',
              width: 88,
              height: 88,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _currentPrefs.uwuModeEnabled ? 'Tinta Nyapló uwu' : 'Tinta Napló',
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
          const SizedBox(height: 16),
          Text(
            uwu('Liquid Glass Mód (Fizikai optika)'),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _currentPrefs.liquidGlassMode.description,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LiquidGlassMode.values.map((mode) {
              final selected = _currentPrefs.liquidGlassMode == mode;
              return ChoiceChip(
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                    Text(
                      mode.subtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
                selected: selected,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  _updatePrefs(
                    _currentPrefs.copyWith(liquidGlassMode: mode),
                  );
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            uwu('Stúdió hátterek & Saját háttérkép'),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: BackgroundPresetInfo.presets.map((bg) {
              final selected = !_currentPrefs.hasCustomBackdrop &&
                  _currentPrefs.backgroundPreset == bg.id;
              return ChoiceChip(
                avatar: Icon(
                  selected ? Icons.check_circle_rounded : bg.icon,
                  size: 16,
                  color: selected ? scheme.primary : null,
                ),
                label: Text(
                  bg.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                selected: selected,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  _updatePrefs(
                    _currentPrefs.copyWith(
                      backgroundPreset: bg.id,
                      clearCustomBackdropPath: true,
                    ),
                  );
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed:
                    _isPickingBackdrop ? null : _pickCustomBackdropImage,
                icon: _isPickingBackdrop
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_rounded, size: 18),
                label: Text(uwu('Saját háttérkép kiválasztása')),
              ),
              if (_currentPrefs.hasCustomBackdrop)
                OutlinedButton.icon(
                  onPressed: _clearCustomBackdropImage,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(uwu('Háttérkép törlése')),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                uwu('Háttér sötétítés / kontraszt'),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${(_currentPrefs.customBackdropDim.clamp(0.0, 0.75) * 100).round()}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: _currentPrefs.customBackdropDim.clamp(0.0, 0.75),
            min: 0.0,
            max: 0.75,
            divisions: 15,
            onChanged: (v) => _updatePrefs(
              _currentPrefs.copyWith(customBackdropDim: v),
            ),
          ),
          const SizedBox(height: 10),
          TactileBounce(
            onTap: () {
              GitHubUpdaterService.showFrostedUpdateDialog(
                context,
                currentVersion: _version,
                release: const GitHubReleaseInfo(
                  tagName: 'v1.1.1',
                  title: 'Tinta Napló v1.1.1 — OTA Frissítő Előnézet',
                  releaseNotes:
                      '• 120Hz-es fizikai animációk és Hero átmenetek\n'
                      '• MenetrendGO reggeli/délutáni helyreállítás és Szünet visszaszámláló\n'
                      '• Kísérleti Liquid Glass módok, Stúdió hátterek és saját háttérkép\n'
                      '• Közvetlen GitHub Releases APK letöltés és telepítés (tinta-naplo-v1.1.1.apk)',
                  htmlUrl: GitHubUpdaterService.repoUrl,
                  apkDownloadUrl:
                      '${GitHubUpdaterService.repoUrl}/releases/latest/download/tinta-naplo-v1.1.1.apk',
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
