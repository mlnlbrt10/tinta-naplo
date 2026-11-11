import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/github_updater_service.dart';
import '../services/kreta_client.dart';
import '../services/menetrend_service.dart';
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

/// Standalone full-screen App Settings page opened EXCLUSIVELY from the
/// top-right Profile & Settings sheet in the HomeScreen AppBar.
/// Maintains its own reactive `_prefs` state so all checkmarks and sliders
/// update on the exact frame the user interacts with them.
class AppSettingsScreen extends StatefulWidget {
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
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late UserProfilePrefs _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefs;
  }

  @override
  void didUpdateWidget(covariant AppSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefs != oldWidget.prefs) {
      _prefs = widget.prefs;
    }
  }

  void _handlePrefsChanged(UserProfilePrefs next) {
    setState(() => _prefs = next);
    widget.onPrefsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(uwu('Alkalmazás beállítások')),
      ),
      body: ChristmasAndBackgroundOverlay(
        prefs: _prefs,
        child: MoreScreen(
          session: widget.session,
          student: widget.student,
          kretaClient: widget.kretaClient,
          prefs: _prefs,
          onPrefsChanged: _handlePrefsChanged,
          onLogout: widget.onLogout,
          settingsOnly: true,
        ),
      ),
    );
  }
}

/// "Továbbiak" tab (`settingsOnly == false`):
/// 1. Hiányzások és Késések (`/ellenorzo/v3/sajat/Mulasztasok`) module with
///    prominent "Összes hiányzás megtekintése" full-screen list button.
/// 2. Kréta Üzenetek (`/ellenorzo/v3/sajat/Uzenetek` — Beérkezett / Elküldött)
///    with Message Detail view and in-app Message Composer dialog featuring
///    live teacher/staff recipient autocomplete.
///
/// Main Settings screen (`settingsOnly == true`, opened exclusively via Profile):
/// Grouped accordions for MenetrendGO Commuter Transit, Appearance & Icons,
/// Grade Colors, Rounding & Timetable, JSON Backup, Account, and About App.
class MoreScreen extends StatefulWidget {
  final StoredSession session;
  final Student? student;
  final KretaClient? kretaClient;
  final DashboardData? dashboardData;
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
    this.dashboardData,
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
  late UserProfilePrefs _currentPrefs;
  int _selectedGradeToCustomize = 5;
  _AttendanceFilter _attendanceFilter = _AttendanceFilter.all;
  bool _showSentMessages = false;
  bool _isLoadingModules = false;

  late List<Omission> _omissions;
  late List<KretaMessage> _messages;
  final Set<String> _readMessageIds = {};

  late final TextEditingController _homeStationController;
  late final TextEditingController _schoolStationController;
  late final TextEditingController _fav1stController;
  late final TextEditingController _fav2ndController;

  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');
  final DateFormat _dateTimeFormat = DateFormat('yyyy. MM. dd. HH:mm');

  @override
  void initState() {
    super.initState();
    _currentPrefs = widget.prefs;
    _omissions = List<Omission>.from(widget.initialOmissions);
    _messages = List<KretaMessage>.from(widget.initialMessages);
    _homeStationController =
        TextEditingController(text: _currentPrefs.transitHomeStation);
    _schoolStationController =
        TextEditingController(text: _currentPrefs.transitSchoolStation);
    _fav1stController =
        TextEditingController(text: _currentPrefs.favoriteRoute1stPeriod);
    _fav2ndController =
        TextEditingController(text: _currentPrefs.favoriteRoute2ndPeriod);

    if (!widget.settingsOnly &&
        widget.kretaClient != null &&
        (_omissions.isEmpty && _messages.isEmpty)) {
      _refreshModules();
    }
  }

  @override
  void didUpdateWidget(covariant MoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefs != oldWidget.prefs) {
      _currentPrefs = widget.prefs;
    }
    if (widget.initialOmissions.isNotEmpty && _omissions.isEmpty) {
      _omissions = List<Omission>.from(widget.initialOmissions);
    }
    if (widget.initialMessages.isNotEmpty && _messages.isEmpty) {
      _messages = List<KretaMessage>.from(widget.initialMessages);
    }
  }

  @override
  void dispose() {
    _homeStationController.dispose();
    _schoolStationController.dispose();
    _fav1stController.dispose();
    _fav2ndController.dispose();
    super.dispose();
  }

  void _updatePrefs(UserProfilePrefs nextPrefs) {
    setState(() => _currentPrefs = nextPrefs);
    widget.onPrefsChanged(nextPrefs);
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
    String nextIcon = _currentPrefs.appIconPreset;
    if (_currentPrefs.christmasModeEnabled &&
        (nextIcon == 'default' ||
            nextIcon == 'christmas' ||
            nextIcon == 'icon_christmas' ||
            nextIcon == 'icon_christmas_oled')) {
      nextIcon = style == AppThemeStyle.oledPureBlack
          ? 'icon_christmas_oled'
          : 'icon_christmas';
    }
    _updatePrefs(
      _currentPrefs.copyWith(
        themeStyle: style,
        appIconPreset: nextIcon,
      ),
    );
  }

  void _toggleChristmasMode(bool enabled) {
    HapticFeedback.mediumImpact();
    final isOled = _currentPrefs.themeStyle == AppThemeStyle.oledPureBlack;
    final String targetIcon = enabled
        ? (isOled ? 'icon_christmas_oled' : 'icon_christmas')
        : (isOled ? 'icon_oled' : 'icon_normal');
    _updatePrefs(
      _currentPrefs.copyWith(
        christmasModeEnabled: enabled,
        appIconPreset: targetIcon,
      ),
    );
  }

  void _selectAppIconPreset(String iconId) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Alkalmazás ikon módosítva! Újraindítás...'),
        duration: Duration(milliseconds: 1500),
      ));
    _updatePrefs(
      _currentPrefs.copyWith(appIconPreset: iconId),
    );
  }

  void _toggleDynamicColor(bool value) {
    _updatePrefs(_currentPrefs.copyWith(useDynamicColor: value));
  }

  void _setSeedColor(int colorVal) {
    _updatePrefs(
      _currentPrefs.copyWith(
        seedColorValue: colorVal,
        useDynamicColor: false,
      ),
    );
  }

  void _setGradeColor(int grade, int colorValue) {
    final nextMap = Map<int, int>.from(_currentPrefs.customGradeColors);
    nextMap[grade] = colorValue;
    _updatePrefs(_currentPrefs.copyWith(customGradeColors: nextMap));
  }

  void _resetGradeColors() {
    _updatePrefs(
      _currentPrefs.copyWith(
        customGradeColors: Map<int, int>.from(
          UserProfilePrefs.defaultGradeColors,
        ),
      ),
    );
  }

  Future<void> _promptCustomHexForGrade(int grade) async {
    final currentArgb = _currentPrefs.colorForGrade(grade).toARGB32();
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
    _updatePrefs(_currentPrefs.copyWith(roundingConfig: nextConfig));
  }

  Future<void> _exportSettingsJson() async {
    HapticFeedback.lightImpact();
    final jsonStr = _currentPrefs.toExportJsonString();
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
                      if (raw.isEmpty &&
                          pathController.text.trim().isNotEmpty) {
                        raw = File(pathController.text.trim())
                            .readAsStringSync();
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
      _updatePrefs(restoredPrefs);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(uwu('Beállítások sikeresen visszaállítva!')),
        ),
      );
    }
  }

  /// Collects all unique teacher and staff contact names from Kréta API data
  /// (`DashboardData`, lessons, grades, homeworks, tests, omissions, messages)
  /// for the Message Composer's recipient autocomplete.
  List<String> _collectTeacherAndStaffContacts() {
    final contacts = <String>{
      'Osztályfőnök',
      'Titkárság',
      'Igazgatóság',
      'Rendszergazda',
    };

    void addContact(String? raw) {
      if (raw == null) return;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return;
      contacts.add(_currentPrefs.resolveTeacherName(trimmed));
      contacts.add(trimmed);
    }

    final dash = widget.dashboardData;
    if (dash != null) {
      for (final lesson in dash.todaysLessons) {
        addContact(lesson.teacher);
        addContact(lesson.substituteTeacher);
      }
      for (final grade in dash.allGrades) {
        addContact(grade.teacher);
      }
      for (final hw in dash.homeworks) {
        addContact(hw.teacherName);
      }
      for (final test in dash.tests) {
        addContact(test.teacherName);
      }
      for (final om in dash.omissions) {
        addContact(om.teacher);
      }
      for (final msg in dash.messages) {
        if (!msg.isSent) {
          addContact(msg.sender);
        }
        for (final r in msg.recipients) {
          addContact(r);
        }
      }
    }

    for (final om in _omissions) {
      addContact(om.teacher);
    }
    for (final msg in _messages) {
      if (!msg.isSent) {
        addContact(msg.sender);
      }
      for (final r in msg.recipients) {
        addContact(r);
      }
    }
    for (final custom in _currentPrefs.teacherCustomNames.values) {
      addContact(custom);
    }

    final sorted = contacts.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
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
                                'Feladó: ${_currentPrefs.resolveTeacherName(msg.sender)}',
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

  /// Opens the Kréta Message Composer dialog with live teacher/staff
  /// recipient autocomplete suggestions.
  Future<void> _openMessageComposerDialog({
    String? initialRecipient,
    String? initialSubject,
  }) async {
    HapticFeedback.lightImpact();
    final allContacts = _collectTeacherAndStaffContacts();
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
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final query = recipientController.text.trim().toLowerCase();
            final matchingContacts = allContacts.where((c) {
              if (query.isEmpty) return true;
              return c.toLowerCase().contains(query) &&
                  c.toLowerCase() != query;
            }).take(6).toList();

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
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Címzett (tanár / titkárság)',
                        hintText: 'Kezdj el gépelni a kereséshez...',
                        prefixIcon: const Icon(Icons.person_search_rounded),
                        suffixIcon: recipientController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  recipientController.clear();
                                  setModalState(() {});
                                },
                              )
                            : null,
                      ),
                    ),
                    if (matchingContacts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 13,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Javasolt címzettek (Kréta névjegyzék):',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: matchingContacts.map((contact) {
                                return ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    Icons.person_rounded,
                                    size: 14,
                                    color: scheme.primary,
                                  ),
                                  label: Text(
                                    contact,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    recipientController.text = contact;
                                    recipientController.selection =
                                        TextSelection.fromPosition(
                                      TextPosition(offset: contact.length),
                                    );
                                    setModalState(() {});
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                                _currentPrefs.nickname ??
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

  void _openAllOmissionsScreen() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      SmoothSharedAxisRoute(
        page: AllOmissionsScreen(
          omissions: _omissions,
          prefs: _currentPrefs,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expFormat = DateFormat('yyyy. MM. dd. HH:mm');
    final rounding = _currentPrefs.roundingConfig;

    // B6: On the 'Továbbiak' bottom tab (!widget.settingsOnly), render ONLY
    // the Attendance and Kréta Messages modules. Settings are accessible
    // EXCLUSIVELY via the top-right Profile sheet (`AppSettingsScreen`).
    if (!widget.settingsOnly) {
      return RefreshIndicator(
        onRefresh: _refreshModules,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
          children: [
            _buildAttendanceModuleCard(theme, scheme).staggeredEntrance(0),
            const SizedBox(height: 16),
            _buildMessagesModuleCard(theme, scheme).staggeredEntrance(1),
          ],
        ),
      );
    }

    // Main Settings view (`widget.settingsOnly == true`):
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      children: [
        // Accordion 1: MenetrendGO Ingázás és Indulási Értesítések (Part A #4)
        _buildMenetrendSettingsAccordion(theme, scheme),
        const SizedBox(height: 12),

        // Accordion 2: Megjelenés, Téma, Karácsonyi mód, Ikonok, Háttér & Ablakok
        _SettingsAccordionCard(
          icon: Icons.palette_rounded,
          title: 'Megjelenés, Téma és Karácsonyi mód',
          subtitle: 'OLED Fekete, Material You, Ikonok, Háttér és Ablakok',
          christmasCap: _currentPrefs.christmasModeEnabled,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Kártyák soft blur & áttetszőség',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'Lágy, matt üveghatású kártyák a főoldalon',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
              value: _currentPrefs.cardBlurEnabled,
              onChanged: (v) =>
                  _updatePrefs(_currentPrefs.copyWith(cardBlurEnabled: v)),
            ),
            if (_currentPrefs.cardBlurEnabled) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Áttetszőség',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${(_currentPrefs.cardOpacity.clamp(0.60, 0.85) * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _currentPrefs.cardOpacity.clamp(0.60, 0.85),
                min: 0.60,
                max: 0.85,
                divisions: 5,
                onChanged: (v) =>
                    _updatePrefs(_currentPrefs.copyWith(cardOpacity: v)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Elmosás erőssége',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _currentPrefs.cardBlurSigma.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _currentPrefs.cardBlurSigma.clamp(2.0, 8.0),
                min: 2,
                max: 8,
                divisions: 6,
                onChanged: (v) =>
                    _updatePrefs(_currentPrefs.copyWith(cardBlurSigma: v)),
              ),
            ],
            const Divider(height: 20),
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
              value: _currentPrefs.christmasModeEnabled,
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
                    selected: _currentPrefs.themeStyle ==
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
                    selected: _currentPrefs.themeStyle ==
                        AppThemeStyle.standardDark,
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
                    selected:
                        _currentPrefs.themeStyle == AppThemeStyle.light,
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
              value: _currentPrefs.useDynamicColor,
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
                final selected = !_currentPrefs.useDynamicColor &&
                    _currentPrefs.seedColorValue == colorVal;
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
            Text(
              'Alkalmazás ikon választó (Azonnali váltás):',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
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
                final resolvedActive =
                    AppIconPresetInfo.resolve(_currentPrefs);
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
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BackgroundPresetInfo.presets.map((bg) {
                final selected = _currentPrefs.backgroundPreset == bg.id;
                return ChoiceChip(
                  avatar: Icon(
                    selected ? Icons.check_circle_rounded : bg.icon,
                    size: 16,
                    color: selected ? scheme.primary : null,
                  ),
                  label: Text(
                    bg.label,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  selected: selected,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    _updatePrefs(
                      _currentPrefs.copyWith(backgroundPreset: bg.id),
                    );
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'Felugró ablakok bezárása (Modális vezérlők):',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ModalCloseButtonMode.values.map((mode) {
                final selected = _currentPrefs.modalCloseMode == mode;
                return ChoiceChip(
                  label: Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  selected: selected,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    _updatePrefs(
                      _currentPrefs.copyWith(modalCloseMode: mode),
                    );
                  },
                );
              }).toList(),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Accordion 3: Érdemjegyek Színeinek Testreszabása
        _SettingsAccordionCard(
          icon: Icons.color_lens_rounded,
          title: 'Érdemjegyek Színeinek Testreszabása',
          subtitle: 'Egyedi színek és HEX kódok az 1–5 jegyekhez',
          christmasCap: _currentPrefs.christmasModeEnabled,
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
                final badgeColor = _currentPrefs.colorForGrade(g);
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
                  final currentVal = _currentPrefs
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

        // Accordion 4: Kerekítési Határok és Órarend Beállítások
        _SettingsAccordionCard(
          icon: Icons.tune_rounded,
          title: 'Kerekítési Határok és Órarend',
          subtitle: 'Átlag küszöbök, elmaradt/nulladik órák és hétvége',
          christmasCap: _currentPrefs.christmasModeEnabled,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Elmaradt/nulladik órák mutatása',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Ha be van kapcsolva, későbbi kezdésnél az inaktív 1. óra is megjelenik szürkítve',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              value: _currentPrefs.showCancelledLessons,
              onChanged: (val) => _updatePrefs(
                _currentPrefs.copyWith(showCancelledLessons: val),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Hétvége mutatása az órarendben',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              value: _currentPrefs.showWeekends,
              onChanged: (val) => _updatePrefs(
                _currentPrefs.copyWith(showWeekends: val),
              ),
            ),
            const Divider(height: 20),
            Text(
              'Kalkulátor jegy súlyozása:',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  showCheckmark: false,
                  label: const Text('100% alapeset'),
                  selected: !_currentPrefs.calcAllow200Weight,
                  onSelected: (_) => _updatePrefs(
                    _currentPrefs.copyWith(calcAllow200Weight: false),
                  ),
                ),
                ChoiceChip(
                  showCheckmark: false,
                  label: const Text('200% témazáró engedélyezése'),
                  selected: _currentPrefs.calcAllow200Weight,
                  onSelected: (_) => _updatePrefs(
                    _currentPrefs.copyWith(calcAllow200Weight: true),
                  ),
                ),
              ],
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
              color: _currentPrefs.colorForGrade(5),
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
              color: _currentPrefs.colorForGrade(4),
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
              color: _currentPrefs.colorForGrade(3),
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
              color: _currentPrefs.colorForGrade(2),
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

        // Accordion 5: Beállítások exportálása / importálása
        _SettingsAccordionCard(
          icon: Icons.import_export_rounded,
          title: 'Beállítások exportálása / importálása',
          subtitle: 'JSON biztonsági mentés készítése és visszaállítása',
          christmasCap: _currentPrefs.christmasModeEnabled,
          children: [
            Text(
              'Minden testreszabás (színek, becenév, tantárgy- és tanár-átnevezések, kerekítési határok, MenetrendGO beállítások) automatikusan megmarad kijelentkezés után is, vagy JSON fájlba exportálható:',
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

        // Accordion 6: Fiók és munkamenet
        _SettingsAccordionCard(
          icon: Icons.manage_accounts_rounded,
          title: 'Fiók és munkamenet',
          subtitle:
              widget.student?.name ?? widget.session.userName ?? 'Milán',
          christmasCap: _currentPrefs.christmasModeEnabled,
          children: [
            _buildRow(
              scheme,
              'Tanuló neve',
              widget.student?.name ?? widget.session.userName ?? 'Milán',
            ),
            _buildRow(
              scheme,
              'Beállított becenév',
              _currentPrefs.nickname ?? 'Alapértelmezett (Milán)',
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

        // Accordion 7: Rendszer / Névjegy (Developer Options live strictly inside AboutAppScreen)
        _SettingsAccordionCard(
          icon: Icons.info_outline_rounded,
          title: uwu('Rendszer / Névjegy'),
          subtitle:
              'reKRETA v${GitHubUpdaterService.fallbackAppVersion}+${GitHubUpdaterService.fallbackBuildNumber} • GitHub OTA frissítő',
          christmasCap: _currentPrefs.christmasModeEnabled,
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
                      prefs: _currentPrefs,
                      onPrefsChanged: _updatePrefs,
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
    );
  }

  /// Part A #4: MenetrendGO Commuter Transit Settings Accordion grouped under Main Settings.
  Widget _buildMenetrendSettingsAccordion(
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final speedKmh = _currentPrefs.walkingSpeedKmh.clamp(3.5, 5.5);
    String speedLabel;
    if (speedKmh <= 3.8) {
      speedLabel = 'Lassú (${speedKmh.toStringAsFixed(1)} km/h)';
    } else if (speedKmh >= 5.0) {
      speedLabel = 'Gyors / Sietős (${speedKmh.toStringAsFixed(1)} km/h)';
    } else {
      speedLabel = 'Normál (${speedKmh.toStringAsFixed(1)} km/h)';
    }

    return _SettingsAccordionCard(
      icon: Icons.directions_railway_filled_rounded,
      title: 'MenetrendGO Ingázás & Értesítések',
      subtitle: _currentPrefs.transitConfigured
          ? '${_currentPrefs.transitHomeStation} ↔ ${_currentPrefs.transitSchoolStation}'
          : 'Nincs beállítva',
      christmasCap: _currentPrefs.christmasModeEnabled,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.directions_railway_filled_rounded),
          title: const Text(
            'MenetrendGO kártya megjelenítése a főoldalon',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          value: _currentPrefs.transitCardEnabled,
          onChanged: (v) => _updatePrefs(
            _currentPrefs.copyWith(transitCardEnabled: v),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Állomások és útvonal (MenetrendGO):',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 10),
        _TransitStopSearchField(
          controller: _homeStationController,
          label: 'Otthoni megálló / lakóhely',
          hint: 'Keress megállót vagy állomást',
          icon: Icons.home_rounded,
          onSelected: (name) => _updatePrefs(
            _currentPrefs.copyWith(transitHomeStation: name),
          ),
          onCleared: () => _updatePrefs(
            _currentPrefs.copyWith(transitHomeStation: ''),
          ),
        ),
        const SizedBox(height: 10),
        _TransitStopSearchField(
          controller: _schoolStationController,
          label: 'Iskola megállója / címe',
          hint: 'Keress megállót vagy állomást',
          icon: Icons.school_rounded,
          onSelected: (name) => _updatePrefs(
            _currentPrefs.copyWith(transitSchoolStation: name),
          ),
          onCleared: () => _updatePrefs(
            _currentPrefs.copyWith(transitSchoolStation: ''),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Közlekedési módok szűrése:',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.72),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.train_rounded, size: 20),
          title: const Text(
            'Vonat (MÁV-START)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          value: _currentPrefs.transitAllowTrain,
          onChanged: (v) => _updatePrefs(
            _currentPrefs.copyWith(transitAllowTrain: v),
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.directions_bus_filled_rounded, size: 20),
          title: const Text(
            'Helyközi / Távolsági busz (Volánbusz)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          value: _currentPrefs.transitAllowCoach,
          onChanged: (v) => _updatePrefs(
            _currentPrefs.copyWith(transitAllowCoach: v),
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.directions_bus_rounded, size: 20),
          title: const Text(
            'Helyi járat (Városi autóbusz)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          value: _currentPrefs.transitAllowLocalBus,
          onChanged: (v) => _updatePrefs(
            _currentPrefs.copyWith(transitAllowLocalBus: v),
          ),
        ),
        const Divider(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Gyaloglási tempó:',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                speedLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: speedKmh,
          min: 3.5,
          max: 5.5,
          divisions: 2,
          label: speedLabel,
          onChanged: (val) {
            final snapped = val < 4.0
                ? 3.5
                : val > 5.0
                    ? 5.5
                    : 4.5;
            _updatePrefs(
              _currentPrefs.copyWith(walkingSpeedKmh: snapped),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Kedvenc járatok (★ csillag jelölés a Főoldalon):',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _fav1stController,
                decoration: const InputDecoration(
                  labelText: '1. órára (pl. 07:09 / S150)',
                  prefixIcon: Icon(Icons.star_rounded, size: 18),
                ),
                onChanged: (v) => _updatePrefs(
                  _currentPrefs.copyWith(favoriteRoute1stPeriod: v.trim()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _fav2ndController,
                decoration: const InputDecoration(
                  labelText: '2. órára (pl. 07:48 / 807)',
                  prefixIcon: Icon(Icons.star_outline_rounded, size: 18),
                ),
                onChanged: (v) => _updatePrefs(
                  _currentPrefs.copyWith(favoriteRoute2ndPeriod: v.trim()),
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Indulási figyelmeztetések engedélyezése',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'Pontos reggeli indulási riasztás és késés figyelmeztetés (+5 perc felett)',
            style: TextStyle(
              fontSize: 11.5,
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          value: _currentPrefs.transitNotificationsEnabled,
          onChanged: (val) async {
            if (val) {
              await MenetrendService.requestNotificationPermissions();
            } else {
              await MenetrendService.cancelAlarms();
            }
            _updatePrefs(
              _currentPrefs.copyWith(transitNotificationsEnabled: val),
            );
          },
        ),
        const SizedBox(height: 6),
        for (final (label, currentVal, onChanged) in <(
          String,
          int,
          ValueChanged<int>,
        )>[
          (
            'Otthon -> Buszmegálló séta',
            _currentPrefs.walkHomeToBusMinutes,
            (v) => _updatePrefs(
                  _currentPrefs.copyWith(walkHomeToBusMinutes: v),
                ),
          ),
          (
            'Otthon -> Vasútállomás séta',
            _currentPrefs.walkHomeToTrainMinutes,
            (v) => _updatePrefs(
                  _currentPrefs.copyWith(walkHomeToTrainMinutes: v),
                ),
          ),
          (
            'Iskola -> Buszmegálló séta',
            _currentPrefs.walkSchoolToBusMinutes,
            (v) => _updatePrefs(
                  _currentPrefs.copyWith(walkSchoolToBusMinutes: v),
                ),
          ),
          (
            'Iskola -> Vasútállomás séta',
            _currentPrefs.walkSchoolToTrainMinutes,
            (v) => _updatePrefs(
                  _currentPrefs.copyWith(walkSchoolToTrainMinutes: v),
                ),
          ),
        ]) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$currentVal perc',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: currentVal.clamp(1, 45).toDouble(),
            min: 1,
            max: 45,
            divisions: 44,
            label: '$currentVal perc',
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Értesítési időtartalék (indulás előtt):',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            Text(
              '${_currentPrefs.transitAlertBufferMinutes} perc',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: scheme.primary,
              ),
            ),
          ],
        ),
        Slider(
          value: _currentPrefs.transitAlertBufferMinutes.clamp(1, 20).toDouble(),
          min: 1,
          max: 20,
          divisions: 19,
          label: '${_currentPrefs.transitAlertBufferMinutes} perc',
          onChanged: (v) => _updatePrefs(
            _currentPrefs.copyWith(transitAlertBufferMinutes: v.round()),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  await MenetrendService.requestNotificationPermissions();
                  await MenetrendService.showImmediateNotification(
                    title: '🚶 Indulj lassan az állomásra!',
                    body:
                        'Teszt értesítés: indulj el időben az állomásra (${_currentPrefs.walkingDurationMinutes} perc séta).',
                  );
                },
                icon: const Icon(Icons.notifications_active_rounded, size: 17),
                label: const Text(
                  'Teszt értesítés',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  MenetrendService.openInMenetrendGo();
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: const Text(
                  'MenetrendGO',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ],
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
      enabled: _currentPrefs.christmasModeEnabled,
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
              ...filtered.take(5).map((omission) {
                return _buildOmissionTile(theme, scheme, omission);
              }),
            const SizedBox(height: 8),
            // B5: Prominent "Összes hiányzás megtekintése" button
            FilledButton.tonalIcon(
              onPressed: _openAllOmissionsScreen,
              icon: const Icon(Icons.list_alt_rounded, size: 18),
              label: Text(
                uwu(
                  'Összes hiányzás megtekintése (${summary.allOmissions.length} tétel)',
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOmissionTile(
    ThemeData theme,
    ColorScheme scheme,
    Omission omission,
  ) {
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
    final subjDisplay = _currentPrefs.resolveSubjectName(
      omission.subject.name,
      omission.subject.uid,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TactileBounce(
        onTap: () {
          showFrostedModal(
            context: context,
            closeMode: _currentPrefs.modalCloseMode,
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
                value: _currentPrefs.resolveTeacherName(omission.teacher),
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
                        color: scheme.onSurface.withValues(alpha: 0.65),
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
      enabled: _currentPrefs.christmasModeEnabled,
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
                  showCheckmark: false,
                  selected: !_showSentMessages,
                  onSelected: (_) =>
                      setState(() => _showSentMessages = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Elküldött'),
                  showCheckmark: false,
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
                    _currentPrefs.resolveTeacherName(msg.sender);

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

/// Dedicated full-screen list view for all past absences, tardiness, and
/// certifications ("Összes hiányzás megtekintése" — Part B #5).
class AllOmissionsScreen extends StatefulWidget {
  final List<Omission> omissions;
  final UserProfilePrefs prefs;

  const AllOmissionsScreen({
    super.key,
    required this.omissions,
    required this.prefs,
  });

  @override
  State<AllOmissionsScreen> createState() => _AllOmissionsScreenState();
}

class _AllOmissionsScreenState extends State<AllOmissionsScreen> {
  _AttendanceFilter _filter = _AttendanceFilter.all;
  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = OmissionsSummary.fromList(widget.omissions);

    List<Omission> filtered;
    switch (_filter) {
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

    return Scaffold(
      appBar: AppBar(
        title: Text(uwu('Összes hiányzás és késés')),
      ),
      body: ChristmasAndBackgroundOverlay(
        prefs: widget.prefs,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _AttendanceFilter.values.map((f) {
                  final selected = _filter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: OledTheme.largeRadius,
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: Colors.greenAccent.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        uwu(
                          'Nincs rögzített mulasztás vagy késés ebben a szűrőben.',
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...filtered.map((omission) {
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
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TactileBounce(
                    onTap: () {
                      showFrostedModal(
                        context: context,
                        closeMode: widget.prefs.modalCloseMode,
                        categoryLabel:
                            isLate ? 'Késés' : 'Mulasztás / Hiányzás',
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
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.cardTheme.color,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
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
                                const SizedBox(height: 2),
                                Text(
                                  '${_dateFormat.format(omission.date.toLocal())} • $statusLabel • ${widget.prefs.resolveTeacherName(omission.teacher)}',
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


/// Text field with live stop/station search against the real transit service.
class _TransitStopSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onSelected;
  final VoidCallback onCleared;

  const _TransitStopSearchField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onSelected,
    required this.onCleared,
  });

  @override
  State<_TransitStopSearchField> createState() =>
      _TransitStopSearchFieldState();
}

class _TransitStopSearchFieldState extends State<_TransitStopSearchField> {
  final MenetrendService _service = MenetrendService();
  Timer? _debounce;
  List<TransitStopResult> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
      });
      widget.onCleared();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() {
        _searching = true;
        _error = null;
      });
      try {
        final res = await _service.searchStops(q);
        if (!mounted) return;
        setState(() {
          _results = res.take(6).toList();
          _searching = false;
          if (res.isEmpty) _error = 'Nincs találat.';
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _results = const [];
          _searching = false;
          _error = 'A keresés nem érhető el.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: Icon(widget.icon),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        for (final r in _results)
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_rounded, size: 18),
            title: Text(r.name),
            onTap: () {
              widget.controller.text = r.name;
              setState(() => _results = const []);
              widget.onSelected(r.name);
              FocusScope.of(context).unfocus();
            },
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(_error!, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
