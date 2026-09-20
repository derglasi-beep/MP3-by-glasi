import '../models/track.dart';

enum SpinningPhase { warmup, build, load, peak, cooldown }

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
  static const defaultPhases = <SpinningPhaseSpec>[
    SpinningPhaseSpec(phase: SpinningPhase.warmup, label: 'Warm-up', minBpm: 90, maxBpm: 110, share: .15),
    SpinningPhaseSpec(phase: SpinningPhase.build, label: 'Aufbau', minBpm: 110, maxBpm: 130, share: .20),
    SpinningPhaseSpec(phase: SpinningPhase.load, label: 'Belastung', minBpm: 125, maxBpm: 145, share: .30),
    SpinningPhaseSpec(phase: SpinningPhase.peak, label: 'Peak', minBpm: 140, maxBpm: 160, share: .20),
    SpinningPhaseSpec(phase: SpinningPhase.cooldown, label: 'Cool-down', minBpm: 90, maxBpm: 110, share: .15),
  ];

  SpinningPlan build({
    required List<Track> library,
    required Duration duration,
    List<SpinningPhaseSpec> phases = defaultPhases,
  }) {
    final usable = library.where((t) => t.bpm != null && t.bpm! > 0).toList();
    if (usable.isEmpty || duration <= Duration.zero) {
      return SpinningPlan(duration: duration, tracks: const [], phases: phases);
    }

    final curve = buildCurve(duration, phases);
    final selected = <Track>[];
    final selections = <SpinningSelection>[];
    final used = <String>{};
    var elapsed = Duration.zero;
    Track? previous;

    while (elapsed < duration && selected.length < usable.length) {
      final point = _curveAt(curve, elapsed);
      final candidates = usable.where((t) => !used.contains(t.id)).toList();
      if (candidates.isEmpty) break;

      candidates.sort((a, b) => _score(b, point, previous, duration - elapsed)
          .compareTo(_score(a, point, previous, duration - elapsed)));
      final chosen = candidates.first;
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
      elapsed += chosen.duration ?? const Duration(minutes: 4);
    }

    return SpinningPlan(
      duration: duration,
      tracks: selected,
      phases: phases,
      curve: curve,
      selections: selections,
    );
  }

  List<SpinningCurvePoint> buildCurve(
    Duration duration, [
    List<SpinningPhaseSpec> phases = defaultPhases,
  ]) {
    final points = <SpinningCurvePoint>[];
    var elapsed = Duration.zero;
    for (final phase in phases) {
      final phaseDuration = Duration(
        milliseconds: (duration.inMilliseconds * phase.share).round(),
      );
      final targets = switch (phase.phase) {
        SpinningPhase.warmup => const [95.0, 100.0, 105.0, 110.0],
        SpinningPhase.build => const [110.0, 116.0, 122.0, 128.0, 130.0],
        SpinningPhase.load => const [130.0, 134.0, 138.0, 142.0, 145.0],
        SpinningPhase.peak => const [145.0, 150.0, 155.0, 158.0, 155.0],
        SpinningPhase.cooldown => const [155.0, 148.0, 140.0, 130.0, 120.0, 110.0, 100.0],
      };
      for (var i = 0; i < targets.length; i++) {
        final fraction = targets.length == 1 ? 0.0 : i / (targets.length - 1);
        points.add(SpinningCurvePoint(
          position: elapsed + Duration(milliseconds: (phaseDuration.inMilliseconds * fraction).round()),
          targetBpm: targets[i],
          phase: phase.phase,
          tolerance: phase.phase == SpinningPhase.peak ? 5 : 7,
        ));
      }
      elapsed += phaseDuration;
    }
    return points;
  }

  double _score(
    Track track,
    SpinningCurvePoint point,
    Track? previous,
    Duration remaining,
  ) {
    final bpm = track.bpm!;
    final targetDistance = (bpm - point.targetBpm).abs();
    final targetScore = 1 - (targetDistance / 35).clamp(0, 1);
    final transitionDistance = previous == null ? 0 : (bpm - previous.bpm!).abs();
    final transitionScore = previous == null
        ? 1
        : 1 - (transitionDistance / (point.targetBpm * .08)).clamp(0, 1);
    final confidenceScore = track.bpmConfidence ?? .55;
    final length = (track.duration ?? const Duration(minutes: 4)).inSeconds;
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
