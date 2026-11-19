import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:kreta_api/kreta_api.dart';

import 'providers/app_providers.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/webview_login_screen.dart';
import 'services/demo_data_service.dart';
import 'services/dynamic_icon_service.dart';
import 'services/home_widget_sync_service.dart';
import 'services/kreta_client.dart';
import 'services/token_storage_service.dart';
import 'services/wear_sync_service.dart';
import 'theme/oled_theme.dart';
import 'utils/uwu_helper.dart';
import 'widgets/tinta_splash_overlay.dart';
import 'widgets/tinta_toast.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TintaNaploApp());
}

class TintaNaploApp extends StatefulWidget {
  final TokenStorageService? tokenStorage;
  final KretaClient? kretaClient;

  const TintaNaploApp({
    super.key,
    this.tokenStorage,
    this.kretaClient,
  });

  @override
  State<TintaNaploApp> createState() => _TintaNaploAppState();
}

class _TintaNaploAppState extends State<TintaNaploApp> {
  late final TokenStorageService _tokenStorage =
      widget.tokenStorage ?? const TokenStorageService();
  late final KretaClient _kretaClient =
      widget.kretaClient ?? KretaClient(storage: _tokenStorage);
  late final SettingsProvider _settingsProvider = SettingsProvider(
    storage: _tokenStorage,
  );
  late final ThemeProvider _themeProvider = ThemeProvider(_settingsProvider);
  late final CommuteProvider _commuteProvider =
      CommuteProvider(_settingsProvider);

  StoredSession? _session;
  DashboardData? _cachedDashboard;
  UserProfilePrefs get _prefs => _settingsProvider.prefs;
  bool _isRestoringSession = true;
  bool _isSplashLoading = true;
  bool _showSplashOverlay = true;
  bool _splashIconPrecached = false;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  bool _isLoginWebViewOpen = false;
  bool _isHandlingWatchAuth = false;
  bool _pendingWatchAuthDuringRestore = false;
  DateTime? _lastWatchSyncFeedbackAt;

  /// Bumped on every state change so routes created via named navigation
  /// (e.g. `/login`) always render the up-to-date root content.
  final ValueNotifier<int> _rootRevision = ValueNotifier<int>(0);

  void _set(VoidCallback fn) {
    setState(fn);
    _rootRevision.value++;
  }

  Widget _rootRoute() => ValueListenableBuilder<int>(
        valueListenable: _rootRevision,
        builder: (_, __, ___) => _buildRootScreen(),
      );

  @override
  void initState() {
    super.initState();
    _settingsProvider.addListener(_onProviderPrefsChanged);
    TokenStorageService.sessionNotifier.addListener(_onGlobalSessionChanged);
    HomeWidgetSyncService.instance.initialize();
    WearSyncService.instance.initialize(
      onWatchAuthRequested: () {
        unawaited(_handleWatchAuthRequested());
      },
    );
    _restoreSavedSessionAndPrefs();
  }

  void _onGlobalSessionChanged() {
    if (!mounted || _prefs.demoModeEnabled) return;
    final next = TokenStorageService.sessionNotifier.value;
    if (next != null && next.accessToken != _session?.accessToken) {
      setState(() => _session = next);
    }
  }

  void _onProviderPrefsChanged() {
    if (!mounted) return;
    _set(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_splashIconPrecached) {
      _splashIconPrecached = true;
      precacheImage(const AssetImage('assets/images/tinta_icon.png'), context);
    }
  }

  @override
  void dispose() {
    TokenStorageService.sessionNotifier.removeListener(_onGlobalSessionChanged);
    WearSyncService.instance.disposeListener();
    _settingsProvider.removeListener(_onProviderPrefsChanged);
    _commuteProvider.dispose();
    _themeProvider.dispose();
    _settingsProvider.dispose();
    _rootRevision.dispose();
    super.dispose();
  }

  Future<void> _restoreSavedSessionAndPrefs() async {
    try {
      final results = await Future.wait<Object?>([
        _tokenStorage.loadSession(),
        _settingsProvider.load(),
      ]);
      if (!mounted) return;
      final restoredSession = results[0] as StoredSession?;
      final restoredPrefs = results[1] as UserProfilePrefs;
      DashboardData? restoredCache;
      UserProfilePrefs.syncActiveGlobals(restoredPrefs);
      if (restoredSession != null && !restoredPrefs.demoModeEnabled) {
        restoredCache =
            await _kretaClient.loadCachedDashboard(restoredSession);
        unawaited(
          WearSyncService.instance.cacheSessionSnapshot(
            session: restoredSession,
            student: restoredCache?.student,
            nickname: restoredPrefs.nickname,
            recentGrades: restoredCache?.allGrades,
            upcomingExams: restoredCache?.tests,
          ),
        );
      } else if (restoredPrefs.demoModeEnabled) {
        restoredCache = DemoDataService.instance.buildDashboardData();
      }
      if (!mounted) return;
      if (restoredCache != null) {
        _commuteProvider.setLessons(restoredCache.todaysLessons);
      }
      _set(() {
        _session = restoredSession;
        _cachedDashboard = restoredCache;
        _isRestoringSession = false;
      });
    } catch (_) {
      if (!mounted) return;
      _set(() => _isRestoringSession = false);
    }

    // Dismiss the splash overlay only after the real HomeScreen/LoginScreen frame
    // has built and painted its first frame underneath so zero white/blank flicker occurs.
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_isSplashLoading) {
          _set(() => _isSplashLoading = false);
        }
        unawaited(_checkPendingWatchAuthOnStartup());
      });
    });
  }

  Future<void> _checkPendingWatchAuthOnStartup() async {
    final pendingWatchAuth = _pendingWatchAuthDuringRestore ||
        await WearSyncService.instance.consumePendingWatchAuthRequest();
    _pendingWatchAuthDuringRestore = false;
    if (pendingWatchAuth && mounted) {
      await _handleWatchAuthRequested();
    }
  }

  void _showWatchSyncFeedback(String message) {
    final now = DateTime.now();
    if (_lastWatchSyncFeedbackAt != null &&
        now.difference(_lastWatchSyncFeedbackAt!).inMilliseconds < 2000) {
      return;
    }
    _lastWatchSyncFeedbackAt = now;
    final ctx = _navigatorKey.currentContext ?? _scaffoldMessengerKey.currentContext;
    if (ctx == null) return;
    TintaToast.info(
      ctx,
      message,
      overlayOverride: _navigatorKey.currentState?.overlay,
    );
  }

  Future<void> _handleWatchAuthRequested() async {
    if (!mounted) return;
    if (_isRestoringSession) {
      _pendingWatchAuthDuringRestore = true;
      return;
    }
    if (_isHandlingWatchAuth) return;
    _isHandlingWatchAuth = true;
    await WearSyncService.instance.consumePendingWatchAuthRequest();
    if (!mounted) {
      _isHandlingWatchAuth = false;
      return;
    }
    try {
      final currentSession =
          await _tokenStorage.loadSession() ?? _session;
      if (currentSession != null) {
        StoredSession active = currentSession;
        if (active.isExpired) {
          try {
            active = await _kretaClient.ensureValidSession(active);
            if (mounted) {
              _set(() => _session = active);
            }
          } on InvalidGrantException {
            await _handleLogout();
            if (mounted) await _openWatchRequestedLogin();
            return;
          } catch (_) {
            // Keep existing session on transient offline errors; the watch still
            // persists refresh_token + institute_code and refreshes independently.
          }
        }
        final pushed = await WearSyncService.instance.syncSessionToWatch(
          session: active,
          student: _cachedDashboard?.student,
          nickname: _prefs.nickname,
          forceSync: true,
          recentGrades: _cachedDashboard?.allGrades,
          upcomingExams: _cachedDashboard?.tests,
        );
        if (pushed && mounted) {
          _showWatchSyncFeedback('Munkamenet szinkronizálva az órával');
        }
      } else {
        if (_isSplashLoading) {
          _set(() {
            _isSplashLoading = false;
            _showSplashOverlay = false;
          });
        }
        await _openWatchRequestedLogin();
      }
    } finally {
      _isHandlingWatchAuth = false;
    }
  }

  Future<void> _openWatchRequestedLogin() async {
    final nav = _navigatorKey.currentState;
    if (nav == null || _isLoginWebViewOpen) return;
    await _launchWebViewLoginWithNavigator(nav);
  }

  Future<void> _updatePrefs(UserProfilePrefs nextPrefs) async {
    final prevPrefs = _prefs;
    final ctx = _navigatorKey.currentContext;
    final themeAccent = ctx != null ? Theme.of(ctx).colorScheme.primary : null;
    // Update reactive provider immediately + persist to SharedPreferences & SecureStorage.
    await _settingsProvider.updatePrefs(nextPrefs);
    if (nextPrefs.appIconPreset != prevPrefs.appIconPreset) {
      await DynamicIconService.syncIconWithPrefs(nextPrefs);
    }
    final affectsWidgets =
        nextPrefs.seedColorValue != prevPrefs.seedColorValue ||
            nextPrefs.themeStyle != prevPrefs.themeStyle ||
            nextPrefs.uwuModeEnabled != prevPrefs.uwuModeEnabled ||
            nextPrefs.tsundereModeEnabled != prevPrefs.tsundereModeEnabled ||
            nextPrefs.liveActivityEnabled != prevPrefs.liveActivityEnabled ||
            nextPrefs.demoModeEnabled != prevPrefs.demoModeEnabled ||
            nextPrefs.hideCancelledLessons != prevPrefs.hideCancelledLessons ||
            nextPrefs.subjectCustomNames.length !=
                prevPrefs.subjectCustomNames.length ||
            nextPrefs.teacherCustomNames.length !=
                prevPrefs.teacherCustomNames.length;
    if (affectsWidgets) {
      unawaited(
        HomeWidgetSyncService.instance.syncPreferencesWithCachedLessons(
          prefs: nextPrefs,
          themeAccent: themeAccent,
        ),
      );
    }
  }

  Future<void> _launchWebViewLogin(BuildContext navContext) async {
    await _launchWebViewLoginWithNavigator(Navigator.of(navContext));
  }

  Future<void> _launchWebViewLoginWithNavigator(
    NavigatorState navigator,
  ) async {
    if (_isLoginWebViewOpen) return;
    _isLoginWebViewOpen = true;
    try {
      final session = await navigator.push<StoredSession>(
        MaterialPageRoute(
          builder: (_) => WebViewLoginScreen(
            kretaClient: _kretaClient,
          ),
        ),
      );

      if (session != null && mounted) {
        _set(() {
          _session = session;
          _cachedDashboard = null;
        });
        final pushed = await WearSyncService.instance.syncSessionToWatch(
          session: session,
          nickname: _prefs.nickname,
          forceSync: true,
        );
        if (pushed && mounted) {
          _showWatchSyncFeedback('Munkamenet elküldve az órára');
        }
      }
    } finally {
      _isLoginWebViewOpen = false;
    }
  }

  Future<void> _handleLogout() async {
    final previousSession = _session;
    if (previousSession != null) {
      await _tokenStorage.clearDashboardCache(
        TokenStorageService.accountKeyForSession(previousSession),
      );
    }
    await _tokenStorage.clearSession();
    HomeWidgetSyncService.instance.clearMemoryCache();
    unawaited(WearSyncService.instance.clearWatchSession());
    if (!mounted) return;
    _set(() {
      _session = null;
      _cachedDashboard = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppProvidersScope(
      settings: _settingsProvider,
      theme: _themeProvider,
      commute: _commuteProvider,
      child: ListenableBuilder(
        listenable: Listenable.merge([_settingsProvider, _themeProvider]),
        builder: (context, _) {
          return DynamicColorBuilder(
            builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
              final isLight = _prefs.themeStyle == AppThemeStyle.light;
              final activeTheme = OledTheme.buildTheme(
                prefs: _prefs,
                dynamicScheme: isLight ? lightDynamic : darkDynamic,
              );

              return MaterialApp(
                navigatorKey: _navigatorKey,
                scaffoldMessengerKey: _scaffoldMessengerKey,
                title: uwu('Tinta Napló'),
                debugShowCheckedModeBanner: false,
                theme: activeTheme,
                darkTheme: activeTheme,
                themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
                themeAnimationDuration: Duration.zero,
                builder: (context, child) {
                  return Stack(
                    children: [
                      child ?? const SizedBox.shrink(),
                      if (_showSplashOverlay)
                        TintaSplashOverlay(
                          key: const ValueKey<String>('tinta-splash-overlay'),
                          isLoading: _isSplashLoading,
                          accentColor: activeTheme.colorScheme.primary,
                          onDismissed: () {
                            if (mounted) {
                              setState(() => _showSplashOverlay = false);
                            }
                          },
                        ),
                    ],
                  );
                },
                home: _rootRoute(),
                routes: {'/login': (_) => _rootRoute()},
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRootScreen() {
    if (_isRestoringSession) {
      return const Scaffold(
        backgroundColor: Color(0xFF000000),
        body: SizedBox.expand(),
      );
    }

    if (_session != null || _prefs.demoModeEnabled) {
      return HomeScreen(
        initialSession: _session ?? DemoDataService.instance.buildDemoSession(),
        initialCachedData: _cachedDashboard,
        kretaClient: _kretaClient,
        prefs: _prefs,
        onPrefsChanged: _updatePrefs,
        onLogout: _handleLogout,
      );
    }

    return Builder(
      builder: (navContext) {
        return LoginScreen(
          prefs: _prefs,
          onLaunchWebAuth: () => _launchWebViewLogin(navContext),
        );
      },
    );
  }
}
