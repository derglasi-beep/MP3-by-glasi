import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/audio_player_service.dart';
import '../services/spinning_playlist_service.dart';

class SpinningLiveScreen extends StatefulWidget {
  final AudioPlayerService player;
  final SpinningPlan plan;
  final CustomBpmProfile? customProfile;
  final bool sprintMode;

  const SpinningLiveScreen({
    super.key,
    required this.player,
    required this.plan,
    required this.customProfile,
    required this.sprintMode,
  });

  @override
  State<SpinningLiveScreen> createState() => _SpinningLiveScreenState();
}

class _SpinningLiveScreenState extends State<SpinningLiveScreen> {
  final SpinningPlaylistService planner = SpinningPlaylistService();
  final Stopwatch _sessionWatch = Stopwatch();
  Duration _sessionOffset = Duration.zero;
  Timer? _ticker;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<dynamic>? _trackSub;
  bool _sessionCompleted = false;

  @override
  void initState() {
    super.initState();

    if (widget.player.audio.playing) {
      _sessionWatch.start();
    }

    _playerStateSub = widget.player.playerStateStream.listen((state) {
      if (state.playing) {
        if (!_sessionWatch.isRunning &&
            _sessionElapsed < widget.plan.duration) {
          _sessionWatch.start();
        }
      } else {
        _sessionWatch.stop();
      }
      if (mounted) setState(() {});
    });

    _trackSub = widget.player.currentTrackStream.listen((_) {
      if (mounted) setState(() {});
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      if (_sessionElapsed >= widget.plan.duration) {
        _sessionWatch.stop();
        if (!_sessionCompleted) {
          _sessionCompleted = true;
          await widget.player.pause();
        }
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _playerStateSub?.cancel();
    _trackSub?.cancel();
    super.dispose();
  }

  Duration get _sessionElapsed {
    final elapsed = _sessionOffset + _sessionWatch.elapsed;
    return elapsed > widget.plan.duration ? widget.plan.duration : elapsed;
  }

  ({
    SpinningPhase phase,
    String label,
    Duration start,
    Duration end,
    SpinningPhase? nextPhase,
  }) _phaseWindowAt(Duration elapsed) {
    final custom = widget.customProfile;
    if (custom != null) {
      final durations =
          planner.scaledCustomSegmentDurations(custom, widget.plan.duration);
      if (durations.length == custom.segments.length) {
        var cursor = Duration.zero;
        for (var i = 0; i < custom.segments.length; i++) {
          final segment = custom.segments[i];
          final end = cursor + durations[i];
          if (elapsed < end || i == custom.segments.length - 1) {
            return (
              phase: segment.phase,
              label: segment.label,
              start: cursor,
              end: end,
              nextPhase: i + 1 < custom.segments.length
                  ? custom.segments[i + 1].phase
                  : null,
            );
          }
          cursor = end;
        }
      }
    }

    const order = <SpinningPhase>[
      SpinningPhase.warmup,
      SpinningPhase.build,
      SpinningPhase.load,
      SpinningPhase.peak,
      SpinningPhase.cooldown,
    ];
    var cursor = Duration.zero;
    for (var i = 0; i < order.length; i++) {
      final phase = order[i];
      final phaseDuration =
          widget.plan.phaseDurations[phase] ?? Duration.zero;
      if (phaseDuration <= Duration.zero) continue;
      final end = cursor + phaseDuration;
      if (elapsed < end || i == order.length - 1) {
        SpinningPhase? next;
        for (var j = i + 1; j < order.length; j++) {
          if ((widget.plan.phaseDurations[order[j]] ?? Duration.zero) >
              Duration.zero) {
            next = order[j];
            break;
          }
        }
        return (
          phase: phase,
          label: _phaseLabel(phase),
          start: cursor,
          end: end,
          nextPhase: next,
        );
      }
      cursor = end;
    }

    return (
      phase: SpinningPhase.cooldown,
      label: _phaseLabel(SpinningPhase.cooldown),
      start: widget.plan.duration,
      end: widget.plan.duration,
      nextPhase: null,
    );
  }

  Duration? _nextPhaseStart(Duration elapsed) {
    final current = _phaseWindowAt(elapsed);
    if (current.nextPhase == null) return null;
    return current.end;
  }

  Future<void> _startNextPhase() async {
    final elapsed = _sessionElapsed;
    final current = _phaseWindowAt(elapsed);
    final targetPosition = _nextPhaseStart(elapsed);
    final targetPhase = current.nextPhase;
    if (targetPosition == null || targetPhase == null) return;

    final wasRunning = _sessionWatch.isRunning;
    _sessionWatch
      ..stop()
      ..reset();
    _sessionOffset = targetPosition;
    if (wasRunning) _sessionWatch.start();

    var targetIndex = -1;
    final currentIndex = widget.player.currentIndex;
    for (var i = 0; i < widget.plan.selections.length; i++) {
      final selection = widget.plan.selections[i];
      if (selection.phase != targetPhase) continue;
      if (i > currentIndex) {
        targetIndex = i;
        break;
      }
      if (targetIndex < 0) targetIndex = i;
    }

    if (targetIndex >= 0 && targetIndex < widget.plan.tracks.length) {
      await widget.player.playAt(targetIndex);
    }

    if (mounted) setState(() {});
  }

  Future<void> _endSession() async {
    _sessionWatch.stop();
    await widget.player.pause();
    if (mounted) Navigator.of(context).pop();
  }

  SpinningCurvePoint? _pointAt(Duration elapsed) {
    if (widget.plan.curve.isEmpty) return null;

    var current = widget.plan.curve.first;
    for (final point in widget.plan.curve) {
      if (point.position > elapsed) break;
      current = point;
    }
    return current;
  }

  ({CustomBpmSegment segment, Duration remaining})? _customSegmentAt(
    Duration elapsed,
  ) {
    final profile = widget.customProfile;
    if (profile == null) return null;

    final durations =
        planner.scaledCustomSegmentDurations(profile, widget.plan.duration);
    if (durations.length != profile.segments.length) return null;

    var cursor = Duration.zero;
    for (var i = 0; i < profile.segments.length; i++) {
      final end = cursor + durations[i];
      if (elapsed < end || i == profile.segments.length - 1) {
        final remaining = end - elapsed;
        return (
          segment: profile.segments[i],
          remaining: remaining > Duration.zero ? remaining : Duration.zero,
        );
      }
      cursor = end;
    }
    return null;
  }

  String _phaseLabel(SpinningPhase phase) => switch (phase) {
        SpinningPhase.warmup => 'Warm-up',
        SpinningPhase.build => 'Aufbau',
        SpinningPhase.load => 'Belastung',
        SpinningPhase.peak => 'Peak',
        SpinningPhase.cooldown => 'Cool-down',
      };

  String _standardHeartRate(SpinningPhase phase) => switch (phase) {
        SpinningPhase.warmup => '65–69 % HFmax',
        SpinningPhase.build => '60–70 % HFmax',
        SpinningPhase.load => '70–80 % HFmax',
        SpinningPhase.peak => '80–90 % HFmax',
        SpinningPhase.cooldown => '65→60 % HFmax',
      };

  String _customHeartRate(CustomBpmSegment segment) {
    final min = segment.minHeartRatePercent;
    final max = segment.maxHeartRatePercent;
    if (min == null || max == null) return 'keine HF-Vorgabe';

    if (segment.phase == SpinningPhase.cooldown) {
      return '$max→$min % HFmax';
    }
    return '$min–$max % HFmax';
  }

  double _displayBpm(double bpm) => widget.sprintMode ? bpm : bpm / 2;

  String _clock(Duration value) {
    final totalSeconds = value.inSeconds < 0 ? 0 : value.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spinning Live'),
      ),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            final elapsed = _sessionElapsed;
            final point = _pointAt(elapsed);
            final phaseWindow = _phaseWindowAt(elapsed);
            final currentPhase = phaseWindow.phase;
            final custom = _customSegmentAt(elapsed);
            final phaseRemaining = phaseWindow.end - elapsed > Duration.zero
                ? phaseWindow.end - elapsed
                : Duration.zero;
            final nextPhase = phaseWindow.nextPhase;
            final progress = widget.plan.duration.inMilliseconds <= 0
                ? 0.0
                : (elapsed.inMilliseconds /
                        widget.plan.duration.inMilliseconds)
                    .clamp(0.0, 1.0);
            final currentTrack = widget.player.currentTrack;
            final hfText = custom == null
                ? _standardHeartRate(currentPhase)
                : _customHeartRate(custom.segment);
            final phaseTitle = phaseWindow.label;
            final targetBpm = point == null
                ? null
                : _displayBpm(point.targetBpm).round();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          _sessionCompleted ? 'Session beendet' : phaseTitle,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _sessionCompleted
                              ? 'Training abgeschlossen'
                              : 'noch ${_clock(phaseRemaining)}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 18),
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 8),
                        Text(
                          '${_clock(elapsed)} / ${_clock(widget.plan.duration)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Expanded(
                          child: _LiveValue(
                            icon: Icons.speed,
                            label: 'Ziel',
                            value: targetBpm == null
                                ? '—'
                                : '$targetBpm BPM',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _LiveValue(
                            icon: Icons.favorite_outline,
                            label: 'Herzfrequenz',
                            value: hfText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.music_note),
                    title: Text(
                      currentTrack?.title ?? 'Kein Titel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      currentTrack?.artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: currentTrack?.bpm == null
                        ? null
                        : Text(
                            '${_displayBpm(currentTrack!.bpm!).round()} BPM',
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.flag_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            nextPhase == null
                                ? 'Sessionende'
                                : 'Als Nächstes: ${_phaseLabel(nextPhase)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _sessionCompleted || nextPhase == null
                              ? null
                              : _startNextPhase,
                          icon: const Icon(Icons.skip_next),
                          label: const Text('Phase starten'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                StreamBuilder<PlayerState>(
                  stream: widget.player.playerStateStream,
                  initialData: widget.player.audio.playerState,
                  builder: (context, stateSnapshot) {
                    final playing = stateSnapshot.data?.playing ??
                        widget.player.audio.playing;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          onPressed: widget.player.previous,
                          icon: const Icon(Icons.skip_previous),
                          tooltip: 'Vorheriger Titel',
                        ),
                        const SizedBox(width: 16),
                        IconButton.filled(
                          onPressed:
                              playing ? widget.player.pause : widget.player.play,
                          icon: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                          ),
                          iconSize: 34,
                          tooltip: playing ? 'Pause' : 'Weiter',
                        ),
                        const SizedBox(width: 16),
                        IconButton.filledTonal(
                          onPressed: widget.player.next,
                          icon: const Icon(Icons.skip_next),
                          tooltip: 'Nächster Titel',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _endSession,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(
                    _sessionCompleted ? 'Zur Planung zurück' : 'Session beenden',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LiveValue extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _LiveValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      );
}
