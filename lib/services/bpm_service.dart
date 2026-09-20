import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'bpm_analyzer.dart';

class BpmService {
  final BpmAnalyzer analyzer;
  BpmService({BpmAnalyzer? analyzer}) : analyzer = analyzer ?? BpmAnalyzer();

  Future<BpmResult?> analyzeFileResult(String inputPath) async {
    final temp = await getTemporaryDirectory();
    final output = File(
      temp.path + '/bpm_' + DateTime.now().microsecondsSinceEpoch.toString() + '.f32',
    );
    try {
      final input = _quote(inputPath);
      final out = _quote(output.path);
      final session = await FFmpegKit.execute(
        '-y -i ' + input + ' -t 90 -vn -ac 1 -ar 44100 -f f32le ' + out,
      );
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code) || !await output.exists()) return null;
      final bytes = await output.readAsBytes();
      final data = Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
      return analyzer.estimateResult(data, 44100);
    } catch (_) {
      return null;
    } finally {
      if (await output.exists()) await output.delete();
    }
  }

  Future<double?> analyzeFile(String inputPath) async =>
      (await analyzeFileResult(inputPath))?.bpm;

  String _quote(String value) => '"' + value.replaceAll('"', '\\"') + '"';
}
