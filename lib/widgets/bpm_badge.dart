import 'package:flutter/material.dart';

class BpmBadge extends StatelessWidget {
  final double? bpm;
  final bool loading;
  const BpmBadge({super.key, this.bpm, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final text = loading ? 'BPM …' : bpm == null ? 'BPM —' : 'BPM ' + bpm!.round().toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
