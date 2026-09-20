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

class SpinningPlan {
  final Duration duration;
  final List<Track> tracks;
  final List<SpinningPhaseSpec> phases;

  const SpinningPlan({
    required this.duration,
    required this.tracks,
    required this.phases,
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

    final selected = <Track>[];
    final used = <String>{};
    for (final phase in phases) {
      final phaseMinutes = duration.inMinutes * phase.share;
      final targetCount = phaseMinutes <= 0 ? 0 : (phaseMinutes / 4.0).ceil();
      final candidates = usable.where((t) =>
          !used.contains(t.id) &&
          t.bpm! >= phase.minBpm &&
          t.bpm! <= phase.maxBpm).toList();
      candidates.sort((a, b) => _phaseDistance(a, phase).compareTo(_phaseDistance(b, phase)));
      for (final track in candidates.take(targetCount)) {
        selected.add(track);
        used.add(track.id);
      }
    }

    // Fill remaining slots with the closest BPM transitions, avoiding repeats.
    final targetTracks = (duration.inMinutes / 4.0).ceil().clamp(1, usable.length);
    while (selected.length < targetTracks) {
      final remaining = usable.where((t) => !used.contains(t.id)).toList();
      if (remaining.isEmpty) break;
      final current = selected.isEmpty ? null : selected.last.bpm;
      remaining.sort((a, b) {
        final da = current == null ? 0 : (a.bpm! - current).abs();
        final db = current == null ? 0 : (b.bpm! - current).abs();
        return da.compareTo(db);
      });
      final next = remaining.first;
      selected.add(next);
      used.add(next.id);
    }

    return SpinningPlan(duration: duration, tracks: selected, phases: phases);
  }

  double _phaseDistance(Track track, SpinningPhaseSpec phase) {
    final center = (phase.minBpm + phase.maxBpm) / 2;
    return (track.bpm! - center).abs();
  }
}
