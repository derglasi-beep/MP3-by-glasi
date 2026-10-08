import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'equalizer_service.dart';
import 'settings_service.dart';

class AudioPlayerService {
  final AndroidEqualizer equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer loudnessEnhancer = AndroidLoudnessEnhancer();
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
  double _playerVolume = .8;
  double _preamp = 0;
  double _bass = 0;
  double _treble = 0;
  List<double> _manualEqBands = const [];
  List<double> _savedEqBands = const [];
  bool _audioSettingsLoaded = false;

  AudioPlayerService() {
    audio = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [equalizer, loudnessEnhancer]),
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

  Future<void> setQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool load = true,
    bool preserveCurrent = true,
  }) async {
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

    final preservedIndex = !preserveCurrent || oldTrack == null
        ? -1
        : queue.indexWhere((item) => item.id == oldTrack.id);
    currentIndex = preservedIndex >= 0
        ? preservedIndex
        : startIndex.clamp(0, queue.length - 1);

    if (load) {
      await _load();
      if (preserveCurrent && oldTrack != null && preservedIndex >= 0) {
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

  void updateTrack(Track track) {
    final index = queue.indexWhere((item) => item.id == track.id);
    if (index < 0) return;

    queue[index] = track;
    _publishQueue();

    if (index == currentIndex) {
      _trackController.add(track);
    }
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
      if (_audioSettingsLoaded) {
        await _restoreEqualizerIfAvailable();
      }
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
  Future<void> setVolume(double v) async {
    _playerVolume = v.clamp(0, 1).toDouble();
    await _applyEffectiveVolume();
  }

  Future<void> _applyEffectiveVolume() async {
    final attenuation = _preamp < 0 ? math.pow(10, _preamp / 20).toDouble() : 1.0;
    await audio.setVolume((_playerVolume * attenuation).clamp(0, 1).toDouble());
  }

  Future<void> setPreamp(double decibels) async {
    _preamp = decibels.clamp(-12, 12).toDouble();
    await _applyEffectiveVolume();

    if (_preamp > 0) {
      await loudnessEnhancer.setTargetGain(_preamp);
      await loudnessEnhancer.setEnabled(true);
    } else {
      await loudnessEnhancer.setTargetGain(0);
      await loudnessEnhancer.setEnabled(false);
    }
  }

  Future<void> setBass(double decibels) async {
    _bass = decibels.clamp(-12, 12).toDouble();
    await _applyToneEq();
  }

  Future<void> setTreble(double decibels) async {
    _treble = decibels.clamp(-12, 12).toDouble();
    await _applyToneEq();
  }

  Future<void> setEqBand(int index, double gain) async {
    try {
      final info = await EqualizerService(effect: equalizer).info;
      if (info == null || index < 0 || index >= info.bands.length) return;

      if (_manualEqBands.length != info.bands.length) {
        final old = _manualEqBands;
        _manualEqBands = List.generate(
          info.bands.length,
          (i) => i < old.length ? old[i] : 0,
        );
      }

      _manualEqBands[index] = gain.clamp(
        info.minDecibels,
        info.maxDecibels,
      ).toDouble();
      _savedEqBands = List<double>.from(_manualEqBands);
      await _applyToneEq(info: info);
    } catch (_) {
      // Android can temporarily invalidate the audio effect/session.
      // Keep the requested value in memory and reapply it after the next load.
      if (index >= 0) {
        final needed = index + 1;
        if (_savedEqBands.length < needed) {
          final old = _savedEqBands;
          _savedEqBands = List.generate(
            needed,
            (i) => i < old.length ? old[i] : 0,
          );
        }
        _savedEqBands[index] = gain;
      }
    }
  }

  double _bassWeight(double hz) {
    if (hz <= 125) return 1;
    if (hz <= 250) return .7;
    if (hz <= 500) return .35;
    return 0;
  }

  double _trebleWeight(double hz) {
    if (hz >= 8000) return 1;
    if (hz >= 4000) return .7;
    if (hz >= 2000) return .35;
    return 0;
  }

  Future<void> _applyToneEq({EqualizerInfo? info}) async {
    try {
      final params = info ?? await EqualizerService(effect: equalizer).info;
      if (params == null || params.bands.isEmpty) return;

      if (_manualEqBands.length != params.bands.length) {
        final source = _savedEqBands.isNotEmpty ? _savedEqBands : _manualEqBands;
        _manualEqBands = List.generate(
          params.bands.length,
          (i) => i < source.length ? source[i] : 0,
        );
      }

      var anyEffect = false;
      for (var i = 0; i < params.bands.length; i++) {
        final hz = params.bands[i].centerFrequency;
        final gain = (
          _manualEqBands[i] +
          (_bass * _bassWeight(hz)) +
          (_treble * _trebleWeight(hz))
        ).clamp(params.minDecibels, params.maxDecibels).toDouble();
        await params.bands[i].setGain(gain);
        if (gain.abs() > .001) anyEffect = true;
      }
      await equalizer.setEnabled(anyEffect);
    } catch (_) {
      // The native effect can disappear briefly when Android recreates
      // the audio session. It will be reapplied after the next track load.
    }
  }

  Future<EqualizerInfo?> equalizerInfo() async {
    try {
      final info = await EqualizerService(effect: equalizer)
          .info
          .timeout(const Duration(milliseconds: 800));
      debugPrint(
        '[EQ] parameters: '
        '${info == null ? 'nicht verfügbar' : '${info.bands.length} Bänder'} '
        'session=${audio.androidAudioSessionId} '
        'state=${audio.processingState.name} playing=${audio.playing}',
      );
      return info;
    } on TimeoutException {
      debugPrint(
        '[EQ] parameters Timeout '
        'session=${audio.androidAudioSessionId} '
        'state=${audio.processingState.name} playing=${audio.playing}',
      );
      return null;
    }
  }

  Future<EqualizerInfo?> ensureEqualizerReady() async {
    debugPrint(
      '[EQ] ensure start: track=${currentTrack?.title ?? 'null'} '
      'session=${audio.androidAudioSessionId} '
      'state=${audio.processingState.name} playing=${audio.playing}',
    );

    EqualizerInfo? info;
    if (audio.androidAudioSessionId != null) {
      info = await equalizerInfo();
      if (info != null && info.bands.isNotEmpty) {
        debugPrint('[EQ] bereits verfügbar.');
        return info;
      }
    } else {
      debugPrint('[EQ] noch keine Session, Parameterabfrage wird übersprungen.');
    }

    final track = currentTrack;
    if (track == null) {
      debugPrint('[EQ] Abbruch: kein aktueller Track.');
      return null;
    }

    try {
      if (audio.processingState == ProcessingState.idle ||
          audio.processingState == ProcessingState.completed) {
        debugPrint('[EQ] lade Quelle: ${track.path}');
        await audio.setFilePath(track.path);
        debugPrint(
          '[EQ] Quelle geladen: session=${audio.androidAudioSessionId} '
          'state=${audio.processingState.name}',
        );
        _trackController.add(track);
      }

      if (audio.androidAudioSessionId == null) {
        final oldPosition = audio.position;
        final wasPlaying = audio.playing;

        if (!wasPlaying) {
          debugPrint('[EQ] prime playback stumm starten.');
          await audio.setVolume(0);
          unawaited(
            audio.play().catchError((Object error, StackTrace stackTrace) {
              debugPrint('[EQ] prime play Fehler: $error');
            }),
          );
        }

        try {
          final sessionId = await audio.androidAudioSessionIdStream
              .firstWhere((id) => id != null)
              .timeout(const Duration(seconds: 3));
          debugPrint('[EQ] audioSessionId erhalten: $sessionId');
        } on TimeoutException {
          debugPrint(
            '[EQ] Timeout: keine audioSessionId nach 3 Sekunden. '
            'state=${audio.processingState.name} playing=${audio.playing}',
          );
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }

        if (!wasPlaying) {
          debugPrint('[EQ] prime playback pausieren/zurücksetzen.');
          await audio.pause();
          await audio.seek(oldPosition);
          await _applyEffectiveVolume();
        }
      }

      if (audio.androidAudioSessionId == null) {
        debugPrint('[EQ] Abbruch: audioSessionId weiterhin null.');
        return null;
      }

      for (var attempt = 0; attempt < 6; attempt++) {
        info = await equalizerInfo();
        if (info != null && info.bands.isNotEmpty) {
          debugPrint(
            '[EQ] bereit nach Versuch ${attempt + 1}: '
            '${info.bands.length} Bänder.',
          );
          if (_audioSettingsLoaded) {
            await _restoreEqualizerIfAvailable(info: info);
          }
          return info;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      debugPrint('[EQ] Session vorhanden, aber Parameter bleiben leer.');
    } catch (error, stackTrace) {
      debugPrint('[EQ] Initialisierung fehlgeschlagen: $error');
      debugPrintStack(stackTrace: stackTrace);
      try {
        await _applyEffectiveVolume();
      } catch (_) {}
      return null;
    }

    return null;
  }

  Future<void> _restoreEqualizerIfAvailable({EqualizerInfo? info}) async {
    final params = info ?? await equalizerInfo();
    if (params == null || params.bands.isEmpty) return;

    _manualEqBands = List.generate(
      params.bands.length,
      (i) => i < _savedEqBands.length
          ? _savedEqBands[i].clamp(
              params.minDecibels,
              params.maxDecibels,
            ).toDouble()
          : 0,
    );
    await _applyToneEq(info: params);
  }

  Future<void> setSpeed(double v) => audio.setSpeed(v.clamp(.5, 2));

  Future<void> restoreAudioSettings() async {
    final settings = SettingsService();
    final values = await Future.wait([
      settings.volume,
      settings.speed,
      settings.eqBands,
      settings.preamp,
      settings.bass,
      settings.treble,
    ]);

    _playerVolume = (values[0] as double).clamp(0, 1).toDouble();
    _savedEqBands = List<double>.from(values[2] as List<double>);
    _preamp = (values[3] as double).clamp(-12, 12).toDouble();
    _bass = (values[4] as double).clamp(-12, 12).toDouble();
    _treble = (values[5] as double).clamp(-12, 12).toDouble();
    _audioSettingsLoaded = true;

    await setSpeed(values[1] as double);
    await _applyEffectiveVolume();

    try {
      await setPreamp(_preamp);
    } catch (_) {
      // Loudness enhancer may also be unavailable before the first source.
    }

    await _restoreEqualizerIfAvailable();
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
