import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/app_providers.dart';
import '../services/kreta_notification_service.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/glass_card.dart';
import '../widgets/tinta_toast.dart';

/// Dedicated Notifications (`Értesítések`) settings screen allowing per-category
/// toggling, background sync interval selection, live preview, test alerts, and
/// full customization of title & body templates with dynamic placeholders.
class NotificationsSettingsScreen extends StatefulWidget {
  final UserProfilePrefs prefs;
  final KretaNotificationService? notificationService;

  const NotificationsSettingsScreen({
    super.key,
    required this.prefs,
    this.notificationService,
  });

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  KretaNotificationService get _service =>
      widget.notificationService ?? KretaNotificationService.instance;

  KretaNotificationConfig _config = KretaNotificationConfig.defaults();
  bool _loading = true;
  bool _hasPermission = true;

  final Map<KretaNotificationCategory, TextEditingController>
      _titleControllers = {};
  final Map<KretaNotificationCategory, TextEditingController> _bodyControllers =
      {};
  final Map<KretaNotificationCategory, FocusNode> _titleFocusNodes = {};
  final Map<KretaNotificationCategory, FocusNode> _bodyFocusNodes = {};
  final Map<KretaNotificationCategory, bool> _lastFocusedIsTitle = {};
  int? _selectedGradeTab;
  String _previewSubject = 'Történelem';

  static const List<String> _previewSubjects = [
    'Történelem',
    'Matematika',
    'Fizika',
    'Testnevelés',
    'Hálózatok I.',
  ];

  static List<String> _presetsForGrade(int grade) {
    switch (grade) {
      case 1:
        return const ['bad boy', 'karó', 'bukó', 'ez nem jött össze', 'cooked vagyok'];
      case 2:
        return const ['kettes', 'épphogy', 'meglett', 'főztem'];
      case 3:
        return const ['hármas', 'közepes', 'elmegy', 'szép volt'];
      case 4:
        return const ['négyes', 'profi', 'ügyes', 'főztem'];
      case 5:
      default:
        return const ['király', 'ötös', 'clutch', 'zseni', 'csillagos ötös', 'gg ez'];
    }
  }

  static IconData _iconForToken(String token) {
    switch (token) {
      case '{subject}':
        return Icons.menu_book_rounded;
      case '{grade}':
        return Icons.grade_rounded;
      case '{weight}':
        return Icons.scale_rounded;
      case '{teacher}':
      case '{sender}':
        return Icons.person_rounded;
      case '{substitute_teacher}':
        return Icons.swap_horiz_rounded;
      case '{room}':
        return Icons.meeting_room_rounded;
      case '{date}':
        return Icons.calendar_today_rounded;
      case '{lesson_number}':
        return Icons.format_list_numbered_rounded;
      case '{minutes}':
        return Icons.timer_rounded;
      case '{excused_status}':
        return Icons.verified_user_rounded;
      case '{topic}':
      case '{type}':
      case '{title}':
        return Icons.label_outline_rounded;
      case '{preview}':
        return Icons.short_text_rounded;
      default:
        return Icons.add_circle_outline_rounded;
    }
  }

  @override
  void initState() {
    super.initState();
    for (final cat in KretaNotificationCategory.values) {
      final def = NotificationCategoryConfig.defaultsFor(cat);
      _titleControllers[cat] = TextEditingController(text: def.titleTemplate);
      _bodyControllers[cat] = TextEditingController(text: def.bodyTemplate);
      final titleNode = FocusNode();
      final bodyNode = FocusNode();
      titleNode.addListener(() {
        if (titleNode.hasFocus) _lastFocusedIsTitle[cat] = true;
      });
      bodyNode.addListener(() {
        if (bodyNode.hasFocus) _lastFocusedIsTitle[cat] = false;
      });
      _titleFocusNodes[cat] = titleNode;
      _bodyFocusNodes[cat] = bodyNode;
      _lastFocusedIsTitle[cat] = false;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    final loaded = await _service.loadConfig();
    final perm = await _service.hasNotificationPermissions();
    if (!mounted) return;
    setState(() {
      _config = loaded;
      _hasPermission = perm;
      _loading = false;
      for (final cat in KretaNotificationCategory.values) {
        final cfg = loaded.forCategory(cat);
        if (cat == KretaNotificationCategory.newGrade &&
            _selectedGradeTab != null) {
          final tpl = cfg.gradeTemplates[_selectedGradeTab!];
          _titleControllers[cat]!.text = tpl?.titleTemplate ?? '';
          _bodyControllers[cat]!.text = tpl?.bodyTemplate ?? '';
        } else {
          _titleControllers[cat]!.text = cfg.titleTemplate;
          _bodyControllers[cat]!.text = cfg.bodyTemplate;
        }
      }
    });
  }

  void _selectGradeTab(int? grade) {
    if (_selectedGradeTab == grade) return;
    HapticFeedback.selectionClick();
    final cfg = _config.forCategory(KretaNotificationCategory.newGrade);
    setState(() {
      _selectedGradeTab = grade;
      if (grade == null) {
        _titleControllers[KretaNotificationCategory.newGrade]!.text =
            cfg.titleTemplate;
        _bodyControllers[KretaNotificationCategory.newGrade]!.text =
            cfg.bodyTemplate;
      } else {
        final tpl = cfg.gradeTemplates[grade];
        _titleControllers[KretaNotificationCategory.newGrade]!.text =
            tpl?.titleTemplate ?? '';
        _bodyControllers[KretaNotificationCategory.newGrade]!.text =
            tpl?.bodyTemplate ?? '';
      }
    });
  }

  @override
  void dispose() {
    for (final c in _titleControllers.values) {
      c.dispose();
    }
    for (final c in _bodyControllers.values) {
      c.dispose();
    }
    for (final f in _titleFocusNodes.values) {
      f.dispose();
    }
    for (final f in _bodyFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _commitConfig(KretaNotificationConfig next) {
    setState(() => _config = next);
    unawaited(_service.saveConfig(next));
  }

  void _updateTemplateField(
    KretaNotificationCategory category, {
    required bool isTitle,
    required String value,
  }) {
    final currentCatCfg = _config.forCategory(category);
    if (category == KretaNotificationCategory.newGrade &&
        _selectedGradeTab != null) {
      final existing = currentCatCfg.gradeTemplates[_selectedGradeTab!] ??
          const GradeNotificationTemplate();
      final updatedTpl = isTitle
          ? existing.copyWith(titleTemplate: value)
          : existing.copyWith(bodyTemplate: value);
      _commitConfig(
        _config.withCategory(
          category,
          currentCatCfg.withGradeTemplate(_selectedGradeTab!, updatedTpl),
        ),
      );
      return;
    }
    _commitConfig(
      _config.withCategory(
        category,
        isTitle
            ? currentCatCfg.copyWith(titleTemplate: value)
            : currentCatCfg.copyWith(bodyTemplate: value),
      ),
    );
  }

  void _insertPlaceholder(
    KretaNotificationCategory category,
    String token,
  ) {
    HapticFeedback.selectionClick();
    final useTitle = _lastFocusedIsTitle[category] == true;
    final ctrl =
        useTitle ? _titleControllers[category]! : _bodyControllers[category]!;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final start =
        sel.isValid && sel.start >= 0 && sel.start <= text.length
            ? sel.start
            : text.length;
    final end =
        sel.isValid && sel.end >= start && sel.end <= text.length
            ? sel.end
            : start;
    final needsLeadingSpace =
        start > 0 && text[start - 1] != ' ' && text[start - 1] != ':';
    final inserted = needsLeadingSpace ? ' $token' : token;
    final nextText = text.replaceRange(start, end, inserted);
    ctrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
    _updateTemplateField(category, isTitle: useTitle, value: nextText);
  }

  void _resetCategoryToDefault(KretaNotificationCategory category) {
    HapticFeedback.lightImpact();
    if (category == KretaNotificationCategory.newGrade &&
        _selectedGradeTab != null) {
      final grade = _selectedGradeTab!;
      final current = _config.forCategory(category);
      _titleControllers[category]!.text = '';
      _bodyControllers[category]!.text = '';
      _commitConfig(
        _config.withCategory(
          category,
          current.withGradeTemplate(grade, const GradeNotificationTemplate()),
        ),
      );
      TintaToast.info(
        context,
        uwu('$grade-ös jegy értesítése visszaállítva alapértelmezettre'),
      );
      return;
    }
    final defaults = NotificationCategoryConfig.defaultsFor(category);
    _titleControllers[category]!.text = defaults.titleTemplate;
    _bodyControllers[category]!.text = defaults.bodyTemplate;
    _commitConfig(_config.withCategory(category, defaults));
    TintaToast.info(
      context,
      uwu('${category.label} sablon visszaállítva alapértelmezettre'),
    );
  }

  void _resetAllToDefaults() {
    HapticFeedback.mediumImpact();
    final defaults = KretaNotificationConfig.defaults();
    setState(() => _selectedGradeTab = null);
    for (final cat in KretaNotificationCategory.values) {
      final cfg = defaults.forCategory(cat);
      _titleControllers[cat]!.text = cfg.titleTemplate;
      _bodyControllers[cat]!.text = cfg.bodyTemplate;
    }
    _commitConfig(defaults);
    TintaToast.success(context, uwu('Minden értesítési sablon alaphelyzetben'));
  }

  Future<void> _sendTest(KretaNotificationCategory category) async {
    HapticFeedback.lightImpact();
    final triggered = await _service.sendTestNotification(
      category,
      configOverride: _config,
      gradeValue: category == KretaNotificationCategory.newGrade
          ? _selectedGradeTab
          : null,
    );
    final granted = await _service.hasNotificationPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = granted);
    TintaToast.success(
      context,
      uwu('Teszt értesítés elküldve: ${triggered.title}'),
    );
  }

  Future<void> _requestPermission() async {
    HapticFeedback.selectionClick();
    final granted = await _service.requestNotificationPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = granted);
    if (granted) {
      TintaToast.success(context, uwu('Értesítési engedély megadva'));
    } else {
      TintaToast.error(
        context,
        uwu('Engedélyezd az értesítéseket a rendszerbeállításokban!'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final uwuOn = activePrefs.uwuModeEnabled;

    return AdaptiveBackgroundScaffold(
      prefs: activePrefs,
      appBar: buildAdaptiveTransparentAppBar(
        context,
        title: uwu('Értesítések', enabled: uwuOn),
        actions: [
          TextButton.icon(
            key: const ValueKey<String>('notifications-reset-all-btn'),
            onPressed: _resetAllToDefaults,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(uwuLabel('Alaphelyzet', enabled: uwuOn)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.only(top: adaptiveAppBarTopPadding(context)),
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                children: [
                if (!_hasPermission) ...[
                  SoftGlassCard(
                    prefs: activePrefs,
                    padding: const EdgeInsets.all(14),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_off_rounded,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            uwu(
                              'Az értesítések megjelenítéséhez Android értesítési engedély szükséges.',
                              enabled: uwuOn,
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _requestPermission,
                          child: Text(uwuLabel('Engedély', enabled: uwuOn)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SoftGlassCard(
                  prefs: activePrefs,
                  padding: const EdgeInsets.all(16),
                  borderRadius: OledTheme.largeRadius,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile.adaptive(
                        key: const ValueKey<String>('notifications-master-switch'),
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(
                          Icons.notifications_active_rounded,
                          color: _config.masterEnabled
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: 0.5),
                        ),
                        title: Text(
                          uwuLabel(
                            'Azonnali & háttér értesítések',
                            enabled: uwuOn,
                          ),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          uwuLabel(
                            'Új jegyek, számonkérések, óraváltozások, késések, hiányzások és üzenetek figyelése.',
                            enabled: uwuOn,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.68),
                          ),
                        ),
                        value: _config.masterEnabled,
                        onChanged: (val) async {
                          HapticFeedback.selectionClick();
                          if (val && !_hasPermission) {
                            await _requestPermission();
                          }
                          _commitConfig(_config.copyWith(masterEnabled: val));
                        },
                      ),
                      const Divider(height: 20),
                      Text(
                        uwuLabel(
                          'Háttér szinkronizálási gyakoriság',
                          enabled: uwuOn,
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [15, 30, 60].map((mins) {
                          final selected =
                              _config.backgroundIntervalMinutes == mins;
                          return ChoiceChip(
                            label: Text('$mins perc'),
                            selected: selected,
                            onSelected: _config.masterEnabled
                                ? (_) {
                                    HapticFeedback.selectionClick();
                                    _commitConfig(
                                      _config.copyWith(
                                        backgroundIntervalMinutes: mins,
                                      ),
                                    );
                                  }
                                : null,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const ValueKey<String>(
                          'notifications-global-test-btn',
                        ),
                        onPressed: () =>
                            _sendTest(KretaNotificationCategory.newGrade),
                        icon: const Icon(Icons.send_rounded, size: 17),
                        label: Text(
                          uwuLabel(
                            'Teszt értesítés küldése',
                            enabled: uwuOn,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final cat in KretaNotificationCategory.values) ...[
                  _buildCategoryCard(
                    context,
                    theme,
                    scheme,
                    activePrefs,
                    cat,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
            ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    UserProfilePrefs activePrefs,
    KretaNotificationCategory category,
  ) {
    final uwuOn = activePrefs.uwuModeEnabled;
    final catConfig = _config.forCategory(category);
    final isNewGrade = category == KretaNotificationCategory.newGrade;
    final selectedGrade = isNewGrade ? _selectedGradeTab : null;
    final previewGrade = selectedGrade ?? 5;
    final accent = isNewGrade && selectedGrade != null
        ? OledTheme.gradeColor(selectedGrade, activePrefs)
        : OledTheme.semanticForeground(
            category.accentColor,
            theme.brightness,
          );
    final baseSample = KretaNotificationService.sampleValuesFor(
      category,
      gradeValue: isNewGrade ? previewGrade : null,
    );
    final sample = Map<String, String>.from(baseSample)
      ..['{subject}'] = _previewSubject;
    final renderedPreview = KretaNotificationService.renderSmartNotification(
      category: category,
      titleTemplate: catConfig.titleTemplateForGrade(selectedGrade),
      bodyTemplate: catConfig.bodyTemplateForGrade(selectedGrade),
      values: sample,
      subjectName: _previewSubject,
      gradeValue: isNewGrade ? previewGrade : null,
    );
    final previewTitle = renderedPreview.title;
    final previewBody = renderedPreview.body;
    final isTargetTitle = _lastFocusedIsTitle[category] == true;

    return SoftGlassCard(
      key: ValueKey<String>('notification-category-${category.keyName}'),
      prefs: activePrefs,
      padding: const EdgeInsets.all(16),
      borderRadius: OledTheme.largeRadius,
      border: Border.all(
        color: catConfig.enabled && _config.masterEnabled
            ? accent.withValues(alpha: 0.45)
            : theme.dividerColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(category.icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uwuLabel(category.label, enabled: uwuOn),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      uwuLabel(category.subtitle, enabled: uwuOn),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                key: ValueKey<String>(
                  'notification-toggle-${category.keyName}',
                ),
                value: catConfig.enabled,
                onChanged: (val) {
                  HapticFeedback.selectionClick();
                  _commitConfig(
                    _config.withCategory(
                      category,
                      catConfig.copyWith(enabled: val),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Live Notification Preview Card at the top of the editor
          Container(
            key: ValueKey<String>('notification-preview-${category.keyName}'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(category.icon, size: 11, color: accent),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      uwuLabel('Tinta Napló • most • Élő előnézet', enabled: uwuOn),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                      ),
                    ),
                    const Spacer(),
                    if (isNewGrade)
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: OledTheme.gradeColor(previewGrade, activePrefs)
                              .withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: OledTheme.gradeColor(previewGrade, activePrefs)
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        child: Text(
                          '$previewGrade',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: OledTheme.gradeColor(
                              previewGrade,
                              activePrefs,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  previewTitle.isEmpty ? category.label : previewTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                if (previewBody.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    previewBody,
                    key: ValueKey<String>(
                      'notification-preview-body-${category.keyName}',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.86),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (isNewGrade || category == KretaNotificationCategory.newExam) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text(
                          uwuLabel('Minta tárgy:', enabled: uwuOn),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface.withValues(alpha: 0.56),
                          ),
                        ),
                        const SizedBox(width: 6),
                        for (final subj in _previewSubjects)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              key: ValueKey<String>(
                                'notification-preview-subject-${category.keyName}-$subj',
                              ),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _previewSubject = subj);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _previewSubject == subj
                                      ? accent.withValues(alpha: 0.22)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _previewSubject == subj
                                        ? accent
                                        : theme.dividerColor,
                                  ),
                                ),
                                child: Text(
                                  subj,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: _previewSubject == subj
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: _previewSubject == subj
                                        ? accent
                                        : scheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isNewGrade) ...[
            const SizedBox(height: 12),
            Text(
              uwuLabel(
                'Személyre szabás érdemjegyenként (1–5):',
                enabled: uwuOn,
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.68),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    key: const ValueKey<String>('notification-grade-tab-default'),
                    label: Text(
                      uwuLabel('Alapértelmezett', enabled: uwuOn),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    selected: _selectedGradeTab == null,
                    onSelected: (_) => _selectGradeTab(null),
                  ),
                  const SizedBox(width: 6),
                  for (final g in const [5, 4, 3, 2, 1]) ...[
                    Builder(
                      builder: (_) {
                        final gColor = OledTheme.gradeColor(g, activePrefs);
                        final isSel = _selectedGradeTab == g;
                        final hasCustom = catConfig.hasCustomGradeTemplate(g);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            key: ValueKey<String>('notification-grade-tab-$g'),
                            selected: isSel,
                            selectedColor: gColor.withValues(alpha: 0.22),
                            side: BorderSide(
                              color: isSel
                                  ? gColor
                                  : (hasCustom
                                      ? gColor.withValues(alpha: 0.55)
                                      : theme.dividerColor),
                            ),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$g',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: isSel ? gColor : scheme.onSurface,
                                  ),
                                ),
                                if (hasCustom) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: gColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            onSelected: (_) => _selectGradeTab(g),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            key: ValueKey<String>('notification-title-${category.keyName}'),
            controller: _titleControllers[category],
            focusNode: _titleFocusNodes[category],
            decoration: InputDecoration(
              labelText: uwuLabel(
                selectedGrade != null
                    ? 'Fejléc / Cím ($selectedGrade-es jegynél)'
                    : 'Fejléc / Cím',
                enabled: uwuOn,
              ),
              hintText: selectedGrade != null
                  ? 'Üresen: ${catConfig.titleTemplate}'
                  : 'pl. Új jegy érkezett',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (val) =>
                _updateTemplateField(category, isTitle: true, value: val),
          ),
          const SizedBox(height: 10),
          TextField(
            key: ValueKey<String>('notification-body-${category.keyName}'),
            controller: _bodyControllers[category],
            focusNode: _bodyFocusNodes[category],
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              labelText: uwuLabel(
                isNewGrade
                    ? (selectedGrade != null
                        ? 'Jegy neve / Megnevezés ($selectedGrade-es jegyhez)'
                        : 'Jegy neve / Megnevezés')
                    : 'Üzenet / Megnevezés',
                enabled: uwuOn,
              ),
              hintText: isNewGrade
                  ? (previewGrade <= 2
                      ? 'pl. bad boy, karó, bukó, ez nem jött össze...'
                      : 'pl. király, ötös, clutch, zseni, főztem...')
                  : 'pl. dolgozat lesz, teremcsere...',
              helperText: isNewGrade
                  ? uwuLabel(
                      'Írj egy szót vagy kifejezést — a ragozást és a mondatot automatikusan felépítjük.',
                      enabled: uwuOn,
                    )
                  : null,
              helperMaxLines: 2,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (val) =>
                _updateTemplateField(category, isTitle: false, value: val),
          ),
          const SizedBox(height: 10),
          if (isNewGrade) ...[
            Text(
              uwuLabel(
                'Gyors ötletek ($previewGrade-es jegyhez):',
                enabled: uwuOn,
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.68),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _presetsForGrade(previewGrade).map((preset) {
                  final active =
                      _bodyControllers[category]?.text.trim().toLowerCase() ==
                          preset;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      key: ValueKey<String>(
                        'notification-preset-${category.keyName}-$preset',
                      ),
                      backgroundColor: active
                          ? accent.withValues(alpha: 0.18)
                          : null,
                      side: BorderSide(
                        color: active ? accent : theme.dividerColor,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      label: Text(
                        preset,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: active ? accent : scheme.onSurface,
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        final ctrl = _bodyControllers[category];
                        if (ctrl != null) {
                          ctrl.text = preset;
                          ctrl.selection = TextSelection.collapsed(
                            offset: preset.length,
                          );
                        }
                        _updateTemplateField(
                          category,
                          isTitle: false,
                          value: preset,
                        );
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    uwuLabel(
                      'Adat beszúrása a kurzorhoz:',
                      enabled: uwuOn,
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.68),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _lastFocusedIsTitle[category] = !isTargetTitle;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      uwuLabel(
                        isTargetTitle ? 'Cél: Cím ▾' : 'Cél: Szöveg ▾',
                        enabled: uwuOn,
                      ),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: category.recommendedPlaceholderTokens.map((token) {
                final spec = kNotificationPlaceholders.firstWhere(
                  (p) => p.token == token,
                  orElse: () => NotificationPlaceholderSpec(token, token),
                );
                return ActionChip(
                  key: ValueKey<String>(
                    'notification-chip-${category.keyName}-${spec.token}',
                  ),
                  avatar: Icon(
                    _iconForToken(spec.token),
                    size: 14,
                    color: accent,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(
                    uwuLabel(spec.label, enabled: uwuOn),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () => _insertPlaceholder(category, spec.token),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: ValueKey<String>(
                    'notification-test-${category.keyName}',
                  ),
                  onPressed: () => _sendTest(category),
                  icon: const Icon(Icons.notifications_none_rounded, size: 16),
                  label: Text(uwuLabel('Teszt', enabled: uwuOn)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  key: ValueKey<String>(
                    'notification-reset-${category.keyName}',
                  ),
                  onPressed: () => _resetCategoryToDefault(category),
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: Text(uwuLabel('Alaphelyzet', enabled: uwuOn)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
