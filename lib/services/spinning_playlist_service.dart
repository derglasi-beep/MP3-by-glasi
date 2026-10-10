import 'dart:math';

import '../models/track.dart';

enum SpinningPhase { warmup, build, load, peak, cooldown }

enum SpinningTrainingProfile { cadence, heartRate, power }

class SpinningPhaseSpec {
  final SpinningPhase phase;
  final String label;
  final int minBpm;
  final int maxBpm;
  final double share;

  const SpinningPhaseSpec({
    required this.phase,
    required this.label,
    required this.minBpm,
    required this.maxBpm,
    required this.share,
  });
}

class SpinningCurvePoint {
  final Duration position;
  final double targetBpm;
  final SpinningPhase phase;
  final double tolerance;

  const SpinningCurvePoint({
    required this.position,
    required this.targetBpm,
    required this.phase,
    required this.tolerance,
  });
}

class SpinningSelection {
  final Track track;
  final double targetBpm;
  final SpinningPhase phase;
  final double score;

  const SpinningSelection({
    required this.track,
    required this.targetBpm,
    required this.phase,
    required this.score,
  });
}

class SpinningPlan {
  final Duration duration;
  final List<Track> tracks;
  final List<SpinningPhaseSpec> phases;
  final List<SpinningCurvePoint> curve;
  final List<SpinningSelection> selections;

  const SpinningPlan({
    required this.duration,
    required this.tracks,
    required this.phases,
    this.curve = const [],
    this.selections = const [],
  });
}

class SpinningPlaylistService {
  final Random _random = Random();
  static const defaultPhases = <SpinningPhaseSpec>[
    SpinningPhaseSpec(phase: SpinningPhase.warmup, label: 'Warm-up', minBpm: 90, maxBpm: 110, share: .15),
    SpinningPhaseSpec(phase: SpinningPhase.build, label: 'Aufbau', minBpm: 110, maxBpm: 130, share: .20),
    SpinningPhaseSpec(phase: SpinningPhase.load, label: 'Belastung', minBpm: 125, maxBpm: 145, share: .30),
    SpinningPhaseSpec(phase: SpinningPhase.peak, label: 'Peak', minBpm: 140, maxBpm: 160, share: .20),
    SpinningPhaseSpec(phase: SpinningPhase.cooldown, label: 'Cool-down', minBpm: 90, maxBpm: 110, share: .15),
  ];

  static const heartRatePhases = <SpinningPhaseSpec>[
    SpinningPhaseSpec(phase: SpinningPhase.warmup, label: 'Warm-up', minBpm: 90, maxBpm: 108, share: .20),
    SpinningPhaseSpec(phase: SpinningPhase.build, label: 'Aufbau', minBpm: 105, maxBpm: 125, share: .25),
    SpinningPhaseSpec(phase: SpinningPhase.load, label: 'Belastung', minBpm: 120, maxBpm: 140, share: .30),
    SpinningPhaseSpec(phase: SpinningPhase.peak, label: 'Peak', minBpm: 135, maxBpm: 150, share: .10),
    SpinningPhaseSpec(phase: SpinningPhase.cooldown, label: 'Cool-down', minBpm: 90, maxBpm: 110, share: .15),
  ];

  static const powerPhases = <SpinningPhaseSpec>[
    SpinningPhaseSpec(phase: SpinningPhase.warmup, label: 'Warm-up', minBpm: 90, maxBpm: 110, share: .15),
    SpinningPhaseSpec(phase: SpinningPhase.build, label: 'Aufbau', minBpm: 110, maxBpm: 135, share: .15),
    SpinningPhaseSpec(phase: SpinningPhase.load, label: 'Belastung', minBpm: 125, maxBpm: 150, share: .25),
    SpinningPhaseSpec(phase: SpinningPhase.peak, label: 'Peak', minBpm: 145, maxBpm: 165, share: .30),
    SpinningPhaseSpec(phase: SpinningPhase.cooldown, label: 'Cool-down', minBpm: 90, maxBpm: 110, share: .15),
  ];

  static List<SpinningPhaseSpec> phasesForProfile(
    SpinningTrainingProfile profile,
  ) =>
      switch (profile) {
        SpinningTrainingProfile.cadence => defaultPhases,
        SpinningTrainingProfile.heartRate => heartRatePhases,
        SpinningTrainingProfile.power => powerPhases,
      };

  SpinningPlan build({
    required List<Track> library,
    required Duration duration,
    List<SpinningPhaseSpec> phases = defaultPhases,
    SpinningTrainingProfile profile = SpinningTrainingProfile.cadence,
    Map<String, Set<SpinningPhase>> phaseEligibility = const {},
  }) {
    final usable = library.where((t) => t.bpm != null && t.bpm! > 0).toList();
    if (usable.isEmpty || duration <= Duration.zero) {
      return SpinningPlan(duration: duration, tracks: const [], phases: phases);
    }

    final curve = buildCurve(duration, phases: phases, profile: profile);
    final selected = <Track>[];
    final selections = <SpinningSelection>[];
    final used = <String>{};
    var elapsed = Duration.zero;
    Track? previous;

    while (elapsed < duration && selected.length < usable.length) {
      final point = _curveAt(curve, elapsed);
      var candidates = usable.where((track) {
        if (used.contains(track.id)) return false;
        final allowed = phaseEligibility[track.id];
        return allowed == null || allowed.isEmpty || allowed.contains(point.phase);
      }).toList();

      // Compatibility fallback: old spinning selections have no phase tags yet.
      // If a phase has no classified candidates, unclassified tracks may still
      // fill the gap instead of producing an unexpectedly short session.
      if (candidates.isEmpty) {
        candidates = usable.where((track) {
          if (used.contains(track.id)) return false;
          final allowed = phaseEligibility[track.id];
          return allowed == null || allowed.isEmpty;
        }).toList();
      }
      if (candidates.isEmpty) break;

      candidates.sort((a, b) => _score(b, point, previous, duration - elapsed)
          .compareTo(_score(a, point, previous, duration - elapsed)));

      final topCount = min(8, candidates.length);
      final top = candidates.take(topCount).toList();

      if (previous != null) {
        final differentArtists = top
            .where((track) =>
                track.artist.trim().toLowerCase() !=
                previous!.artist.trim().toLowerCase())
            .toList();
        if (differentArtists.isNotEmpty) {
          top
            ..clear()
            ..addAll(differentArtists);
        }
      }

      final chosen = top[_random.nextInt(top.length)];
      final score = _score(chosen, point, previous, duration - elapsed);
      selected.add(chosen);
      selections.add(SpinningSelection(
        track: chosen,
        targetBpm: point.targetBpm,
        phase: point.phase,
        score: score,
      ));
      used.add(chosen.id);
      previous = chosen;
      elapsed += _planningDuration(chosen);
    }

    return SpinningPlan(
      duration: duration,
      tracks: selected,
      phases: phases,
      curve: curve,
      selections: selections,
    );
  }

  SpinningPlan buildFromTracks({
    required List<Track> tracks,
    required Duration duration,
    List<SpinningPhaseSpec> phases = defaultPhases,
    SpinningTrainingProfile profile = SpinningTrainingProfile.cadence,
    List<SpinningCurvePoint>? curveOverride,
  }) {
    final usable = tracks.where((t) => t.bpm != null && t.bpm! > 0).toList();
    final curve = curveOverride ??
        buildCurve(duration, phases: phases, profile: profile);
    final selections = <SpinningSelection>[];
    var elapsed = Duration.zero;

    for (final track in usable) {
      final point = _curveAt(curve, elapsed);
      selections.add(
        SpinningSelection(
          track: track,
          targetBpm: point.targetBpm,
          phase: point.phase,
          score: _score(track, point, selections.isEmpty ? null : selections.last.track, duration - elapsed),
        ),
      );
      elapsed += _planningDuration(track);
    }

    return SpinningPlan(
      duration: duration,
      tracks: usable,
      phases: phases,
      curve: curve,
      selections: selections,
    );
  }

  SpinningPlan buildFromPhaseTracks({
    required Map<SpinningPhase, List<Track>> phaseTracks,
    required Duration duration,
    List<SpinningPhaseSpec> phases = defaultPhases,
    SpinningTrainingProfile profile = SpinningTrainingProfile.cadence,
  }) {
    final curve = buildCurve(duration, phases: phases, profile: profile);
    final selections = <SpinningSelection>[];
    final tracks = <Track>[];
    final used = <String>{};
    Track? previous;

    for (final spec in phases) {
      final selectedForPhase = phaseTracks[spec.phase] ?? const <Track>[];
      for (final track in selectedForPhase) {
        if (track.bpm == null || track.bpm! <= 0 || !used.add(track.id)) {
          continue;
        }

        final targetBpm = (spec.minBpm + spec.maxBpm) / 2;
        final point = SpinningCurvePoint(
          position: Duration.zero,
          targetBpm: targetBpm,
          phase: spec.phase,
          tolerance: spec.phase == SpinningPhase.peak ? 5 : 7,
        );

        tracks.add(track);
        selections.add(
          SpinningSelection(
            track: track,
            targetBpm: targetBpm,
            phase: spec.phase,
            score: _score(
              track,
              point,
              previous,
              _planningDuration(track),
            ),
          ),
        );
        previous = track;
      }
    }

    return SpinningPlan(
      duration: duration,
      tracks: tracks,
      phases: phases,
      curve: curve,
      selections: selections,
    );
  }

  List<SpinningCurvePoint> buildCurve(
    Duration duration, {
    List<SpinningPhaseSpec> phases = defaultPhases,
    SpinningTrainingProfile profile = SpinningTrainingProfile.cadence,
  }) {
    if (duration <= Duration.zero || phases.isEmpty) {
      return const <SpinningCurvePoint>[];
    }

    final variant = _random.nextInt(3);
    final points = <SpinningCurvePoint>[];
    var elapsed = Duration.zero;
    double? previousTarget;
    var globalSample = 0;

    for (final phase in phases) {
      final phaseDuration = Duration(
        milliseconds: (duration.inMilliseconds * phase.share).round(),
      );
      final pattern = _phasePattern(profile, phase.phase, variant);
      final min = phase.minBpm.toDouble();
      final max = phase.maxBpm.toDouble();
      final span = max - min;

      if (profile == SpinningTrainingProfile.power) {
        for (var i = 0; i < pattern.length; i++) {
          final fraction =
              pattern.length == 1 ? 0.0 : i / (pattern.length - 1);
          final target = min + span * pattern[i].clamp(0.0, 1.0);

          points.add(
            SpinningCurvePoint(
              position: elapsed +
                  Duration(
                    milliseconds:
                        (phaseDuration.inMilliseconds * fraction).round(),
                  ),
              targetBpm: target,
              phase: phase.phase,
              tolerance: phase.phase == SpinningPhase.peak ? 5 : 7,
            ),
          );
        }
        previousTarget = points.isEmpty ? previousTarget : points.last.targetBpm;
        elapsed += phaseDuration;
        continue;
      }

      final samplesPerSegment =
          profile == SpinningTrainingProfile.heartRate ? 6 : 4;
      final anchorTargets = <double>[
        for (final value in pattern)
          min + span * value.clamp(0.0, 1.0),
      ];

      if (previousTarget != null && anchorTargets.isNotEmpty) {
        anchorTargets[0] = (
          previousTarget! * .65 + anchorTargets.first * .35
        ).clamp(min, max).toDouble();
      }

      for (var segment = 0;
          segment < anchorTargets.length - 1;
          segment++) {
        final startTarget = anchorTargets[segment];
        final endTarget = anchorTargets[segment + 1];

        for (var sample = 0; sample < samplesPerSegment; sample++) {
          if (segment > 0 && sample == 0) continue;

          final local = sample / samplesPerSegment;
          final eased = local * local * (3 - 2 * local);
          var target =
              startTarget + (endTarget - startTarget) * eased;

          final waveStrength =
              profile == SpinningTrainingProfile.heartRate ? .035 : .018;
          final wave = sin((globalSample + variant * 2) * .72) *
              span *
              waveStrength;
          target = (target + wave).clamp(min, max).toDouble();

          final phaseFraction =
              (segment + local) / (anchorTargets.length - 1);
          points.add(
            SpinningCurvePoint(
              position: elapsed +
                  Duration(
                    milliseconds:
                        (phaseDuration.inMilliseconds * phaseFraction).round(),
                  ),
              targetBpm: target,
              phase: phase.phase,
              tolerance: phase.phase == SpinningPhase.peak ? 5 : 7,
            ),
          );
          globalSample++;
        }
      }

      final finalTarget = anchorTargets.last.clamp(min, max).toDouble();
      points.add(
        SpinningCurvePoint(
          position: elapsed + phaseDuration,
          targetBpm: finalTarget,
          phase: phase.phase,
          tolerance: phase.phase == SpinningPhase.peak ? 5 : 7,
        ),
      );
      previousTarget = finalTarget;
      elapsed += phaseDuration;
    }

    return points;
  }

  List<double> _phasePattern(
    SpinningTrainingProfile profile,
    SpinningPhase phase,
    int variant,
  ) {
    if (profile == SpinningTrainingProfile.heartRate) {
      return switch (phase) {
        SpinningPhase.warmup =>
          const [0.08, 0.20, 0.34, 0.48, 0.62, 0.72],
        SpinningPhase.build => switch (variant) {
          0 => const [0.18, 0.34, 0.50, 0.42, 0.62, 0.74, 0.82],
          1 => const [0.15, 0.30, 0.46, 0.60, 0.50, 0.70, 0.84],
          _ => const [0.20, 0.42, 0.32, 0.56, 0.46, 0.68, 0.86],
        },
        SpinningPhase.load => switch (variant) {
          0 => const [0.34, 0.52, 0.46, 0.68, 0.52, 0.76, 0.60, 0.82],
          1 => const [0.30, 0.48, 0.66, 0.44, 0.72, 0.56, 0.84, 0.64],
          _ => const [0.38, 0.60, 0.46, 0.74, 0.52, 0.80, 0.60, 0.76],
        },
        SpinningPhase.peak => switch (variant) {
          0 => const [0.52, 0.80, 0.64, 0.94, 0.72, 0.88],
          1 => const [0.58, 0.88, 0.70, 0.98, 0.76, 0.90],
          _ => const [0.50, 0.76, 0.62, 0.90, 0.70, 0.96],
        },
        SpinningPhase.cooldown =>
          const [0.82, 0.68, 0.54, 0.40, 0.28, 0.16, 0.08],
      };
    }

    if (profile == SpinningTrainingProfile.power) {
      return switch (phase) {
        SpinningPhase.warmup =>
          const [0.10, 0.28, 0.46, 0.64, 0.76],
        SpinningPhase.build => switch (variant) {
          0 => const [0.22, 0.52, 0.30, 0.68, 0.38, 0.78],
          1 => const [0.18, 0.58, 0.26, 0.72, 0.34, 0.82],
          _ => const [0.24, 0.48, 0.32, 0.66, 0.42, 0.84],
        },
        SpinningPhase.load => switch (variant) {
          0 => const [0.30, 0.82, 0.34, 0.88, 0.38, 0.92, 0.44, 0.84],
          1 => const [0.34, 0.74, 0.42, 0.90, 0.36, 0.86, 0.46, 0.94],
          _ => const [0.28, 0.78, 0.40, 0.86, 0.32, 0.96, 0.48, 0.88],
        },
        SpinningPhase.peak => switch (variant) {
          0 => const [0.62, 0.96, 0.66, 1.00, 0.70, 0.94],
          1 => const [0.58, 0.92, 0.64, 1.00, 0.72, 0.98],
          _ => const [0.66, 1.00, 0.60, 0.94, 0.74, 0.98],
        },
        SpinningPhase.cooldown =>
          const [0.78, 0.58, 0.42, 0.28, 0.14, 0.06],
      };
    }

    return switch (phase) {
      SpinningPhase.warmup => const [0.10, 0.28, 0.46, 0.64, 0.78],
      SpinningPhase.build => switch (variant) {
        0 => const [0.18, 0.40, 0.58, 0.46, 0.70, 0.84],
        1 => const [0.20, 0.34, 0.54, 0.72, 0.56, 0.86],
        _ => const [0.16, 0.44, 0.36, 0.62, 0.52, 0.82],
      },
      SpinningPhase.load => switch (variant) {
        0 => const [0.34, 0.58, 0.46, 0.72, 0.54, 0.82],
        1 => const [0.30, 0.50, 0.68, 0.48, 0.76, 0.60],
        _ => const [0.38, 0.62, 0.44, 0.74, 0.56, 0.84],
      },
      SpinningPhase.peak => const [0.58, 0.82, 0.68, 0.96, 0.74, 0.90],
      SpinningPhase.cooldown =>
        const [0.80, 0.62, 0.46, 0.32, 0.18, 0.08],
    };
  }

  Duration _planningDuration(Track track) {
    final duration = track.duration;
    if (duration == null || duration <= Duration.zero) {
      return const Duration(minutes: 4);
    }

    // Bad metadata must not make a 45-minute session stop after one title.
    // For planning purposes, clamp implausibly long single-track durations.
    if (duration > const Duration(minutes: 15)) {
      return const Duration(minutes: 5);
    }
    return duration;
  }

  double _tempoForTarget(double bpm, double targetBpm) {
    final candidates = <double>[
      bpm,
      if (bpm >= 120) bpm / 2,
      if (bpm <= 100) bpm * 2,
    ];

    var best = candidates.first;
    var bestDistance = (best - targetBpm).abs();
    for (final candidate in candidates.skip(1)) {
      final distance = (candidate - targetBpm).abs();
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  double _score(
    Track track,
    SpinningCurvePoint point,
    Track? previous,
    Duration remaining,
  ) {
    final bpm = _tempoForTarget(track.bpm!, point.targetBpm);
    final targetDistance = (bpm - point.targetBpm).abs();
    final targetScore = 1 - (targetDistance / 35).clamp(0, 1);
    final previousBpm = previous == null
        ? null
        : _tempoForTarget(previous.bpm!, point.targetBpm);
    final transitionDistance =
        previousBpm == null ? 0 : (bpm - previousBpm).abs();
    final transitionScore = previous == null
        ? 1
        : 1 - (transitionDistance / (point.targetBpm * .08)).clamp(0, 1);
    final confidenceScore = track.bpmConfidence ?? .55;
    final length = _planningDuration(track).inSeconds;
    final desired = remaining.inSeconds.clamp(120, 360);
    final lengthScore = 1 - ((length - desired).abs() / 360).clamp(0, 1);
    return targetScore * .40 +
        transitionScore * .25 +
        confidenceScore * .15 +
        lengthScore * .10 +
        (1 - (transitionDistance / 35).clamp(0, 1)) * .10;
  }

  SpinningCurvePoint _curveAt(List<SpinningCurvePoint> curve, Duration position) {
    if (position <= curve.first.position) return curve.first;
    for (var i = 1; i < curve.length; i++) {
      if (position <= curve[i].position) {
        final a = curve[i - 1];
        final b = curve[i];
        final span = b.position - a.position;
        final fraction = span.inMilliseconds == 0
            ? 0.0
            : (position - a.position).inMilliseconds / span.inMilliseconds;
        return SpinningCurvePoint(
          position: position,
          targetBpm: a.targetBpm + (b.targetBpm - a.targetBpm) * fraction,
          phase: b.phase,
          tolerance: b.tolerance,
        );
      }
    }
    return curve.last;
  }
}
