import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/custom_bpm_profile_service.dart';
import '../services/library_service.dart';
import '../services/spinning_playlist_service.dart';
import '../services/spinning_session_controller.dart';
import '../services/spinning_transfer_service.dart';
import 'spinning_live_screen.dart';

class SpinningScreen extends StatefulWidget {
  final AudioPlayerService player;
  final List<Track> tracks;
  final Set<String> spinningTrackIds;
  final SpinningPlan? initialPlan;
  final ValueChanged<SpinningPlan?> onPlanChanged;
  final ValueChanged<SpinningSessionController?> onSessionChanged;
  const SpinningScreen({
    super.key,
    required this.player,
    required this.tracks,
    required this.spinningTrackIds,
    required this.initialPlan,
    required this.onPlanChanged,
    required this.onSessionChanged,
  });
  @override State<SpinningScreen> createState() => _SpinningScreenState();
}

class _CurveCard extends StatelessWidget {
  final SpinningPlan plan;
  final SpinningTrainingProfile profile;
  final double Function(double) displayBpm;
  const _CurveCard({
    required this.plan,
    required this.profile,
    required this.displayBpm,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          switch (profile) {
            SpinningTrainingProfile.heartRate => 'Herz-Trainingskurve',
            SpinningTrainingProfile.power => 'Watt-Trainingskurve',
            SpinningTrainingProfile.cadence => 'BPM-/Cadence-Kurve',
          },
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Text(
          switch (profile) {
            SpinningTrainingProfile.heartRate =>
              'Weicher Verlauf mit Belastungswellen und Erholungsphasen.',
            SpinningTrainingProfile.power =>
              'Klarere Belastungsblöcke und Intervalle.',
            SpinningTrainingProfile.cadence =>
              'Ausgewogene Wellen zwischen Aufbau, Belastung und Peak.',
          },
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
  final spinningTransfer = SpinningTransferService();
  final customBpmProfiles = CustomBpmProfileService();
  Duration duration = const Duration(minutes: 45);
  bool sprintMode = false;
  bool useSpinningLibrary = true;
  SpinningTrainingProfile trainingProfile = SpinningTrainingProfile.cadence;
  List<CustomBpmProfile> _customProfiles = const <CustomBpmProfile>[];
  String? _activeCustomProfileId;
  SpinningPlan? plan;
  final Map<String, Set<SpinningPhase>> _phaseEligibility =
      <String, Set<SpinningPhase>>{};

  @override
  void initState() {
    super.initState();
    plan = widget.initialPlan;
    _loadSpinningPhases();
    _loadTrainingProfile();
    _loadCustomBpmProfiles();
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

  Future<void> _loadCustomBpmProfiles() async {
    final profiles = await customBpmProfiles.loadProfiles();
    final activeId = await customBpmProfiles.loadActiveProfileId();
    if (!mounted) return;

    final active = profiles.any((profile) => profile.id == activeId)
        ? activeId
        : null;
    setState(() {
      _customProfiles = profiles;
      _activeCustomProfileId = active;
      // Keep the user's selected session duration independent from the
      // profile's original template length.
    });
  }

  CustomBpmProfile? get _activeCustomProfile {
    final id = _activeCustomProfileId;
    if (id == null) return null;
    for (final profile in _customProfiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  List<SpinningPhaseSpec> get _activePhases {
    final custom = _activeCustomProfile;
    if (custom == null || custom.segments.isEmpty) {
      return SpinningPlaylistService.phasesForProfile(trainingProfile);
    }

    final totalSeconds = custom.duration.inSeconds;
    return [
      for (final segment in custom.segments)
        SpinningPhaseSpec(
          phase: segment.phase,
          label: segment.label,
          minBpm: segment.minBpm,
          maxBpm: segment.maxBpm,
          share: totalSeconds <= 0
              ? 0
              : segment.duration.inSeconds / totalSeconds,
        ),
    ];
  }

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

  int _heartRateZone(double percent) => percent < 60
      ? 1
      : percent < 70
          ? 2
          : percent < 80
              ? 3
              : percent < 90
                  ? 4
                  : 5;

  String _heartRateTargetText(
    CustomBpmSegment segment,
    int? maxHeartRate,
  ) {
    final min = segment.minHeartRatePercent;
    final max = segment.maxHeartRatePercent;
    if (min == null || max == null) return '';

    final midpoint = (min + max) / 2;
    final zone = _heartRateZone(midpoint);
    if (maxHeartRate == null || maxHeartRate <= 0) {
      return ' · HF $min–$max % · Zone $zone';
    }

    final minPulse = (maxHeartRate * min / 100).round();
    final maxPulse = (maxHeartRate * max / 100).round();
    return ' · HF $min–$max % · $minPulse–$maxPulse bpm · Zone $zone';
  }

  String _scaledSegmentDuration(
    CustomBpmProfile profile,
    int index,
  ) {
    final scaled = planner.scaledCustomSegmentDurations(profile, duration);
    final value = index >= 0 && index < scaled.length
        ? scaled[index]
        : profile.segments[index].duration;
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60);
    if (seconds == 0) return '$minutes min';
    return '$minutes:${seconds.toString().padLeft(2, '0')} min';
  }

  bool _validateCustomSessionDuration() {
    final custom = _activeCustomProfile;
    if (custom == null) return true;

    final scaled = planner.scaledCustomSegmentDurations(custom, duration);
    if (scaled.length == custom.segments.length) return true;

    final fixed = custom.segments
        .where((segment) =>
            segment.phase == SpinningPhase.warmup ||
            segment.phase == SpinningPhase.cooldown)
        .fold<Duration>(
          Duration.zero,
          (sum, segment) => sum + segment.duration,
        );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Die gewählte Session ist zu kurz: Warm-up und Cool-down '
            'benötigen zusammen mindestens ${fixed.inMinutes} Minuten.',
          ),
        ),
      );
    return false;
  }

  String _heartRateZoneLabel(CustomBpmSegment segment) {
    final min = segment.minHeartRatePercent;
    final max = segment.maxHeartRatePercent;
    if (min == null || max == null) return 'keine HF-Vorgabe';
    final minZone = _heartRateZone(min.toDouble());
    final maxZone = _heartRateZone(max.toDouble());
    return minZone == maxZone ? 'Zone $minZone' : 'Zone $minZone–$maxZone';
  }

  ({int min, int max}) _standardHeartRateRange(SpinningPhase phase) =>
      switch (phase) {
        SpinningPhase.warmup => (min: 65, max: 69),
        SpinningPhase.build => (min: 60, max: 70),
        SpinningPhase.load => (min: 70, max: 80),
        SpinningPhase.peak => (min: 80, max: 90),
        SpinningPhase.cooldown => (min: 60, max: 65),
      };

  String _standardHeartRateText(SpinningPhase phase) {
    final range = _standardHeartRateRange(phase);
    final minZone = _heartRateZone(range.min.toDouble());
    final maxZone = _heartRateZone(range.max.toDouble());
    final zoneText =
        minZone == maxZone ? 'Zone $minZone' : 'Zone $minZone–$maxZone';

    if (phase == SpinningPhase.cooldown) {
      return 'HF ${range.max}→${range.min} % · $zoneText';
    }
    return 'HF ${range.min}–${range.max} % · $zoneText';
  }

  String _formatPhaseDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60);
    if (seconds == 0) return '$minutes:00';
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  List<Track> get _spinningTracks => widget.tracks
      .where((track) => widget.spinningTrackIds.contains(track.id))
      .toList(growable: false);

  List<Track> get _activeLibrary =>
      useSpinningLibrary ? _spinningTracks : widget.tracks;

  void _buildPlan() {
    if (!_validateCustomSessionDuration()) return;
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
          profile: trainingProfile,
          phaseEligibility: _phaseEligibility,
          curveOverride: _activeCustomProfile == null
              ? null
              : planner.buildCustomCurve(
                    _activeCustomProfile!,
                    targetDuration: duration,
                  ),
        ),
      );
    });
  }

  void _buildManualPlan() {
    if (!_validateCustomSessionDuration()) return;
    setState(() {
      _setPlan(
        _activeCustomProfile == null
            ? planner.buildFromPhaseTracks(
                phaseTracks: manualPhaseTracks,
                duration: duration,
                phases: _activePhases,
                profile: trainingProfile,
              )
            : planner.buildFromTracks(
                tracks: [
                  for (final phase in SpinningPhase.values)
                    ...manualPhaseTracks[phase] ?? const <Track>[],
                ],
                duration: duration,
                phases: _activePhases,
                profile: trainingProfile,
                curveOverride:
                    planner.buildCustomCurve(
                    _activeCustomProfile!,
                    targetDuration: duration,
                  ),
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

  Future<void> _selectCustomProfile(String? id) async {
    CustomBpmProfile? profile;
    if (id != null) {
      for (final item in _customProfiles) {
        if (item.id == id) {
          profile = item;
          break;
        }
      }
    }

    setState(() {
      _activeCustomProfileId = profile?.id;
      _setPlan(null);
    });
    await customBpmProfiles.saveActiveProfileId(profile?.id);
  }

  Future<void> _editCustomBpmProfile([CustomBpmProfile? existing]) async {
    final nameController = TextEditingController(
      text: existing?.name ?? 'Intervalltraining',
    );
    final maxHeartRateController = TextEditingController(
      text: existing?.maxHeartRate?.toString() ?? '',
    );
    final segments = existing == null
        ? <CustomBpmSegment>[
            const CustomBpmSegment(
              label: 'Warm-up',
              duration: Duration(minutes: 8),
              minBpm: 90,
              maxBpm: 110,
              minHeartRatePercent: 50,
              maxHeartRatePercent: 60,
              phase: SpinningPhase.warmup,
            ),
            const CustomBpmSegment(
              label: 'Belastung',
              duration: Duration(minutes: 4),
              minBpm: 135,
              maxBpm: 150,
              minHeartRatePercent: 80,
              maxHeartRatePercent: 90,
              phase: SpinningPhase.load,
            ),
            const CustomBpmSegment(
              label: 'Erholung',
              duration: Duration(minutes: 3),
              minBpm: 105,
              maxBpm: 120,
              minHeartRatePercent: 60,
              maxHeartRatePercent: 70,
              phase: SpinningPhase.build,
            ),
            const CustomBpmSegment(
              label: 'Belastung',
              duration: Duration(minutes: 4),
              minBpm: 140,
              maxBpm: 155,
              minHeartRatePercent: 90,
              maxHeartRatePercent: 95,
              phase: SpinningPhase.peak,
            ),
            const CustomBpmSegment(
              label: 'Cool-down',
              duration: Duration(minutes: 8),
              minBpm: 90,
              maxBpm: 105,
              minHeartRatePercent: 50,
              maxHeartRatePercent: 60,
              phase: SpinningPhase.cooldown,
            ),
          ]
        : List<CustomBpmSegment>.from(existing.segments);

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> editSegment(int index) async {
            final segment = segments[index];
            final label = TextEditingController(text: segment.label);
            final minutes = TextEditingController(
              text: segment.duration.inMinutes.toString(),
            );
            final minBpm = TextEditingController(
              text: segment.minBpm.toString(),
            );
            final maxBpm = TextEditingController(
              text: segment.maxBpm.toString(),
            );
            final minHeartRatePercent = TextEditingController(
              text: segment.minHeartRatePercent?.toString() ?? '',
            );
            final maxHeartRatePercent = TextEditingController(
              text: segment.maxHeartRatePercent?.toString() ?? '',
            );
            var phase = segment.phase;

            final changed = await showDialog<bool>(
              context: dialogContext,
              builder: (segmentContext) => StatefulBuilder(
                builder: (context, setSegmentState) => AlertDialog(
                  title: const Text('Intervall bearbeiten'),
                  content: SizedBox(
                    width: 460,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: label,
                            decoration: const InputDecoration(
                              labelText: 'Bezeichnung',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: minutes,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Dauer in Minuten',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: minBpm,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Musik-BPM min.',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: maxBpm,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Musik-BPM max.',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: minHeartRatePercent,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'HF min. %',
                                    hintText: 'z. B. 70',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: maxHeartRatePercent,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'HF max. %',
                                    hintText: 'z. B. 80',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Polar-orientiert: Z1 50–60 %, Z2 60–70 %, '
                              'Z3 70–80 %, Z4 80–90 %, Z5 90–100 %.',
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<SpinningPhase>(
                            initialValue: phase,
                            decoration: const InputDecoration(
                              labelText: 'Trainingsphase',
                            ),
                            items: [
                              for (final item in SpinningPhase.values)
                                DropdownMenuItem(
                                  value: item,
                                  child: Text(_phaseLabel(item)),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setSegmentState(() => phase = value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(segmentContext, false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(segmentContext, true),
                      child: const Text('Übernehmen'),
                    ),
                  ],
                ),
              ),
            );

            if (changed == true) {
              final mins = int.tryParse(minutes.text.trim()) ?? 1;
              var min = int.tryParse(minBpm.text.trim()) ?? 100;
              var max = int.tryParse(maxBpm.text.trim()) ?? 120;
              if (min > max) {
                final swap = min;
                min = max;
                max = swap;
              }
              var minHrPercent =
                  int.tryParse(minHeartRatePercent.text.trim());
              var maxHrPercent =
                  int.tryParse(maxHeartRatePercent.text.trim());
              if (minHrPercent != null &&
                  maxHrPercent != null &&
                  minHrPercent > maxHrPercent) {
                final swap = minHrPercent;
                minHrPercent = maxHrPercent;
                maxHrPercent = swap;
              }
              minHrPercent = minHrPercent?.clamp(30, 100);
              maxHrPercent = maxHrPercent?.clamp(30, 100);

              setDialogState(() {
                segments[index] = CustomBpmSegment(
                  label: label.text.trim().isEmpty
                      ? 'Intervall'
                      : label.text.trim(),
                  duration: Duration(minutes: mins.clamp(1, 180)),
                  minBpm: min.clamp(40, 240),
                  maxBpm: max.clamp(40, 240),
                  minHeartRatePercent: minHrPercent,
                  maxHeartRatePercent: maxHrPercent,
                  phase: phase,
                );
              });
            }
            label.dispose();
            minutes.dispose();
            minBpm.dispose();
            maxBpm.dispose();
            minHeartRatePercent.dispose();
            maxHeartRatePercent.dispose();
          }

          final totalMinutes = segments.fold<int>(
            0,
            (sum, segment) => sum + segment.duration.inMinutes,
          );

          return AlertDialog(
            title: Text(existing == null
                ? 'Eigene BPM-Kurve'
                : 'BPM-Kurve bearbeiten'),
            content: SizedBox(
              width: 680,
              height: MediaQuery.sizeOf(dialogContext).height * .68,
              child: Column(
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Profilname',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: maxHeartRateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'HFmax (optional)',
                      helperText:
                          'Nur für die zusätzliche Umrechnung der Prozentwerte in Puls-bpm.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '$totalMinutes Minuten · ${segments.length} Abschnitte',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: segments.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex--;
                        setDialogState(() {
                          final item = segments.removeAt(oldIndex);
                          segments.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (_, index) {
                        final segment = segments[index];
                        return ListTile(
                          key: ValueKey(
                            '${segment.label}-${segment.duration.inSeconds}-$index',
                          ),
                          leading: const Icon(Icons.drag_handle),
                          title: Text(segment.label),
                          subtitle: Text(
                            '${segment.duration.inMinutes} min · '
                            '${segment.minBpm}–${segment.maxBpm} Musik-BPM'
                            '${_heartRateTargetText(segment, int.tryParse(maxHeartRateController.text.trim()))}'
                            ' · ${_phaseLabel(segment.phase)}',
                          ),
                          onTap: () => editSegment(index),
                          trailing: IconButton(
                            tooltip: 'Abschnitt entfernen',
                            onPressed: segments.length <= 1
                                ? null
                                : () => setDialogState(
                                      () => segments.removeAt(index),
                                    ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setDialogState(() {
                      segments.add(
                        const CustomBpmSegment(
                          label: 'Neues Intervall',
                          duration: Duration(minutes: 5),
                          minBpm: 120,
                          maxBpm: 140,
                          phase: SpinningPhase.load,
                        ),
                      );
                    }),
                    icon: const Icon(Icons.add),
                    label: const Text('Abschnitt hinzufügen'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: segments.isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Profil speichern'),
              ),
            ],
          );
        },
      ),
    );

    if (accepted != true || !mounted) {
      nameController.dispose();
      maxHeartRateController.dispose();
      return;
    }

    final id = existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final maxHeartRate =
        int.tryParse(maxHeartRateController.text.trim())?.clamp(80, 240);
    final profile = CustomBpmProfile(
      id: id,
      name: nameController.text.trim().isEmpty
          ? 'Eigenes Profil'
          : nameController.text.trim(),
      maxHeartRate: maxHeartRate,
      segments: List<CustomBpmSegment>.from(segments),
    );
    nameController.dispose();
    maxHeartRateController.dispose();

    final nextProfiles = List<CustomBpmProfile>.from(_customProfiles);
    final existingIndex = nextProfiles.indexWhere((item) => item.id == id);
    if (existingIndex >= 0) {
      nextProfiles[existingIndex] = profile;
    } else {
      nextProfiles.add(profile);
    }

    await customBpmProfiles.saveProfiles(nextProfiles);
    await customBpmProfiles.saveActiveProfileId(profile.id);
    if (!mounted) return;
    setState(() {
      _customProfiles = nextProfiles;
      _activeCustomProfileId = profile.id;
      _setPlan(null);
    });
  }

  Future<void> _deleteActiveCustomProfile() async {
    final active = _activeCustomProfile;
    if (active == null) return;
    final next = _customProfiles
        .where((profile) => profile.id != active.id)
        .toList(growable: false);
    await customBpmProfiles.saveProfiles(next);
    await customBpmProfiles.saveActiveProfileId(null);
    if (!mounted) return;
    setState(() {
      _customProfiles = next;
      _activeCustomProfileId = null;
      _setPlan(null);
    });
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

  Future<void> _exportSpinningProfile() async {
    if (widget.spinningTrackIds.isEmpty) return;

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Spinning-Markierungen exportieren',
      fileName: 'MP3-by-Glasi-Spinning.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (savePath == null || savePath.isEmpty) return;

    final raw = spinningTransfer.exportProfile(
      library: widget.tracks,
      spinningTrackIds: widget.spinningTrackIds,
      phasesByTrackId: _phaseEligibility,
    );

    try {
      await File(savePath).writeAsString(raw, flush: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Spinning-Export fehlgeschlagen: $error')),
        );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${widget.spinningTrackIds.length} Spinning-Markierungen exportiert.',
          ),
        ),
      );
  }

  Future<void> _importSpinningProfile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = picked?.files.single.path;
    if (path == null || path.isEmpty) return;

    SpinningImportResult result;
    try {
      result = await spinningTransfer.importFile(
        File(path),
        widget.tracks,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Spinning-Import fehlgeschlagen: $error')),
        );
      return;
    }

    if (!mounted) return;

    final apply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Spinning-Markierungen importieren'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.matchedCount} Titel gefunden · '
                '${result.unmatched.length} nicht gefunden',
              ),
              const SizedBox(height: 8),
              const Text(
                'Gefundene Titel werden zur vorhandenen Spinning-Auswahl '
                'hinzugefügt. Bestehende Markierungen bleiben erhalten.',
              ),
              if (result.unmatched.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Nicht gefunden:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: result.unmatched.length,
                    itemBuilder: (_, index) => Text(
                      '• ${result.unmatched[index]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: result.matchedCount == 0
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('Importieren'),
          ),
        ],
      ),
    );

    if (apply != true || !mounted) return;

    widget.spinningTrackIds.addAll(result.matched.keys);
    for (final entry in result.matched.entries) {
      if (entry.value.isEmpty) continue;
      _phaseEligibility[entry.key] = Set<SpinningPhase>.from(entry.value);
    }

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

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${result.matchedCount} Spinning-Markierungen importiert.',
          ),
        ),
      );
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
          profile: trainingProfile,
          curveOverride: plan?.curve,
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
    final p = plan;
    if (p == null || p.tracks.isEmpty) return;

    await widget.player.setQueue(
      p.tracks,
      preserveCurrent: false,
    );
    await widget.player.play();
    if (!mounted) return;

    final session = SpinningSessionController(
      player: widget.player,
      plan: p,
      customProfile: _activeCustomProfile,
      sprintMode: sprintMode,
    );
    widget.onSessionChanged(session);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SpinningLiveScreen(
          session: session,
          onSessionEnded: () => widget.onSessionChanged(null),
        ),
      ),
    );
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
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 30, label: Text('30 min')),
            ButtonSegment(value: 45, label: Text('45 min')),
            ButtonSegment(value: 60, label: Text('60 min')),
            ButtonSegment(value: 90, label: Text('90 min')),
          ],
          selected: {duration.inMinutes},
          onSelectionChanged: (v) => setState(() {
            duration = Duration(minutes: v.first);
            _setPlan(null);
          }),
        ),
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
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importSpinningProfile,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Spinning importieren'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.spinningTrackIds.isEmpty
                    ? null
                    : _exportSpinningProfile,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Spinning exportieren'),
              ),
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
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Individuelle BPM-Kurve',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _activeCustomProfileId,
                decoration: const InputDecoration(
                  labelText: 'Profil',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Standardprofil verwenden'),
                  ),
                  for (final profile in _customProfiles)
                    DropdownMenuItem<String?>(
                      value: profile.id,
                      child: Text(
                        '${profile.name} · ${profile.duration.inMinutes} min',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _selectCustomProfile,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: _activeCustomProfile == null
                  ? 'Neue BPM-Kurve'
                  : 'BPM-Kurve bearbeiten',
              onPressed: () => _editCustomBpmProfile(_activeCustomProfile),
              icon: Icon(
                _activeCustomProfile == null
                    ? Icons.add_chart
                    : Icons.edit_outlined,
              ),
            ),
            if (_activeCustomProfile != null) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Eigenes Profil löschen',
                onPressed: _deleteActiveCustomProfile,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ],
        ),
        if (_activeCustomProfile != null) ...[
          const SizedBox(height: 6),
          Text(
            '${_activeCustomProfile!.segments.length} Abschnitte · '
            '${_activeCustomProfile!.duration.inMinutes} Minuten Vorlage. '
            'Warm-up/Cool-down bleiben fest, die mittleren Intervalle '
            'passen sich an die Sessiondauer an.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
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
        _CurveCard(
          plan: p,
          profile: trainingProfile,
          displayBpm: _displayBpm,
        ),
        const SizedBox(height: 14),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p.tracks.length} Tracks · ${duration.inMinutes} Minuten', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 3),
          Text(
            _activeCustomProfile == null
                ? 'Die Kurve ist das Ziel – einzelne Tracks dürfen leicht davon abweichen.'
                : 'Musik-BPM und Herzfrequenz sind getrennte Zielwerte. '
                    'Die Abschnittszeiten sind auf die gewählte Sessiondauer skaliert.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_activeCustomProfile case final custom?) ...[
            for (final entry in custom.segments.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(
                        _scaledSegmentDuration(custom, entry.$1),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.$2.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_displayBpm(entry.$2.minBpm.toDouble()).round()}–'
                            '${_displayBpm(entry.$2.maxBpm.toDouble()).round()} Musik-BPM'
                            '${_heartRateTargetText(entry.$2, custom.maxHeartRate)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _heartRateZoneLabel(entry.$2),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ] else ...[
            Builder(
              builder: (context) {
                final phaseDurations = p.phaseDurations;
                return Column(
                  children: [
                    for (final phase in p.phases)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 58,
                              child: Text(
                                _formatPhaseDuration(
                                  phaseDurations[phase.phase] ?? Duration.zero,
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(phase.label),
                                  const SizedBox(height: 2),
                                  Text(
                                    _standardHeartRateText(phase.phase),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${_displayBpm(phase.minBpm.toDouble()).round()}–'
                              '${_displayBpm(phase.maxBpm.toDouble()).round()} BPM',
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
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