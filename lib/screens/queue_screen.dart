import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import 'package:just_audio/just_audio.dart';
import '../widgets/bpm_badge.dart';

class QueueScreen extends StatefulWidget {
  final AudioPlayerService player;
  const QueueScreen({super.key, required this.player});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<List<Track>>(
          stream: widget.player.queueStream,
          initialData: List.unmodifiable(widget.player.queue),
          builder: (_, snapshot) => Text('Queue (${snapshot.data?.length ?? 0})'),
        ),
        actions: [
          IconButton(
            tooltip: widget.player.shuffle ? 'Shuffle aus' : 'Shuffle an',
            onPressed: () async {
              await widget.player.toggleShuffle();
              if (mounted) setState(() {});
            },
            icon: Icon(
              Icons.shuffle,
              color: widget.player.shuffle
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          IconButton(
            tooltip: _repeatLabel(widget.player.loopMode),
            onPressed: () async {
              await widget.player.toggleRepeat();
              if (mounted) setState(() {});
            },
            icon: Icon(
              _repeatIcon(widget.player.loopMode),
              color: widget.player.loopMode != LoopMode.off
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          IconButton(
            tooltip: 'Queue leeren',
            onPressed: widget.player.queue.isEmpty ? null : _clearQueue,
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: StreamBuilder<List<Track>>(
        stream: widget.player.queueStream,
        initialData: List.unmodifiable(widget.player.queue),
        builder: (_, snapshot) {
          final queue = snapshot.data ?? const <Track>[];
          if (queue.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.queue_music, size: 64),
                  SizedBox(height: 12),
                  Text('Queue ist leer'),
                  SizedBox(height: 4),
                  Text('Titel über „Als Nächstes abspielen“ hinzufügen.'),
                ],
              ),
            );
          }

          return Column(
            children: [
              _NowPlaying(player: widget.player),
              _QueueSummary(queue: queue, player: widget.player),
              const Divider(height: 1),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: queue.length,
                  onReorder: (oldIndex, newIndex) =>
                      widget.player.move(oldIndex, newIndex),
                  itemBuilder: (_, index) {
                    final track = queue[index];
                    final current = widget.player.currentTrack?.id == track.id;
                    return ListTile(
                      key: ValueKey('${track.id}-${index}'),
                      selected: current,
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.drag_handle),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 42,
                            height: 42,
                            child: track.artwork == null
                                ? const CircleAvatar(child: Icon(Icons.music_note))
                                : Image.memory(track.artwork!, fit: BoxFit.cover),
                          ),
                        ],
                      ),
                      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${track.artist} • ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BpmBadge(bpm: track.bpm),
                          IconButton(
                            tooltip: 'Entfernen',
                            onPressed: () => widget.player.removeAt(index),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      onTap: () => widget.player.playAt(index),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _repeatLabel(LoopMode mode) => switch (mode) {
    LoopMode.off => 'Wiederholung aus',
    LoopMode.all => 'Alle Titel wiederholen',
    LoopMode.one => 'Titel wiederholen',
  };

  IconData _repeatIcon(LoopMode mode) => switch (mode) {
    LoopMode.one => Icons.repeat_one,
    _ => Icons.repeat,
  };

  Future<void> _clearQueue() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Queue leeren?'),
        content: const Text(
          'Alle Titel werden aus der aktuellen Queue entfernt und die Wiedergabe wird gestoppt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leeren'),
          ),
        ],
      ),
    );

    if (shouldClear == true) await widget.player.clearQueue();
  }
}

class _QueueSummary extends StatelessWidget {
  final List<Track> queue;
  final AudioPlayerService player;

  const _QueueSummary({required this.queue, required this.player});

  String _duration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final rest = (minutes % 60).toString().padLeft(2, '0');
      return '\${hours}:\${rest}:\${seconds}';
    }
    return '\${minutes}:\${seconds}';
  }

  @override
  Widget build(BuildContext context) {
    final total = queue.fold<Duration>(Duration.zero, (sum, track) => sum + track.duration);
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.audio.position,
      builder: (_, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final current = player.currentTrack;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(Icons.queue_music, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('\${queue.length} Titel'),
              const Spacer(),
              if (current != null) Text('\${_duration(position)} / \${_duration(current.duration)}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
              Text(_duration(total), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }
}

class _NowPlaying extends StatelessWidget {
  final AudioPlayerService player;
  const _NowPlaying({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (_, snapshot) {
        final track = snapshot.data;
        if (track == null) return const SizedBox.shrink();

        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  height: 54,
                  child: track.artwork == null
                      ? const Card(child: Icon(Icons.album))
                      : Image.memory(track.artwork!, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('JETZT LÄUFT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      const SizedBox(height: 2),
                      Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  initialData: player.audio.playerState,
                  builder: (_, snapshot) {
                    final playing = snapshot.data?.playing ?? player.audio.playing;
                    return IconButton(
                      tooltip: playing ? 'Pause' : 'Wiedergabe',
                      onPressed: playing ? player.pause : player.play,
                      icon: Icon(
                        playing
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
