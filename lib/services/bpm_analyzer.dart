import 'dart:math';

class BpmResult {
  final double bpm;
  final double confidence;

  const BpmResult({required this.bpm, required this.confidence});
}

/// Lightweight BPM estimator for mono PCM audio.
///
/// Uses an onset envelope plus normalized autocorrelation. Several harmonic
/// interpretations are compared so half/double-tempo mistakes are reduced.
class BpmAnalyzer {
  BpmResult? estimateResult(List<double> samples, int sampleRate) {
    if (sampleRate <= 0 || samples.length < sampleRate * 8) return null;

    const frameSize = 2048;
    const hop = 512;
    final envelope = <double>[];

    for (var i = 0; i + frameSize <= samples.length; i += hop) {
      var energy = 0.0;
      for (var j = 0; j < frameSize; j++) {
        final x = samples[i + j];
        energy += x * x;
      }
      envelope.add(sqrt(energy / frameSize));
    }
    if (envelope.length < 32) return null;

    // First difference is a simple onset-strength function.
    final onset = List<double>.filled(envelope.length, 0);
    for (var i = 1; i < envelope.length; i++) {
      final diff = envelope[i] - envelope[i - 1];
      onset[i] = diff > 0 ? diff : 0;
    }

    // Normalize to make the result less sensitive to overall track volume.
    final mean = onset.reduce((a, b) => a + b) / onset.length;
    final variance = onset
        .map((x) => pow(x - mean, 2).toDouble())
        .reduce((a, b) => a + b) /
        onset.length;
    final std = sqrt(variance);
    if (std < 1e-7 || mean < 1e-7) return null;

    for (var i = 0; i < onset.length; i++) {
      onset[i] = max(0, (onset[i] - mean) / std);
    }

    const minBpm = 55.0;
    const maxBpm = 210.0;
    final minLag = max(1, (60 * sampleRate / (maxBpm * hop)).round());
    final maxLag = min(
      onset.length ~/ 2,
      (60 * sampleRate / (minBpm * hop)).round(),
    );
    if (maxLag <= minLag) return null;

    final scores = <int, double>{};
    for (var lag = minLag; lag <= maxLag; lag++) {
      scores[lag] = _correlation(onset, lag);
    }

    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isEmpty || ranked.first.value < 0.08) return null;

    // Evaluate local peaks and their 1/2x and 2x tempo interpretations.
    final candidates = <_Candidate>[];
    for (final entry in ranked.take(12)) {
      if (!_isLocalPeak(scores, entry.key)) continue;
      final baseBpm = 60 * sampleRate / (entry.key * hop);
      for (final factor in const [0.5, 1.0, 2.0]) {
        final bpm = baseBpm * factor;
        if (bpm < 60 || bpm > 200) continue;

        final support = _harmonicSupport(scores, entry.key);
        final rangeBonus = _rangePreference(bpm);
        candidates.add(_Candidate(
          bpm: bpm,
          score: entry.value + support * 0.18 + rangeBonus,
        ));
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;

    // Round to a practical tenth while keeping a confidence estimate from
    // score separation. Confidence is intentionally conservative.
    final second = candidates.length > 1 ? candidates[1].score : 0.0;
    final separation = max(0, best.score - second);
    final confidence = (0.45 + best.score * 0.45 + separation * 0.8)
        .clamp(0.0, 1.0);

    return BpmResult(
      bpm: double.parse(best.bpm.toStringAsFixed(1)),
      confidence: double.parse(confidence.toStringAsFixed(2)),
    );
  }

  double? estimate(List<double> samples, int sampleRate) =>
      estimateResult(samples, sampleRate)?.bpm;

  double _correlation(List<double> data, int lag) {
    var dot = 0.0;
    var a2 = 0.0;
    var b2 = 0.0;
    for (var i = lag; i < data.length; i++) {
      final a = data[i];
      final b = data[i - lag];
      dot += a * b;
      a2 += a * a;
      b2 += b * b;
    }
    if (a2 <= 0 || b2 <= 0) return 0;
    return dot / sqrt(a2 * b2);
  }

  bool _isLocalPeak(Map<int, double> scores, int lag) {
    final score = scores[lag] ?? 0;
    for (var d = 1; d <= 2; d++) {
      if ((scores[lag - d] ?? -1) > score) return false;
      if ((scores[lag + d] ?? -1) > score) return false;
    }
    return true;
  }

  double _harmonicSupport(Map<int, double> scores, int lag) {
    var total = 0.0;
    var count = 0;
    for (final factor in const [0.5, 2.0]) {
      final related = (lag * factor).round();
      final value = scores[related];
      if (value != null) {
        total += value;
        count++;
      }
    }
    return count == 0 ? 0 : total / count;
  }

  double _rangePreference(double bpm) {
    // Small preference for common musical tempos, never enough to override
    // a clearly stronger autocorrelation peak.
    if (bpm >= 85 && bpm <= 175) return 0.035;
    return 0;
  }
}

class _Candidate {
  final double bpm;
  final double score;

  const _Candidate({required this.bpm, required this.score});
}
