import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';
import '../services/spinning_playlist_service.dart';
import '../screens/now_playing_screen.dart';

class MiniPlayer extends StatefulWidget {
  final AudioPlayerService player;

  const MiniPlayer({super.key, required this.player});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  final LibraryService library = LibraryService();
  final Set<String> _spinningTrackIds = <String>{};
  final Map<String, Set<SpinningPhase>> _spinningPhases = {};

  AudioPlayerService get player => widget.player;

  @override
  void initState() {
    super.initState();
    _loadSpinningSelection();
  }

  Future<void> _loadSpinningSelection() async {
    final ids = await library.loadSpinningTrackIds();
    final stored = await library.loadSpinningTrackPhases();
    if (!mounted) return;
    setState(() {
      _spinningTrackIds
        ..clear()
        ..addAll(ids);
      _spinningPhases
        ..clear()
        ..addEntries(stored.entries.map((entry) => MapEntry(
          entry.key,
          SpinningPhase.values.where((p) => entry.value.contains(p.name)).toSet(),
        )));
    });
  }

  Future<void> _toggleSpinningTrack(Track track) async {
    await _loadSpinningSelection();
    if (!mounted) return;
    setState(() {
      if (!_spinningTrackIds.add(track.id)) {
        _spinningTrackIds.remove(track.id);
        _spinningPhases.remove(track.id);
      }
    });
    await library.saveSpinningTrackIds(_spinningTrackIds);
    await _saveSpinningPhases();
  }

  Future<void> _saveSpinningPhases() =>
      library.saveSpinningTrackPhases({
        for (final e in _spinningPhases.entries)
          e.key: e.value.map((phase) => phase.name).toSet(),
      });

  Future<void> _editSpinningPhases(Track track) async {
    await _loadSpinningSelection();
    if (!mounted) return;
    final selected = Set<SpinningPhase>.from(_spinningPhases[track.id] ?? {});
    final result = await showDialog<Set<SpinningPhase>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: Text('Spinning-Phasen: ${track.title}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Mehrfachauswahl. Ohne Auswahl: alle Phasen.'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final phase in SpinningPhase.values)
                    FilterChip(
                      label: Text(switch (phase) {
                        SpinningPhase.warmup => 'Warm-up',
                        SpinningPhase.build => 'Aufbau',
                        SpinningPhase.load => 'Belastung',
                        SpinningPhase.peak => 'Peak',
                        SpinningPhase.recovery => 'Erholung',
                        SpinningPhase.cooldown => 'Cool-down',
                      }),
                      selected: selected.contains(phase),
                      onSelected: (value) => refresh(() {
                        if (value) { selected.add(phase); }
                        else { selected.remove(phase); }
                      }),
                    ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => refresh(selected.clear),
              child: const Text('Alle Phasen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _spinningTrackIds.add(track.id);
      if (result.isEmpty) {
        _spinningPhases.remove(track.id);
      } else {
        _spinningPhases[track.id] = result;
      }
    });
    await library.saveSpinningTrackIds(_spinningTrackIds);
    await _saveSpinningPhases();
  }

  void _openNowPlaying(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NowPlayingScreen(
          player: player,
          spinningTrackIds: _spinningTrackIds,
          onToggleSpinning: _toggleSpinningTrack,
          onEditSpinningPhases: _editSpinningPhases,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (_, current) {
        final track = current.data;
        if (track == null) return const SizedBox.shrink();

        return Material(
          elevation: 10,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openNowPlaying(context),
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 180) return;
              if (velocity < 0) {
                player.next();
              } else {
                player.previous();
              }
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -180) _openNowPlaying(context);
            },
            child: SizedBox(
              height: 72,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: track.artwork == null
                          ? Container(
                              width: 52,
                              height: 52,
                              color: Theme.of(context).colorScheme.surfaceContainer,
                              child: const Icon(Icons.music_note),
                            )
                          : Image.memory(
                              track.artwork!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StreamBuilder<PlayerState>(
                        stream: player.playerStateStream,
                        builder: (_, state) => StreamBuilder<Duration>(
                          stream: player.positionStream,
                          builder: (_, position) {
                            final duration = player.audio.duration;
                            final currentPosition =
                                position.data ?? player.audio.position;
                            final progress = _progress(
                              currentPosition,
                              duration,
                            );

                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                    if (track.bpm != null) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '${track.bpm!.round()} BPM',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 2,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    StreamBuilder<PlayerState>(
                      stream: player.playerStateStream,
                      initialData: player.audio.playerState,
                      builder: (_, state) {
                        final playing = state.data?.playing ?? false;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Zurück',
                              onPressed:
                                  player.canGoPrevious ? player.previous : null,
                              icon: const Icon(Icons.skip_previous),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              tooltip: '10 Sekunden zurück',
                              onPressed: () => player.seekRelative(
                                const Duration(seconds: -10),
                              ),
                              icon: const Icon(Icons.replay_10),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              tooltip: playing ? 'Pause' : 'Wiedergabe',
                              onPressed: playing ? player.pause : player.play,
                              icon: Icon(
                                playing
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                                size: 34,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              tooltip: '10 Sekunden vor',
                              onPressed: () => player.seekRelative(
                                const Duration(seconds: 10),
                              ),
                              icon: const Icon(Icons.forward_10),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              tooltip: 'Weiter',
                              onPressed: player.canGoNext ? player.next : null,
                              icon: const Icon(Icons.skip_next),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _progress(Duration position, Duration? duration) {
    if (duration == null || duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }
}
