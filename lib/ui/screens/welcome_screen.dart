import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../dots/dot_sphere.dart';
import '../widgets/dot_widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ScreenContent(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width > 800 ? 32 : 20,
                  vertical: 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 180,
                      height: 180,
                      child: CustomPaint(
                        painter: DotSphere(
                          baseColor: Theme.of(context).colorScheme.primary,
                          radius: 70,
                          center: const Offset(90, 80),
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    Text(
                      'Je telefoon en MacBook, verbonden.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      child: DotButton(
                        label: 'Apparaat koppelen',
                        onPressed: () => Navigator.pushNamed(context, '/pair'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DotButton(
                      label: 'Eerst bekijken',
                      variant: DotButtonStyle.ghost,
                      onPressed: () async {
                        await context.read<AppState>().enterDemoMode();
                        if (context.mounted) {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/workspace',
                            (_) => false,
                          );
                        }
                      },
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
