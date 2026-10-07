import 'package:flutter/material.dart';

class PairScreen extends StatelessWidget {
  const PairScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Apparaat koppelen')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const Text('Apparaat koppelen')],
      ),
    ),
  );
}
