import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

class DotColors {
  static const Color paper = Color(0xFFF5F0E8);
  static const Color ink = Color(0xFF1A1A1A);
  static const Color coral = Color(0xFFFF4F81);
  static const Color lime = Color(0xFFCCFF00);
  static const Color blue = Color(0xFF2979FF);
  static const Color amber = Color(0xFFFFA41F);

  // Dark mode
  static const Color bgDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
}

final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: DotColors.paper,
  colorScheme: const ColorScheme.light(
    primary: DotColors.coral,
    secondary: DotColors.lime,
    surface: DotColors.paper,
    onSurface: DotColors.ink,
  ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.ink),
    displayMedium: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.ink),
    displaySmall: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.ink),
    headlineLarge: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.ink),
    headlineMedium: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.ink),
    headlineSmall: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.ink),
    titleLarge: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.ink),
    titleMedium: TextStyle(
      fontFamily: 'SpaceGrotesk',
      color: DotColors.ink,
      fontWeight: FontWeight.bold,
    ),
    titleSmall: TextStyle(
      fontFamily: 'SpaceGrotesk',
      color: DotColors.ink,
      fontWeight: FontWeight.bold,
    ),
    bodyLarge: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.ink),
    bodyMedium: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.ink),
    bodySmall: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.ink),
    labelLarge: TextStyle(
      fontFamily: 'SpaceGrotesk',
      color: DotColors.ink,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.ink),
    labelSmall: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.ink),
  ),
);

final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: DotColors.bgDark,
  colorScheme: const ColorScheme.dark(
    primary: DotColors.coral,
    secondary: DotColors.lime,
    surface: DotColors.surfaceDark,
    onSurface: DotColors.paper,
  ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.paper),
    displayMedium: TextStyle(
      fontFamily: 'ArchivoBlack',
      color: DotColors.paper,
    ),
    displaySmall: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.paper),
    headlineLarge: TextStyle(
      fontFamily: 'ArchivoBlack',
      color: DotColors.paper,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'ArchivoBlack',
      color: DotColors.paper,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'ArchivoBlack',
      color: DotColors.paper,
    ),
    titleLarge: TextStyle(fontFamily: 'ArchivoBlack', color: DotColors.paper),
    titleMedium: TextStyle(
      fontFamily: 'SpaceGrotesk',
      color: DotColors.paper,
      fontWeight: FontWeight.bold,
    ),
    titleSmall: TextStyle(
      fontFamily: 'SpaceGrotesk',
      color: DotColors.paper,
      fontWeight: FontWeight.bold,
    ),
    bodyLarge: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.paper),
    bodyMedium: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.paper),
    bodySmall: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.paper),
    labelLarge: TextStyle(
      fontFamily: 'SpaceGrotesk',
      color: DotColors.paper,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.paper),
    labelSmall: TextStyle(fontFamily: 'SpaceGrotesk', color: DotColors.paper),
  ),
);

class NoiseOverlay extends StatelessWidget {
  const NoiseOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _NoisePainter(), child: Container()),
    );
  }
}

class _NoisePainter extends CustomPainter {
  static final List<Offset> _noisePoints = _generateNoise();
  static final Paint _noisePaint = Paint()
    ..color = DotColors.ink.withValues(alpha: 0.03)
    ..strokeWidth = 1.0
    ..strokeCap = StrokeCap.round;

  static List<Offset> _generateNoise() {
    final random = Random(42);
    final points = <Offset>[];
    // A fixed amount of points for a typical screen size, repeated across canvas.
    for (int i = 0; i < 5000; i++) {
      points.add(Offset(random.nextDouble(), random.nextDouble()));
    }
    return points;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final point in _noisePoints) {
      final x = point.dx * size.width;
      final y = point.dy * size.height;
      canvas.drawPoints(PointMode.points, [Offset(x, y)], _noisePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
