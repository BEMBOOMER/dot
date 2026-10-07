import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'dot_sphere.dart';

class DotsStage extends StatefulWidget {
  final ConnectionStatus status;
  final bool reducedMotion;

  const DotsStage({
    super.key,
    required this.status,
    required this.reducedMotion,
  });

  @override
  State<DotsStage> createState() => DotsStageState();
}

class DotsStageState extends State<DotsStage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _active = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _active = state == AppLifecycleState.resumed);
  }

  late AnimationController _ambientController;
  late AnimationController _transitionController;
  late AnimationController _pulseController;
  late AnimationController _receivePulseController;

  late ConnectionStatus _previousStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _receivePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _previousStatus = widget.status;
  }

  @override
  void didUpdateWidget(covariant DotsStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _previousStatus = oldWidget.status;
      if (widget.reducedMotion) {
        _transitionController.value = 1;
      } else {
        _transitionController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ambientController.dispose();
    _transitionController.dispose();
    _pulseController.dispose();
    _receivePulseController.dispose();
    super.dispose();
  }

  void sendPulse() {
    if (widget.reducedMotion || !_active) return;
    _pulseController.forward(from: 0.0);
  }

  void receivePulse() {
    if (widget.reducedMotion || !_active) return;
    _receivePulseController.forward(from: 0.0).whenCompleteOrCancel(() {
      if (mounted &&
          !widget.reducedMotion &&
          _active &&
          TickerMode.valuesOf(context).enabled) {
        _receivePulseController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tickerMode = TickerMode.valuesOf(context).enabled && _active;
    if (!tickerMode && _ambientController.isAnimating) {
      _ambientController.stop();
    } else if (tickerMode &&
        !_ambientController.isAnimating &&
        widget.status != ConnectionStatus.failed &&
        !widget.reducedMotion) {
      _ambientController.repeat();
    }

    if (widget.status == ConnectionStatus.failed ||
        widget.reducedMotion ||
        !tickerMode) {
      _ambientController.stop();
      _pulseController.stop();
      _receivePulseController.stop();
      _transitionController.stop();
      _transitionController.value = 1;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth == double.infinity
            ? 200.0
            : constraints.maxWidth;
        final height = constraints.maxHeight == double.infinity
            ? 150.0
            : constraints.maxHeight;
        final size = Size(width, height);

        return AnimatedBuilder(
          animation: Listenable.merge([
            _ambientController,
            _transitionController,
            _pulseController,
            _receivePulseController,
          ]),
          builder: (context, child) {
            return CustomPaint(
              size: size,
              painter: _DotsStagePainter(
                status: widget.status,
                previousStatus: _previousStatus,
                ambientValue: _ambientController.value,
                transitionValue: Curves.easeInOut.transform(
                  _transitionController.value,
                ),
                pulseValue: _pulseController.value,
                receivePulseValue: _receivePulseController.value,
                reducedMotion: widget.reducedMotion,
              ),
            );
          },
        );
      },
    );
  }
}

class _DotsStagePainter extends CustomPainter {
  final ConnectionStatus status;
  final ConnectionStatus previousStatus;
  final double ambientValue;
  final double transitionValue;
  final double pulseValue;
  final double receivePulseValue;
  final bool reducedMotion;

  static const Color coral = Color(0xFFFF4F81);
  static const Color lime = Color(0xFFCCFF00);
  static const Color mutedRed = Color(0xFFB05060);
  static const Color mutedGrey = Color(0xFF888888);

  _DotsStagePainter({
    required this.status,
    required this.previousStatus,
    required this.ambientValue,
    required this.transitionValue,
    required this.pulseValue,
    required this.receivePulseValue,
    required this.reducedMotion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseRadius = math.min(size.width, size.height) * 0.15;

    final oldLayout = _computeLayout(previousStatus, size, baseRadius);
    final newLayout = _computeLayout(status, size, baseRadius);

    final leftDotCenter = Offset.lerp(
      oldLayout.leftCenter,
      newLayout.leftCenter,
      transitionValue,
    )!;
    final rightDotCenter = Offset.lerp(
      oldLayout.rightCenter,
      newLayout.rightCenter,
      transitionValue,
    )!;
    final leftRadius = _lerpDouble(
      oldLayout.leftRadius,
      newLayout.leftRadius,
      transitionValue,
    );
    final rightRadius = _lerpDouble(
      oldLayout.rightRadius,
      newLayout.rightRadius,
      transitionValue,
    );
    final leftColor = Color.lerp(
      oldLayout.leftColor,
      newLayout.leftColor,
      transitionValue,
    )!;
    final rightColor = Color.lerp(
      oldLayout.rightColor,
      newLayout.rightColor,
      transitionValue,
    )!;
    final leftOpacity = _lerpDouble(
      oldLayout.leftOpacity,
      newLayout.leftOpacity,
      transitionValue,
    );
    final rightOpacity = _lerpDouble(
      oldLayout.rightOpacity,
      newLayout.rightOpacity,
      transitionValue,
    );

    Offset ambientLeft = leftDotCenter;
    Offset ambientRight = rightDotCenter;
    double ambientLeftScale = 1.0;

    if (!reducedMotion && status != ConnectionStatus.failed) {
      if (status == ConnectionStatus.unpaired) {
        ambientLeftScale = 1.0 + math.sin(ambientValue * math.pi * 2) * 0.05;
      } else if (status == ConnectionStatus.searching) {
        final t = ambientValue * math.pi * 2;
        ambientLeft += Offset(math.sin(t) * 8, math.cos(t * 2) * 4);
        ambientRight += Offset(math.cos(t) * 8, math.sin(t * 2) * 4);
      }
    }

    double rightDotScale = 1.0 + (receivePulseValue * 0.2);

    if (leftOpacity > 0.01) {
      DotSphere(
        baseColor: leftColor.withValues(alpha: leftOpacity),
        radius: leftRadius * ambientLeftScale,
        center: ambientLeft,
      ).paint(canvas, size);
    }

    if (rightOpacity > 0.01) {
      DotSphere(
        baseColor: rightColor.withValues(alpha: rightOpacity),
        radius: rightRadius * rightDotScale,
        center: ambientRight,
      ).paint(canvas, size);
    }

    if (pulseValue > 0.0 && pulseValue < 1.0 && !reducedMotion) {
      final pulsePos = Offset.lerp(ambientLeft, ambientRight, pulseValue)!;
      final pulseColor = Color.lerp(coral, lime, pulseValue)!;
      DotSphere(
        baseColor: pulseColor,
        radius: baseRadius * 0.3,
        center: pulsePos,
      ).paint(canvas, size);
    }

    if (status == ConnectionStatus.syncing && !reducedMotion) {
      final syncValue = (ambientValue * 2.0) % 1.0;
      final pulsePos = Offset.lerp(ambientLeft, ambientRight, syncValue)!;
      final pulseColor = Color.lerp(coral, lime, syncValue)!;
      DotSphere(
        baseColor: pulseColor,
        radius: baseRadius * 0.25,
        center: pulsePos,
      ).paint(canvas, size);
    }
  }

  double _lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }

  _DotLayout _computeLayout(
    ConnectionStatus stat,
    Size size,
    double baseRadius,
  ) {
    final center = Offset(size.width / 2, size.height / 2);
    final gap = size.width * 0.2;

    switch (stat) {
      case ConnectionStatus.unpaired:
        return _DotLayout(
          leftCenter: center,
          rightCenter: center,
          leftRadius: baseRadius,
          rightRadius: baseRadius * 0.1,
          leftColor: coral,
          rightColor: coral,
          leftOpacity: 1.0,
          rightOpacity: 0.0,
        );
      case ConnectionStatus.searching:
        return _DotLayout(
          leftCenter: Offset(center.dx - gap / 2, center.dy),
          rightCenter: Offset(center.dx + gap / 2, center.dy),
          leftRadius: baseRadius * 0.8,
          rightRadius: baseRadius * 0.8,
          leftColor: coral,
          rightColor: coral,
          leftOpacity: 1.0,
          rightOpacity: 1.0,
        );
      case ConnectionStatus.pairing:
        return _DotLayout(
          leftCenter: Offset(center.dx - gap / 4, center.dy),
          rightCenter: Offset(center.dx + gap / 4, center.dy),
          leftRadius: baseRadius * 0.9,
          rightRadius: baseRadius * 0.9,
          leftColor: coral,
          rightColor: coral,
          leftOpacity: 1.0,
          rightOpacity: 1.0,
        );
      case ConnectionStatus.connected:
      case ConnectionStatus.syncing:
        return _DotLayout(
          leftCenter: Offset(center.dx - gap / 8, center.dy),
          rightCenter: Offset(center.dx + gap / 8, center.dy),
          leftRadius: baseRadius,
          rightRadius: baseRadius,
          leftColor: lime,
          rightColor: lime,
          leftOpacity: 1.0,
          rightOpacity: 1.0,
        );
      case ConnectionStatus.offline:
        return _DotLayout(
          leftCenter: Offset(center.dx - gap * 1.5, center.dy),
          rightCenter: Offset(center.dx + gap * 1.5, center.dy),
          leftRadius: baseRadius * 0.7,
          rightRadius: baseRadius * 0.7,
          leftColor: mutedGrey,
          rightColor: mutedGrey,
          leftOpacity: 0.6,
          rightOpacity: 0.6,
        );
      case ConnectionStatus.failed:
        return _DotLayout(
          leftCenter: Offset(center.dx - gap, center.dy),
          rightCenter: Offset(center.dx + gap, center.dy),
          leftRadius: baseRadius * 0.8,
          rightRadius: baseRadius * 0.8,
          leftColor: mutedRed,
          rightColor: mutedRed,
          leftOpacity: 1.0,
          rightOpacity: 1.0,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _DotsStagePainter oldDelegate) {
    return oldDelegate.status != status ||
        oldDelegate.previousStatus != previousStatus ||
        oldDelegate.ambientValue != ambientValue ||
        oldDelegate.transitionValue != transitionValue ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.receivePulseValue != receivePulseValue ||
        oldDelegate.reducedMotion != reducedMotion;
  }
}

class _DotLayout {
  final Offset leftCenter;
  final Offset rightCenter;
  final double leftRadius;
  final double rightRadius;
  final Color leftColor;
  final Color rightColor;
  final double leftOpacity;
  final double rightOpacity;

  _DotLayout({
    required this.leftCenter,
    required this.rightCenter,
    required this.leftRadius,
    required this.rightRadius,
    required this.leftColor,
    required this.rightColor,
    required this.leftOpacity,
    required this.rightOpacity,
  });
}
