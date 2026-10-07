import 'package:flutter/material.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Itemdetails')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const Text('Itemdetails')],
      ),
    ),
  );
}
