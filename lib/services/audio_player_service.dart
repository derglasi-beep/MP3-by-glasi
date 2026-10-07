import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'equalizer_service.dart';
import 'settings_service.dart';

class AudioPlayerService {
  final AndroidEqualizer equalizer = AndroidEqualizer();
  late final AudioPlayer audio;
  final List<Track> queue = [];
  final List<int> _history = [];
  final StreamController<Track?> _trackController = StreamController.broadcast();
  final StreamController<List<Track>> _queueController = StreamController.broadcast();
  final StreamController<String> _errorController = StreamController.broadcast();
  late final StreamSubscription<PlayerState> _stateSub;

  int currentIndex = -1;
  bool shuffle = false;
  LoopMode loopMode = LoopMode.off;
  bool _completionInProgress = false;

  AudioPlayerService() {
    audio = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]),
    );
    _stateSub = audio.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _handleCompletion();
      }
    });
  }

  Stream<Duration> get positionStream => audio.positionStream;
  Stream<Duration?> get durationStream => audio.durationStream;
  Stream<PlayerState> get playerStateStream => audio.playerStateStream;
  Stream<Track?> get currentTrackStream => _trackController.stream;
  Stream<List<Track>> get queueStream => _queueController.stream;
  Stream<String> get errorStream => _errorController.stream;

  Track? get currentTrack =>
      currentIndex >= 0 && currentIndex < queue.length ? queue[currentIndex] : null;

  bool get canGoNext {
    if (queue.isEmpty || currentIndex < 0) return false;
    if (loopMode == LoopMode.one) return true;
    if (queue.length > 1 && shuffle) return true;
    if (currentIndex < queue.length - 1) return true;
    return loopMode == LoopMode.all;
  }

  bool get canGoPrevious =>
      audio.position > const Duration(seconds: 3) ||
      (shuffle && _history.isNotEmpty) ||
      currentIndex > 0 ||
      loopMode == LoopMode.all;

  void _publishQueue() => _queueController.add(List.unmodifiable(queue));

  void _publishError(Object error, {String? fallback}) {
    final message = error is PlayerException && (error.message ?? '').isNotEmpty
        ? error.message ?? ''
        : fallback ?? 'Wiedergabe konnte nicht gestartet werden.';
    if (!_errorController.isClosed) _errorController.add(message);
  }

  Future<void> _handleCompletion() async {
    if (_completionInProgress) return;
    _completionInProgress = true;
    try {
      await next(fromCompletion: true);
    } catch (e) {
      _publishError(e);
    } finally {
      _completionInProgress = false;
    }
  }

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0, bool load = true}) async {
    final oldTrack = currentTrack;
    final oldPosition = audio.position;
    final wasPlaying = audio.playing;

    queue
      ..clear()
      ..addAll(tracks);
    _history.clear();

    if (queue.isEmpty) {
      currentIndex = -1;
      _trackController.add(null);
      _publishQueue();
      await audio.stop();
      return;
    }

    final preservedIndex = oldTrack == null
        ? -1
        : queue.indexWhere((item) => item.id == oldTrack.id);
    currentIndex = preservedIndex >= 0
        ? preservedIndex
        : startIndex.clamp(0, queue.length - 1);

    if (load) {
      await _load();
      if (oldTrack != null && preservedIndex >= 0) {
        await seek(oldPosition);
        if (wasPlaying) await play();
      }
    } else {
      _trackController.add(currentTrack);
    }
    _publishQueue();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= queue.length) return;
    if (index == currentIndex &&
        audio.processingState != ProcessingState.idle &&
        audio.processingState != ProcessingState.completed) {
      await play();
      return;
    }

    currentIndex = index;
    await _load();
    await play();
    _publishQueue();
  }

  Future<void> addToQueue(Track track) async {
    queue.add(track);
    if (currentIndex == -1) {
      currentIndex = 0;
      await _load();
    }
    _publishQueue();
  }

  Future<void> addTracksToQueue(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final wasEmpty = queue.isEmpty;
    queue.addAll(tracks);
    if (wasEmpty) {
      currentIndex = 0;
      await _load();
    }
    _publishQueue();
  }

  Future<void> playNext(Track track) async {
    if (queue.isEmpty || currentIndex < 0) {
      await addToQueue(track);
      return;
    }
    final insertAt = (currentIndex + 1).clamp(0, queue.length);
    queue.insert(insertAt, track);
    _shiftHistoryAfterInsert(insertAt);
    _publishQueue();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= queue.length) return;
    final wasCurrent = index == currentIndex;
    final wasPlaying = audio.playing;

    queue.removeAt(index);
    _shiftHistoryAfterRemove(index);

    if (queue.isEmpty) {
      currentIndex = -1;
      _trackController.add(null);
      _publishQueue();
      await audio.stop();
      return;
    }

    if (index < currentIndex) {
      currentIndex--;
    } else if (wasCurrent) {
      if (currentIndex >= queue.length) currentIndex = queue.length - 1;
      await _load();
      if (wasPlaying) await play();
    }

    _publishQueue();
  }

  Future<void> move(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= queue.length) return;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex < 0 || newIndex >= queue.length || newIndex == oldIndex) return;

    final history = List<int>.from(_history);
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);

    currentIndex = _movedIndex(currentIndex, oldIndex, newIndex);
    _history
      ..clear()
      ..addAll(history.map((i) => _movedIndex(i, oldIndex, newIndex)));
    _publishQueue();
    _trackController.add(currentTrack);
  }

  Future<void> clearQueue() async {
    queue.clear();
    _history.clear();
    currentIndex = -1;
    _trackController.add(null);
    _publishQueue();
    await audio.stop();
  }

  int _movedIndex(int index, int oldIndex, int newIndex) {
    if (index == oldIndex) return newIndex;
    if (oldIndex < newIndex && index > oldIndex && index <= newIndex) return index - 1;
    if (newIndex < oldIndex && index >= newIndex && index < oldIndex) return index + 1;
    return index;
  }

  void _shiftHistoryAfterInsert(int index) {
    for (var i = 0; i < _history.length; i++) {
      if (_history[i] >= index) _history[i]++;
    }
  }

  void _shiftHistoryAfterRemove(int index) {
    _history.removeWhere((i) => i == index);
    for (var i = 0; i < _history.length; i++) {
      if (_history[i] > index) _history[i]--;
    }
  }

  Future<void> _load() async {
    final t = currentTrack;
    if (t == null) return;

    try {
      await audio.setFilePath(t.path);
      _trackController.add(t);
    } on PlayerException catch (e) {
      await audio.stop();
      _trackController.add(null);
      _publishError(e, fallback: 'Titel konnte nicht geladen werden.');
      rethrow;
    }
  }

  Future<void> play() async {
    if (currentTrack == null) return;

    // A restored queue can have a valid currentIndex while the native
    // player is still idle. In that state play() alone cannot produce audio.
    if (audio.processingState == ProcessingState.idle ||
        audio.processingState == ProcessingState.completed) {
      await _load();
    }

    try {
      await audio.play();
    } on PlayerException catch (e) {
      await audio.stop();
      _publishError(e, fallback: 'Wiedergabe konnte nicht gestartet werden.');
      rethrow;
    }
  }

  Future<void> pause() => audio.pause();
  Future<void> seek(Duration p) {
    final duration = audio.duration;
    if (duration == null) return audio.seek(p);
    final clamped = Duration(
      milliseconds: p.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    return audio.seek(clamped);
  }
  Future<void> setVolume(double v) => audio.setVolume(v.clamp(0, 1));
  Future<void> setSpeed(double v) => audio.setSpeed(v.clamp(.5, 2));

  Future<void> restoreAudioSettings() async {
    final settings = SettingsService();
    final values = await Future.wait([
      settings.volume,
      settings.speed,
      settings.eqBands,
    ]);

    await setVolume(values[0] as double);
    await setSpeed(values[1] as double);

    final savedBands = values[2] as List<double>;
    final eq = EqualizerService(effect: equalizer);
    final info = await eq.info;
    if (info == null || info.bands.isEmpty) return;

    for (var i = 0; i < info.bands.length && i < savedBands.length; i++) {
      final gain = savedBands[i].clamp(
        info.minDecibels,
        info.maxDecibels,
      ).toDouble();
      if (gain != 0) {
        await info.bands[i].setGain(gain);
      }
    }

    if (savedBands.take(info.bands.length).any((gain) => gain != 0)) {
      await equalizer.setEnabled(true);
    }
  }

  int _nextShuffleIndex() {
    if (queue.length <= 1) return currentIndex;
    final remaining = <int>[];
    for (var i = 0; i < queue.length; i++) {
      if (i != currentIndex && !_history.contains(i)) remaining.add(i);
    }
    final candidates = remaining.isNotEmpty
        ? remaining
        : [for (var i = 0; i < queue.length; i++) if (i != currentIndex) i];
    candidates.shuffle();
    return candidates.first;
  }

  Future<void> next({bool fromCompletion = false}) async {
    if (queue.isEmpty) return;

    if (loopMode == LoopMode.one && fromCompletion) {
      await audio.seek(Duration.zero);
      await play();
      return;
    }

    if (shuffle && currentIndex >= 0) {
      _history.add(currentIndex);
    }

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
    _completionInProgress = true;
    await _stateSub.cancel();
    await _trackController.close();
    await _queueController.close();
    await _errorController.close();
    await audio.dispose();
  }
}
