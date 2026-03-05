import 'package:flutter/material.dart';

class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('Debug Panel'),
            SizedBox(height: 8),
            Text('Some debug controls here...'),
          ],
        ),
      ),
    );
  }
}