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
  final Map<SpinningPhase, List<Track>> manualPhaseTracks = {
    for (final phase in SpinningPhase.values) phase: <Track>[],
  };

  double _displayBpm(double bpm) => sprintMode ? bpm : bpm / 2;
  String _bpmText(double bpm) => '${_displayBpm(bpm).round()} BPM${sprintMode ? ' · Sprint' : ''}';

  void _buildPlan() => setState(
        () => plan = planner.build(
          library: widget.tracks,
          duration: duration,
        ),
      );

  void _buildManualPlan() {
    setState(() {
      plan = planner.buildFromPhaseTracks(
        phaseTracks: manualPhaseTracks,
        duration: duration,
      );
    });
  }

  String _phaseLabel(SpinningPhase phase) => switch (phase) {
    SpinningPhase.warmup => 'Warm-up',
    SpinningPhase.build => 'Aufbau',
    SpinningPhase.load => 'Belastung',
    SpinningPhase.peak => 'Peak',
    SpinningPhase.cooldown => 'Cool-down',
  };

  int get _manualTrackCount =>
      manualPhaseTracks.values.fold(0, (sum, tracks) => sum + tracks.length);

  Future<void> _chooseManualTracks() async {
    final usable = widget.tracks
        .where((track) => track.bpm != null && track.bpm! > 0)
        .toList(growable: false);

    var activePhase = SpinningPhase.warmup;
    var query = '';

    final working = {
      for (final phase in SpinningPhase.values)
        phase: List<Track>.from(manualPhaseTracks[phase] ?? const <Track>[]),
    };

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final visible = usable.where((track) {
            if (q.isEmpty) return true;
            return track.title.toLowerCase().contains(q) ||
                track.artist.toLowerCase().contains(q) ||
                track.album.toLowerCase().contains(q);
          }).toList(growable: false);

          final activeIds =
              working[activePhase]!.map((track) => track.id).toSet();

          return AlertDialog(
            title: const Text('Spinning-Phasen befüllen'),
            content: SizedBox(
              width: 640,
              height: 660,
              child: Column(
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final phase in SpinningPhase.values)
                        ChoiceChip(
                          label: Text(
                            '${_phaseLabel(phase)} (${working[phase]!.length})',
                          ),
                          selected: activePhase == phase,
                          onSelected: (_) =>
                              setDialogState(() => activePhase = phase),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Titel, Interpret oder Album',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Phase: ${_phaseLabel(activePhase)} · '
                      '${working[activePhase]!.length} Titel',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) {
                        final track = visible[index];
                        final selected = activeIds.contains(track.id);
                        return CheckboxListTile(
                          value: selected,
                          dense: true,
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${track.artist} · ${_bpmText(track.bpm!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              final list = working[activePhase]!;
                              if (value == true) {
                                if (!list.any((item) => item.id == track.id)) {
                                  list.add(track);
                                }
                              } else {
                                list.removeWhere((item) => item.id == track.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setDialogState(
                  () => working[activePhase]!.clear(),
                ),
                child: const Text('Phase leeren'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Übernehmen'),
              ),
            ],
          );
        },
      ),
    );

    if (accepted != true || !mounted) return;

    setState(() {
      for (final phase in SpinningPhase.values) {
        manualPhaseTracks[phase]!
          ..clear()
          ..addAll(working[phase]!);
      }
      plan = null;
    });
  }

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
        FilledButton.icon(
          onPressed: _buildPlan,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Session automatisch planen'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _chooseManualTracks,
          icon: const Icon(Icons.playlist_add),
          label: Text(
            _manualTrackCount == 0
                ? 'Session manuell befüllen'
                : 'Manuelle Auswahl: $_manualTrackCount Titel',
          ),
        ),
        if (_manualTrackCount > 0) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _buildManualPlan,
            icon: const Icon(Icons.tune),
            label: const Text('Manuelle Session übernehmen'),
          ),
        ],
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
              Text('${_displayBpm(phase.minBpm.toDouble()).round()}–${_displayBpm(phase.maxBpm.toDouble()).round()} BPM'),
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