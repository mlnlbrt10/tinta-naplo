import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/bug_report_service.dart';
import '../services/github_updater_service.dart';
import '../services/token_storage_service.dart';
import '../utils/uwu_helper.dart';
import 'frosted_inspection_modal.dart';
import 'glass_card.dart';
import 'tinta_toast.dart';

/// Opens the privacy-masked in-app bug report bottom sheet targeting
/// `https://ticket.mlnlbrt.hu/api/tickets`.
Future<void> showBugReportSheet(
  BuildContext context, {
  Student? student,
  required UserProfilePrefs prefs,
  http.Client? httpClient,
  Future<XFile?> Function()? pickImageOverride,
  Future<XFile?> Function()? pickVideoOverride,
  Future<String> Function()? appVersionLoader,
}) {
  HapticFeedback.lightImpact();
  return showFloatingGlassSheet<void>(
    context: context,
    prefs: prefs,
    barrierColor: resolveSoftBlurBarrierColor(
      context,
      prefs: prefs,
      solidDarkAlpha: 0.62,
      solidLightAlpha: 0.42,
    ),
    builder: (sheetContext) => _BugReportModalSheet(
      student: student,
      prefs: prefs,
      httpClient: httpClient,
      pickImageOverride: pickImageOverride,
      pickVideoOverride: pickVideoOverride,
      appVersionLoader: appVersionLoader,
    ),
  );
}

class _BugReportModalSheet extends StatefulWidget {
  final Student? student;
  final UserProfilePrefs prefs;
  final http.Client? httpClient;
  final Future<XFile?> Function()? pickImageOverride;
  final Future<XFile?> Function()? pickVideoOverride;
  final Future<String> Function()? appVersionLoader;

  const _BugReportModalSheet({
    required this.student,
    required this.prefs,
    this.httpClient,
    this.pickImageOverride,
    this.pickVideoOverride,
    this.appVersionLoader,
  });

  @override
  State<_BugReportModalSheet> createState() => _BugReportModalSheetState();
}

class _BugReportModalSheetState extends State<_BugReportModalSheet> {
  final TextEditingController _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _selectedCategory = BugReportService.categories.first;
  String _appVersion =
      '${GitHubUpdaterService.fallbackAppVersion}+${GitHubUpdaterService.fallbackBuildNumber}';
  BugAttachment? _attachment;
  String? _attachmentError;
  String? _validationError;
  String? _submitError;
  bool _isSubmitting = false;
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final loaded = widget.appVersionLoader != null
          ? await widget.appVersionLoader!()
          : (await GitHubUpdaterService.getAppVersionInfo()).$1;
      if (mounted && loaded.trim().isNotEmpty) {
        setState(() => _appVersion = loaded.trim());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia({required bool isVideo}) async {
    if (_isSubmitting) return;
    setState(() => _attachmentError = null);
    try {
      final XFile? picked = isVideo
          ? await (widget.pickVideoOverride != null
              ? widget.pickVideoOverride!()
              : _picker.pickVideo(source: ImageSource.gallery))
          : await (widget.pickImageOverride != null
              ? widget.pickImageOverride!()
              : _picker.pickImage(source: ImageSource.gallery));
      if (picked == null || picked.path.trim().isEmpty) return;

      final sizeBytes = await picked.length();
      final rawName = picked.name.trim().isNotEmpty
          ? picked.name.trim()
          : picked.path.split(Platform.pathSeparator).last;
      final validation = BugReportService.validateAttachment(
        path: picked.path,
        name: rawName,
        sizeBytes: sizeBytes,
        isVideo: isVideo,
      );
      if (!mounted) return;
      if (!validation.isValid) {
        setState(() => _attachmentError = validation.errorMessage);
        return;
      }
      setState(() {
        _attachment = validation.attachment;
        _attachmentError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _attachmentError = 'Nem sikerült megnyitni a fájlt: $e',
      );
    }
  }

  Future<void> _copyFallbackDetails({
    required String reporter,
    required String osVersion,
    required String themeMode,
  }) async {
    final text = BugReportService.buildCopyableDetails(
      reporter: reporter,
      category: _selectedCategory,
      description: _descriptionController.text,
      appVersion: _appVersion,
      osVersion: osVersion,
      themeMode: themeMode,
      attachment: _attachment,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    TintaToast.info(
      context,
      uwu('Hibajelentés részletei vágólapra másolva.'),
    );
  }

  Future<void> _submit({
    required String reporter,
    required String osVersion,
    required String themeMode,
  }) async {
    final desc = _descriptionController.text.trim();
    if (desc.isEmpty) {
      setState(
        () => _validationError = 'Kérjük, írj rövid leírást a beküldés előtt.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _validationError = null;
      _submitError = null;
      _isSubmitting = true;
      _uploadProgress = _attachment != null ? 0.0 : null;
    });

    final res = await BugReportService.submitTicket(
      reporter: reporter,
      category: _selectedCategory,
      description: desc,
      appVersion: _appVersion,
      osVersion: osVersion,
      themeMode: themeMode,
      attachment: _attachment,
      client: widget.httpClient,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _uploadProgress = p);
      },
    );

    if (!mounted) return;
    if (res.success) {
      final rootOverlay = Overlay.maybeOf(context, rootOverlay: true) ??
          Overlay.maybeOf(context);
      TintaToast.success(
        context,
        uwu('Köszönjük! A hibajelentés sikeresen elküldve.'),
        overlayOverride: rootOverlay,
      );
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isSubmitting = false;
      _uploadProgress = null;
      _submitError = res.errorMessage ?? 'Sikertelen küldés.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final maskedReporter = BugReportService.maskReporterName(
      widget.student?.name,
    );
    final osVersion = BugReportService.resolveOsVersionLabel();
    final themeMode = BugReportService.describeThemeMode(
      widget.prefs,
      platformBrightness: theme.brightness,
    );

    return PopScope(
      canPop: !_isSubmitting,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: FrostedBottomSheetSurface(
          prefs: widget.prefs,
          topRadius: 26,
          showDragHandle: false,
          includeSafeAreaBottom: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.bug_report_outlined,
                        color: scheme.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            uwu('Hibajelentés küldése'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            uwu('Hibák és javaslatok beküldése'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.62),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bezárás',
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  uwu('Kategória'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: BugReportService.categories.map((cat) {
                    final selected = _selectedCategory == cat;
                    return ChoiceChip(
                      label: Text(
                        uwu(cat),
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      selected: selected,
                      onSelected: _isSubmitting
                          ? null
                          : (_) {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCategory = cat);
                            },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _descriptionController,
                  enabled: !_isSubmitting,
                  minLines: 4,
                  maxLines: 7,
                  onChanged: (_) {
                    if (_validationError != null) {
                      setState(() => _validationError = null);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: uwu('Írd le röviden, mit tapasztaltál...'),
                    errorText: _validationError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  uwu('Képernyőkép vagy videó csatolása'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _pickMedia(isVideo: false),
                      icon: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 18,
                      ),
                      label: Text(uwu('Képernyőkép csatolása')),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _isSubmitting
                          ? null
                          : () => _pickMedia(isVideo: true),
                      icon: const Icon(
                        Icons.video_library_outlined,
                        size: 18,
                      ),
                      label: Text(uwu('Képernyőfelvétel csatolása')),
                    ),
                  ],
                ),
                if (_attachmentError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.error.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      _attachmentError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (_attachment != null) ...[
                  const SizedBox(height: 10),
                  _buildAttachmentPreviewChip(theme, scheme, _attachment!),
                ],
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.privacy_tip_outlined,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              uwu('Adatvédelmi előnézet (küldött adatok)'),
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _metaChip(scheme, uwuLabel('Beküldő: $maskedReporter')),
                          _metaChip(scheme, uwuLabel('Verzió: $_appVersion')),
                          _metaChip(scheme, uwuLabel(osVersion)),
                          _metaChip(scheme, uwuLabel(themeMode)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        uwu(
                          'A teljes vezetékneved és KRÉTA azonosítóid soha nem kerülnek elküldésre.',
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isSubmitting) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: _uploadProgress,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _uploadProgress != null
                        ? uwu(
                            'Feltöltés folyamatban: ${(_uploadProgress! * 100).round()}%',
                          )
                        : uwu('Hibajelentés küldése...'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: scheme.error.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _submitError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _copyFallbackDetails(
                            reporter: maskedReporter,
                            osVersion: osVersion,
                            themeMode: themeMode,
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: Text(uwu('Részletek másolása')),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => _submit(
                            reporter: maskedReporter,
                            osVersion: osVersion,
                            themeMode: themeMode,
                          ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  label: Text(
                    uwu('Küldés'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaChip(ColorScheme scheme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface.withValues(alpha: 0.86),
        ),
      ),
    );
  }

  Widget _buildAttachmentPreviewChip(
    ThemeData theme,
    ColorScheme scheme,
    BugAttachment attachment,
  ) {
    final file = File(attachment.path);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: !attachment.isVideo && file.existsSync()
                ? Image.file(
                    file,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _mediaFallbackThumb(
                      scheme,
                      isVideo: attachment.isVideo,
                    ),
                  )
                : _mediaFallbackThumb(scheme, isVideo: attachment.isVideo),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  attachment.formattedSizeMb,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: uwuLabel('Csatolmány eltávolítása'),
            onPressed: _isSubmitting
                ? null
                : () => setState(() => _attachment = null),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _mediaFallbackThumb(ColorScheme scheme, {required bool isVideo}) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      color: scheme.primary.withValues(alpha: 0.16),
      child: Icon(
        isVideo ? Icons.videocam_rounded : Icons.image_rounded,
        color: scheme.primary,
        size: 20,
      ),
    );
  }
}
