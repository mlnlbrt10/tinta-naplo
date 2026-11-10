import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';

/// Accordion-style expandable Student Profile Card for the Home Screen (Főoldal).
///
/// * Collapsed: displays custom uploaded photo (or vector avatar), name/nickname,
///   institute name, and expand arrow.
/// * Expanded: shows full student details, custom nickname editor, custom gallery
///   photo picker (`image_picker`), and avatar icon/color selection controls.
class ExpandableProfileCard extends StatefulWidget {
  final Student? student;
  final StoredSession session;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;

  const ExpandableProfileCard({
    super.key,
    required this.student,
    required this.session,
    required this.prefs,
    required this.onPrefsChanged,
  });

  @override
  State<ExpandableProfileCard> createState() => _ExpandableProfileCardState();
}

class _ExpandableProfileCardState extends State<ExpandableProfileCard> {
  bool _isExpanded = false;
  late final TextEditingController _nicknameController;
  final DateFormat _birthDateFormat = DateFormat('yyyy. MM. dd.');
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: widget.prefs.nickname ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant ExpandableProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs.nickname != widget.prefs.nickname &&
        _nicknameController.text != (widget.prefs.nickname ?? '')) {
      _nicknameController.text = widget.prefs.nickname ?? '';
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _saveNickname() {
    final trimmed = _nicknameController.text.trim();
    final updated = widget.prefs.copyWith(
      nickname: trimmed.isEmpty ? null : trimmed,
      clearNickname: trimmed.isEmpty,
    );
    widget.onPrefsChanged(updated);
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
        widget.onPrefsChanged(
          widget.prefs.copyWith(customPhotoPath: picked.path),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nem sikerült betölteni a képet: $e')),
      );
    }
  }

  void _clearCustomPhoto() {
    widget.onPrefsChanged(widget.prefs.copyWith(clearCustomPhoto: true));
  }

  void _selectAvatarIcon(int index) {
    widget.onPrefsChanged(widget.prefs.copyWith(avatarIconIndex: index));
  }

  void _selectAvatarColor(int index) {
    widget.onPrefsChanged(widget.prefs.copyWith(avatarColorIndex: index));
  }

  File? _resolveValidPhotoFile() {
    final path = widget.prefs.customPhotoPath;
    if (path == null || path.trim().isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final student = widget.student;

    final iconIdx =
        widget.prefs.avatarIconIndex.clamp(0, OledTheme.avatarIcons.length - 1);
    final colorIdx = widget.prefs.avatarColorIndex
        .clamp(0, OledTheme.avatarColors.length - 1);
    final avatarIcon = OledTheme.avatarIcons[iconIdx];
    final avatarColor = OledTheme.avatarColors[colorIdx];
    final photoFile = _resolveValidPhotoFile();

    final hasNickname = widget.prefs.nickname != null &&
        widget.prefs.nickname!.trim().isNotEmpty;
    final legalName = student?.name ?? widget.session.userName ?? 'Milán';
    final headerTitle = hasNickname ? widget.prefs.nickname! : legalName;
    final instituteLabel = student != null
        ? '${student.instituteName} (${student.instituteCode})'
        : widget.session.instituteCode;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.largeRadius,
        border: Border.all(
          color: _isExpanded
              ? avatarColor.withValues(alpha: 0.7)
              : theme.dividerColor,
          width: _isExpanded ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: OledTheme.largeRadius,
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  _buildAvatarWidget(
                    photoFile: photoFile,
                    avatarIcon: avatarIcon,
                    avatarColor: avatarColor,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (hasNickname) ...[
                          const SizedBox(height: 2),
                          Text(
                            legalName,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          instituteLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.62),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: scheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildExpandedBody(
              theme,
              scheme,
              student,
              avatarColor,
              photoFile,
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 240),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarWidget({
    required File? photoFile,
    required IconData avatarIcon,
    required Color avatarColor,
  }) {
    if (photoFile != null) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: OledTheme.badgeRadius,
          border: Border.all(color: avatarColor, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.file(
            photoFile,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(
              avatarIcon,
              color: avatarColor,
              size: 28,
            ),
          ),
        ),
      );
    }

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: avatarColor.withValues(alpha: 0.22),
        borderRadius: OledTheme.badgeRadius,
        border: Border.all(
          color: avatarColor.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      child: Icon(
        avatarIcon,
        color: avatarColor,
        size: 28,
      ),
    );
  }

  Widget _buildExpandedBody(
    ThemeData theme,
    ColorScheme scheme,
    Student? student,
    Color avatarColor,
    File? photoFile,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: theme.dividerColor, height: 24),
          Text(
            'Tanulói adatok',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: OledTheme.cardRadius,
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  scheme: scheme,
                  icon: Icons.badge_rounded,
                  label: 'Teljes név',
                  value: student?.name ?? widget.session.userName ?? 'Milán',
                ),
                _buildInfoRow(
                  scheme: scheme,
                  icon: Icons.tag_rounded,
                  label: 'Azonosító',
                  value: student?.uid ?? widget.session.userName ?? '-',
                ),
                _buildInfoRow(
                  scheme: scheme,
                  icon: Icons.account_balance_rounded,
                  label: 'Intézmény',
                  value: student != null
                      ? '${student.instituteName} (${student.instituteCode})'
                      : widget.session.instituteCode,
                ),
                if (student != null) ...[
                  _buildInfoRow(
                    scheme: scheme,
                    icon: Icons.cake_rounded,
                    label: 'Születési dátum',
                    value: _birthDateFormat.format(student.birthdate),
                  ),
                  if (student.emailAddress != null &&
                      student.emailAddress!.trim().isNotEmpty)
                    _buildInfoRow(
                      scheme: scheme,
                      icon: Icons.alternate_email_rounded,
                      label: 'E-mail',
                      value: student.emailAddress!,
                    ),
                  if (student.phoneNumber != null &&
                      student.phoneNumber!.trim().isNotEmpty)
                    _buildInfoRow(
                      scheme: scheme,
                      icon: Icons.phone_rounded,
                      label: 'Telefonszám',
                      value: student.phoneNumber!,
                    ),
                  if (student.addressDataList.isNotEmpty)
                    _buildInfoRow(
                      scheme: scheme,
                      icon: Icons.location_on_rounded,
                      label: 'Lakcím',
                      value: student.addressDataList.first,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Saját becenév beállítása',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nicknameController,
                  decoration: InputDecoration(
                    hintText: 'Alapértelmezett: Milán',
                    prefixIcon: const Icon(Icons.edit_rounded, size: 20),
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
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: avatarColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                onPressed: _saveNickname,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Mentés'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Saját profilkép vagy ikon választása',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                onPressed: _pickCustomPhoto,
                icon: const Icon(Icons.photo_library_rounded, size: 18),
                label: Text(
                  photoFile != null ? 'Másik kép választása' : 'Kép feltöltése galériából',
                ),
              ),
              if (photoFile != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: _clearCustomPhoto,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Kép eltávolítása'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(OledTheme.avatarIcons.length, (idx) {
              final selected = idx == widget.prefs.avatarIconIndex;
              return InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _selectAvatarIcon(idx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: selected
                        ? avatarColor.withValues(alpha: 0.28)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selected ? avatarColor : theme.dividerColor,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Icon(
                    OledTheme.avatarIcons[idx],
                    color: selected
                        ? avatarColor
                        : scheme.onSurface.withValues(alpha: 0.7),
                    size: 22,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(OledTheme.avatarColors.length, (idx) {
              final color = OledTheme.avatarColors[idx];
              final selected = idx == widget.prefs.avatarColorIndex;
              return InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _selectAvatarColor(idx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selected ? scheme.onSurface : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required ColorScheme scheme,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 17,
            color: scheme.onSurface.withValues(alpha: 0.54),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
