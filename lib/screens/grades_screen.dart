import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../widgets/frosted_inspection_modal.dart';

/// Represents a hypothetical ("ghost") grade added in the Szellemjegy Számoló.
class GhostGrade {
  final int value;
  final int weightPercentage;

  const GhostGrade({
    required this.value,
    this.weightPercentage = 100,
  });
}

/// Per-subject aggregated grade statistics and grade list.
class SubjectGradeSummary {
  final String subjectUid;
  final String subjectName;
  final String categoryDescription;
  final List<Grade> grades;
  final double? weightedAverage;
  final Grade latestGrade;

  const SubjectGradeSummary({
    required this.subjectUid,
    required this.subjectName,
    required this.categoryDescription,
    required this.grades,
    required this.weightedAverage,
    required this.latestGrade,
  });

  /// Computes a weighted average across real [grades] and optional [ghostGrades].
  static double? computeWeightedAverage(
    Iterable<Grade> grades, [
    Iterable<GhostGrade> ghostGrades = const [],
  ]) {
    double weightedSum = 0;
    double totalWeight = 0;
    for (final g in grades) {
      final val = g.numericValue;
      if (val == null || val < 1 || val > 5) continue;
      final weight =
          (g.weightPercentage != null && g.weightPercentage! > 0)
              ? g.weightPercentage!.toDouble()
              : 100.0;
      weightedSum += val * weight;
      totalWeight += weight;
    }
    for (final ghost in ghostGrades) {
      final w = ghost.weightPercentage > 0
          ? ghost.weightPercentage.toDouble()
          : 100.0;
      weightedSum += ghost.value * w;
      totalWeight += w;
    }
    if (totalWeight <= 0) return null;
    return weightedSum / totalWeight;
  }

  /// Calculates how many grades of [gradeValue] (at [weightPercentage]) are
  /// needed to reach [targetThreshold]. Returns 0 if already achieved, or null
  /// if mathematically impossible (e.g. gradeValue <= targetThreshold).
  static int? calculateNeededGradesCount({
    required Iterable<Grade> currentGrades,
    required Iterable<GhostGrade> ghostGrades,
    required double targetThreshold,
    required int gradeValue,
    int weightPercentage = 100,
  }) {
    double weightedSum = 0;
    double totalWeight = 0;
    for (final g in currentGrades) {
      final val = g.numericValue;
      if (val == null || val < 1 || val > 5) continue;
      final weight =
          (g.weightPercentage != null && g.weightPercentage! > 0)
              ? g.weightPercentage!.toDouble()
              : 100.0;
      weightedSum += val * weight;
      totalWeight += weight;
    }
    for (final ghost in ghostGrades) {
      final w = ghost.weightPercentage > 0
          ? ghost.weightPercentage.toDouble()
          : 100.0;
      weightedSum += ghost.value * w;
      totalWeight += w;
    }

    if (totalWeight > 0 && (weightedSum / totalWeight) >= targetThreshold) {
      return 0;
    }
    if (gradeValue <= targetThreshold) {
      return null;
    }

    final w = weightPercentage.toDouble();
    for (int count = 1; count <= 50; count++) {
      final simAvg = (weightedSum + count * gradeValue * w) /
          (totalWeight + count * w);
      if (simAvg >= targetThreshold) {
        return count;
      }
    }
    return null;
  }

  /// Groups all student grades by subject and sorts subjects alphabetically.
  static List<SubjectGradeSummary> groupBySubject(List<Grade> allGrades) {
    final map = <String, List<Grade>>{};
    for (final g in allGrades) {
      final key = g.subject.uid.isNotEmpty ? g.subject.uid : g.subject.name;
      map.putIfAbsent(key, () => <Grade>[]).add(g);
    }

    final summaries = <SubjectGradeSummary>[];
    for (final entry in map.entries) {
      final list = List<Grade>.from(entry.value)
        ..sort((a, b) {
          final cmp = b.recordDate.compareTo(a.recordDate);
          return cmp != 0 ? cmp : b.creationDate.compareTo(a.creationDate);
        });
      final first = list.first;
      summaries.add(
        SubjectGradeSummary(
          subjectUid: first.subject.uid,
          subjectName: first.subject.name,
          categoryDescription: first.subject.category.description,
          grades: list,
          weightedAverage: computeWeightedAverage(list),
          latestGrade: first,
        ),
      );
    }

    summaries.sort(
      (a, b) =>
          a.subjectName.toLowerCase().compareTo(b.subjectName.toLowerCase()),
    );
    return summaries;
  }
}

/// "Jegyek" tab: displays cumulative weighted average, interactive Overall
/// Szellemjegy Számoló (Ghost Grade Simulator), per-subject averages with
/// configurable rounding rules, and opens subject detail views on tap.
class GradesScreen extends StatefulWidget {
  final List<Grade> allGrades;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final Future<void> Function() onRefresh;

  const GradesScreen({
    super.key,
    required this.allGrades,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onRefresh,
  });

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  final List<GhostGrade> _overallGhostGrades = [];
  bool _showSimulatorPanel = false;
  int _selectedGhostWeight = 100;

  void _addOverallGhostGrade(int gradeValue) {
    setState(() {
      _overallGhostGrades.add(
        GhostGrade(
          value: gradeValue,
          weightPercentage: _selectedGhostWeight,
        ),
      );
    });
  }

  void _removeOverallGhostGrade(int index) {
    setState(() {
      _overallGhostGrades.removeAt(index);
    });
  }

  void _clearOverallGhostGrades() {
    setState(() => _overallGhostGrades.clear());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subjects = SubjectGradeSummary.groupBySubject(widget.allGrades);

    final baseOverallAvg =
        SubjectGradeSummary.computeWeightedAverage(widget.allGrades);
    final simulatedOverallAvg = SubjectGradeSummary.computeWeightedAverage(
      widget.allGrades,
      _overallGhostGrades,
    );
    final numericGradeCount =
        widget.allGrades.where((g) => g.numericValue != null).length;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            setState(() => _showSimulatorPanel = !_showSimulatorPanel),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        icon: Icon(
          _showSimulatorPanel
              ? Icons.expand_less_rounded
              : Icons.auto_fix_high_rounded,
        ),
        label: Text(
          _overallGhostGrades.isEmpty
              ? 'Szellemjegy számoló'
              : 'Szellemjegy (${_overallGhostGrades.length})',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _buildCumulativeAverageCard(
              theme,
              scheme,
              baseAverage: baseOverallAvg,
              simulatedAverage: simulatedOverallAvg,
              subjectCount: subjects.length,
              gradeCount: numericGradeCount,
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _buildOverallGhostSimulatorCard(
                  theme,
                  scheme,
                  baseAverage: baseOverallAvg,
                  simulatedAverage: simulatedOverallAvg,
                ),
              ),
              crossFadeState:
                  (_showSimulatorPanel || _overallGhostGrades.isNotEmpty)
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 240),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Icon(
                  Icons.star_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tantárgyak és kerekített átlagok',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    '${subjects.length} tantárgy',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (subjects.isEmpty)
              _buildEmptyCard(theme, scheme)
            else
              ...subjects.map(
                (subj) => _buildSubjectTile(context, theme, scheme, subj),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCumulativeAverageCard(
    ThemeData theme,
    ColorScheme scheme, {
    required double? baseAverage,
    required double? simulatedAverage,
    required int subjectCount,
    required int gradeCount,
  }) {
    final activeAvg =
        _overallGhostGrades.isNotEmpty ? simulatedAverage : baseAverage;
    final avgText = activeAvg != null ? activeAvg.toStringAsFixed(2) : '–';
    final avgColor = activeAvg != null
        ? OledTheme.averageColor(activeAvg, widget.prefs)
        : scheme.primary;
    final roundedGrade = activeAvg != null
        ? widget.prefs.roundingConfig.evaluateRoundedGrade(activeAvg)
        : null;

    final delta = (baseAverage != null &&
            simulatedAverage != null &&
            _overallGhostGrades.isNotEmpty)
        ? (simulatedAverage - baseAverage)
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.largeRadius,
        border: Border.all(
          color: avgColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 74,
            height: 74,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: avgColor,
              borderRadius: OledTheme.badgeRadius,
            ),
            child: Text(
              avgText,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _overallGhostGrades.isNotEmpty
                      ? 'Szimulált összesített átlag'
                      : 'Összesített súlyozott átlag',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (roundedGrade != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: avgColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          'Kerekítve: $roundedGrade-ös',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: avgColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    if (delta != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: delta >= 0
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.redAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(2)} (alap: ${baseAverage!.toStringAsFixed(2)})',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: delta >= 0
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '$gradeCount db érdemjegy • $subjectCount tantárgyból',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallGhostSimulatorCard(
    ThemeData theme,
    ColorScheme scheme, {
    required double? baseAverage,
    required double? simulatedAverage,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.largeRadius,
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.55),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_fix_high_rounded,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Szellemjegy Számoló (Összesített)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_overallGhostGrades.isNotEmpty)
                TextButton.icon(
                  onPressed: _clearOverallGhostGrades,
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Törlés'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Válassz súlyozást, majd koppints egy jegyre (1–5) a szimulációhoz:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Súly: $_selectedGhostWeight%',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              ...[50, 100, 200].map((w) {
                final selected = _selectedGhostWeight == w;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$w%'),
                    selected: selected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    onSelected: (_) =>
                        setState(() => _selectedGhostWeight = w),
                  ),
                );
              }),
            ],
          ),
          Slider(
            value: _selectedGhostWeight.toDouble(),
            min: 25,
            max: 300,
            divisions: 11,
            label: '$_selectedGhostWeight%',
            onChanged: (v) =>
                setState(() => _selectedGhostWeight = v.round()),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [1, 2, 3, 4, 5].map((val) {
              final color = OledTheme.gradeColor(val, widget.prefs);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _addOverallGhostGrade(val),
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        '+$val',
                        style: theme.textTheme.titleMedium?.copyWith(
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
          if (_overallGhostGrades.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_overallGhostGrades.length, (idx) {
                final g = _overallGhostGrades[idx];
                final color = OledTheme.gradeColor(g.value, widget.prefs);
                return InputChip(
                  backgroundColor: color.withValues(alpha: 0.22),
                  side: BorderSide(color: color),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  label: Text(
                    '${g.value} (${g.weightPercentage}%)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onDeleted: () => _removeOverallGhostGrade(idx),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCard(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.cardRadius,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(
            Icons.assignment_outlined,
            color: scheme.onSurface.withValues(alpha: 0.54),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Még nem található rögzített értékelés.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectTile(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    SubjectGradeSummary summary,
  ) {
    final latest = summary.latestGrade;
    final latestColor =
        OledTheme.gradeColor(latest.numericValue, widget.prefs);
    final latestBadgeText = latest.numericValue?.toString() ??
        latest.shortStrValue ??
        (latest.strValue.isNotEmpty ? latest.strValue.substring(0, 1) : '?');

    final avg = summary.weightedAverage;
    final avgText = avg != null ? avg.toStringAsFixed(2) : '–';
    final avgColor = avg != null
        ? OledTheme.averageColor(avg, widget.prefs)
        : scheme.onSurface.withValues(alpha: 0.54);
    final roundedStanding = avg != null
        ? widget.prefs.roundingConfig.evaluateRoundedGrade(avg)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: OledTheme.cardRadius,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubjectGradesDetailScreen(
                summary: summary,
                prefs: widget.prefs,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: OledTheme.cardRadius,
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.subjectName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: avgColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: avgColor.withValues(alpha: 0.65),
                            ),
                          ),
                          child: Text(
                            roundedStanding != null
                                ? 'Átlag: $avgText ($roundedStanding)'
                                : 'Átlag: $avgText',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${summary.grades.length} db jegy',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => showGradeInspectionModal(
                  context,
                  latest,
                  prefs: widget.prefs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Legutóbbi',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.54),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: latestColor,
                        borderRadius: OledTheme.badgeRadius,
                      ),
                      child: Text(
                        latestBadgeText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurface.withValues(alpha: 0.54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detailed view showing all grades for a single selected subject, plus the
/// Subject-level Szellemjegy Számoló & target average calculator.
class SubjectGradesDetailScreen extends StatefulWidget {
  final SubjectGradeSummary summary;
  final UserProfilePrefs prefs;

  const SubjectGradesDetailScreen({
    super.key,
    required this.summary,
    required this.prefs,
  });

  @override
  State<SubjectGradesDetailScreen> createState() =>
      _SubjectGradesDetailScreenState();
}

class _SubjectGradesDetailScreenState extends State<SubjectGradesDetailScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');
  final List<GhostGrade> _ghostGrades = [];
  int _selectedWeight = 100;
  int _targetGrade = 5;

  @override
  void initState() {
    super.initState();
    final avg = widget.summary.weightedAverage ?? 3.0;
    final currentRounded =
        widget.prefs.roundingConfig.evaluateRoundedGrade(avg);
    _targetGrade = (currentRounded < 5) ? (currentRounded + 1) : 5;
  }

  void _addGhost(int val) {
    setState(() {
      _ghostGrades.add(
        GhostGrade(value: val, weightPercentage: _selectedWeight),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final baseAvg = widget.summary.weightedAverage;
    final simAvg = SubjectGradeSummary.computeWeightedAverage(
      widget.summary.grades,
      _ghostGrades,
    );
    final activeAvg = _ghostGrades.isNotEmpty ? simAvg : baseAvg;
    final avgText = activeAvg != null ? activeAvg.toStringAsFixed(2) : '–';
    final avgColor = activeAvg != null
        ? OledTheme.averageColor(activeAvg, widget.prefs)
        : scheme.primary;
    final roundedStanding = activeAvg != null
        ? widget.prefs.roundingConfig.evaluateRoundedGrade(activeAvg)
        : null;

    final targetThreshold =
        widget.prefs.roundingConfig.thresholdForGrade(_targetGrade);
    final needed5Count100 = SubjectGradeSummary.calculateNeededGradesCount(
      currentGrades: widget.summary.grades,
      ghostGrades: _ghostGrades,
      targetThreshold: targetThreshold,
      gradeValue: 5,
      weightPercentage: 100,
    );
    final needed5Count200 = SubjectGradeSummary.calculateNeededGradesCount(
      currentGrades: widget.summary.grades,
      ghostGrades: _ghostGrades,
      targetThreshold: targetThreshold,
      gradeValue: 5,
      weightPercentage: 200,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.summary.subjectName),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: OledTheme.largeRadius,
              border: Border.all(
                color: avgColor.withValues(alpha: 0.6),
                width: 1.4,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: avgColor,
                    borderRadius: OledTheme.badgeRadius,
                  ),
                  child: Text(
                    avgText,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.summary.subjectName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        roundedStanding != null
                            ? 'Kerekített jegy: $roundedStanding (${widget.summary.grades.length} db jegy)'
                            : '${widget.summary.grades.length} rögzített értékelés',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                      if (_ghostGrades.isNotEmpty && baseAvg != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Eredeti átlag: ${baseAvg.toStringAsFixed(2)} • +${_ghostGrades.length} szellemjegy',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSubjectSimulatorCard(
            theme,
            scheme,
            targetThreshold: targetThreshold,
            needed5Count100: needed5Count100,
            needed5Count200: needed5Count200,
          ),
          const SizedBox(height: 20),
          Text(
            'Rögzített jegyek (koppints a részletekért)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...widget.summary.grades.map(
            (grade) => _buildGradeDetailCard(context, theme, scheme, grade),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectSimulatorCard(
    ThemeData theme,
    ColorScheme scheme, {
    required double targetThreshold,
    required int? needed5Count100,
    required int? needed5Count200,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(
                Icons.auto_fix_high_rounded,
                size: 19,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Szellemjegy & Célátlag kalkulátor',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_ghostGrades.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _ghostGrades.clear()),
                  child: const Text('Alaphelyzet'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Cél érdemjegy:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(width: 10),
              ...[2, 3, 4, 5].map((g) {
                final selected = _targetGrade == g;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$g-ös'),
                    selected: selected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    onSelected: (_) => setState(() => _targetGrade = g),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              needed5Count100 == 0
                  ? 'Elérted a(z) $_targetGrade-ös szintet (küszöb: ${targetThreshold.toStringAsFixed(2)})!'
                  : needed5Count100 != null
                      ? 'A(z) $_targetGrade-ös eléréséhez (${targetThreshold.toStringAsFixed(2)}) még $needed5Count100 db 100%-os 5-ös (vagy ${needed5Count200 ?? needed5Count100} db 200%-os 5-ös) szükséges.'
                      : 'Adj hozzá szellemjegyeket alább a szimulációhoz.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: needed5Count100 == 0
                    ? Colors.greenAccent
                    : scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Súly: $_selectedWeight%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              ...[50, 100, 200].map((w) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$w%'),
                    selected: _selectedWeight == w,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    onSelected: (_) => setState(() => _selectedWeight = w),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [1, 2, 3, 4, 5].map((val) {
              final color = OledTheme.gradeColor(val, widget.prefs);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => _addGhost(val),
                    child: Container(
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        '+$val',
                        style: theme.textTheme.titleMedium?.copyWith(
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
          if (_ghostGrades.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_ghostGrades.length, (idx) {
                final g = _ghostGrades[idx];
                final color = OledTheme.gradeColor(g.value, widget.prefs);
                return InputChip(
                  backgroundColor: color.withValues(alpha: 0.22),
                  side: BorderSide(color: color),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  label: Text('${g.value} (${g.weightPercentage}%)'),
                  onDeleted: () => setState(() => _ghostGrades.removeAt(idx)),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGradeDetailCard(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    Grade grade,
  ) {
    final badgeColor = OledTheme.gradeColor(grade.numericValue, widget.prefs);
    final badgeText = grade.numericValue?.toString() ??
        grade.shortStrValue ??
        (grade.strValue.isNotEmpty ? grade.strValue.substring(0, 1) : '?');

    final weightText = grade.weightPercentage != null
        ? '${grade.weightPercentage}%'
        : '100%';
    final modeText = grade.mode?.description;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: OledTheme.cardRadius,
        onTap: () =>
            showGradeInspectionModal(context, grade, prefs: widget.prefs),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: OledTheme.cardRadius,
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: OledTheme.badgeRadius,
                ),
                child: Text(
                  badgeText,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${grade.strValue} ($weightText)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          _dateFormat.format(grade.recordDate),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        grade.type.description,
                        if (modeText != null && modeText.isNotEmpty) modeText,
                      ].join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (grade.topic != null &&
                        grade.topic!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Téma: ${grade.topic}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 14,
                          color: scheme.onSurface.withValues(alpha: 0.54),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            grade.teacher,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
