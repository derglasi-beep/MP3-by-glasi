import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'audio_player_service.dart';
import 'heart_rate_sensor_service.dart';
import 'spinning_playlist_service.dart';
import 'spinning_session_history_service.dart';

typedef SpinningPhaseWindow = ({
  SpinningPhase phase,
  String label,
  Duration start,
  Duration end,
  SpinningPhase? nextPhase,
});

class SpinningSessionController {
  final AudioPlayerService player;
  final SpinningPlan plan;
  final CustomBpmProfile? customProfile;
  final bool sprintMode;
  final SpinningTrainingProfile trainingProfile;
  final int? maxHeartRate;
  final List<Track> library;
  final Map<String, SpinningPhase> phaseByTrackId = <String, SpinningPhase>{};
  final HeartRateSensorService heartRateSensor;
  final Map<String, int> maxHeartRatePercentByTrackId;

  Duration _offset = Duration.zero;
  DateTime? _runningSince;
  late final List<SpinningPhaseWindow> _phaseWindows;
  int _activeWindowIndex = 0;
  Duration _phaseStartedAtElapsed = Duration.zero;
  StreamSubscription<Track?>? _trackSub;
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
  late final bool _previousShuffle;
  late final LoopMode _previousLoopMode;
  bool _historySaved = false;
  bool completed = false;
  bool ended = false;

  SpinningSessionController({
    required this.player,
    required this.plan,
    required this.customProfile,
    required this.sprintMode,
    this.trainingProfile = SpinningTrainingProfile.cadence,
    required this.maxHeartRate,
    required this.library,
    required this.heartRateSensor,
    Map<String, int> maxHeartRatePercentByTrackId = const {},
  }) : maxHeartRatePercentByTrackId =
           Map<String, int>.from(maxHeartRatePercentByTrackId) {
    for (final selection in plan.selections) {
      phaseByTrackId[selection.track.id] = selection.phase;
    }

    _phaseWindows = phaseWindowsFor(plan, customProfile);
    _previousShuffle = player.shuffle;
    _previousLoopMode = player.loopMode;
    player.shuffle = false;
    player.loopMode = LoopMode.off;
    player.onTrackCompleted = _onTrackCompleted;
    _trackSub = player.currentTrackStream.listen((_) {
      _syncWindowToCurrentTrack();
    });
    _syncWindowToCurrentTrack();

    if (player.audio.playing) {
      _runningSince = DateTime.now();
    }

    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ended || completed) return;
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

  // The music clock tracks real playback time, including any song overrun.
  // Phase changes happen only when the next tagged song starts.
  Duration get elapsed {
    final since = _runningSince;
    return since == null
        ? _offset
        : _offset + DateTime.now().difference(since);
  }

  static List<SpinningPhaseWindow> phaseWindowsFor(
    SpinningPlan plan,
    CustomBpmProfile? customProfile,
  ) {
    final segments = <({SpinningPhase phase, Duration start, Duration end, String label})>[];
    final custom = customProfile;
    if (custom != null && custom.segments.isNotEmpty) {
      final times = SpinningPlaylistService()
          .scaledCustomSegmentDurations(custom, plan.duration);
      var cursor = Duration.zero;
      for (var i = 0; i < times.length && i < custom.segments.length; i++) {
        final segment = custom.segments[i];
        final end = cursor + times[i];
        if (end > cursor) {
          segments.add((
            phase: segment.phase,
            label: segment.label,
            start: cursor,
            end: end,
          ));
        }
        cursor = end;
      }
    } else if (plan.curve.isNotEmpty) {
      var start = Duration.zero;
      var phase = plan.curve.first.phase;
      for (final point in plan.curve) {
        if (point.phase == phase) continue;
        if (point.position > start) {
          segments.add((
            phase: phase,
            label: _phaseLabel(phase),
            start: start,
            end: point.position,
          ));
        }
        start = point.position;
        phase = point.phase;
      }
      if (start < plan.duration) {
        segments.add((
          phase: phase,
          label: _phaseLabel(phase),
          start: start,
          end: plan.duration,
        ));
      }
    } else {
      var cursor = Duration.zero;
      for (final phase in const <SpinningPhase>[
        SpinningPhase.warmup,
        SpinningPhase.build,
        SpinningPhase.load,
        SpinningPhase.peak,
        SpinningPhase.cooldown,
      ]) {
        final end = cursor + (plan.phaseDurations[phase] ?? Duration.zero);
        if (end > cursor) {
          segments.add((
            phase: phase,
            label: _phaseLabel(phase),
            start: cursor,
            end: end,
          ));
        }
        cursor = end;
      }
    }

    return [
      for (var i = 0; i < segments.length; i++)
        (
          phase: segments[i].phase,
          label: segments[i].label,
          start: segments[i].start,
          end: segments[i].end,
          nextPhase: i + 1 < segments.length
              ? segments[i + 1].phase
              : null,
        ),
    ];
  }

  static String _phaseLabel(SpinningPhase phase) => switch (phase) {
        SpinningPhase.warmup => 'Warm-up',
        SpinningPhase.build => 'Aufbau',
        SpinningPhase.load => 'Belastung',
        SpinningPhase.peak => 'Peak',
        SpinningPhase.cooldown => 'Cool-down',
      };

  void _syncWindowToCurrentTrack() {
    if (_phaseWindows.isEmpty) return;
    var windowIndex = 0;
    SpinningPhase? lastPhase;
    final through = player.currentIndex;
    for (var i = 0; i <= through && i < player.queue.length; i++) {
      final phase = phaseForTrack(player.queue[i]);
      if (phase == null || phase == lastPhase) continue;
      lastPhase = phase;
      var found = -1;
      for (var j = windowIndex; j < _phaseWindows.length; j++) {
        if (_phaseWindows[j].phase == phase) {
          found = j;
          break;
        }
      }
      if (found >= 0) windowIndex = found;
    }
    final previousPhase = _phaseWindows[_activeWindowIndex].phase;
    final current = player.currentTrack;
    final currentPhase =
        current == null ? null : phaseForTrack(current);
    if (windowIndex != _activeWindowIndex ||
        (currentPhase != null && currentPhase != previousPhase)) {
      _phaseStartedAtElapsed = elapsed;
    }
    _activeWindowIndex = windowIndex;
  }

  SpinningPhaseWindow get currentPhaseWindow {
    if (_phaseWindows.isEmpty) {
      return (
        phase: SpinningPhase.warmup,
        label: 'Warm-up',
        start: Duration.zero,
        end: plan.duration,
        nextPhase: null,
      );
    }
    final window = _phaseWindows[_activeWindowIndex];
    final currentIndex = player.currentIndex;
    SpinningPhase? next;
    final currentTrack = player.currentTrack;
    final activePhase =
        currentTrack == null ? null : phaseForTrack(currentTrack);
    for (var i = currentIndex + 1; i < player.queue.length; i++) {
      final phase = phaseForTrack(player.queue[i]);
      if (phase != null && phase != activePhase) {
        next = phase;
        break;
      }
    }
    return (
      phase: activePhase ?? window.phase,
      label: activePhase == null
          ? window.label
          : trainingProfile == SpinningTrainingProfile.interval &&
                  customProfile == null
              ? switch (activePhase) {
                  SpinningPhase.build => 'Aktive Erholung',
                  SpinningPhase.peak => 'Schnelles Intervall',
                  SpinningPhase.load => 'Bergfahrt',
                  _ => _phaseLabel(activePhase),
                }
              : _phaseLabel(activePhase),
      start: window.start,
      end: window.end,
      nextPhase: next,
    );
  }

  // A natural ending (and a manual Next command) always advances to the
  // immediate successor. No phase searching, skipping, shuffle or repeat.
  int? _onTrackCompleted(int previousIndex) {
    if (completed || ended) return -1;
    if (previousIndex >= player.queue.length - 1) {
      unawaited(complete());
      return -1;
    }
    _commitRunningTime(); // Preserve elapsed song overrun.
    return previousIndex + 1;
  }

  bool get isRunning => _runningSince != null;

  Duration get phaseRemaining {
    final window = currentPhaseWindow;
    final duration = window.end - window.start;
    final spent = elapsed - _phaseStartedAtElapsed;
    return duration > spent ? duration - spent : Duration.zero;
  }

  bool get waitingForSongEnd =>
      !completed &&
      !ended &&
      isRunning &&
      currentPhaseWindow.nextPhase != null &&
      phaseRemaining == Duration.zero;

  void _commitRunningTime() {
    final runningSince = _runningSince;
    if (runningSince == null) return;
    _offset += DateTime.now().difference(runningSince);
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
    if (profile != null &&
        _activeWindowIndex < profile.segments.length) {
      final segment = profile.segments[_activeWindowIndex];
      return segment.maxHeartRatePercent ??
          _standardPhaseCeiling(segment.phase);
    }
    return _standardPhaseCeiling(currentPhaseWindow.phase);
  }

  int _standardPhaseCeiling(SpinningPhase phase) =>
      SpinningPlaylistService.heartRateRange(trainingProfile, phase).max;

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
    final wasRunning = isRunning;
    _runningSince = null;
    // Never make real elapsed time jump backwards on a manual phase skip.
    if (position > _offset) _offset = position;
    _syncWindowToCurrentTrack();
    if (wasRunning && !ended && !completed) {
      _runningSince = DateTime.now();
    }
  }

  void _releasePlayerControl() {
    if (player.onTrackCompleted == _onTrackCompleted) {
      player.onTrackCompleted = null;
      player.shuffle = _previousShuffle;
      player.loopMode = _previousLoopMode;
    }
  }

  Future<void> complete() async {
    if (completed || ended) return;
    _commitRunningTime();
    completed = true;
    _releasePlayerControl();
    await player.pause();
    await _saveHistory(wasCompleted: true);
  }

  Future<void> end() async {
    if (ended) return;
    ended = true;
    _releasePlayerControl();
    _commitRunningTime();
    await player.pause();
    await _saveHistory(wasCompleted: false);
  }

  Future<void> dispose() async {
    _releasePlayerControl();
    _commitRunningTime();
    _statsTimer?.cancel();
    await _playerStateSub?.cancel();
    await _trackSub?.cancel();
  }
}
