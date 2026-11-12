import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/kreta_client.dart';
import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/edge_fade_horizontal_scroll.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';
import 'about_app_screen.dart';

enum _AttendanceFilter {
  all('Összes'),
  certified('Igazolt'),
  uncertified('Igazolatlan'),
  tardiness('Késések');

  final String label;
  const _AttendanceFilter(this.label);
}

/// Absences and tardiness entries grouped into a single calendar day.
class DailyOmissionGroup {
  final DateTime day;
  final List<Omission> entries;

  const DailyOmissionGroup({
    required this.day,
    required this.entries,
  });

  /// Compact count/status badge label for the daily header pill.
  String get summaryLabel {
    final missedCount =
        entries.where((o) => !OmissionsSummary.isTardiness(o)).length;
    final tardyCount = entries.length - missedCount;
    if (missedCount > 0 && tardyCount > 0) {
      return '$missedCount óra • $tardyCount késés';
    }
    if (tardyCount > 0) {
      return '$tardyCount késés';
    }
    return '$missedCount óra';
  }

  Color resolveAccentColor() {
    if (entries.any((o) => o.state == OmissionState.unexcused)) {
      return const Color(0xFFC62828);
    }
    if (entries.any(
      (o) =>
          o.state == OmissionState.pending || o.state == OmissionState.unknown,
    )) {
      return const Color(0xFFF9A825);
    }
    return const Color(0xFF2E7D32);
  }
}

/// Groups omissions by local calendar date (newest day first), sorting entries
/// within each day by lesson period (`classNo`) ascending.
List<DailyOmissionGroup> groupOmissionsByDay(List<Omission> omissions) {
  final grouped = <DateTime, List<Omission>>{};
  for (final o in omissions) {
    final local = o.date.toLocal();
    final dayKey = DateTime(local.year, local.month, local.day);
    grouped.putIfAbsent(dayKey, () => <Omission>[]).add(o);
  }

  final sortedDays = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return sortedDays.map((day) {
    final entries = grouped[day]!
      ..sort((a, b) {
        final periodA = a.lesson?.classNo ?? 999;
        final periodB = b.lesson?.classNo ?? 999;
        final periodCmp = periodA.compareTo(periodB);
        if (periodCmp != 0) return periodCmp;
        final startA = a.lesson?.start ?? a.date;
        final startB = b.lesson?.start ?? b.date;
        final timeCmp = startA.compareTo(startB);
        if (timeCmp != 0) return timeCmp;
        return a.subject.name.compareTo(b.subject.name);
      });
    return DailyOmissionGroup(day: day, entries: List.unmodifiable(entries));
  }).toList(growable: false);
}

/// Formats a calendar day concisely as Hungarian `Month Day. • Weekday`.
String formatHungarianOmissionDay(DateTime day, {int? referenceYear}) {
  const shortMonths = [
    'Jan.',
    'Feb.',
    'Már.',
    'Ápr.',
    'Máj.',
    'Jún.',
    'Júl.',
    'Aug.',
    'Szept.',
    'Okt.',
    'Nov.',
    'Dec.',
  ];
  const weekdays = [
    '',
    'Hétfő',
    'Kedd',
    'Szerda',
    'Csütörtök',
    'Péntek',
    'Szombat',
    'Vasárnap',
  ];
  final currentYear = referenceYear ?? DateTime.now().year;
  final yearPrefix = day.year == currentYear ? '' : '${day.year}. ';
  final month = shortMonths[(day.month - 1).clamp(0, 11)];
  final weekday = weekdays[day.weekday.clamp(1, 7)];
  return '$yearPrefix$month ${day.day}. • $weekday';
}

List<Omission> _filterOmissions(
  OmissionsSummary summary,
  _AttendanceFilter filter,
) {
  switch (filter) {
    case _AttendanceFilter.certified:
      return summary.missedLessons
          .where((o) => o.state == OmissionState.excused)
          .toList();
    case _AttendanceFilter.uncertified:
      return summary.missedLessons
          .where((o) => o.state != OmissionState.excused)
          .toList();
    case _AttendanceFilter.tardiness:
      return summary.tardinessEntries;
    case _AttendanceFilter.all:
      return summary.allOmissions;
  }
}

Widget _buildOmissionFilterChips({
  required _AttendanceFilter selected,
  required ValueChanged<_AttendanceFilter> onSelected,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 16),
}) {
  return EdgeFadeHorizontalScroll(
    padding: padding,
    spacing: 8,
    children: _AttendanceFilter.values.map((f) {
      return ChoiceChip(
        label: Text(f.label),
        selected: selected == f,
        onSelected: (_) => onSelected(f),
      );
    }).toList(),
  );
}

Widget _buildEmptyOmissionCard({
  required UserProfilePrefs prefs,
  required String message,
}) {
  return SoftGlassCard(
    prefs: prefs,
    padding: const EdgeInsets.all(20),
    borderRadius: OledTheme.largeRadius,
    child: Row(
      children: [
        Icon(
          Icons.verified_rounded,
          color: Colors.greenAccent.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(uwu(message)),
        ),
      ],
    ),
  );
}

void _showOmissionDetailModal(
  BuildContext context, {
  required UserProfilePrefs prefs,
  required DateFormat dateFormat,
  required Omission omission,
}) {
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
  final subjDisplay = prefs.resolveSubjectName(
    omission.subject.name,
    omission.subject.uid,
  );

  showFrostedModal(
    context: context,
    closeMode: prefs.modalCloseMode,
    prefs: prefs,
    categoryLabel: isLate ? 'Késés' : 'Mulasztás / Hiányzás',
    categoryIcon: Icons.event_busy_rounded,
    accentColor: statusColor,
    title: subjDisplay,
    badgeText: isLate
        ? '${omission.lateForMin ?? 0}p'
        : (omission.lesson?.classNo != null ? '${omission.lesson!.classNo}.' : '!'),
    rows: [
      FrostedDetailRow(
        icon: Icons.calendar_today_rounded,
        label: 'Dátum',
        value: dateFormat.format(omission.date.toLocal()),
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
        value: prefs.resolveTeacherName(omission.teacher),
      ),
    ],
  );
}

class _DailyOmissionCard extends StatelessWidget {
  final DailyOmissionGroup group;
  final UserProfilePrefs prefs;
  final DateFormat dateFormat;

  const _DailyOmissionCard({
    required this.group,
    required this.prefs,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headerColor = group.resolveAccentColor();
    final hairlineColor = theme.dividerColor.withValues(alpha: 0.45);

    return SoftGlassCard(
      prefs: prefs,
      borderRadius: OledTheme.largeRadius,
      child: ClipRRect(
        borderRadius: OledTheme.largeRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: headerColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formatHungarianOmissionDay(group.day),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: headerColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: headerColor.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    group.summaryLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: headerColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.7,
            color: theme.dividerColor.withValues(alpha: 0.55),
          ),
          for (int i = 0; i < group.entries.length; i++) ...[
            _buildEntryRow(context, theme, scheme, group.entries[i]),
            if (i < group.entries.length - 1)
              Divider(
                height: 1,
                thickness: 0.6,
                indent: 16,
                endIndent: 16,
                color: hairlineColor,
              ),
          ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntryRow(
    BuildContext context,
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
    final subjDisplay = prefs.resolveSubjectName(
      omission.subject.name,
      omission.subject.uid,
    );
    final teacherName = prefs.resolveTeacherName(omission.teacher).trim();
    final metaLine = teacherName.isEmpty
        ? statusLabel
        : '$statusLabel • $teacherName';

    return InkWell(
      onTap: () => _showOmissionDetailModal(
        context,
        prefs: prefs,
        dateFormat: dateFormat,
        omission: omission,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                    metaLine,
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
    );
  }
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
    return AdaptiveBackgroundScaffold(
      prefs: _prefs,
      appBar: buildAdaptiveTransparentAppBar(
        context,
        title: uwu('Alkalmazás beállítások'),
      ),
      body: MoreScreen(
        session: widget.session,
        student: widget.student,
        kretaClient: widget.kretaClient,
        prefs: _prefs,
        onPrefsChanged: _handlePrefsChanged,
        onLogout: widget.onLogout,
        settingsOnly: true,
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

  /// When `true` (and not [settingsOnly]) only the Kréta messages module is
  /// shown; otherwise the non-settings view shows only absences (Hiányzások tab).
  final bool messagesOnly;

  /// Notified whenever the message list changes (refresh, read state).
  final ValueChanged<List<KretaMessage>>? onMessagesChanged;

  /// Whether this tab is currently visible in the bottom navigation IndexedStack.
  final bool isActiveTab;

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
    this.messagesOnly = false,
    this.onMessagesChanged,
    this.isActiveTab = true,
  });

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late UserProfilePrefs _currentPrefs;
  int _selectedGradeToCustomize = 5;
  _AttendanceFilter _attendanceFilter = _AttendanceFilter.all;
  bool _showSentMessages = false;
  bool _isLoadingModules = false;
  String _appVersion = '1.0.0';
  bool _initialEntrancePlayed = false;
  bool _entranceActive = false;

  static const MethodChannel _fileChannel =
      MethodChannel('hu.rekreta.rekreta_app/updater');

  late List<Omission> _omissions;
  late List<KretaMessage> _messages;
  final Set<String> _readMessageIds = {};

  late final TextEditingController _homeStationController;
  late final TextEditingController _homeTrainStationController;
  late final TextEditingController _schoolStationController;
  late final TextEditingController _schoolTrainStationController;
  late final TextEditingController _homeAddressController;
  late final TextEditingController _schoolAddressController;
  late final TextEditingController _fav1stController;
  late final TextEditingController _fav2ndController;
  final ValueNotifier<int> _stateVersion = ValueNotifier<int>(0);

  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');
  final DateFormat _dateTimeFormat = DateFormat('yyyy. MM. dd. HH:mm');

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _stateVersion.value++;
  }

  @override
  void initState() {
    super.initState();
    _currentPrefs = widget.prefs;
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    }).catchError((_) {});
    _omissions = List<Omission>.from(widget.initialOmissions);
    _messages = List<KretaMessage>.from(widget.initialMessages);
    _loadPersistedReadIds();
    _homeStationController =
        TextEditingController(text: _currentPrefs.transitHomeStation);
    _homeTrainStationController =
        TextEditingController(text: _currentPrefs.homeTrainStation);
    _schoolStationController =
        TextEditingController(text: _currentPrefs.transitSchoolStation);
    _schoolTrainStationController =
        TextEditingController(text: _currentPrefs.schoolTrainStation);
    _homeAddressController =
        TextEditingController(text: _currentPrefs.homeAddress);
    _schoolAddressController =
        TextEditingController(text: _currentPrefs.schoolAddress);
    _fav1stController =
        TextEditingController(text: _currentPrefs.favoriteRoute1stPeriod);
    _fav2ndController =
        TextEditingController(text: _currentPrefs.favoriteRoute2ndPeriod);

    if (!widget.settingsOnly &&
        widget.kretaClient != null &&
        (widget.messagesOnly || (_omissions.isEmpty && _messages.isEmpty))) {
      _refreshModules();
    } else if (widget.isActiveTab) {
      _armInitialEntranceIfNeeded();
    }
  }

  bool _isMessageRead(KretaMessage msg) {
    if (msg.isRead) return true;
    if (_readMessageIds.contains(msg.uid)) return true;
    if (msg.messageId != null && _readMessageIds.contains(msg.messageId)) {
      return true;
    }
    if (msg.isSystemMessage && _readMessageIds.contains('sys:${msg.uid}')) {
      return true;
    }
    return false;
  }

  void _loadPersistedReadIds() {
    const TokenStorageService()
        .loadReadMessageIds(
          accountKey: TokenStorageService.accountKeyForSession(widget.session),
        )
        .then((ids) {
      if (!mounted || ids.isEmpty) return;
      var changed = false;
      setState(() {
        _readMessageIds.addAll(ids);
        for (var i = 0; i < _messages.length; i++) {
          final m = _messages[i];
          if (!m.isRead && _isMessageRead(m)) {
            _messages[i] = m.copyWith(isRead: true);
            changed = true;
          }
        }
      });
      if (changed) {
        widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
      }
    }).catchError((_) {});
  }

  void _armInitialEntranceIfNeeded() {
    if (_initialEntrancePlayed) return;
    _initialEntrancePlayed = true;
    _entranceActive = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceActive = false;
      }
    });
  }

  @override
  void didUpdateWidget(covariant MoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefs != oldWidget.prefs) {
      _currentPrefs = widget.prefs;
      _stateVersion.value++;
    }
    if (widget.initialOmissions.isNotEmpty && _omissions.isEmpty) {
      _omissions = List<Omission>.from(widget.initialOmissions);
    }
    if (widget.initialMessages != oldWidget.initialMessages &&
        widget.initialMessages.isNotEmpty) {
      _messages = widget.initialMessages
          .map(
            (m) => !m.isRead && _isMessageRead(m) ? m.copyWith(isRead: true) : m,
          )
          .toList();
    }
    if (widget.isActiveTab && !oldWidget.isActiveTab && !_isLoadingModules) {
      setState(() {
        _armInitialEntranceIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _homeStationController.dispose();
    _homeTrainStationController.dispose();
    _schoolStationController.dispose();
    _schoolTrainStationController.dispose();
    _homeAddressController.dispose();
    _schoolAddressController.dispose();
    _fav1stController.dispose();
    _fav2ndController.dispose();
    _stateVersion.dispose();
    super.dispose();
  }

  void _updatePrefs(UserProfilePrefs nextPrefs) {
    UserProfilePrefs.syncActiveGlobals(nextPrefs);
    setState(() => _currentPrefs = nextPrefs);
    widget.onPrefsChanged(nextPrefs);
  }

  Future<void> _refreshModules() async {
    final client = widget.kretaClient;
    if (client == null) return;
    setState(() => _isLoadingModules = true);
    try {
      if (widget.messagesOnly) {
        final fetchedMessages = await client.fetchMessages(widget.session);
        if (!mounted) return;
        setState(() {
          _messages = fetchedMessages
              .map(
                (m) => !m.isRead && _isMessageRead(m)
                    ? m.copyWith(isRead: true)
                    : m,
              )
              .toList();
          _isLoadingModules = false;
          if (widget.isActiveTab) {
            _armInitialEntranceIfNeeded();
          }
        });
        widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
        return;
      }

      final results = await Future.wait<Object>([
        client.fetchOmissions(widget.session),
        client.fetchMessages(widget.session),
      ]);
      if (!mounted) return;
      setState(() {
        _omissions = results[0] as List<Omission>;
        _messages = (results[1] as List<KretaMessage>)
            .map(
              (m) =>
                  !m.isRead && _isMessageRead(m) ? m.copyWith(isRead: true) : m,
            )
            .toList();
        _isLoadingModules = false;
        if (widget.isActiveTab) {
          _armInitialEntranceIfNeeded();
        }
      });
      widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingModules = false;
        if (widget.isActiveTab) {
          _armInitialEntranceIfNeeded();
        }
      });
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

    final result = await showSoftBlurDialog<int>(
      context: context,
      prefs: _currentPrefs,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Érdemjegy ($grade) egyedi HEX színe',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'HEX színkód (#RRGGBB)',
                hintText: '#2E7D32',
                prefixIcon: Icon(Icons.colorize_rounded),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Mégse'),
                ),
                const SizedBox(width: 8),
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
            ),
          ],
        );
      },
    );

    if (result != null) {
      _setGradeColor(grade, result);
    }
  }

  void _previewRounding(GradeRoundingConfig nextConfig) {
    setState(() {
      _currentPrefs = _currentPrefs.copyWith(roundingConfig: nextConfig);
    });
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
          final file = File('${dir.path}/tinta_naplo_settings_backup.json');
          await file.writeAsString(jsonStr);
          savedFilePath = file.path;
          break;
        }
      } catch (_) {}
    }

    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;

    await showSoftBlurDialog<void>(
      context: context,
      prefs: _currentPrefs,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Beállítások exportálva (JSON)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
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
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Rendben'),
              ),
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

    final restoredPrefs = await showSoftBlurDialog<UserProfilePrefs>(
      context: context,
      prefs: _currentPrefs,
      builder: (dialogContext) {
        String? errorMsg;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final theme = Theme.of(context);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Beállítások importálása (JSON)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
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
                                      () => errorMsg =
                                          'Nem sikerült beolvasni: $e',
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
                            hintText: '/storage/.../tinta_naplo_settings_backup.json',
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
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Mégse'),
                    ),
                    const SizedBox(width: 8),
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

  Future<void> _downloadAndOpenAttachment(
    BuildContext feedbackContext,
    KretaMessageAttachment attachment,
    ValueNotifier<String?> downloadingIdNotifier,
    bool Function() isSheetClosed,
  ) async {
    final client = widget.kretaClient;
    if (client == null) return;
    if (!isSheetClosed()) {
      downloadingIdNotifier.value = attachment.id;
    }
    try {
      final file = await client.downloadMessageAttachment(
        widget.session,
        attachment,
      );
      if (Platform.isAndroid) {
        await _fileChannel.invokeMethod<String>('openFile', {
          'filePath': file.path,
        });
      }
    } catch (e) {
      if (feedbackContext.mounted) {
        ScaffoldMessenger.of(feedbackContext).showSnackBar(
          SnackBar(
            content: Text(
              uwu('Csatolmány megnyitása sikertelen: $e'),
            ),
          ),
        );
      }
    } finally {
      if (!isSheetClosed()) {
        downloadingIdNotifier.value = null;
      }
    }
  }

  void _openMessageDetailModal(KretaMessage msg) {
    HapticFeedback.lightImpact();
    setState(() {
      _readMessageIds.add(msg.uid);
      if (msg.messageId != null && msg.messageId!.isNotEmpty) {
        _readMessageIds.add(msg.messageId!);
      }
      if (msg.isSystemMessage) {
        _readMessageIds.add('sys:${msg.uid}');
      }
      final idx = _messages.indexWhere(
        (m) => m.uid == msg.uid && m.isSystemMessage == msg.isSystemMessage,
      );
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(isRead: true);
      }
    });
    widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));

    final client = widget.kretaClient;
    if (client != null) {
      unawaited(
        client.markMessageAsRead(widget.session, msg).catchError((_) {}),
      );
    } else {
      unawaited(
        const TokenStorageService().markMessagesReadLocally(
          [
            msg.uid,
            if (msg.messageId != null && msg.messageId!.isNotEmpty)
              msg.messageId!,
            if (msg.isSystemMessage) 'sys:${msg.uid}',
          ],
          accountKey: TokenStorageService.accountKeyForSession(widget.session),
        ),
      );
    }

    final shouldFetchDetails =
        !msg.isSystemMessage && !msg.detailsLoaded && client != null;
    final msgNotifier = ValueNotifier<KretaMessage>(msg.copyWith(isRead: true));
    final loadingNotifier = ValueNotifier<bool>(shouldFetchDetails);
    final downloadingIdNotifier = ValueNotifier<String?>(null);
    var sheetClosed = false;

    if (shouldFetchDetails) {
      client.fetchMessageDetail(widget.session, msg).then((detailed) {
        final merged = detailed.copyWith(isRead: true, detailsLoaded: true);
        if (!sheetClosed) {
          msgNotifier.value = merged;
          loadingNotifier.value = false;
        }
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere(
              (m) =>
                  m.uid == msg.uid && m.isSystemMessage == msg.isSystemMessage,
            );
            if (idx != -1) {
              _messages[idx] = merged;
            }
          });
          widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
        }
      }).catchError((_) {
        if (!sheetClosed) {
          loadingNotifier.value = false;
        }
      });
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: resolveSoftBlurBarrierColor(context, prefs: _currentPrefs),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;
        return LiquidGlassSurface(
          prefs: _currentPrefs,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: DraggableScrollableSheet(
            initialChildSize: 0.78,
            minChildSize: 0.5,
            maxChildSize: 0.94,
            expand: false,
            builder: (context, scrollController) {
              return ValueListenableBuilder<KretaMessage>(
                valueListenable: msgNotifier,
                builder: (context, current, _) {
                  final senderDisplay =
                      _currentPrefs.resolveTeacherName(current.sender);
                  final senderLine = current.senderTitle != null &&
                          current.senderTitle!.isNotEmpty
                      ? '$senderDisplay (${current.senderTitle})'
                      : senderDisplay;
                  return ValueListenableBuilder<bool>(
                    valueListenable: loadingNotifier,
                    builder: (context, isLoadingDetails, _) {
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
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.24),
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
                                    color:
                                        scheme.primary.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    current.isSystemMessage
                                        ? Icons.campaign_rounded
                                        : Icons.mail_rounded,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        current.subject,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Feladó: $senderLine',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (current.recipients.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Címzett: ${current.recipients.join(", ")}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: scheme.onSurface
                                                .withValues(alpha: 0.65),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            _dateTimeFormat.format(
                                              current.sentAt.toLocal(),
                                            ),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.55),
                                            ),
                                          ),
                                          if (current.isSystemMessage) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: scheme.primary
                                                    .withValues(alpha: 0.14),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'Rendszer',
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: scheme.primary,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            if (isLoadingDetails) ...[
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: const LinearProgressIndicator(
                                  minHeight: 3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: OledTheme.cardRadius,
                                border: Border.all(color: theme.dividerColor),
                              ),
                              child: SelectableText(
                                current.cleanBody.isNotEmpty
                                    ? current.cleanBody
                                    : (isLoadingDetails
                                        ? 'Üzenet tartalmának betöltése...'
                                        : 'Üres üzenetszöveg.'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.45,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            if (current.attachments.isNotEmpty ||
                                (current.hasAttachments &&
                                    isLoadingDetails)) ...[
                              const SizedBox(height: 14),
                              Text(
                                'Csatolmányok',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.78),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (current.attachments.isEmpty &&
                                  isLoadingDetails)
                                Text(
                                  'Csatolmányok betöltése...',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                )
                              else
                                ValueListenableBuilder<String?>(
                                  valueListenable: downloadingIdNotifier,
                                  builder: (context, downloadingId, _) {
                                    return Column(
                                      children: current.attachments.map((att) {
                                        final isDownloading =
                                            downloadingId == att.id;
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            onTap: isDownloading
                                                ? null
                                                : () =>
                                                    _downloadAndOpenAttachment(
                                                      sheetContext,
                                                      att,
                                                      downloadingIdNotifier,
                                                      () => sheetClosed,
                                                    ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color:
                                                    scheme.surfaceContainerHigh,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: theme.dividerColor,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.attach_file_rounded,
                                                    size: 18,
                                                    color: scheme.primary,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      att.fileName,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  if (isDownloading)
                                                    const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  else
                                                    Icon(
                                                      Icons
                                                          .download_rounded,
                                                      size: 18,
                                                      color: scheme.primary,
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        Navigator.of(sheetContext).pop(),
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
                                        initialRecipient: current.sender,
                                        initialSubject:
                                            current.subject.startsWith('Re:')
                                                ? current.subject
                                                : 'Re: ${current.subject}',
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.reply_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Válasz küldése'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      sheetClosed = true;
      msgNotifier.dispose();
      loadingNotifier.dispose();
      downloadingIdNotifier.dispose();
    });
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

    final sent = await showSoftBlurDialog<KretaMessage>(
      context: context,
      prefs: _currentPrefs,
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

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  initialRecipient != null ? 'Válasz üzenet' : 'Új Kréta üzenet',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
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
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: isSending
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: const Text('Mégse'),
                    ),
                    const SizedBox(width: 8),
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
                                    widget.session.userName ??
                                    '',
                              );
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop(created);
                              }
                            },
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(isSending ? 'Küldés...' : 'Küldés'),
                    ),
                  ],
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
      widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
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
    super.build(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expFormat = DateFormat('yyyy. MM. dd. HH:mm');

    // B6: On the 'Továbbiak' bottom tab (!widget.settingsOnly), render ONLY
    // the Attendance and Kréta Messages modules. Settings are accessible
    // EXCLUSIVELY via the top-right Profile sheet (`AppSettingsScreen`).
    if (!widget.settingsOnly) {
      return RefreshIndicator(
        displacement: 44,
        edgeOffset: 8,
        strokeWidth: 2.6,
        onRefresh: _refreshModules,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: widget.messagesOnly
              ? const EdgeInsets.fromLTRB(16, 12, 16, 112)
              : const EdgeInsets.fromLTRB(0, 12, 0, 112),
          children: widget.messagesOnly
              ? [
                  _buildMessagesModuleCard(theme, scheme)
                      .staggeredEntrance(0, enabled: _entranceActive),
                ]
              : _buildAttendanceTabChildren(theme, scheme),
        ),
      );
    }

    // Main Settings view (`widget.settingsOnly == true`):
    return ListView(
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
        _SettingsAccordionCard(
          icon: Icons.manage_accounts_rounded,
          title: 'Fiók és munkamenet',
          subtitle:
              widget.student?.name ?? widget.session.userName ?? '—',
          christmasCap: _currentPrefs.christmasModeEnabled,
          prefs: _currentPrefs,
          stateListenable: _stateVersion,
          prefsGetter: () => _currentPrefs,
          childrenBuilder: () => [
            _buildRow(
              scheme,
              'Tanuló neve',
              widget.student?.name ?? widget.session.userName ?? '—',
            ),
            _buildRow(
              scheme,
              'Beállított becenév',
              (_currentPrefs.nickname?.trim().isNotEmpty ?? false)
                  ? _currentPrefs.nickname!
                  : 'Alapértelmezett',
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
              onPressed: () async {
                final rootNav = Navigator.of(context, rootNavigator: true);
                await Future.sync(widget.onLogout);
                rootNav.pushNamedAndRemoveUntil('/login', (route) => false);
              },
              icon: const Icon(Icons.logout_rounded),
              label: Text(
                uwu('Kijelentkezés (beállítások megtartásával)'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _SettingsAccordionCard(
          icon: Icons.palette_rounded,
          title: 'Megjelenés és témák',
          subtitle: 'OLED Fekete, Material You, Háttér és Ablakok',
          christmasCap: _currentPrefs.christmasModeEnabled,
          prefs: _currentPrefs,
          stateListenable: _stateVersion,
          prefsGetter: () => _currentPrefs,
          childrenBuilder: () => [
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
            const SizedBox(height: 6),
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
            EdgeFadeHorizontalScroll(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              spacing: 10,
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
            const SizedBox(height: 16),
            Text(
              'Háttér effektus / atmoszféra:',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            EdgeFadeHorizontalScroll(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              spacing: 8,
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
            EdgeFadeHorizontalScroll(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              spacing: 8,
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

        _SettingsAccordionCard(
          icon: Icons.color_lens_rounded,
          title: 'Érdemjegyek Színeinek Testreszabása',
          subtitle: 'Egyedi színek és HEX kódok az 1–5 jegyekhez',
          christmasCap: _currentPrefs.christmasModeEnabled,
          prefs: _currentPrefs,
          stateListenable: _stateVersion,
          prefsGetter: () => _currentPrefs,
          childrenBuilder: () => [
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
            EdgeFadeHorizontalScroll(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              spacing: 10,
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

        _buildMenetrendSettingsAccordion(theme, scheme),
        const SizedBox(height: 12),

        _SettingsAccordionCard(
          icon: Icons.tune_rounded,
          title: 'Órarend',
          subtitle: 'Átlag küszöbök, elmaradt/nulladik órák és hétvége',
          christmasCap: _currentPrefs.christmasModeEnabled,
          prefs: _currentPrefs,
          stateListenable: _stateVersion,
          prefsGetter: () => _currentPrefs,
          childrenBuilder: () => [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Elmaradó órák elrejtése',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Az elmaradt tanórák nem jelennek meg az órarendben',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              value: _currentPrefs.hideCancelledLessons,
              onChanged: (val) => _updatePrefs(
                _currentPrefs.withExtra('hideCancelledLessons', val),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Lyukas / szabad órák elrejtése',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'A szabad sávok (nulladik óra, lyukasóra) nem jelennek meg',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              value: _currentPrefs.hideFreeLessons,
              onChanged: (val) => _updatePrefs(
                _currentPrefs.withExtra('hideFreeLessons', val),
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
            EdgeFadeHorizontalScroll(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              spacing: 8,
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
              value: _currentPrefs.roundingConfig.threshold5,
              min: 4.00,
              max: 4.95,
              onChanged: (v) => _previewRounding(
                _currentPrefs.roundingConfig.copyWith(
                  threshold5: double.parse(v.toStringAsFixed(2)),
                ),
              ),
              onChangeEnd: (v) => _updateRounding(
                _currentPrefs.roundingConfig.copyWith(
                  threshold5: double.parse(v.toStringAsFixed(2)),
                ),
              ),
            ),
            _buildThresholdSlider(
              theme: theme,
              scheme: scheme,
              gradeLabel: 'Jó (4) határ',
              color: _currentPrefs.colorForGrade(4),
              value: _currentPrefs.roundingConfig.threshold4,
              min: 3.00,
              max: 3.95,
              onChanged: (v) => _previewRounding(
                _currentPrefs.roundingConfig.copyWith(
                  threshold4: double.parse(v.toStringAsFixed(2)),
                ),
              ),
              onChangeEnd: (v) => _updateRounding(
                _currentPrefs.roundingConfig.copyWith(
                  threshold4: double.parse(v.toStringAsFixed(2)),
                ),
              ),
            ),
            _buildThresholdSlider(
              theme: theme,
              scheme: scheme,
              gradeLabel: 'Közepes (3) határ',
              color: _currentPrefs.colorForGrade(3),
              value: _currentPrefs.roundingConfig.threshold3,
              min: 2.00,
              max: 2.95,
              onChanged: (v) => _previewRounding(
                _currentPrefs.roundingConfig.copyWith(
                  threshold3: double.parse(v.toStringAsFixed(2)),
                ),
              ),
              onChangeEnd: (v) => _updateRounding(
                _currentPrefs.roundingConfig.copyWith(
                  threshold3: double.parse(v.toStringAsFixed(2)),
                ),
              ),
            ),
            _buildThresholdSlider(
              theme: theme,
              scheme: scheme,
              gradeLabel: 'Elégséges (2) határ',
              color: _currentPrefs.colorForGrade(2),
              value: _currentPrefs.roundingConfig.threshold2,
              min: 1.10,
              max: 2.20,
              onChanged: (v) => _previewRounding(
                _currentPrefs.roundingConfig.copyWith(
                  threshold2: double.parse(v.toStringAsFixed(2)),
                ),
              ),
              onChangeEnd: (v) => _updateRounding(
                _currentPrefs.roundingConfig.copyWith(
                  threshold2: double.parse(v.toStringAsFixed(2)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _SettingsAccordionCard(
          icon: Icons.import_export_rounded,
          title: 'Beállítások exportálása / importálása',
          subtitle: 'JSON biztonsági mentés készítése és visszaállítása',
          christmasCap: _currentPrefs.christmasModeEnabled,
          prefs: _currentPrefs,
          stateListenable: _stateVersion,
          prefsGetter: () => _currentPrefs,
          childrenBuilder: () => [
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

        _SettingsAccordionCard(
          icon: Icons.info_outline_rounded,
          title: uwu('Rendszer / Névjegy'),
          subtitle: 'Tinta Napló v$_appVersion • GitHub OTA frissítő',
          christmasCap: _currentPrefs.christmasModeEnabled,
          prefs: _currentPrefs,
          stateListenable: _stateVersion,
          prefsGetter: () => _currentPrefs,
          childrenBuilder: () => [
            _buildRow(
              scheme,
              uwu('Alkalmazás'),
              uwu('Tinta Napló v$_appVersion'),
            ),
            _buildRow(scheme, uwu('GitHub'), 'github.com/mlnlbrt10/tinta-naplo'),
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
    final speedKmh = _currentPrefs.walkingSpeedKmh;

    return _SettingsAccordionCard(
      icon: Icons.directions_railway_filled_rounded,
      title: 'MenetrendGO',
      subtitle: _currentPrefs.transitConfigured
          ? '${_currentPrefs.primaryHomeStop} ↔ ${_currentPrefs.primarySchoolStop}'
          : 'Nincs beállítva',
      christmasCap: _currentPrefs.christmasModeEnabled,
      prefs: _currentPrefs,
      stateListenable: _stateVersion,
      prefsGetter: () => _currentPrefs,
      childrenBuilder: () => [
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
        const SizedBox(height: 8),
        Text(
          '1. Otthoni cím (pontos lakcím automatikus sétaszámítással):',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        _TransitStopSearchField(
          controller: _homeAddressController,
          label: 'Otthoni cím',
          hint: 'Kezdd el gépelni a címed (pl. Szolnok, Kossuth tér 1.)',
          icon: Icons.home_work_rounded,
          isAddressSearch: true,
          onSelectedResult: (r) {
            var next = _currentPrefs.withExtras({
              'homeAddress': r.name,
              'homeAddressLat': r.lat,
              'homeAddressLon': r.lon,
            });
            final busLat = (next.extras['homeBusLat'] as num?)?.toDouble();
            final busLon = (next.extras['homeBusLon'] as num?)?.toDouble();
            if (busLat != null && busLon != null) {
              final walkMins = MenetrendService.estimateWalkingMinutesBetween(
                lat1: r.lat,
                lon1: r.lon,
                lat2: busLat,
                lon2: busLon,
                walkingSpeedKmh: next.walkingSpeedKmh,
              );
              next = next.copyWith(
                walkHomeToBusMinutes: walkMins,
                walkingDurationMinutes: walkMins,
              );
            }
            final trainLat = (next.extras['homeTrainLat'] as num?)?.toDouble();
            final trainLon = (next.extras['homeTrainLon'] as num?)?.toDouble();
            if (trainLat != null && trainLon != null) {
              next = next.copyWith(
                walkHomeToTrainMinutes:
                    MenetrendService.estimateWalkingMinutesBetween(
                  lat1: r.lat,
                  lon1: r.lon,
                  lat2: trainLat,
                  lon2: trainLon,
                  walkingSpeedKmh: next.walkingSpeedKmh,
                ),
              );
            }
            _updatePrefs(next);
          },
          onSelected: (name) => _updatePrefs(
            _currentPrefs.withExtra('homeAddress', name),
          ),
          onCleared: () => _updatePrefs(
            _currentPrefs.withExtras({
              'homeAddress': null,
              'homeAddressLat': null,
              'homeAddressLon': null,
            }),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '2. Iskola címe (pontos iskolacím automatikus sétaszámítással):',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        _TransitStopSearchField(
          controller: _schoolAddressController,
          label: 'Iskola címe',
          hint: 'Kezdd el gépelni az iskola címét (pl. Szolnok, Ady Endre út)',
          icon: Icons.apartment_rounded,
          isAddressSearch: true,
          onSelectedResult: (r) {
            var next = _currentPrefs.withExtras({
              'schoolAddress': r.name,
              'schoolAddressLat': r.lat,
              'schoolAddressLon': r.lon,
            });
            final busLat = (next.extras['schoolBusLat'] as num?)?.toDouble();
            final busLon = (next.extras['schoolBusLon'] as num?)?.toDouble();
            if (busLat != null && busLon != null) {
              next = next.copyWith(
                walkSchoolToBusMinutes:
                    MenetrendService.estimateWalkingMinutesBetween(
                  lat1: r.lat,
                  lon1: r.lon,
                  lat2: busLat,
                  lon2: busLon,
                  walkingSpeedKmh: next.walkingSpeedKmh,
                ),
              );
            }
            final trainLat =
                (next.extras['schoolTrainLat'] as num?)?.toDouble();
            final trainLon =
                (next.extras['schoolTrainLon'] as num?)?.toDouble();
            if (trainLat != null && trainLon != null) {
              next = next.copyWith(
                walkSchoolToTrainMinutes:
                    MenetrendService.estimateWalkingMinutesBetween(
                  lat1: r.lat,
                  lon1: r.lon,
                  lat2: trainLat,
                  lon2: trainLon,
                  walkingSpeedKmh: next.walkingSpeedKmh,
                ),
              );
            }
            _updatePrefs(next);
          },
          onSelected: (name) => _updatePrefs(
            _currentPrefs.withExtra('schoolAddress', name),
          ),
          onCleared: () => _updatePrefs(
            _currentPrefs.withExtras({
              'schoolAddress': null,
              'schoolAddressLat': null,
              'schoolAddressLon': null,
            }),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '3. Otthoni megálló (Buszmegálló & Vasútállomás):',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        _TransitStopSearchField(
          controller: _homeStationController,
          label: 'Otthoni buszmegálló',
          hint: 'Keress buszmegállót vagy állomást',
          icon: Icons.directions_bus_rounded,
          onSelectedResult: (r) {
            var next = _currentPrefs
                .copyWith(transitHomeStation: r.name)
                .withExtras({'homeBusLat': r.lat, 'homeBusLon': r.lon});
            if (next.homeAddressLat != null && next.homeAddressLon != null) {
              final walkMins = MenetrendService.estimateWalkingMinutesBetween(
                lat1: next.homeAddressLat!,
                lon1: next.homeAddressLon!,
                lat2: r.lat,
                lon2: r.lon,
                walkingSpeedKmh: next.walkingSpeedKmh,
              );
              next = next.copyWith(
                walkHomeToBusMinutes: walkMins,
                walkingDurationMinutes: walkMins,
              );
            }
            _updatePrefs(next);
          },
          onSelected: (name) => _updatePrefs(
            _currentPrefs.copyWith(transitHomeStation: name),
          ),
          onCleared: () => _updatePrefs(
            _currentPrefs.copyWith(transitHomeStation: ''),
          ),
        ),
        const SizedBox(height: 8),
        _TransitStopSearchField(
          controller: _homeTrainStationController,
          label: 'Otthoni vasútállomás',
          hint: 'Keress vasútállomást (opcionális)',
          icon: Icons.train_rounded,
          onSelectedResult: (r) {
            var next = _currentPrefs.withExtras({
              'homeTrainStation': r.name,
              'homeTrainLat': r.lat,
              'homeTrainLon': r.lon,
            });
            if (next.homeAddressLat != null && next.homeAddressLon != null) {
              next = next.copyWith(
                walkHomeToTrainMinutes:
                    MenetrendService.estimateWalkingMinutesBetween(
                  lat1: next.homeAddressLat!,
                  lon1: next.homeAddressLon!,
                  lat2: r.lat,
                  lon2: r.lon,
                  walkingSpeedKmh: next.walkingSpeedKmh,
                ),
              );
            }
            _updatePrefs(next);
          },
          onSelected: (name) => _updatePrefs(
            _currentPrefs.withExtra('homeTrainStation', name),
          ),
          onCleared: () => _updatePrefs(
            _currentPrefs.withExtra('homeTrainStation', null),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '4. Iskolai megálló (Buszmegálló & Vasútállomás):',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        _TransitStopSearchField(
          controller: _schoolStationController,
          label: 'Iskolai buszmegálló',
          hint: 'Keress iskolai buszmegállót vagy állomást',
          icon: Icons.directions_bus_filled_rounded,
          onSelectedResult: (r) {
            var next = _currentPrefs
                .copyWith(transitSchoolStation: r.name)
                .withExtras({'schoolBusLat': r.lat, 'schoolBusLon': r.lon});
            if (next.schoolAddressLat != null &&
                next.schoolAddressLon != null) {
              next = next.copyWith(
                walkSchoolToBusMinutes:
                    MenetrendService.estimateWalkingMinutesBetween(
                  lat1: next.schoolAddressLat!,
                  lon1: next.schoolAddressLon!,
                  lat2: r.lat,
                  lon2: r.lon,
                  walkingSpeedKmh: next.walkingSpeedKmh,
                ),
              );
            }
            _updatePrefs(next);
          },
          onSelected: (name) => _updatePrefs(
            _currentPrefs.copyWith(transitSchoolStation: name),
          ),
          onCleared: () => _updatePrefs(
            _currentPrefs.copyWith(transitSchoolStation: ''),
          ),
        ),
        const SizedBox(height: 8),
        _TransitStopSearchField(
          controller: _schoolTrainStationController,
          label: 'Iskolai vasútállomás',
          hint: 'Keress vasútállomást az iskola közelében (opcionális)',
          icon: Icons.directions_railway_rounded,
          onSelectedResult: (r) {
            var next = _currentPrefs.withExtras({
              'schoolTrainStation': r.name,
              'schoolTrainLat': r.lat,
              'schoolTrainLon': r.lon,
            });
            if (next.schoolAddressLat != null &&
                next.schoolAddressLon != null) {
              next = next.copyWith(
                walkSchoolToTrainMinutes:
                    MenetrendService.estimateWalkingMinutesBetween(
                  lat1: next.schoolAddressLat!,
                  lon1: next.schoolAddressLon!,
                  lat2: r.lat,
                  lon2: r.lon,
                  walkingSpeedKmh: next.walkingSpeedKmh,
                ),
              );
            }
            _updatePrefs(next);
          },
          onSelected: (name) => _updatePrefs(
            _currentPrefs.withExtra('schoolTrainStation', name),
          ),
          onCleared: () => _updatePrefs(
            _currentPrefs.withExtra('schoolTrainStation', null),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'A gyaloglási idő automatikusan kiszámolódik a megadott címek és megállók távolságából.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.6),
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
        Text(
          'Gyaloglási tempó:',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        EdgeFadeHorizontalScroll(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          spacing: 8,
          children: [
            for (final kmh in const [4.0, 5.0, 6.0])
              ChoiceChip(
                showCheckmark: false,
                label: Text(MenetrendService.walkingSpeedLabel(kmh)),
                selected:
                    MenetrendService.normalizeWalkingSpeed(speedKmh) == kmh,
                onSelected: (_) => _updatePrefs(
                  _currentPrefs.copyWith(walkingSpeedKmh: kmh),
                ),
              ),
          ],
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
        Text(
          'Napi ingázási beállítások (Hétfő–Péntek • Odafele & Hazafele):',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        _FullBleedChild(
          child: _DayCommuteEditor(
            prefs: _currentPrefs,
            onChanged: _updatePrefs,
          ),
        ),
        const Divider(height: 20),
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
  List<Widget> _buildAttendanceTabChildren(
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final summary = OmissionsSummary.fromList(_omissions);
    final filtered = _filterOmissions(summary, _attendanceFilter);
    final dailyGroups = groupOmissionsByDay(filtered);

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ChristmasSnowCap(
          enabled: _currentPrefs.christmasModeEnabled,
          child: SoftGlassCard(
            prefs: _currentPrefs,
            padding: const EdgeInsets.all(18),
            borderRadius: OledTheme.largeRadius,
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
                const SizedBox(height: 14),
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
        ).staggeredEntrance(0, enabled: _entranceActive),
      ),
      const SizedBox(height: 12),
      _buildOmissionFilterChips(
        selected: _attendanceFilter,
        onSelected: (f) => setState(() => _attendanceFilter = f),
      ),
      const SizedBox(height: 12),
      if (dailyGroups.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildEmptyOmissionCard(
            prefs: _currentPrefs,
            message:
                'Nincs rögzített mulasztás vagy késés ebben a kategóriában.',
          ),
        )
      else
        for (int i = 0; i < dailyGroups.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _DailyOmissionCard(
              group: dailyGroups[i],
              prefs: _currentPrefs,
              dateFormat: _dateFormat,
            ).staggeredEntrance(
              i < 6 ? i + 1 : 6,
              enabled: _entranceActive,
            ),
          ),
    ];
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
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: OledTheme.largeRadius,
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
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
            ),
            const SizedBox(height: 12),
            EdgeFadeHorizontalScroll(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              spacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.inbox_rounded, size: 16),
                  label: const Text('Beérkezett'),
                  showCheckmark: false,
                  selected: !_showSentMessages,
                  onSelected: (_) =>
                      setState(() => _showSentMessages = false),
                ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    ...visibleMessages.map((msg) {
                      final isRead = _isMessageRead(msg);
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
                                        : scheme.onSurface
                                            .withValues(alpha: 0.25),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              msg.isSent &&
                                                      msg.recipients.isNotEmpty
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
                                          if (msg.isSystemMessage) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: scheme.primary
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Rendszer',
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  color: scheme.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (msg.hasAttachments ||
                                              msg.attachments.isNotEmpty) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.attach_file_rounded,
                                              size: 13,
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.65),
                                            ),
                                          ],
                                          const SizedBox(width: 6),
                                          Text(
                                            _dateFormat
                                                .format(msg.sentAt.toLocal()),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.58),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        msg.subject,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
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
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
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
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.5),
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
    ValueChanged<double>? onChangeEnd,
  }) {
    final clamped = value.clamp(min, max);

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
            activeColor: color,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
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
    final summary = OmissionsSummary.fromList(widget.omissions);
    final filtered = _filterOmissions(summary, _filter);
    final dailyGroups = groupOmissionsByDay(filtered);

    return AdaptiveBackgroundScaffold(
      prefs: widget.prefs,
      appBar: buildAdaptiveTransparentAppBar(
        context,
        title: uwu('Összes hiányzás és késés'),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          0,
          adaptiveAppBarTopPadding(context),
          0,
          36,
        ),
        children: [
          _buildOmissionFilterChips(
            selected: _filter,
            onSelected: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (dailyGroups.isEmpty)
                  _buildEmptyOmissionCard(
                    prefs: widget.prefs,
                    message:
                        'Nincs rögzített mulasztás vagy késés ebben a szűrőben.',
                  )
                else
                  for (final group in dailyGroups) ...[
                    _DailyOmissionCard(
                      group: group,
                      prefs: widget.prefs,
                      dateFormat: _dateFormat,
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings category row. Tapping it pushes a dedicated, full-screen
/// sub-screen (no cramped inline accordions). The sub-screen stays reactive:
/// whenever [stateListenable] fires, [childrenBuilder] and [prefsGetter] are
/// re-evaluated immediately inside the open route.
class _SettingsAccordionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> Function()? childrenBuilder;
  final ValueListenable<int>? stateListenable;
  final UserProfilePrefs Function()? prefsGetter;
  final bool christmasCap;
  final UserProfilePrefs? prefs;

  const _SettingsAccordionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.childrenBuilder,
    this.stateListenable,
    this.prefsGetter,
    this.christmasCap = false,
    this.prefs,
  });

  @override
  State<_SettingsAccordionCard> createState() => _SettingsAccordionCardState();
}

class _SettingsAccordionCardState extends State<_SettingsAccordionCard> {
  Future<void> _openSubScreen() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      SmoothSharedAxisRoute(
        page: _SettingsSubScreen(
          title: widget.title,
          prefs: widget.prefs,
          prefsGetter: widget.prefsGetter,
          stateListenable: widget.stateListenable,
          childrenBuilder: widget.childrenBuilder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final activePrefs =
        widget.prefsGetter?.call() ?? widget.prefs ?? const UserProfilePrefs();

    return ChristmasSnowCap(
      enabled: widget.christmasCap,
      child: SoftGlassCard(
        prefs: activePrefs,
        padding: EdgeInsets.zero,
        borderRadius: OledTheme.largeRadius,
        child: TactileBounce(
          pressedScale: 0.98,
          onTap: _openSubScreen,
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
                  child: Icon(widget.icon, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
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
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Marks a settings child as full-bleed inside [_SettingsSubScreen] so
/// horizontal scroll bars reach the card edges without outer padding clipping.
class _FullBleedChild extends StatelessWidget {
  final Widget child;

  const _FullBleedChild({required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Dedicated settings sub-screen pushed by [_SettingsAccordionCard].
class _SettingsSubScreen extends StatelessWidget {
  final String title;
  final UserProfilePrefs? prefs;
  final UserProfilePrefs Function()? prefsGetter;
  final ValueListenable<int>? stateListenable;
  final List<Widget> Function()? childrenBuilder;

  const _SettingsSubScreen({
    required this.title,
    required this.prefs,
    this.prefsGetter,
    this.stateListenable,
    this.childrenBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final listenable = stateListenable ?? ValueNotifier<int>(0);
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, _, _) {
        final currentPrefs = prefsGetter?.call() ?? prefs;
        final currentChildren = childrenBuilder != null
            ? childrenBuilder!()
            : const <Widget>[];
        return AdaptiveBackgroundScaffold(
          prefs: currentPrefs,
          appBar: buildAdaptiveTransparentAppBar(
            context,
            title: uwu(title),
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              adaptiveAppBarTopPadding(context),
              16,
              40,
            ),
            children: [
              SoftGlassCard(
                prefs: currentPrefs ?? const UserProfilePrefs(),
                padding: const EdgeInsets.symmetric(vertical: 14),
                borderRadius: OledTheme.largeRadius,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final child in currentChildren)
                      if (child is _FullBleedChild ||
                          child is EdgeFadeHorizontalScroll)
                        child
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: child,
                        ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Bidirectional per-weekday commute preferences (Hétfő–Péntek):
/// - Direction selector: "Odafele (Reggeli bejárás)" vs "Hazafele (Délutáni hazaút)"
/// - Scheduled departure picker fetched from the real timetable
/// - Per-direction/day toggle between "Helyi járat használata" vs "Gyaloglás"
class _DayCommuteEditor extends StatefulWidget {
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onChanged;

  const _DayCommuteEditor({required this.prefs, required this.onChanged});

  @override
  State<_DayCommuteEditor> createState() => _DayCommuteEditorState();
}

class _DayCommuteEditorState extends State<_DayCommuteEditor> {
  static const _days = ['Hétfő', 'Kedd', 'Szerda', 'Csütörtök', 'Péntek'];
  final MenetrendService _service = MenetrendService();
  int _selected = (DateTime.now().weekday - 1).clamp(0, 4);
  bool _isMorning = true;
  late final TextEditingController _lineController;
  List<({String value, String label})> _scheduledOptions = const [];
  bool _loadingOptions = false;

  Map<String, dynamic> get _plan =>
      widget.prefs.commutePlanForWeekday(_selected + 1);

  String get _currentLine {
    final key = _isMorning ? 'morningLine' : 'afternoonLine';
    final specific = (_plan[key] as String?)?.trim() ?? '';
    if (specific.isNotEmpty) return specific;
    return _isMorning ? ((_plan['line'] as String?)?.trim() ?? '') : '';
  }

  bool get _currentUseLocalBus {
    final key = _isMorning ? 'morningUseLocalBus' : 'afternoonUseLocalBus';
    if (_plan.containsKey(key)) {
      return _plan[key] != false;
    }
    return _plan['useLocalBus'] != false;
  }

  @override
  void initState() {
    super.initState();
    _lineController = TextEditingController(text: _currentLine);
    _fetchOptions();
  }

  @override
  void didUpdateWidget(covariant _DayCommuteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs.primaryHomeStop != widget.prefs.primaryHomeStop ||
        oldWidget.prefs.primarySchoolStop != widget.prefs.primarySchoolStop) {
      _fetchOptions();
    }
  }

  @override
  void dispose() {
    _lineController.dispose();
    super.dispose();
  }

  Future<void> _fetchOptions() async {
    if (!widget.prefs.transitConfigured) {
      if (mounted) {
        setState(() {
          _scheduledOptions = const [];
          _loadingOptions = false;
        });
      }
      return;
    }
    setState(() => _loadingOptions = true);
    try {
      final opts = await _service.fetchScheduledDepartureOptions(
        prefs: widget.prefs,
        isMorning: _isMorning,
        weekday: _selected + 1,
        useLocalBus: _currentUseLocalBus,
      );
      if (!mounted) return;
      setState(() {
        _scheduledOptions = opts;
        _loadingOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scheduledOptions = const [];
        _loadingOptions = false;
      });
    }
  }

  void _syncTextController() {
    final text = _currentLine;
    if (_lineController.text != text) {
      _lineController.text = text;
    }
  }

  void _save({String? line, bool? useLocalBus}) {
    final plan = Map<String, dynamic>.from(_plan);
    if (line != null) {
      if (_isMorning) {
        plan['morningLine'] = line;
        plan['line'] = line;
      } else {
        plan['afternoonLine'] = line;
      }
    }
    if (useLocalBus != null) {
      if (_isMorning) {
        plan['morningUseLocalBus'] = useLocalBus;
        plan['useLocalBus'] = useLocalBus;
      } else {
        plan['afternoonUseLocalBus'] = useLocalBus;
      }
    }
    widget.onChanged(widget.prefs.withCommutePlan(_selected + 1, plan));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final useLocalBus = _currentUseLocalBus;
    final selectedLine = _currentLine;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Weekday selector (Hétfő – Péntek)
        EdgeFadeHorizontalScroll(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          spacing: 6,
          children: [
            for (var i = 0; i < _days.length; i++)
              ChoiceChip(
                showCheckmark: false,
                label: Text(_days[i]),
                selected: _selected == i,
                onSelected: (_) {
                  setState(() => _selected = i);
                  _syncTextController();
                  _fetchOptions();
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Direction selector: Odafele vs Hazafele
        EdgeFadeHorizontalScroll(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          spacing: 8,
          children: [
            ChoiceChip(
              showCheckmark: false,
              avatar: const Icon(Icons.wb_sunny_rounded, size: 16),
              label: const Text('Odafele (Reggeli bejárás)'),
              selected: _isMorning,
              onSelected: (_) {
                if (_isMorning) return;
                setState(() => _isMorning = true);
                _syncTextController();
                _fetchOptions();
              },
            ),
            ChoiceChip(
              showCheckmark: false,
              avatar: const Icon(Icons.home_rounded, size: 16),
              label: const Text('Hazafele (Délutáni hazaút)'),
              selected: !_isMorning,
              onSelected: (_) {
                if (!_isMorning) return;
                setState(() => _isMorning = false);
                _syncTextController();
                _fetchOptions();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Connecting local transit vs walking toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Csatlakozás módja (${_days[_selected]} • ${_isMorning ? "Odafele" : "Hazafele"})',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
        ),
        const SizedBox(height: 6),
        EdgeFadeHorizontalScroll(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          spacing: 8,
          children: [
            ChoiceChip(
              showCheckmark: false,
              avatar: const Icon(Icons.directions_bus_rounded, size: 16),
              label: const Text('Helyi járat használata'),
              selected: useLocalBus,
              onSelected: (_) {
                _save(useLocalBus: true);
                setState(() {});
                _fetchOptions();
              },
            ),
            ChoiceChip(
              showCheckmark: false,
              avatar: const Icon(Icons.directions_walk_rounded, size: 16),
              label: const Text('Gyaloglás'),
              selected: !useLocalBus,
              onSelected: (_) {
                _save(useLocalBus: false);
                setState(() {});
                _fetchOptions();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Menetrend szerinti indulások (${_isMorning ? "Reggel" : "Délután"})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface.withValues(alpha: 0.78),
                  ),
                ),
              ),
              if (_loadingOptions)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Járatok frissítése',
                  onPressed: _fetchOptions,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
            ],
          ),
        ),
        if (_scheduledOptions.isNotEmpty) ...[
          const SizedBox(height: 6),
          EdgeFadeHorizontalScroll(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            spacing: 6,
            children: [
              ChoiceChip(
                showCheckmark: false,
                label: const Text('Automatikus (legjobb)'),
                selected: selectedLine.isEmpty,
                onSelected: (_) {
                  _lineController.clear();
                  _save(line: '');
                  setState(() {});
                },
              ),
              for (final opt in _scheduledOptions)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(opt.label),
                  selected: selectedLine == opt.value ||
                      (selectedLine.isNotEmpty &&
                          opt.value.contains(selectedLine)),
                  onSelected: (_) {
                    _lineController.text = opt.value;
                    _save(line: opt.value);
                    setState(() {});
                  },
                ),
            ],
          ),
        ] else if (!_loadingOptions) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              widget.prefs.transitConfigured
                  ? 'Nincs lekérdezhető menetrendi indulás erre az időszakra, vagy add meg kézzel alább.'
                  : 'Állítsd be fent az otthoni és iskolai megállót a menetrendi indulások betöltéséhez.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11.5,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _lineController,
            decoration: InputDecoration(
              labelText:
                  '${_days[_selected]} (${_isMorning ? "Odafele" : "Hazafele"}): kiválasztott indulás / járat',
              hintText: 'pl. 07:09 S150',
              prefixIcon: const Icon(Icons.schedule_rounded, size: 18),
              suffixIcon: _lineController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _lineController.clear();
                        _save(line: '');
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (v) {
              _save(line: v.trim());
              setState(() {});
            },
          ),
        ),
      ],
    );
  }
}

/// Text field with live stop/station or street address search.
class _TransitStopSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool isAddressSearch;
  final ValueChanged<String> onSelected;
  final ValueChanged<TransitStopResult>? onSelectedResult;
  final VoidCallback onCleared;

  const _TransitStopSearchField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.isAddressSearch = false,
    required this.onSelected,
    this.onSelectedResult,
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
    _debounce = Timer(const Duration(milliseconds: 420), () async {
      setState(() {
        _searching = true;
        _error = null;
      });
      try {
        final res = widget.isAddressSearch
            ? await _service.searchAddresses(q)
            : await _service.searchStops(q);
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
                : (widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          widget.controller.clear();
                          setState(() {
                            _results = const [];
                            _error = null;
                          });
                          widget.onCleared();
                        },
                      )
                    : null),
          ),
        ),
        for (final r in _results)
          ListTile(
            dense: true,
            leading: Icon(
              widget.isAddressSearch
                  ? Icons.location_on_rounded
                  : Icons.directions_transit_rounded,
              size: 18,
            ),
            title: Text(
              r.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              widget.controller.text = r.name;
              setState(() => _results = const []);
              widget.onSelected(r.name);
              widget.onSelectedResult?.call(r);
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
