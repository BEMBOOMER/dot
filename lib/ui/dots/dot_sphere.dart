import 'package:flutter/material.dart';

class DotSphere extends CustomPainter {
  final Color baseColor;
  final double radius;
  final Offset center;

  DotSphere({
    required this.baseColor,
    required this.radius,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Soft contact shadow below the sphere
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.1)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.4);
    final shadowRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + radius * 1.05),
      width: radius * 1.8,
      height: radius * 0.6,
    );
    canvas.drawOval(shadowRect, shadowPaint);

    // Keep the accent recognizable; shading never exceeds 20% black.
    final darkerColor = Color.lerp(baseColor, Colors.black, .20)!;

    final basePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.5),
        radius: 1.2,
        colors: [
          Color.lerp(baseColor, Colors.white, .35)!,
          baseColor,
          darkerColor,
        ],
        stops: const [0, .24, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, basePaint);

    // 3. Key light highlight: small bright white-ish radial gradient at top-left
    final highlightCenter = Offset(
      center.dx - radius * 0.3,
      center.dy - radius * 0.3,
    );
    final highlightPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.12),
              Colors.white.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 1.0],
          ).createShader(
            Rect.fromCircle(center: highlightCenter, radius: radius * 0.75),
          );
    canvas.drawCircle(center, radius, highlightPaint);

    // 4. Rim light: subtle lighter edge gradient on bottom-right
    final rimCenter = Offset(
      center.dx + radius * 0.3,
      center.dy + radius * 0.3,
    );
    final rimPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.08),
        ],
        stops: const [0.7, 1.0],
      ).createShader(Rect.fromCircle(center: rimCenter, radius: radius * 1.1));
    canvas.drawCircle(center, radius, rimPaint);
  }

  @override
  bool shouldRepaint(covariant DotSphere oldDelegate) {
    return oldDelegate.baseColor != baseColor ||
        oldDelegate.radius != radius ||
        oldDelegate.center != center;
  }
}
