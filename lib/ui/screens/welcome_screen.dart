import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../widgets/brutal_widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final paperColor = isDark
        ? const Color(0xFF121212)
        : const Color(0xFFF5F0E8);
    final inkColor = isDark ? const Color(0xFFF5F0E8) : const Color(0xFF1A1A1A);
    final coral = const Color(0xFFFF4F81);

    return Scaffold(
      backgroundColor: paperColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 32),
              // Big dot
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.3, -0.3),
                    radius: 0.8,
                    colors: [
                      coral.withValues(alpha: 0.8),
                      coral,
                      coral.withValues(alpha: 0.9),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: inkColor.withValues(alpha: 0.2),
                      offset: const Offset(4, 4),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              // Title
              Text(
                'Je telefoon en MacBook, verbonden.',
                textAlign: TextAlign.center,
                style: theme.textTheme.displayMedium?.copyWith(
                  fontFamily: 'ArchivoBlack',
                  color: inkColor,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const Spacer(),
              // Buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BrutalButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/pair');
                    },
                    label: 'Apparaat koppelen',
                    color: coral,
                  ),
                  const SizedBox(height: 16),
                  BrutalButton(
                    onPressed: () async {
                      await context.read<AppState>().enterDemoMode();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/workspace');
                      }
                    },
                    label: 'Eerst bekijken',
                    color: theme.cardColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
