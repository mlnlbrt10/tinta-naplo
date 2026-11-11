import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import 'about_app_screen.dart';

/// "Több" tab: Dedicated 'Testreszabás' (Personalization) settings hub,
/// Grade Colors Customizer, Rounding Rule Configurator, and Account summary.
class MoreScreen extends StatefulWidget {
  final StoredSession session;
  final Student? student;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onLogout;

  const MoreScreen({
    super.key,
    required this.session,
    required this.student,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onLogout,
  });

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  int _selectedGradeToCustomize = 5;

  void _setThemeStyle(AppThemeStyle style) {
    widget.onPrefsChanged(widget.prefs.copyWith(themeStyle: style));
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
          title: Text('$grade-ös jegy egyedi HEX színe'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expFormat = DateFormat('yyyy. MM. dd. HH:mm');
    final rounding = widget.prefs.roundingConfig;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
      children: [
        _buildSectionCard(
          theme,
          scheme,
          icon: Icons.palette_rounded,
          title: 'Testreszabás — Téma és Színvilág',
          children: [
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
                    selected:
                        widget.prefs.themeStyle == AppThemeStyle.oledPureBlack,
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
            const SizedBox(height: 16),
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
              'Vagy válassz egyedi Material 3 alapszínt:',
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
                        color:
                            selected ? scheme.onSurface : Colors.transparent,
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
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          theme,
          scheme,
          icon: Icons.color_lens_rounded,
          title: 'Érdemjegyek Színeinek Testreszabása',
          trailing: TextButton(
            onPressed: _resetGradeColors,
            child: const Text('Alapértelmezett'),
          ),
          children: [
            Text(
              'Koppints egy érdemjegyre (1–5), majd válassz színt vagy adj meg HEX kódot:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        _buildSectionCard(
          theme,
          scheme,
          icon: Icons.tune_rounded,
          title: 'Kerekítési Határok (Átlag küszöbök)',
          trailing: TextButton(
            onPressed: () => _updateRounding(const GradeRoundingConfig()),
            child: const Text('Alaphelyzet'),
          ),
          children: [
            Text(
              'Állítsd be, milyen tanulmányi átlagtól kerekítsen felfelé a rendszer:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 10),
            _buildThresholdSlider(
              theme: theme,
              scheme: scheme,
              gradeLabel: '5-ös (Jeles) határ',
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
              gradeLabel: '4-es (Jó) határ',
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
              gradeLabel: '3-as (Közepes) határ',
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
              gradeLabel: '2-es (Elégséges) határ',
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
        const SizedBox(height: 16),
        _buildSectionCard(
          theme,
          scheme,
          icon: Icons.manage_accounts_rounded,
          title: 'Fiók és munkamenet',
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
            _buildRow(scheme, 'Intézménykód (iss)', widget.session.instituteCode),
            if (widget.student != null)
              _buildRow(scheme, 'Intézmény', widget.student!.instituteName),
            _buildRow(
              scheme,
              'Token lejárat',
              expFormat.format(widget.session.expiresAt.toLocal()),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.prefs.developerModeUnlocked) ...[
          _buildSectionCard(
            theme,
            scheme,
            icon: Icons.terminal_rounded,
            title: uwu('Fejlesztői beállítások'),
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: OledTheme.uwuPastelPink,
                title: Text(
                  widget.prefs.uwuModeEnabled
                      ? 'UwU / Kawaii mód aktív nya~ :3'
                      : 'UwU / Kawaii mód',
                  style: const TextStyle(
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
            ],
          ),
          const SizedBox(height: 16),
        ],
        _buildSectionCard(
          theme,
          scheme,
          icon: Icons.info_outline_rounded,
          title: uwu('Rendszer / Névjegy'),
          children: [
            _buildRow(scheme, uwu('Alkalmazás'), uwu('reKRETA • Naprakész (v1.0.1)')),
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
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC62828),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: OledTheme.cardRadius,
            ),
          ),
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout_rounded),
          label: Text(
            uwu('Kijelentkezés és munkamenet törlése'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
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

  Widget _buildSectionCard(
    ThemeData theme,
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.largeRadius,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
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
