import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:universal_ble/universal_ble.dart';

import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/heart_rate_sensor_service.dart';
import '../services/spinning_playlist_service.dart';
import '../services/spinning_session_controller.dart';

class SpinningLiveScreen extends StatefulWidget {
  final SpinningSessionController session;
  final VoidCallback onSessionEnded;

  const SpinningLiveScreen({
    super.key,
    required this.session,
    required this.onSessionEnded,
  });

  AudioPlayerService get player => session.player;
  SpinningPlan get plan => session.plan;
  CustomBpmProfile? get customProfile => session.customProfile;
  bool get sprintMode => session.sprintMode;

  @override
  State<SpinningLiveScreen> createState() => _SpinningLiveScreenState();
}

class _SpinningLiveScreenState extends State<SpinningLiveScreen> {
  final SpinningPlaylistService planner = SpinningPlaylistService();
  Timer? _ticker;
  StreamSubscription<dynamic>? _trackSub;

  @override
  void initState() {
    super.initState();

    _trackSub = widget.player.currentTrackStream.listen((_) {
      if (mounted) setState(() {});
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      if (_sessionElapsed >= widget.plan.duration &&
          !widget.session.completed) {
        await widget.session.complete();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _trackSub?.cancel();
    super.dispose();
  }

  Duration get _sessionElapsed => widget.session.elapsed;

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

    widget.session.jumpTo(targetPosition);

    var targetQueueIndex = -1;
    final currentIndex = widget.player.currentIndex;
    for (var i = 0; i < widget.player.queue.length; i++) {
      final track = widget.player.queue[i];
      if (widget.session.phaseForTrack(track) != targetPhase) continue;
      if (i > currentIndex) {
        targetQueueIndex = i;
        break;
      }
      if (targetQueueIndex < 0) targetQueueIndex = i;
    }

    if (targetQueueIndex >= 0 &&
        targetQueueIndex < widget.player.queue.length) {
      await widget.player.playAt(targetQueueIndex);
    }

    if (mounted) setState(() {});
  }

  Future<void> _endSession() async {
    await widget.session.end();
    widget.onSessionEnded();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _addTrackToSession() async {
    final searchController = TextEditingController();
    var selectedPhase = _phaseWindowAt(_sessionElapsed).phase;

    final result = await showDialog<({Track track, SpinningPhase phase})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = searchController.text.trim().toLowerCase();
          final queuedIds = widget.player.queue.map((track) => track.id).toSet();
          final matches = widget.session.library.where((track) {
            if (queuedIds.contains(track.id)) return false;
            if (query.isEmpty) return true;
            return track.title.toLowerCase().contains(query) ||
                track.artist.toLowerCase().contains(query) ||
                track.album.toLowerCase().contains(query);
          }).take(250).toList(growable: false);

          return AlertDialog(
            title: const Text('Titel zur Session hinzufügen'),
            content: SizedBox(
              width: 660,
              height: 560,
              child: Column(
                children: [
                  DropdownButtonFormField<SpinningPhase>(
                    initialValue: selectedPhase,
                    decoration: const InputDecoration(
                      labelText: 'Für Phase einfügen',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final phase in SpinningPhase.values)
                        DropdownMenuItem(
                          value: phase,
                          child: Text(_phaseLabel(phase)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedPhase = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Titel, Interpret oder Album',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(
                            child: Text('Keine passenden Titel gefunden.'),
                          )
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (_, index) {
                              final track = matches[index];
                              return ListTile(
                                leading: const Icon(Icons.add_circle_outline),
                                title: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: track.bpm == null
                                    ? null
                                    : Text(
                                        '${_displayBpm(track.bpm!).round()} BPM',
                                      ),
                                onTap: () => Navigator.pop(
                                  dialogContext,
                                  (track: track, phase: selectedPhase),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Abbrechen'),
              ),
            ],
          );
        },
      ),
    );

    searchController.dispose();
    if (result == null) return;

    final track = result.track;
    final phase = result.phase;
    widget.session.setTrackPhase(track, phase);

    await widget.player.addTracksToQueue([track]);

    var insertAfter = widget.player.currentIndex;
    for (var i = 0; i < widget.player.queue.length - 1; i++) {
      final queued = widget.player.queue[i];
      if (widget.session.phaseForTrack(queued) == phase) {
        insertAfter = i;
      }
    }

    final addedIndex =
        widget.player.queue.indexWhere((item) => item.id == track.id);
    final targetIndex = (insertAfter + 1)
        .clamp(
          widget.player.currentIndex + 1,
          widget.player.queue.length - 1,
        )
        .toInt();

    if (addedIndex >= 0 && addedIndex != targetIndex) {
      await widget.player.move(addedIndex, targetIndex);
    }

    if (mounted) setState(() {});
  }

  Future<void> _removeTrackFromSession(int index) async {
    if (index < 0 || index >= widget.player.queue.length) return;
    final track = widget.player.queue[index];
    widget.session.removeTrackPhase(track);
    await widget.player.removeAt(index);
    if (mounted) setState(() {});
  }

  Future<void> _moveTrack(int index, int delta) async {
    final target = index + delta;
    if (index < 0 ||
        index >= widget.player.queue.length ||
        target < 0 ||
        target >= widget.player.queue.length) {
      return;
    }

    // AudioPlayerService.move uses ReorderableList-style destination indices:
    // moving down needs one extra slot because the source is removed first.
    final destination = delta > 0 ? target + 1 : target;
    await widget.player.move(index, destination);
    if (mounted) setState(() {});
  }

  Future<void> _openHeartRateSensorDialog() async {
    final sensor = widget.session.heartRateSensor;
    await sensor.startScan();
    if (!mounted) return;

    final selected = await showDialog<BleDevice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Herzfrequenz-Sensor'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: StreamBuilder<List<BleDevice>>(
            stream: sensor.devicesStream,
            initialData: sensor.devices,
            builder: (context, snapshot) {
              final devices = snapshot.data ?? const <BleDevice>[];
              if (devices.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text(
                        'Suche nach BLE-Herzfrequenz-Sensoren …',
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Brustgurt ggf. anlegen oder Sensor aktivieren.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: devices.length,
                itemBuilder: (_, index) {
                  final device = devices[index];
                  final name = device.name?.trim();
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(
                      name == null || name.isEmpty ? 'HF-Sensor' : name,
                    ),
                    subtitle: Text(device.deviceId),
                    trailing: device.rssi == null
                        ? null
                        : Text('${device.rssi} dBm'),
                    onTap: () => Navigator.pop(dialogContext, device),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );

    await sensor.stopScan();
    if (selected == null) return;

    await sensor.connect(selected);
    if (mounted) setState(() {});
  }

  ({int min, int max}) _heartRateRange(
    SpinningPhase phase,
    CustomBpmSegment? custom,
  ) {
    if (custom != null &&
        custom.minHeartRatePercent != null &&
        custom.maxHeartRatePercent != null) {
      return (
        min: custom.minHeartRatePercent!,
        max: custom.maxHeartRatePercent!,
      );
    }

    return switch (phase) {
      SpinningPhase.warmup => (min: 65, max: 69),
      SpinningPhase.build => (min: 60, max: 70),
      SpinningPhase.load => (min: 70, max: 80),
      SpinningPhase.peak => (min: 80, max: 90),
      SpinningPhase.cooldown => (min: 60, max: 65),
    };
  }

  int? _heartRateZoneForBpm(int bpm) {
    final maxHeartRate = widget.session.maxHeartRate;
    if (maxHeartRate == null || maxHeartRate <= 0) return null;
    final percent = bpm / maxHeartRate * 100;
    if (percent < 60) return 1;
    if (percent < 70) return 2;
    if (percent < 80) return 3;
    if (percent < 90) return 4;
    return 5;
  }

  ({
    String label,
    String detail,
    IconData icon,
    Color color,
  }) _heartRateFeedback(
    BuildContext context,
    int bpm,
    ({int min, int max}) targetPercent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeartRate = widget.session.maxHeartRate;
    if (maxHeartRate == null || maxHeartRate <= 0) {
      return (
        label: 'Live-Puls',
        detail:
            'Ziel ${targetPercent.min}–${targetPercent.max} % HFmax · HFmax nicht gesetzt',
        icon: Icons.favorite,
        color: scheme.primary,
      );
    }

    final minBpm = (maxHeartRate * targetPercent.min / 100).round();
    final maxBpm = (maxHeartRate * targetPercent.max / 100).round();
    if (bpm < minBpm) {
      return (
        label: 'Unter Ziel',
        detail: 'Ziel $minBpm–$maxBpm bpm',
        icon: Icons.south,
        color: scheme.tertiary,
      );
    }
    if (bpm > maxBpm) {
      return (
        label: 'Über Ziel',
        detail: 'Ziel $minBpm–$maxBpm bpm',
        icon: Icons.north,
        color: scheme.error,
      );
    }
    return (
      label: 'Im Zielbereich',
      detail: '$minBpm–$maxBpm bpm',
      icon: Icons.check_circle,
      color: scheme.primary,
    );
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
                          widget.session.completed ? 'Session beendet' : phaseTitle,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.session.completed
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
                            label: 'HF-Ziel',
                            value: hfText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<HeartRateSensorState>(
                  stream: widget.session.heartRateSensor.stateStream,
                  initialData: widget.session.heartRateSensor.state,
                  builder: (context, sensorSnapshot) {
                    final sensorState = sensorSnapshot.data ??
                        const HeartRateSensorState.disconnected();
                    final liveBpm = sensorState.bpm;
                    final targetPercent =
                        _heartRateRange(currentPhase, custom?.segment);
                    final connected =
                        sensorState.status == HeartRateSensorStatus.connected;
                    final connecting =
                        sensorState.status == HeartRateSensorStatus.connecting;
                    final scanning =
                        sensorState.status == HeartRateSensorStatus.scanning;

                    final zone =
                        liveBpm == null ? null : _heartRateZoneForBpm(liveBpm);
                    final feedback = liveBpm == null
                        ? null
                        : _heartRateFeedback(
                            context,
                            liveBpm,
                            targetPercent,
                          );

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: connected && liveBpm != null
                            ? Column(
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.favorite,
                                        size: 34,
                                        color: feedback!.color,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sensorState.deviceName ??
                                                  'HF-Sensor',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '$liveBpm',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .displaySmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.only(
                                                    left: 6,
                                                    bottom: 6,
                                                  ),
                                                  child: Text(
                                                    widget.session.maxHeartRate ==
                                                                null ||
                                                            widget.session
                                                                    .maxHeartRate! <=
                                                                0
                                                        ? 'bpm'
                                                        : '${(liveBpm / widget.session.maxHeartRate! * 100).round()} % · $liveBpm bpm',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (zone != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: feedback.color.withValues(
                                              alpha: .12,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            'Zone $zone',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: feedback.color,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: feedback.color.withValues(
                                        alpha: .10,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          feedback.icon,
                                          color: feedback.color,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                feedback.label,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: feedback.color,
                                                ),
                                              ),
                                              Text(
                                                feedback.detail,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            await widget
                                                .session.heartRateSensor
                                                .disconnect();
                                            if (mounted) setState(() {});
                                          },
                                          child: const Text('Trennen'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  connected
                                      ? Icons.favorite
                                      : Icons.favorite_outline,
                                ),
                                title: Text(
                                  connected
                                      ? 'HF-Sensor verbunden'
                                      : connecting
                                          ? 'HF-Sensor wird verbunden …'
                                          : scanning
                                              ? 'Suche nach HF-Sensor …'
                                              : 'Kein HF-Sensor verbunden',
                                ),
                                subtitle: Text(
                                  sensorState.error ??
                                      sensorState.deviceName ??
                                      'Bluetooth-LE Brustgurt oder HF-Sensor',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: connected
                                    ? TextButton(
                                        onPressed: () async {
                                          await widget
                                              .session.heartRateSensor
                                              .disconnect();
                                          if (mounted) setState(() {});
                                        },
                                        child: const Text('Trennen'),
                                      )
                                    : FilledButton.tonalIcon(
                                        onPressed: connecting || scanning
                                            ? null
                                            : _openHeartRateSensorDialog,
                                        icon: const Icon(
                                          Icons.bluetooth_searching,
                                        ),
                                        label: const Text('Verbinden'),
                                      ),
                              ),
                      ),
                    );
                  },
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
                StreamBuilder<List<Track>>(
                  stream: widget.player.queueStream,
                  initialData: List<Track>.from(widget.player.queue),
                  builder: (context, queueSnapshot) {
                    final queue = queueSnapshot.data ??
                        List<Track>.from(widget.player.queue);
                    final currentIndex = widget.player.currentIndex;

                    return Card(
                      child: ExpansionTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text('Session-Musik (${queue.length})'),
                        subtitle: const Text(
                          'Titel während der laufenden Session anpassen',
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(8, 0, 8, 10),
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              onPressed: widget.session.completed
                                  ? null
                                  : _addTrackToSession,
                              icon: const Icon(Icons.add),
                              label: const Text('Titel hinzufügen'),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (queue.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('Keine Titel in der Session.'),
                            )
                          else
                            for (var i = 0; i < queue.length; i++)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  i == currentIndex
                                      ? Icons.play_arrow
                                      : Icons.music_note,
                                ),
                                title: Text(
                                  queue[i].title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${queue[i].artist} · ${_phaseLabel(widget.session.phaseForTrack(queue[i]) ?? _phaseWindowAt(_sessionElapsed).phase)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => widget.player.playAt(i),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Nach oben',
                                      onPressed: widget.session.completed || i == 0
                                          ? null
                                          : () => _moveTrack(i, -1),
                                      icon: const Icon(Icons.arrow_upward),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Nach unten',
                                      onPressed: widget.session.completed ||
                                              i == queue.length - 1
                                          ? null
                                          : () => _moveTrack(i, 1),
                                      icon: const Icon(Icons.arrow_downward),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Aus Session entfernen',
                                      onPressed: widget.session.completed
                                          ? null
                                          : () => _removeTrackFromSession(i),
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    );
                  },
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
                          onPressed: widget.session.completed || nextPhase == null
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
                    widget.session.completed ? 'Zur Planung zurück' : 'Session beenden',
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
