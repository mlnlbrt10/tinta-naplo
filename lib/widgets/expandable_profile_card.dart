import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';

/// Sleek top-right CircleAvatar icon for the HomeScreen AppBar.
/// Tapping opens the streamlined Profile & Settings modal sheet.
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
    final iconIdx =
        prefs.avatarIconIndex.clamp(0, OledTheme.avatarIcons.length - 1);
    final colorIdx =
        prefs.avatarColorIndex.clamp(0, OledTheme.avatarColors.length - 1);
    final avatarIcon = OledTheme.avatarIcons[iconIdx];
    final avatarColor = prefs.christmasModeEnabled
        ? const Color(0xFFD32F2F)
        : OledTheme.avatarColors[colorIdx];
    final photoFile = _resolveValidPhotoFile();

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: TactileBounce(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: avatarColor.withValues(alpha: 0.85),
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 19,
                backgroundColor: avatarColor.withValues(alpha: 0.22),
                backgroundImage:
                    photoFile != null ? FileImage(photoFile) : null,
                child: photoFile == null
                    ? Icon(
                        avatarIcon,
                        color: avatarColor,
                        size: 20,
                      )
                    : null,
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

/// Opens the streamlined Profile & Settings modal bottom sheet:
/// - Minimal student view: shows only the custom user avatar and editable nickname.
/// - Clean entry point button to open full App Settings.
Future<void> showStreamlinedProfileSheet({
  required BuildContext context,
  required Student? student,
  required StoredSession session,
  required UserProfilePrefs prefs,
  required ValueChanged<UserProfilePrefs> onPrefsChanged,
  required VoidCallback onOpenFullSettings,
}) {
  HapticFeedback.lightImpact();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _StreamlinedProfileModalSheet(
        student: student,
        session: session,
        initialPrefs: prefs,
        onPrefsChanged: onPrefsChanged,
        onOpenFullSettings: () {
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
  final UserProfilePrefs initialPrefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onOpenFullSettings;

  const _StreamlinedProfileModalSheet({
    required this.student,
    required this.session,
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
  late final TextEditingController _nicknameController;
  final ImagePicker _imagePicker = ImagePicker();
  bool _showAvatarCustomizer = false;

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

    final iconIdx =
        _prefs.avatarIconIndex.clamp(0, OledTheme.avatarIcons.length - 1);
    final colorIdx =
        _prefs.avatarColorIndex.clamp(0, OledTheme.avatarColors.length - 1);
    final avatarIcon = OledTheme.avatarIcons[iconIdx];
    final avatarColor = OledTheme.avatarColors[colorIdx];
    final photoFile = _resolveValidPhotoFile();

    final displayNick = (_prefs.nickname != null &&
            _prefs.nickname!.trim().isNotEmpty)
        ? _prefs.nickname!
        : (widget.student?.name.split(' ').last ?? 'Milán');

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: theme.dividerColor),
        ),
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
                  onTap: () => setState(
                    () => _showAvatarCustomizer = !_showAvatarCustomizer,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: avatarColor.withValues(alpha: 0.22),
                        backgroundImage:
                            photoFile != null ? FileImage(photoFile) : null,
                        child: photoFile == null
                            ? Icon(
                                avatarIcon,
                                color: avatarColor,
                                size: 38,
                              )
                            : null,
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
                            Icons.edit_rounded,
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
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nicknameController,
                      decoration: InputDecoration(
                        labelText: uwu('Becenév szerkesztése'),
                        hintText: 'pl. Milán',
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
                      backgroundColor: avatarColor,
                      foregroundColor: Colors.white,
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
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
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
                              photoFile != null ? 'Új kép' : 'Kép galériából',
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
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(
                          OledTheme.avatarIcons.length,
                          (idx) {
                            final selected = idx == _prefs.avatarIconIndex;
                            return InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _applyPrefs(
                                _prefs.copyWith(avatarIconIndex: idx),
                              ),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? avatarColor.withValues(alpha: 0.25)
                                      : scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected
                                        ? avatarColor
                                        : theme.dividerColor,
                                  ),
                                ),
                                child: Icon(
                                  OledTheme.avatarIcons[idx],
                                  color: selected
                                      ? avatarColor
                                      : scheme.onSurface.withValues(alpha: 0.7),
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(
                          OledTheme.avatarColors.length,
                          (idx) {
                            final c = OledTheme.avatarColors[idx];
                            final selected = idx == _prefs.avatarColorIndex;
                            return InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _applyPrefs(
                                _prefs.copyWith(avatarColorIndex: idx),
                              ),
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selected
                                        ? scheme.onSurface
                                        : Colors.transparent,
                                    width: 2.2,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                crossFadeState: _showAvatarCustomizer
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 220),
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
