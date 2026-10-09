import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';
import '../services/spinning_playlist_service.dart';

class SpinningScreen extends StatefulWidget {
  final AudioPlayerService player;
  final List<Track> tracks;
  final Set<String> spinningTrackIds;
  const SpinningScreen({
    super.key,
    required this.player,
    required this.tracks,
    required this.spinningTrackIds,
  });
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
  final library = LibraryService();
  Duration duration = const Duration(minutes: 45);
  bool sprintMode = false;
  bool useSpinningLibrary = true;
  SpinningPlan? plan;
  final Map<SpinningPhase, List<Track>> manualPhaseTracks = {
    for (final phase in SpinningPhase.values) phase: <Track>[],
  };

  double _displayBpm(double bpm) => sprintMode ? bpm : bpm / 2;
  String _bpmText(double bpm) => '${_displayBpm(bpm).round()} BPM${sprintMode ? ' · Sprint' : ''}';

  List<Track> get _spinningTracks => widget.tracks
      .where((track) => widget.spinningTrackIds.contains(track.id))
      .toList(growable: false);

  List<Track> get _activeLibrary {
    final spinning = _spinningTracks;
    if (useSpinningLibrary && spinning.isNotEmpty) return spinning;
    return widget.tracks;
  }

  void _buildPlan() {
    final active = _activeLibrary;
    final usable =
        active.where((track) => track.bpm != null && track.bpm! > 0).toList();

    if (usable.length < 2) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              usable.isEmpty
                  ? 'In dieser Auswahl hat noch kein Titel einen BPM-Wert.'
                  : 'In dieser Auswahl ist aktuell nur 1 Titel mit BPM planbar.',
            ),
          ),
        );
    }

    setState(() {
      plan = planner.build(
        library: active,
        duration: duration,
      );
    });
  }

  void _buildManualPlan() {
    setState(() {
      plan = planner.buildFromPhaseTracks(
        phaseTracks: manualPhaseTracks,
        duration: duration,
      );
    });
  }

  Future<void> _manageSpinningLibrary() async {
    var query = '';
    final selected = Set<String>.from(widget.spinningTrackIds);

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final visible = widget.tracks.where((track) {
            if (q.isEmpty) return true;
            return track.title.toLowerCase().contains(q) ||
                track.artist.toLowerCase().contains(q) ||
                track.album.toLowerCase().contains(q);
          }).toList(growable: false);

          return AlertDialog(
            title: const Text('Spinning-Auswahl verwalten'),
            content: SizedBox(
              width: 680,
              height: 680,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
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
                      '${selected.length} Titel markiert · '
                      '${visible.length} Treffer',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) {
                        final track = visible[index];
                        return CheckboxListTile(
                          dense: true,
                          value: selected.contains(track.id),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${track.artist} · ${track.album}'
                            '${track.bpm == null ? '' : ' · ${_bpmText(track.bpm!)}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              selected.add(track.id);
                            } else {
                              selected.remove(track.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setDialogState(selected.clear),
                child: const Text('Alle entfernen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Speichern'),
              ),
            ],
          );
        },
      ),
    );

    if (accepted != true || !mounted) return;

    widget.spinningTrackIds
      ..clear()
      ..addAll(selected);
    await library.saveSpinningTrackIds(widget.spinningTrackIds);

    if (!mounted) return;
    setState(() {
      useSpinningLibrary = widget.spinningTrackIds.isNotEmpty;
      plan = null;
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
  SpinningPhaseSpec _phaseSpec(SpinningPhase phase) =>
      SpinningPlaylistService.defaultPhases
          .firstWhere((spec) => spec.phase == phase);

  SpinningPhase _suggestedPhase(double bpm) {
    SpinningPhase best = SpinningPhase.warmup;
    var bestDistance = double.infinity;

    for (final spec in SpinningPlaylistService.defaultPhases) {
      final distance = bpm < spec.minBpm
          ? spec.minBpm - bpm
          : bpm > spec.maxBpm
              ? bpm - spec.maxBpm
              : 0.0;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = spec.phase;
      }
    }
    return best;
  }

  double _phaseDistance(Track track, SpinningPhase phase) {
    final bpm = track.bpm;
    if (bpm == null || bpm <= 0) return double.infinity;
    final spec = _phaseSpec(phase);
    if (bpm < spec.minBpm) return spec.minBpm - bpm;
    if (bpm > spec.maxBpm) return bpm - spec.maxBpm;
    return 0;
  }

  String _phaseHint(Track track, SpinningPhase phase) {
    final bpm = track.bpm;
    if (bpm == null) return 'BPM unbekannt';
    final spec = _phaseSpec(phase);

    if (bpm >= spec.minBpm && bpm <= spec.maxBpm) {
      return 'Passt gut zu ${_phaseLabel(phase)}';
    }

    final suggested = _suggestedPhase(bpm);
    return 'Eher ${_phaseLabel(suggested)}';
  }

  Future<void> _chooseManualTracks() async {
    var useSpinningSource =
        useSpinningLibrary && _spinningTracks.isNotEmpty;
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
          final sourceTracks =
              useSpinningSource && _spinningTracks.isNotEmpty
                  ? _spinningTracks
                  : widget.tracks;
          final q = query.trim().toLowerCase();
          final visible = sourceTracks.where((track) {
            if (q.isEmpty) return true;
            return track.title.toLowerCase().contains(q) ||
                track.artist.toLowerCase().contains(q) ||
                track.album.toLowerCase().contains(q);
          }).toList(growable: true)
            ..sort((a, b) {
              final distanceA = _phaseDistance(a, activePhase);
              final distanceB = _phaseDistance(b, activePhase);
              if (distanceA != distanceB) {
                return distanceA.compareTo(distanceB);
              }
              return a.title.toLowerCase().compareTo(
                    b.title.toLowerCase(),
                  );
            });

          final activeIds =
              working[activePhase]!.map((track) => track.id).toSet();

          return AlertDialog(
            title: const Text('Spinning-Phasen befüllen'),
            content: SizedBox(
              width: 640,
              height: 660,
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.directions_bike),
                        label: Text('Spinning-Auswahl'),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.library_music),
                        label: Text('Alle Titel'),
                      ),
                    ],
                    selected: {
                      useSpinningSource && _spinningTracks.isNotEmpty,
                    },
                    onSelectionChanged: (values) => setDialogState(() {
                      useSpinningSource = values.first;
                    }),
                  ),
                  const SizedBox(height: 10),
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
                    child: Builder(
                      builder: (_) {
                        final spec = _phaseSpec(activePhase);
                        return Text(
                          'Phase: ${_phaseLabel(activePhase)} · '
                          '${working[activePhase]!.length} gewählt · '
                          '${visible.length} Treffer · '
                          'empfohlen ${_displayBpm(spec.minBpm.toDouble()).round()}–'
                          '${_displayBpm(spec.maxBpm.toDouble()).round()} BPM',
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) {
                        final track = visible[index];
                        final selected = activeIds.contains(track.id);
                        final hasBpm = track.bpm != null && track.bpm! > 0;
                        return CheckboxListTile(
                          value: selected,
                          dense: true,
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            hasBpm
                                ? '${track.artist} · ${_bpmText(track.bpm!)} · '
                                    '${_phaseHint(track, activePhase)}'
                                : '${track.artist} · BPM noch analysieren',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: hasBpm ? (value) {
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
                          } : null,
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
    await widget.player.setQueue(
      p.tracks,
      preserveCurrent: false,
    );
    await widget.player.play();
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
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.directions_bike),
              label: Text('Spinning-Auswahl'),
            ),
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.library_music),
              label: Text('Alle Titel'),
            ),
          ],
          selected: {useSpinningLibrary && _spinningTracks.isNotEmpty},
          onSelectionChanged: (values) => setState(() {
            useSpinningLibrary = values.first;
            plan = null;
          }),
        ),
        const SizedBox(height: 6),
        Builder(
          builder: (_) {
            final active = _activeLibrary;
            final usable = active
                .where((track) => track.bpm != null && track.bpm! > 0)
                .length;
            final sourceLabel = _spinningTracks.isEmpty
                ? 'Noch keine Titel für Spinning markiert – aktuell werden alle Titel verwendet.'
                : (useSpinningLibrary
                    ? '${_spinningTracks.length} markierte Spinning-Titel'
                    : '${widget.tracks.length} Titel aus der gesamten Bibliothek');
            return Text(
              '$sourceLabel · $usable mit BPM planbar',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _manageSpinningLibrary,
          icon: const Icon(Icons.checklist),
          label: const Text('Spinning-Auswahl verwalten'),
        ),
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
      if (_activeLibrary.every((t) => t.bpm == null)) const Padding(padding: EdgeInsets.only(top: 20), child: Text('Bitte zuerst die BPM-Werte deiner Bibliothek analysieren.', textAlign: TextAlign.center)),
    ]));
  }
}