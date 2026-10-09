import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../widgets/bpm_badge.dart';
import '../widgets/glasi_visualizer.dart';
import 'queue_screen.dart';

class NowPlayingScreen extends StatefulWidget {
  final AudioPlayerService player;
  final Set<String> spinningTrackIds;
  final Future<void> Function(Track track) onToggleSpinning;

  const NowPlayingScreen({
    super.key,
    required this.player,
    required this.spinningTrackIds,
    required this.onToggleSpinning,
  });

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  AudioPlayerService get player => widget.player;

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
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 22),
                    child: Column(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 620,
                            maxHeight: 620,
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
                                        cacheWidth: 1200,
                                        cacheHeight: 1200,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            track?.title ?? 'Keine Wiedergabe',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.08,
                                ),
                          ),
                        ),
                        const SizedBox(height: 5),
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
                            if (track != null) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                message: widget.spinningTrackIds.contains(track.id)
                                    ? 'Aus Spinning entfernen'
                                    : 'Für Spinning markieren',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () async {
                                    await widget.onToggleSpinning(track);
                                    if (mounted) setState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: widget.spinningTrackIds.contains(track.id)
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                          : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.directions_bike,
                                          size: 16,
                                          color: widget.spinningTrackIds.contains(track.id)
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onPrimaryContainer
                                              : null,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          widget.spinningTrackIds.contains(track.id)
                                              ? 'Spinning'
                                              : 'Markieren',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.speed, size: 16),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${player.audio.speed.toStringAsFixed(2)}x',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 12),
                        GlasiVisualizer(
                          playing: playing,
                          bpm: track?.bpm,
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<List<Track>>(
                          stream: player.queueStream,
                          initialData: player.queue,
                          builder: (_, __) => Row(
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
                                onPressed: player.canGoPrevious
                                    ? player.previous
                                    : null,
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
                                iconSize: 58,
                                padding: const EdgeInsets.all(18),
                              ),
                              IconButton(
                                tooltip: 'Weiter',
                                onPressed:
                                    player.canGoNext ? player.next : null,
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
