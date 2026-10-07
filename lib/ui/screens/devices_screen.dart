import 'package:flutter/material.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Apparaten')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const Text('Apparaten')],
      ),
    ),
  );
}
