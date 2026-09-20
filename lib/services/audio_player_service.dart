import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';

class AudioPlayerService {
  final AndroidEqualizer equalizer = AndroidEqualizer();
  late final AudioPlayer audio;
  final List<Track> queue = [];
  final List<int> _history = [];
  final StreamController<Track?> _trackController = StreamController.broadcast();
  late final StreamSubscription<PlayerState> _stateSub;

  int currentIndex = -1;
  bool shuffle = false;
  LoopMode loopMode = LoopMode.off;

  AudioPlayerService() {
    audio = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]),
    );
    _stateSub = audio.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
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

  bool get canGoPrevious =>
      audio.position > const Duration(seconds: 3) || _history.isNotEmpty || currentIndex > 0;

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    queue
      ..clear()
      ..addAll(tracks);
    _history.clear();

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

  int _nextShuffleIndex() {
    if (queue.length <= 1) return currentIndex;
    final remaining = <int>[];
    for (var i = 0; i < queue.length; i++) {
      if (i != currentIndex && !_history.contains(i)) remaining.add(i);
    }
    // Start a fresh shuffle cycle after every track has been visited.
    final candidates = remaining.isNotEmpty
        ? remaining
        : [for (var i = 0; i < queue.length; i++) if (i != currentIndex) i];
    candidates.shuffle();
    return candidates.first;
  }

  Future<void> next() async {
    if (queue.isEmpty) return;

    if (loopMode == LoopMode.one) {
      await audio.seek(Duration.zero);
      await play();
      return;
    }

    if (currentIndex >= 0) _history.add(currentIndex);

    if (shuffle && queue.length > 1) {
      currentIndex = _nextShuffleIndex();
    } else if (currentIndex < queue.length - 1) {
      currentIndex++;
    } else if (loopMode == LoopMode.all) {
      currentIndex = 0;
    } else {
      _history.clear();
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

    if (shuffle && _history.isNotEmpty) {
      currentIndex = _history.removeLast();
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
    if (!shuffle) _history.clear();
    await audio.setShuffleModeEnabled(false);
  }

  Future<void> toggleRepeat() async {
    loopMode = switch (loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await audio.setLoopMode(LoopMode.off);
  }

  Future<void> dispose() async {
    await _stateSub.cancel();
    await _trackController.close();
    await audio.dispose();
  }
}
