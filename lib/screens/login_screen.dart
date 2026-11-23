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

/// Clean, editorial showcase login screen on pure `#000000` OLED black with
/// static, deliberately cropped/zoomed-in phone mockups, bottom-nav-free
/// framing, crisp typography, and a thumb-accessible WebAuth CTA.
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
  final String editorialTitleTop;
  final String editorialTitleAccent;
  final String caption;
  final Color accentColor;
  final Alignment focusAlignment;
  final double cropZoom;

  const _ShowcaseSlideSpec({
    required this.assetPath,
    required this.aspectRatio,
    required this.statusBarTime,
    required this.editorialTitleTop,
    required this.editorialTitleAccent,
    required this.caption,
    required this.accentColor,
    required this.focusAlignment,
    required this.cropZoom,
  });
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _oledBlack = Color(0xFF000000);
  static const Color _crispOffWhite = Color(0xFFF8FAFC);
  static const double _showcaseAspectRatio = 1440 / 2992;

  static const List<_ShowcaseSlideSpec> _screenshotSlides = [
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_home.webp',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      editorialTitleTop: 'Aktuális óra,',
      editorialTitleAccent: 'egy pillantásra.',
      caption:
          'Minden fontos infó egy helyen - aktuális óra, házik és jegyek átlaghatással.',
      accentColor: Color(0xFF3B82F6),
      focusAlignment: Alignment(0.0, -0.78),
      cropZoom: 1.18,
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_timetable.webp',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      editorialTitleTop: 'Tiszta napirend,',
      editorialTitleAccent: 'káosz nélkül.',
      caption:
          'Átlátható heti órarend helyettesítésekkel, elmaradt órákkal és házikkal.',
      accentColor: Color(0xFF06B6D4),
      focusAlignment: Alignment(0.0, -0.34),
      cropZoom: 1.16,
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_grades.webp',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      editorialTitleTop: 'Átlaghatás,',
      editorialTitleAccent: 'tizedre pontosan.',
      caption:
          'Tantárgyankénti átlagok és jegyek, rendezhetően és azonnal átláthatóan.',
      accentColor: Color(0xFF22C55E),
      focusAlignment: Alignment(0.0, -0.68),
      cropZoom: 1.18,
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_scholarship.webp',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      editorialTitleTop: 'Tűzd ki a célt,',
      editorialTitleAccent: 'mérd a lépést.',
      caption:
          'Tűzd ki, érd el - kövesd az ösztöndíjadat és a következő sávhoz szükséges lépéseket.',
      accentColor: Color(0xFFF59E0B),
      focusAlignment: Alignment(0.0, -0.38),
      cropZoom: 1.15,
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_absences.webp',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      editorialTitleTop: 'Minden mulasztás',
      editorialTitleAccent: 'tiszta keretben.',
      caption:
          'Hiányzások tantárgyanként és napi órarend-nézetben, pirossal kiemelve.',
      accentColor: Color(0xFFEF4444),
      focusAlignment: Alignment(0.0, -0.45),
      cropZoom: 1.16,
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_themes.webp',
      aspectRatio: _showcaseAspectRatio,
      statusBarTime: LoginScreen.fixedStatusBarTime,
      editorialTitleTop: 'OLED fekete,',
      editorialTitleAccent: 'folyékony üveg.',
      caption:
          'OLED fekete, Material You és Liquid Glass - szabd teljesen magadra az appot.',
      accentColor: Color(0xFFA855F7),
      focusAlignment: Alignment(0.0, -0.28),
      cropZoom: 1.15,
    ),
  ];

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
  double _pagePosition = _kInfiniteBasePage.toDouble();
  bool _userTouching = false;
  bool _screenshotsPrecached = false;

  @override
  void initState() {
    super.initState();
    _menetrendLinkRecognizer = TapGestureRecognizer()
      ..onTap = _openMenetrendGoWebsite;

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
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

    _pageController.addListener(_onPageScroll);
    _startAutoAdvance();
  }

  void _onPageScroll() {
    if (!_pageController.hasClients) return;
    final nextPos = _pageController.page ?? _currentPage.toDouble();
    if ((nextPos - _pagePosition).abs() > 0.002 && mounted) {
      setState(() => _pagePosition = nextPos);
    }
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
        duration: const Duration(milliseconds: 520),
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
    _pageController.removeListener(_onPageScroll);
    _menetrendLinkRecognizer.dispose();
    _entranceController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Color _activeAccentColor(int normalizedIdx) {
    if (normalizedIdx < _screenshotSlides.length) {
      return _screenshotSlides[normalizedIdx].accentColor;
    }
    return const Color(0xFF38BDF8);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activeIdx = _currentPage % _slideCount;
    final activeAccent = _activeAccentColor(activeIdx);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: OledTheme.systemOverlayStyleForBrightness(Brightness.dark),
      child: Scaffold(
        backgroundColor: _oledBlack,
        body: ColoredBox(
          color: _oledBlack,
          child: Stack(
            children: [
              // Subtle asymmetric ambient spotlight shifted toward the phone stage.
              Positioned(
                top: -60,
                right: -80,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    width: 340,
                    height: 340,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          activeAccent.withValues(alpha: 0.22),
                          activeAccent.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compactHeight = constraints.maxHeight < 680;
                        final activeSlide = activeIdx < _screenshotSlides.length
                            ? _screenshotSlides[activeIdx]
                            : null;
                        final activeAccent =
                            activeSlide?.accentColor ?? const Color(0xFF38BDF8);

                        return Padding(
                          padding: EdgeInsets.only(
                            top: compactHeight ? 8 : 14,
                            bottom: compactHeight ? 10 : 16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: _buildBrandHeader(
                                  theme,
                                  compactHeight: compactHeight,
                                ),
                              ),
                              SizedBox(height: compactHeight ? 6 : 12),
                              Expanded(
                                child: Listener(
                                  onPointerDown: (_) => _onUserTouchStart(),
                                  onPointerUp: (_) => _onUserTouchEnd(),
                                  onPointerCancel: (_) => _onUserTouchEnd(),
                                  child: RepaintBoundary(
                                    child: PageView.builder(
                                      clipBehavior: Clip.none,
                                      controller: _pageController,
                                      physics: const BouncingScrollPhysics(),
                                      onPageChanged: (idx) {
                                        if (mounted) {
                                          setState(() => _currentPage = idx);
                                        }
                                      },
                                      itemBuilder: (context, index) =>
                                          _buildShowcaseSlide(
                                        context,
                                        theme,
                                        scheme,
                                        index,
                                        compactHeight: compactHeight,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: compactHeight ? 6 : 10),
                              _buildSlideProgressBar(
                                activeIdx,
                                activeAccent,
                              ),
                              SizedBox(height: compactHeight ? 10 : 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: _buildHeroCtaSection(
                                  theme,
                                  scheme,
                                  activeAccent,
                                  compactHeight: compactHeight,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _jumpToSlide(int targetModIdx) {
    if (!_pageController.hasClients) return;
    HapticFeedback.selectionClick();
    final currentWhole = _pageController.page?.round() ?? _currentPage;
    final currentMod = currentWhole % _slideCount;
    var delta = targetModIdx - currentMod;
    if (delta > _slideCount ~/ 2) delta -= _slideCount;
    if (delta < -(_slideCount ~/ 2)) delta += _slideCount;
    _onUserTouchStart();
    _pageController
        .animateToPage(
          currentWhole + delta,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(_onUserTouchEnd);
  }

  Widget _buildBrandHeader(
    ThemeData theme, {
    required bool compactHeight,
  }) {
    return Row(
      children: [
        AppBrandIconBadge(
          prefs: widget.prefs,
          size: compactHeight ? 34 : 38,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            uwu('Tinta Napló'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: compactHeight ? 18.5 : 20.5,
              fontWeight: FontWeight.w900,
              color: _crispOffWhite,
              letterSpacing: -0.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlideProgressBar(int activeIdx, Color activeAccent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < _slideCount; i++)
          GestureDetector(
            key: ValueKey<String>('login-slide-dot-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _jumpToSlide(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: i == activeIdx ? 24 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == activeIdx
                      ? activeAccent
                      : Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: i == activeIdx
                      ? [
                          BoxShadow(
                            color: activeAccent.withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeroCtaSection(
    ThemeData theme,
    ColorScheme scheme,
    Color activeAccent, {
    required bool compactHeight,
  }) {
    return FadeTransition(
      opacity: _heroFade,
      child: SlideTransition(
        position: _heroSlide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.center,
              child: RichText(
                key: const ValueKey<String>('login-hero-headline'),
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: OledTheme.defaultFontFamily,
                    color: _crispOffWhite.withValues(alpha: 0.90),
                    fontSize: compactHeight ? 18 : 21,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.16,
                  ),
                  children: [
                    TextSpan(
                      text: '${uwu('Készen állsz valami')} ',
                    ),
                    TextSpan(
                      text: uwu('igazán jóra?'),
                      style: TextStyle(
                        fontFamily: OledTheme.defaultFontFamily,
                        color: const Color(0xFF3B82F6),
                        fontSize: compactHeight ? 19 : 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: compactHeight ? 10 : 12),
            TactileBounce(
              pressedScale: 0.97,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onLaunchWebAuth();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                height: compactHeight ? 48 : 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary,
                      Color.lerp(scheme.primary, activeAccent, 0.24) ??
                          scheme.primary,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                    width: 0.9,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.34),
                      blurRadius: 22,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 19,
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
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: scheme.onPrimary.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: compactHeight ? 6 : 8),
            Center(
              child: GestureDetector(
                key: const ValueKey<String>('login-privacy-legal-link'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  showPrivacyAndLegalModal(context, prefs: widget.prefs);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    uwu('Nem hivatalos e-KRÉTA kliens • Adatvédelem'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: _crispOffWhite.withValues(alpha: 0.50),
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
    int pageIndex, {
    required bool compactHeight,
  }) {
    final index = pageIndex % _slideCount;
    final bool isScreenshotSlide = index < _screenshotSlides.length;
    final spec = isScreenshotSlide ? _screenshotSlides[index] : null;
    final accent = spec?.accentColor ?? const Color(0xFF38BDF8);
    final titleTop = spec?.editorialTitleTop ?? 'Mindig tudd,';
    final titleAccent = spec?.editorialTitleAccent ?? 'mikor indulj.';
    final pageDelta = (_pagePosition - pageIndex).clamp(-1.0, 1.0);
    final absDelta = pageDelta.abs();
    final stageScale = (1.0 - absDelta * 0.09).clamp(0.85, 1.0);
    final stageOpacity = (1.0 - absDelta * 0.52).clamp(0.32, 1.0);
    final captionOpacity = (1.0 - absDelta * 0.85).clamp(0.0, 1.0);

    final baseCaptionStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: compactHeight ? 11.5 : 12.5,
      fontWeight: FontWeight.w500,
      color: _crispOffWhite.withValues(alpha: 0.72),
      height: 1.32,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Frameless floating hero showcase visual with ambient depth glow.
          // The reworked screenshot asset is rendered cleanly & directly without
          // any fake device bezel, cutout, or artificial crop.
          Expanded(
            child: Opacity(
              opacity: stageOpacity,
              child: Transform.translate(
                offset: Offset(0, absDelta * 10),
                child: Transform.scale(
                  scale: stageScale,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Soft ambient reactive light bloom behind the screenshot
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, -0.05),
                              radius: 0.78,
                              colors: [
                                accent.withValues(alpha: 0.22),
                                accent.withValues(alpha: 0.06),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.48, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Container(
                        key: ValueKey<String>('login-showcase-stage-$index'),
                        padding: EdgeInsets.symmetric(
                          horizontal: compactHeight ? 6 : 10,
                          vertical: compactHeight ? 2 : 4,
                        ),
                        child: isScreenshotSlide
                            ? Image.asset(
                                spec!.assetPath,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              )
                            : _buildExpandedMenetrendFrame(theme, scheme),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: compactHeight ? 6 : 10),
          // 2. Editorial copy synchronized with subtle horizontal parallax
          Opacity(
            opacity: captionOpacity,
            child: Transform.translate(
              offset: Offset(-pageDelta * 16, 0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(
                          fontFamily: OledTheme.defaultFontFamily,
                          fontSize: compactHeight ? 17.5 : 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          height: 1.12,
                          color: _crispOffWhite,
                        ),
                        children: [
                          TextSpan(text: '${uwu(titleTop)} '),
                          TextSpan(
                            text: uwu(titleAccent),
                            style: TextStyle(color: accent),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    isScreenshotSlide
                        ? Text(
                            uwu(spec!.caption),
                            textAlign: TextAlign.left,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: baseCaptionStyle,
                          )
                        : Text.rich(
                            TextSpan(
                              style: baseCaptionStyle,
                              children: [
                                TextSpan(
                                  text: uwu(
                                    'Mindig tudd, mikor kell menned, a ',
                                  ),
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
                            textAlign: TextAlign.left,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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

  Widget _buildExpandedMenetrendFrame(
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = math.min(math.max(constraints.maxWidth, 320.0), 356.0);
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: cardWidth,
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF101622),
                      Color(0xFF090C12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.24),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
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
