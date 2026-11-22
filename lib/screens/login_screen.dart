import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/privacy_legal_modal.dart';

/// Showcase-driven WebAuth-only login screen seamlessly integrated on pure
/// `#000000` OLED black with horizontal/vertical alpha fades and a single CTA.
class LoginScreen extends StatefulWidget {
  final UserProfilePrefs prefs;
  final VoidCallback onLaunchWebAuth;

  const LoginScreen({
    super.key,
    required this.prefs,
    required this.onLaunchWebAuth,
  });

  static const String fixedStatusBarTime = '08:02';

  /// Extracts `HH:MM` from real screenshot EXIF `DateTimeOriginal`, Android
  /// screenshot filenames (`Screenshot_YYYYMMDD_HHMMSS`), or file timestamps.
  static String formatStatusBarTimeFromMetadata({
    String? exifDateTime,
    String? filename,
    DateTime? modifiedAt,
    String fallback = fixedStatusBarTime,
  }) {
    if (exifDateTime != null) {
      final match = RegExp(
        r'\d{4}[:\-]\d{2}[:\-]\d{2}[ T](\d{2}):(\d{2})',
      ).firstMatch(exifDateTime.trim());
      if (match != null) {
        return '${match.group(1)}:${match.group(2)}';
      }
    }
    if (filename != null) {
      final match = RegExp(
        r'\d{8}[_\-](\d{2})(\d{2})\d{2}',
      ).firstMatch(filename.trim());
      if (match != null) {
        return '${match.group(1)}:${match.group(2)}';
      }
    }
    if (modifiedAt != null) {
      final local = modifiedAt.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    return fallback;
  }

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _ShowcaseSlideSpec {
  final String assetPath;
  final double aspectRatio;
  final String statusBarTime;
  final String caption;

  const _ShowcaseSlideSpec({
    required this.assetPath,
    required this.aspectRatio,
    required this.statusBarTime,
    required this.caption,
  });
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  static const Color _oledBlack = Color(0xFF000000);
  static const Color _crispOffWhite = Color(0xFFF8FAFC);
  static const double _showcaseAspectRatio = 1440 / 2992;

  static const List<_ShowcaseSlideSpec> _screenshotSlides = [
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_home.jpg',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      caption:
          'Minden fontos infó egy helyen - aktuális óra, házik és jegyek átlaghatással.',
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_timetable.jpg',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      caption:
          'Átlátható heti órarend helyettesítésekkel, elmaradt órákkal és házikkal.',
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_grades.jpg',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      caption:
          'Tantárgyankénti átlagok és jegyek, rendezhetően és azonnal átláthatóan.',
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_scholarship.jpg',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      caption:
          'Tűzd ki, érd el - kövesd az ösztöndíjadat és a következő sávhoz szükséges lépéseket.',
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_absences.jpg',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      caption:
          'Hiányzások tantárgyanként és napi órarend-nézetben, pirossal kiemelve.',
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_themes.jpg',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      caption:
          'OLED fekete, Material You és Liquid Glass - szabd teljesen magadra az appot.',
    ),
  ];
  static const String _menetrendSlideStatusBarTime =
      LoginScreen.fixedStatusBarTime;

  static final Uri _menetrendGoUri = Uri.parse('https://menetrendgo.hu');

  static int get _slideCount => _screenshotSlides.length + 1;
  static const int _kInfiniteBasePage = 7000;

  final PageController _pageController = PageController(
    initialPage: _kInfiniteBasePage,
    viewportFraction: 0.85,
  );
  late final AnimationController _entranceController;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;
  late final TapGestureRecognizer _menetrendLinkRecognizer;

  Timer? _autoAdvanceTimer;
  Timer? _resumeTimer;
  int _currentPage = _kInfiniteBasePage;
  bool _userTouching = false;
  bool _screenshotsPrecached = false;

  @override
  void initState() {
    super.initState();
    _menetrendLinkRecognizer = TapGestureRecognizer()
      ..onTap = _openMenetrendGoWebsite;

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _heroFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutCubic,
      ),
    );
    _entranceController.forward();

    _startAutoAdvance();
  }

  Future<void> _openMenetrendGoWebsite() async {
    HapticFeedback.lightImpact();
    try {
      await launchUrl(
        _menetrendGoUri,
        mode: LaunchMode.inAppBrowserView,
      );
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_screenshotsPrecached) {
      _screenshotsPrecached = true;
      for (final slide in _screenshotSlides) {
        unawaited(
          precacheImage(AssetImage(slide.assetPath), context).catchError((_) {}),
        );
      }
    }
  }

  void _startAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _userTouching || !_pageController.hasClients) {
        return;
      }
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onUserTouchStart() {
    _userTouching = true;
    _resumeTimer?.cancel();
    _autoAdvanceTimer?.cancel();
  }

  void _onUserTouchEnd() {
    _userTouching = false;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _userTouching) return;
      _startAutoAdvance();
    });
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _resumeTimer?.cancel();
    _menetrendLinkRecognizer.dispose();
    _entranceController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: OledTheme.systemOverlayStyleForBrightness(Brightness.dark),
      child: Scaffold(
        backgroundColor: _oledBlack,
      body: ColoredBox(
        color: _oledBlack,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildBrandHeader(theme),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) => _onUserTouchStart(),
                        onPointerUp: (_) => _onUserTouchEnd(),
                        onPointerCancel: (_) => _onUserTouchEnd(),
                        child: RepaintBoundary(
                          child: ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (bounds) => const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.transparent,
                                Colors.black,
                                Colors.black,
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.09, 0.91, 1.0],
                            ).createShader(bounds),
                            child: PageView.builder(
                              clipBehavior: Clip.none,
                              controller: _pageController,
                              physics: const BouncingScrollPhysics(),
                              onPageChanged: (idx) {
                                _currentPage = idx;
                              },
                              itemBuilder: (context, index) =>
                                  _buildShowcaseSlide(
                                context,
                                theme,
                                scheme,
                                index % _slideCount,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildHeroCtaSection(theme, scheme),
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

  Widget _buildBrandHeader(ThemeData theme) {
    return Row(
      children: [
        AppBrandIconBadge(
          prefs: widget.prefs,
          size: 42,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            uwu('Tinta Napló'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: _crispOffWhite,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCtaSection(ThemeData theme, ColorScheme scheme) {
    return FadeTransition(
      opacity: _heroFade,
      child: SlideTransition(
        position: _heroSlide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: RichText(
                key: const ValueKey<String>('login-hero-headline'),
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: OledTheme.defaultFontFamily,
                    color: _crispOffWhite,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.18,
                  ),
                  children: [
                    TextSpan(
                      text: '${uwu('Készen állsz valami')}\n',
                    ),
                    TextSpan(
                      text: uwu('igazán jóra?'),
                      style: const TextStyle(
                        fontFamily: OledTheme.defaultFontFamily,
                        color: Color(0xFF3B82F6),
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TactileBounce(
              pressedScale: 0.97,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onLaunchWebAuth();
              },
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 20,
                      color: scheme.onPrimary,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        uwu('Bejelentkezés KRÉTA-val'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                key: const ValueKey<String>('login-privacy-legal-link'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  showPrivacyAndLegalModal(context, prefs: widget.prefs);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    uwu('Nem hivatalos e-KRÉTA kliens • Adatvédelem'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: _crispOffWhite.withValues(alpha: 0.48),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowcaseSlide(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    int index,
  ) {
    final bool isScreenshotSlide = index < _screenshotSlides.length;
    final baseCaptionStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: _crispOffWhite.withValues(alpha: 0.78),
      height: 1.38,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _buildPhoneMockupFrame(
              slideIndex: index,
              statusBarTime: isScreenshotSlide
                  ? _screenshotSlides[index].statusBarTime
                  : _menetrendSlideStatusBarTime,
              child: isScreenshotSlide
                  ? _buildSeamlessScreenshot(_screenshotSlides[index])
                  : _buildExpandedMenetrendFrame(theme, scheme),
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: isScreenshotSlide
                ? Text(
                    uwu(_screenshotSlides[index].caption),
                    textAlign: TextAlign.center,
                    style: baseCaptionStyle,
                  )
                : Text.rich(
                    TextSpan(
                      style: baseCaptionStyle,
                      children: [
                        TextSpan(
                          text: uwu('Mindig tudd, mikor kell menned, a '),
                        ),
                        TextSpan(
                          text: 'MenetrendGO',
                          recognizer: _menetrendLinkRecognizer,
                          style: baseCaptionStyle?.copyWith(
                            color: const Color(0xFF38BDF8),
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                            decorationColor: const Color(0xFF38BDF8)
                                .withValues(alpha: 0.72),
                          ),
                        ),
                        TextSpan(
                          text: uwu(' integrációnak köszönhetően.'),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneMockupFrame({
    required int slideIndex,
    required String statusBarTime,
    required Widget child,
  }) {
    return RepaintBoundary(
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: SizedBox(
            width: 260,
            height: 508,
            child: Container(
              key: ValueKey<String>('login-phone-mockup-$slideIndex'),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E14),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: const Color(0xFF2B3240),
                  width: 2.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.05),
                    blurRadius: 1,
                    spreadRadius: 0.5,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.70),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: const Color(0xFF04060A),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                        child: Row(
                          children: [
                            Text(
                              statusBarTime,
                              key: ValueKey<String>('login-phone-time-$slideIndex'),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xD8F8FAFC),
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF020305),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF262D3A),
                                  width: 1.0,
                                ),
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.signal_cellular_4_bar_rounded,
                              size: 11,
                              color: Color(0xCCF8FAFC),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.wifi_rounded,
                              size: 11,
                              color: Color(0xCCF8FAFC),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.battery_full_rounded,
                              size: 11,
                              color: Color(0xCCF8FAFC),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: child,
                        ),
                      ),
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 7),
                          width: 56,
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: _crispOffWhite.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(999),
                          ),
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
    );
  }

  Widget _buildSeamlessScreenshot(_ShowcaseSlideSpec spec) {
    return Center(
      child: AspectRatio(
        aspectRatio: spec.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            spec.assetPath,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedMenetrendFrame(
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = math.min(math.max(constraints.maxWidth, 336.0), 360.0);
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: cardWidth,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D13),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                    width: 1.0,
                  ),
                ),
                child: _buildExpandedMenetrendContent(theme, scheme),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExpandedMenetrendContent(
    ThemeData theme,
    ColorScheme scheme,
  ) {
    const onTimeGreen = Color(0xFF22C55E);
    const accentCyan = Color(0xFF38BDF8);
    final secondaryText = _crispOffWhite.withValues(alpha: 0.66);
    final timelineSurface = Colors.white.withValues(alpha: 0.04);
    final timelineBorder = Colors.white.withValues(alpha: 0.08);
    final routeAccent =
        scheme.primary.computeLuminance() > 0.2 ? scheme.primary : accentCyan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: onTimeGreen.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: onTimeGreen.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 13,
                        color: onTimeGreen,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Időben',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: onTimeGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: routeAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: routeAccent.withValues(alpha: 0.42),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'MenetrendGO',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: routeAccent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 13,
                        color: routeAccent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: routeAccent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: routeAccent.withValues(alpha: 0.34),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.train_rounded,
                    size: 15,
                    color: routeAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'S70',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: routeAccent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uwu('Reggeli bejárás'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: _crispOffWhite,
                    ),
                  ),
                  Text(
                    uwu('1. óra: Matematika (08:00)'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timelapse_rounded,
                    size: 13,
                    color: secondaryText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '28 perc',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _crispOffWhite,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: timelineSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: timelineBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTimelineStopRow(
                theme: theme,
                dotColor: routeAccent,
                filledDot: true,
                time: '07:12',
                station: 'Kezdőállomás',
                detail: '2. vágány • Séta ind.: 07:06 (6 perc)',
                secondaryText: secondaryText,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Row(
                  children: [
                    Container(
                      width: 2,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            routeAccent.withValues(alpha: 0.75),
                            onTimeGreen.withValues(alpha: 0.75),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: routeAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.swap_horiz_rounded,
                              size: 13,
                              color: routeAccent,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                uwu('3 megálló • Átszállás: Központ (3 p)'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: routeAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildTimelineStopRow(
                theme: theme,
                dotColor: onTimeGreen,
                filledDot: false,
                time: '07:40',
                station: 'Gimnázium megálló',
                detail: 'Cél séta: 6 perc az iskola bejáratáig',
                secondaryText: secondaryText,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: onTimeGreen.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: onTimeGreen.withValues(alpha: 0.34),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.school_rounded,
                size: 16,
                color: onTimeGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  uwu('14 perccel az 1. óra előtt beérsz'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: onTimeGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '07:46',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: onTimeGreen,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineStopRow({
    required ThemeData theme,
    required Color dotColor,
    required bool filledDot,
    required String time,
    required String station,
    required String detail,
    required Color secondaryText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filledDot ? dotColor : Colors.transparent,
            border: Border.all(color: dotColor, width: 2.2),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 46,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              time,
              maxLines: 1,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: _crispOffWhite,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                uwu(station),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _crispOffWhite,
                ),
              ),
              Text(
                uwu(detail),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10.8,
                  color: secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
