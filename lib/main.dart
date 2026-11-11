import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/webview_login_screen.dart';
import 'services/dynamic_icon_service.dart';
import 'services/kreta_client.dart';
import 'services/token_storage_service.dart';
import 'theme/oled_theme.dart';
import 'widgets/christmas_snowfall_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReKretaApp());
}

class ReKretaApp extends StatefulWidget {
  const ReKretaApp({super.key});

  @override
  State<ReKretaApp> createState() => _ReKretaAppState();
}

class _ReKretaAppState extends State<ReKretaApp> {
  final TokenStorageService _tokenStorage = const TokenStorageService();
  late final KretaClient _kretaClient = KretaClient(storage: _tokenStorage);

  StoredSession? _session;
  UserProfilePrefs _prefs = const UserProfilePrefs();
  bool _isRestoringSession = true;

  final TextEditingController _instituteController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restoreSavedSessionAndPrefs();
  }

  @override
  void dispose() {
    _instituteController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _restoreSavedSessionAndPrefs() async {
    try {
      final results = await Future.wait<Object?>([
        _tokenStorage.loadSession(),
        _tokenStorage.loadProfilePrefs(),
      ]);
      if (!mounted) return;
      setState(() {
        _session = results[0] as StoredSession?;
        _prefs = results[1] as UserProfilePrefs;
        _isRestoringSession = false;
      });
      await DynamicIconService.syncIconWithPrefs(_prefs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRestoringSession = false);
    }
  }

  Future<void> _updatePrefs(UserProfilePrefs nextPrefs) async {
    setState(() => _prefs = nextPrefs);
    await Future.wait([
      _tokenStorage.saveProfilePrefs(nextPrefs),
      DynamicIconService.syncIconWithPrefs(nextPrefs),
    ]);
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
      setState(() => _session = session);
    }
  }

  Future<void> _handleLogout() async {
    await _tokenStorage.clearSession();
    if (!mounted) return;
    setState(() => _session = null);
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
          title: 'reKRETA',
          debugShowCheckedModeBanner: false,
          theme: activeTheme,
          darkTheme: activeTheme,
          themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
          home: _buildRootScreen(),
        );
      },
    );
  }

  Widget _buildRootScreen() {
    if (_isRestoringSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_session != null) {
      return HomeScreen(
        initialSession: _session!,
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
                              'reKRETA',
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
