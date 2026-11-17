import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:kreta_api/kreta_api.dart';

import 'providers/app_providers.dart';
import 'screens/home_screen.dart';
import 'screens/webview_login_screen.dart';
import 'services/dynamic_icon_service.dart';
import 'services/kreta_client.dart';
import 'services/token_storage_service.dart';
import 'services/wear_sync_service.dart';
import 'theme/oled_theme.dart';
import 'widgets/christmas_snowfall_overlay.dart';
import 'widgets/tinta_splash_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReKretaApp());
}

class ReKretaApp extends StatefulWidget {
  final TokenStorageService? tokenStorage;
  final KretaClient? kretaClient;

  const ReKretaApp({
    super.key,
    this.tokenStorage,
    this.kretaClient,
  });

  @override
  State<ReKretaApp> createState() => _ReKretaAppState();
}

class _ReKretaAppState extends State<ReKretaApp> {
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

  final TextEditingController _instituteController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
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
    WearSyncService.instance.initialize(
      onWatchAuthRequested: () {
        unawaited(_handleWatchAuthRequested());
      },
    );
    _restoreSavedSessionAndPrefs();
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
    WearSyncService.instance.disposeListener();
    _settingsProvider.removeListener(_onProviderPrefsChanged);
    _commuteProvider.dispose();
    _themeProvider.dispose();
    _settingsProvider.dispose();
    _instituteController.dispose();
    _usernameController.dispose();
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
      if (restoredSession != null) {
        restoredCache =
            await _kretaClient.loadCachedDashboard(restoredSession);
        unawaited(
          WearSyncService.instance.cacheSessionSnapshot(
            session: restoredSession,
            student: restoredCache?.student,
            nickname: restoredPrefs.nickname,
          ),
        );
      }
      if (!mounted) return;
      UserProfilePrefs.syncActiveGlobals(restoredPrefs);
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

    // Dismiss the splash overlay right after the first real screen frame builds
    // and paints underneath so the 450ms easeOutCubic dissolve stays smooth.
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isSplashLoading) {
        _set(() => _isSplashLoading = false);
      }
      unawaited(_checkPendingWatchAuthOnStartup());
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
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
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
      final currentSession = _session;
      if (currentSession != null) {
        StoredSession active = currentSession;
        if (active.isExpired) {
          try {
            active = await _kretaClient.ensureValidSession(active);
            if (mounted) {
              _set(() => _session = active);
            }
          } on TokenExpiredException {
            await _handleLogout();
            if (mounted) await _openWatchRequestedLogin();
            return;
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
    final prevIcon = _prefs.appIconPreset;
    // Update reactive provider immediately + persist to SharedPreferences & SecureStorage.
    await _settingsProvider.updatePrefs(nextPrefs);
    if (nextPrefs.appIconPreset != prevIcon) {
      await DynamicIconService.syncIconWithPrefs(nextPrefs);
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
            initialInstituteCode: _instituteController.text.trim(),
            initialUsername: _usernameController.text.trim(),
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
                title: 'Tinta Napló',
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

    if (_session != null) {
      return HomeScreen(
        initialSession: _session!,
        initialCachedData: _cachedDashboard,
        kretaClient: _kretaClient,
        prefs: _prefs,
        onPrefsChanged: _updatePrefs,
        onLogout: _handleLogout,
      );
    }

    return Builder(
      builder: (navContext) {
        final theme = Theme.of(navContext);
        final scheme = theme.colorScheme;

        return Scaffold(
          body: ChristmasAndBackgroundOverlay(
            prefs: _prefs,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: ChristmasSnowCap(
                      enabled: _prefs.christmasModeEnabled,
                      child: Container(
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius: OledTheme.largeRadius,
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: AppBrandIconBadge(
                                prefs: _prefs,
                                size: 72,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Tinta Napló',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Jelentkezz be a hivatalos E-Kréta IDP felületén '
                              '(OAuth2 PKCE + interaktív reCAPTCHA WebView).',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.7),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 26),
                            TextField(
                              controller: _instituteController,
                              decoration: const InputDecoration(
                                labelText:
                                    'Intézményazonosító (opcionális előkitöltés)',
                                hintText: 'pl. klik035220001',
                                prefixIcon: Icon(Icons.account_balance_rounded),
                              ),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _usernameController,
                              decoration: const InputDecoration(
                                labelText:
                                    'Oktatási azonosító (opcionális előkitöltés)',
                                hintText: 'pl. 71234567890',
                                prefixIcon: Icon(Icons.badge_rounded),
                              ),
                              textInputAction: TextInputAction.done,
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: scheme.primary,
                                foregroundColor: scheme.onPrimary,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              onPressed: () => _launchWebViewLogin(navContext),
                              icon: const Icon(Icons.login_rounded),
                              label: const Text(
                                'Bejelentkezés E-Kréta WebView-val',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
