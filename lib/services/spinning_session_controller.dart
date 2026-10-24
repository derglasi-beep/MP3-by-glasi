import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'audio_player_service.dart';
import 'spinning_playlist_service.dart';

class SpinningSessionController {
  final AudioPlayerService player;
  final SpinningPlan plan;
  final CustomBpmProfile? customProfile;
  final bool sprintMode;
  final List<Track> library;
  final Map<String, SpinningPhase> phaseByTrackId = <String, SpinningPhase>{};

  final Stopwatch _watch = Stopwatch();
  Duration _offset = Duration.zero;
  StreamSubscription<PlayerState>? _playerStateSub;
  bool completed = false;
  bool ended = false;

  SpinningSessionController({
    required this.player,
    required this.plan,
    required this.customProfile,
    required this.sprintMode,
    required this.library,
  }) {
    for (final selection in plan.selections) {
      phaseByTrackId[selection.track.id] = selection.phase;
    }

    if (player.audio.playing) {
      _watch.start();
    }

    _playerStateSub = player.playerStateStream.listen((state) {
      if (ended || completed) {
        _watch.stop();
        return;
      }

      if (state.playing) {
        if (!_watch.isRunning && elapsed < plan.duration) {
          _watch.start();
        }
      } else {
        _watch.stop();
      }
    });
  }

  Duration get elapsed {
    final value = _offset + _watch.elapsed;
    return value > plan.duration ? plan.duration : value;
  }

  bool get isRunning => _watch.isRunning;

  SpinningPhase? phaseForTrack(Track track) => phaseByTrackId[track.id];

  void setTrackPhase(Track track, SpinningPhase phase) {
    phaseByTrackId[track.id] = phase;
  }

  void removeTrackPhase(Track track) {
    phaseByTrackId.remove(track.id);
  }

  void jumpTo(Duration position) {
    final clampedMs =
        position.inMilliseconds.clamp(0, plan.duration.inMilliseconds).toInt();
    final wasRunning = _watch.isRunning;
    _watch
      ..stop()
      ..reset();
    _offset = Duration(milliseconds: clampedMs);
    if (wasRunning && _offset < plan.duration && !ended) {
      _watch.start();
    }
  }

  Future<void> complete() async {
    if (completed || ended) return;
    completed = true;
    _watch.stop();
    _offset = plan.duration;
    await player.pause();
  }

  Future<void> end() async {
    if (ended) return;
    ended = true;
    _watch.stop();
    await player.pause();
  }

  Future<void> dispose() async {
    _watch.stop();
    await _playerStateSub?.cancel();
  }
}
