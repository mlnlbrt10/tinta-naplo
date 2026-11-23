import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../core/kreta_auth_config.dart';
import '../providers/app_providers.dart';
import '../services/demo_data_service.dart';
import '../services/dynamic_icon_service.dart';
import '../services/github_updater_service.dart';
import '../services/home_widget_sync_service.dart';
import '../services/kreta_client.dart';
import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../services/wear_sync_service.dart';
import '../theme/custom_skin_config.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';
import '../widgets/tinta_toast.dart';

/// Shared rounded icon bubble matching the Tinta Napló landing page aesthetic
/// (`width: 40, height: 40`, `BorderRadius.circular(13)`, subtle tint, `1px` border).
class DeveloperIconBubble extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final double size;

  const DeveloperIconBubble({
    super.key,
    required this.icon,
    required this.accentColor,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : theme.colorScheme.onSurface.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: Icon(icon, size: 20, color: accentColor),
    );
  }
}

class _DevSectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;

  const _DevSectionHeader(this.title, {this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13.5, color: scheme.primary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              uwuLabel(title.toUpperCase()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable 5-item menu launcher list shared between the standalone
/// [DeveloperOptionsHubScreen] and the unlocked section in [AboutAppScreen].
class DeveloperOptionsMenuList extends StatelessWidget {
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final Future<Uint8List?> Function()? customImagePicker;
  final Future<Directory> Function()? backdropDirectoryProvider;
  final TokenStorageService? tokenStorage;
  final KretaClient? kretaClient;
  final WearSyncService? wearSyncService;

  const DeveloperOptionsMenuList({
    super.key,
    required this.prefs,
    required this.onPrefsChanged,
    this.customImagePicker,
    this.backdropDirectoryProvider,
    this.tokenStorage,
    this.kretaClient,
    this.wearSyncService,
  });

  void _pushSubPage(BuildContext context, Widget page) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      SmoothSharedAxisRoute(page: page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appearanceActive = prefs.uwuModeEnabled ||
        prefs.customSkinEnabled ||
        prefs.fitymaModeEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DevSectionHeader('Felület és Testreszabás', icon: Icons.palette_outlined),
        _DeveloperCategoryCard(
          key: const ValueKey<String>('dev-hub-tile-appearance'),
          prefs: prefs,
          icon: Icons.palette_outlined,
          accent: scheme.primary,
          title: uwu('Megjelenés és UI'),
          subtitle: uwu('Saját háttérkép, egyéni CSS skin és kísérleti módok'),
          statusBadge: appearanceActive ? 'Aktív' : null,
          onTap: () => _pushSubPage(
            context,
            DeveloperAppearanceSubPage(
              initialPrefs: prefs,
              onPrefsChanged: onPrefsChanged,
              customImagePicker: customImagePicker,
              backdropDirectoryProvider: backdropDirectoryProvider,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _DevSectionHeader('Tesztelés és Adatkészlet', icon: Icons.science_outlined),
        _DeveloperCategoryCard(
          key: const ValueKey<String>('dev-hub-tile-demo'),
          prefs: prefs,
          icon: Icons.auto_awesome_rounded,
          accent: const Color(0xFF22C55E),
          title: uwu('Demó mód és Tesztadatok'),
          subtitle: uwu('Kovács Bence elszigetelt bemutató adatkészlet'),
          statusBadge: prefs.demoModeEnabled ? 'Aktív' : null,
          onTap: () => _pushSubPage(
            context,
            DeveloperDemoModeSubPage(
              initialPrefs: prefs,
              onPrefsChanged: onPrefsChanged,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _DevSectionHeader('Hálózat, Hitelesítés és Eszközök', icon: Icons.hub_outlined),
        _DeveloperCategoryCard(
          key: const ValueKey<String>('dev-hub-tile-auth'),
          prefs: prefs,
          icon: Icons.verified_user_outlined,
          accent: const Color(0xFF38BDF8),
          title: uwu('KRÉTA Auth és Hálózat'),
          subtitle: uwu('Token állapot, frissítés teszt és API diagnosztika'),
          statusBadge: prefs.demoModeEnabled ? 'Demó' : null,
          onTap: () => _pushSubPage(
            context,
            DeveloperAuthNetworkSubPage(
              initialPrefs: prefs,
              tokenStorage: tokenStorage,
              kretaClient: kretaClient,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _DeveloperCategoryCard(
          key: const ValueKey<String>('dev-hub-tile-integrations'),
          prefs: prefs,
          icon: Icons.watch_rounded,
          accent: const Color(0xFFF59E0B),
          title: uwu('Wear OS és Külső Integrációk'),
          subtitle: uwu('Okosóra szinkron állapot, Now Bar és MenetrendGO'),
          statusBadge: prefs.liveActivityEnabled ? 'Aktív' : null,
          onTap: () => _pushSubPage(
            context,
            DeveloperIntegrationsSubPage(
              initialPrefs: prefs,
              onPrefsChanged: onPrefsChanged,
              tokenStorage: tokenStorage,
              wearSyncService: wearSyncService,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _DevSectionHeader('Rendszer és Karbantartás', icon: Icons.memory_rounded),
        _DeveloperCategoryCard(
          key: const ValueKey<String>('dev-hub-tile-system'),
          prefs: prefs,
          icon: Icons.memory_rounded,
          accent: OledTheme.uwuPastelLavender,
          title: uwu('Rendszer, Cache és Naplók'),
          subtitle: uwu('Verzió, OS telemetria, cache és új jegy ragyogás'),
          onTap: () => _pushSubPage(
            context,
            DeveloperSystemCacheSubPage(
              initialPrefs: prefs,
              tokenStorage: tokenStorage,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeveloperCategoryCard extends StatelessWidget {
  final UserProfilePrefs prefs;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String? statusBadge;
  final VoidCallback onTap;

  const _DeveloperCategoryCard({
    super.key,
    required this.prefs,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.statusBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ChristmasSnowCap(
      enabled: prefs.christmasModeEnabled,
      child: SoftGlassCard(
        prefs: prefs,
        padding: EdgeInsets.zero,
        borderRadius: OledTheme.largeRadius,
        child: TactileBounce(
          pressedScale: 0.98,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                DeveloperIconBubble(icon: icon, accentColor: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uwu(title),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        uwu(subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                if (statusBadge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3.5,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.42),
                      ),
                    ),
                    child: Text(
                      uwuLabel(statusBadge!),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.68),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Multi-page Developer Options root hub (`Fejlesztői beállítások`).
class DeveloperOptionsHubScreen extends StatelessWidget {
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final Future<Uint8List?> Function()? customImagePicker;
  final Future<Directory> Function()? backdropDirectoryProvider;
  final TokenStorageService? tokenStorage;
  final KretaClient? kretaClient;
  final WearSyncService? wearSyncService;

  const DeveloperOptionsHubScreen({
    super.key,
    required this.prefs,
    required this.onPrefsChanged,
    this.customImagePicker,
    this.backdropDirectoryProvider,
    this.tokenStorage,
    this.kretaClient,
    this.wearSyncService,
  });

  @override
  Widget build(BuildContext context) {
    final scope = AppProvidersScope.maybeOf(context);
    Widget buildBody(UserProfilePrefs activePrefs) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;

      return AdaptiveBackgroundScaffold(
        prefs: activePrefs,
        appBar: buildAdaptiveTransparentAppBar(
          context,
          title: uwu('Fejlesztői beállítások'),
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
            DeveloperOptionsMenuList(
              prefs: activePrefs,
              onPrefsChanged: onPrefsChanged,
              customImagePicker: customImagePicker,
              backdropDirectoryProvider: backdropDirectoryProvider,
              tokenStorage: tokenStorage,
              kretaClient: kretaClient,
              wearSyncService: wearSyncService,
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: BorderSide(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: OledTheme.cardRadius,
                ),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                final next = activePrefs
                    .withDemoMode(false)
                    .copyWith(
                      developerModeUnlocked: false,
                      uwuModeEnabled: false,
                    );
                UserProfilePrefs.syncActiveGlobals(next);
                scope?.settings.updatePrefs(next);
                onPrefsChanged(next);
                Navigator.of(context).pop();
                TintaToast.info(
                  context,
                  uwu('Fejlesztői beállítások elrejtve.'),
                );
              },
              icon: const Icon(Icons.visibility_off_outlined, size: 18),
              label: Text(
                uwu('Fejlesztői beállítások elrejtése'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: scheme.error,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (scope == null) {
      return buildBody(prefs);
    }
    return AnimatedBuilder(
      animation: scope.settings,
      builder: (context, _) => buildBody(scope.settings.prefs),
    );
  }
}

void _applyDevPrefs(
  BuildContext context, {
  required UserProfilePrefs nextPrefs,
  ValueChanged<UserProfilePrefs>? onPrefsChanged,
  ValueChanged<UserProfilePrefs>? setLocalState,
}) {
  UserProfilePrefs.syncActiveGlobals(nextPrefs);
  setLocalState?.call(nextPrefs);
  final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
  if (scope != null) {
    unawaited(scope.settings.updatePrefs(nextPrefs));
  } else {
    TokenStorageService.saveProfilePrefsToSharedPrefs(nextPrefs);
  }
  onPrefsChanged?.call(nextPrefs);
}

// =============================================================================
// 1. Megjelenés és UI
// =============================================================================
class DeveloperAppearanceSubPage extends StatefulWidget {
  final UserProfilePrefs initialPrefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final Future<Uint8List?> Function()? customImagePicker;
  final Future<Directory> Function()? backdropDirectoryProvider;

  const DeveloperAppearanceSubPage({
    super.key,
    required this.initialPrefs,
    required this.onPrefsChanged,
    this.customImagePicker,
    this.backdropDirectoryProvider,
  });

  @override
  State<DeveloperAppearanceSubPage> createState() =>
      _DeveloperAppearanceSubPageState();
}

class _DeveloperAppearanceSubPageState
    extends State<DeveloperAppearanceSubPage> {
  late UserProfilePrefs _localPrefs;
  late final TextEditingController _cssSkinController;
  bool _isPickingBackdrop = false;

  @override
  void initState() {
    super.initState();
    _localPrefs = widget.initialPrefs;
    _cssSkinController = TextEditingController(
      text: widget.initialPrefs.customSkinCss,
    );
  }

  @override
  void dispose() {
    _cssSkinController.dispose();
    super.dispose();
  }

  UserProfilePrefs _activePrefs(BuildContext context) =>
      AppProvidersScope.maybeOf(context)?.settings.prefs ?? _localPrefs;

  void _update(UserProfilePrefs next) {
    _applyDevPrefs(
      context,
      nextPrefs: next,
      onPrefsChanged: widget.onPrefsChanged,
      setLocalState: (val) => setState(() => _localPrefs = val),
    );
  }

  Future<void> _pickCustomBackdropImage(UserProfilePrefs activePrefs) async {
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
      targetFile.writeAsBytesSync(bytes, flush: true);

      await FileImage(targetFile).evict();
      await ResizeImage(FileImage(targetFile), width: 1440).evict();

      final lum = await AdaptiveContrastTokens.computeImageLuminance(bytes);
      if (!mounted) return;
      _update(
        activePrefs.copyWith(
          animatedBackdropPreset: AnimatedBackdropPreset.off,
          customBackdropPath: targetFile.path,
          customBackdropLuminance: lum,
        ),
      );
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isPickingBackdrop = false);
      }
    }
  }

  Future<void> _clearCustomBackdropImage(UserProfilePrefs activePrefs) async {
    final existingPath = activePrefs.customBackdropPath;
    _update(activePrefs.copyWith(clearCustomBackdropPath: true));
    if (existingPath != null && existingPath.trim().isNotEmpty) {
      try {
        final f = File(existingPath);
        await FileImage(f).evict();
        await ResizeImage(FileImage(f), width: 1440).evict();
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppProvidersScope.maybeOf(context);
    Widget buildPage(UserProfilePrefs activePrefs) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;

      return AdaptiveBackgroundScaffold(
        prefs: activePrefs,
        appBar: buildAdaptiveTransparentAppBar(
          context,
          title: uwu('Megjelenés és UI'),
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
            const _DevSectionHeader('Háttér és Atmoszféra', icon: Icons.wallpaper_rounded),
            SoftGlassCard(
              prefs: activePrefs,
              padding: const EdgeInsets.all(18),
              borderRadius: OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    uwu('Saját háttérkép'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _isPickingBackdrop
                            ? null
                            : () => _pickCustomBackdropImage(activePrefs),
                        icon: _isPickingBackdrop
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.photo_library_rounded, size: 18),
                        label: Text(uwu('Saját háttérkép kiválasztása')),
                      ),
                      if (activePrefs.hasCustomBackdrop)
                        OutlinedButton.icon(
                          onPressed: () =>
                              _clearCustomBackdropImage(activePrefs),
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: Text(uwu('Háttérkép törlése')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          uwu('Háttér sötétítés / kontraszt'),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(activePrefs.customBackdropDim.clamp(0.0, 0.75) * 100).round()}%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: activePrefs.customBackdropDim.clamp(0.0, 0.75),
                    min: 0.0,
                    max: 0.75,
                    divisions: 15,
                    onChanged: (v) => _update(
                      activePrefs.copyWith(customBackdropDim: v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _DevSectionHeader('Kísérleti Stílusok és Easter Eggek', icon: Icons.auto_fix_high_rounded),
            Material(
              color: OledTheme.uwuPastelPink.withValues(alpha: 0.14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(
                  color: OledTheme.uwuPastelPink.withValues(alpha: 0.45),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: OledTheme.uwuPastelPink,
                  title: Text(
                    uwuLabel(
                      'UwU mód',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    uwuLabel(
                      'Cuki fonetikus átalakítás (r/l -> w, :3, uwu, >w<) és pasztell rózsaszín/levendula árnyalatok az egész appban!',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                  value: activePrefs.uwuModeEnabled,
                  onChanged: (val) {
                    HapticFeedback.mediumImpact();
                    _update(activePrefs.copyWith(uwuModeEnabled: val));
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: const Color(0xFFFFB74D).withValues(alpha: 0.14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(
                  color: const Color(0xFFFFB74D).withValues(alpha: 0.45),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: SwitchListTile.adaptive(
                  key: const ValueKey<String>('dev-fityma-mode-switch'),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: const Color(0xFFFFB74D),
                  title: Text(
                    uwuLabel(
                      'Fityma Napló mód',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    uwuLabel(
                      'Lecseréli az alkalmazás nevét és logóját a játékos „Fityma Napló” kiadásra.',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                  value: activePrefs.fitymaModeEnabled,
                  onChanged: (val) {
                    HapticFeedback.mediumImpact();
                    final next = activePrefs.withFitymaMode(val);
                    _update(next);
                    unawaited(DynamicIconService.syncIconWithPrefs(next));
                    TintaToast.info(
                      context,
                      val
                          ? 'Fityma Napló mód aktiválva (indítóikon frissítve)'
                          : 'Tinta Napló alapállapot visszaállítva',
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _DevSectionHeader('Haladó CSS Skin Szerkesztő', icon: Icons.code_rounded),
            SoftGlassCard(
              prefs: activePrefs,
              padding: const EdgeInsets.all(18),
              borderRadius: OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile.adaptive(
                    key: const ValueKey<String>('dev-custom-skin-switch'),
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: scheme.primary,
                    title: Text(
                      uwuLabel(
                        'Egyéni CSS Skin',
                        enabled: activePrefs.uwuModeEnabled,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      uwuLabel(
                        'Élő CSS-változó alapú felület- és témaszerkesztő (:root { --bg, --surface, --accent, --card-radius... }).',
                        enabled: activePrefs.uwuModeEnabled,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                    value: activePrefs.customSkinEnabled,
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      _update(
                        activePrefs.withCustomSkin(
                          enabled: val,
                          css: _cssSkinController.text,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey<String>('dev-custom-skin-editor'),
                    controller: _cssSkinController,
                    minLines: 7,
                    maxLines: 12,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.38,
                    ),
                    decoration: InputDecoration(
                      hintText: CustomSkinConfig.defaultTemplateCss,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey<String>('dev-custom-skin-apply'),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _update(
                            activePrefs.withCustomSkin(
                              enabled: true,
                              css: _cssSkinController.text,
                            ),
                          );
                          TintaToast.success(
                            context,
                            'Egyéni CSS Skin alkalmazva',
                          );
                        },
                        icon: const Icon(Icons.check_rounded, size: 17),
                        label: Text(
                          uwuLabel(
                            'Alkalmaz',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey<String>('dev-custom-skin-reset'),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _cssSkinController.text =
                              CustomSkinConfig.defaultTemplateCss;
                          _update(
                            activePrefs.withCustomSkin(
                              enabled: false,
                              css: CustomSkinConfig.defaultTemplateCss,
                            ),
                          );
                          TintaToast.info(
                            context,
                            'Egyéni CSS Skin alaphelyzetbe állítva',
                          );
                        },
                        icon: const Icon(Icons.restart_alt_rounded, size: 17),
                        label: Text(
                          uwuLabel(
                            'Alaphelyzet',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            await Clipboard.setData(
                              ClipboardData(text: _cssSkinController.text),
                            );
                            if (!context.mounted) return;
                            TintaToast.info(context, 'CSS vágólapra másolva');
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(
                          uwuLabel(
                            'Másolás',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            final clip = await Clipboard.getData('text/plain');
                            if (!mounted || !context.mounted) return;
                            final pasted = clip?.text;
                            if (pasted == null || pasted.trim().isEmpty) return;
                            _cssSkinController.text = pasted;
                            TintaToast.info(context, 'CSS beillesztve');
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.paste_rounded, size: 16),
                        label: Text(
                          uwuLabel(
                            'Beillesztés',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (scope == null) {
      return buildPage(_localPrefs);
    }
    return AnimatedBuilder(
      animation: scope.settings,
      builder: (context, _) => buildPage(_activePrefs(context)),
    );
  }
}

// =============================================================================
// 2. Demó mód és Tesztadatok
// =============================================================================
class DeveloperDemoModeSubPage extends StatefulWidget {
  final UserProfilePrefs initialPrefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;

  const DeveloperDemoModeSubPage({
    super.key,
    required this.initialPrefs,
    required this.onPrefsChanged,
  });

  @override
  State<DeveloperDemoModeSubPage> createState() =>
      _DeveloperDemoModeSubPageState();
}

class _DeveloperDemoModeSubPageState extends State<DeveloperDemoModeSubPage> {
  late UserProfilePrefs _localPrefs;

  @override
  void initState() {
    super.initState();
    _localPrefs = widget.initialPrefs;
  }

  void _toggleDemo(BuildContext context, UserProfilePrefs current, bool val) {
    HapticFeedback.mediumImpact();
    final next = current.withDemoMode(val);
    _applyDevPrefs(
      context,
      nextPrefs: next,
      onPrefsChanged: widget.onPrefsChanged,
      setLocalState: (p) => setState(() => _localPrefs = p),
    );
    TintaToast.success(
      context,
      val
          ? 'Demó mód aktiválva (Kovács Bence • 11.B)'
          : 'Valós KRÉTA munkamenet visszaállítva',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppProvidersScope.maybeOf(context);

    Widget buildPage(UserProfilePrefs activePrefs) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final isDemo = activePrefs.demoModeEnabled;
      const demoAccent = Color(0xFF22C55E);

      return AdaptiveBackgroundScaffold(
        prefs: activePrefs,
        appBar: buildAdaptiveTransparentAppBar(
          context,
          title: uwu('Demó mód és Tesztadatok'),
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
            const _DevSectionHeader('Demó Adatkészlet Vezérlés', icon: Icons.toggle_on_outlined),
            SoftGlassCard(
              prefs: activePrefs,
              padding: const EdgeInsets.all(18),
              borderRadius: OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: demoAccent,
                    title: Text(
                      uwuLabel(
                        'Demó mód',
                        enabled: activePrefs.uwuModeEnabled,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      uwuLabel(
                        'Teljes bemutató adatkészlet (Kovács Bence • 11.B) a tinta-naplo.mlnlbrt.hu képernyőképekhez. A főoldalon nem jelenít meg zavaró szalagcímet.',
                        enabled: activePrefs.uwuModeEnabled,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.74),
                      ),
                    ),
                    value: isDemo,
                    onChanged: (val) => _toggleDemo(context, activePrefs, val),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: demoAccent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: demoAccent.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: demoAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            uwuLabel(
                              'Teljes izoláció: a valós KRÉTA munkameneted, SecureStorage tokenjeid és letöltött adataid érintetlenek maradnak, kikapcsoláskor azonnal visszatöltenek.',
                              enabled: activePrefs.uwuModeEnabled,
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.82),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _DevSectionHeader('Aktív Demó Adatkészlet', icon: Icons.dataset_rounded),
            SoftGlassCard(
              prefs: activePrefs,
              padding: const EdgeInsets.all(18),
              borderRadius: OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uwu('Aktív demó adatkészlet'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _DevInfoRow('Tanuló', DemoDataService.demoStudentName),
                  const _DevInfoRow(
                    'Intézmény',
                    '${DemoDataService.demoSchoolName} (${DemoDataService.demoClassName})',
                  ),
                  const _DevInfoRow(
                    'Órarend',
                    'Dinamikus H-P órarend (aktív óra, helyettesítés, elmaradó óra)',
                  ),
                  const _DevInfoRow(
                    'Értékelések',
                    '28 jegy / 8 tantárgy • 4.58 súlyozott átlag',
                  ),
                  const _DevInfoRow(
                    'Egyéb modulok',
                    '4 számonkérés • 4 házi • 2 igazolt mulasztás • 3 üzenet',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      DemoDataService.instance.regenerateNow();
                      TintaToast.success(
                        context,
                        'Demó órarend és időzítések frissítve a jelenlegi időhöz',
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Demó időzítések újragenerálása (Most)'),
                  ),
                  if (isDemo) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _toggleDemo(context, activePrefs, false),
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Valós munkamenetre visszaállás'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (scope == null) {
      return buildPage(_localPrefs);
    }
    return AnimatedBuilder(
      animation: scope.settings,
      builder: (context, _) => buildPage(scope.settings.prefs),
    );
  }
}

// =============================================================================
// 3. KRÉTA Auth és Hálózat
// =============================================================================
class DeveloperAuthNetworkSubPage extends StatefulWidget {
  final UserProfilePrefs initialPrefs;
  final TokenStorageService? tokenStorage;
  final KretaClient? kretaClient;

  const DeveloperAuthNetworkSubPage({
    super.key,
    required this.initialPrefs,
    this.tokenStorage,
    this.kretaClient,
  });

  @override
  State<DeveloperAuthNetworkSubPage> createState() =>
      _DeveloperAuthNetworkSubPageState();
}

class _DeveloperAuthNetworkSubPageState
    extends State<DeveloperAuthNetworkSubPage> {
  StoredSession? _storedSession;
  LogoutDiagnosticEntry? _lastLogoutReason;
  List<AuthEventEntry> _authTimeline = const [];
  bool _loadingSession = true;
  bool _testingRefresh = false;
  bool _testingSync = false;
  String? _diagResult;

  TokenStorageService get _storage =>
      widget.tokenStorage ?? const TokenStorageService();

  @override
  void initState() {
    super.initState();
    _loadSessionState();
  }

  Future<void> _loadSessionState() async {
    StoredSession? loaded;
    LogoutDiagnosticEntry? logoutReason;
    List<AuthEventEntry> timeline = const [];
    try {
      loaded = await _storage.loadSession();
    } catch (_) {
      loaded = null;
    }
    try {
      logoutReason = await TokenStorageService.loadLastLogoutReason();
    } catch (_) {
      logoutReason = null;
    }
    try {
      timeline = await TokenStorageService.loadAuthEventTimeline();
    } catch (_) {
      timeline = const [];
    }
    if (!mounted) return;
    setState(() {
      _storedSession = loaded;
      _lastLogoutReason = logoutReason;
      _authTimeline = timeline;
      _loadingSession = false;
    });
  }

  Future<void> _testTokenRefresh() async {
    if (_testingRefresh) return;
    setState(() {
      _testingRefresh = true;
      _diagResult = null;
    });
    KretaClient? tempClient;
    try {
      final session = await _storage.loadSession();
      if (session == null) {
        if (!mounted) return;
        setState(() => _diagResult = 'Nincs mentett KRÉTA munkamenet.');
        TintaToast.info(context, 'Nincs mentett munkamenet a teszthez');
        return;
      }
      final client = widget.kretaClient ??
          (tempClient = KretaClient(storage: _storage));
      final refreshed = await _storage.refreshToken(
        session: session,
        httpClient: null,
        clientId: client.clientId,
      );
      final updatedTimeline = await TokenStorageService.loadAuthEventTimeline();
      if (!mounted) return;
      final fmt = DateFormat('yyyy. MM. dd. HH:mm:ss');
      setState(() {
        _storedSession = refreshed;
        _authTimeline = updatedTimeline;
        _diagResult =
            'Token frissítés sikeres • Új lejárat: ${fmt.format(refreshed.expiresAt.toLocal())}';
      });
      TintaToast.success(context, 'KRÉTA token sikeresen frissítve');
    } catch (e) {
      final updatedTimeline = await TokenStorageService.loadAuthEventTimeline();
      if (!mounted) return;
      setState(() {
        _authTimeline = updatedTimeline;
        _diagResult = 'Token frissítés hiba: $e';
      });
      TintaToast.error(context, 'Token frissítés sikertelen');
    } finally {
      tempClient?.close();
      if (mounted) {
        setState(() => _testingRefresh = false);
      }
    }
  }

  Future<void> _testApiSync(UserProfilePrefs activePrefs) async {
    if (_testingSync) return;
    setState(() {
      _testingSync = true;
      _diagResult = null;
    });
    final sw = Stopwatch()..start();
    KretaClient? tempClient;
    try {
      if (activePrefs.demoModeEnabled) {
        final data = DemoDataService.instance.buildDashboardData();
        sw.stop();
        if (!mounted) return;
        setState(() {
          _diagResult =
              'Demó mód aktív (${sw.elapsedMilliseconds} ms) - valós API hívás letiltva (${data.allGrades.length} jegy, ${data.todaysLessons.length} mai óra).';
        });
        return;
      }
      final session = _storedSession ?? await _storage.loadSession();
      if (session == null) {
        if (!mounted) return;
        setState(() => _diagResult = 'Nincs aktív munkamenet.');
        return;
      }
      final client = widget.kretaClient ??
          (tempClient = KretaClient(storage: _storage));
      final profile = await client.fetchStudentProfile(session);
      sw.stop();
      if (!mounted) return;
      setState(() {
        _diagResult =
            'API válasz OK (${sw.elapsedMilliseconds} ms) • Intézmény: ${profile?.instituteName ?? session.instituteCode}';
      });
      TintaToast.success(
        context,
        'API szinkron OK (${sw.elapsedMilliseconds} ms)',
      );
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _diagResult = 'API hiba (${sw.elapsedMilliseconds} ms): $e';
      });
      TintaToast.error(context, 'API diagnosztika hibával zárult');
    } finally {
      tempClient?.close();
      if (mounted) {
        setState(() => _testingSync = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.initialPrefs;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fmt = DateFormat('yyyy. MM. dd. HH:mm:ss');
    final s = _storedSession;

    final String tokenStatusLabel;
    if (_loadingSession) {
      tokenStatusLabel = 'Betöltés...';
    } else if (s == null) {
      tokenStatusLabel = 'Nincs mentett munkamenet';
    } else if (s.isExpired) {
      tokenStatusLabel = 'Lejárt / előfrissítésre vár';
    } else {
      tokenStatusLabel = 'Érvényes';
    }

    return AdaptiveBackgroundScaffold(
      prefs: activePrefs,
      appBar: buildAdaptiveTransparentAppBar(
        context,
        title: uwu('KRÉTA Auth és Hálózat'),
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
          const _DevSectionHeader('Hitelesítés és API Kapcsolat', icon: Icons.vpn_key_outlined),
          SoftGlassCard(
            prefs: activePrefs,
            padding: const EdgeInsets.all(18),
            borderRadius: OledTheme.largeRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uwu('OAuth2 Munkamenet és Token állapot'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                _DevInfoRow(
                  'Aktív mód',
                  activePrefs.demoModeEnabled
                      ? 'Demó mód (szigetelt)'
                      : 'Valós KRÉTA kliens',
                ),
                _DevInfoRow('Token állapot', tokenStatusLabel),
                _DevInfoRow('Intézménykód', s?.instituteCode ?? '-'),
                _DevInfoRow('Felhasználó', s?.userName ?? '-'),
                _DevInfoRow(
                  'Lejárat ideje',
                  s != null ? fmt.format(s.expiresAt.toLocal()) : '-',
                ),
                const _DevInfoRow('IdP végpont', KretaAuthConfig.tokenEndpoint),
                const _DevInfoRow('Kliens azonosító', KretaAuthConfig.clientIdIos),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: _testingRefresh ? null : _testTokenRefresh,
                  icon: _testingRefresh
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.key_rounded, size: 18),
                  label: Text(
                    uwuLabel(
                      'Token frissítés tesztelése',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      _testingSync ? null : () => _testApiSync(activePrefs),
                  icon: _testingSync
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: Text(
                    uwuLabel(
                      'API szinkron diagnosztika',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                  ),
                ),
                if (_diagResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _diagResult!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _DevSectionHeader('Esemény- és Hibanaplók', icon: Icons.history_rounded),
          SoftGlassCard(
            prefs: activePrefs,
            padding: const EdgeInsets.all(18),
            borderRadius: OledTheme.largeRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uwu('Utolsó kijelentkezés oka (last_logout_reason)'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (_lastLogoutReason == null)
                  Text(
                    uwu('Nincs rögzített kijelentkezési esemény.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.72),
                    ),
                  )
                else ...[
                  _DevInfoRow(
                    'Időpont',
                    fmt.format(_lastLogoutReason!.timestamp.toLocal()),
                  ),
                  _DevInfoRow('Hívó metódus', _lastLogoutReason!.caller),
                  _DevInfoRow('Ok', _lastLogoutReason!.reason),
                  if (_lastLogoutReason!.httpStatusCode != null)
                    _DevInfoRow(
                      'HTTP státusz',
                      '${_lastLogoutReason!.httpStatusCode}',
                    ),
                  if (_lastLogoutReason!.errorBody != null &&
                      _lastLogoutReason!.errorBody!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh
                            .withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _lastLogoutReason!.errorBody!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.onSurface.withValues(alpha: 0.88),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final entry = _lastLogoutReason;
                          if (entry == null) return;
                          await Clipboard.setData(
                            ClipboardData(text: entry.toDiagnosticSummary()),
                          );
                          if (!context.mounted) return;
                          TintaToast.info(
                            context,
                            'Kijelentkezési napló vágólapra másolva',
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(
                          uwuLabel(
                            'Másolás',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await TokenStorageService.clearLastLogoutReason();
                          if (!mounted) return;
                          setState(() => _lastLogoutReason = null);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: Text(
                          uwuLabel(
                            'Napló törlése',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _DevSectionHeader('Hitelesítési Eseménynapló', icon: Icons.timeline_rounded),
          SoftGlassCard(
            key: const ValueKey<String>('dev-auth-timeline-card'),
            prefs: activePrefs,
            padding: const EdgeInsets.all(18),
            borderRadius: OledTheme.largeRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        uwu('Hitelesítési eseménynapló (utolsó 25)'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: uwuLabel(
                        'Frissítés',
                        enabled: activePrefs.uwuModeEnabled,
                      ),
                      onPressed: _loadSessionState,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_authTimeline.isEmpty)
                  Text(
                    uwu('Nincs rögzített hitelesítési esemény.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.72),
                    ),
                  )
                else ...[
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 260),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        TokenStorageService.formatAuthEventTimeline(
                          _authTimeline,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.4,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey<String>('dev-auth-timeline-copy'),
                        onPressed: () async {
                          try {
                            final formatted =
                                TokenStorageService.formatAuthEventTimeline(
                              _authTimeline,
                            );
                            await Clipboard.setData(
                              ClipboardData(text: formatted),
                            );
                            if (!context.mounted) return;
                            TintaToast.info(
                              context,
                              'Hitelesítési eseménynapló vágólapra másolva',
                            );
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: Text(
                          uwuLabel(
                            'Másolás',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await TokenStorageService.clearAuthEventTimeline();
                          if (!mounted) return;
                          setState(() => _authTimeline = const []);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 16),
                        label: Text(
                          uwuLabel(
                            'Napló törlése',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4. Wear OS és Külső Integrációk
// =============================================================================
class DeveloperIntegrationsSubPage extends StatefulWidget {
  final UserProfilePrefs initialPrefs;
  final ValueChanged<UserProfilePrefs>? onPrefsChanged;
  final TokenStorageService? tokenStorage;
  final WearSyncService? wearSyncService;
  final HomeWidgetSyncService? homeWidgetSyncService;

  const DeveloperIntegrationsSubPage({
    super.key,
    required this.initialPrefs,
    this.onPrefsChanged,
    this.tokenStorage,
    this.wearSyncService,
    this.homeWidgetSyncService,
  });

  @override
  State<DeveloperIntegrationsSubPage> createState() =>
      _DeveloperIntegrationsSubPageState();
}

class _DeveloperIntegrationsSubPageState
    extends State<DeveloperIntegrationsSubPage>
    with WidgetsBindingObserver {
  late UserProfilePrefs _localPrefs;
  WearConnectionStatus _status = WearConnectionStatus.disconnected;
  bool _loading = true;
  bool _syncing = false;
  bool _togglingLiveActivity = false;
  bool _refreshingLiveActivity = false;
  bool _canPromoteLiveNotifications = true;

  WearSyncService get _wear =>
      widget.wearSyncService ?? WearSyncService.instance;
  TokenStorageService get _storage =>
      widget.tokenStorage ?? const TokenStorageService();
  HomeWidgetSyncService get _widgetSync =>
      widget.homeWidgetSyncService ?? HomeWidgetSyncService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _localPrefs = widget.initialPrefs;
    _refreshWear();
    unawaited(_refreshPromotionStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_refreshPromotionStatus(refreshIfGranted: true));
    }
  }

  Future<void> _refreshPromotionStatus({bool refreshIfGranted = false}) async {
    try {
      final canPromote = await _widgetSync.canPostPromotedNotifications();
      if (!mounted) return;
      final becameGranted = !_canPromoteLiveNotifications && canPromote;
      setState(() => _canPromoteLiveNotifications = canPromote);
      if (refreshIfGranted &&
          becameGranted &&
          _activePrefs(context).liveActivityEnabled) {
        await _widgetSync.refreshLiveUpdateNow();
      }
    } catch (_) {}
  }

  UserProfilePrefs _activePrefs(BuildContext context) =>
      AppProvidersScope.maybeOf(context)?.settings.prefs ?? _localPrefs;

  Future<void> _refreshWear() async {
    try {
      final s = await _wear.getConnectionStatus();
      if (!mounted) return;
      setState(() {
        _status = s;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _manualWearSync(UserProfilePrefs activePrefs) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final realSession = await _storage.loadSession();
      if (realSession == null) {
        if (!mounted) return;
        TintaToast.error(context, 'Nincs mentett valós munkamenet a szinkronhoz');
        return;
      }
      final ok = await _wear.syncSessionToWatch(
        session: realSession,
        nickname: activePrefs.nickname,
        forceSync: true,
      );
      final updated = await _wear.getConnectionStatus();
      if (!mounted) return;
      setState(() => _status = updated);
      TintaToast.show(
        context,
        ok
            ? 'Wear OS munkamenet szinkronizálva'
            : 'Wear OS szinkron sikertelen',
        type: ok ? TintaToastType.success : TintaToastType.error,
      );
    } catch (_) {
      if (mounted) {
        TintaToast.error(context, 'Wear OS szinkron sikertelen');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _toggleLiveActivity(
    UserProfilePrefs activePrefs,
    bool enabled,
  ) async {
    if (_togglingLiveActivity) return;
    HapticFeedback.mediumImpact();
    final primaryColor = Theme.of(context).colorScheme.primary;
    setState(() => _togglingLiveActivity = true);
    try {
      final granted = await _widgetSync.setLiveActivityEnabled(
        enabled,
        requestPermissionIfNeeded: enabled,
      );
      if (!mounted) return;

      if (enabled && !granted) {
        TintaToast.error(
          context,
          'Az élő értesítéshez értesítési engedély szükséges.',
        );
        return;
      }

      final nextPrefs = activePrefs.withLiveActivityEnabled(enabled);
      _applyDevPrefs(
        context,
        nextPrefs: nextPrefs,
        onPrefsChanged: widget.onPrefsChanged,
        setLocalState: (p) => setState(() => _localPrefs = p),
      );
      await _widgetSync.syncPreferencesWithCachedLessons(
        prefs: nextPrefs,
        themeAccent: primaryColor,
      );
      if (!mounted) return;
      if (enabled) {
        await _widgetSync.refreshLiveUpdateNow();
        final canPromote = await _widgetSync.canPostPromotedNotifications();
        if (!mounted) return;
        setState(() => _canPromoteLiveNotifications = canPromote);
        if (!canPromote) {
          await _promptPromotedNotificationSettings();
        } else {
          TintaToast.success(
            context,
            'Élő tevékenység (Now Bar) aktiválva',
          );
        }
      } else {
        setState(() => _canPromoteLiveNotifications = true);
        TintaToast.info(
          context,
          'Élő tevékenység kikapcsolva',
        );
      }
    } catch (_) {
      if (mounted) {
        TintaToast.error(context, 'Nem sikerült módosítani az élő tevékenységet');
      }
    } finally {
      if (mounted) setState(() => _togglingLiveActivity = false);
    }
  }

  Future<void> _promptPromotedNotificationSettings() async {
    if (!mounted) return;
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.initialPrefs;
    await showFloatingGlassSheet<void>(
      context: context,
      prefs: activePrefs,
      builder: (dialogCtx) {
        final theme = Theme.of(dialogCtx);
        final scheme = theme.colorScheme;
        final closeMode = activePrefs.modalCloseMode;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: FrostedBottomSheetSurface(
            prefs: activePrefs,
            showDragHandle: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.notifications_active_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        uwuLabel(
                          'Samsung Now Bar / Live Updates engedély',
                          enabled: activePrefs.uwuModeEnabled,
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (closeMode.showTopX) ...[
                      const SizedBox(width: 8),
                      PopupTopCloseButton(
                        onTap: () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  uwu(
                    'Android 16 és One UI alatt az állapotsoron és a zárolási képernyőn való kiemelt megjelenítéshez engedélyezd az „Élő értesítések” opciót a Tinta Napló rendszerbeállításaiban.',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: scheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      child: Text(
                        uwuLabel('Később', enabled: activePrefs.uwuModeEnabled),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(dialogCtx).pop();
                        unawaited(_widgetSync.openPromotedNotificationSettings());
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(
                        uwuLabel(
                          'Beállítások megnyitása',
                          enabled: activePrefs.uwuModeEnabled,
                        ),
                      ),
                    ),
                  ],
                ),
                if (closeMode.showBottomButton) ...[
                  const SizedBox(height: 12),
                  PopupBottomCloseButton(
                    onTap: () => Navigator.of(dialogCtx).pop(),
                    uwuEnabled: activePrefs.uwuModeEnabled,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _refreshLiveNow(UserProfilePrefs activePrefs) async {
    if (_refreshingLiveActivity) return;
    HapticFeedback.lightImpact();
    final primaryColor = Theme.of(context).colorScheme.primary;
    setState(() => _refreshingLiveActivity = true);
    try {
      await _widgetSync.syncPreferencesWithCachedLessons(
        prefs: activePrefs,
        themeAccent: primaryColor,
      );
      await _widgetSync.refreshLiveUpdateNow();
      if (!mounted) return;
      TintaToast.success(
        context,
        activePrefs.liveActivityEnabled
            ? 'Élő értesítés és kezdőképernyő modul frissítve'
            : 'Kezdőképernyő modulok frissítve',
      );
    } finally {
      if (mounted) setState(() => _refreshingLiveActivity = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppProvidersScope.maybeOf(context);

    Widget buildBody(UserProfilePrefs activePrefs) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final timeFmt = DateFormat('yyyy. MM. dd. HH:mm');
      final liveEnabled = activePrefs.liveActivityEnabled;

      return AdaptiveBackgroundScaffold(
        prefs: activePrefs,
        appBar: buildAdaptiveTransparentAppBar(
          context,
          title: uwu('Wear OS és Külső Integrációk'),
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
            const _DevSectionHeader('Zárolási Képernyő és Élő Értesítés', icon: Icons.notifications_active_outlined),
            SoftGlassCard(
              prefs: activePrefs,
              padding: const EdgeInsets.all(18),
              borderRadius: OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile.adaptive(
                    key: const ValueKey<String>(
                      'dev-live-activity-switch',
                    ),
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: scheme.primary,
                    title: Text(
                      uwuLabel(
                        'Élő tevékenység (Now Bar)',
                        enabled: activePrefs.uwuModeEnabled,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      uwuLabel(
                        'Aktuális óra és visszaszámláló megjelenítése a zárolási képernyőn és az állapotsoron',
                        enabled: activePrefs.uwuModeEnabled,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.74),
                      ),
                    ),
                    value: liveEnabled,
                    onChanged: _togglingLiveActivity
                        ? null
                        : (val) => _toggleLiveActivity(activePrefs, val),
                  ),
                  if (liveEnabled && !_canPromoteLiveNotifications) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey<String>(
                        'dev-live-activity-promotion-banner',
                      ),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.42),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            uwuLabel(
                              'Now Bar / Live Updates kiemelési engedély hiányzik.',
                              enabled: activePrefs.uwuModeEnabled,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            key: const ValueKey<String>(
                              'dev-live-activity-open-promo-btn',
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              unawaited(
                                _widgetSync.openPromotedNotificationSettings(),
                              );
                            },
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: Text(
                              uwuLabel(
                                'Now Bar engedélyezése',
                                enabled: activePrefs.uwuModeEnabled,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey<String>(
                        'dev-live-activity-refresh-btn',
                      ),
                      onPressed: _refreshingLiveActivity
                          ? null
                          : () => _refreshLiveNow(activePrefs),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      icon: _refreshingLiveActivity
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.notifications_active_outlined, size: 16),
                      label: Text(
                        uwuLabel(
                          'Élő értesítés frissítése most',
                          enabled: activePrefs.uwuModeEnabled,
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: const ValueKey<String>(
                      'dev-live-activity-tutorial-card',
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                uwuLabel(
                                  'Bekapcsolási útmutató (Samsung / Android 16+):',
                                  enabled: activePrefs.uwuModeEnabled,
                                ),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          uwuLabel(
                            'Beállítások → Fejlesztői beállítások → További beállítások (More settings) → Élő tevékenységek engedélyezése minden alkalmazáshoz (Allow Live Activities for all apps)',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: scheme.onSurface.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _DevSectionHeader('Viselhető Eszközök (Wear OS)', icon: Icons.watch_outlined),
            SoftGlassCard(
              prefs: activePrefs,
              padding: const EdgeInsets.all(18),
              borderRadius: OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    uwu('Wear OS Okosóra Kapcsolat'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DevInfoRow(
                    'Állapot',
                    _loading
                        ? 'Lekérdezés...'
                        : (_status.isConnected
                            ? 'Csatlakozva'
                            : 'Nincs csatlakozva'),
                  ),
                  _DevInfoRow(
                    'Eszköz',
                    _status.resolvedDeviceName ?? 'Ismeretlen / nem elérhető',
                  ),
                  _DevInfoRow(
                    'Utolsó szinkron',
                    _status.lastSyncedAt != null
                        ? timeFmt.format(_status.lastSyncedAt!)
                        : '-',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _syncing
                              ? null
                              : () => _manualWearSync(activePrefs),
                          icon: _syncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.watch_rounded, size: 18),
                          label: Text(
                            uwuLabel(
                              'Manuális óra szinkron',
                              enabled: activePrefs.uwuModeEnabled,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: uwuLabel(
                          'Állapot frissítése',
                          enabled: activePrefs.uwuModeEnabled,
                        ),
                        onPressed: _refreshWear,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const _DevSectionHeader('Utazástervező Integráció', icon: Icons.directions_bus_rounded),
            SoftGlassCard(
              prefs: activePrefs,
              padding: const EdgeInsets.all(18),
              borderRadius: OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    uwu('MenetrendGO Mélyhivatkozás'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DevInfoRow(
                    'Otthoni megálló',
                    activePrefs.primaryHomeStop.isNotEmpty
                        ? activePrefs.primaryHomeStop
                        : 'Nincs megadva',
                  ),
                  _DevInfoRow(
                    'Iskolai megálló',
                    activePrefs.primarySchoolStop.isNotEmpty
                        ? activePrefs.primarySchoolStop
                        : 'Nincs megadva',
                  ),
                  _DevInfoRow(
                    'Séta tempó',
                    '${activePrefs.walkingSpeedKmh.toStringAsFixed(1)} km/h',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      unawaited(
                        MenetrendService.openInMenetrendGo(prefs: activePrefs),
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(
                      uwuLabel(
                        'MenetrendGO mélyhivatkozás teszt',
                        enabled: activePrefs.uwuModeEnabled,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (scope == null) {
      return buildBody(_localPrefs);
    }
    return AnimatedBuilder(
      animation: scope.settings,
      builder: (context, _) => buildBody(_activePrefs(context)),
    );
  }
}

// =============================================================================
// 5. Rendszer, Cache és Naplók
// =============================================================================
class DeveloperSystemCacheSubPage extends StatefulWidget {
  final UserProfilePrefs initialPrefs;
  final TokenStorageService? tokenStorage;

  const DeveloperSystemCacheSubPage({
    super.key,
    required this.initialPrefs,
    this.tokenStorage,
  });

  @override
  State<DeveloperSystemCacheSubPage> createState() =>
      _DeveloperSystemCacheSubPageState();
}

class _DeveloperSystemCacheSubPageState
    extends State<DeveloperSystemCacheSubPage> {
  String _version = GitHubUpdaterService.fallbackAppVersion;
  String _buildNumber = GitHubUpdaterService.fallbackBuildNumber;
  bool _clearingCache = false;
  bool _resettingGlow = false;

  TokenStorageService get _storage =>
      widget.tokenStorage ?? const TokenStorageService();

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final (ver, buildNum) = await GitHubUpdaterService.getAppVersionInfo();
      if (!mounted) return;
      setState(() {
        _version = ver;
        _buildNumber = buildNum;
      });
    } catch (_) {}
  }

  Future<void> _clearDashboardCache() async {
    if (_clearingCache) return;
    setState(() => _clearingCache = true);
    try {
      final session = await _storage.loadSession();
      if (session != null) {
        await _storage.clearDashboardCache(
          TokenStorageService.accountKeyForSession(session),
        );
      }
      if (!mounted) return;
      TintaToast.success(context, 'Helyi gyorsítótár sikeresen törölve');
    } catch (_) {
      if (!mounted) return;
      TintaToast.error(context, 'Gyorsítótár törlése sikertelen');
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _resetGradeGlowBaseline(UserProfilePrefs activePrefs) async {
    if (_resettingGlow) return;
    setState(() => _resettingGlow = true);
    try {
      final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
      if (scope != null) {
        await scope.settings.resetGradeGlowBaseline(
          previewGrades: activePrefs.demoModeEnabled
              ? DemoDataService.instance.buildDemoGrades().take(3)
              : null,
        );
      }
      if (!mounted) return;
      TintaToast.success(
        context,
        'Új jegy ragyogás alapállapota visszaállítva',
      );
    } catch (_) {
      if (mounted) {
        TintaToast.error(context, 'Alapállapot visszaállítása sikertelen');
      }
    } finally {
      if (mounted) setState(() => _resettingGlow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.initialPrefs;
    final theme = Theme.of(context);

    return AdaptiveBackgroundScaffold(
      prefs: activePrefs,
      appBar: buildAdaptiveTransparentAppBar(
        context,
        title: uwu('Rendszer, Cache és Naplók'),
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
          const _DevSectionHeader('Alkalmazás és Rendszer Telemetria', icon: Icons.analytics_outlined),
          SoftGlassCard(
            prefs: activePrefs,
            padding: const EdgeInsets.all(18),
            borderRadius: OledTheme.largeRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  uwu('Alkalmazás és Rendszer Telemetria'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                _DevInfoRow('Verzió', 'v$_version (+$_buildNumber)'),
                _DevInfoRow('Platform', Platform.operatingSystem),
                _DevInfoRow('OS verzió', Platform.operatingSystemVersion),
                _DevInfoRow(
                  'CPU magok',
                  '${Platform.numberOfProcessors} logikai szál',
                ),
                _DevInfoRow('Téma', activePrefs.themeStyle.name),
                _DevInfoRow(
                  'Aktív módok',
                  [
                    if (activePrefs.minimalistModeEnabled) 'Minimalista',
                    if (activePrefs.demoModeEnabled) 'Demó',
                    if (activePrefs.uwuModeEnabled) 'UwU',
                    if (!activePrefs.minimalistModeEnabled &&
                        !activePrefs.demoModeEnabled &&
                        !activePrefs.uwuModeEnabled)
                      'Alapértelmezett',
                  ].join(', '),
                ),
                const SizedBox(height: 14),
                TactileBounce(
                  onTap: () {
                    final apkName =
                        GitHubUpdaterService.apkFileNameForTag('v$_version');
                    GitHubUpdaterService.showFrostedUpdateDialog(
                      context,
                      currentVersion: _version,
                      release: GitHubReleaseInfo(
                        tagName: 'v$_version',
                        title: 'Tinta Napló v$_version - OTA Frissítő Előnézet',
                        releaseNotes:
                            '• 120Hz-es fizikai animációk és Hero átmenetek\n'
                            '• MenetrendGO reggeli/délutáni helyreállítás és Szünet visszaszámláló\n'
                            '• Többoldalas Fejlesztői Központ, elszigetelt Demó mód és Minimalista javítások\n'
                            '• Közvetlen GitHub Releases APK letöltés és telepítés ($apkName)',
                        htmlUrl: GitHubUpdaterService.repoUrl,
                        apkDownloadUrl:
                            '${GitHubUpdaterService.repoUrl}/releases/latest/download/$apkName',
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
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
          ),
          const SizedBox(height: 16),
          const _DevSectionHeader('Gyorsítótár és Karbantartás', icon: Icons.cleaning_services_outlined),
          SoftGlassCard(
            prefs: activePrefs,
            padding: const EdgeInsets.all(18),
            borderRadius: OledTheme.largeRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  uwu('Gyorsítótár és Állapot Visszaállítás'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _clearingCache ? null : _clearDashboardCache,
                  icon: _clearingCache
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cleaning_services_rounded, size: 18),
                  label: Text(
                    uwuLabel(
                      'Helyi dashboard cache törlése',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _resettingGlow
                      ? null
                      : () => _resetGradeGlowBaseline(activePrefs),
                  icon: _resettingGlow
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    uwuLabel(
                      'Új jegy ragyogás alaphelyzetbe állítása',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DevInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _DevInfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              uwuLabel(label),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.62),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              uwuLabel(value),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
