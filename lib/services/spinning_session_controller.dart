import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'audio_player_service.dart';
import 'heart_rate_sensor_service.dart';
import 'spinning_playlist_service.dart';
import 'spinning_session_history_service.dart';

class SpinningSessionController {
  final AudioPlayerService player;
  final SpinningPlan plan;
  final CustomBpmProfile? customProfile;
  final bool sprintMode;
  final int? maxHeartRate;
  final List<Track> library;
  final Map<String, SpinningPhase> phaseByTrackId = <String, SpinningPhase>{};
  final HeartRateSensorService heartRateSensor;

  Duration _offset = Duration.zero;
  DateTime? _runningSince;
  StreamSubscription<PlayerState>? _playerStateSub;
  Timer? _statsTimer;
  final DateTime startedAt = DateTime.now();
  final Set<String> _heardTrackIds = <String>{};
  final Map<String, Track> _heardTracks = <String, Track>{};
  final Map<int, int> _zoneSeconds = <int, int>{};
  int _heartRateSamples = 0;
  int _heartRateTotal = 0;
  int? _heartRateMax;
  bool _historySaved = false;
  bool completed = false;
  bool ended = false;

  SpinningSessionController({
    required this.player,
    required this.plan,
    required this.customProfile,
    required this.sprintMode,
    required this.maxHeartRate,
    required this.library,
    required this.heartRateSensor,
  }) {
    for (final selection in plan.selections) {
      phaseByTrackId[selection.track.id] = selection.phase;
    }

    if (player.audio.playing) {
      _runningSince = DateTime.now();
    }

    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ended || completed) return;
      if (elapsed >= plan.duration) {
        unawaited(complete());
        return;
      }
      if (_runningSince == null) return;

      final current = player.currentTrack;
      if (current != null) {
        _heardTrackIds.add(current.id);
        _heardTracks[current.id] = current;
      }

      final sensorState = heartRateSensor.state;
      final bpm = sensorState.bpm;
      final measuredAt = sensorState.measuredAt;
      final measurementIsFresh = measuredAt != null &&
          DateTime.now().difference(measuredAt) <= const Duration(seconds: 4);
      if (sensorState.status != HeartRateSensorStatus.connected ||
          bpm == null ||
          bpm <= 0 ||
          !measurementIsFresh) {
        return;
      }

      _heartRateSamples++;
      _heartRateTotal += bpm;
      if (_heartRateMax == null || bpm > _heartRateMax!) {
        _heartRateMax = bpm;
      }

      final zone = _zoneForHeartRate(bpm);
      if (zone != null) {
        _zoneSeconds[zone] = (_zoneSeconds[zone] ?? 0) + 1;
      }
    });

    _playerStateSub = player.playerStateStream.listen((state) {
      if (ended || completed) {
        _commitRunningTime();
        return;
      }

      if (state.playing) {
        if (_runningSince == null && elapsed < plan.duration) {
          _runningSince = DateTime.now();
        }
      } else {
        _commitRunningTime();
      }
    });
  }

  Duration get elapsed {
    var value = _offset;
    final runningSince = _runningSince;
    if (runningSince != null) {
      value += DateTime.now().difference(runningSince);
    }
    return value > plan.duration ? plan.duration : value;
  }

  bool get isRunning => _runningSince != null;

  void _commitRunningTime() {
    final runningSince = _runningSince;
    if (runningSince == null) return;
    _offset += DateTime.now().difference(runningSince);
    if (_offset > plan.duration) {
      _offset = plan.duration;
    }
    _runningSince = null;
  }

  SpinningPhase? phaseForTrack(Track track) => phaseByTrackId[track.id];

  void setTrackPhase(Track track, SpinningPhase phase) {
    phaseByTrackId[track.id] = phase;
  }

  void removeTrackPhase(Track track) {
    phaseByTrackId.remove(track.id);
  }

  int? _zoneForHeartRate(int bpm) {
    final max = maxHeartRate;
    if (max == null || max <= 0) return null;
    final percent = bpm / max * 100;
    if (percent < 60) return 1;
    if (percent < 70) return 2;
    if (percent < 80) return 3;
    if (percent < 90) return 4;
    return 5;
  }

  Future<void> _saveHistory({required bool wasCompleted}) async {
    if (_historySaved) return;
    final seconds = elapsed.inSeconds;
    if (seconds < 30) return;

    _historySaved = true;
    final average = _heartRateSamples == 0
        ? null
        : (_heartRateTotal / _heartRateSamples).round();

    final tracks = <SpinningHistoryTrack>[
      for (final id in _heardTrackIds)
        if (_heardTracks[id] case final track?)
          SpinningHistoryTrack(
            title: track.title,
            artist: track.artist,
          ),
    ];

    await SpinningSessionHistoryService().add(
      SpinningSessionHistoryEntry(
        id: startedAt.microsecondsSinceEpoch.toString(),
        startedAt: startedAt,
        durationSeconds: seconds,
        averageHeartRate: average,
        maxHeartRate: _heartRateMax,
        configuredMaxHeartRate: maxHeartRate,
        zoneSeconds: {
          for (var zone = 1; zone <= 5; zone++)
            zone: _zoneSeconds[zone] ?? 0,
        },
        tracks: tracks,
        completed: wasCompleted,
      ),
    );
  }

  void jumpTo(Duration position) {
    final clampedMs =
        position.inMilliseconds.clamp(0, plan.duration.inMilliseconds).toInt();
    final wasRunning = _runningSince != null;
    _runningSince = null;
    _offset = Duration(milliseconds: clampedMs);
    if (wasRunning && _offset < plan.duration && !ended && !completed) {
      _runningSince = DateTime.now();
    }
  }

  Future<void> complete() async {
    if (completed || ended) return;
    completed = true;
    _runningSince = null;
    _offset = plan.duration;
    await player.pause();
    await _saveHistory(wasCompleted: true);
  }

  Future<void> end() async {
    if (ended) return;
    ended = true;
    _commitRunningTime();
    await player.pause();
    await _saveHistory(wasCompleted: false);
  }

  Future<void> dispose() async {
    _commitRunningTime();
    _statsTimer?.cancel();
    await _playerStateSub?.cancel();
  }
}
