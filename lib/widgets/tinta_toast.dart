import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';
import '../utils/platform_support.dart';
import '../utils/uwu_helper.dart';
import 'real_liquid_glass_surface.dart';

enum TintaToastType {
  info,
  success,
  error,
}

/// Top-anchored unified floating notification capsule (`BorderRadius.circular(22)`)
/// inserted strictly into the root [Navigator] [Overlay] on a post-frame
/// callback so dismissing soft keyboards and bottom sheets never causes route
/// or visual glitching.
class TintaToast {
  TintaToast._();

  static OverlayEntry? _activeEntry;
  static int _generation = 0;

  static void dismissCurrent({bool immediate = true}) {
    _generation++;
    final entry = _activeEntry;
    _activeEntry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  static void show(
    BuildContext context,
    String message, {
    TintaToastType type = TintaToastType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    Color? accentColorOverride,
    OverlayState? overlayOverride,
  }) {
    final overlay = overlayOverride ??
        Navigator.maybeOf(context, rootNavigator: true)?.overlay ??
        Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);
    if (overlay == null) return;

    dismissCurrent(immediate: true);
    final int gen = _generation;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (gen != _generation || !overlay.mounted) return;

      late OverlayEntry entry;
      void removeSelf() {
        if (identical(_activeEntry, entry)) {
          _activeEntry = null;
        }
        if (entry.mounted) {
          entry.remove();
        }
      }

      entry = OverlayEntry(
        builder: (overlayContext) => _TintaToastOverlay(
          key: ValueKey<int>(gen),
          message: message,
          type: type,
          duration: duration,
          actionLabel: actionLabel,
          onAction: onAction,
          accentColorOverride: accentColorOverride,
          onDismissComplete: removeSelf,
        ),
      );

      _activeEntry = entry;
      overlay.insert(entry);
    });
  }

  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    Color? accentColorOverride,
    OverlayState? overlayOverride,
  }) =>
      show(
        context,
        message,
        type: TintaToastType.info,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        accentColorOverride: accentColorOverride,
        overlayOverride: overlayOverride,
      );

  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    Color? accentColorOverride,
    OverlayState? overlayOverride,
  }) =>
      show(
        context,
        message,
        type: TintaToastType.success,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        accentColorOverride: accentColorOverride,
        overlayOverride: overlayOverride,
      );

  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    Color? accentColorOverride,
    OverlayState? overlayOverride,
  }) =>
      show(
        context,
        message,
        type: TintaToastType.error,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        accentColorOverride: accentColorOverride,
        overlayOverride: overlayOverride,
      );
}

class _TintaToastOverlay extends StatefulWidget {
  final String message;
  final TintaToastType type;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accentColorOverride;
  final VoidCallback onDismissComplete;

  const _TintaToastOverlay({
    super.key,
    required this.message,
    required this.type,
    required this.duration,
    this.actionLabel,
    this.onAction,
    this.accentColorOverride,
    required this.onDismissComplete,
  });

  @override
  State<_TintaToastOverlay> createState() => _TintaToastOverlayState();
}

class _TintaToastOverlayState extends State<_TintaToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curved;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _dismissTimer;
  double _dragOffsetY = 0.0;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = _curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, -24),
      end: Offset.zero,
    ).animate(_curved);

    _controller.forward();
    _dismissTimer = Timer(widget.duration, _dismissWithAnimation);
  }

  void _dismissWithAnimation() {
    if (_isDismissing) return;
    _isDismissing = true;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (!mounted) {
      widget.onDismissComplete();
      return;
    }
    _controller.reverse().whenCompleteOrCancel(widget.onDismissComplete);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final liquidGlass = UserProfilePrefs.activeLiquidGlassEnabled;
    final realLiquidGlass =
        !isIOSPlatform && UserProfilePrefs.activeRealLiquidGlassEnabled;

    final Color accent;
    final IconData badgeIcon;
    switch (widget.type) {
      case TintaToastType.success:
        accent = widget.accentColorOverride ?? const Color(0xFF22C55E);
        badgeIcon = Icons.check_circle_rounded;
      case TintaToastType.error:
        accent = widget.accentColorOverride ?? const Color(0xFFEF4444);
        badgeIcon = Icons.error_outline_rounded;
      case TintaToastType.info:
        accent = widget.accentColorOverride ?? scheme.primary;
        badgeIcon = Icons.info_outline_rounded;
    }

    final surfaceFill = liquidGlass
        ? (isDark
            ? const Color(0xCC12141B)
            : Colors.white.withValues(alpha: 0.86))
        : (isDark ? const Color(0xF514161D) : const Color(0xF8FFFFFF));
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final topMargin = MediaQuery.paddingOf(context).top + 12.0;

    final Widget pillContentRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(
              color: accent.withValues(alpha: 0.38),
              width: 0.9,
            ),
          ),
          child: Icon(
            badgeIcon,
            size: 16,
            color: accent,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            uwu(widget.message),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        if (widget.actionLabel != null && widget.onAction != null) ...[
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final cb = widget.onAction;
              _dismissWithAnimation();
              cb?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accent.withValues(alpha: 0.42),
                  width: 0.8,
                ),
              ),
              child: Text(
                uwuLabel(widget.actionLabel!),
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    final Widget pillContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceFill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.38 : 0.34),
          width: 1.0,
        ),
      ),
      child: pillContentRow,
    );

    final Widget decoratedPill = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: realLiquidGlass
          ? RealLiquidGlassSurface(
              borderRadius: BorderRadius.circular(22),
              tintColor: surfaceFill,
              compactOptics: true,
              highContrast: true,
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.44 : 0.38),
                width: 1.0,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: pillContentRow,
              ),
            )
          : (liquidGlass
              ? RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                      child: pillContent,
                    ),
                  ),
                )
              : pillContent),
    );

    return Positioned(
      top: topMargin,
      left: 16,
      right: 16,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(_slide.value.dx, _slide.value.dy + _dragOffsetY),
                child: Opacity(
                  opacity: _fade.value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: Dismissible(
              key: ValueKey<String>('tinta-toast-${widget.hashCode}'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) {
                _isDismissing = true;
                _dismissTimer?.cancel();
                _dismissTimer = null;
                widget.onDismissComplete();
              },
              child: GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.delta.dy < 0 || _dragOffsetY < 0) {
                    setState(() {
                      _dragOffsetY =
                          (_dragOffsetY + details.delta.dy).clamp(-64.0, 0.0);
                    });
                  }
                },
                onVerticalDragEnd: (details) {
                  if (_dragOffsetY < -16 ||
                      (details.primaryVelocity ?? 0.0) < -240) {
                    _dismissWithAnimation();
                  } else if (_dragOffsetY != 0.0) {
                    setState(() => _dragOffsetY = 0.0);
                  }
                },
                child: Material(
                  type: MaterialType.transparency,
                  child: decoratedPill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
