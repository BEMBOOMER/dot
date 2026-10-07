import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Instellingen')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const Text('Instellingen')],
      ),
    ),
  );
}
