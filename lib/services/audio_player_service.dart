import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

class AudioPlayerService {
  final AndroidEqualizer equalizer = AndroidEqualizer();
  late final AudioPlayer audio;
  final List<Track> queue = [];
  final StreamController<Track?> _trackController = StreamController.broadcast();
  late final StreamSubscription<PlayerState> _stateSub;

  int currentIndex = -1;
  bool shuffle = false;
  LoopMode loopMode = LoopMode.off;
  final Random _random = Random();

  AudioPlayerService() {
    audio = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]),
    );
    _stateSub = audio.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed &&
          loopMode == LoopMode.off) {
        await next();
      }
    });
  }

  Stream<Duration> get positionStream => audio.positionStream;
  Stream<Duration?> get durationStream => audio.durationStream;
  Stream<PlayerState> get playerStateStream => audio.playerStateStream;
  Stream<Track?> get currentTrackStream => _trackController.stream;

  Track? get currentTrack =>
      currentIndex >= 0 && currentIndex < queue.length ? queue[currentIndex] : null;

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    queue
      ..clear()
      ..addAll(tracks);

    if (queue.isEmpty) {
      currentIndex = -1;
      _trackController.add(null);
      await audio.stop();
      return;
    }

    currentIndex = startIndex.clamp(0, queue.length - 1);
    await _load();
  }

  Future<void> _load() async {
    final t = currentTrack;
    if (t == null) return;
    await audio.setFilePath(t.path);
    _trackController.add(t);
  }

  Future<void> play() async {
    if (currentTrack != null) await audio.play();
  }

  Future<void> pause() => audio.pause();
  Future<void> seek(Duration p) => audio.seek(p);
  Future<void> setVolume(double v) => audio.setVolume(v.clamp(0, 1));
  Future<void> setSpeed(double v) => audio.setSpeed(v.clamp(.5, 2));

  Future<void> next() async {
    if (queue.isEmpty) return;

    if (loopMode == LoopMode.one) {
      await audio.seek(Duration.zero);
      await play();
      return;
    }

    if (shuffle && queue.length > 1) {
      var nextIndex = currentIndex;
      while (nextIndex == currentIndex) {
        nextIndex = _random.nextInt(queue.length);
      }
      currentIndex = nextIndex;
    } else if (currentIndex < queue.length - 1) {
      currentIndex++;
    } else if (loopMode == LoopMode.all) {
      currentIndex = 0;
    } else {
      await audio.pause();
      await audio.seek(Duration.zero);
      return;
    }

    await _load();
    await play();
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    if (audio.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }

    if (shuffle && queue.length > 1) {
      var previousIndex = currentIndex;
      while (previousIndex == currentIndex) {
        previousIndex = _random.nextInt(queue.length);
      }
      currentIndex = previousIndex;
    } else if (currentIndex > 0) {
      currentIndex--;
    } else if (loopMode == LoopMode.all) {
      currentIndex = queue.length - 1;
    } else {
      await seek(Duration.zero);
      return;
    }

    await _load();
    await play();
  }

  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
    await audio.setShuffleModeEnabled(false);
  }

  Future<void> toggleRepeat() async {
    loopMode = switch (loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await audio.setLoopMode(loopMode);
  }

  Future<void> dispose() async {
    await _stateSub.cancel();
    await _trackController.close();
    await audio.dispose();
  }
}
