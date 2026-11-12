import 'package:flutter/material.dart';

/// Immutable left/right fade state computed from horizontal scroll metrics.
@immutable
class _FadeEdges {
  final bool fadeLeft;
  final bool fadeRight;

  const _FadeEdges({required this.fadeLeft, required this.fadeRight});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FadeEdges &&
          other.fadeLeft == fadeLeft &&
          other.fadeRight == fadeRight;

  @override
  int get hashCode => Object.hash(fadeLeft, fadeRight);
}

/// Lightweight, 120fps-safe horizontal scroll wrapper that eliminates mid-screen
/// hard clipping and accidental right-end auto-scrolling.
///
/// Guarantees:
/// - Always starts cleanly at the leftmost item (`reverse: false` with a
///   `ScrollController(initialScrollOffset: 0.0)`).
/// - Applies horizontal padding *inside* the scroll view (`padding`,
///   defaulting to `EdgeInsets.symmetric(horizontal: 16)`) so content scrolls
///   full-bleed edge-to-edge.
/// - Dynamically fades overflowing left (`0.0 -> 0.06` when `offset > 2.0`)
///   and right (`0.94 -> 1.0` when `offset < maxScrollExtent - 2.0`) borders
///   via a lightweight `ShaderMask` (`BlendMode.dstIn`) without heavy blur
///   shaders or per-frame widget tree rebuilds.
class EdgeFadeHorizontalScroll extends StatefulWidget {
  final List<Widget>? children;
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final CrossAxisAlignment crossAxisAlignment;
  final Clip clipBehavior;

  const EdgeFadeHorizontalScroll({
    super.key,
    this.children,
    this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.spacing = 0,
    this.controller,
    this.physics,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.clipBehavior = Clip.hardEdge,
  }) : assert(
          children != null || child != null,
          'Provide either children or child to EdgeFadeHorizontalScroll.',
        );

  @override
  State<EdgeFadeHorizontalScroll> createState() =>
      _EdgeFadeHorizontalScrollState();
}

class _EdgeFadeHorizontalScrollState extends State<EdgeFadeHorizontalScroll> {
  late ScrollController _controller;
  late bool _ownsController;
  bool _didResetInitialScroll = false;
  final ValueNotifier<_FadeEdges> _edges = ValueNotifier<_FadeEdges>(
    const _FadeEdges(fadeLeft: false, fadeRight: false),
  );

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        ScrollController(initialScrollOffset: 0.0, keepScrollOffset: false);
    _controller.addListener(_updateEdgesFromController);
    _scheduleInitialResetAndEdgeUpdate();
  }

  void _scheduleInitialResetAndEdgeUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_didResetInitialScroll && _controller.hasClients) {
        _didResetInitialScroll = true;
        if (_controller.offset != 0.0) {
          _controller.jumpTo(0.0);
        }
      }
      _updateEdgesFromController();
    });
  }

  @override
  void didUpdateWidget(covariant EdgeFadeHorizontalScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_updateEdgesFromController);
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ??
          ScrollController(initialScrollOffset: 0.0, keepScrollOffset: false);
      _controller.addListener(_updateEdgesFromController);
      _didResetInitialScroll = false;
      _scheduleInitialResetAndEdgeUpdate();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateEdgesFromController();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateEdgesFromController);
    if (_ownsController) {
      _controller.dispose();
    }
    _edges.dispose();
    super.dispose();
  }

  void _updateEdgesFromController() {
    if (!mounted || !_controller.hasClients) return;
    _updateEdges(_controller.position);
  }

  void _updateEdges(ScrollMetrics metrics) {
    if (!mounted || !metrics.hasContentDimensions || !metrics.hasPixels) {
      return;
    }
    final maxExtent = metrics.maxScrollExtent;
    final offset = metrics.pixels;
    final hasOverflow = maxExtent > 2.0;
    final next = _FadeEdges(
      fadeLeft: hasOverflow && offset > 2.0,
      fadeRight: hasOverflow && offset < (maxExtent - 2.0),
    );
    if (_edges.value != next) {
      _edges.value = next;
    }
  }

  LinearGradient _buildMaskGradient(_FadeEdges edges) {
    if (edges.fadeLeft && edges.fadeRight) {
      return const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0.0, 0.06, 0.94, 1.0],
      );
    }
    if (edges.fadeLeft) {
      return const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.transparent, Colors.white, Colors.white],
        stops: [0.0, 0.06, 1.0],
      );
    }
    if (edges.fadeRight) {
      return const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, 0.94, 1.0],
      );
    }
    return const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Colors.white, Colors.white],
      stops: [0.0, 1.0],
    );
  }

  Widget _buildRowContent() {
    if (widget.child != null) return widget.child!;
    final items = widget.children!;
    if (widget.spacing <= 0 || items.length <= 1) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: widget.crossAxisAlignment,
        children: items,
      );
    }
    final spaced = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) spaced.add(SizedBox(width: widget.spacing));
      spaced.add(items[i]);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.crossAxisAlignment,
      children: spaced,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scrollChild = NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.horizontal) {
          _updateEdges(notification.metrics);
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        reverse: false,
        primary: false,
        clipBehavior: widget.clipBehavior,
        physics: widget.physics ?? const BouncingScrollPhysics(),
        padding: widget.padding,
        child: _buildRowContent(),
      ),
    );

    return ValueListenableBuilder<_FadeEdges>(
      valueListenable: _edges,
      child: scrollChild,
      builder: (context, edges, staticChild) {
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => _buildMaskGradient(edges).createShader(rect),
          child: staticChild,
        );
      },
    );
  }
}
