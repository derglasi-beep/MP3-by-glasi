import 'dart:math';

/// Lightweight BPM estimator for mono PCM audio.
///
/// It builds an onset-strength envelope and compares it against a range of
/// beat periods. The best period is octave-corrected into a practical
/// music range (60..200 BPM).
class BpmAnalyzer {
  double? estimate(List<double> samples, int sampleRate) {
    if (sampleRate <= 0 || samples.length < sampleRate * 8) return null;

    const frameSize = 2048;
    const hop = 512;
    final envelope = <double>[];

    // RMS envelope. We deliberately keep this simple so it remains fast on
    // Windows/Linux as well as Android.
    for (var i = 0; i + frameSize <= samples.length; i += hop) {
      var energy = 0.0;
      for (var j = 0; j < frameSize; j++) {
        final x = samples[i + j];
        energy += x * x;
      }
      envelope.add(sqrt(energy / frameSize));
    }
    if (envelope.length < 16) return null;

    // Remove slow volume changes, then keep only positive changes.
    final mean = envelope.reduce((a, b) => a + b) / envelope.length;
    final onset = List<double>.filled(envelope.length, 0);
    for (var i = 1; i < envelope.length; i++) {
      final diff = envelope[i] - envelope[i - 1];
      onset[i] = diff > 0 ? diff : 0;
    }

    final onsetMean = onset.reduce((a, b) => a + b) / onset.length;
    final onsetVariance = onset
        .map((x) => pow(x - onsetMean, 2).toDouble())
        .reduce((a, b) => a + b) /
        onset.length;
    final onsetStd = sqrt(onsetVariance);
    if (onsetStd < 1e-7 || mean < 1e-7) return null;

    // Search beat periods directly using normalized autocorrelation.
    final minBpm = 60.0;
    final maxBpm = 200.0;
    final minLag = max(1, (60 * sampleRate / (maxBpm * hop)).round());
    final maxLag = min(
      onset.length ~/ 2,
      (60 * sampleRate / (minBpm * hop)).round(),
    );
    if (maxLag <= minLag) return null;

    var bestLag = 0;
    var bestScore = -double.infinity;

    for (var lag = minLag; lag <= maxLag; lag++) {
      var dot = 0.0;
      var a2 = 0.0;
      var b2 = 0.0;
      for (var i = lag; i < onset.length; i++) {
        final a = onset[i];
        final b = onset[i - lag];
        dot += a * b;
        a2 += a * a;
        b2 += b * b;
      }
      if (a2 <= 0 || b2 <= 0) continue;
      final score = dot / sqrt(a2 * b2);
      if (score > bestScore) {
        bestScore = score;
        bestLag = lag;
      }
    }

    if (bestLag == 0 || bestScore < 0.08) return null;

    var bpm = 60 * sampleRate / (bestLag * hop);

    // Autocorrelation often locks onto half/double tempo. Prefer the
    // musically common interpretation closest to 120 BPM.
    while (bpm < 70) bpm *= 2;
    while (bpm > 180) bpm /= 2;

    if (bpm < 60 || bpm > 200) return null;
    return double.parse(bpm.toStringAsFixed(1));
  }
}
