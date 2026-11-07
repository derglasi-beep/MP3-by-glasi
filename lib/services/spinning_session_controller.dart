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
  final Map<String, int> maxHeartRatePercentByTrackId;

  Duration _offset = Duration.zero;
  DateTime? _runningSince;
  late final List<Duration> _phaseBoundaries;
  int _nextBoundaryIndex = 0;
  StreamSubscription<PlayerState>? _playerStateSub;
  Timer? _statsTimer;
  final DateTime startedAt = DateTime.now();
  final Set<String> _heardTrackIds = <String>{};
  final Map<String, Track> _heardTracks = <String, Track>{};
  final Map<int, int> _zoneSeconds = <int, int>{};
  int _aboveTargetSeconds = 0;
  int _targetMeasuredSeconds = 0;
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
    Map<String, int> maxHeartRatePercentByTrackId = const {},
  }) : maxHeartRatePercentByTrackId =
           Map<String, int>.from(maxHeartRatePercentByTrackId) {
    for (final selection in plan.selections) {
      phaseByTrackId[selection.track.id] = selection.phase;
    }

    _phaseBoundaries = _buildPhaseBoundaries();
    player.onTrackCompleted = _onTrackCompleted;

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

      final max = maxHeartRate;
      if (max != null && max > 0) {
        final ceiling = current == null
            ? null
            : maxPercentForTrack(current);
        final phaseCeiling = _targetCeilingAt(elapsed);
        final effectiveCeiling = ceiling ?? phaseCeiling;
        if (effectiveCeiling != null) {
          _targetMeasuredSeconds++;
          if (bpm / max * 100 > effectiveCeiling) {
            _aboveTargetSeconds++;
          }
        }
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

  // Session time waits at each phase boundary until the playing song ends.
  // Only song completion advances the active boundary; the current song is
  // never cut off merely because the planned phase duration elapsed.
  Duration get _rawElapsed {
    var value = _offset;
    final since = _runningSince;
    if (since != null) value += DateTime.now().difference(since);
    return value > plan.duration ? plan.duration : value;
  }

  Duration get elapsed {
    final raw = _rawElapsed;
    if (_nextBoundaryIndex >= _phaseBoundaries.length) return raw;
    final boundary = _phaseBoundaries[_nextBoundaryIndex];
    if (raw < boundary) return raw;
    return boundary - const Duration(milliseconds: 1);
  }

  List<Duration> _buildPhaseBoundaries() {
    final boundaries = <Duration>[];
    var cursor = Duration.zero;
    final profile = customProfile;
    if (profile != null && profile.segments.isNotEmpty) {
      final durations = SpinningPlaylistService()
          .scaledCustomSegmentDurations(profile, plan.duration);
      for (final duration in durations) {
        cursor += duration;
        if (cursor > Duration.zero && cursor <= plan.duration) {
          boundaries.add(cursor);
        }
      }
    } else {
      for (final phase in const <SpinningPhase>[
        SpinningPhase.warmup,
        SpinningPhase.build,
        SpinningPhase.load,
        SpinningPhase.peak,
        SpinningPhase.cooldown,
      ]) {
        cursor += plan.phaseDurations[phase] ?? Duration.zero;
        if (cursor > Duration.zero && cursor <= plan.duration) {
          boundaries.add(cursor);
        }
      }
    }
    if (boundaries.isEmpty || boundaries.last != plan.duration) {
      boundaries.add(plan.duration);
    }
    return boundaries.toSet().toList()..sort();
  }

  int? _onTrackCompleted(int previousIndex) {
    if (completed || ended) return null;
    if (_nextBoundaryIndex >= _phaseBoundaries.length ||
        _rawElapsed < _phaseBoundaries[_nextBoundaryIndex]) {
      return null;
    }

    final boundary = _phaseBoundaries[_nextBoundaryIndex];
    _nextBoundaryIndex++;
    _offset = boundary;
    _runningSince = player.audio.playing ? DateTime.now() : null;

    // Reaching the planned session end also waits for the final song.
    if (boundary >= plan.duration) {
      unawaited(complete());
      return -1;
    }

    final phase = _phaseAt(boundary);
    if (phase == null) return null;
    for (var index = previousIndex + 1; index < player.queue.length; index++) {
      if (phaseForTrack(player.queue[index]) == phase) return index;
    }
    // No suitable upcoming track: preserve normal playback rather than
    // jumping backwards or repeating an earlier title.
    return null;
  }

  SpinningPhase? _phaseAt(Duration position) {
    final profile = customProfile;
    if (profile != null && profile.segments.isNotEmpty) {
      final durations = SpinningPlaylistService()
          .scaledCustomSegmentDurations(profile, plan.duration);
      var cursor = Duration.zero;
      for (var index = 0; index < durations.length; index++) {
        cursor += durations[index];
        if (position < cursor && index < profile.segments.length) {
          return profile.segments[index].phase;
        }
      }
      return null;
    }
    var cursor = Duration.zero;
    for (final phase in const <SpinningPhase>[
      SpinningPhase.warmup,
      SpinningPhase.build,
      SpinningPhase.load,
      SpinningPhase.peak,
      SpinningPhase.cooldown,
    ]) {
      cursor += plan.phaseDurations[phase] ?? Duration.zero;
      if (position < cursor) return phase;
    }
    return null;
  }

  bool get isRunning => _runningSince != null;

  bool get waitingForSongEnd =>
      !completed &&
      !ended &&
      _runningSince != null &&
      _nextBoundaryIndex < _phaseBoundaries.length &&
      _rawElapsed >= _phaseBoundaries[_nextBoundaryIndex];

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

  int? maxPercentForTrack(Track? track) =>
      track == null ? null : maxHeartRatePercentByTrackId[track.id];

  void setTrackMaxPercent(Track track, int? percent) {
    if (percent == null) {
      maxHeartRatePercentByTrackId.remove(track.id);
    } else {
      maxHeartRatePercentByTrackId[track.id] = percent;
    }
  }

  void setTrackPhase(Track track, SpinningPhase phase) {
    phaseByTrackId[track.id] = phase;
  }

  void removeTrackPhase(Track track) {
    phaseByTrackId.remove(track.id);
  }

  int? _targetCeilingAt(Duration position) {
    final profile = customProfile;
    if (profile != null && profile.segments.isNotEmpty) {
      final durations = SpinningPlaylistService()
          .scaledCustomSegmentDurations(profile, plan.duration);
      var cursor = Duration.zero;
      for (var index = 0;
          index < durations.length && index < profile.segments.length;
          index++) {
        cursor += durations[index];
        if (position < cursor || index == durations.length - 1) {
          final segment = profile.segments[index];
          if (segment.maxHeartRatePercent != null) {
            return segment.maxHeartRatePercent;
          }
          return _standardPhaseCeiling(segment.phase);
        }
      }
    }
    final phase = _phaseAt(position);
    return phase == null ? null : _standardPhaseCeiling(phase);
  }

  int _standardPhaseCeiling(SpinningPhase phase) => switch (phase) {
        SpinningPhase.warmup => 69,
        SpinningPhase.build => 70,
        SpinningPhase.load => 80,
        SpinningPhase.peak => 90,
        SpinningPhase.cooldown => 65,
      };

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
        aboveTargetSeconds: _aboveTargetSeconds,
        targetMeasuredSeconds: _targetMeasuredSeconds,
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
    _nextBoundaryIndex = _phaseBoundaries.indexWhere(
      (boundary) => boundary > _offset,
    );
    if (_nextBoundaryIndex < 0) {
      _nextBoundaryIndex = _phaseBoundaries.length;
    }
    if (wasRunning && _offset < plan.duration && !ended && !completed) {
      _runningSince = DateTime.now();
    }
  }

  Future<void> complete() async {
    if (completed || ended) return;
    completed = true;
    if (player.onTrackCompleted == _onTrackCompleted) {
      player.onTrackCompleted = null;
    }
    _runningSince = null;
    _offset = plan.duration;
    await player.pause();
    await _saveHistory(wasCompleted: true);
  }

  Future<void> end() async {
    if (ended) return;
    ended = true;
    if (player.onTrackCompleted == _onTrackCompleted) {
      player.onTrackCompleted = null;
    }
    _commitRunningTime();
    await player.pause();
    await _saveHistory(wasCompleted: false);
  }

  Future<void> dispose() async {
    if (player.onTrackCompleted == _onTrackCompleted) {
      player.onTrackCompleted = null;
    }
    _commitRunningTime();
    _statsTimer?.cancel();
    await _playerStateSub?.cancel();
  }
}
