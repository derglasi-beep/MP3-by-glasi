import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

class AudioPlayerService {
  final AudioPlayer audio = AudioPlayer();
  final List<Track> queue = [];
  int currentIndex = -1;

  Stream<Duration> get positionStream => audio.positionStream;
  Stream<Duration?> get durationStream => audio.durationStream;
  Stream<PlayerState> get playerStateStream => audio.playerStateStream;

  Track? get currentTrack =>
      currentIndex >= 0 && currentIndex < queue.length ? queue[currentIndex] : null;

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    queue
      ..clear()
      ..addAll(tracks);
    if (queue.isEmpty) {
      currentIndex = -1;
      await audio.stop();
      return;
    }
    currentIndex = startIndex.clamp(0, queue.length - 1);
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final track = currentTrack;
    if (track == null) return;
    await audio.setFilePath(track.path);
  }

  Future<void> play() async {
    if (currentTrack == null) return;
    await audio.play();
  }

  Future<void> pause() => audio.pause();

  Future<void> seek(Duration position) => audio.seek(position);

  Future<void> next() async {
    if (queue.isEmpty) return;
    currentIndex = (currentIndex + 1) % queue.length;
    await _loadCurrent();
    await play();
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    if (audio.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    currentIndex = (currentIndex - 1 + queue.length) % queue.length;
    await _loadCurrent();
    await play();
  }

  Future<void> setVolume(double value) => audio.setVolume(value.clamp(0, 1));

  Future<void> dispose() => audio.dispose();
}
