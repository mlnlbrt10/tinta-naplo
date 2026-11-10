import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/kreta_auth_config.dart';
import '../services/kreta_client.dart';
import '../services/token_storage_service.dart';

/// Interactive in-app WebView screen that runs the OAuth2 Authorization Code +
/// PKCE login flow on `https://idp.e-kreta.hu`, allowing the user to solve any
/// reCAPTCHA challenge and intercepting the redirect to
/// `https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect`.
class WebViewLoginScreen extends StatefulWidget {
  final KretaClient kretaClient;
  final String? initialInstituteCode;
  final String? initialUsername;

  const WebViewLoginScreen({
    super.key,
    required this.kretaClient,
    this.initialInstituteCode,
    this.initialUsername,
  });

  @override
  State<WebViewLoginScreen> createState() => _WebViewLoginScreenState();
}

class _WebViewLoginScreenState extends State<WebViewLoginScreen> {
  late final WebViewController _webViewController;
  late PkcePair _pkce;
  late Uri _authorizationUri;

  int _loadingProgress = 0;
  bool _isExchangingToken = false;
  bool _hasInterceptedCode = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initPkceAndWebView();
  }

  void _initPkceAndWebView() {
    _pkce = PkcePair.generate();
    _authorizationUri = KretaAuthConfig.buildAuthorizationUri(
      pkce: _pkce,
      clientId: widget.kretaClient.clientId,
      instituteCode: widget.initialInstituteCode,
      loginHint: widget.initialUsername,
    );

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(KretaAuthConfig.userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _loadingProgress = progress);
            }
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() => _errorMessage = null);
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (KretaAuthConfig.isOAuthRedirectUrl(request.url)) {
              _handleOAuthRedirect(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            // Ignore errors triggered by cancelling the oauthredirect navigation.
            if (_hasInterceptedCode || error.isForMainFrame == false) {
              return;
            }
            if (mounted) {
              setState(() {
                _errorMessage =
                    'WebView error (${error.errorCode}): ${error.description}';
              });
            }
          },
        ),
      )
      ..loadRequest(_authorizationUri);
  }

  Future<void> _handleOAuthRedirect(String redirectUrl) async {
    if (_hasInterceptedCode) return;
    _hasInterceptedCode = true;

    final uri = Uri.tryParse(redirectUrl);
    final code = uri?.queryParameters['code'];
    final error = uri?.queryParameters['error'];
    final errorDescription = uri?.queryParameters['error_description'];

    if (error != null && error.isNotEmpty) {
      if (mounted) {
        setState(() {
          _hasInterceptedCode = false;
          _errorMessage =
              'OAuth error: $error${errorDescription != null ? " ($errorDescription)" : ""}';
        });
      }
      return;
    }

    if (code == null || code.isEmpty) {
      if (mounted) {
        setState(() {
          _hasInterceptedCode = false;
          _errorMessage =
              'Redirect intercepted, but no authorization code was present.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isExchangingToken = true;
        _errorMessage = null;
      });
    }

    try {
      final session = await widget.kretaClient.exchangeCodeForTokens(
        code: code,
        codeVerifier: _pkce.codeVerifier,
        fallbackInstituteCode: widget.initialInstituteCode,
      );
      if (!mounted) return;
      Navigator.of(context).pop<StoredSession>(session);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExchangingToken = false;
        _hasInterceptedCode = false;
        _errorMessage = 'Token exchange failed: $e';
      });
    }
  }

  void _reloadFreshAuthSession() {
    setState(() {
      _hasInterceptedCode = false;
      _isExchangingToken = false;
      _errorMessage = null;
      _loadingProgress = 0;
      _pkce = PkcePair.generate();
      _authorizationUri = KretaAuthConfig.buildAuthorizationUri(
        pkce: _pkce,
        clientId: widget.kretaClient.clientId,
        instituteCode: widget.initialInstituteCode,
        loginHint: widget.initialUsername,
      );
    });
    _webViewController.loadRequest(_authorizationUri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('E-Kréta Bejelentkezés'),
        actions: [
          IconButton(
            tooltip: 'Újratöltés új PKCE munkamenettel',
            onPressed: _isExchangingToken ? null : _reloadFreshAuthSession,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: _loadingProgress < 100 || _isExchangingToken
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _isExchangingToken ? null : _loadingProgress / 100.0,
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_errorMessage != null)
                MaterialBanner(
                  backgroundColor: theme.colorScheme.errorContainer,
                  content: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: _reloadFreshAuthSession,
                      child: const Text('Újrapróbálás'),
                    ),
                  ],
                ),
              Expanded(
                child: WebViewWidget(controller: _webViewController),
              ),
            ],
          ),
          if (_isExchangingToken)
            Container(
              color: theme.colorScheme.surface.withValues(alpha: 0.88),
              alignment: Alignment.center,
              child: Card(
                elevation: 4,
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Kód beváltása tokenre (/connect/token)...',
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
