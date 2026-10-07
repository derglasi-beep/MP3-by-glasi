import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../widgets/bpm_badge.dart';
import '../widgets/glasi_visualizer.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends StatelessWidget {
  final AudioPlayerService player;

  const NowPlayingScreen({super.key, required this.player});

  String _time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Queue',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => QueueScreen(player: player)),
            ),
            icon: const Icon(Icons.queue_music),
          ),
        ],
      ),
      body: StreamBuilder<PlayerState>(
        stream: player.playerStateStream,
        builder: (_, state) => StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (_, position) => StreamBuilder<Duration?>(
            stream: player.durationStream,
            builder: (_, duration) => StreamBuilder<Track?>(
              stream: player.currentTrackStream,
              initialData: player.currentTrack,
              builder: (_, current) {
                final track = current.data;
                final d = duration.data ?? track?.duration ?? Duration.zero;
                final p = position.data ?? Duration.zero;
                final max =
                    d.inMilliseconds > 0 ? d.inMilliseconds.toDouble() : 1.0;
                final value =
                    p.inMilliseconds.clamp(0, max.toInt()).toDouble();
                final playing = state.data?.playing ?? false;

                return SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 2),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 560,
                            maxHeight: 560,
                          ),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Hero(
                              tag: 'now-playing-cover',
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                child: track?.artwork == null
                                    ? Container(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        child: const Icon(Icons.album, size: 160),
                                      )
                                    : Image.memory(
                                        track!.artwork!,
                                        fit: BoxFit.cover,
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          track?.title ?? 'Keine Wiedergabe',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.left,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            track?.artist ?? 'Lokale Bibliothek',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (track?.album != null) ...[
                          const SizedBox(height: 2),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              track!.album,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            BpmBadge(bpm: track?.bpm),
                            const SizedBox(width: 8),
                            Chip(
                              avatar: const Icon(Icons.speed, size: 17),
                              label: Text(
                                '${player.audio.speed.toStringAsFixed(2)}x',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        GlasiVisualizer(
                          playing: playing,
                          bpm: track?.bpm,
                        ),
                        Slider(
                          value: value,
                          max: max,
                          onChanged: track == null
                              ? null
                              : (v) => player.seek(
                                    Duration(milliseconds: v.toInt()),
                                  ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_time(p)),
                            Text(_time(d)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Shuffle',
                              onPressed: player.toggleShuffle,
                              color: player.shuffle
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                              icon: const Icon(Icons.shuffle),
                            ),
                            IconButton(
                              tooltip: 'Zurück',
                              onPressed:
                                  player.canGoPrevious ? player.previous : null,
                              icon: const Icon(Icons.skip_previous),
                              iconSize: 42,
                            ),
                            IconButton.filled(
                              tooltip: playing ? 'Pause' : 'Wiedergabe',
                              onPressed: track == null
                                  ? null
                                  : (playing ? player.pause : player.play),
                              icon: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                              ),
                              iconSize: 54,
                              padding: const EdgeInsets.all(16),
                            ),
                            IconButton(
                              tooltip: 'Weiter',
                              onPressed: player.canGoNext ? player.next : null,
                              icon: const Icon(Icons.skip_next),
                              iconSize: 42,
                            ),
                            IconButton(
                              tooltip: 'Wiederholung',
                              onPressed: player.toggleRepeat,
                              color: player.loopMode != LoopMode.off
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                              icon: Icon(
                                player.loopMode == LoopMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
