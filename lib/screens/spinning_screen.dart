import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';
import '../services/spinning_playlist_service.dart';

class SpinningScreen extends StatefulWidget {
  final AudioPlayerService player;
  final List<Track> tracks;
  final Set<String> spinningTrackIds;
  final SpinningPlan? initialPlan;
  final ValueChanged<SpinningPlan?> onPlanChanged;
  const SpinningScreen({
    super.key,
    required this.player,
    required this.tracks,
    required this.spinningTrackIds,
    required this.initialPlan,
    required this.onPlanChanged,
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BPM-Kurve', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          'Farbe zeigt die Trainingsintensität',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 108,
          child: CustomPaint(
            painter: _CurvePainter(
              plan.curve,
              displayBpm,
              gridColor: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: .45),
              textColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ]),
    ),
  );
}

class _CurvePainter extends CustomPainter {
  final List<SpinningCurvePoint> curve;
  final double Function(double) displayBpm;
  final Color gridColor;
  final Color textColor;

  _CurvePainter(
    this.curve,
    this.displayBpm, {
    required this.gridColor,
    required this.textColor,
  });

  Color _intensityColor(double targetBpm) {
    if (targetBpm < 110) return const Color(0xFF29B6F6);
    if (targetBpm < 130) return const Color(0xFF66BB6A);
    if (targetBpm < 145) return const Color(0xFFFFCA28);
    if (targetBpm < 155) return const Color(0xFFFF8A65);
    return const Color(0xFFEF5350);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.isEmpty) return;

    final values = curve.map((p) => displayBpm(p.targetBpm)).toList();
    final min = values.reduce((a, b) => a < b ? a : b) - 4;
    final max = values.reduce((a, b) => a > b ? a : b) + 4;
    final span = (max - min).abs() < .001 ? 1.0 : max - min;
    final chartTop = 14.0;
    final chartBottom = size.height - 18;
    final chartHeight = chartBottom - chartTop;
    final totalMs = curve.last.position.inMilliseconds;

    double xAt(int index) => curve.length == 1 || totalMs <= 0
        ? 0
        : curve[index].position.inMilliseconds / totalMs * size.width;

    double yAt(int index) =>
        chartBottom - ((values[index] - min) / span) * chartHeight;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 1; i <= 2; i++) {
      final y = chartTop + chartHeight * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (curve.length == 1) {
      final color = _intensityColor(curve.first.targetBpm);
      canvas.drawCircle(
        Offset(0, yAt(0)),
        4,
        Paint()..color = color,
      );
    } else {
      for (var i = 1; i < curve.length; i++) {
        final color = _intensityColor(curve[i].targetBpm);
        final linePaint = Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(xAt(i - 1), yAt(i - 1)),
          Offset(xAt(i), yAt(i)),
          linePaint,
        );
      }

      for (var i = 0; i < curve.length; i++) {
        final color = _intensityColor(curve[i].targetBpm);
        canvas.drawCircle(
          Offset(xAt(i), yAt(i)),
          3.5,
          Paint()..color = color,
        );
      }
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (final entry in <MapEntry<double, Alignment>>[
      MapEntry(values.first, Alignment.bottomLeft),
      MapEntry(values.last, Alignment.topRight),
    ]) {
      textPainter.text = TextSpan(
        text: '${entry.key.round()} BPM',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      );
      textPainter.layout();
      final isFirst = entry.value == Alignment.bottomLeft;
      final x = isFirst ? 0.0 : size.width - textPainter.width;
      final y = isFirst ? size.height - textPainter.height : 0.0;
      textPainter.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) =>
      oldDelegate.curve != curve ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.textColor != textColor;
}

class _SpinningScreenState extends State<SpinningScreen> {
  final planner = SpinningPlaylistService();
  final library = LibraryService();
  Duration duration = const Duration(minutes: 45);
  bool sprintMode = false;
  bool useSpinningLibrary = true;
  SpinningTrainingProfile trainingProfile = SpinningTrainingProfile.cadence;
  SpinningPlan? plan;
  final Map<String, Set<SpinningPhase>> _phaseEligibility =
      <String, Set<SpinningPhase>>{};

  @override
  void initState() {
    super.initState();
    plan = widget.initialPlan;
    _loadSpinningPhases();
    _loadTrainingProfile();
  }

  Future<void> _loadSpinningPhases() async {
    final stored = await library.loadSpinningTrackPhases();
    if (!mounted) return;

    final parsed = <String, Set<SpinningPhase>>{};
    for (final entry in stored.entries) {
      final phases = <SpinningPhase>{};
      for (final name in entry.value) {
        for (final phase in SpinningPhase.values) {
          if (phase.name == name) phases.add(phase);
        }
      }
      if (phases.isNotEmpty) parsed[entry.key] = phases;
    }

    setState(() {
      _phaseEligibility
        ..clear()
        ..addAll(parsed);
    });
  }

  Future<void> _loadTrainingProfile() async {
    final stored = await library.loadSpinningTrainingProfile();
    if (!mounted || stored == null) return;

    for (final profile in SpinningTrainingProfile.values) {
      if (profile.name != stored) continue;
      setState(() => trainingProfile = profile);
      return;
    }
  }

  List<SpinningPhaseSpec> get _activePhases =>
      SpinningPlaylistService.phasesForProfile(trainingProfile);

  String _trainingProfileLabel(SpinningTrainingProfile profile) =>
      switch (profile) {
        SpinningTrainingProfile.cadence => 'BPM',
        SpinningTrainingProfile.heartRate => 'Herz',
        SpinningTrainingProfile.power => 'Watt',
      };

  String _trainingProfileDescription() => switch (trainingProfile) {
        SpinningTrainingProfile.cadence =>
          'Ausgewogene Cadence-/BPM-Kurve mit klassischem Aufbau und Peak.',
        SpinningTrainingProfile.heartRate =>
          'Ruhigerer Ausdaueraufbau mit längerer Belastungsphase und kürzerem Peak.',
        SpinningTrainingProfile.power =>
          'Kräftigeres Intervallprofil mit mehr Belastungs- und Peak-Anteil.',
      };

  void _setPlan(SpinningPlan? next) {
    plan = next;
    widget.onPlanChanged(next);
  }
  final Map<SpinningPhase, List<Track>> manualPhaseTracks = {
    for (final phase in SpinningPhase.values) phase: <Track>[],
  };

  double _displayBpm(double bpm) => sprintMode ? bpm : bpm / 2;
  String _bpmText(double bpm) => '${_displayBpm(bpm).round()} BPM${sprintMode ? ' · Sprint' : ''}';

  List<Track> get _spinningTracks => widget.tracks
      .where((track) => widget.spinningTrackIds.contains(track.id))
      .toList(growable: false);

  List<Track> get _activeLibrary =>
      useSpinningLibrary ? _spinningTracks : widget.tracks;

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
      _setPlan(
        planner.build(
          library: active,
          duration: duration,
          phases: _activePhases,
          phaseEligibility: _phaseEligibility,
        ),
      );
    });
  }

  void _buildManualPlan() {
    setState(() {
      _setPlan(
        planner.buildFromPhaseTracks(
          phaseTracks: manualPhaseTracks,
          duration: duration,
          phases: _activePhases,
        ),
      );
    });
  }

  Future<Set<SpinningPhase>?> _pickSpinningPhases(
    Set<SpinningPhase> initial,
  ) async {
    final selected = Set<SpinningPhase>.from(initial);

    return showDialog<Set<SpinningPhase>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Geeignete Trainingsphasen'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mehrfachauswahl ist möglich. Ohne Auswahl bleibt der Titel '
                  'für alle Phasen verwendbar.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final phase in SpinningPhase.values)
                      FilterChip(
                        label: Text(_phaseLabel(phase)),
                        selected: selected.contains(phase),
                        onSelected: (value) => setDialogState(() {
                          if (value) {
                            selected.add(phase);
                          } else {
                            selected.remove(phase);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialogState(selected.clear),
              child: const Text('Alle Phasen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                Set<SpinningPhase>.from(selected),
              ),
              child: const Text('Übernehmen'),
            ),
          ],
        ),
      ),
    );
  }

  String _phaseSummary(Set<SpinningPhase>? phases) {
    if (phases == null || phases.isEmpty) return 'Alle Phasen';
    return SpinningPhase.values
        .where(phases.contains)
        .map(_phaseLabel)
        .join(', ');
  }

  Future<void> _manageSpinningLibrary() async {
    var query = '';
    var showOnlySpinning = true;
    final selected = Set<String>.from(widget.spinningTrackIds);
    final workingPhases = <String, Set<SpinningPhase>>{
      for (final entry in _phaseEligibility.entries)
        entry.key: Set<SpinningPhase>.from(entry.value),
    };

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final source = showOnlySpinning
              ? widget.tracks.where((track) => selected.contains(track.id))
              : widget.tracks;
          final visible = source.where((track) {
            if (q.isEmpty) return true;
            return track.title.toLowerCase().contains(q) ||
                track.artist.toLowerCase().contains(q) ||
                track.album.toLowerCase().contains(q);
          }).toList(growable: false);

          return AlertDialog(
            title: const Text('Spinning-Auswahl verwalten'),
            content: SizedBox(
              width: 720,
              height: 700,
              child: Column(
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.directions_bike),
                        label: Text('Spinning Songs'),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.library_music),
                        label: Text('Alle'),
                      ),
                    ],
                    selected: {showOnlySpinning},
                    onSelectionChanged: (values) => setDialogState(() {
                      showOnlySpinning = values.first;
                    }),
                  ),
                  const SizedBox(height: 10),
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
                        final isSelected = selected.contains(track.id);
                        final phases = workingPhases[track.id];

                        return CheckboxListTile(
                          dense: true,
                          value: isSelected,
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${track.artist} · ${track.album}'
                            '${track.bpm == null ? '' : ' · ${_bpmText(track.bpm!)}'}'
                            '${isSelected ? ' · ${_phaseSummary(phases)}' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: isSelected
                              ? IconButton(
                                  tooltip: 'Trainingsphasen auswählen',
                                  icon: const Icon(Icons.tune),
                                  onPressed: () async {
                                    final next = await _pickSpinningPhases(
                                      phases ?? const <SpinningPhase>{},
                                    );
                                    if (next == null) return;
                                    setDialogState(() {
                                      selected.add(track.id);
                                      if (next.isEmpty) {
                                        workingPhases.remove(track.id);
                                      } else {
                                        workingPhases[track.id] = next;
                                      }
                                    });
                                  },
                                )
                              : null,
                          onChanged: (value) => setDialogState(() {
                            if (value == true) {
                              selected.add(track.id);
                            } else {
                              selected.remove(track.id);
                              workingPhases.remove(track.id);
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
                onPressed: () => setDialogState(() {
                  selected.clear();
                  workingPhases.clear();
                }),
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

    _phaseEligibility
      ..clear()
      ..addEntries(
        workingPhases.entries.where(
          (entry) => selected.contains(entry.key) && entry.value.isNotEmpty,
        ),
      );

    await library.saveSpinningTrackIds(widget.spinningTrackIds);
    await library.saveSpinningTrackPhases({
      for (final entry in _phaseEligibility.entries)
        entry.key: entry.value.map((phase) => phase.name).toSet(),
    });

    if (!mounted) return;
    setState(() {
      useSpinningLibrary = widget.spinningTrackIds.isNotEmpty;
      _setPlan(null);
    });
  }

  Future<void> _clearSpinningLibrary() async {
    if (widget.spinningTrackIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Spinning-Auswahl leeren?'),
        content: const Text(
          'Alle Markierungen für Spinning werden entfernt. '
          'Die Titel selbst bleiben natürlich in der Musikbibliothek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Alle entfernen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    widget.spinningTrackIds.clear();
    _phaseEligibility.clear();
    await library.saveSpinningTrackIds(widget.spinningTrackIds);
    await library.saveSpinningTrackPhases(const <String, Set<String>>{});

    if (!mounted) return;
    setState(() {
      useSpinningLibrary = false;
      _setPlan(null);
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
      _activePhases.firstWhere((spec) => spec.phase == phase);

  SpinningPhase _suggestedPhase(double bpm) {
    SpinningPhase best = SpinningPhase.warmup;
    var bestDistance = double.infinity;

    for (final spec in _activePhases) {
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

  double _tempoForPhase(Track track, SpinningPhase phase) {
    final bpm = track.bpm;
    if (bpm == null || bpm <= 0) return double.infinity;

    final spec = _phaseSpec(phase);
    final target = (spec.minBpm + spec.maxBpm) / 2;
    final candidates = <double>[
      bpm,
      if (bpm >= 120) bpm / 2,
      if (bpm <= 100) bpm * 2,
    ];

    var best = candidates.first;
    var bestDistance = (best - target).abs();
    for (final candidate in candidates.skip(1)) {
      final distance = (candidate - target).abs();
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  bool _isEligibleForPhase(Track track, SpinningPhase phase) {
    final phases = _phaseEligibility[track.id];
    return phases == null || phases.isEmpty || phases.contains(phase);
  }

  double _phaseDistance(Track track, SpinningPhase phase) {
    final bpm = _tempoForPhase(track, phase);
    if (!bpm.isFinite) return double.infinity;
    final spec = _phaseSpec(phase);
    if (bpm < spec.minBpm) return spec.minBpm - bpm;
    if (bpm > spec.maxBpm) return bpm - spec.maxBpm;
    return 0;
  }

  String _phaseHint(Track track, SpinningPhase phase) {
    if (track.bpm == null) return 'BPM unbekannt';
    final bpm = _tempoForPhase(track, phase);
    final spec = _phaseSpec(phase);

    if (bpm >= spec.minBpm && bpm <= spec.maxBpm) {
      return 'Passt gut zu ${_phaseLabel(phase)}';
    }

    final suggested = _suggestedPhase(track.bpm!);
    return 'Eher ${_phaseLabel(suggested)}';
  }

  Future<void> _chooseManualTracks() async {
    var useSpinningSource = useSpinningLibrary;
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
              useSpinningSource ? _spinningTracks : widget.tracks;
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
                        label: Text('Spinning Songs'),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.library_music),
                        label: Text('Alle'),
                      ),
                    ],
                    selected: {useSpinningSource},
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
      _setPlan(null);
    });
  }

  void _replacePlanTracks(List<Track> nextTracks) {
    setState(() {
      _setPlan(
        planner.buildFromTracks(
          tracks: nextTracks,
          duration: duration,
          phases: _activePhases,
        ),
      );
    });
  }

  void _removePlanTrack(int index) {
    final current = plan;
    if (current == null || index < 0 || index >= current.tracks.length) return;
    final next = List<Track>.from(current.tracks)..removeAt(index);
    _replacePlanTracks(next);
  }

  void _movePlanTrack(int oldIndex, int newIndex) {
    final current = plan;
    if (current == null) return;

    final next = List<Track>.from(current.tracks);
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex < 0 ||
        oldIndex >= next.length ||
        newIndex < 0 ||
        newIndex >= next.length) {
      return;
    }

    final track = next.removeAt(oldIndex);
    next.insert(newIndex, track);
    _replacePlanTracks(next);
  }

  void _movePlanTrackBy(int index, int offset) {
    final current = plan;
    if (current == null) return;
    final target = index + offset;
    if (index < 0 ||
        index >= current.tracks.length ||
        target < 0 ||
        target >= current.tracks.length) {
      return;
    }

    final next = List<Track>.from(current.tracks);
    final track = next.removeAt(index);
    next.insert(target, track);
    _replacePlanTracks(next);
  }

  Future<void> _addPlanTrack() async {
    final current = plan;
    if (current == null) return;

    var query = '';
    final used = current.tracks.map((track) => track.id).toSet();

    final selected = await showDialog<Track>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final available = _activeLibrary.where((track) {
            if (used.contains(track.id)) return false;
            if (track.bpm == null || track.bpm! <= 0) return false;
            if (q.isEmpty) return true;
            return track.title.toLowerCase().contains(q) ||
                track.artist.toLowerCase().contains(q) ||
                track.album.toLowerCase().contains(q);
          }).toList(growable: true)
            ..sort((a, b) {
              final artist = a.artist.toLowerCase().compareTo(
                    b.artist.toLowerCase(),
                  );
              if (artist != 0) return artist;
              return a.title.toLowerCase().compareTo(b.title.toLowerCase());
            });

          return AlertDialog(
            title: const Text('Titel zur Session hinzufügen'),
            content: SizedBox(
              width: 620,
              height: 600,
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
                    child: Text('${available.length} passende Titel'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: available.length,
                      itemBuilder: (_, index) {
                        final track = available[index];
                        return ListTile(
                          leading: const Icon(Icons.add_circle_outline),
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
                          onTap: () => Navigator.pop(dialogContext, track),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Abbrechen'),
              ),
            ],
          );
        },
      ),
    );

    if (selected == null || !mounted) return;
    final next = List<Track>.from(current.tracks)..add(selected);
    _replacePlanTracks(next);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Spinning DJ')),
      body: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
        const Icon(Icons.directions_bike, size: 54),
        const SizedBox(height: 8),
        Text('Trainings-Session', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        SegmentedButton<int>(segments: const [
          ButtonSegment(value: 30, label: Text('30 min')), ButtonSegment(value: 45, label: Text('45 min')),
          ButtonSegment(value: 60, label: Text('60 min')), ButtonSegment(value: 90, label: Text('90 min'))],
          selected: {duration.inMinutes}, onSelectionChanged: (v) => setState(() { duration = Duration(minutes: v.first); _setPlan(null); })),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.directions_bike),
              label: Text('Spinning Songs'),
            ),
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.library_music),
              label: Text('Alle'),
            ),
          ],
          selected: {useSpinningLibrary},
          onSelectionChanged: (values) => setState(() {
            useSpinningLibrary = values.first;
            _setPlan(null);
          }),
        ),
        const SizedBox(height: 6),
        Builder(
          builder: (_) {
            final active = _activeLibrary;
            final usable = active
                .where((track) => track.bpm != null && track.bpm! > 0)
                .length;
            final sourceLabel = useSpinningLibrary
                ? '${_spinningTracks.length} markierte Spinning-Titel'
                : '${widget.tracks.length} Titel aus der gesamten Bibliothek';
            return Text(
              '$sourceLabel · $usable mit BPM planbar',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _manageSpinningLibrary,
                icon: const Icon(Icons.checklist),
                label: const Text('Spinning-Auswahl verwalten'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: widget.spinningTrackIds.isEmpty
                  ? null
                  : _clearSpinningLibrary,
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Spinning-Auswahl leeren',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Trainingsprofil',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<SpinningTrainingProfile>(
          segments: const [
            ButtonSegment<SpinningTrainingProfile>(
              value: SpinningTrainingProfile.cadence,
              icon: Icon(Icons.speed),
              label: Text('BPM'),
            ),
            ButtonSegment<SpinningTrainingProfile>(
              value: SpinningTrainingProfile.heartRate,
              icon: Icon(Icons.favorite_outline),
              label: Text('Herz'),
            ),
            ButtonSegment<SpinningTrainingProfile>(
              value: SpinningTrainingProfile.power,
              icon: Icon(Icons.bolt),
              label: Text('Watt'),
            ),
          ],
          selected: {trainingProfile},
          onSelectionChanged: (values) {
            final next = values.first;
            setState(() {
              trainingProfile = next;
              _setPlan(null);
            });
            library.saveSpinningTrainingProfile(next.name);
          },
        ),
        const SizedBox(height: 6),
        Text(
          _trainingProfileDescription(),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
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
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Session bearbeiten',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addPlanTrack,
                      icon: const Icon(Icons.add),
                      label: const Text('Titel'),
                    ),
                  ],
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: p.tracks.length,
                  onReorder: _movePlanTrack,
                  itemBuilder: (_, i) {
                    final track = p.tracks[i];
                    final selection = i < p.selections.length
                        ? p.selections[i]
                        : null;
                    return ListTile(
                      key: ValueKey('session-${track.id}-$i'),
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        selection == null
                            ? track.artist
                            : '${track.artist} · ${_bpmText(track.bpm!)} · '
                                '${_phaseLabel(selection.phase)} · '
                                'Ziel ${_displayBpm(selection.targetBpm).round()} BPM'
                                '${_isEligibleForPhase(track, selection.phase) ? '' : ' · ⚠ nicht für diese Phase markiert'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: Tooltip(
                              message: 'Ziehen zum Verschieben',
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                ),
                                child: const Icon(Icons.drag_indicator),
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Nach oben',
                            onPressed: i == 0
                                ? null
                                : () => _movePlanTrackBy(i, -1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Nach unten',
                            onPressed: i == p.tracks.length - 1
                                ? null
                                : () => _movePlanTrackBy(i, 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Aus Session entfernen',
                            onPressed: () => _removePlanTrack(i),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: p.tracks.isEmpty ? null : _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Session starten'),
        ),
      ],
      if (_activeLibrary.every((t) => t.bpm == null))
        const Padding(
          padding: EdgeInsets.only(top: 20),
          child: Text(
            'Bitte zuerst die BPM-Werte deiner Bibliothek analysieren.',
            textAlign: TextAlign.center,
          ),
        ),
      const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}