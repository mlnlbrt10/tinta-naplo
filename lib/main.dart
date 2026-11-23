import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'providers/app_providers.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/webview_login_screen.dart';
import 'services/demo_data_service.dart';
import 'services/dynamic_icon_service.dart';
import 'services/home_widget_sync_service.dart';
import 'services/kreta_client.dart';
import 'services/kreta_notification_service.dart';
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
  UserProfilePrefs? _lastSyncedPrefs;
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
  Brightness? _lastAppliedOverlayBrightness;

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
    TokenStorageService.externalSessionFallbackLoader =
        WearSyncService.instance.loadCachedSessionFromNative;
    HomeWidgetSyncService.instance.initialize();
    unawaited(
      KretaNotificationService.instance
          .syncBackgroundSchedule()
          .catchError((_) {}),
    );
    WearSyncService.instance.initialize(
      onWatchAuthRequested: () {
        unawaited(_handleWatchAuthRequested());
      },
      onSessionUpdatedFromWatch: (rotated) {
        unawaited(_ingestRotatedWatchSession(rotated));
      },
    );
    _restoreSavedSessionAndPrefs();
  }

  Future<void> _ingestRotatedWatchSession(StoredSession rotated) async {
    try {
      if (_prefs.demoModeEnabled) return;
      final current = _session ?? TokenStorageService.latestSession;
      if (current != null &&
          current.instituteCode.toLowerCase() !=
              rotated.instituteCode.toLowerCase()) {
        return;
      }
      if (current != null &&
          rotated.expiresAt.isBefore(current.expiresAt) &&
          rotated.refreshToken == current.refreshToken) {
        return;
      }
      await _tokenStorage.saveSession(rotated);
      await TokenStorageService.recordAuthEvent(
        caller: 'TintaNaploApp._ingestRotatedWatchSession',
        action: 'watch_rotated_session_ingested',
      );
      if (mounted) {
        _set(() => _session = rotated);
      }
    } catch (_) {}
  }

  void _onGlobalSessionChanged() {
    if (!mounted || _prefs.demoModeEnabled) return;
    final next = TokenStorageService.sessionNotifier.value;
    if (next != null &&
        (next.accessToken != _session?.accessToken ||
            next.refreshToken != _session?.refreshToken ||
            next.expiresAt != _session?.expiresAt)) {
      _set(() => _session = next);
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
      unawaited(
        precacheImage(AssetImage(_prefs.activeAppIconAsset), context)
            .catchError((_) {}),
      );
    }
  }

  @override
  void dispose() {
    TokenStorageService.sessionNotifier.removeListener(_onGlobalSessionChanged);
    if (TokenStorageService.externalSessionFallbackLoader ==
        WearSyncService.instance.loadCachedSessionFromNative) {
      TokenStorageService.externalSessionFallbackLoader = null;
    }
    WearSyncService.instance.disposeListener();
    _settingsProvider.removeListener(_onProviderPrefsChanged);
    _commuteProvider.dispose();
    _themeProvider.dispose();
    _settingsProvider.dispose();
    if (widget.kretaClient == null) {
      _kretaClient.close();
    }
    _rootRevision.dispose();
    super.dispose();
  }

  Future<void> _restoreSavedSessionAndPrefs() async {
    StoredSession? restoredSession;
    UserProfilePrefs restoredPrefs = _settingsProvider.prefs;
    DashboardData? restoredCache;

    // 1. Isolate session loading so a corrupted prefs/cache entry can NEVER
    // wipe out `_session` and kick the user back to LoginScreen!
    try {
      restoredSession = await _tokenStorage.loadSession();
    } catch (e) {
      await TokenStorageService.recordAuthEvent(
        caller: 'TintaNaploApp._restoreSavedSessionAndPrefs',
        action: 'startup_load_session_error',
        errorSnippet: e.toString(),
      );
      restoredSession = TokenStorageService.latestSession;
    }

    // 2. Load preferences independently.
    try {
      restoredPrefs = await _settingsProvider.load();
    } catch (_) {
      restoredPrefs = _settingsProvider.prefs;
    }
    if (!mounted) return;

    UserProfilePrefs.syncActiveGlobals(restoredPrefs);
    _lastSyncedPrefs = restoredPrefs;

    // 3. Load cached dashboard independently (corrupted cache must never drop session).
    try {
      if (restoredSession != null && !restoredPrefs.demoModeEnabled) {
        try {
          restoredCache =
              await _kretaClient.loadCachedDashboard(restoredSession);
        } catch (_) {
          restoredCache = null;
        }
        unawaited(
          WearSyncService.instance
              .cacheSessionSnapshot(
                session: restoredSession,
                student: restoredCache?.student,
                nickname: restoredPrefs.nickname,
                recentGrades: restoredCache?.allGrades,
                upcomingExams: restoredCache?.tests,
              )
              .catchError((_) => false),
        );
      } else if (restoredPrefs.demoModeEnabled) {
        restoredCache = DemoDataService.instance.buildDashboardData();
      } else if (await TokenStorageService.hadPreviousLogin()) {
        await TokenStorageService.recordLogoutReason(
          caller: 'TintaNaploApp._restoreSavedSessionAndPrefs',
          reason:
              'Munkamenet nem található indításkor (korábbi bejelentkezés után)',
          errorBody: TokenStorageService.lastStorageReadError ??
              'no_stored_session_found',
        );
      }
    } catch (_) {}

    if (!mounted) return;
    if (restoredCache != null) {
      _commuteProvider.setLessons(restoredCache.todaysLessons);
    }
    _set(() {
      _session = restoredSession;
      _cachedDashboard = restoredCache;
      _isRestoringSession = false;
    });

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
    try {
      final pendingWatchAuth = _pendingWatchAuthDuringRestore ||
          await WearSyncService.instance.consumePendingWatchAuthRequest();
      _pendingWatchAuthDuringRestore = false;
      if (pendingWatchAuth && mounted) {
        await _handleWatchAuthRequested();
      }
    } catch (_) {}
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
    try {
      await WearSyncService.instance.consumePendingWatchAuthRequest();
      if (!mounted) return;
      final currentSession =
          await _tokenStorage.loadSession() ?? _session;
      if (!mounted) return;
      if (currentSession != null) {
        StoredSession active = currentSession;
        if (active.isExpired) {
          try {
            active = await _kretaClient.ensureValidSession(active);
            if (mounted) {
              _set(() => _session = active);
            }
          } on VerifiedInvalidGrantException catch (e) {
            // ZERO AUTO-KICK: never wipe tokens or kick the user out to LoginScreen!
            // Keep cached data intact, flag the non-destructive re-auth banner, and
            // offer in-place re-authentication.
            TokenStorageService.markReauthRequired(
              'A munkamenet lejárt óra szinkronizálás közben (HTTP ${e.httpStatusCode}).',
            );
            await TokenStorageService.recordAuthEvent(
              caller: 'TintaNaploApp._handleWatchAuthRequested',
              action: 'watch_sync_verified_invalid_grant_no_kick',
              httpStatus: e.httpStatusCode,
              errorSnippet: e.responseBody,
            );
            if (mounted) {
              await _openWatchRequestedLogin(preserveCache: true);
            }
            return;
          } catch (_) {
            // Keep existing session on transient offline or unverified errors;
            // never silently log out the phone user.
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
        if (_isSplashLoading && mounted) {
          _set(() {
            _isSplashLoading = false;
            _showSplashOverlay = false;
          });
        }
        await _openWatchRequestedLogin();
      }
    } catch (_) {
      // Never propagate unhandled async exceptions from watch sync callbacks.
    } finally {
      _isHandlingWatchAuth = false;
    }
  }

  Future<void> _openWatchRequestedLogin({bool preserveCache = false}) async {
    final nav = _navigatorKey.currentState;
    if (nav == null || _isLoginWebViewOpen) return;
    await _launchWebViewLoginWithNavigator(
      nav,
      preserveCache: preserveCache,
    );
  }

  Future<void> _updatePrefs(UserProfilePrefs nextPrefs) async {
    final prevPrefs = _lastSyncedPrefs ?? _prefs;
    _lastSyncedPrefs = nextPrefs;
    final ctx = _navigatorKey.currentContext;
    final themeAccent = ctx != null ? Theme.of(ctx).colorScheme.primary : null;
    // Update reactive provider immediately + persist to SharedPreferences & SecureStorage.
    if (!identical(_settingsProvider.prefs, nextPrefs)) {
      await _settingsProvider.updatePrefs(nextPrefs);
    }
    if (nextPrefs.appIconPreset != prevPrefs.appIconPreset ||
        nextPrefs.fitymaModeEnabled != prevPrefs.fitymaModeEnabled) {
      unawaited(
        DynamicIconService.syncIconWithPrefs(nextPrefs).catchError((_) {}),
      );
    }
    final affectsWidgets =
        nextPrefs.seedColorValue != prevPrefs.seedColorValue ||
            nextPrefs.themeStyle != prevPrefs.themeStyle ||
            nextPrefs.uwuModeEnabled != prevPrefs.uwuModeEnabled ||
            nextPrefs.liveActivityEnabled != prevPrefs.liveActivityEnabled ||
            nextPrefs.demoModeEnabled != prevPrefs.demoModeEnabled ||
            nextPrefs.hideCancelledLessons != prevPrefs.hideCancelledLessons ||
            !mapEquals(
              nextPrefs.subjectCustomNames,
              prevPrefs.subjectCustomNames,
            ) ||
            !mapEquals(
              nextPrefs.teacherCustomNames,
              prevPrefs.teacherCustomNames,
            );
    if (affectsWidgets) {
      unawaited(
        HomeWidgetSyncService.instance
            .syncPreferencesWithCachedLessons(
              prefs: nextPrefs,
              themeAccent: themeAccent,
            )
            .catchError((_) => false),
      );
    }
  }

  Future<void> _launchWebViewLogin(BuildContext navContext) async {
    await _launchWebViewLoginWithNavigator(Navigator.of(navContext));
  }

  Future<StoredSession?> _handleReauthenticateInPlace(
    BuildContext navContext,
  ) async {
    return _launchWebViewLoginWithNavigator(
      Navigator.of(navContext),
      preserveCache: true,
    );
  }

  Future<StoredSession?> _launchWebViewLoginWithNavigator(
    NavigatorState navigator, {
    bool preserveCache = false,
  }) async {
    if (_isLoginWebViewOpen) return null;
    _isLoginWebViewOpen = true;
    try {
      final session = await navigator.push<StoredSession>(
        MaterialPageRoute(
          builder: (_) => WebViewLoginScreen(
            kretaClient: _kretaClient,
            initialInstituteCode: preserveCache ? _session?.instituteCode : null,
            initialUsername: preserveCache ? _session?.userName : null,
          ),
        ),
      );

      if (session != null && mounted) {
        TokenStorageService.clearReauthRequired();
        await TokenStorageService.recordAuthEvent(
          caller: 'TintaNaploApp._launchWebViewLoginWithNavigator',
          action: preserveCache ? 'in_place_reauth_succeeded' : 'login_succeeded',
        );
        _set(() {
          _session = session;
          if (!preserveCache) {
            _cachedDashboard = null;
          }
        });
        unawaited(
          WearSyncService.instance
              .syncSessionToWatch(
                session: session,
                student: _cachedDashboard?.student,
                nickname: _prefs.nickname,
                forceSync: true,
                recentGrades: _cachedDashboard?.allGrades,
                upcomingExams: _cachedDashboard?.tests,
              )
              .then((pushed) {
                if (pushed && mounted) {
                  _showWatchSyncFeedback('Munkamenet elküldve az órára');
                }
              })
              .catchError((_) {}),
        );
      }
      return session;
    } finally {
      _isLoginWebViewOpen = false;
    }
  }

  /// Explicit user-initiated logout (ONLY called from the "Kijelentkezés" button).
  Future<void> _handleLogout() async {
    final previousSession = _session;
    try {
      if (previousSession != null) {
        await _tokenStorage.clearDashboardCache(
          TokenStorageService.accountKeyForSession(previousSession),
        );
      }
    } catch (_) {}
    try {
      await _tokenStorage.clearSession(
        caller: 'TintaNaploApp._handleLogout',
        reason: 'Felhasználói kijelentkezés',
        isUserInitiated: true,
      );
    } catch (_) {}
    if (_prefs.demoModeEnabled) {
      try {
        await _settingsProvider.updatePrefs(
          _prefs.withExtra('demoModeEnabled', false),
        );
      } catch (_) {}
    }
    _kretaClient.clearLocalState();
    HomeWidgetSyncService.instance.clearMemoryCache();
    unawaited(
      WearSyncService.instance.clearWatchSession().catchError((_) => false),
    );
    if (!mounted) return;
    _set(() {
      _session = null;
      _cachedDashboard = null;
    });
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
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
              final isShowingLoginScreen = !_isRestoringSession &&
                  _session == null &&
                  !_prefs.demoModeEnabled;
              final effectiveOverlayBrightness = isShowingLoginScreen
                  ? Brightness.dark
                  : activeTheme.brightness;
              final overlayStyle = OledTheme.systemOverlayStyleForBrightness(
                effectiveOverlayBrightness,
              );
              if (_lastAppliedOverlayBrightness != effectiveOverlayBrightness) {
                _lastAppliedOverlayBrightness = effectiveOverlayBrightness;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
                  }
                });
              }

              final activeIsLight = activeTheme.brightness == Brightness.light;
              return MaterialApp(
                navigatorKey: _navigatorKey,
                scaffoldMessengerKey: _scaffoldMessengerKey,
                title: uwu('Tinta Napló'),
                debugShowCheckedModeBanner: false,
                theme: activeTheme,
                darkTheme: activeTheme,
                themeMode: activeIsLight ? ThemeMode.light : ThemeMode.dark,
                themeAnimationDuration: Duration.zero,
                themeAnimationStyle: AnimationStyle.noAnimation,
                builder: (context, child) {
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: overlayStyle,
                    child: Stack(
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
                    ),
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
      return Builder(
        builder: (navContext) {
          return HomeScreen(
            initialSession:
                _session ?? DemoDataService.instance.buildDemoSession(),
            initialCachedData: _cachedDashboard,
            kretaClient: _kretaClient,
            prefs: _prefs,
            onPrefsChanged: _updatePrefs,
            onLogout: _handleLogout,
            onReauthenticate: () => _handleReauthenticateInPlace(navContext),
          );
        },
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
