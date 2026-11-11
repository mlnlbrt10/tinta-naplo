import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/dynamic_icon_service.dart';
import '../services/github_updater_service.dart';
import '../services/kreta_client.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/frosted_inspection_modal.dart';
import 'about_app_screen.dart';

enum _AttendanceFilter {
  all('Összes'),
  certified('Igazolt'),
  uncertified('Igazolatlan'),
  tardiness('Késések');

  final String label;
  const _AttendanceFilter(this.label);
}

/// Standalone full-screen App Settings page opened from the top-right
/// Profile & Settings sheet in the HomeScreen AppBar.
class AppSettingsScreen extends StatelessWidget {
  final StoredSession session;
  final Student? student;
  final KretaClient kretaClient;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onLogout;

  const AppSettingsScreen({
    super.key,
    required this.session,
    required this.student,
    required this.kretaClient,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(uwu('Alkalmazás beállítások')),
      ),
      body: ChristmasAndBackgroundOverlay(
        prefs: prefs,
        child: MoreScreen(
          session: session,
          student: student,
          kretaClient: kretaClient,
          prefs: prefs,
          onPrefsChanged: onPrefsChanged,
          onLogout: onLogout,
          settingsOnly: true,
        ),
      ),
    );
  }
}

/// "Továbbiak" tab:
/// 1. Hiányzások és Késések (`/ellenorzo/v3/sajat/Mulasztasok`) module.
/// 2. Kréta Üzenetek (`/ellenorzo/v3/sajat/Uzenetek` — Beérkezett / Elküldött)
///    with Message Detail view and in-app Message Composer dialog.
/// 3. Accordion-Style Settings Architecture (collapsed by default), Christmas Mode,
///    App Icon & Background Customizer, JSON Export/Import, UwU & Tsundere modes.
class MoreScreen extends StatefulWidget {
  final StoredSession session;
  final Student? student;
  final KretaClient? kretaClient;
  final List<Omission> initialOmissions;
  final List<KretaMessage> initialMessages;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onLogout;
  final bool settingsOnly;

  const MoreScreen({
    super.key,
    required this.session,
    required this.student,
    this.kretaClient,
    this.initialOmissions = const [],
    this.initialMessages = const [],
    required this.prefs,
    required this.onPrefsChanged,
    required this.onLogout,
    this.settingsOnly = false,
  });

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  int _selectedGradeToCustomize = 5;
  _AttendanceFilter _attendanceFilter = _AttendanceFilter.all;
  bool _showSentMessages = false;
  bool _isLoadingModules = false;

  late List<Omission> _omissions;
  late List<KretaMessage> _messages;
  final Set<String> _readMessageIds = {};

  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');
  final DateFormat _dateTimeFormat = DateFormat('yyyy. MM. dd. HH:mm');

  @override
  void initState() {
    super.initState();
    _omissions = List<Omission>.from(widget.initialOmissions);
    _messages = List<KretaMessage>.from(widget.initialMessages);
    if (!widget.settingsOnly &&
        widget.kretaClient != null &&
        (_omissions.isEmpty && _messages.isEmpty)) {
      _refreshModules();
    }
  }

  @override
  void didUpdateWidget(covariant MoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialOmissions.isNotEmpty && _omissions.isEmpty) {
      _omissions = List<Omission>.from(widget.initialOmissions);
    }
    if (widget.initialMessages.isNotEmpty && _messages.isEmpty) {
      _messages = List<KretaMessage>.from(widget.initialMessages);
    }
  }

  Future<void> _refreshModules() async {
    final client = widget.kretaClient;
    if (client == null) return;
    setState(() => _isLoadingModules = true);
    try {
      final results = await Future.wait<Object>([
        client.fetchOmissions(widget.session),
        client.fetchMessages(widget.session),
      ]);
      if (!mounted) return;
      setState(() {
        _omissions = results[0] as List<Omission>;
        _messages = results[1] as List<KretaMessage>;
        _isLoadingModules = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingModules = false);
    }
  }

  void _setThemeStyle(AppThemeStyle style) {
    String nextIcon = widget.prefs.appIconPreset;
    if (widget.prefs.christmasModeEnabled &&
        (nextIcon == 'default' ||
            nextIcon == 'christmas' ||
            nextIcon == 'icon_christmas' ||
            nextIcon == 'icon_christmas_oled')) {
      nextIcon = style == AppThemeStyle.oledPureBlack
          ? 'icon_christmas_oled'
          : 'icon_christmas';
      DynamicIconService.setAppIcon(nextIcon);
    }
    widget.onPrefsChanged(
      widget.prefs.copyWith(
        themeStyle: style,
        appIconPreset: nextIcon,
      ),
    );
  }

  void _toggleChristmasMode(bool enabled) {
    HapticFeedback.mediumImpact();
    final isOled = widget.prefs.themeStyle == AppThemeStyle.oledPureBlack;
    final String targetIcon = enabled
        ? (isOled ? 'icon_christmas_oled' : 'icon_christmas')
        : (isOled ? 'icon_oled' : 'icon_normal');
    DynamicIconService.setAppIcon(targetIcon);
    widget.onPrefsChanged(
      widget.prefs.copyWith(
        christmasModeEnabled: enabled,
        appIconPreset: targetIcon,
      ),
    );
  }

  void _selectAppIconPreset(String iconId) {
    HapticFeedback.selectionClick();
    DynamicIconService.setAppIcon(iconId);
    widget.onPrefsChanged(
      widget.prefs.copyWith(appIconPreset: iconId),
    );
  }

  void _toggleDynamicColor(bool value) {
    widget.onPrefsChanged(widget.prefs.copyWith(useDynamicColor: value));
  }

  void _setSeedColor(int colorVal) {
    widget.onPrefsChanged(
      widget.prefs.copyWith(
        seedColorValue: colorVal,
        useDynamicColor: false,
      ),
    );
  }

  void _setGradeColor(int grade, int colorValue) {
    final nextMap = Map<int, int>.from(widget.prefs.customGradeColors);
    nextMap[grade] = colorValue;
    widget.onPrefsChanged(widget.prefs.copyWith(customGradeColors: nextMap));
  }

  void _resetGradeColors() {
    widget.onPrefsChanged(
      widget.prefs.copyWith(
        customGradeColors: Map<int, int>.from(
          UserProfilePrefs.defaultGradeColors,
        ),
      ),
    );
  }

  Future<void> _promptCustomHexForGrade(int grade) async {
    final currentArgb = widget.prefs.colorForGrade(grade).toARGB32();
    final currentHex = currentArgb
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    final controller = TextEditingController(text: '#$currentHex');

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Érdemjegy ($grade) egyedi HEX színe'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'HEX színkód (#RRGGBB)',
              hintText: '#2E7D32',
              prefixIcon: Icon(Icons.colorize_rounded),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Mégse'),
            ),
            FilledButton(
              onPressed: () {
                final cleaned = controller.text
                    .trim()
                    .replaceAll('#', '')
                    .toUpperCase();
                if (RegExp(r'^[0-9A-F]{6}$').hasMatch(cleaned)) {
                  final parsed = int.parse('FF$cleaned', radix: 16);
                  Navigator.of(dialogContext).pop(parsed);
                }
              },
              child: const Text('Alkalmaz'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      _setGradeColor(grade, result);
    }
  }

  void _updateRounding(GradeRoundingConfig nextConfig) {
    widget.onPrefsChanged(widget.prefs.copyWith(roundingConfig: nextConfig));
  }

  Future<void> _exportSettingsJson() async {
    HapticFeedback.lightImpact();
    final jsonStr = widget.prefs.toExportJsonString();
    String? savedFilePath;

    final candidateDirs = <String>[
      '/storage/emulated/0/Download',
      Directory.systemTemp.path,
    ];
    for (final dirPath in candidateDirs) {
      try {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          final file = File('${dir.path}/rekreta_settings_backup.json');
          await file.writeAsString(jsonStr);
          savedFilePath = file.path;
          break;
        }
      } catch (_) {}
    }

    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Beállítások exportálva (JSON)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (savedFilePath != null) ...[
                  Text(
                    'Mentve ide:\n$savedFilePath\n\nA JSON konfiguráció a vágólapra is felkerült.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ] else
                  const Text(
                    'A JSON konfiguráció a vágólapra lett másolva.',
                    style: TextStyle(fontSize: 13),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    jsonStr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Rendben'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _importSettingsJson() async {
    HapticFeedback.lightImpact();
    final pathController = TextEditingController();
    final jsonController = TextEditingController();

    final availableFiles = <File>[];
    for (final dirPath in [
      '/storage/emulated/0/Download',
      Directory.systemTemp.path,
    ]) {
      try {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          final found = dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.json'))
              .take(8);
          availableFiles.addAll(found);
        }
      } catch (_) {}
    }

    final restoredPrefs = await showDialog<UserProfilePrefs>(
      context: context,
      builder: (dialogContext) {
        String? errorMsg;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Beállítások importálása (JSON)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (availableFiles.isNotEmpty) ...[
                      const Text(
                        'Talált JSON mentésfájlok a készüléken:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...availableFiles.map((file) {
                        final name = file.path.split('/').last;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              try {
                                final content = file.readAsStringSync();
                                jsonController.text = content;
                                pathController.text = file.path;
                                setModalState(() => errorMsg = null);
                              } catch (e) {
                                setModalState(
                                  () => errorMsg = 'Nem sikerült beolvasni: $e',
                                );
                              }
                            },
                            icon: const Icon(
                              Icons.insert_drive_file_rounded,
                              size: 16,
                            ),
                            label: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: pathController,
                      decoration: InputDecoration(
                        labelText: 'JSON fájl elérési útja (opcionális)',
                        hintText: '/storage/.../rekreta_settings_backup.json',
                        prefixIcon: const Icon(Icons.folder_open_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'Beolvasás fájlból',
                          onPressed: () {
                            final p = pathController.text.trim();
                            if (p.isEmpty) return;
                            try {
                              final f = File(p);
                              jsonController.text = f.readAsStringSync();
                              setModalState(() => errorMsg = null);
                            } catch (e) {
                              setModalState(
                                () => errorMsg = 'Fájl hiba: $e',
                              );
                            }
                          },
                          icon: const Icon(Icons.file_upload_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: jsonController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Vagy illeszd be a JSON tartalmat',
                        hintText: '{"schemaVersion": 2, ...}',
                      ),
                    ),
                    if (errorMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorMsg!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Mégse'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    try {
                      String raw = jsonController.text.trim();
                      if (raw.isEmpty && pathController.text.trim().isNotEmpty) {
                        raw = File(pathController.text.trim()).readAsStringSync();
                      }
                      final parsed =
                          UserProfilePrefs.fromExportJsonString(raw);
                      Navigator.of(dialogContext).pop(parsed);
                    } catch (e) {
                      setModalState(
                        () => errorMsg = 'Érvénytelen JSON formátum: $e',
                      );
                    }
                  },
                  icon: const Icon(Icons.restore_rounded, size: 18),
                  label: const Text('Visszaállítás'),
                ),
              ],
            );
          },
        );
      },
    );

    if (restoredPrefs != null && mounted) {
      widget.onPrefsChanged(restoredPrefs);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(uwu('Beállítások sikeresen visszaállítva!')),
        ),
      );
    }
  }

  void _openMessageDetailModal(KretaMessage msg) {
    HapticFeedback.lightImpact();
    setState(() {
      _readMessageIds.add(msg.uid);
      final idx = _messages.indexWhere((m) => m.uid == msg.uid);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(isRead: true);
      }
    });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: theme.dividerColor),
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.78,
            minChildSize: 0.5,
            maxChildSize: 0.94,
            expand: false,
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 32),
                child: Column(
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
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.mail_rounded,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.subject,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Feladó: ${widget.prefs.resolveTeacherName(msg.sender)}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (msg.recipients.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Címzett: ${msg.recipients.join(", ")}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                _dateTimeFormat.format(msg.sentAt.toLocal()),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: OledTheme.cardRadius,
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: SelectableText(
                        msg.cleanBody.isNotEmpty
                            ? msg.cleanBody
                            : 'Üres üzenetszöveg.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.45,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text('Bezárás'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _openMessageComposerDialog(
                                initialRecipient: msg.sender,
                                initialSubject: msg.subject.startsWith('Re:')
                                    ? msg.subject
                                    : 'Re: ${msg.subject}',
                              );
                            },
                            icon: const Icon(Icons.reply_rounded, size: 18),
                            label: const Text('Válasz küldése'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openMessageComposerDialog({
    String? initialRecipient,
    String? initialSubject,
  }) async {
    HapticFeedback.lightImpact();
    final recipientController =
        TextEditingController(text: initialRecipient ?? '');
    final subjectController =
        TextEditingController(text: initialSubject ?? '');
    final bodyController = TextEditingController();

    final sent = await showDialog<KretaMessage>(
      context: context,
      builder: (dialogContext) {
        bool isSending = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                initialRecipient != null ? 'Válasz üzenet' : 'Új Kréta üzenet',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: recipientController,
                      decoration: const InputDecoration(
                        labelText: 'Címzett (tanár / titkárság)',
                        hintText: 'pl. Osztályfőnök',
                        prefixIcon: Icon(Icons.person_search_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subjectController,
                      decoration: const InputDecoration(
                        labelText: 'Tárgy',
                        hintText: 'pl. Hiányzás igazolása',
                        prefixIcon: Icon(Icons.subject_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Üzenet szövege',
                        hintText: 'Írd ide az üzenetedet...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Mégse'),
                ),
                FilledButton.icon(
                  onPressed: isSending
                      ? null
                      : () async {
                          final recip = recipientController.text.trim();
                          final subj = subjectController.text.trim();
                          final body = bodyController.text.trim();
                          if (recip.isEmpty || subj.isEmpty || body.isEmpty) {
                            return;
                          }
                          setModalState(() => isSending = true);
                          final client =
                              widget.kretaClient ?? KretaClient();
                          final created = await client.sendMessage(
                            widget.session,
                            recipient: recip,
                            subject: subj,
                            body: body,
                            senderName: widget.student?.name ??
                                widget.prefs.nickname ??
                                'Milán',
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(created);
                          }
                        },
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(isSending ? 'Küldés...' : 'Küldés'),
                ),
              ],
            );
          },
        );
      },
    );

    if (sent != null && mounted) {
      setState(() {
        _messages.insert(0, sent);
        _showSentMessages = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(uwu('Üzenet sikeresen elküldve: ${sent.subject}')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expFormat = DateFormat('yyyy. MM. dd. HH:mm');
    final rounding = widget.prefs.roundingConfig;

    return RefreshIndicator(
      onRefresh: _refreshModules,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          widget.settingsOnly ? 36 : 112,
        ),
        children: [
          if (!widget.settingsOnly) ...[
            _buildAttendanceModuleCard(theme, scheme).staggeredEntrance(0),
            const SizedBox(height: 16),
            _buildMessagesModuleCard(theme, scheme).staggeredEntrance(1),
            const SizedBox(height: 22),
            Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  uwu('Beállítások és Testreszabás'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // Accordion 1: Megjelenés, Téma, Karácsonyi mód, Ikonok és Háttér
          _SettingsAccordionCard(
            icon: Icons.palette_rounded,
            title: 'Megjelenés, Téma és Karácsonyi mód',
            subtitle: 'OLED Fekete, Material You, Hóesés, Ikon & Háttér témák',
            christmasCap: widget.prefs.christmasModeEnabled,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: const Color(0xFFFF5252),
                title: const Text(
                  'Karácsonyi mód (Ünnepi hóesés)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Fizikai alapú hóesés animáció a háttérben, havas kártyaszélek és ünnepi ikon',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
                value: widget.prefs.christmasModeEnabled,
                onChanged: _toggleChristmasMode,
              ),
              const SizedBox(height: 10),
              Text(
                'Alkalmazás megjelenési módja:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildThemeOptionChip(
                      scheme: scheme,
                      dividerColor: theme.dividerColor,
                      label: 'OLED Fekete',
                      icon: Icons.dark_mode_rounded,
                      selected: widget.prefs.themeStyle ==
                          AppThemeStyle.oledPureBlack,
                      onTap: () => _setThemeStyle(AppThemeStyle.oledPureBlack),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildThemeOptionChip(
                      scheme: scheme,
                      dividerColor: theme.dividerColor,
                      label: 'Sötét M3',
                      icon: Icons.nights_stay_rounded,
                      selected:
                          widget.prefs.themeStyle == AppThemeStyle.standardDark,
                      onTap: () => _setThemeStyle(AppThemeStyle.standardDark),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildThemeOptionChip(
                      scheme: scheme,
                      dividerColor: theme.dividerColor,
                      label: 'Világos',
                      icon: Icons.light_mode_rounded,
                      selected: widget.prefs.themeStyle == AppThemeStyle.light,
                      onTap: () => _setThemeStyle(AppThemeStyle.light),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Material You (Rendszerszín követése)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Automatikus színpaletta az Android háttérképből',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                value: widget.prefs.useDynamicColor,
                onChanged: _toggleDynamicColor,
              ),
              const SizedBox(height: 8),
              Text(
                'Egyedi Material 3 alapszín:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: OledTheme.avatarColors.map((color) {
                  final colorVal = color.toARGB32();
                  final selected = !widget.prefs.useDynamicColor &&
                      widget.prefs.seedColorValue == colorVal;
                  return InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _setSeedColor(colorVal),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: selected
                              ? scheme.onSurface
                              : Colors.transparent,
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
                }).toList(),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Alkalmazás ikon választó (Manuális felülbírálás):',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.35,
                children: AppIconPresetInfo.presets.map((preset) {
                  final resolvedActive = AppIconPresetInfo.resolve(widget.prefs);
                  final selected = resolvedActive.id == preset.id;
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _selectAppIconPreset(preset.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary.withValues(alpha: 0.18)
                            : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected ? scheme.primary : theme.dividerColor,
                          width: selected ? 1.8 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              preset.assetPath,
                              width: 42,
                              height: 42,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 42,
                                height: 42,
                                color: preset.backgroundColor,
                                child: Icon(
                                  preset.icon,
                                  size: 22,
                                  color: preset.primaryColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preset.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: selected
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                    color: selected
                                        ? scheme.primary
                                        : scheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preset.subtitle,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.62),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: scheme.primary,
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'Háttér effektus / atmoszféra:',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: BackgroundPresetInfo.presets.map((bg) {
                  final selected = widget.prefs.backgroundPreset == bg.id;
                  return ChoiceChip(
                    avatar: Icon(bg.icon, size: 16),
                    label: Text(bg.label),
                    selected: selected,
                    onSelected: (_) => widget.onPrefsChanged(
                      widget.prefs.copyWith(backgroundPreset: bg.id),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Accordion 2: Érdemjegyek Színeinek Testreszabása
          _SettingsAccordionCard(
            icon: Icons.color_lens_rounded,
            title: 'Érdemjegyek Színeinek Testreszabása',
            subtitle: 'Egyedi színek és HEX kódok az 1–5 jegyekhez',
            christmasCap: widget.prefs.christmasModeEnabled,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Koppints egy érdemjegyre (1–5), majd válassz színt:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _resetGradeColors,
                    child: const Text('Alapértelmezett'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [5, 4, 3, 2, 1].map((g) {
                  final badgeColor = widget.prefs.colorForGrade(g);
                  final selected = _selectedGradeToCustomize == g;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () =>
                            setState(() => _selectedGradeToCustomize = g),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: selected
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              width: selected ? 3 : 0,
                            ),
                          ),
                          child: Text(
                            '$g',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ...OledTheme.gradeColorPalette.map((paletteColor) {
                    final val = paletteColor.toARGB32();
                    final currentVal = widget.prefs
                        .colorForGrade(_selectedGradeToCustomize)
                        .toARGB32();
                    final isCurrent = val == currentVal;
                    return InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () =>
                          _setGradeColor(_selectedGradeToCustomize, val),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: paletteColor,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isCurrent
                                ? scheme.onSurface
                                : Colors.transparent,
                            width: 2.2,
                          ),
                        ),
                        child: isCurrent
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    );
                  }),
                  ActionChip(
                    avatar: const Icon(Icons.tag_rounded, size: 16),
                    label: const Text('Egyedi HEX'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    onPressed: () =>
                        _promptCustomHexForGrade(_selectedGradeToCustomize),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Accordion 3: Kerekítési Határok és Órarend Beállítások
          _SettingsAccordionCard(
            icon: Icons.tune_rounded,
            title: 'Kerekítési Határok és Órarend',
            subtitle: 'Átlag küszöbök, elmaradt órák és hétvége megjelenítése',
            christmasCap: widget.prefs.christmasModeEnabled,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Elmaradt órák megjelenítése (nulladik/első óra is)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Ha be van kapcsolva, a reggeli elmaradó órák is láthatók maradnak az órarendben',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                value: widget.prefs.showCancelledLessons,
                onChanged: (val) => widget.onPrefsChanged(
                  widget.prefs.copyWith(showCancelledLessons: val),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Hétvége mutatása az órarendben',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                value: widget.prefs.showWeekends,
                onChanged: (val) => widget.onPrefsChanged(
                  widget.prefs.copyWith(showWeekends: val),
                ),
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Globális kerekítési határok:',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _updateRounding(const GradeRoundingConfig()),
                    child: const Text('Alaphelyzet'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildThresholdSlider(
                theme: theme,
                scheme: scheme,
                gradeLabel: 'Jeles (5) határ',
                color: widget.prefs.colorForGrade(5),
                value: rounding.threshold5,
                min: 4.00,
                max: 4.95,
                onChanged: (v) => _updateRounding(
                  rounding.copyWith(
                    threshold5: double.parse(v.toStringAsFixed(2)),
                  ),
                ),
              ),
              _buildThresholdSlider(
                theme: theme,
                scheme: scheme,
                gradeLabel: 'Jó (4) határ',
                color: widget.prefs.colorForGrade(4),
                value: rounding.threshold4,
                min: 3.00,
                max: 3.95,
                onChanged: (v) => _updateRounding(
                  rounding.copyWith(
                    threshold4: double.parse(v.toStringAsFixed(2)),
                  ),
                ),
              ),
              _buildThresholdSlider(
                theme: theme,
                scheme: scheme,
                gradeLabel: 'Közepes (3) határ',
                color: widget.prefs.colorForGrade(3),
                value: rounding.threshold3,
                min: 2.00,
                max: 2.95,
                onChanged: (v) => _updateRounding(
                  rounding.copyWith(
                    threshold3: double.parse(v.toStringAsFixed(2)),
                  ),
                ),
              ),
              _buildThresholdSlider(
                theme: theme,
                scheme: scheme,
                gradeLabel: 'Elégséges (2) határ',
                color: widget.prefs.colorForGrade(2),
                value: rounding.threshold2,
                min: 1.10,
                max: 2.20,
                onChanged: (v) => _updateRounding(
                  rounding.copyWith(
                    threshold2: double.parse(v.toStringAsFixed(2)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Accordion 4: Beállítások exportálása / importálása
          _SettingsAccordionCard(
            icon: Icons.import_export_rounded,
            title: 'Beállítások exportálása / importálása',
            subtitle: 'JSON biztonsági mentés készítése és visszaállítása',
            christmasCap: widget.prefs.christmasModeEnabled,
            children: [
              Text(
                'Minden testreszabás (színek, becenév, tantárgy- és tanár-átnevezések, kerekítési határok, módok) automatikusan megmarad kijelentkezés után is, vagy JSON fájlba exportálható:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _exportSettingsJson,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Exportálás (JSON)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _importSettingsJson,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Importálás (JSON)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Accordion 5: Fejlesztői beállítások (UwU mód & Tsundere mód)
          _SettingsAccordionCard(
            icon: Icons.terminal_rounded,
            title: 'Fejlesztői mód & Easter Eggs',
            subtitle: 'UwU mód és Tsundere mód kapcsolók',
            christmasCap: widget.prefs.christmasModeEnabled,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: OledTheme.uwuPastelPink,
                title: const Text(
                  'UwU mód',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  uwu(
                    'Fonetikus szövegátalakítás (:3, uwu, >w<) és pasztell rózsaszín/levendula téma',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
                value: widget.prefs.uwuModeEnabled,
                onChanged: (val) => widget.onPrefsChanged(
                  widget.prefs.copyWith(uwuModeEnabled: val),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: const Color(0xFFFF7043),
                title: const Text(
                  'Tsundere mód',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  'Csípős tsundere köszöntések és értesítések („Nem mintha érdekelne a házi feladatod, b-baka!”, „Megint hármas? Nem mintha figyeltem volna...”)',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
                value: widget.prefs.tsundereModeEnabled,
                onChanged: (val) => widget.onPrefsChanged(
                  widget.prefs.copyWith(tsundereModeEnabled: val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Accordion 6: Fiók és munkamenet
          _SettingsAccordionCard(
            icon: Icons.manage_accounts_rounded,
            title: 'Fiók és munkamenet',
            subtitle: widget.student?.name ?? widget.session.userName ?? 'Milán',
            christmasCap: widget.prefs.christmasModeEnabled,
            children: [
              _buildRow(
                scheme,
                'Tanuló neve',
                widget.student?.name ?? widget.session.userName ?? 'Milán',
              ),
              _buildRow(
                scheme,
                'Beállított becenév',
                widget.prefs.nickname ?? 'Alapértelmezett (Milán)',
              ),
              _buildRow(
                scheme,
                'Intézménykód (iss)',
                widget.session.instituteCode,
              ),
              if (widget.student != null)
                _buildRow(scheme, 'Intézmény', widget.student!.instituteName),
              _buildRow(
                scheme,
                'Token lejárat',
                expFormat.format(widget.session.expiresAt.toLocal()),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: OledTheme.cardRadius,
                  ),
                ),
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: Text(
                  uwu('Kijelentkezés (beállítások megtartásával)'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Accordion 7: Rendszer / Névjegy
          _SettingsAccordionCard(
            icon: Icons.info_outline_rounded,
            title: uwu('Rendszer / Névjegy'),
            subtitle:
                'reKRETA v${GitHubUpdaterService.fallbackAppVersion}+${GitHubUpdaterService.fallbackBuildNumber} • GitHub OTA frissítő',
            christmasCap: widget.prefs.christmasModeEnabled,
            children: [
              _buildRow(
                scheme,
                uwu('Alkalmazás'),
                uwu(
                  'reKRETA • v${GitHubUpdaterService.fallbackAppVersion}+${GitHubUpdaterService.fallbackBuildNumber}',
                ),
              ),
              _buildRow(scheme, uwu('GitHub'), 'github.com/mlnlbrt10/reKRETA'),
              const SizedBox(height: 12),
              TactileBounce(
                onTap: () {
                  Navigator.of(context).push(
                    SmoothSharedAxisRoute(
                      page: AboutAppScreen(
                        prefs: widget.prefs,
                        onPrefsChanged: widget.onPrefsChanged,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          uwu('Az alkalmazásról & Frissítések megnyitása'),
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
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
            ],
          ),
        ],
      ),
    );
  }

  /// Module 1: Hiányzások és Késések (`/ellenorzo/v3/sajat/Mulasztasok`).
  Widget _buildAttendanceModuleCard(ThemeData theme, ColorScheme scheme) {
    final summary = OmissionsSummary.fromList(_omissions);

    List<Omission> filtered;
    switch (_attendanceFilter) {
      case _AttendanceFilter.certified:
        filtered = summary.missedLessons
            .where((o) => o.state == OmissionState.excused)
            .toList();
        break;
      case _AttendanceFilter.uncertified:
        filtered = summary.missedLessons
            .where((o) => o.state != OmissionState.excused)
            .toList();
        break;
      case _AttendanceFilter.tardiness:
        filtered = summary.tardinessEntries;
        break;
      case _AttendanceFilter.all:
        filtered = summary.allOmissions;
        break;
    }

    return ChristmasSnowCap(
      enabled: widget.prefs.christmasModeEnabled,
      child: Container(
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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.event_busy_rounded,
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
                        uwu('Hiányzások és Késések'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Mulasztott órák és késések részletes összesítése',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoadingModules)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _buildStatPill(
                    theme,
                    scheme,
                    label: 'Összes óra',
                    value: '${summary.totalMissedHours} óra',
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatPill(
                    theme,
                    scheme,
                    label: 'Igazolt',
                    value: '${summary.certifiedHours} óra',
                    color: const Color(0xFF2E7D32),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatPill(
                    theme,
                    scheme,
                    label: 'Igazolatlan',
                    value: '${summary.uncertifiedHours} óra',
                    color: const Color(0xFFC62828),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatPill(
                    theme,
                    scheme,
                    label: 'Késések',
                    value: '${summary.totalTardinessMinutes} perc',
                    color: const Color(0xFFF9A825),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _AttendanceFilter.values.map((f) {
                  final selected = _attendanceFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: selected,
                      onSelected: (_) =>
                          setState(() => _attendanceFilter = f),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: Colors.greenAccent.withValues(alpha: 0.85),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nincs rögzített mulasztás vagy késés ebben a kategóriában.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...filtered.take(6).map((omission) {
                final isLate = OmissionsSummary.isTardiness(omission);
                final isExcused = omission.state == OmissionState.excused;
                final isUnexcused = omission.state == OmissionState.unexcused;
                final statusColor = isExcused
                    ? const Color(0xFF2E7D32)
                    : isUnexcused
                        ? const Color(0xFFC62828)
                        : const Color(0xFFF9A825);
                final statusLabel = isExcused
                    ? 'Igazolt'
                    : isUnexcused
                        ? 'Igazolatlan'
                        : 'Igazolandó';
                final subjDisplay = widget.prefs.resolveSubjectName(
                  omission.subject.name,
                  omission.subject.uid,
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TactileBounce(
                    onTap: () {
                      showFrostedModal(
                        context: context,
                        categoryLabel: isLate ? 'Késés' : 'Mulasztás / Hiányzás',
                        categoryIcon: Icons.event_busy_rounded,
                        accentColor: statusColor,
                        title: subjDisplay,
                        badgeText: isLate
                            ? '${omission.lateForMin ?? 0}p'
                            : (omission.lesson?.classNo != null
                                ? '${omission.lesson!.classNo}.'
                                : '!'),
                        rows: [
                          FrostedDetailRow(
                            icon: Icons.calendar_today_rounded,
                            label: 'Dátum',
                            value: _dateFormat.format(omission.date.toLocal()),
                          ),
                          FrostedDetailRow(
                            icon: Icons.verified_user_rounded,
                            label: 'Státusz',
                            value: statusLabel,
                          ),
                          if (isLate)
                            FrostedDetailRow(
                              icon: Icons.timer_rounded,
                              label: 'Késés mértéke',
                              value: '${omission.lateForMin ?? 0} perc',
                            ),
                          if (omission.proofType != null &&
                              omission.proofType!.description.isNotEmpty)
                            FrostedDetailRow(
                              icon: Icons.description_rounded,
                              label: 'Igazolás típusa',
                              value: omission.proofType!.description,
                            ),
                          FrostedDetailRow(
                            icon: Icons.person_rounded,
                            label: 'Rögzítő tanár',
                            value: widget.prefs
                                .resolveTeacherName(omission.teacher),
                          ),
                        ],
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isLate
                                  ? '${omission.lateForMin ?? 0} p'
                                  : (omission.lesson?.classNo != null
                                      ? '${omission.lesson!.classNo}. óra'
                                      : statusLabel),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subjDisplay,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${_dateFormat.format(omission.date.toLocal())} • $statusLabel',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(
    ThemeData theme,
    ColorScheme scheme, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.68),
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Module 2: Kréta Üzenetek (`/ellenorzo/v3/sajat/Uzenetek` — Beérkezett / Elküldött).
  Widget _buildMessagesModuleCard(ThemeData theme, ColorScheme scheme) {
    final visibleMessages = _messages
        .where((m) => _showSentMessages ? m.isSent : !m.isSent)
        .toList();

    return ChristmasSnowCap(
      enabled: widget.prefs.christmasModeEnabled,
      child: Container(
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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.mail_outline_rounded,
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
                        uwu('Kréta Üzenetek'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Beérkezett és elküldött üzenetek',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _openMessageComposerDialog(),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Új üzenet'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.inbox_rounded, size: 16),
                  label: const Text('Beérkezett'),
                  selected: !_showSentMessages,
                  onSelected: (_) =>
                      setState(() => _showSentMessages = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Elküldött'),
                  selected: _showSentMessages,
                  onSelected: (_) =>
                      setState(() => _showSentMessages = true),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (visibleMessages.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.mark_email_read_rounded,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _showSentMessages
                            ? 'Még nincs elküldött üzenet. Koppints az „Új üzenet” gombra!'
                            : 'Nincs megjeleníthető beérkezett üzenet.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...visibleMessages.take(8).map((msg) {
                final isRead =
                    msg.isRead || _readMessageIds.contains(msg.uid);
                final senderDisplay =
                    widget.prefs.resolveTeacherName(msg.sender);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TactileBounce(
                    onTap: () => _openMessageDetailModal(msg),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: !isRead
                              ? scheme.primary.withValues(alpha: 0.7)
                              : theme.dividerColor,
                          width: !isRead ? 1.4 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: !isRead
                                  ? scheme.primary
                                  : scheme.onSurface.withValues(alpha: 0.25),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        msg.isSent && msg.recipients.isNotEmpty
                                            ? 'Címzett: ${msg.recipients.first}'
                                            : senderDisplay,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          fontWeight: !isRead
                                              ? FontWeight.w900
                                              : FontWeight.w700,
                                          color: scheme.primary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      _dateFormat.format(msg.sentAt.toLocal()),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.58),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  msg.subject,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: !isRead
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (msg.cleanBody.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    msg.cleanBody,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOptionChip({
    required ColorScheme scheme,
    required Color dividerColor,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.22)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? scheme.primary : dividerColor,
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.78),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdSlider({
    required ThemeData theme,
    required ColorScheme scheme,
    required String gradeLabel,
    required Color color,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final clamped = value.clamp(min, max);
    final divisions = ((max - min) * 20).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  gradeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  clamped.toStringAsFixed(2),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: clamped,
            min: min,
            max: max,
            divisions: divisions > 0 ? divisions : null,
            activeColor: color,
            label: clamped.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(ColorScheme scheme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
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

/// Collapsible Accordion Card for Settings categories (collapsed by default).
class _SettingsAccordionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool christmasCap;

  const _SettingsAccordionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.christmasCap = false,
  });

  @override
  State<_SettingsAccordionCard> createState() => _SettingsAccordionCardState();
}

class _SettingsAccordionCardState extends State<_SettingsAccordionCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ChristmasSnowCap(
      enabled: widget.christmasCap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: OledTheme.largeRadius,
          border: Border.all(
            color: _isExpanded
                ? scheme.primary.withValues(alpha: 0.65)
                : theme.dividerColor,
            width: _isExpanded ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TactileBounce(
              pressedScale: 0.98,
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.icon,
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
                            widget.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.62),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(color: theme.dividerColor, height: 16),
                    ...widget.children,
                  ],
                ),
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
            ),
          ],
        ),
      ),
    );
  }
}
