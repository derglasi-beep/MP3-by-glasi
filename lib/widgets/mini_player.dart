import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';
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

  AudioPlayerService get player => widget.player;

  @override
  void initState() {
    super.initState();
    _loadSpinningSelection();
  }

  Future<void> _loadSpinningSelection() async {
    final ids = await library.loadSpinningTrackIds();
    if (!mounted) return;
    setState(() {
      _spinningTrackIds
        ..clear()
        ..addAll(ids);
    });
  }

  Future<void> _toggleSpinningTrack(Track track) async {
    setState(() {
      if (!_spinningTrackIds.add(track.id)) {
        _spinningTrackIds.remove(track.id);
      }
    });
    await library.saveSpinningTrackIds(_spinningTrackIds);
  }

  void _openNowPlaying(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NowPlayingScreen(
          player: player,
          spinningTrackIds: _spinningTrackIds,
          onToggleSpinning: _toggleSpinningTrack,
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
                            final playing = state.data?.playing ?? false;
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
                              onPressed: player.canGoPrevious ? player.previous : null,
                              icon: const Icon(Icons.skip_previous),
                            ),
                            IconButton(
                              tooltip: playing ? 'Pause' : 'Wiedergabe',
                              onPressed: playing ? player.pause : player.play,
                              icon: Icon(
                                playing ? Icons.pause_circle : Icons.play_circle,
                                size: 34,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Weiter',
                              onPressed: player.canGoNext ? player.next : null,
                              icon: const Icon(Icons.skip_next),
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
