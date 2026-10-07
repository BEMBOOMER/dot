import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Welkom bij DOT')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Welkom bij DOT'),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/pair'),
            child: const Text('Apparaat koppelen'),
          ),
          TextButton(
            onPressed: () async {
              await context.read<AppState>().enterDemoMode();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/workspace');
              }
            },
            child: const Text('Eerst bekijken'),
          ),
        ],
      ),
    ),
  );
}
