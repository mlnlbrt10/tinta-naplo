import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';

/// Reactive controller managing [UserProfilePrefs] with synchronous listener
/// notification and immediate `SharedPreferences` + serialized secure storage
/// persistence.
class SettingsProvider extends ChangeNotifier {
  static const String completedHomeworkPrefsKey = 'completed_homework_ids_v1';

  final TokenStorageService _storage;
  UserProfilePrefs _prefs;
  Set<String> _completedHomeworkIds;
  Future<void> _saveQueue = Future<void>.value();

  SettingsProvider({
    UserProfilePrefs initialPrefs = const UserProfilePrefs(),
    Set<String> initialCompletedHomeworkIds = const <String>{},
    TokenStorageService? storage,
  })  : _prefs = initialPrefs,
        _completedHomeworkIds = Set<String>.from(initialCompletedHomeworkIds),
        _storage = storage ?? const TokenStorageService() {
    UserProfilePrefs.syncActiveGlobals(_prefs);
  }

  UserProfilePrefs get prefs => _prefs;
  Set<String> get completedHomeworkIds =>
      Set<String>.unmodifiable(_completedHomeworkIds);

  static String homeworkCompletionKey(Homework homework) {
    final uid = homework.uid.trim();
    if (uid.isNotEmpty) return uid;
    return '${homework.subject.uid}_${homework.dueDate.toUtc().toIso8601String()}_${homework.description.hashCode}';
  }

  static Future<Set<String>> loadCompletedHomeworkIdsFromPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(completedHomeworkPrefsKey);
      if (list == null) return <String>{};
      return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> saveCompletedHomeworkIdsToPrefs(Set<String> ids) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final sorted = ids.toList()..sort();
      await sp.setStringList(completedHomeworkPrefsKey, sorted);
    } catch (_) {}
  }

  bool isHomeworkCompleted(Homework homework) =>
      _completedHomeworkIds.contains(homeworkCompletionKey(homework));

  bool isHomeworkKeyCompleted(String rawKey) {
    final key = rawKey.trim();
    return key.isNotEmpty && _completedHomeworkIds.contains(key);
  }

  /// Loads persisted preferences from [TokenStorageService] (`SharedPreferences`
  /// primary mirror with `FlutterSecureStorage` migration fallback).
  Future<UserProfilePrefs> load() async {
    final loaded = await _storage.loadProfilePrefs();
    final completed = await loadCompletedHomeworkIdsFromPrefs();
    _prefs = loaded;
    if (completed.isNotEmpty) {
      _completedHomeworkIds = completed;
    }
    UserProfilePrefs.syncActiveGlobals(loaded);
    notifyListeners();
    return loaded;
  }

  /// Synchronously toggles a homework completion key, notifies listeners
  /// right away, and persists `completedHomeworkIds` to `SharedPreferences`.
  Future<void> setHomeworkKeyCompleted(String rawKey, bool completed) {
    final key = rawKey.trim();
    if (key.isEmpty) return Future<void>.value();
    final next = Set<String>.from(_completedHomeworkIds);
    final changed = completed ? next.add(key) : next.remove(key);
    if (!changed) return Future<void>.value();

    _completedHomeworkIds = next;
    notifyListeners();

    final queued = _saveQueue.then((_) async {
      await saveCompletedHomeworkIdsToPrefs(next);
    }).catchError((_) {});
    _saveQueue = queued;
    return queued;
  }

  Future<bool> toggleHomeworkKeyCompleted(String rawKey) async {
    final key = rawKey.trim();
    if (key.isEmpty) return false;
    final nextState = !_completedHomeworkIds.contains(key);
    await setHomeworkKeyCompleted(key, nextState);
    return nextState;
  }

  Future<void> setHomeworkCompleted(Homework homework, bool completed) =>
      setHomeworkKeyCompleted(homeworkCompletionKey(homework), completed);

  Future<bool> toggleHomeworkCompleted(Homework homework) =>
      toggleHomeworkKeyCompleted(homeworkCompletionKey(homework));

  /// Synchronously updates in-memory state, notifies all listeners immediately,
  /// writes to `SharedPreferences` right away, and serializes full persistence.
  Future<void> updatePrefs(UserProfilePrefs nextPrefs) {
    _prefs = nextPrefs;
    UserProfilePrefs.syncActiveGlobals(nextPrefs);
    notifyListeners();

    final queued = _saveQueue.then((_) async {
      await _storage.saveProfilePrefs(nextPrefs);
    }).catchError((_) {});
    _saveQueue = queued;
    return queued;
  }

  /// Convenience transform helper over current [prefs].
  Future<void> updateWith(
    UserProfilePrefs Function(UserProfilePrefs current) transform,
  ) {
    return updatePrefs(transform(_prefs));
  }

  /// Persists custom timetable period number badge color (`null` = theme default).
  Future<void> setTimetablePeriodColor(int? argb) =>
      updateWith((p) => p.withTimetablePeriodColor(argb));

  /// Waits for any in-flight persistence writes to finish (useful in tests).
  Future<void> flushPersistence() => _saveQueue;
}

/// Reactive theme controller derived from [SettingsProvider].
class ThemeProvider extends ChangeNotifier {
  final SettingsProvider _settings;
  _ThemeSnapshot _snapshot;

  ThemeProvider(this._settings)
      : _snapshot = _ThemeSnapshot.fromPrefs(_settings.prefs) {
    _settings.addListener(_handleSettingsChanged);
  }

  UserProfilePrefs get prefs => _settings.prefs;

  AdaptiveContrastTokens get contrastTokens =>
      AdaptiveContrastTokens.resolve(_settings.prefs);
  Color get adaptivePrimaryText => contrastTokens.primaryText;
  Color get adaptiveSecondaryText => contrastTokens.secondaryText;
  Color get adaptiveIconColor => contrastTokens.iconColor;
  Color get adaptiveCardFill => contrastTokens.cardFill;
  Color get adaptiveCardBorder => contrastTokens.cardBorder;

  bool get isLight {
    final preset = BackgroundPresetInfo.resolve(_settings.prefs);
    if (_snapshot.hasAnimatedBackdrop ||
        _snapshot.hasCustomBackdrop ||
        preset.id != 'pure_oled') {
      return contrastTokens.isLightBackdrop;
    }
    return _snapshot.themeStyle == AppThemeStyle.light;
  }

  bool get isDark => !isLight;
  bool get isPureOled =>
      !_snapshot.hasAnimatedBackdrop &&
      !_snapshot.hasCustomBackdrop &&
      _snapshot.themeStyle == AppThemeStyle.oledPureBlack &&
      _snapshot.backgroundPreset == 'pure_oled';
  bool get liquidGlassEnabled => _snapshot.liquidGlassEnabled;
  bool get hasSoftBlur => liquidGlassEnabled;
  LiquidGlassMode get liquidGlassMode => _snapshot.liquidGlassMode;
  AnimatedBackdropPreset get animatedBackdropPreset =>
      _snapshot.animatedBackdropPreset;
  double get cardOpacity => _snapshot.cardOpacity;
  double get cardBlurSigma => _snapshot.cardBlurSigma;
  String get backgroundPreset => _snapshot.backgroundPreset;
  int? get timetablePeriodColorValue => _snapshot.timetablePeriodColorValue;
  Color? get timetablePeriodColor => timetablePeriodColorValue == null
      ? null
      : Color(timetablePeriodColorValue!);

  ThemeData buildLightTheme([ColorScheme? dynamicLight]) {
    return OledTheme.buildTheme(
      prefs: _settings.prefs.copyWith(themeStyle: AppThemeStyle.light),
      dynamicScheme: dynamicLight,
    );
  }

  ThemeData buildDarkTheme([ColorScheme? dynamicDark]) {
    final style = _settings.prefs.themeStyle == AppThemeStyle.light
        ? AppThemeStyle.oledPureBlack
        : _settings.prefs.themeStyle;
    return OledTheme.buildTheme(
      prefs: _settings.prefs.copyWith(themeStyle: style),
      dynamicScheme: dynamicDark,
    );
  }

  void _handleSettingsChanged() {
    final next = _ThemeSnapshot.fromPrefs(_settings.prefs);
    if (next != _snapshot) {
      _snapshot = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);
    super.dispose();
  }
}

class _ThemeSnapshot {
  final AppThemeStyle themeStyle;
  final bool useDynamicColor;
  final int seedColorValue;
  final bool uwuModeEnabled;
  final bool tsundereModeEnabled;
  final bool christmasModeEnabled;
  final String backgroundPreset;
  final bool liquidGlassEnabled;
  final LiquidGlassMode liquidGlassMode;
  final bool hasCustomBackdrop;
  final String? customBackdropPath;
  final double customBackdropDim;
  final double customBackdropLuminance;
  final AnimatedBackdropPreset animatedBackdropPreset;
  final double cardOpacity;

  bool get hasAnimatedBackdrop =>
      animatedBackdropPreset != AnimatedBackdropPreset.off;
  final double cardBlurSigma;
  final Map<int, int> customGradeColors;
  final ModalCloseButtonMode modalCloseMode;
  final int? timetablePeriodColorValue;

  const _ThemeSnapshot({
    required this.themeStyle,
    required this.useDynamicColor,
    required this.seedColorValue,
    required this.uwuModeEnabled,
    required this.tsundereModeEnabled,
    required this.christmasModeEnabled,
    required this.backgroundPreset,
    required this.liquidGlassEnabled,
    required this.liquidGlassMode,
    required this.hasCustomBackdrop,
    required this.customBackdropPath,
    required this.customBackdropDim,
    required this.customBackdropLuminance,
    required this.animatedBackdropPreset,
    required this.cardOpacity,
    required this.cardBlurSigma,
    required this.customGradeColors,
    required this.modalCloseMode,
    this.timetablePeriodColorValue,
  });

  factory _ThemeSnapshot.fromPrefs(UserProfilePrefs p) => _ThemeSnapshot(
        themeStyle: p.themeStyle,
        useDynamicColor: p.useDynamicColor,
        seedColorValue: p.seedColorValue,
        uwuModeEnabled: p.uwuModeEnabled,
        tsundereModeEnabled: p.tsundereModeEnabled,
        christmasModeEnabled: p.christmasModeEnabled,
        backgroundPreset: p.backgroundPreset,
        liquidGlassEnabled: p.liquidGlassEnabled,
        liquidGlassMode: p.liquidGlassMode,
        hasCustomBackdrop: p.hasCustomBackdrop,
        customBackdropPath: p.customBackdropPath,
        customBackdropDim: p.customBackdropDim,
        customBackdropLuminance: p.customBackdropLuminance,
        animatedBackdropPreset: p.animatedBackdropPreset,
        cardOpacity: p.cardOpacity,
        cardBlurSigma: p.cardBlurSigma,
        customGradeColors: p.customGradeColors,
        modalCloseMode: p.modalCloseMode,
        timetablePeriodColorValue: p.timetablePeriodColorValue,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ThemeSnapshot &&
        other.themeStyle == themeStyle &&
        other.useDynamicColor == useDynamicColor &&
        other.seedColorValue == seedColorValue &&
        other.uwuModeEnabled == uwuModeEnabled &&
        other.tsundereModeEnabled == tsundereModeEnabled &&
        other.christmasModeEnabled == christmasModeEnabled &&
        other.backgroundPreset == backgroundPreset &&
        other.liquidGlassEnabled == liquidGlassEnabled &&
        other.liquidGlassMode == liquidGlassMode &&
        other.hasCustomBackdrop == hasCustomBackdrop &&
        other.customBackdropPath == customBackdropPath &&
        other.customBackdropDim == customBackdropDim &&
        other.customBackdropLuminance == customBackdropLuminance &&
        other.animatedBackdropPreset == animatedBackdropPreset &&
        other.cardOpacity == cardOpacity &&
        other.cardBlurSigma == cardBlurSigma &&
        other.modalCloseMode == modalCloseMode &&
        other.timetablePeriodColorValue == timetablePeriodColorValue &&
        mapEquals(other.customGradeColors, customGradeColors);
  }

  @override
  int get hashCode => Object.hash(
        themeStyle,
        useDynamicColor,
        seedColorValue,
        uwuModeEnabled,
        tsundereModeEnabled,
        christmasModeEnabled,
        backgroundPreset,
        liquidGlassEnabled,
        liquidGlassMode,
        hasCustomBackdrop,
        customBackdropPath,
        customBackdropDim,
        customBackdropLuminance,
        animatedBackdropPreset,
        cardOpacity,
        cardBlurSigma,
        modalCloseMode,
        timetablePeriodColorValue,
        customGradeColors.length,
      );
}

/// Reactive commute controller managing MenetrendGO evaluation state.
///
/// Immediately recalculates walking durations & evaluations locally when
/// `walkingSpeedKmh` ("séta tempó") or buffer/favorites change, and suppresses
/// live delay notification spam on settings-driven updates or refreshes.
class CommuteProvider extends ChangeNotifier {
  final SettingsProvider _settings;
  final MenetrendService _menetrendService;

  CommuteEvaluation? _evaluation;
  bool _isLoading = false;
  List<Lesson> _todaysLessons = const <Lesson>[];
  bool _hasLessons = false;
  _CommuteSettingsSnapshot _lastSnapshot;
  int _syncEpoch = 0;

  CommuteProvider(
    this._settings, {
    MenetrendService? menetrendService,
  })  : _menetrendService = menetrendService ?? MenetrendService(),
        _lastSnapshot = _CommuteSettingsSnapshot.fromPrefs(_settings.prefs) {
    _settings.addListener(_handleSettingsChanged);
  }

  CommuteEvaluation? get evaluation => _evaluation;
  bool get isLoading => _isLoading;
  List<Lesson> get todaysLessons => _todaysLessons;
  bool get hasLessons => _hasLessons;

  static bool _hasEvaluationChanged(
    CommuteEvaluation? prev,
    CommuteEvaluation? next,
  ) {
    if (prev == null || next == null) return prev != next;
    return !prev.isMeaningfullyEqual(next) ||
        prev.minutesUntilDeparture != next.minutesUntilDeparture ||
        prev.minutesUntilWalkStart != next.minutesUntilWalkStart;
  }

  void setLessons(List<Lesson> lessons, {DateTime? nowOverride}) {
    _todaysLessons = lessons;
    _hasLessons = true;
    if (_evaluation != null) {
      revalidateForNow(
        nowOverride ?? _evaluation!.now,
        todaysLessons: lessons,
      );
    }
  }

  /// Directly seeds an evaluation (useful in tests or SSR hydration) and notifies listeners.
  void setEvaluationForTesting(CommuteEvaluation? evaluation) {
    _evaluation = evaluation;
    notifyListeners();
  }

  /// Synchronously re-evaluates in-memory commute visibility and trip
  /// eligibility at [now] without requiring a manual pull-to-refresh.
  void revalidateForNow(
    DateTime now, {
    List<Lesson>? todaysLessons,
  }) {
    if (todaysLessons != null) {
      _todaysLessons = todaysLessons;
      _hasLessons = true;
    }
    final current = _evaluation;
    if (current == null) return;

    final next = MenetrendService.filterVisibleEvaluation(
      evaluation: current,
      todaysLessons: _hasLessons ? _todaysLessons : null,
      prefs: _settings.prefs,
      now: now,
    );

    if (next == null) {
      _evaluation = null;
      _isLoading = false;
      notifyListeners();
      unawaited(MenetrendService.cancelAlarms());
      return;
    }

    if (_hasEvaluationChanged(current, next)) {
      _evaluation = next;
      notifyListeners();
    }
  }

  Future<void> syncLive({
    List<Lesson>? todaysLessons,
    bool allowDelayNotifications = true,
    DateTime? nowOverride,
  }) async {
    if (todaysLessons != null) {
      _todaysLessons = todaysLessons;
      _hasLessons = true;
    }
    final prefs = _settings.prefs;
    if (!prefs.transitCardEnabled || !prefs.transitConfigured) {
      ++_syncEpoch;
      if (_evaluation != null || _isLoading) {
        _evaluation = null;
        _isLoading = false;
        notifyListeners();
      }
      unawaited(MenetrendService.cancelAlarms());
      return;
    }

    final effectiveNow = (nowOverride ?? DateTime.now()).toLocal();
    final window = MenetrendService.commuteWindowForLessons(
      now: effectiveNow,
      lessons: _todaysLessons,
    );
    if (window == null) {
      ++_syncEpoch;
      if (_evaluation != null || _isLoading) {
        _evaluation = null;
        _isLoading = false;
        notifyListeners();
      }
      unawaited(MenetrendService.cancelAlarms());
      return;
    }

    final epoch = ++_syncEpoch;
    if (_evaluation != null && _evaluation!.isMorningMode != window) {
      _evaluation = null;
    }
    final hadEval = _evaluation != null;
    if (!hadEval && !_isLoading) {
      _isLoading = true;
      notifyListeners();
    }

    final eval = await _menetrendService.fetchLiveCommuteEvaluation(
      todaysLessons: _todaysLessons,
      prefs: prefs,
      nowOverride: nowOverride,
    );
    if (epoch != _syncEpoch) return;

    final prevEval = _evaluation;
    final evalChanged = _hasEvaluationChanged(prevEval, eval);
    final loadingChanged = _isLoading;
    _evaluation = eval;
    _isLoading = false;
    if (evalChanged || loadingChanged) {
      notifyListeners();
    }

    if (eval != null) {
      unawaited(
        MenetrendService.syncNotificationsForEvaluation(
          evaluation: eval,
          prefs: prefs,
          allowDelayNotification: allowDelayNotifications,
        ),
      );
    }
  }

  void _handleSettingsChanged() {
    final nextPrefs = _settings.prefs;
    final next = _CommuteSettingsSnapshot.fromPrefs(nextPrefs);
    if (next == _lastSnapshot) return;
    final prev = _lastSnapshot;
    _lastSnapshot = next;

    if (!nextPrefs.transitCardEnabled || !nextPrefs.transitConfigured) {
      ++_syncEpoch;
      if (_evaluation != null || _isLoading) {
        _evaluation = null;
        _isLoading = false;
        notifyListeners();
      }
      MenetrendService.cancelAlarms();
      return;
    }

    final needsLiveFetch = _evaluation == null ||
        prev.requiresNetworkRefresh(next);

    if (_evaluation != null) {
      final recalculated = _evaluation!.recalculateForPrefs(nextPrefs);
      final filtered = MenetrendService.filterVisibleEvaluation(
        evaluation: recalculated,
        todaysLessons: _hasLessons ? _todaysLessons : null,
        prefs: nextPrefs,
        now: recalculated.now,
      );
      _evaluation = filtered;
      notifyListeners();
      if (filtered != null) {
        // Update morning departure alarm without firing delay notification spam.
        MenetrendService.syncNotificationsForEvaluation(
          evaluation: filtered,
          prefs: nextPrefs,
          allowDelayNotification: false,
        );
      } else {
        MenetrendService.cancelAlarms();
      }
    }

    if (needsLiveFetch) {
      unawaited(syncLive(allowDelayNotifications: false));
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);
    super.dispose();
  }
}

class _CommuteSettingsSnapshot {
  final bool transitCardEnabled;
  final String transitHomeStation;
  final String transitSchoolStation;
  final String homeAddress;
  final String schoolAddress;
  final bool transitAllowTrain;
  final bool transitAllowCoach;
  final bool transitAllowLocalBus;
  final double walkingSpeedKmh;
  final int walkingDurationMinutes;
  final int walkHomeToBusMinutes;
  final int walkHomeToTrainMinutes;
  final int walkSchoolToBusMinutes;
  final int walkSchoolToTrainMinutes;
  final int transitAlertBufferMinutes;
  final bool transitNotificationsEnabled;
  final String favoriteRoute1stPeriod;
  final String favoriteRoute2ndPeriod;
  final String commuteDaysJson;

  const _CommuteSettingsSnapshot({
    required this.transitCardEnabled,
    required this.transitHomeStation,
    required this.transitSchoolStation,
    required this.homeAddress,
    required this.schoolAddress,
    required this.transitAllowTrain,
    required this.transitAllowCoach,
    required this.transitAllowLocalBus,
    required this.walkingSpeedKmh,
    required this.walkingDurationMinutes,
    required this.walkHomeToBusMinutes,
    required this.walkHomeToTrainMinutes,
    required this.walkSchoolToBusMinutes,
    required this.walkSchoolToTrainMinutes,
    required this.transitAlertBufferMinutes,
    required this.transitNotificationsEnabled,
    required this.favoriteRoute1stPeriod,
    required this.favoriteRoute2ndPeriod,
    required this.commuteDaysJson,
  });

  factory _CommuteSettingsSnapshot.fromPrefs(UserProfilePrefs p) =>
      _CommuteSettingsSnapshot(
        transitCardEnabled: p.transitCardEnabled,
        transitHomeStation: p.transitHomeStation,
        transitSchoolStation: p.transitSchoolStation,
        homeAddress: '${p.homeAddress}|${p.homeAddressLat}|${p.homeAddressLon}',
        schoolAddress:
            '${p.schoolAddress}|${p.schoolAddressLat}|${p.schoolAddressLon}',
        transitAllowTrain: p.transitAllowTrain,
        transitAllowCoach: p.transitAllowCoach,
        transitAllowLocalBus: p.transitAllowLocalBus,
        walkingSpeedKmh: p.walkingSpeedKmh,
        walkingDurationMinutes: p.walkingDurationMinutes,
        walkHomeToBusMinutes: p.walkHomeToBusMinutes,
        walkHomeToTrainMinutes: p.walkHomeToTrainMinutes,
        walkSchoolToBusMinutes: p.walkSchoolToBusMinutes,
        walkSchoolToTrainMinutes: p.walkSchoolToTrainMinutes,
        transitAlertBufferMinutes: p.transitAlertBufferMinutes,
        transitNotificationsEnabled: p.transitNotificationsEnabled,
        favoriteRoute1stPeriod: p.favoriteRoute1stPeriod,
        favoriteRoute2ndPeriod: p.favoriteRoute2ndPeriod,
        commuteDaysJson: jsonEncode(p.extras['commuteDays']),
      );

  bool requiresNetworkRefresh(_CommuteSettingsSnapshot other) =>
      transitHomeStation != other.transitHomeStation ||
      transitSchoolStation != other.transitSchoolStation ||
      homeAddress != other.homeAddress ||
      schoolAddress != other.schoolAddress ||
      transitAllowTrain != other.transitAllowTrain ||
      transitAllowCoach != other.transitAllowCoach ||
      transitAllowLocalBus != other.transitAllowLocalBus ||
      commuteDaysJson != other.commuteDaysJson;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _CommuteSettingsSnapshot &&
        other.transitCardEnabled == transitCardEnabled &&
        other.transitHomeStation == transitHomeStation &&
        other.transitSchoolStation == transitSchoolStation &&
        other.homeAddress == homeAddress &&
        other.schoolAddress == schoolAddress &&
        other.transitAllowTrain == transitAllowTrain &&
        other.transitAllowCoach == transitAllowCoach &&
        other.transitAllowLocalBus == transitAllowLocalBus &&
        other.walkingSpeedKmh == walkingSpeedKmh &&
        other.walkingDurationMinutes == walkingDurationMinutes &&
        other.walkHomeToBusMinutes == walkHomeToBusMinutes &&
        other.walkHomeToTrainMinutes == walkHomeToTrainMinutes &&
        other.walkSchoolToBusMinutes == walkSchoolToBusMinutes &&
        other.walkSchoolToTrainMinutes == walkSchoolToTrainMinutes &&
        other.transitAlertBufferMinutes == transitAlertBufferMinutes &&
        other.transitNotificationsEnabled == transitNotificationsEnabled &&
        other.favoriteRoute1stPeriod == favoriteRoute1stPeriod &&
        other.favoriteRoute2ndPeriod == favoriteRoute2ndPeriod &&
        other.commuteDaysJson == commuteDaysJson;
  }

  @override
  int get hashCode => Object.hash(
        transitCardEnabled,
        transitHomeStation,
        transitSchoolStation,
        homeAddress,
        schoolAddress,
        transitAllowTrain,
        transitAllowCoach,
        transitAllowLocalBus,
        walkingSpeedKmh,
        walkingDurationMinutes,
        walkHomeToBusMinutes,
        walkHomeToTrainMinutes,
        walkSchoolToBusMinutes,
        walkSchoolToTrainMinutes,
        transitAlertBufferMinutes,
        transitNotificationsEnabled,
        favoriteRoute1stPeriod,
        favoriteRoute2ndPeriod,
        commuteDaysJson,
      );
}

/// Inherited scope exposing [SettingsProvider], [ThemeProvider], and [CommuteProvider]
/// cleanly down the widget tree (including modal routes and pushed settings screens).
class AppProvidersScope extends InheritedWidget {
  final SettingsProvider settings;
  final ThemeProvider theme;
  final CommuteProvider commute;

  const AppProvidersScope({
    super.key,
    required this.settings,
    required this.theme,
    required this.commute,
    required super.child,
  });

  static AppProvidersScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppProvidersScope>();
  }

  @override
  bool updateShouldNotify(covariant AppProvidersScope oldWidget) =>
      settings != oldWidget.settings ||
      theme != oldWidget.theme ||
      commute != oldWidget.commute;
}
