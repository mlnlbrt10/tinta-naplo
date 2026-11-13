import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/greeting_utils.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/token_storage_service.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';
import 'glass_card.dart';

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
                  child: CircleAvatar(
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
                      initialPrefs: prefs,
                      onPrefsChanged: onPrefsChanged,
                      contentOpacityAnimation: curved,
                      onOpenFullSettings: () {
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
  final UserProfilePrefs initialPrefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onOpenFullSettings;
  final Animation<double>? contentOpacityAnimation;

  const _StreamlinedProfileModalSheet({
    required this.student,
    required this.session,
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

  @override
  void initState() {
    super.initState();
    _prefs = widget.initialPrefs;
    _nicknameController = TextEditingController(text: _prefs.nickname ?? '');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _applyPrefs(UserProfilePrefs next) {
    UserProfilePrefs.syncActiveGlobals(next);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nem sikerült betölteni a képet: $e')),
      );
    }
  }

  File? _resolveValidPhotoFile() {
    final path = _prefs.customPhotoPath;
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final avatarAccent = _prefs.christmasModeEnabled
        ? const Color(0xFFD32F2F)
        : scheme.primary;
    final photoFile = _resolveValidPhotoFile();

    final displayNick = GreetingUtils.resolveDisplayName(
      customNickname: _prefs.nickname,
      fullStudentName: widget.student?.name,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: LiquidGlassSurface(
        prefs: _prefs,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        contentOpacityAnimation: widget.contentOpacityAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: _pickCustomPhoto,
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
                            child: CircleAvatar(
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
              const SizedBox(height: 12),
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
                      photoFile != null ? 'Új kép választása' : 'Kép galériából',
                    ),
                  ),
                  if (photoFile != null)
                    OutlinedButton.icon(
                      onPressed: () => _applyPrefs(
                        _prefs.copyWith(clearCustomPhoto: true),
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
                                icon: const Icon(Icons.clear_rounded, size: 18),
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
              const SizedBox(height: 20),
              TactileBounce(
                onTap: widget.onOpenFullSettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                    horizontal: 18,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.settings_rounded,
                        size: 20,
                        color: scheme.onPrimary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        uwu('Alkalmazás beállítások megnyitása'),
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
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
