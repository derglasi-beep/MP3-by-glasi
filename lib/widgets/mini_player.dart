import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../screens/now_playing_screen.dart';

class MiniPlayer extends StatelessWidget {
  final AudioPlayerService player;

  const MiniPlayer({super.key, required this.player});

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
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NowPlayingScreen(player: player),
              ),
            ),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
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
                          builder: (_, _) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: _progress(player),
                              minHeight: 2,
                            ),
                          ],
                        ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Zurück',
                      onPressed: player.previous,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton(
                      tooltip: statePlaying(player) ? 'Pause' : 'Wiedergabe',
                      onPressed: statePlaying(player) ? player.pause : player.play,
                      icon: Icon(
                        statePlaying(player) ? Icons.pause_circle : Icons.play_circle,
                        size: 34,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Weiter',
                      onPressed: player.next,
                      icon: const Icon(Icons.skip_next),
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

  bool statePlaying(AudioPlayerService player) => player.audio.playing;

  double _progress(AudioPlayerService player) {
    final duration = player.audio.duration;
    if (duration == null || duration.inMilliseconds <= 0) return 0;
    return (player.audio.position.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }
}
