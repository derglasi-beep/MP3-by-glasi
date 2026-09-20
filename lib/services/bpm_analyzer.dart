import 'dart:math';

/// BPM estimation from a mono PCM amplitude envelope.
///
/// The player currently exposes this as a reusable analysis engine.
/// A platform decoder still needs to feed normalized PCM samples from
/// MP3/FLAC/etc. into [estimate].
class BpmAnalyzer {
  double? estimate(List<double> samples, int sampleRate) {
    if (samples.length < sampleRate * 4 || sampleRate <= 0) return null;

    const frameSize = 1024;
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

    if (envelope.length < 8) return null;

    var mean = envelope.reduce((a, b) => a + b) / envelope.length;
    var variance = envelope
        .map((x) => pow(x - mean, 2))
        .reduce((a, b) => a + b) / envelope.length;
    final threshold = mean + sqrt(variance);

    final onsets = <int>[];
    for (var i = 1; i < envelope.length; i++) {
      if (envelope[i] > threshold && envelope[i] > envelope[i - 1]) {
        onsets.add(i);
      }
    }

    if (onsets.length < 4) return null;

    final candidates = <double>[];
    for (var i = 1; i < onsets.length; i++) {
      final frames = onsets[i] - onsets[i - 1];
      final seconds = frames * hop / sampleRate;
      if (seconds <= 0) continue;
      final bpm = 60 / seconds;
      if (bpm >= 50 && bpm <= 220) candidates.add(bpm);
    }

    if (candidates.isEmpty) return null;
    candidates.sort();
    final median = candidates[candidates.length ~/ 2];
    return double.parse(median.toStringAsFixed(1));
  }
}
