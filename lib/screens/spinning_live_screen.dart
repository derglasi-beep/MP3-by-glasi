import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
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

  Duration _planningDuration(Track track) {
    final value = track.duration;
    if (value == null || value <= Duration.zero) {
      return const Duration(minutes: 4);
    }
    if (value > const Duration(minutes: 15)) {
      return const Duration(minutes: 5);
    }
    return value;
  }

  Duration _sessionElapsed(Duration trackPosition) {
    var index = widget.player.currentIndex;
    if (index < 0 || index >= widget.plan.tracks.length) {
      final currentId = widget.player.currentTrack?.id;
      index = currentId == null
          ? 0
          : widget.plan.tracks.indexWhere((track) => track.id == currentId);
      if (index < 0) index = 0;
    }

    var elapsed = Duration.zero;
    for (var i = 0; i < index && i < widget.plan.tracks.length; i++) {
      elapsed += _planningDuration(widget.plan.tracks[i]);
    }
    elapsed += trackPosition;

    if (elapsed > widget.plan.duration) return widget.plan.duration;
    return elapsed;
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

  Duration _phaseRemaining(Duration elapsed, SpinningPhase phase) {
    for (final point in widget.plan.curve) {
      if (point.position <= elapsed) continue;
      if (point.phase != phase) {
        final remaining = point.position - elapsed;
        return remaining > Duration.zero ? remaining : Duration.zero;
      }
    }
    final remaining = widget.plan.duration - elapsed;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  SpinningPhase? _nextPhase(Duration elapsed, SpinningPhase current) {
    for (final point in widget.plan.curve) {
      if (point.position <= elapsed) continue;
      if (point.phase != current) return point.phase;
    }
    return null;
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
        child: StreamBuilder<Duration>(
          stream: widget.player.positionStream,
          initialData: widget.player.audio.position,
          builder: (context, positionSnapshot) {
            final elapsed = _sessionElapsed(
              positionSnapshot.data ?? Duration.zero,
            );
            final point = _pointAt(elapsed);
            final currentPhase = point?.phase ?? SpinningPhase.warmup;
            final custom = _customSegmentAt(elapsed);
            final phaseRemaining = custom?.remaining ??
                _phaseRemaining(elapsed, currentPhase);
            final nextPhase = _nextPhase(elapsed, currentPhase);
            final progress = widget.plan.duration.inMilliseconds <= 0
                ? 0.0
                : (elapsed.inMilliseconds /
                        widget.plan.duration.inMilliseconds)
                    .clamp(0.0, 1.0);
            final currentTrack = widget.player.currentTrack;
            final hfText = custom == null
                ? _standardHeartRate(currentPhase)
                : _customHeartRate(custom.segment);
            final phaseTitle =
                custom?.segment.label ?? _phaseLabel(currentPhase);
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
                          phaseTitle,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'noch ${_clock(phaseRemaining)}',
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
                  child: ListTile(
                    leading: const Icon(Icons.skip_next),
                    title: const Text('Als Nächstes'),
                    subtitle: Text(
                      nextPhase == null
                          ? 'Sessionende'
                          : _phaseLabel(nextPhase),
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
