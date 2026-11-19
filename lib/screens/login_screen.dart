import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/token_storage_service.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';

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

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _ShowcaseSlideSpec {
  final String assetPath;
  final double aspectRatio;
  final String caption;

  const _ShowcaseSlideSpec({
    required this.assetPath,
    required this.aspectRatio,
    required this.caption,
  });
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  static const Color _oledBlack = Color(0xFF000000);
  static const Color _crispOffWhite = Color(0xFFF8FAFC);

  static const List<_ShowcaseSlideSpec> _screenshotSlides = [
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_1_lesson.webp',
      aspectRatio: 1440 / 860,
      caption:
          'Kövesd az órád, lásd a következőt. Mindig képben lehetsz a napod menetével.',
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_2_scholarship.webp',
      aspectRatio: 1438 / 2527,
      caption:
          'Tűzd ki, érd el. Az ösztöndíj-kalkulátorral semmi se lehetetlen.',
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_3_timetable.webp',
      aspectRatio: 1440 / 2373,
      caption:
          'Egyből csak a lényeg. Lásd könnyen, milyen órád marad el, és melyik lesz helyettesítve.',
    ),
    _ShowcaseSlideSpec(
      assetPath: 'assets/images/showcase/showcase_4_themes.webp',
      aspectRatio: 1440 / 3002,
      caption:
          'A végtelen személyre szabásnak köszönhetően igazán olyan lehet az app, amilyennek Te elképzelted.',
    ),
  ];

  static final Uri _menetrendGoUri = Uri.parse('https://menetrendgo.hu');

  static int get _slideCount => _screenshotSlides.length + 1;

  final PageController _pageController = PageController(viewportFraction: 0.85);
  late final AnimationController _entranceController;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;
  late final TapGestureRecognizer _menetrendLinkRecognizer;

  Timer? _autoAdvanceTimer;
  Timer? _resumeTimer;
  int _currentPage = 0;
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
    await launchUrl(
      _menetrendGoUri,
      mode: LaunchMode.inAppBrowserView,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_screenshotsPrecached) {
      _screenshotsPrecached = true;
      for (final slide in _screenshotSlides) {
        precacheImage(AssetImage(slide.assetPath), context);
      }
    }
  }

  void _startAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _userTouching || !_pageController.hasClients) {
        return;
      }
      final next = (_currentPage + 1) % _slideCount;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
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

    return Scaffold(
      backgroundColor: _oledBlack,
      body: ColoredBox(
        color: _oledBlack,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 22),
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
                            itemCount: _slideCount,
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
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildPageIndicators(scheme),
                    ),
                    const SizedBox(height: 20),
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

  Widget _buildPageIndicators(ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_slideCount, (index) {
        final selected = index == _currentPage;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            _onUserTouchStart();
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            );
            _onUserTouchEnd();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: selected ? 26 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary
                    : _crispOffWhite.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      }),
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
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF38BDF8)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(bounds),
                child: Text(
                  uwu('Készen állsz?'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
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
            child: isScreenshotSlide
                ? _buildSeamlessScreenshot(_screenshotSlides[index])
                : _buildExpandedMenetrendFrame(theme, scheme),
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

  Widget _buildSeamlessScreenshot(_ShowcaseSlideSpec spec) {
    return Center(
      child: AspectRatio(
        aspectRatio: spec.aspectRatio,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.12, 0.85, 1.0],
          ).createShader(bounds),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              spec.assetPath,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
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
          final cardWidth = math.min(constraints.maxWidth, 360.0);
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
