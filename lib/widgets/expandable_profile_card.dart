import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../services/demo_data_service.dart';
import '../services/kreta_client.dart';
import '../services/token_storage_service.dart';
import '../services/wear_sync_service.dart';
import '../utils/greeting_utils.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';
import 'bug_report_sheet.dart';
import 'glass_card.dart';
import 'tinta_toast.dart';

/// Sleek top-right CircleAvatar icon for the HomeScreen AppBar.
/// Wrapped in a `Hero('profile_avatar_hero')` so tapping animates the avatar
/// smoothly into the expanded Profile sheet and boomerangs it back on dismiss.
class ProfileTopBarAvatar extends StatelessWidget {
  final UserProfilePrefs prefs;
  final VoidCallback onTap;

  const ProfileTopBarAvatar({
    super.key,
    required this.prefs,
    required this.onTap,
  });

  File? _resolveValidPhotoFile() {
    if (prefs.demoModeEnabled) return null;
    final path = prefs.customPhotoPath;
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatarAccent = prefs.christmasModeEnabled
        ? const Color(0xFFD32F2F)
        : scheme.primary;
    final photoFile = _resolveValidPhotoFile();
    final isDemo = prefs.demoModeEnabled;

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: TactileBounce(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Hero(
              tag: 'profile_avatar_hero',
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: avatarAccent.withValues(alpha: 0.9),
                      width: 2,
                    ),
                  ),
                  child: isDemo
                      ? DemoStudentAvatar(
                          size: 38,
                          accentColor: avatarAccent,
                        )
                      : CircleAvatar(
                          radius: 19,
                          backgroundColor: avatarAccent.withValues(alpha: 0.2),
                          backgroundImage:
                              photoFile != null ? FileImage(photoFile) : null,
                          child: photoFile == null
                              ? Icon(
                                  Icons.person_rounded,
                                  color: avatarAccent,
                                  size: 20,
                                )
                              : null,
                        ),
                ),
              ),
            ),
            if (prefs.christmasModeEnabled)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.4),
                  ),
                  child: const Icon(
                    Icons.ac_unit_rounded,
                    size: 9,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens the streamlined Profile & Settings modal bottom sheet using a
/// [PageRouteBuilder] so `Hero('profile_avatar_hero')` boomerangs seamlessly
/// between the top-right AppBar and the expanded profile modal.
Future<void> showStreamlinedProfileSheet({
  required BuildContext context,
  required Student? student,
  required StoredSession session,
  KretaClient? kretaClient,
  WearSyncService? wearSyncService,
  required UserProfilePrefs prefs,
  required ValueChanged<UserProfilePrefs> onPrefsChanged,
  required VoidCallback onOpenFullSettings,
}) {
  HapticFeedback.lightImpact();

  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Bezárás',
      barrierColor: resolveSoftBlurBarrierColor(
        context,
        prefs: prefs,
        solidDarkAlpha: 0.65,
        solidLightAlpha: 0.45,
      ),
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 230),
      pageBuilder: (sheetContext, animation, secondaryAnimation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (ModalRoute.of(sheetContext)?.isCurrent ?? true) {
                Navigator.of(sheetContext).pop();
              }
            },
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.16),
                  end: Offset.zero,
                ).animate(curved),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {},
                    child: _StreamlinedProfileModalSheet(
                      student: student,
                      session: session,
                      kretaClient: kretaClient,
                      wearSyncService: wearSyncService,
                      initialPrefs: prefs,
                      onPrefsChanged: onPrefsChanged,
                      contentOpacityAnimation: curved,
                      onOpenFullSettings: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.of(sheetContext).pop();
                        onOpenFullSettings();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _StreamlinedProfileModalSheet extends StatefulWidget {
  final Student? student;
  final StoredSession session;
  final KretaClient? kretaClient;
  final WearSyncService? wearSyncService;
  final UserProfilePrefs initialPrefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onOpenFullSettings;
  final Animation<double>? contentOpacityAnimation;

  const _StreamlinedProfileModalSheet({
    required this.student,
    required this.session,
    this.kretaClient,
    this.wearSyncService,
    required this.initialPrefs,
    required this.onPrefsChanged,
    required this.onOpenFullSettings,
    this.contentOpacityAnimation,
  });

  @override
  State<_StreamlinedProfileModalSheet> createState() =>
      _StreamlinedProfileModalSheetState();
}

class _StreamlinedProfileModalSheetState
    extends State<_StreamlinedProfileModalSheet> {
  late UserProfilePrefs _prefs;
  late final TextEditingController _nicknameController;
  final ImagePicker _imagePicker = ImagePicker();
  WearConnectionStatus _wearStatus = WearConnectionStatus.disconnected;
  bool _isSyncingWear = false;
  bool _wearSyncedRecently = false;

  WearSyncService get _wearService =>
      widget.wearSyncService ?? WearSyncService.instance;

  @override
  void initState() {
    super.initState();
    _prefs = widget.initialPrefs;
    _nicknameController = TextEditingController(text: _prefs.nickname ?? '');
    unawaited(_loadWearStatus());
  }

  Future<void> _loadWearStatus() async {
    final status = await _wearService.getConnectionStatus();
    if (!mounted) return;
    setState(() => _wearStatus = status);
  }

  Future<void> _syncWithWatch() async {
    if (_isSyncingWear) return;
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? _prefs;
    setState(() {
      _isSyncingWear = true;
      _wearSyncedRecently = false;
    });
    StoredSession active = widget.session;
    if (active.isExpired && widget.kretaClient != null) {
      try {
        active = await widget.kretaClient!.ensureValidSession(active);
      } catch (_) {}
    }
    final ok = await _wearService.syncSessionToWatch(
      session: active,
      student: widget.student,
      nickname: activePrefs.nickname,
      forceSync: true,
    );
    final refreshedStatus = await _wearService.getConnectionStatus();
    if (!mounted) return;
    setState(() {
      _isSyncingWear = false;
      _wearSyncedRecently = ok;
      if (refreshedStatus.isConnected) {
        _wearStatus = refreshedStatus;
      }
    });
    TintaToast.show(
      context,
      ok
          ? 'Munkamenet szinkronizálva az órával'
          : 'Nem sikerült szinkronizálni az órával',
      type: ok ? TintaToastType.success : TintaToastType.error,
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _applyPrefs(UserProfilePrefs next) {
    UserProfilePrefs.syncActiveGlobals(next);
    final scope = AppProvidersScope.maybeOf(context);
    if (scope != null) {
      scope.settings.updatePrefs(next);
    } else {
      TokenStorageService.saveProfilePrefsToSharedPrefs(next);
    }
    setState(() => _prefs = next);
    widget.onPrefsChanged(next);
  }

  void _saveNickname() {
    final trimmed = _nicknameController.text.trim();
    _applyPrefs(
      _prefs.copyWith(
        nickname: trimmed.isEmpty ? null : trimmed,
        clearNickname: trimmed.isEmpty,
      ),
    );
    FocusScope.of(context).unfocus();
  }

  Future<void> _pickCustomPhoto() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 88,
      );
      if (picked != null && picked.path.isNotEmpty) {
        _applyPrefs(_prefs.copyWith(customPhotoPath: picked.path));
      }
    } catch (e) {
      if (!mounted) return;
      TintaToast.error(context, 'Nem sikerült betölteni a képet: $e');
    }
  }

  File? _resolveValidPhotoFile(UserProfilePrefs prefs) {
    if (prefs.demoModeEnabled) return null;
    final path = prefs.customPhotoPath;
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  Widget _buildMenuIconBubble({
    required BuildContext context,
    required IconData icon,
    required Color tint,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : theme.colorScheme.onSurface.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: Icon(icon, size: 20, color: tint),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? _prefs;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final avatarAccent = activePrefs.christmasModeEnabled
        ? const Color(0xFFD32F2F)
        : scheme.primary;
    final isDemo = activePrefs.demoModeEnabled;
    final photoFile = _resolveValidPhotoFile(activePrefs);

    final displayNick = isDemo
        ? (widget.student?.name ?? DemoDataService.demoStudentName)
        : GreetingUtils.resolveDisplayName(
            customNickname: activePrefs.nickname,
            fullStudentName: widget.student?.name,
          );

    final menuTileBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : scheme.surfaceContainerHigh.withValues(alpha: 0.55);
    final menuTileBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : scheme.onSurface.withValues(alpha: 0.10);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: LiquidGlassSurface(
        prefs: activePrefs,
        highContrastExpanded: true,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        contentOpacityAnimation: widget.contentOpacityAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              Center(
                child: GestureDetector(
                  onTap: isDemo ? null : _pickCustomPhoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Hero(
                        tag: 'profile_avatar_hero',
                        child: Material(
                          type: MaterialType.transparency,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: avatarAccent,
                                width: 2.5,
                              ),
                            ),
                            child: isDemo
                                ? DemoStudentAvatar(
                                    size: 80,
                                    accentColor: avatarAccent,
                                    showClassBadge: true,
                                  )
                                : CircleAvatar(
                                    radius: 40,
                                    backgroundColor:
                                        avatarAccent.withValues(alpha: 0.2),
                                    backgroundImage: photoFile != null
                                        ? FileImage(photoFile)
                                        : null,
                                    child: photoFile == null
                                        ? Icon(
                                            Icons.person_rounded,
                                            color: avatarAccent,
                                            size: 40,
                                          )
                                        : null,
                                  ),
                          ),
                        ),
                      ),
                      if (!isDemo)
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.scaffoldBackgroundColor,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.photo_camera_rounded,
                              size: 14,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                displayNick,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
              if (widget.student?.instituteName.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  widget.student!.instituteName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (!isDemo) ...[
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _pickCustomPhoto,
                      icon: const Icon(
                        Icons.photo_library_rounded,
                        size: 18,
                      ),
                      label: Text(
                        photoFile != null
                            ? 'Új kép választása'
                            : 'Kép galériából',
                      ),
                    ),
                    if (photoFile != null)
                      OutlinedButton.icon(
                        onPressed: () => _applyPrefs(
                          activePrefs.copyWith(clearCustomPhoto: true),
                        ),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Kép törlése'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nicknameController,
                        decoration: InputDecoration(
                          labelText: uwu('Becenév szerkesztése'),
                          hintText: 'pl. Alexa',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          suffixIcon: _nicknameController.text.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Törlés',
                                  onPressed: () {
                                    _nicknameController.clear();
                                    _saveNickname();
                                  },
                                  icon:
                                      const Icon(Icons.clear_rounded, size: 18),
                                )
                              : null,
                        ),
                        onSubmitted: (_) => _saveNickname(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: avatarAccent,
                        foregroundColor: scheme.onPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      onPressed: _saveNickname,
                      child: Text(
                        uwu('Mentés'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (_wearStatus.isConnected) ...[
                Container(
                  key: const ValueKey<String>('profile-wear-sync-card'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: menuTileBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: menuTileBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      _buildMenuIconBubble(
                        context: context,
                        icon: Icons.watch_rounded,
                        tint: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _wearStatus.resolvedDeviceName ?? 'Wear OS óra',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            Text(
                              _wearSyncedRecently
                                  ? 'Szinkronizálva'
                                  : (_wearStatus.lastSyncedAt != null
                                      ? 'Csatlakozva • ${DateFormat('HH:mm').format(_wearStatus.lastSyncedAt!)}'
                                      : 'Wear OS csatlakozva'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _wearSyncedRecently
                                    ? const Color(0xFF26D0A8)
                                    : scheme.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        key: const ValueKey<String>('profile-wear-sync-button'),
                        onPressed: _isSyncingWear ? null : _syncWithWatch,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: _isSyncingWear
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Szinkronizálás órával',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TactileBounce(
                key: const ValueKey<String>('profile-bug-report-tile'),
                pressedScale: 0.98,
                onTap: () => showBugReportSheet(
                  context,
                  student: widget.student,
                  prefs: activePrefs,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: menuTileBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: menuTileBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      _buildMenuIconBubble(
                        context: context,
                        icon: Icons.bug_report_rounded,
                        tint: const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              uwu('Hibajelentés'),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            Text(
                              uwu('Hiba vagy visszajelzés küldése'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TactileBounce(
                key: const ValueKey<String>('profile-settings-tile'),
                pressedScale: 0.98,
                onTap: widget.onOpenFullSettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.32),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildMenuIconBubble(
                        context: context,
                        icon: Icons.settings_rounded,
                        tint: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              uwu('Alkalmazás beállítások'),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.onSurface,
                              ),
                            ),
                            Text(
                              uwu('Témák, értesítések, MenetrendGO és fiók'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.68),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
