import 'dart:math';

import 'online_bpm_service.dart';

class BpmFusionResult {
  final double bpm;
  final double confidence;
  final double? localBpm;
  final double? onlineBpm;
  final double? onlineMatchScore;
  final BpmRelation relation;
  final bool possibleRemix;

  const BpmFusionResult({
    required this.bpm,
    required this.confidence,
    this.localBpm,
    this.onlineBpm,
    this.onlineMatchScore,
    required this.relation,
    required this.possibleRemix,
  });
}

enum BpmRelation { exact, halfTempo, doubleTempo, close, mismatch, localOnly, onlineOnly }

/// Combines local audio analysis with catalogue BPM data.
///
/// Tempo is compared in a harmonic-aware way so 64 vs 128 and 128 vs 256
/// are not treated as unrelated values. A large non-harmonic difference is
/// flagged as a possible alternate recording, remix or bad metadata match.
class BpmFusionService {
  BpmFusionResult fuse({
    required double? localBpm,
    required double? localConfidence,
    required OnlineBpmResult? online,
  }) {
    if (localBpm == null && online == null) {
      return const BpmFusionResult(
        bpm: 0,
        confidence: 0,
        relation: BpmRelation.mismatch,
        possibleRemix: false,
      );
    }

    if (localBpm == null) {
      final confidence = ((online!.matchScore * 0.85).clamp(0.0, 1.0));
      return BpmFusionResult(
        bpm: online.bpm,
        confidence: double.parse(confidence.toStringAsFixed(2)),
        onlineBpm: online.bpm,
        onlineMatchScore: online.matchScore,
        relation: BpmRelation.onlineOnly,
        possibleRemix: false,
      );
    }

    if (online == null) {
      return BpmFusionResult(
        bpm: localBpm,
        confidence: double.parse((localConfidence ?? 0.35).clamp(0.0, 1.0).toStringAsFixed(2)),
        localBpm: localBpm,
        relation: BpmRelation.localOnly,
        possibleRemix: false,
      );
    }

    final relation = _relation(localBpm, online.bpm);
    final localWeight = (localConfidence ?? 0.5).clamp(0.15, 0.95);
    final onlineWeight = online.matchScore.clamp(0.15, 1.0);

    double chosen;
    double agreement;
    final canonicalLocal = _canonical(localBpm);
    final canonicalOnline = _canonical(online.bpm);

    switch (relation) {
      case BpmRelation.exact:
        chosen = _weighted(localBpm, localWeight, online.bpm, onlineWeight);
        agreement = 1.0;
        break;
      case BpmRelation.halfTempo:
      case BpmRelation.doubleTempo:
        // First bring harmonic equivalents such as 64/128 or 128/256 to
        // the same canonical tempo before weighting them. This avoids
        // producing an artificial midpoint such as 96 BPM.
        chosen = _weighted(canonicalLocal, localWeight, canonicalOnline, onlineWeight);
        agreement = 0.72;
        break;
      case BpmRelation.close:
        chosen = _weighted(localBpm, localWeight, online.bpm, onlineWeight);
        agreement = 0.82;
        break;
      case BpmRelation.mismatch:
        chosen = localWeight >= onlineWeight ? localBpm : online.bpm;
        agreement = 0.25;
        break;
      case BpmRelation.localOnly:
      case BpmRelation.onlineOnly:
        chosen = localBpm;
        agreement = 0;
        break;
    }

    final confidence = (localWeight * 0.45 +
            onlineWeight * 0.35 +
            agreement * 0.20)
        .clamp(0.0, 1.0);

    final remix = relation == BpmRelation.mismatch &&
        online.matchScore >= 0.88 &&
        (localConfidence ?? 0) >= 0.65;

    return BpmFusionResult(
      bpm: double.parse(_normalize(chosen).toStringAsFixed(1)),
      confidence: double.parse(confidence.toStringAsFixed(2)),
      localBpm: localBpm,
      onlineBpm: online.bpm,
      onlineMatchScore: online.matchScore,
      relation: relation,
      possibleRemix: remix,
    );
  }

  BpmRelation _relation(double a, double b) {
    final direct = _distance(a, b);
    if (direct <= 0.025) return BpmRelation.exact;

    final half = _distance(a, b * 2);
    if (half <= 0.035) return BpmRelation.halfTempo;

    final twice = _distance(a * 2, b);
    if (twice <= 0.035) return BpmRelation.doubleTempo;

    if (direct <= 0.08) return BpmRelation.close;
    return BpmRelation.mismatch;
  }

  double _distance(double a, double b) => (a - b).abs() / max(1.0, max(a, b));

  double _weighted(double a, double wa, double b, double wb) =>
      (a * wa + b * wb) / (wa + wb);

  double _normalize(double bpm) {
    var value = bpm;
    while (value > 200) value /= 2;
    while (value < 70) value *= 2;
    return value;
  }

  double _canonical(double bpm) => _normalize(bpm);
}
