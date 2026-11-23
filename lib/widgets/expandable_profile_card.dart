import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../screens/school_year_schedule_screen.dart';
import '../services/demo_data_service.dart';
import '../services/kreta_client.dart';
import '../services/school_year_schedule_service.dart';
import '../services/token_storage_service.dart';
import '../services/wear_sync_service.dart';
import '../theme/oled_theme.dart';
import '../utils/greeting_utils.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';
import 'bug_report_sheet.dart';
import 'frosted_inspection_modal.dart';
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
    final isMinimalist = prefs.minimalistModeEnabled;
    final avatarRadius = isMinimalist ? 14.0 : 19.0;

    return Padding(
      padding: EdgeInsets.only(right: isMinimalist ? 10 : 14),
      child: TactileBounce(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Hero(
              tag: 'profile_avatar_hero',
              createRectTween: createLinearHeroRectTween,
              flightShuttleBuilder: buildBoomerangBadgeHeroShuttle,
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: EdgeInsets.all(isMinimalist ? 1.5 : 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: avatarAccent.withValues(alpha: 0.9),
                      width: isMinimalist ? 1.5 : 2,
                    ),
                  ),
                  child: isDemo
                      ? DemoStudentAvatar(
                          size: avatarRadius * 2,
                          accentColor: avatarAccent,
                        )
                      : CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: avatarAccent.withValues(alpha: 0.2),
                          backgroundImage:
                              photoFile != null ? FileImage(photoFile) : null,
                          child: photoFile == null
                              ? Icon(
                                  Icons.person_rounded,
                                  color: avatarAccent,
                                  size: isMinimalist ? 16 : 20,
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

/// Opens the streamlined Profile & Settings modal bottom sheet using
/// [showFloatingGlassSheet] so the card floats detached with Liquid Glass
/// translucency while `Hero('profile_avatar_hero')` boomerangs linearly
/// between the top-right AppBar and the expanded profile sheet.
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

  return showFloatingGlassSheet<void>(
    context: context,
    prefs: prefs,
    barrierColor: resolveSoftBlurBarrierColor(
      context,
      prefs: prefs,
      solidDarkAlpha: 0.65,
      solidLightAlpha: 0.45,
      glassDarkAlpha: 0.46,
      glassLightAlpha: 0.30,
    ),
    builder: (sheetContext) {
      return _StreamlinedProfileModalSheet(
        student: student,
        session: session,
        kretaClient: kretaClient,
        wearSyncService: wearSyncService,
        initialPrefs: prefs,
        onPrefsChanged: onPrefsChanged,
        onOpenFullSettings: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(sheetContext).pop();
          onOpenFullSettings();
        },
      );
    },
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

  const _StreamlinedProfileModalSheet({
    required this.student,
    required this.session,
    this.kretaClient,
    this.wearSyncService,
    required this.initialPrefs,
    required this.onPrefsChanged,
    required this.onOpenFullSettings,
  });

  @override
  State<_StreamlinedProfileModalSheet> createState() =>
      _StreamlinedProfileModalSheetState();
}

class _StreamlinedProfileModalSheetState
    extends State<_StreamlinedProfileModalSheet> {
  late UserProfilePrefs _prefs;
  final ImagePicker _imagePicker = ImagePicker();
  WearConnectionStatus _wearStatus = WearConnectionStatus.disconnected;
  SchoolYearSchedule? _schoolYearSchedule;
  String? _pinnedCountdownEventId;

  WearSyncService get _wearService =>
      widget.wearSyncService ?? WearSyncService.instance;

  @override
  void initState() {
    super.initState();
    _prefs = widget.initialPrefs;
    unawaited(_loadWearStatus());
    unawaited(_loadSchoolYearPreview());
  }

  Future<void> _loadSchoolYearPreview() async {
    final schedule =
        await SchoolYearScheduleService.instance.loadCachedOrFallback(
      student: widget.student,
      instituteCode: widget.session.instituteCode,
    );
    final pinnedId = await SchoolYearScheduleService.instance
        .loadPinnedCountdownEventId(widget.session.instituteCode);
    if (!mounted) return;
    setState(() {
      _schoolYearSchedule = schedule;
      _pinnedCountdownEventId = pinnedId;
    });
  }

  Future<void> _loadWearStatus() async {
    final status = await _wearService.getConnectionStatus();
    if (!mounted) return;
    setState(() => _wearStatus = status);
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

  Future<void> _openNicknameEditorPopup(UserProfilePrefs activePrefs) async {
    HapticFeedback.selectionClick();
    final ctrl = TextEditingController(text: activePrefs.nickname ?? '');
    await showFloatingGlassSheet<void>(
      context: context,
      prefs: activePrefs,
      builder: (sheetCtx) {
        return SheetDisposableScope(
          disposables: [ctrl],
          builder: (_) => StatefulBuilder(
            builder: (innerCtx, setSheetState) {
              final theme = Theme.of(innerCtx);
              final scheme = theme.colorScheme;
              final closeMode = activePrefs.modalCloseMode;
              final bottomInset = MediaQuery.viewInsetsOf(innerCtx).bottom;
              final hasSavedNickname =
                  (activePrefs.nickname ?? '').trim().isNotEmpty;
              final fullName = (widget.student?.name ?? '').trim();

              void commitNickname([String? explicitValue]) {
                final trimmed = (explicitValue ?? ctrl.text).trim();
                _applyPrefs(
                  activePrefs.copyWith(
                    nickname: trimmed.isEmpty ? null : trimmed,
                    clearNickname: trimmed.isEmpty,
                  ),
                );
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.of(sheetCtx).pop();
              }

              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 460,
                    maxHeight:
                        (MediaQuery.sizeOf(innerCtx).height - bottomInset) *
                            0.84,
                  ),
                  child: FrostedBottomSheetSurface(
                    key: const ValueKey<String>('profile-nickname-sheet'),
                    prefs: activePrefs,
                    showDragHandle: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: SingleChildScrollView(
                      physics: const FloatingSheetScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
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
                                  Icons.badge_outlined,
                                  size: 20,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      uwuLabel(
                                        'Becenév',
                                        enabled: activePrefs.uwuModeEnabled,
                                      ),
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    if (fullName.isNotEmpty)
                                      Text(
                                        fullName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.62),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (closeMode.showTopX) ...[
                                const SizedBox(width: 8),
                                PopupTopCloseButton(
                                  onTap: () => Navigator.of(sheetCtx).pop(),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            key: const ValueKey<String>(
                              'profile-nickname-input',
                            ),
                            controller: ctrl,
                            autofocus: true,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setSheetState(() {}),
                            onSubmitted: (_) => commitNickname(),
                            decoration: InputDecoration(
                              labelText: uwuLabel(
                                'Megjelenített név / Becenév',
                                enabled: activePrefs.uwuModeEnabled,
                              ),
                              hintText: uwuLabel(
                                'Hagyd üresen a keresztnevedhez',
                                enabled: activePrefs.uwuModeEnabled,
                              ),
                              prefixIcon:
                                  const Icon(Icons.person_outline_rounded),
                              suffixIcon: ctrl.text.isNotEmpty
                                  ? IconButton(
                                      tooltip: uwuLabel(
                                        'Mező törlése',
                                        enabled: activePrefs.uwuModeEnabled,
                                      ),
                                      onPressed: () {
                                        ctrl.clear();
                                        setSheetState(() {});
                                      },
                                      icon: const Icon(
                                        Icons.clear_rounded,
                                        size: 18,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              if (hasSavedNickname)
                                TextButton.icon(
                                  key: const ValueKey<String>(
                                    'profile-nickname-clear-btn',
                                  ),
                                  onPressed: () => commitNickname(''),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 17,
                                    color: scheme.error,
                                  ),
                                  label: Text(
                                    uwuLabel(
                                      'Törlés',
                                      enabled: activePrefs.uwuModeEnabled,
                                    ),
                                    style: TextStyle(color: scheme.error),
                                  ),
                                ),
                              const Spacer(),
                              TextButton(
                                onPressed: () => Navigator.of(sheetCtx).pop(),
                                child: Text(
                                  uwuLabel(
                                    'Mégse',
                                    enabled: activePrefs.uwuModeEnabled,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                key: const ValueKey<String>(
                                  'profile-nickname-save-btn',
                                ),
                                onPressed: () => commitNickname(),
                                child: Text(
                                  uwuLabel(
                                    'Mentés',
                                    enabled: activePrefs.uwuModeEnabled,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (closeMode.showBottomButton) ...[
                            const SizedBox(height: 12),
                            PopupBottomCloseButton(
                              onTap: () => Navigator.of(sheetCtx).pop(),
                              uwuEnabled: activePrefs.uwuModeEnabled,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openAvatarOptionsPopup(
    UserProfilePrefs activePrefs,
    File? currentPhotoFile,
  ) async {
    HapticFeedback.selectionClick();
    final action = await showFloatingGlassSheet<String>(
      context: context,
      prefs: activePrefs,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final scheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final closeMode = activePrefs.modalCloseMode;
        final hasPhoto = currentPhotoFile != null;

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: FrostedBottomSheetSurface(
            key: const ValueKey<String>('profile-avatar-options-sheet'),
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
                        Icons.photo_camera_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        uwuLabel(
                          'Profilkép',
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
                        onTap: () => Navigator.of(sheetCtx).pop(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                TactileBounce(
                  key: const ValueKey<String>('profile-avatar-pick-btn'),
                  pressedScale: 0.98,
                  onTap: () => Navigator.of(sheetCtx).pop('pick'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(
                        alpha: isDark ? 0.14 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_photo_alternate_rounded,
                          color: scheme.primary,
                          size: 21,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            uwuLabel(
                              'Új profilkép választása',
                              enabled: activePrefs.uwuModeEnabled,
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
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
                if (hasPhoto) ...[
                  const SizedBox(height: 10),
                  TactileBounce(
                    key: const ValueKey<String>('profile-avatar-delete-btn'),
                    pressedScale: 0.98,
                    onTap: () => Navigator.of(sheetCtx).pop('delete'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(
                          alpha: isDark ? 0.14 : 0.08,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.error.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            color: scheme.error,
                            size: 21,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              uwuLabel(
                                'Jelenlegi kép törlése',
                                enabled: activePrefs.uwuModeEnabled,
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (closeMode.showBottomButton) ...[
                  const SizedBox(height: 14),
                  PopupBottomCloseButton(
                    onTap: () => Navigator.of(sheetCtx).pop(),
                    label: 'Mégse',
                    uwuEnabled: activePrefs.uwuModeEnabled,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'pick') {
      await _pickCustomPhoto();
    } else if (action == 'delete') {
      _applyPrefs(activePrefs.copyWith(clearCustomPhoto: true));
    }
  }

  Future<void> _pickCustomPhoto() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 88,
      );
      if (!mounted) return;
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
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFF4F6F8);
    final menuTileBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final maxSheetHeight =
        ((MediaQuery.sizeOf(context).height - bottomInset) * 0.86)
            .clamp(240.0, 820.0);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: maxSheetHeight,
        ),
        child: FrostedBottomSheetSurface(
          key: const ValueKey<String>('profile-floating-sheet-surface'),
          prefs: activePrefs,
          topRadius: 26.0,
          showDragHandle: true,
          includeSafeAreaBottom: true,
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: GestureDetector(
                        key: const ValueKey<String>('profile-avatar-tap'),
                        onTap: isDemo
                            ? null
                            : () => _openAvatarOptionsPopup(
                                  activePrefs,
                                  photoFile,
                                ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Hero(
                              tag: 'profile_avatar_hero',
                              createRectTween: createLinearHeroRectTween,
                              flightShuttleBuilder:
                                  buildBoomerangBadgeHeroShuttle,
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
                                          backgroundColor: avatarAccent
                                              .withValues(alpha: 0.2),
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
                                child: _DeferredCameraBadge(
                                  backgroundColor: scheme.primary,
                                  iconColor: scheme.onPrimary,
                                  borderColor: theme.scaffoldBackgroundColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (activePrefs.modalCloseMode.showTopX)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: PopupTopCloseButton(
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: TactileBounce(
                    key: const ValueKey<String>('profile-name-tap'),
                    pressedScale: 0.97,
                    onTap: isDemo
                        ? null
                        : () => _openNicknameEditorPopup(activePrefs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: isDemo
                            ? Colors.transparent
                            : scheme.onSurface.withValues(
                                alpha: isDark ? 0.04 : 0.035,
                              ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              uwuLabel(
                                displayNick,
                                enabled: activePrefs.uwuModeEnabled,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          if (!isDemo) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: scheme.primary.withValues(alpha: 0.82),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.student?.instituteName.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    uwuLabel(
                      widget.student!.instituteName,
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
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
                              uwuLabel(
                                _wearStatus.resolvedDeviceName ?? 'Wear OS óra',
                                enabled: activePrefs.uwuModeEnabled,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            Text(
                              uwuLabel(
                                _wearStatus.lastSyncedAt != null
                                    ? 'Csatlakozva • ${DateFormat('HH:mm').format(_wearStatus.lastSyncedAt!)}'
                                    : 'Wear OS csatlakozva',
                                enabled: activePrefs.uwuModeEnabled,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              _buildSchoolYearTile(
                context: context,
                theme: theme,
                scheme: scheme,
                activePrefs: activePrefs,
                menuTileBg: menuTileBg,
                menuTileBorder: menuTileBorder,
              ),
              const SizedBox(height: 10),
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
                        tint: OledTheme.semanticForeground(
                          const Color(0xFFF59E0B),
                          theme.brightness,
                        ),
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
              if (activePrefs.modalCloseMode.showBottomButton) ...[
                const SizedBox(height: 14),
                PopupBottomCloseButton(
                  onTap: () => Navigator.of(context).pop(),
                  uwuEnabled: activePrefs.uwuModeEnabled,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildSchoolYearTile({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme scheme,
    required UserProfilePrefs activePrefs,
    required Color menuTileBg,
    required Color menuTileBorder,
  }) {
    final now = DateTime.now();
    final schedule = _schoolYearSchedule;
    final activeEv = schedule?.activeEventOn(now);
    final countdownTarget = schedule != null
        ? SchoolYearScheduleService.instance.resolveCountdownEvent(
            schedule,
            now,
            pinnedEventId: _pinnedCountdownEventId,
          )
        : null;
    final targetEv = activeEv ?? countdownTarget ?? schedule?.nextUpcomingEvent(now);
    String subtitle = 'Szünetek, ünnepek és tanév naptár';
    if (targetEv != null) {
      if (targetEv.isOngoingOn(now)) {
        subtitle = '${targetEv.title} • még ${targetEv.daysRemaining(now)} nap';
      } else {
        final days = targetEv.daysUntil(now);
        subtitle = days == 0
            ? '${targetEv.title} • Ma'
            : '${targetEv.title} • $days nap múlva';
      }
    }

    return TactileBounce(
      key: const ValueKey<String>('profile-school-year-tile'),
      pressedScale: 0.98,
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context)
            .push(
              SmoothSharedAxisRoute(
                page: SchoolYearScheduleScreen(
                  student: widget.student,
                  instituteCode: widget.session.instituteCode,
                  prefs: activePrefs,
                ),
              ),
            )
            .then((_) {
          if (mounted) {
            unawaited(_loadSchoolYearPreview());
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: menuTileBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: menuTileBorder, width: 1),
        ),
        child: Row(
          children: [
            _buildMenuIconBubble(
              context: context,
              icon: Icons.calendar_today_rounded,
              tint: OledTheme.semanticForeground(
                const Color(0xFF10B981),
                theme.brightness,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uwu('Tanév rendje', enabled: activePrefs.uwuModeEnabled),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    uwuLabel(subtitle, enabled: activePrefs.uwuModeEnabled),
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
    );
  }
}

/// Fades/scales in the small camera icon badge only once the Hero profile
/// avatar has landed, and hides it immediately on route reverse so it never
/// glitches or overlaps during the Hero flight animation.
class _DeferredCameraBadge extends StatelessWidget {
  final Color backgroundColor;
  final Color iconColor;
  final Color borderColor;

  const _DeferredCameraBadge({
    required this.backgroundColor,
    required this.iconColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final routeAnim = ModalRoute.of(context)?.animation;
    final badge = Container(
      key: const ValueKey<String>('profile-avatar-camera-badge'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: 2,
        ),
      ),
      child: Icon(
        Icons.photo_camera_rounded,
        size: 14,
        color: iconColor,
      ),
    );
    if (routeAnim == null) {
      return badge;
    }
    return AnimatedBuilder(
      animation: routeAnim,
      builder: (context, child) {
        if (routeAnim.status == AnimationStatus.reverse) {
          return const SizedBox.shrink();
        }
        final raw = routeAnim.value.clamp(0.0, 1.0);
        final progress = ((raw - 0.72) / 0.28).clamp(0.0, 1.0);
        if (progress <= 0.0) {
          return const SizedBox.shrink();
        }
        final scale = Curves.easeOutBack.transform(progress);
        return Opacity(
          opacity: Curves.easeOutCubic.transform(progress),
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
      child: badge,
    );
  }
}
