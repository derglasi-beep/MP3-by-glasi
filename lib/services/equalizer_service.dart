import 'dart:io';

import 'package:just_audio/just_audio.dart';

class EqualizerInfo {
  final double minDecibels;
  final double maxDecibels;
  final List<AndroidEqualizerBand> bands;

  const EqualizerInfo({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bands,
  });
}

class EqualizerService {
  final AndroidEqualizer effect;

  EqualizerService({AndroidEqualizer? effect}) : effect = effect ?? AndroidEqualizer();

  Future<EqualizerInfo?> get info async {
    if (!Platform.isAndroid) return null;
    try {
      final params = await effect.parameters;
      return EqualizerInfo(
        minDecibels: params.minDecibels,
        maxDecibels: params.maxDecibels,
        bands: params.bands,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setBand(int index, double gain) async {
    final params = await info;
    if (params == null || params.bands.isEmpty) return;
    if (index < 0 || index >= params.bands.length) return;
    final safeGain = gain.clamp(params.minDecibels, params.maxDecibels);
    await params.bands[index].setGain(safeGain);
    await effect.setEnabled(true);
  }
}
