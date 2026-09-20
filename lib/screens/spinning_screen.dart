import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/spinning_playlist_service.dart';

class SpinningScreen extends StatefulWidget {
  final AudioPlayerService player;
  final List<Track> tracks;
  const SpinningScreen({super.key, required this.player, required this.tracks});
  @override State<SpinningScreen> createState() => _SpinningScreenState();
}

class _CurveCard extends StatelessWidget {
  final SpinningPlan plan;
  final double Function(double) displayBpm;
  const _CurveCard({required this.plan, required this.displayBpm});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BPM-Kurve', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('Zielkurve über die gesamte Trainingsdauer', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        SizedBox(height: 150, child: CustomPaint(
          painter: _CurvePainter(plan.curve, displayBpm),
          child: const SizedBox.expand(),
        )),
      ]),
    ),
  );
}

class _CurvePainter extends CustomPainter {
  final List<SpinningCurvePoint> curve;
  final double Function(double) displayBpm;
  _CurvePainter(this.curve, this.displayBpm);

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.isEmpty) return;
    final values = curve.map((p) => displayBpm(p.targetBpm)).toList();
    final min = values.reduce((a, b) => a < b ? a : b) - 4;
    final max = values.reduce((a, b) => a > b ? a : b) + 4;
    final span = max - min;
    final paint = Paint()..strokeWidth = 3..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < curve.length; i++) {
      final x = curve.length == 1 ? 0.0 : curve[i].position.inMilliseconds / curve.last.position.inMilliseconds * size.width;
      final y = size.height - ((values[i] - min) / span) * size.height;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < curve.length; i++) {
      final x = curve.length == 1 ? 0.0 : curve[i].position.inMilliseconds / curve.last.position.inMilliseconds * size.width;
      final y = size.height - ((values[i] - min) / span) * size.height;
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (final label in [values.first, values.last]) {
      textPainter.text = TextSpan(text: '${label.round()} BPM', style: const TextStyle(fontSize: 11));
      textPainter.layout();
      final x = label == values.first ? 0.0 : size.width - textPainter.width;
      final y = label == values.first ? size.height - textPainter.height : 0.0;
      textPainter.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}

class _SpinningScreenState extends State<SpinningScreen> {
  final planner = SpinningPlaylistService();
  Duration duration = const Duration(minutes: 45);
  bool sprintMode = false;
  SpinningPlan? plan;

  double _displayBpm(double bpm) => sprintMode ? bpm : bpm / 2;
  String _bpmText(double bpm) => '${_displayBpm(bpm).round()} BPM${sprintMode ? ' · Sprint' : ''}';
  void _buildPlan() => setState(() => plan = planner.build(library: widget.tracks, duration: duration));
  Future<void> _start() async {
    final p = plan; if (p == null || p.tracks.isEmpty) return;
    await widget.player.setQueue(p.tracks); await widget.player.play();
    if (mounted) Navigator.pop(context);
  }
  @override Widget build(BuildContext context) {
    final p = plan;
    return Scaffold(appBar: AppBar(title: const Text('Spinning DJ')), body: ListView(padding: const EdgeInsets.all(18), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
        const Icon(Icons.directions_bike, size: 54),
        const SizedBox(height: 8),
        Text('Trainings-Session', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        SegmentedButton<int>(segments: const [
          ButtonSegment(value: 30, label: Text('30 min')), ButtonSegment(value: 45, label: Text('45 min')),
          ButtonSegment(value: 60, label: Text('60 min')), ButtonSegment(value: 90, label: Text('90 min'))],
          selected: {duration.inMinutes}, onSelectionChanged: (v) => setState(() { duration = Duration(minutes: v.first); plan = null; })),
        const SizedBox(height: 14),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: sprintMode,
          onChanged: (value) => setState(() => sprintMode = value),
          title: const Text('Sprint-Modus'),
          subtitle: Text(sprintMode
              ? 'Volle BPM-Anzeige für Sprint-/Hochfrequenz-Intervalle.'
              : 'Spinning-Anzeige halbiert die Musik-BPM auf die übliche Trittfrequenz.'),
          secondary: const Icon(Icons.speed),
        ),
        const SizedBox(height: 4),
        FilledButton.icon(onPressed: _buildPlan, icon: const Icon(Icons.auto_awesome), label: const Text('Session automatisch planen')),
      ]))),
      if (p != null) ...[
        const SizedBox(height: 14),
        _CurveCard(plan: p, displayBpm: _displayBpm),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p.tracks.length} Tracks · ${duration.inMinutes} Minuten', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 3),
          Text(
            'Die Kurve ist das Ziel – einzelne Tracks dürfen leicht davon abweichen.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final phase in p.phases) Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              Expanded(child: Text(phase.label)),
              Text('${_displayBpm(phase.minBpm).round()}–${_displayBpm(phase.maxBpm).round()} BPM'),
            ]),
          ),
        ]))),
        const SizedBox(height: 14),
        for (var i = 0; i < p.tracks.length; i++) ListTile(
          leading: CircleAvatar(child: Text('${i + 1}')),
          title: Text(p.tracks[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${p.tracks[i].artist} · Ziel ${_displayBpm(p.selections[i].targetBpm).round()} BPM'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_bpmText(p.tracks[i].bpm!)),
              if ((p.selections[i].targetBpm - p.tracks[i].bpm!).abs() >= 4)
                Text(
                  'Zielabweichung ${_displayBpm((p.selections[i].targetBpm - p.tracks[i].bpm!).abs()).round()} BPM',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        FilledButton.icon(onPressed: p.tracks.isEmpty ? null : _start, icon: const Icon(Icons.play_arrow), label: const Text('Session starten')),
      ],
      if (widget.tracks.every((t) => t.bpm == null)) const Padding(padding: EdgeInsets.only(top: 20), child: Text('Bitte zuerst die BPM-Werte deiner Bibliothek analysieren.', textAlign: TextAlign.center)),
    ]));
  }
}