import 'package:just_audio/just_audio.dart';

class EqualizerService {
  final AndroidEqualizer effect;

  EqualizerService({AndroidEqualizer? effect}) : effect = effect ?? AndroidEqualizer();

  Future<void> setBand(int index, double gain) async {
    try {
      final params = await effect.parameters;
      if (params.bands.isEmpty) return;
      final safeIndex = index.clamp(0, params.bands.length - 1);
      final safeGain = gain.clamp(params.minDecibels, params.maxDecibels);
      await params.bands[safeIndex].setGain(safeGain);
      await effect.setEnabled(true);
    } catch (_) {
      // Desktop backends currently do not expose just_audio's Android EQ API.
    }
  }
}
