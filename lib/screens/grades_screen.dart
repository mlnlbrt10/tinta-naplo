import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_providers.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/edge_fade_horizontal_scroll.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';

/// SharedPreferences key storing the persisted Jegyek subject sort mode.
const String kGradesSelectedSortModeKey = 'grades_selected_sort_mode';

/// Sorting modes for the Jegyek subject list.
enum SubjectSortMode {
  alphabetical('A–Z', Icons.sort_by_alpha_rounded),
  averageAsc('Átlag ↑ (Javítandó)', Icons.trending_down_rounded),
  averageDesc('Átlag ↓ (Legjobb)', Icons.trending_up_rounded);

  final String label;
  final IconData icon;
  const SubjectSortMode(this.label, this.icon);

  static SubjectSortMode fromStorageKey(String? key) {
    if (key == null || key.isEmpty) return SubjectSortMode.alphabetical;
    return SubjectSortMode.values.firstWhere(
      (mode) => mode.name == key,
      orElse: () => SubjectSortMode.alphabetical,
    );
  }
}

/// Vocational Scholarship Tier definition (`Szakképzési ösztöndíj sáv`).
class ScholarshipTier {
  final String rangeLabel;
  final double minAverage;
  final double maxAverage;
  final String title;
  final String shortTitle;
  final String monthlyAmountLabel;
  final int estimatedMonthlyForint;
  final int percent;

  const ScholarshipTier({
    required this.rangeLabel,
    required this.minAverage,
    required this.maxAverage,
    required this.title,
    required this.shortTitle,
    required this.monthlyAmountLabel,
    required this.estimatedMonthlyForint,
    required this.percent,
  });

  /// Official Hungarian vocational scholarship (szakképzési ösztöndíj) tiers
  /// for szakirányú oktatás (11. évfolyamtól).
  static const List<ScholarshipTier> tiers = [
    ScholarshipTier(
      rangeLabel: '2,00 – 2,99',
      minAverage: 2.00,
      maxAverage: 2.99,
      title: '8 000 Ft / hó',
      shortTitle: '2,00 – 2,99 sáv',
      monthlyAmountLabel: '8 000 Ft / hó',
      estimatedMonthlyForint: 8000,
      percent: 8,
    ),
    ScholarshipTier(
      rangeLabel: '3,00 – 3,99',
      minAverage: 3.00,
      maxAverage: 3.99,
      title: '25 000 Ft / hó',
      shortTitle: '3,00 – 3,99 sáv',
      monthlyAmountLabel: '25 000 Ft / hó',
      estimatedMonthlyForint: 25000,
      percent: 25,
    ),
    ScholarshipTier(
      rangeLabel: '4,00 – 4,49',
      minAverage: 4.00,
      maxAverage: 4.49,
      title: '42 000 Ft / hó',
      shortTitle: '4,00 – 4,49 sáv',
      monthlyAmountLabel: '42 000 Ft / hó',
      estimatedMonthlyForint: 42000,
      percent: 42,
    ),
    ScholarshipTier(
      rangeLabel: '4,50 – 5,00',
      minAverage: 4.50,
      maxAverage: 5.00,
      title: '59 000 Ft / hó',
      shortTitle: '4,50 – 5,00 sáv',
      monthlyAmountLabel: '59 000 Ft / hó',
      estimatedMonthlyForint: 59000,
      percent: 59,
    ),
  ];

  /// Fixed monthly payout during ágazati alapoktatás (9–10. évf.):
  /// Technikum 8 000 Ft / hó, Szakképző 16 000 Ft / hó.
  static int basicEducationMonthlyForint(String schoolType) =>
      schoolType == 'szakkepzo' ? 16000 : 8000;

  static String formatForint(int amount) {
    final s = amount.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static int? currentTierIndex(double? average) {
    if (average == null || average < 2.00) return null;
    if (average >= 4.50) return 3;
    if (average >= 4.00) return 2;
    if (average >= 3.00) return 1;
    return 0;
  }

  static String estimatePercentileBadge(double? average) {
    if (average == null) {
      return 'Még nincs elég adat a rangsoroláshoz';
    }
    if (average >= 4.75) {
      return 'A tanulók felső 5%-ában vagy!';
    }
    if (average >= 4.50) {
      return 'A tanulók felső 10%-ában vagy!';
    }
    if (average >= 4.15) {
      return 'A tanulók felső 20%-ában vagy!';
    }
    if (average >= 3.75) {
      return 'A tanulók felső 35%-ában vagy!';
    }
    if (average >= 3.25) {
      return 'A tanulók felső 50%-ában vagy!';
    }
    return 'A tanulók felső 75%-ában vagy!';
  }
}

/// One concrete step of a scholarship path (e.g. 1x grade 5 at 100%).
class ScholarshipStep {
  final String subjectName;
  final bool isProfessional;
  final int grade;
  final int weight;
  final int count;

  const ScholarshipStep({
    required this.subjectName,
    required this.isProfessional,
    required this.grade,
    required this.weight,
    required this.count,
  });
}

/// Recommendation item generated by the Vocational Scholarship Tier Optimizer.
/// Vocational scholarship average is calculated from the subject averages:
/// `Global Average = Sum(Subject Averages) / Number of Subjects`.
class ScholarshipRecommendation {
  final String subjectName;
  final double subjectOldAverage;
  final double subjectNewAverage;
  final double globalBoost;
  final int recommendedGrade;
  final int recommendedWeight;
  final int countNeeded;
  final List<ScholarshipStep> steps;
  final double pointsNeeded;
  final double resultingOverallAverage;
  final String explanation;

  const ScholarshipRecommendation({
    required this.subjectName,
    required this.subjectOldAverage,
    required this.subjectNewAverage,
    required this.globalBoost,
    required this.recommendedGrade,
    required this.recommendedWeight,
    required this.countNeeded,
    required this.steps,
    required this.pointsNeeded,
    required this.resultingOverallAverage,
    required this.explanation,
  });

  String get title => subjectName;
  int get totalCount => countNeeded;
}

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

  String get heroId => subjectUid.isNotEmpty ? subjectUid : subjectName;
  String get uniqueHeroTag =>
      'subject_hero_${subjectUid.isNotEmpty ? subjectUid : subjectName}';

  int get maxWeightPercentage {
    int maxW = 100;
    for (final g in grades) {
      if (g.weightPercentage != null && g.weightPercentage! > maxW) {
        maxW = g.weightPercentage!;
      }
    }
    return maxW;
  }

  /// Computes a weighted average across real [grades] and optional [ghostGrades].
  /// When [allow200Weight] is explicitly `false`, weights above 100% are treated
  /// as 100% (unweighted / 100% base weight mode).
  static double? computeWeightedAverage(
    Iterable<Grade> grades, [
    Iterable<GhostGrade> ghostGrades = const [],
    bool? allow200Weight,
  ]) {
    double weightedSum = 0;
    double totalWeight = 0;
    for (final g in grades) {
      final val = g.numericValue;
      if (val == null || val < 1 || val > 5) continue;
      double weight =
          (g.weightPercentage != null && g.weightPercentage! > 0)
              ? g.weightPercentage!.toDouble()
              : 100.0;
      if (allow200Weight == false && weight > 100.0) {
        weight = 100.0;
      }
      weightedSum += val * weight;
      totalWeight += weight;
    }
    for (final ghost in ghostGrades) {
      double w = ghost.weightPercentage > 0
          ? ghost.weightPercentage.toDouble()
          : 100.0;
      if (allow200Weight == false && w > 100.0) {
        w = 100.0;
      }
      weightedSum += ghost.value * w;
      totalWeight += w;
    }
    if (totalWeight <= 0) return null;
    return weightedSum / totalWeight;
  }

  /// Evaluates the rounded integer grade (1..5) for [subject] using the user's
  /// configured rounding thresholds ("Globális kerekítési határok": Jeles 5,
  /// Jó 4, Közepes 3, Elégséges 2, plus any per-subject override).
  static int evaluateRoundedSubjectGrade(
    SubjectGradeSummary subject, {
    UserProfilePrefs? prefs,
    bool? allow200Weight,
    double? rawAverageOverride,
  }) {
    final rawAvg = rawAverageOverride ??
        (allow200Weight != null && subject.grades.isNotEmpty
            ? computeWeightedAverage(subject.grades, const [], allow200Weight)
            : null) ??
        subject.weightedAverage ??
        computeWeightedAverage(subject.grades) ??
        1.0;
    if (prefs != null) {
      return prefs.evaluateSubjectRoundedGrade(
        rawAvg,
        subject.heroId,
        subject.subjectName,
      );
    }
    return const GradeRoundingConfig().evaluateRoundedGrade(rawAvg);
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
    bool? allow200Weight,
  }) {
    double weightedSum = 0;
    double totalWeight = 0;
    for (final g in currentGrades) {
      final val = g.numericValue;
      if (val == null || val < 1 || val > 5) continue;
      double weight =
          (g.weightPercentage != null && g.weightPercentage! > 0)
              ? g.weightPercentage!.toDouble()
              : 100.0;
      if (allow200Weight == false && weight > 100.0) {
        weight = 100.0;
      }
      weightedSum += val * weight;
      totalWeight += weight;
    }
    for (final ghost in ghostGrades) {
      double w = ghost.weightPercentage > 0
          ? ghost.weightPercentage.toDouble()
          : 100.0;
      if (allow200Weight == false && w > 100.0) {
        w = 100.0;
      }
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
    for (int count = 1; count <= 60; count++) {
      final simAvg = (weightedSum + count * gradeValue * w) /
          (totalWeight + count * w);
      if (simAvg >= targetThreshold) {
        return count;
      }
    }
    return null;
  }

  /// Hungarian numeric grade label with proper suffix (`2-es`, `3-as`, `4-es`, `5-ös`).
  static String hungarianGradeLabel(int gradeValue) => switch (gradeValue) {
        1 => '1-es',
        2 => '2-es',
        3 => '3-as',
        4 => '4-es',
        5 => '5-ös',
        _ => '$gradeValue',
      };

  /// Calculates realistic target-grade paths using **strictly 100% weight**.
  ///
  /// Prioritizes the lowest whole grade (`3`, `4`, `5`, or `2` when threshold
  /// `< 2.0`) that can lift the average to [targetThreshold] at 100% weight,
  /// and optionally includes `5` when `5` reaches the target in strictly
  /// fewer grades.
  static ({
    bool isReached,
    ({int gradeValue, int count})? lowestOption,
    ({int gradeValue, int count})? fasterFiveOption,
  }) calculate100PercentNeededPlan({
    required Iterable<Grade> currentGrades,
    List<GhostGrade> ghostGrades = const [],
    required double targetThreshold,
    bool allow200Weight = true,
  }) {
    final currentAvg = computeWeightedAverage(
      currentGrades,
      ghostGrades,
      allow200Weight,
    );
    if (currentAvg != null && currentAvg >= targetThreshold) {
      return (isReached: true, lowestOption: null, fasterFiveOption: null);
    }

    final candidates = targetThreshold < 2.0 ? const [2, 3, 4, 5] : const [3, 4, 5];
    ({int gradeValue, int count})? lowestOption;
    int? countForFive;

    for (final g in candidates) {
      if (g <= targetThreshold) continue;
      if (currentAvg != null && g <= currentAvg) continue;
      final needed = calculateNeededGradesCount(
        currentGrades: currentGrades,
        ghostGrades: ghostGrades,
        targetThreshold: targetThreshold,
        gradeValue: g,
        weightPercentage: 100,
        allow200Weight: allow200Weight,
      );
      if (needed == null || needed <= 0) continue;
      lowestOption ??= (gradeValue: g, count: needed);
      if (g == 5) {
        countForFive = needed;
      }
    }

    ({int gradeValue, int count})? fasterFiveOption;
    if (lowestOption != null &&
        lowestOption.gradeValue != 5 &&
        countForFive != null &&
        countForFive < lowestOption.count) {
      fasterFiveOption = (gradeValue: 5, count: countForFive);
    }

    return (
      isReached: false,
      lowestOption: lowestOption,
      fasterFiveOption: fasterFiveOption,
    );
  }

  /// Computes grade count breakdown `{5: c5, 4: c4, 3: c3, 2: c2, 1: c1}`.
  static Map<int, int> computeGradeCounts(Iterable<Grade> allGrades) {
    final counts = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final g in allGrades) {
      final v = g.numericValue;
      if (v != null && counts.containsKey(v)) {
        counts[v] = counts[v]! + 1;
      }
    }
    return counts;
  }

  /// Computes the overall average (Kimeneti átlag) and vocational scholarship
  /// average strictly as the arithmetic mean of each subject's rounded integer
  /// grade (1, 2, 3, 4, or 5) evaluated via the user's rounding thresholds.
  static double? computeOverallSubjectAverage(
    Iterable<SubjectGradeSummary> subjects, {
    UserProfilePrefs? prefs,
    bool? allow200Weight,
    Iterable<GhostGrade> ghostGrades = const [],
  }) {
    double sumRounded = 0;
    double count = 0;
    for (final s in subjects) {
      final rawAvg = (allow200Weight != null && s.grades.isNotEmpty
              ? computeWeightedAverage(s.grades, const [], allow200Weight)
              : null) ??
          s.weightedAverage ??
          computeWeightedAverage(s.grades);
      if (rawAvg != null && rawAvg > 0) {
        final rounded = evaluateRoundedSubjectGrade(
          s,
          prefs: prefs,
          allow200Weight: allow200Weight,
          rawAverageOverride: rawAvg,
        );
        sumRounded += rounded;
        count += 1.0;
      }
    }
    for (final ghost in ghostGrades) {
      final wFactor = (ghost.weightPercentage > 0
              ? ghost.weightPercentage.toDouble()
              : 100.0) /
          100.0;
      sumRounded += ghost.value.clamp(1, 5) * wFactor;
      count += wFactor;
    }
    if (count <= 0) return null;
    return sumRounded / count;
  }

  /// Resolves the configured scholarship target average and matching tier (if any).
  static ({double targetAverage, ScholarshipTier? tier, int tierIndex})
      resolveScholarshipTarget(
    double? currentOverallAvg,
    UserProfilePrefs prefs,
  ) {
    final savedIdx = prefs.scholarshipTargetTierIdx;
    final savedAvg = prefs.scholarshipTargetAverage;
    if (savedIdx != null &&
        savedIdx >= 0 &&
        savedIdx < ScholarshipTier.tiers.length) {
      final tier = ScholarshipTier.tiers[savedIdx];
      final target = (savedAvg != null && savedAvg >= 1.0 && savedAvg <= 5.0)
          ? savedAvg
          : tier.minAverage;
      return (targetAverage: target, tier: tier, tierIndex: savedIdx);
    }
    if (savedAvg != null && savedAvg >= 1.0 && savedAvg <= 5.0) {
      final matchingIdx = ScholarshipTier.tiers.indexWhere(
        (t) => (t.minAverage - savedAvg).abs() < 0.005,
      );
      return (
        targetAverage: savedAvg,
        tier: matchingIdx >= 0 ? ScholarshipTier.tiers[matchingIdx] : null,
        tierIndex: matchingIdx >= 0
            ? matchingIdx
            : (ScholarshipTier.tiers.length - 1),
      );
    }
    final curIdx = ScholarshipTier.currentTierIndex(currentOverallAvg);
    final defaultIdx = curIdx == null
        ? 0
        : (curIdx + 1).clamp(0, ScholarshipTier.tiers.length - 1);
    final tier = ScholarshipTier.tiers[defaultIdx];
    return (
      targetAverage: tier.minAverage,
      tier: tier,
      tierIndex: defaultIdx,
    );
  }

  /// Computes overall cumulative average across [subjects], replacing
  /// [simulatedSubject]'s raw weighted average with [simulatedSubjectRawAverage].
  static double? computeSimulatedOverallAverage(
    Iterable<SubjectGradeSummary> subjects, {
    required SubjectGradeSummary simulatedSubject,
    required double? simulatedSubjectRawAverage,
    UserProfilePrefs? prefs,
    bool? allow200Weight,
  }) {
    double sumRounded = 0;
    double count = 0;
    var foundTarget = false;
    for (final s in subjects) {
      final isTarget = s.uniqueHeroTag == simulatedSubject.uniqueHeroTag ||
          s.heroId == simulatedSubject.heroId;
      double? rawAvg;
      if (isTarget) {
        foundTarget = true;
        rawAvg = simulatedSubjectRawAverage;
      } else {
        rawAvg = (allow200Weight != null && s.grades.isNotEmpty
                ? computeWeightedAverage(s.grades, const [], allow200Weight)
                : null) ??
            s.weightedAverage ??
            computeWeightedAverage(s.grades);
      }
      if (rawAvg != null && rawAvg > 0) {
        final rounded = evaluateRoundedSubjectGrade(
          s,
          prefs: prefs,
          allow200Weight: allow200Weight,
          rawAverageOverride: rawAvg,
        );
        sumRounded += rounded;
        count += 1.0;
      }
    }
    if (!foundTarget &&
        simulatedSubjectRawAverage != null &&
        simulatedSubjectRawAverage > 0) {
      final rounded = evaluateRoundedSubjectGrade(
        simulatedSubject,
        prefs: prefs,
        allow200Weight: allow200Weight,
        rawAverageOverride: simulatedSubjectRawAverage,
      );
      sumRounded += rounded;
      count += 1.0;
    }
    if (count <= 0) return null;
    return sumRounded / count;
  }

  /// Analyzes the student's overall scholarship average across subjects:
  /// `Global Average = Sum(Rounded Integer Subject Grades) / Number of Subjects`
  /// and calculates how many 5-ös grades are needed in each subject to push its
  /// raw average across the next rounding threshold (flipping its rounded integer
  /// grade up by +1 and boosting the overall average).
  static List<ScholarshipRecommendation> buildScholarshipRecommendations({
    required List<Grade> allGrades,
    required List<SubjectGradeSummary> subjects,
    required double targetAverage,
    UserProfilePrefs? prefs,
    bool? allow200Weight,
  }) {
    final validSubjects = subjects
        .where(
          (s) => (s.weightedAverage ?? computeWeightedAverage(s.grades)) != null,
        )
        .toList();
    final nSubjects = validSubjects.length;
    if (nSubjects == 0 || targetAverage > 5.0) {
      return const [];
    }

    final use200 = allow200Weight ?? prefs?.calcAllow200Weight ?? false;
    final weight = use200 ? 200 : 100;
    // Respect the 100% vs 200% weight toggle when explicit or configured:
    final effectiveAllow200 =
        (allow200Weight != null || prefs != null) ? use200 : null;

    final currentGlobalAvg = computeOverallSubjectAverage(
          validSubjects,
          prefs: prefs,
          allow200Weight: effectiveAllow200,
        ) ??
        0.0;
    if (currentGlobalAvg >= targetAverage - 1e-9) {
      return const [];
    }

    final gap = targetAverage - currentGlobalAvg;

    String nameOf(SubjectGradeSummary s) => prefs != null
        ? prefs.resolveSubjectName(s.subjectName, s.subjectUid)
        : s.subjectName;

    GradeRoundingConfig roundingOf(SubjectGradeSummary s) => prefs != null
        ? prefs.roundingForSubject(s.heroId, s.subjectName)
        : const GradeRoundingConfig();

    double rawAvgOf(SubjectGradeSummary s) =>
        (effectiveAllow200 != null && s.grades.isNotEmpty
            ? computeWeightedAverage(s.grades, const [], effectiveAllow200)
            : null) ??
        s.weightedAverage ??
        computeWeightedAverage(s.grades) ??
        0.0;

    double simSubjAvg(SubjectGradeSummary s, int k) {
      return computeWeightedAverage(
            s.grades,
            List<GhostGrade>.filled(
              k,
              GhostGrade(value: 5, weightPercentage: weight),
            ),
            effectiveAllow200,
          ) ??
          5.0;
    }

    final candidates = <({
      SubjectGradeSummary subj,
      double oldAvg,
      int oldRounded,
      int newRounded,
      int count,
      double newAvg,
      double totalBoost,
      double distanceToThreshold,
    })>[];

    for (final subj in validSubjects) {
      final rounding = roundingOf(subj);
      final oldAvg = rawAvgOf(subj);
      final oldRounded = rounding.evaluateRoundedGrade(oldAvg);
      if (oldRounded >= 5) continue;

      final nextRounded = oldRounded + 1;
      final nextThreshold = rounding.thresholdForGrade(nextRounded);

      final neededCount = calculateNeededGradesCount(
        currentGrades: subj.grades,
        ghostGrades: const [],
        targetThreshold: nextThreshold,
        gradeValue: 5,
        weightPercentage: weight,
        allow200Weight: effectiveAllow200,
      );
      if (neededCount == null || neededCount <= 0) continue;

      int chosenCount = neededCount;
      double newAvg = simSubjAvg(subj, chosenCount);
      int newRounded = rounding.evaluateRoundedGrade(newAvg);
      if (newRounded <= oldRounded) {
        newRounded = nextRounded;
      }
      double totalBoost = (newRounded - oldRounded) / nSubjects;

      // If flipping by +1 doesn't reach targetAverage alone and the subject can
      // be pushed to an even higher rounded integer grade within <= 4 grades,
      // check if a multi-grade jump reaches the target.
      if (totalBoost < gap - 1e-9 && newRounded < 5) {
        final higherTargetGrade = (oldRounded + 2).clamp(2, 5);
        final higherThreshold = rounding.thresholdForGrade(higherTargetGrade);
        final neededHigher = calculateNeededGradesCount(
          currentGrades: subj.grades,
          ghostGrades: const [],
          targetThreshold: higherThreshold,
          gradeValue: 5,
          weightPercentage: weight,
          allow200Weight: effectiveAllow200,
        );
        if (neededHigher != null && neededHigher > 0 && neededHigher <= 4) {
          final avgH = simSubjAvg(subj, neededHigher);
          final roundH = rounding.evaluateRoundedGrade(avgH);
          final boostH = (roundH - oldRounded) / nSubjects;
          if (boostH >= gap - 1e-9) {
            chosenCount = neededHigher;
            newAvg = avgH;
            newRounded = roundH;
            totalBoost = boostH;
          }
        }
      }

      candidates.add((
        subj: subj,
        oldAvg: oldAvg,
        oldRounded: oldRounded,
        newRounded: newRounded,
        count: chosenCount,
        newAvg: newAvg,
        totalBoost: totalBoost,
        distanceToThreshold: (nextThreshold - oldAvg).clamp(0.0, 5.0),
      ));
    }

    // Order dynamically by easiest effort: fewest 5-ös grades needed to flip
    // the rounded subject grade first, then highest global boost, then closest
    // to the next rounding threshold!
    candidates.sort((a, b) {
      final countCmp = a.count.compareTo(b.count);
      if (countCmp != 0) return countCmp;
      final boostCmp = b.totalBoost.compareTo(a.totalBoost);
      if (boostCmp != 0) return boostCmp;
      return a.distanceToThreshold.compareTo(b.distanceToThreshold);
    });

    final recs = <ScholarshipRecommendation>[];
    for (final c in candidates.take(5)) {
      final displayName = nameOf(c.subj);
      final projGlobal = currentGlobalAvg + c.totalBoost;
      final weightLabel = weight == 100 ? '' : '$weight%-os ';
      final reachesTarget = projGlobal >= targetAverage - 1e-9;
      final explanation =
          '$displayName: Szerezz ${c.count} db ${weightLabel}5-öst '
          '(${c.oldAvg.toStringAsFixed(2)} -> ${c.newAvg.toStringAsFixed(2)}, '
          'kerekítve: ${c.oldRounded} -> ${c.newRounded}), '
          'ami +${c.totalBoost.toStringAsFixed(2)}-vel dobja meg a teljes átlagodat'
          '${reachesTarget ? " (eléri a kívánt ${targetAverage.toStringAsFixed(2)}-t)!" : "!"}';

      recs.add(
        ScholarshipRecommendation(
          subjectName: displayName,
          subjectOldAverage: c.oldAvg,
          subjectNewAverage: c.newAvg,
          globalBoost: c.totalBoost,
          recommendedGrade: 5,
          recommendedWeight: weight,
          countNeeded: c.count,
          steps: [
            ScholarshipStep(
              subjectName: displayName,
              isProfessional: weight >= 200,
              grade: 5,
              weight: weight,
              count: c.count,
            ),
          ],
          pointsNeeded: gap,
          resultingOverallAverage: projGlobal,
          explanation: explanation,
        ),
      );
    }

    return recs;
  }

  /// Groups all student grades by subject and sorts them according to [sortMode].
  static List<SubjectGradeSummary> groupBySubject(
    List<Grade> allGrades, {
    SubjectSortMode sortMode = SubjectSortMode.alphabetical,
    UserProfilePrefs? prefs,
  }) {
    final map = <String, List<Grade>>{};
    for (final g in allGrades) {
      final key = g.subject.uid.isNotEmpty ? g.subject.uid : g.subject.name;
      map.putIfAbsent(key, () => <Grade>[]).add(g);
    }

    final summaries = <SubjectGradeSummary>[];
    for (final entry in map.entries) {
      final list = List<Grade>.from(entry.value)
        ..sort((a, b) {
          final cmp = b.recordedAt.compareTo(a.recordedAt);
          return cmp != 0 ? cmp : b.recordDate.compareTo(a.recordDate);
        });
      final first = list.first;
      summaries.add(
        SubjectGradeSummary(
          subjectUid: first.subject.uid,
          subjectName: first.subject.name,
          categoryDescription: first.subject.category.description,
          grades: list,
          weightedAverage: computeWeightedAverage(
            list,
            const [],
            prefs?.calcAllow200Weight,
          ),
          latestGrade: first,
        ),
      );
    }

    summaries.sort((a, b) {
      final nameA = (prefs != null
              ? prefs.resolveSubjectName(a.subjectName, a.subjectUid)
              : a.subjectName)
          .toLowerCase();
      final nameB = (prefs != null
              ? prefs.resolveSubjectName(b.subjectName, b.subjectUid)
              : b.subjectName)
          .toLowerCase();

      switch (sortMode) {
        case SubjectSortMode.averageAsc:
          final avgA = a.weightedAverage ?? 99.0;
          final avgB = b.weightedAverage ?? 99.0;
          final cmp = avgA.compareTo(avgB);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case SubjectSortMode.averageDesc:
          final avgA = a.weightedAverage ?? -1.0;
          final avgB = b.weightedAverage ?? -1.0;
          final cmp = avgB.compareTo(avgA);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case SubjectSortMode.alphabetical:
          return nameA.compareTo(nameB);
      }
    });
    return summaries;
  }
}

/// "Jegyek" tab: displays cumulative weighted average (tappable for Breakdown &
/// Vocational Scholarship Optimizer Modal), Overall Szellemjegy Számoló,
/// sorting controls (A-Z, Average Ascending, Average Descending), standing grade
/// badges, and opens [SubjectGradesDetailScreen].
class GradesScreen extends StatefulWidget {
  final List<Grade> allGrades;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final Future<void> Function() onRefresh;
  final bool isActiveTab;
  final int entranceEpoch;

  const GradesScreen({
    super.key,
    required this.allGrades,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onRefresh,
    this.isActiveTab = true,
    this.entranceEpoch = 0,
  });

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  final List<GhostGrade> _overallGhostGrades = [];
  bool _showSimulatorPanel = false;
  int _selectedGhostWeight = 100;
  late SubjectSortMode _sortMode;
  bool _userChangedSort = false;

  late final AnimationController _sortReflowCtrl;
  late final CurvedAnimation _sortReflowCurve;
  final GlobalKey _sortListHeaderKey = GlobalKey();
  final Map<String, GlobalKey> _subjectTileKeys = {};
  Map<String, double> _sortDeltaYs = const {};
  List<SubjectGradeSummary> _lastRenderedSubjects = const [];

  /// Entrance animations run once when the screen is first shown with data;
  /// lazily built list tiles never re-animate while scrolling.
  bool _initialEntrancePlayed = false;
  bool _entranceActive = false;

  @override
  void initState() {
    super.initState();
    _sortMode = SubjectSortMode.fromStorageKey(
      widget.prefs.extras[kGradesSelectedSortModeKey] as String?,
    );
    _sortReflowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1.0,
    );
    _sortReflowCurve = CurvedAnimation(
      parent: _sortReflowCtrl,
      curve: Curves.easeOutCubic,
    );
    unawaited(_restorePersistedSortMode());
    if (widget.isActiveTab) {
      _armInitialEntrance();
    }
  }

  @override
  void dispose() {
    _sortReflowCurve.dispose();
    _sortReflowCtrl.dispose();
    super.dispose();
  }

  Future<void> _restorePersistedSortMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKey = prefs.getString(kGradesSelectedSortModeKey);
      if (!mounted || _userChangedSort || savedKey == null) return;
      final restored = SubjectSortMode.fromStorageKey(savedKey);
      if (restored != _sortMode) {
        setState(() => _sortMode = restored);
      }
    } catch (_) {
      // Keep initial fallback if SharedPreferences is unavailable.
    }
  }

  Map<String, double> _computeSortReflowDeltas(SubjectSortMode nextMode) {
    final oldList = _lastRenderedSubjects.isNotEmpty
        ? _lastRenderedSubjects
        : SubjectGradeSummary.groupBySubject(
            widget.allGrades,
            sortMode: _sortMode,
            prefs: widget.prefs,
          );
    final nextList = SubjectGradeSummary.groupBySubject(
      widget.allGrades,
      sortMode: nextMode,
      prefs: widget.prefs,
    );
    if (oldList.isEmpty || nextList.isEmpty) return const {};

    final oldTops = <String, double>{};
    final tileHeights = <String, double>{};
    double totalMeasuredHeight = 0.0;
    int measuredCount = 0;
    int? firstMeasuredIdx;
    double? firstMeasuredTop;

    for (int i = 0; i < oldList.length; i++) {
      final heroId = oldList[i].heroId;
      final box =
          _subjectTileKeys[heroId]?.currentContext?.findRenderObject()
              as RenderBox?;
      if (box != null && box.hasSize) {
        final top = box.localToGlobal(Offset.zero).dy;
        oldTops[heroId] = top;
        tileHeights[heroId] = box.size.height;
        totalMeasuredHeight += box.size.height;
        measuredCount++;
        firstMeasuredIdx ??= i;
        firstMeasuredTop ??= top;
      }
    }

    final fallbackHeight =
        measuredCount > 0 ? (totalMeasuredHeight / measuredCount) : 92.0;
    final headerBox =
        _sortListHeaderKey.currentContext?.findRenderObject() as RenderBox?;
    final double originY;
    if (headerBox != null && headerBox.hasSize) {
      originY = headerBox.localToGlobal(Offset(0, headerBox.size.height)).dy;
    } else if (firstMeasuredTop != null && firstMeasuredIdx != null) {
      originY = firstMeasuredTop - (firstMeasuredIdx * fallbackHeight);
    } else {
      originY = 0.0;
    }

    final oldIndexByHero = <String, int>{
      for (int i = 0; i < oldList.length; i++) oldList[i].heroId: i,
    };
    final deltas = <String, double>{};
    double cursorY = originY;
    for (int i = 0; i < nextList.length; i++) {
      final heroId = nextList[i].heroId;
      final h = tileHeights[heroId] ?? fallbackHeight;
      final oldIdx = oldIndexByHero[heroId] ?? i;
      final oldY = oldTops[heroId] ?? (originY + (oldIdx * fallbackHeight));
      final rawDelta = oldY - cursorY;
      if (rawDelta.abs() > 0.5) {
        deltas[heroId] = rawDelta.clamp(-420.0, 420.0);
      }
      cursorY += h;
    }
    return deltas;
  }

  void _selectSortMode(SubjectSortMode mode) {
    _userChangedSort = true;
    HapticFeedback.selectionClick();
    if (_sortMode != mode) {
      final nextDeltaYs = _computeSortReflowDeltas(mode);
      setState(() {
        _sortMode = mode;
        _sortDeltaYs = nextDeltaYs;
      });
      if (nextDeltaYs.isNotEmpty) {
        _sortReflowCtrl.forward(from: 0.0);
      }
    }
    unawaited(_persistSortMode(mode));
    widget.onPrefsChanged(
      widget.prefs.withExtra(kGradesSelectedSortModeKey, mode.name),
    );
  }

  Future<void> _persistSortMode(SubjectSortMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kGradesSelectedSortModeKey, mode.name);
    } catch (_) {
      // Ignore storage failures so UI responsiveness stays immediate.
    }
  }

  @override
  void didUpdateWidget(covariant GradesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.prefs.extras[kGradesSelectedSortModeKey];
    final newKey = widget.prefs.extras[kGradesSelectedSortModeKey];
    if (!_userChangedSort && newKey != oldKey && newKey is String) {
      _sortMode = SubjectSortMode.fromStorageKey(newKey);
    }
    if (widget.isActiveTab && !_initialEntrancePlayed) {
      _armInitialEntrance();
    }
  }

  void _armInitialEntrance() {
    _initialEntrancePlayed = true;
    _entranceActive = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceActive = false;
    });
  }

  Widget _enter(Widget child, int index, Key key) => child.staggeredEntrance(
        index,
        animationKey: key,
        enabled: _entranceActive,
      );

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
    HapticFeedback.lightImpact();
    setState(() {
      _overallGhostGrades.removeAt(index);
    });
  }

  void _clearOverallGhostGrades() {
    HapticFeedback.lightImpact();
    setState(() => _overallGhostGrades.clear());
  }

  void _openScholarshipAndBreakdownModal(
    List<SubjectGradeSummary> subjects,
    double? overallAvg,
  ) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: resolveSoftBlurBarrierColor(context, prefs: widget.prefs),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 250),
        reverseDuration: Duration(milliseconds: 230),
      ),
      builder: (modalContext) {
        return _ScholarshipAndBreakdownDialog(
          allGrades: widget.allGrades,
          subjects: subjects,
          overallAverage: overallAvg,
          prefs: widget.prefs,
          onPrefsChanged: widget.onPrefsChanged,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subjects = SubjectGradeSummary.groupBySubject(
      widget.allGrades,
      sortMode: _sortMode,
      prefs: widget.prefs,
    );
    _lastRenderedSubjects = subjects;
    final indexByHeroId = <String, int>{
      for (int i = 0; i < subjects.length; i++) subjects[i].heroId: i,
    };

    final baseOverallAvg = SubjectGradeSummary.computeOverallSubjectAverage(
          subjects,
          prefs: widget.prefs,
          allow200Weight: widget.prefs.calcAllow200Weight,
        ) ??
        SubjectGradeSummary.computeWeightedAverage(
          widget.allGrades,
          const [],
          widget.prefs.calcAllow200Weight,
        );
    final simulatedOverallAvg = _overallGhostGrades.isEmpty
        ? baseOverallAvg
        : (SubjectGradeSummary.computeOverallSubjectAverage(
              subjects,
              prefs: widget.prefs,
              allow200Weight: widget.prefs.calcAllow200Weight,
              ghostGrades: _overallGhostGrades,
            ) ??
            SubjectGradeSummary.computeWeightedAverage(
              widget.allGrades,
              _overallGhostGrades,
              widget.prefs.calcAllow200Weight,
            ));
    final numericGradeCount =
        widget.allGrades.where((g) => g.numericValue != null).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: TactileBounce(
          onTap: () =>
              setState(() => _showSimulatorPanel = !_showSimulatorPanel),
          child: FloatingActionButton(
            heroTag: null,
            tooltip: 'Szellemjegy számoló',
            onPressed: null,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              _showSimulatorPanel
                  ? Icons.expand_less_rounded
                  : Icons.auto_fix_high_rounded,
              size: 24,
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        displacement: 44,
        edgeOffset: 8,
        strokeWidth: 2.6,
        onRefresh: widget.onRefresh,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(top: 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  key: _sortListHeaderKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _enter(
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TactileBounce(
                          pressedScale: 0.98,
                          onTap: () => _openScholarshipAndBreakdownModal(
                            subjects,
                            _overallGhostGrades.isNotEmpty
                                ? simulatedOverallAvg
                                : baseOverallAvg,
                          ),
                          child: _buildCumulativeAverageCard(
                            theme,
                            scheme,
                            baseAverage: baseOverallAvg,
                            simulatedAverage: simulatedOverallAvg,
                            subjectCount: subjects.length,
                            gradeCount: numericGradeCount,
                          ),
                        ),
                      ),
                      0,
                      const ValueKey('grades-top'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: (_showSimulatorPanel ||
                                _overallGhostGrades.isNotEmpty)
                            ? Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: _buildOverallGhostSimulatorCard(
                                  theme,
                                  scheme,
                                  baseAverage: baseOverallAvg,
                                  simulatedAverage: simulatedOverallAvg,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 20,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              uwu('Tantárgyak és kerekített átlagok'),
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
                    ),
                    const SizedBox(height: 10),
                    _buildSortBar(theme, scheme),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (subjects.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 160),
                sliver: SliverToBoxAdapter(
                  child: _buildEmptyCard(theme, scheme),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 160),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, idx) {
                      final subj = subjects[idx];
                      final tileKey = _subjectTileKeys.putIfAbsent(
                        subj.heroId,
                        () => GlobalKey(),
                      );
                      final startDeltaY = _sortDeltaYs[subj.heroId] ?? 0.0;
                      final tileWidget = _enter(
                        _buildSubjectTile(
                          context,
                          theme,
                          scheme,
                          subj,
                          subjects,
                        ),
                        idx < 7 ? idx + 1 : 7,
                        ValueKey('subj-enter-${subj.heroId}'),
                      );

                      return RepaintBoundary(
                        key: ValueKey<String>('subj-${subj.heroId}'),
                        child: AnimatedBuilder(
                          animation: _sortReflowCurve,
                          child: KeyedSubtree(
                            key: tileKey,
                            child: tileWidget,
                          ),
                          builder: (context, child) {
                            final t = _sortReflowCurve.value.clamp(0.0, 1.0);
                            final dy = startDeltaY * (1.0 - t);
                            final moving = startDeltaY.abs() > 1.0 && t < 1.0;
                            final opacity = moving ? (0.85 + (0.15 * t)) : 1.0;
                            final shifted = dy.abs() > 0.01
                                ? Transform.translate(
                                    offset: Offset(0.0, dy),
                                    child: child,
                                  )
                                : child!;
                            return opacity < 0.999
                                ? Opacity(opacity: opacity, child: shifted)
                                : shifted;
                          },
                        ),
                      );
                    },
                    childCount: subjects.length,
                    findChildIndexCallback: (Key key) {
                      if (key is ValueKey<String>) {
                        const prefix = 'subj-';
                        if (key.value.startsWith(prefix)) {
                          return indexByHeroId[
                              key.value.substring(prefix.length)];
                        }
                      }
                      return null;
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortBar(ThemeData theme, ColorScheme scheme) {
    final selectedIdx = SubjectSortMode.values.indexOf(_sortMode);
    final effectivePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    return LiquidBubbleTabBar(
      height: 40,
      fontSize: 12,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      liquidGlassEnabled: effectivePrefs.liquidGlassEnabled,
      selectedIndex: selectedIdx < 0 ? 0 : selectedIdx,
      items: [
        for (final mode in SubjectSortMode.values)
          LiquidBubbleTabItem(
            label: mode.label,
            icon: mode.icon,
          ),
      ],
      onSelected: (idx) => _selectSortMode(SubjectSortMode.values[idx]),
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

    return ChristmasSnowCap(
      enabled: widget.prefs.christmasModeEnabled,
      child: SoftGlassCard(
        prefs: widget.prefs,
        padding: const EdgeInsets.all(20),
        borderRadius: OledTheme.largeRadius,
        border: Border.all(
          color: avgColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: 74,
              height: 74,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: avgColor,
                borderRadius: OledTheme.badgeRadius,
              ),
              child: activeAvg != null
                  ? AnimatedNumberText(
                      value: activeAvg,
                      fractionDigits: 2,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : Text(
                      '–',
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          uwu(
                            _overallGhostGrades.isNotEmpty
                                ? 'Szimulált összesített átlag'
                                : 'Összesített súlyozott átlag',
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.analytics_outlined,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ],
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
                            '$roundedGrade',
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
                          child: AnimatedNumberText(
                            value: delta,
                            fractionDigits: 2,
                            prefix: delta >= 0 ? '+' : '',
                            suffix:
                                ' (alap: ${baseAverage!.toStringAsFixed(2)})',
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
                    '$gradeCount db érdemjegy • $subjectCount tantárgy • Koppints az ösztöndíj kalkulátorért!',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallGhostSimulatorCard(
    ThemeData theme,
    ColorScheme scheme, {
    required double? baseAverage,
    required double? simulatedAverage,
  }) {
    return SoftGlassCard(
      prefs: widget.prefs,
      padding: const EdgeInsets.symmetric(vertical: 18),
      borderRadius: OledTheme.largeRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
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
              ],
            ),
          ),
          EdgeFadeHorizontalScroll(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            spacing: 8,
            children: [
              Text(
                'Súly: $_selectedGhostWeight%',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              ...[50, 100, 200].map((w) {
                final selected = _selectedGhostWeight == w;
                return TactileBounce(
                  onTap: () => setState(() => _selectedGhostWeight = w),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                        child: TactileBounce(
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
              ],
            ),
          ),
          if (_overallGhostGrades.isNotEmpty) ...[
            const SizedBox(height: 14),
            EdgeFadeHorizontalScroll(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              spacing: 8,
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
    return SoftGlassCard(
      prefs: widget.prefs,
      padding: const EdgeInsets.all(24),
      borderRadius: OledTheme.cardRadius,
      border: Border.all(color: theme.dividerColor),
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
    List<SubjectGradeSummary> allSubjects,
  ) {
    final avg = summary.weightedAverage;
    final avgText = avg != null ? avg.toStringAsFixed(2) : '–';
    final customColor = widget.prefs.customColorForSubject(
      summary.heroId,
      summary.subjectName,
    );
    final roundedStanding = avg != null
        ? widget.prefs.evaluateSubjectRoundedGrade(
            avg,
            summary.heroId,
            summary.subjectName,
          )
        : null;

    final standingColor = customColor ??
        (roundedStanding != null
            ? OledTheme.gradeColor(roundedStanding, widget.prefs)
            : scheme.surfaceContainerHigh);

    final standingText = roundedStanding?.toString() ?? '–';
    final displaySubjectName = widget.prefs.resolveSubjectName(
      summary.subjectName,
      summary.subjectUid,
    );

    final subjectHeroTag = summary.uniqueHeroTag;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () {
          Navigator.of(context).push(
            SmoothSharedAxisRoute(
              page: SubjectGradesDetailScreen(
                summary: summary,
                allSubjects: allSubjects,
                prefs: widget.prefs,
                onPrefsChanged: widget.onPrefsChanged,
              ),
            ),
          );
        },
        child: Hero(
          tag: subjectHeroTag,
          child: Material(
            type: MaterialType.transparency,
            child: ChristmasSnowCap(
              enabled: widget.prefs.christmasModeEnabled,
              child: SoftGlassCard(
                prefs: widget.prefs,
                padding: const EdgeInsets.all(16),
                borderRadius: OledTheme.cardRadius,
                border: Border.all(
                  color: customColor != null
                      ? customColor.withValues(alpha: 0.65)
                      : theme.dividerColor,
                ),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displaySubjectName,
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
                                    color: standingColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: standingColor.withValues(
                                        alpha: 0.65,
                                      ),
                                    ),
                                  ),
                                  child: avg != null
                                      ? AnimatedNumberText(
                                          value: avg,
                                          fractionDigits: 2,
                                          prefix: 'Átlag: ',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: scheme.onSurface,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        )
                                      : Text(
                                          'Átlag: $avgText',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: scheme.onSurface,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                                Text(
                                  '${summary.grades.length} db jegy',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: standingColor,
                          borderRadius: OledTheme.badgeRadius,
                        ),
                        child: Text(
                          standingText,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
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
            ),
          ),
        ),
      ),
    );
  }
}

/// Comprehensive Cumulative Average Breakdown & Vocational Scholarship Tier
/// Optimizer Modal (`Szakképzési ösztöndíj kalkulátor`).
class _ScholarshipAndBreakdownDialog extends StatefulWidget {
  final List<Grade> allGrades;
  final List<SubjectGradeSummary> subjects;
  final double? overallAverage;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs>? onPrefsChanged;

  const _ScholarshipAndBreakdownDialog({
    required this.allGrades,
    required this.subjects,
    required this.overallAverage,
    required this.prefs,
    this.onPrefsChanged,
  });

  @override
  State<_ScholarshipAndBreakdownDialog> createState() =>
      _ScholarshipAndBreakdownDialogState();
}

class _ScholarshipAndBreakdownDialogState
    extends State<_ScholarshipAndBreakdownDialog> {
  late int _selectedTargetTierIdx;
  late bool _allow200Weight;
  late UserProfilePrefs _prefs;
  late bool _basic;

  void _updateScholarshipPrefs(UserProfilePrefs next) {
    setState(() {
      _prefs = next;
      _basic = next.scholarshipBasicEducation;
    });
    widget.onPrefsChanged?.call(next);
  }

  Widget _buildModeSelector(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EdgeFadeHorizontalScroll(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          spacing: 8,
          children: [
            ChoiceChip(
              showCheckmark: false,
              label: const Text('Szakirányú oktatás'),
              selected: !_basic,
              onSelected: (_) => _updateScholarshipPrefs(
                _prefs.withExtra('scholarshipBasic', false),
              ),
            ),
            ChoiceChip(
              showCheckmark: false,
              label: const Text('Ágazati alapoktatás (9–10. évf.)'),
              selected: _basic,
              onSelected: (_) => _updateScholarshipPrefs(
                _prefs.withExtra('scholarshipBasic', true),
              ),
            ),
          ],
        ),
        if (_basic) ...[
          const SizedBox(height: 10),
          EdgeFadeHorizontalScroll(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            spacing: 8,
            children: [
              for (final entry in const {
                'technikum': 'Technikum',
                'szakkepzo': 'Szakképző',
              }.entries)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(entry.value),
                  selected: _prefs.scholarshipSchoolType == entry.key,
                  onSelected: (_) => _updateScholarshipPrefs(
                    _prefs.withExtra('scholarshipSchoolType', entry.key),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBasicEducationCard(ThemeData theme, ColorScheme scheme) {
    final amount =
        ScholarshipTier.basicEducationMonthlyForint(_prefs.scholarshipSchoolType);
    final typeLabel =
        _prefs.scholarshipSchoolType == 'szakkepzo' ? 'Szakképző' : 'Technikum';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.22),
            scheme.surfaceContainerHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: OledTheme.cardRadius,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_rounded, color: scheme.primary, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ScholarshipTier.formatForint(amount)} Ft / hó',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ágazati alapoktatás • $typeLabel • fix összeg, átlagtól független',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _allow200Weight = widget.prefs.calcAllow200Weight;
    _prefs = widget.prefs;
    _basic = widget.prefs.scholarshipBasicEducation;
    final resolvedTarget = SubjectGradeSummary.resolveScholarshipTarget(
      widget.overallAverage,
      widget.prefs,
    );
    _selectedTargetTierIdx = resolvedTarget.tierIndex;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = SubjectGradeSummary.computeGradeCounts(widget.allGrades);
    final totalGrades = counts.values.fold<int>(0, (a, b) => a + b);
    final currentAvg = SubjectGradeSummary.computeOverallSubjectAverage(
          widget.subjects,
          prefs: _prefs,
          allow200Weight: _allow200Weight,
        ) ??
        widget.overallAverage;
    final currentTierIdx = ScholarshipTier.currentTierIndex(currentAvg);
    final currentTier =
        currentTierIdx != null ? ScholarshipTier.tiers[currentTierIdx] : null;
    final targetTier = ScholarshipTier.tiers[_selectedTargetTierIdx];
    final goalTier = targetTier;
    final currentForint = currentTier?.estimatedMonthlyForint ?? 0;
    final goalForint = goalTier.estimatedMonthlyForint;
    final extraForint = (goalForint - currentForint).clamp(0, 100000);
    final avgGap = currentAvg != null
        ? (goalTier.minAverage - currentAvg).clamp(0.0, 5.0)
        : goalTier.minAverage;

    final prevFloor = currentTier?.minAverage ?? 1.00;
    final span = (goalTier.minAverage - prevFloor).clamp(0.25, 4.0);
    final progressToGoal = currentAvg == null
        ? 0.0
        : currentAvg >= goalTier.minAverage
            ? 1.0
            : ((currentAvg - prevFloor) / span).clamp(0.08, 0.96);

    final recommendations =
        SubjectGradeSummary.buildScholarshipRecommendations(
      allGrades: widget.allGrades,
      subjects: widget.subjects,
      targetAverage: targetTier.minAverage,
      prefs: _prefs,
      allow200Weight: _allow200Weight,
    );

    return LiquidGlassSurface(
      prefs: _prefs,
      highContrastExpanded: true,
      contentOpacityAnimation: ModalRoute.of(context)?.animation,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.55,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: scheme.primary,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          uwu('Átlag elemzés & Ösztöndíj kalkulátor'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildModeSelector(theme, scheme),
                const SizedBox(height: 12),
                // 1. Gamified Motivational Cash Payout Milestone Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _basic
                      ? _buildBasicEducationCard(theme, scheme)
                      : Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.22),
                        scheme.surfaceContainerHigh,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: OledTheme.cardRadius,
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 54,
                            height: 54,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 54,
                                  height: 54,
                                  child: CircularProgressIndicator(
                                    value: progressToGoal,
                                    strokeWidth: 5.5,
                                    backgroundColor:
                                        scheme.onSurface.withValues(alpha: 0.12),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      scheme.primary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${(progressToGoal * 100).round()}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentTier != null
                                      ? '${currentTier.shortTitle}: ${currentTier.monthlyAmountLabel}'
                                      : 'Jelenleg: Nem jogosult (< 2.00)',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Cél: ${goalTier.shortTitle} ${goalTier.minAverage.toStringAsFixed(2)}-tól (${goalTier.monthlyAmountLabel})',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currentAvg != null
                                      ? 'Összesített tantárgyi átlagod: ${currentAvg.toStringAsFixed(2)}'
                                      : 'Nincs rögzített átlag',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.72),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progressToGoal,
                          minHeight: 7,
                          backgroundColor:
                              scheme.onSurface.withValues(alpha: 0.12),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(scheme.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            avgGap <= 0
                                ? Icons.verified_rounded
                                : Icons.trending_up_rounded,
                            size: 16,
                            color: avgGap <= 0
                                ? Colors.greenAccent
                                : scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              avgGap <= 0
                                  ? 'Elérted a kiválasztott ${goalTier.shortTitle.toLowerCase()}ot (${goalTier.monthlyAmountLabel})!'
                                  : extraForint > 0
                                      ? 'Még ${avgGap.toStringAsFixed(2)} hiányzik a havi +${ScholarshipTier.formatForint(extraForint)} Ft-hoz!'
                                      : 'Még ${avgGap.toStringAsFixed(2)} hiányzik a(z) ${goalTier.minAverage.toStringAsFixed(2)} célátlaghoz!',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: avgGap <= 0
                                    ? Colors.greenAccent
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ),
                const SizedBox(height: 18),
                // 2. Grade Count Breakdown
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Érdemjegyek eloszlása ($totalGrades db)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                EdgeFadeHorizontalScroll(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  spacing: 8,
                  children: [5, 4, 3, 2, 1].map((g) {
                    final count = counts[g] ?? 0;
                    final color = OledTheme.gradeColor(g, widget.prefs);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: color.withValues(alpha: 0.65)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${count}x',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '$g',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                if (!_basic) ...[
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 3. Vocational Scholarship Tier Optimizer
                      Row(
                        children: [
                          Icon(
                            Icons.school_rounded,
                            size: 19,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Szakképzési ösztöndíj kalkulátor',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'A szakképzési ösztöndíj kizárólag az összesített súlyozott átlagtól függ (nem szükséges minden tantárgyból külön 4.00 feletti átlagot elérni). Válassz cél sávot:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.68),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...List.generate(ScholarshipTier.tiers.length, (idx) {
                        final tier = ScholarshipTier.tiers[idx];
                        final isCurrent = currentTierIdx == idx;
                        final isTarget = _selectedTargetTierIdx == idx;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TactileBounce(
                            onTap: () {
                              setState(() => _selectedTargetTierIdx = idx);
                              _updateScholarshipPrefs(
                                _prefs.withExtras({
                                  'scholarshipTargetTierIdx': idx,
                                  'scholarshipTargetAverage': tier.minAverage,
                                }),
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: isTarget
                                    ? scheme.primary.withValues(alpha: 0.2)
                                    : scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isTarget
                                      ? scheme.primary
                                      : isCurrent
                                          ? Colors.greenAccent
                                          : theme.dividerColor,
                                  width: (isTarget || isCurrent) ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isCurrent
                                        ? Icons.check_circle_rounded
                                        : isTarget
                                            ? Icons.flag_circle_rounded
                                            : Icons.circle_outlined,
                                    size: 20,
                                    color: isCurrent
                                        ? Colors.greenAccent
                                        : isTarget
                                            ? scheme.primary
                                            : scheme.onSurface
                                                .withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${tier.rangeLabel}: ${tier.title}',
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCurrent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.green.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Jelenlegi sáv',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    )
                                  else if (isTarget)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primary
                                            .withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Kiválasztott cél',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 14),
                      Text(
                        'Kalkulátor jegy súlyozása:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                EdgeFadeHorizontalScroll(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      showCheckmark: false,
                      label: const Text('100% alapeset'),
                      selected: !_allow200Weight,
                      onSelected: (_) {
                        setState(() {
                          _allow200Weight = false;
                          _prefs = _prefs.copyWith(calcAllow200Weight: false);
                        });
                        widget.onPrefsChanged?.call(_prefs);
                      },
                    ),
                    ChoiceChip(
                      showCheckmark: false,
                      label: const Text('200% témazáró engedélyezése'),
                      selected: _allow200Weight,
                      onSelected: (_) {
                        setState(() {
                          _allow200Weight = true;
                          _prefs = _prefs.copyWith(calcAllow200Weight: true);
                        });
                        widget.onPrefsChanged?.call(_prefs);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (currentAvg != null &&
                          currentAvg >= targetTier.minAverage)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            'Már elérted a(z) ${targetTier.rangeLabel} ösztöndíj sávot (${currentAvg.toStringAsFixed(2)})!',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      else if (recommendations.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            'Válassz sávot vagy szerezz további jegyeket az optimalizáláshoz.',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      else ...[
                        Text(
                          'Stratégiai utak a(z) ${targetTier.rangeLabel} sávhoz (csak az összesített átlag számít):',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...recommendations.map((rec) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: theme.dividerColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        rec.title,
                                        style:
                                            theme.textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primary
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${rec.countNeeded}x 5-ös • +${rec.globalBoost.toStringAsFixed(2)} átlag',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  rec.explanation,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.78),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Detailed view showing all grades for a single selected subject with matching
/// Hero header, animated counter rollups, Subject-level Szellemjegy Számoló,
/// and per-subject customization (custom name, teacher rename, custom color,
/// and custom rounding thresholds).
class SubjectGradesDetailScreen extends StatefulWidget {
  final SubjectGradeSummary summary;
  final List<SubjectGradeSummary> allSubjects;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs>? onPrefsChanged;

  const SubjectGradesDetailScreen({
    super.key,
    required this.summary,
    this.allSubjects = const [],
    required this.prefs,
    this.onPrefsChanged,
  });

  @override
  State<SubjectGradesDetailScreen> createState() =>
      _SubjectGradesDetailScreenState();
}

class _SubjectGradesDetailScreenState extends State<SubjectGradesDetailScreen> {
  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');
  final List<GhostGrade> _ghostGrades = [];
  bool _showGhostSimulator = false;
  int _selectedWeight = 100;
  int _targetGrade = 5;
  late UserProfilePrefs _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefs;
    final avg = widget.summary.weightedAverage ?? 3.0;
    final currentRounded = _prefs.evaluateSubjectRoundedGrade(
      avg,
      widget.summary.heroId,
      widget.summary.subjectName,
    );
    _targetGrade = (currentRounded < 5) ? (currentRounded + 1) : 5;
  }

  @override
  void didUpdateWidget(covariant SubjectGradesDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prefs = widget.prefs;
  }

  void _updatePrefs(UserProfilePrefs next) {
    setState(() => _prefs = next);
    widget.onPrefsChanged?.call(next);
  }

  void _addGhost(int val) {
    setState(() {
      _ghostGrades.add(
        GhostGrade(value: val, weightPercentage: _selectedWeight),
      );
    });
  }

  Future<void> _openEditGhostDialog(int index) async {
    if (index < 0 || index >= _ghostGrades.length) return;
    HapticFeedback.selectionClick();
    final current = _ghostGrades[index];
    var draftValue = current.value;
    var draftWeight = current.weightPercentage;

    await showSoftBlurDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final theme = Theme.of(ctx);
            final scheme = theme.colorScheme;
            return AlertDialog(
              title: const Text('Szellemjegy szerkesztése'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Érdemjegy',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [1, 2, 3, 4, 5].map((v) {
                      final selected = draftValue == v;
                      final c = OledTheme.gradeColor(v, _prefs);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => setDialogState(() => draftValue = v),
                            child: Container(
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? c
                                    : c.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: c.withValues(alpha: 0.75),
                                ),
                              ),
                              child: Text(
                                '$v',
                                style: TextStyle(
                                  color: selected ? Colors.white : c,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Súly',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [50, 100, 200].map((w) {
                      final selected = draftWeight == w;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => setDialogState(() => draftWeight = w),
                            child: Container(
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? scheme.primary
                                    : scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '$w%',
                                style: TextStyle(
                                  color: selected
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (index < _ghostGrades.length) {
                        _ghostGrades.removeAt(index);
                      }
                    });
                    Navigator.of(dialogCtx).pop();
                  },
                  child: Text(
                    'Törlés',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Mégse'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      if (index < _ghostGrades.length) {
                        _ghostGrades[index] = GhostGrade(
                          value: draftValue,
                          weightPercentage: draftWeight,
                        );
                      }
                    });
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('Mentés'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openScholarshipTargetPicker(double? baseOverallAvg) async {
    HapticFeedback.lightImpact();
    final resolved = SubjectGradeSummary.resolveScholarshipTarget(
      baseOverallAvg,
      _prefs,
    );
    var selectedIdx = resolved.tierIndex;
    final chosenTierIdx = await showSoftBlurDialog<int>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final scheme = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: const Text('Ösztöndíj célátlag kiválasztása'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(ScholarshipTier.tiers.length, (idx) {
                  final tier = ScholarshipTier.tiers[idx];
                  final isSel = selectedIdx == idx;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setDialogState(() => selectedIdx = idx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? scheme.primary.withValues(alpha: 0.16)
                              : scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSel
                                ? scheme.primary
                                : scheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cél: ${tier.minAverage.toStringAsFixed(2)} (${tier.rangeLabel})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    tier.title,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSel)
                              Icon(Icons.check_circle_rounded,
                                  color: scheme.primary),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Mégse'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(selectedIdx),
                  child: const Text('Alkalmaz'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || chosenTierIdx == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tier = ScholarshipTier.tiers[chosenTierIdx];
      _updatePrefs(
        _prefs.withExtras({
          'scholarshipTargetTierIdx': chosenTierIdx,
          'scholarshipTargetAverage': tier.minAverage,
        }),
      );
    });
  }

  Future<void> _openSubjectCustomizationModal() async {
    HapticFeedback.lightImpact();
    final subjectKey = widget.summary.heroId;
    final currentCustomName =
        _prefs.subjectCustomNames[subjectKey] ??
            _prefs.subjectCustomNames[widget.summary.subjectName] ??
            '';
    final primaryTeacher = widget.summary.grades.isNotEmpty
        ? widget.summary.grades.first.teacher.trim()
        : '';
    final currentTeacherRename = primaryTeacher.isNotEmpty
        ? (_prefs.teacherCustomNames[primaryTeacher] ?? '')
        : '';
    final currentRounding = _prefs.roundingForSubject(
      subjectKey,
      widget.summary.subjectName,
    );
    final selectedColor = _prefs.subjectCustomColors[subjectKey] ??
        _prefs.subjectCustomColors[widget.summary.subjectName];

    final result = await showModalBottomSheet<_SubjectCustomizationResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: resolveSoftBlurBarrierColor(context, prefs: _prefs),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 250),
        reverseDuration: Duration(milliseconds: 230),
      ),
      builder: (sheetContext) {
        return _SubjectCustomizationSheet(
          prefs: _prefs,
          subjectName: widget.summary.subjectName,
          primaryTeacher: primaryTeacher,
          initialCustomName: currentCustomName,
          initialTeacherRename: currentTeacherRename,
          initialRounding: currentRounding,
          defaultRounding: _prefs.roundingConfig,
          initialColor: selectedColor,
        );
      },
    );

    if (!mounted || result == null) return;
    // Defer provider/inherited theme mutations until the modal OverlayEntry
    // deactivation frame has fully completed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applySubjectCustomizationResult(
        result,
        subjectKey: subjectKey,
        primaryTeacher: primaryTeacher,
      );
    });
  }

  void _applySubjectCustomizationResult(
    _SubjectCustomizationResult result, {
    required String subjectKey,
    required String primaryTeacher,
  }) {
    final nextSubjNames = Map<String, String>.from(_prefs.subjectCustomNames);
    if (result.customSubjectName.isEmpty) {
      nextSubjNames.remove(subjectKey);
      nextSubjNames.remove(widget.summary.subjectName);
    } else {
      nextSubjNames[subjectKey] = result.customSubjectName;
      nextSubjNames[widget.summary.subjectName] = result.customSubjectName;
    }

    final nextTeacherNames =
        Map<String, String>.from(_prefs.teacherCustomNames);
    if (primaryTeacher.isNotEmpty) {
      if (result.customTeacherName.isEmpty) {
        nextTeacherNames.remove(primaryTeacher);
      } else {
        nextTeacherNames[primaryTeacher] = result.customTeacherName;
      }
    }

    final nextSubjColors = Map<String, int>.from(_prefs.subjectCustomColors);
    if (result.selectedColor == null) {
      nextSubjColors.remove(subjectKey);
      nextSubjColors.remove(widget.summary.subjectName);
    } else {
      nextSubjColors[subjectKey] = result.selectedColor!;
    }

    final nextSubjRounding = Map<String, GradeRoundingConfig>.from(
      _prefs.subjectRoundingOverrides,
    );
    nextSubjRounding[subjectKey] = result.rounding;

    _updatePrefs(
      _prefs.copyWith(
        subjectCustomNames: nextSubjNames,
        teacherCustomNames: nextTeacherNames,
        subjectCustomColors: nextSubjColors,
        subjectRoundingOverrides: nextSubjRounding,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomSafePadding = MediaQuery.of(context).padding.bottom + 48;

    final subjectKey = widget.summary.heroId;
    final subjectRounding = _prefs.roundingForSubject(
      subjectKey,
      widget.summary.subjectName,
    );
    final displaySubjectName = _prefs.resolveSubjectName(
      widget.summary.subjectName,
      widget.summary.subjectUid,
    );
    final customSubjColor = _prefs.customColorForSubject(
      subjectKey,
      widget.summary.subjectName,
    );

    final baseAvg = widget.summary.weightedAverage ??
        SubjectGradeSummary.computeWeightedAverage(widget.summary.grades);
    final simAvg = SubjectGradeSummary.computeWeightedAverage(
      widget.summary.grades,
      _ghostGrades,
    );
    final activeAvg = _ghostGrades.isNotEmpty ? simAvg : baseAvg;
    final roundedStanding = activeAvg != null
        ? subjectRounding.evaluateRoundedGrade(activeAvg)
        : null;
    final avgColor = customSubjColor ??
        (roundedStanding != null
            ? OledTheme.gradeColor(roundedStanding, _prefs)
            : scheme.primary);

    final effectiveSubjects = widget.allSubjects.isNotEmpty
        ? widget.allSubjects
        : [widget.summary];
    final baseOverallAvg = SubjectGradeSummary.computeOverallSubjectAverage(
      effectiveSubjects,
      prefs: _prefs,
      allow200Weight: _prefs.calcAllow200Weight,
    );
    final simSubjectAvgForOverall = _ghostGrades.isEmpty
        ? null
        : SubjectGradeSummary.computeWeightedAverage(
            widget.summary.grades,
            _ghostGrades,
            _prefs.calcAllow200Weight,
          );
    final simOverallAvg = _ghostGrades.isEmpty
        ? baseOverallAvg
        : SubjectGradeSummary.computeSimulatedOverallAverage(
            effectiveSubjects,
            simulatedSubject: widget.summary,
            simulatedSubjectRawAverage: simSubjectAvgForOverall,
            prefs: _prefs,
            allow200Weight: _prefs.calcAllow200Weight,
          );
    final activeOverallAvg = _ghostGrades.isNotEmpty ? simOverallAvg : baseOverallAvg;
    final overallDelta = (baseOverallAvg != null && activeOverallAvg != null)
        ? (activeOverallAvg - baseOverallAvg)
        : null;
    final subjectDelta = (baseAvg != null && activeAvg != null)
        ? (activeAvg - baseAvg)
        : null;
    final scholarshipTarget = SubjectGradeSummary.resolveScholarshipTarget(
      baseOverallAvg,
      _prefs,
    );

    final targetThreshold = subjectRounding.thresholdForGrade(_targetGrade);
    final neededPlan100 = SubjectGradeSummary.calculate100PercentNeededPlan(
      currentGrades: widget.summary.grades,
      ghostGrades: _ghostGrades,
      targetThreshold: targetThreshold,
      allow200Weight: _prefs.calcAllow200Weight,
    );

    final subjectHeroTag = widget.summary.uniqueHeroTag;

    return Scaffold(
      appBar: AppBar(
        title: Text(displaySubjectName),
        actions: [
          IconButton(
            tooltip: 'Tantárgy testreszabása',
            onPressed: _openSubjectCustomizationModal,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(top: 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Hero(
                      tag: subjectHeroTag,
                      child: Material(
                        type: MaterialType.transparency,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color,
                            borderRadius: OledTheme.largeRadius,
                            border: Border.all(
                              color: avgColor.withValues(alpha: 0.6),
                              width: 1.4,
                            ),
                          ),
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 240),
                                  width: 66,
                                  height: 66,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: avgColor,
                                    borderRadius: OledTheme.badgeRadius,
                                  ),
                                  child: activeAvg != null
                                      ? AnimatedNumberText(
                                          value: activeAvg,
                                          fractionDigits: 2,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        )
                                      : Text(
                                          '–',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displaySubjectName,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        roundedStanding != null
                                            ? '$roundedStanding (${widget.summary.grades.length} db jegy)'
                                            : '${widget.summary.grades.length} rögzített értékelés',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.72),
                                        ),
                                      ),
                                      if (_ghostGrades.isNotEmpty &&
                                          baseAvg != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Eredeti átlag: ${baseAvg.toStringAsFixed(2)} • +${_ghostGrades.length} szellemjegy',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
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
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSubjectSimulatorCard(
                    theme,
                    scheme,
                    displaySubjectName: displaySubjectName,
                    activeSubjectAvg: activeAvg,
                    roundedSubjectStanding: roundedStanding,
                    subjectDelta: subjectDelta,
                    baseOverallAvg: baseOverallAvg,
                    activeOverallAvg: activeOverallAvg,
                    overallDelta: overallDelta,
                    scholarshipTarget: scholarshipTarget,
                    targetThreshold: targetThreshold,
                    neededPlan100: neededPlan100,
                  ).staggeredEntrance(0),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Rögzített jegyek (koppints a részletekért)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openSubjectCustomizationModal,
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: const Text('Testreszabás'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, bottomSafePadding),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, idx) {
                  final grade = widget.summary.grades[idx];
                  return RepaintBoundary(
                    child: _buildGradeDetailCard(context, theme, scheme, grade)
                        .staggeredEntrance(idx < 8 ? idx + 1 : 8),
                  );
                },
                childCount: widget.summary.grades.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeltaPill(
    ThemeData theme,
    ColorScheme scheme,
    double? delta,
  ) {
    final val = delta ?? 0.0;
    final isDark = theme.brightness == Brightness.dark;
    final isPositive = val > 0.0049;
    final isNegative = val < -0.0049;
    final color = isPositive
        ? (isDark ? Colors.greenAccent : Colors.green.shade700)
        : isNegative
            ? (isDark ? Colors.redAccent : Colors.red.shade700)
            : scheme.onSurface.withValues(alpha: 0.65);
    final label = isPositive
        ? '+${val.toStringAsFixed(2)}'
        : isNegative
            ? val.toStringAsFixed(2)
            : '0.00';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _buildSubjectSimulatorCard(
    ThemeData theme,
    ColorScheme scheme, {
    required String displaySubjectName,
    required double? activeSubjectAvg,
    required int? roundedSubjectStanding,
    required double? subjectDelta,
    required double? baseOverallAvg,
    required double? activeOverallAvg,
    required double? overallDelta,
    required ({double targetAverage, ScholarshipTier? tier, int tierIndex})
        scholarshipTarget,
    required double targetThreshold,
    required ({
      bool isReached,
      ({int gradeValue, int count})? lowestOption,
      ({int gradeValue, int count})? fasterFiveOption,
    }) neededPlan100,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final targetAvg = scholarshipTarget.targetAverage;
    final isScholarshipReached =
        activeOverallAvg != null && (activeOverallAvg + 1e-6) >= targetAvg;
    final scholarshipGap = activeOverallAvg != null
        ? (targetAvg - activeOverallAvg).clamp(0.0, 5.0)
        : targetAvg;
    final scholarshipAccent = isScholarshipReached
        ? (isDark ? Colors.greenAccent : Colors.green.shade700)
        : (isDark ? Colors.amberAccent : Colors.orange.shade800);
    final scholarshipStatusText = isScholarshipReached
        ? 'Elérted a kitűzött ${targetAvg.toStringAsFixed(2)}-es ösztöndíj célt!'
        : 'Cél: ${targetAvg.toStringAsFixed(2)} • Még +${scholarshipGap.toStringAsFixed(2)} kell';
    final overallColor = activeOverallAvg != null
        ? OledTheme.averageColor(activeOverallAvg, _prefs)
        : scheme.primary;
    final subjectTileColor = roundedSubjectStanding != null
        ? OledTheme.gradeColor(roundedSubjectStanding, _prefs)
        : scheme.primary;

    Widget pill<T>({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      Color? accent,
    }) {
      final color = accent ?? scheme.primary;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected
                    ? Colors.white
                    : scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      );
    }

    Widget segmented(List<Widget> children) => Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(children: children),
        );

    final lowestOption = neededPlan100.lowestOption;
    final fasterFive = neededPlan100.fasterFiveOption;
    final String needText;
    if (neededPlan100.isReached) {
      needText =
          'Elérted a kitűzött jegyet: $_targetGrade (küszöb: ${targetThreshold.toStringAsFixed(2)})!';
    } else if (lowestOption != null && fasterFive != null) {
      needText =
          'Még ${fasterFive.count} db ${SubjectGradeSummary.hungarianGradeLabel(fasterFive.gradeValue)} (100%) vagy ${lowestOption.count} db ${SubjectGradeSummary.hungarianGradeLabel(lowestOption.gradeValue)} (100%) kell (cél: ${targetThreshold.toStringAsFixed(2)})';
    } else if (lowestOption != null) {
      needText =
          'Még ${lowestOption.count} db ${SubjectGradeSummary.hungarianGradeLabel(lowestOption.gradeValue)} (100%) kell (cél: ${targetThreshold.toStringAsFixed(2)})';
    } else {
      needText =
          'A célátlag (${targetThreshold.toStringAsFixed(2)}) 100%-os jegyekkel nem érhető el belátható számmal.';
    }

    final showImpactSummary = _showGhostSimulator || _ghostGrades.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh.withValues(alpha: 0.45),
                    borderRadius: OledTheme.badgeRadius,
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.65),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.flag_circle_rounded,
                            size: 18,
                            color: OledTheme.gradeColor(_targetGrade, _prefs),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cél érdemjegy',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            'Küszöb: ${targetThreshold.toStringAsFixed(2)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      segmented([
                        for (final g in [2, 3, 4, 5])
                          pill<int>(
                            label: '$g',
                            selected: _targetGrade == g,
                            accent: OledTheme.gradeColor(g, _prefs),
                            onTap: () => setState(() => _targetGrade = g),
                          ),
                      ]),
                      const SizedBox(height: 10),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          needText,
                          key: ValueKey(needText),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: neededPlan100.isReached
                                ? (isDark
                                    ? Colors.greenAccent
                                    : Colors.green.shade700)
                                : scheme.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TactileBounce(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() =>
                              _showGhostSimulator = !_showGhostSimulator);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: showImpactSummary
                                ? scheme.primary.withValues(alpha: 0.14)
                                : scheme.surfaceContainerHigh
                                    .withValues(alpha: 0.45),
                            borderRadius: OledTheme.badgeRadius,
                            border: Border.all(
                              color: showImpactSummary
                                  ? scheme.primary.withValues(alpha: 0.5)
                                  : theme.dividerColor.withValues(alpha: 0.65),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_fix_high_rounded,
                                size: 18,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _ghostGrades.isEmpty
                                      ? 'Szellemjegyek'
                                      : 'Szellemjegyek (${_ghostGrades.length})',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: showImpactSummary
                                        ? scheme.primary
                                        : scheme.onSurface,
                                  ),
                                ),
                              ),
                              AnimatedRotation(
                                turns: _showGhostSimulator ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_ghostGrades.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() => _ghostGrades.clear());
                        },
                        child: const Text('Alaphelyzet'),
                      ),
                    ],
                  ],
                ),
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: !showImpactSummary
                        ? const SizedBox(width: double.infinity)
                        : AnimatedOpacity(
                            opacity: showImpactSummary ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 12),
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: subjectTileColor.withValues(
                                                alpha: 0.1),
                                            borderRadius: OledTheme.badgeRadius,
                                            border: Border.all(
                                              color: subjectTileColor.withValues(
                                                  alpha: 0.35),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Tantárgyi átlag',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: scheme.onSurface
                                                      .withValues(alpha: 0.7),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Flexible(
                                                    child: activeSubjectAvg !=
                                                            null
                                                        ? AnimatedNumberText(
                                                            value:
                                                                activeSubjectAvg,
                                                            fractionDigits: 2,
                                                            style: theme
                                                                .textTheme
                                                                .titleLarge
                                                                ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              color:
                                                                  subjectTileColor,
                                                            ),
                                                          )
                                                        : Text(
                                                            '–',
                                                            style: theme
                                                                .textTheme
                                                                .titleLarge
                                                                ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                            ),
                                                          ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  _buildDeltaPill(
                                                    theme,
                                                    scheme,
                                                    _ghostGrades.isEmpty
                                                        ? 0.0
                                                        : subjectDelta,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: overallColor.withValues(
                                                alpha: 0.1),
                                            borderRadius: OledTheme.badgeRadius,
                                            border: Border.all(
                                              color: overallColor.withValues(
                                                  alpha: 0.35),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Összesített tanulmányi átlag',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: scheme.onSurface
                                                      .withValues(alpha: 0.7),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Flexible(
                                                    child: activeOverallAvg !=
                                                            null
                                                        ? AnimatedNumberText(
                                                            value:
                                                                activeOverallAvg,
                                                            fractionDigits: 2,
                                                            style: theme
                                                                .textTheme
                                                                .titleLarge
                                                                ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              color:
                                                                  overallColor,
                                                            ),
                                                          )
                                                        : Text(
                                                            '–',
                                                            style: theme
                                                                .textTheme
                                                                .titleLarge
                                                                ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                            ),
                                                          ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  _buildDeltaPill(
                                                    theme,
                                                    scheme,
                                                    _ghostGrades.isEmpty
                                                        ? 0.0
                                                        : overallDelta,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TactileBounce(
                                  onTap: () => _openScholarshipTargetPicker(
                                      baseOverallAvg),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scholarshipAccent.withValues(
                                          alpha: 0.14),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: scholarshipAccent.withValues(
                                            alpha: 0.45),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isScholarshipReached
                                              ? Icons.verified_rounded
                                              : Icons.flag_rounded,
                                          size: 18,
                                          color: scholarshipAccent,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    'Ösztöndíj cél',
                                                    style: theme
                                                        .textTheme.labelSmall
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: scholarshipAccent,
                                                    ),
                                                  ),
                                                  if (scholarshipTarget.tier !=
                                                      null) ...[
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        '• ${scholarshipTarget.tier!.rangeLabel} (${scholarshipTarget.tier!.title})',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme.textTheme
                                                            .labelSmall
                                                            ?.copyWith(
                                                          color: scheme
                                                              .onSurface
                                                              .withValues(
                                                                  alpha: 0.68),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                scholarshipStatusText,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: scholarshipAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.tune_rounded,
                                          size: 16,
                                          color: scholarshipAccent.withValues(
                                              alpha: 0.8),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: !_showGhostSimulator
                        ? const SizedBox(width: double.infinity)
                        : AnimatedOpacity(
                            opacity: _showGhostSimulator ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 14),
                                Text(
                                  'Szellemjegy súlya',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                segmented([
                                  for (final w in [50, 100, 200])
                                    pill<int>(
                                      label: '$w%',
                                      selected: _selectedWeight == w,
                                      onTap: () =>
                                          setState(() => _selectedWeight = w),
                                    ),
                                ]),
                                const SizedBox(height: 12),
                                Row(
                                  children: [1, 2, 3, 4, 5].map((val) {
                                    final color =
                                        OledTheme.gradeColor(val, _prefs);
                                    return Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 3),
                                        child: TactileBounce(
                                          onTap: () => _addGhost(val),
                                          child: Container(
                                            height: 38,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color:
                                                  color.withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                  color: color.withValues(
                                                      alpha: 0.7)),
                                            ),
                                            child: Text(
                                              '+$val',
                                              style: TextStyle(
                                                color: color,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _ghostGrades.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: EdgeFadeHorizontalScroll(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      spacing: 6,
                      children: List.generate(_ghostGrades.length, (idx) {
                        final g = _ghostGrades[idx];
                        final color = OledTheme.gradeColor(g.value, _prefs);
                        return TweenAnimationBuilder<double>(
                          key: ObjectKey(g),
                          tween: Tween(begin: 0.6, end: 1.0),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutBack,
                          builder: (context, t, child) => Transform.scale(
                            scale: t,
                            child: child,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TactileBounce(
                                  onTap: () => _openEditGhostDialog(idx),
                                  child: Text(
                                    '${g.value} · ${g.weightPercentage}%',
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    setState(() => _ghostGrades.removeAt(idx));
                                  },
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
          ),
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
    final badgeColor = OledTheme.gradeColor(grade.numericValue, _prefs);
    final badgeText = grade.numericValue?.toString() ??
        grade.shortStrValue ??
        (grade.strValue.isNotEmpty ? grade.strValue.substring(0, 1) : '?');

    final weightText = grade.weightPercentage != null
        ? '${grade.weightPercentage}%'
        : '100%';
    final modeText = grade.mode?.description;
    final teacherDisplay = _prefs.resolveTeacherName(grade.teacher);
    final heroTag = 'subj_grade_${grade.uid}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () => showGradeInspectionModal(
          context,
          grade,
          heroTag: heroTag,
          prefs: _prefs,
        ),
        child: SoftGlassCard(
          prefs: _prefs,
          padding: const EdgeInsets.all(16),
          borderRadius: OledTheme.cardRadius,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: heroTag,
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
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
                          _dateFormat.format(grade.recordDate.toLocal()),
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
                            teacherDisplay,
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

class _SubjectCustomizationResult {
  final String customSubjectName;
  final String customTeacherName;
  final int? selectedColor;
  final GradeRoundingConfig rounding;

  const _SubjectCustomizationResult({
    required this.customSubjectName,
    required this.customTeacherName,
    required this.selectedColor,
    required this.rounding,
  });
}

/// Modal bottom sheet for customizing a single subject's alias, teacher name,
/// accent color, and per-subject rounding thresholds.
///
/// Owns its [TextEditingController]s and [FocusNode]s in [State] so they are
/// only disposed after the route has finished deactivating.
class _SubjectCustomizationSheet extends StatefulWidget {
  final UserProfilePrefs prefs;
  final String subjectName;
  final String primaryTeacher;
  final String initialCustomName;
  final String initialTeacherRename;
  final GradeRoundingConfig initialRounding;
  final GradeRoundingConfig defaultRounding;
  final int? initialColor;

  const _SubjectCustomizationSheet({
    required this.prefs,
    required this.subjectName,
    required this.primaryTeacher,
    required this.initialCustomName,
    required this.initialTeacherRename,
    required this.initialRounding,
    required this.defaultRounding,
    required this.initialColor,
  });

  @override
  State<_SubjectCustomizationSheet> createState() =>
      _SubjectCustomizationSheetState();
}

class _SubjectCustomizationSheetState
    extends State<_SubjectCustomizationSheet> {
  late final TextEditingController _subjController;
  late final TextEditingController _teacherController;
  late final FocusNode _subjFocusNode;
  late final FocusNode _teacherFocusNode;
  late double _threshold5;
  late double _threshold4;
  late double _threshold3;
  late double _threshold2;
  int? _selectedColor;

  @override
  void initState() {
    super.initState();
    _subjController = TextEditingController(text: widget.initialCustomName);
    _teacherController = TextEditingController(
      text: widget.initialTeacherRename,
    );
    _subjFocusNode = FocusNode();
    _teacherFocusNode = FocusNode();
    _threshold5 = widget.initialRounding.threshold5;
    _threshold4 = widget.initialRounding.threshold4;
    _threshold3 = widget.initialRounding.threshold3;
    _threshold2 = widget.initialRounding.threshold2;
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _subjFocusNode.dispose();
    _teacherFocusNode.dispose();
    _subjController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  void _saveAndClose() {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = _SubjectCustomizationResult(
      customSubjectName: _subjController.text.trim(),
      customTeacherName: _teacherController.text.trim(),
      selectedColor: _selectedColor,
      rounding: GradeRoundingConfig(
        threshold5: double.parse(_threshold5.toStringAsFixed(2)),
        threshold4: double.parse(_threshold4.toStringAsFixed(2)),
        threshold3: double.parse(_threshold3.toStringAsFixed(2)),
        threshold2: double.parse(_threshold2.toStringAsFixed(2)),
      ),
    );
    Navigator.of(context).pop(result);
  }

  Widget _buildThresholdRow(
    ThemeData theme,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    final clamped = value.clamp(min, max);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                clamped.toStringAsFixed(2),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
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
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: LiquidGlassSurface(
          prefs: widget.prefs,
          highContrastExpanded: true,
          contentOpacityAnimation: ModalRoute.of(context)?.animation,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      const SizedBox(height: 16),
                      Text(
                        'Tantárgy testreszabása',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _subjController,
                        focusNode: _subjFocusNode,
                        decoration: InputDecoration(
                          labelText: 'Tantárgy saját elnevezése',
                          hintText: widget.subjectName,
                          prefixIcon: const Icon(Icons.edit_rounded),
                        ),
                      ),
                      if (widget.primaryTeacher.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _teacherController,
                          focusNode: _teacherFocusNode,
                          decoration: InputDecoration(
                            labelText:
                                'Tanár átnevezése (${widget.primaryTeacher})',
                            hintText: widget.primaryTeacher,
                            prefixIcon: const Icon(Icons.person_rounded),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Egyedi tantárgy szín:',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                EdgeFadeHorizontalScroll(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Automatikus'),
                      selected: _selectedColor == null,
                      onSelected: (_) => setState(() => _selectedColor = null),
                    ),
                    ...OledTheme.gradeColorPalette.map((c) {
                      final argb = c.toARGB32();
                      final isSel = _selectedColor == argb;
                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => setState(() => _selectedColor = argb),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSel
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              width: 2.2,
                            ),
                          ),
                          child: isSel
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tantárgyi kerekítési határok:',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _threshold5 = widget.defaultRounding.threshold5;
                                _threshold4 = widget.defaultRounding.threshold4;
                                _threshold3 = widget.defaultRounding.threshold3;
                                _threshold2 = widget.defaultRounding.threshold2;
                              });
                            },
                            child: const Text('Alapértelmezett'),
                          ),
                        ],
                      ),
                      _buildThresholdRow(
                        theme,
                        '5 (Jeles) küszöb',
                        _threshold5,
                        4.00,
                        4.95,
                        (v) => setState(() => _threshold5 = v),
                      ),
                      _buildThresholdRow(
                        theme,
                        '4 (Jó) küszöb',
                        _threshold4,
                        3.00,
                        3.95,
                        (v) => setState(() => _threshold4 = v),
                      ),
                      _buildThresholdRow(
                        theme,
                        '3 (Közepes) küszöb',
                        _threshold3,
                        2.00,
                        2.95,
                        (v) => setState(() => _threshold3 = v),
                      ),
                      _buildThresholdRow(
                        theme,
                        '2 (Elégséges) küszöb',
                        _threshold2,
                        1.10,
                        2.20,
                        (v) => setState(() => _threshold2 = v),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _saveAndClose,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Mentés'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
