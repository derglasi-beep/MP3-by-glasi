import 'dart:math';

import '../models/track.dart';

enum SpinningPhase { warmup, build, load, peak, cooldown }

enum SpinningTrainingProfile { cadence, heartRate, power }

class _SpinningCurveBlock {
  final SpinningPhase phase;
  final double share;
  final List<double> pattern;

  const _SpinningCurveBlock(this.phase, this.share, this.pattern);
}

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
    final specs = {for (final spec in phases) spec.phase: spec};
    final blocks = _curveBlocks(profile, variant);
    final points = <SpinningCurvePoint>[];
    var elapsed = Duration.zero;
    double? previousTarget;
    var globalSample = 0;

    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final block = blocks[blockIndex];
      final spec = specs[block.phase];
      if (spec == null) continue;

      final blockDuration = blockIndex == blocks.length - 1
          ? duration - elapsed
          : Duration(
              milliseconds:
                  (duration.inMilliseconds * block.share).round(),
            );
      if (blockDuration <= Duration.zero) continue;

      final min = spec.minBpm.toDouble();
      final max = spec.maxBpm.toDouble();
      final span = max - min;
      final anchors = <double>[
        for (final value in block.pattern)
          min + span * value.clamp(0.0, 1.0),
      ];
      if (anchors.isEmpty) continue;

      if (previousTarget != null) {
        final blend = profile == SpinningTrainingProfile.heartRate ? .72 : .45;
        anchors[0] = (
          previousTarget! * blend + anchors.first * (1 - blend)
        ).clamp(min, max).toDouble();
      }

      if (profile == SpinningTrainingProfile.power) {
        for (var i = 0; i < anchors.length; i++) {
          final fraction =
              anchors.length == 1 ? 0.0 : i / (anchors.length - 1);
          points.add(
            SpinningCurvePoint(
              position: elapsed +
                  Duration(
                    milliseconds:
                        (blockDuration.inMilliseconds * fraction).round(),
                  ),
              targetBpm: anchors[i],
              phase: block.phase,
              tolerance: block.phase == SpinningPhase.peak ? 5 : 7,
            ),
          );
        }
      } else {
        final samplesPerSegment =
            profile == SpinningTrainingProfile.heartRate ? 7 : 4;

        if (anchors.length == 1) {
          points.add(
            SpinningCurvePoint(
              position: elapsed,
              targetBpm: anchors.first,
              phase: block.phase,
              tolerance: block.phase == SpinningPhase.peak ? 5 : 7,
            ),
          );
        } else {
          for (var segment = 0; segment < anchors.length - 1; segment++) {
            final startTarget = anchors[segment];
            final endTarget = anchors[segment + 1];

            for (var sample = 0; sample < samplesPerSegment; sample++) {
              if (segment > 0 && sample == 0) continue;

              final local = sample / samplesPerSegment;
              final eased = local * local * (3 - 2 * local);
              var target =
                  startTarget + (endTarget - startTarget) * eased;

              final waveStrength =
                  profile == SpinningTrainingProfile.heartRate ? .045 : .02;
              target += sin((globalSample + variant * 3) * .68) *
                  span *
                  waveStrength;
              target = target.clamp(min, max).toDouble();

              final blockFraction =
                  (segment + local) / (anchors.length - 1);
              points.add(
                SpinningCurvePoint(
                  position: elapsed +
                      Duration(
                        milliseconds: (blockDuration.inMilliseconds *
                                blockFraction)
                            .round(),
                      ),
                  targetBpm: target,
                  phase: block.phase,
                  tolerance: block.phase == SpinningPhase.peak ? 5 : 7,
                ),
              );
              globalSample++;
            }
          }

          points.add(
            SpinningCurvePoint(
              position: elapsed + blockDuration,
              targetBpm: anchors.last,
              phase: block.phase,
              tolerance: block.phase == SpinningPhase.peak ? 5 : 7,
            ),
          );
        }
      }

      previousTarget = anchors.last;
      elapsed += blockDuration;
    }

    if (points.isNotEmpty && points.last.position != duration) {
      final last = points.last;
      points.add(
        SpinningCurvePoint(
          position: duration,
          targetBpm: last.targetBpm,
          phase: last.phase,
          tolerance: last.tolerance,
        ),
      );
    }

    return points;
  }

  List<_SpinningCurveBlock> _curveBlocks(
    SpinningTrainingProfile profile,
    int variant,
  ) {
    if (profile == SpinningTrainingProfile.heartRate) {
      return switch (variant) {
        0 => const [
            _SpinningCurveBlock(SpinningPhase.warmup, .16, [.05, .28, .52, .68]),
            _SpinningCurveBlock(SpinningPhase.build, .11, [.30, .58, .78]),
            _SpinningCurveBlock(SpinningPhase.load, .13, [.42, .74, .58, .82]),
            _SpinningCurveBlock(SpinningPhase.build, .08, [.58, .34]),
            _SpinningCurveBlock(SpinningPhase.load, .13, [.44, .70, .88]),
            _SpinningCurveBlock(SpinningPhase.peak, .10, [.52, .84, .68, .96]),
            _SpinningCurveBlock(SpinningPhase.build, .08, [.62, .38]),
            _SpinningCurveBlock(SpinningPhase.peak, .09, [.58, .90, .72, .98]),
            _SpinningCurveBlock(SpinningPhase.cooldown, .12, [.72, .48, .26, .08]),
          ],
        1 => const [
            _SpinningCurveBlock(SpinningPhase.warmup, .15, [.05, .24, .46, .66]),
            _SpinningCurveBlock(SpinningPhase.build, .10, [.28, .56, .76]),
            _SpinningCurveBlock(SpinningPhase.load, .12, [.46, .68, .52, .78]),
            _SpinningCurveBlock(SpinningPhase.build, .07, [.54, .32]),
            _SpinningCurveBlock(SpinningPhase.load, .11, [.48, .76, .60, .84]),
            _SpinningCurveBlock(SpinningPhase.peak, .08, [.60, .88, .70]),
            _SpinningCurveBlock(SpinningPhase.build, .07, [.56, .36]),
            _SpinningCurveBlock(SpinningPhase.load, .10, [.50, .80, .64]),
            _SpinningCurveBlock(SpinningPhase.peak, .09, [.62, .94, .76, .98]),
            _SpinningCurveBlock(SpinningPhase.cooldown, .11, [.74, .50, .28, .08]),
          ],
        _ => const [
            _SpinningCurveBlock(SpinningPhase.warmup, .17, [.04, .22, .44, .64]),
            _SpinningCurveBlock(SpinningPhase.build, .09, [.30, .52, .72]),
            _SpinningCurveBlock(SpinningPhase.load, .11, [.40, .66, .52, .76]),
            _SpinningCurveBlock(SpinningPhase.build, .07, [.52, .30]),
            _SpinningCurveBlock(SpinningPhase.peak, .08, [.56, .82, .66]),
            _SpinningCurveBlock(SpinningPhase.load, .12, [.48, .72, .88]),
            _SpinningCurveBlock(SpinningPhase.build, .07, [.58, .34]),
            _SpinningCurveBlock(SpinningPhase.peak, .10, [.60, .90, .72, .98]),
            _SpinningCurveBlock(SpinningPhase.cooldown, .19, [.76, .60, .42, .24, .08]),
          ],
      };
    }

    if (profile == SpinningTrainingProfile.power) {
      return switch (variant) {
        0 => const [
            _SpinningCurveBlock(SpinningPhase.warmup, .14, [.10, .38, .66]),
            _SpinningCurveBlock(SpinningPhase.build, .08, [.28, .62]),
            _SpinningCurveBlock(SpinningPhase.peak, .08, [.62, .96]),
            _SpinningCurveBlock(SpinningPhase.build, .07, [.54, .26]),
            _SpinningCurveBlock(SpinningPhase.load, .10, [.38, .86]),
            _SpinningCurveBlock(SpinningPhase.build, .06, [.52, .24]),
            _SpinningCurveBlock(SpinningPhase.peak, .09, [.64, 1.00]),
            _SpinningCurveBlock(SpinningPhase.build, .06, [.56, .28]),
            _SpinningCurveBlock(SpinningPhase.load, .10, [.42, .90]),
            _SpinningCurveBlock(SpinningPhase.peak, .09, [.70, .98]),
            _SpinningCurveBlock(SpinningPhase.cooldown, .13, [.72, .38, .08]),
          ],
        1 => const [
            _SpinningCurveBlock(SpinningPhase.warmup, .15, [.08, .34, .62]),
            _SpinningCurveBlock(SpinningPhase.load, .09, [.38, .80]),
            _SpinningCurveBlock(SpinningPhase.build, .06, [.48, .24]),
            _SpinningCurveBlock(SpinningPhase.peak, .08, [.62, .94]),
            _SpinningCurveBlock(SpinningPhase.build, .06, [.50, .26]),
            _SpinningCurveBlock(SpinningPhase.load, .09, [.40, .86]),
            _SpinningCurveBlock(SpinningPhase.build, .06, [.52, .28]),
            _SpinningCurveBlock(SpinningPhase.peak, .10, [.66, 1.00]),
            _SpinningCurveBlock(SpinningPhase.build, .06, [.54, .26]),
            _SpinningCurveBlock(SpinningPhase.peak, .10, [.68, .96]),
            _SpinningCurveBlock(SpinningPhase.cooldown, .15, [.74, .40, .08]),
          ],
        _ => const [
            _SpinningCurveBlock(SpinningPhase.warmup, .13, [.10, .40, .68]),
            _SpinningCurveBlock(SpinningPhase.peak, .07, [.60, .92]),
            _SpinningCurveBlock(SpinningPhase.build, .07, [.50, .24]),
            _SpinningCurveBlock(SpinningPhase.load, .10, [.40, .84]),
            _SpinningCurveBlock(SpinningPhase.build, .06, [.48, .22]),
            _SpinningCurveBlock(SpinningPhase.peak, .09, [.64, 1.00]),
            _SpinningCurveBlock(SpinningPhase.build, .06, [.52, .26]),
            _SpinningCurveBlock(SpinningPhase.load, .09, [.42, .88]),
            _SpinningCurveBlock(SpinningPhase.build, .06, [.50, .24]),
            _SpinningCurveBlock(SpinningPhase.peak, .11, [.66, .98]),
            _SpinningCurveBlock(SpinningPhase.cooldown, .16, [.72, .36, .08]),
          ],
      };
    }

    return switch (variant) {
      0 => const [
          _SpinningCurveBlock(SpinningPhase.warmup, .15, [.08, .30, .56, .72]),
          _SpinningCurveBlock(SpinningPhase.build, .12, [.30, .58, .76]),
          _SpinningCurveBlock(SpinningPhase.load, .13, [.42, .72, .54, .82]),
          _SpinningCurveBlock(SpinningPhase.build, .08, [.54, .30]),
          _SpinningCurveBlock(SpinningPhase.peak, .10, [.58, .88, .70]),
          _SpinningCurveBlock(SpinningPhase.load, .12, [.46, .78, .60]),
          _SpinningCurveBlock(SpinningPhase.peak, .10, [.62, .94, .74]),
          _SpinningCurveBlock(SpinningPhase.cooldown, .20, [.72, .50, .28, .08]),
        ],
      1 => const [
          _SpinningCurveBlock(SpinningPhase.warmup, .16, [.08, .28, .52, .70]),
          _SpinningCurveBlock(SpinningPhase.load, .12, [.38, .68, .52]),
          _SpinningCurveBlock(SpinningPhase.build, .08, [.50, .28]),
          _SpinningCurveBlock(SpinningPhase.load, .12, [.42, .76, .58]),
          _SpinningCurveBlock(SpinningPhase.peak, .10, [.58, .90, .70]),
          _SpinningCurveBlock(SpinningPhase.build, .08, [.54, .30]),
          _SpinningCurveBlock(SpinningPhase.peak, .11, [.62, .96, .76]),
          _SpinningCurveBlock(SpinningPhase.cooldown, .23, [.74, .54, .34, .16, .06]),
        ],
      _ => const [
          _SpinningCurveBlock(SpinningPhase.warmup, .14, [.06, .26, .50, .68]),
          _SpinningCurveBlock(SpinningPhase.build, .10, [.30, .54, .72]),
          _SpinningCurveBlock(SpinningPhase.peak, .08, [.56, .84]),
          _SpinningCurveBlock(SpinningPhase.build, .07, [.50, .26]),
          _SpinningCurveBlock(SpinningPhase.load, .13, [.40, .72, .56, .82]),
          _SpinningCurveBlock(SpinningPhase.build, .07, [.52, .28]),
          _SpinningCurveBlock(SpinningPhase.peak, .10, [.60, .92, .72]),
          _SpinningCurveBlock(SpinningPhase.load, .11, [.48, .78, .62]),
          _SpinningCurveBlock(SpinningPhase.cooldown, .20, [.72, .48, .26, .06]),
        ],
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
