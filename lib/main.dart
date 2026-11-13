import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/webview_login_screen.dart';
import 'services/dynamic_icon_service.dart';
import 'services/kreta_client.dart';
import 'services/token_storage_service.dart';
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

  StoredSession? _session;
  DashboardData? _cachedDashboard;
  UserProfilePrefs _prefs = const UserProfilePrefs();
  bool _isRestoringSession = true;
  bool _isSplashLoading = true;
  bool _showSplashOverlay = true;
  bool _splashIconPrecached = false;

  final TextEditingController _instituteController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

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
    _restoreSavedSessionAndPrefs();
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
    _instituteController.dispose();
    _usernameController.dispose();
    _rootRevision.dispose();
    super.dispose();
  }

  Future<void> _restoreSavedSessionAndPrefs() async {
    try {
      final results = await Future.wait<Object?>([
        _tokenStorage.loadSession(),
        _tokenStorage.loadProfilePrefs(),
      ]);
      if (!mounted) return;
      final restoredSession = results[0] as StoredSession?;
      final restoredPrefs = results[1] as UserProfilePrefs;
      DashboardData? restoredCache;
      if (restoredSession != null) {
        restoredCache =
            await _kretaClient.loadCachedDashboard(restoredSession);
      }
      if (!mounted) return;
      UserProfilePrefs.syncActiveGlobals(restoredPrefs);
      _set(() {
        _session = restoredSession;
        _prefs = restoredPrefs;
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
      if (mounted && _isSplashLoading) {
        _set(() => _isSplashLoading = false);
      }
    });
  }

  Future<void> _updatePrefs(UserProfilePrefs nextPrefs) async {
    UserProfilePrefs.syncActiveGlobals(nextPrefs);
    _set(() => _prefs = nextPrefs);
    // Persist first: the alias swap may restart the process.
    await _tokenStorage.saveProfilePrefs(nextPrefs);
    await DynamicIconService.syncIconWithPrefs(nextPrefs);
  }

  Future<void> _launchWebViewLogin(BuildContext navContext) async {
    final session = await Navigator.of(navContext).push<StoredSession>(
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
    if (!mounted) return;
    _set(() {
      _session = null;
      _cachedDashboard = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final isLight = _prefs.themeStyle == AppThemeStyle.light;
        final activeTheme = OledTheme.buildTheme(
          prefs: _prefs,
          dynamicScheme: isLight ? lightDynamic : darkDynamic,
        );

        return MaterialApp(
          title: 'Tinta Napló',
          debugShowCheckedModeBanner: false,
          theme: activeTheme,
          darkTheme: activeTheme,
          themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
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
