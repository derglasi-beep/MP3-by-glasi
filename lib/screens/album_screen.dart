import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/audio_player_service.dart';

class AlbumScreen extends StatelessWidget {
  final AudioPlayerService player;
  final List<Track> tracks;

  const AlbumScreen({
    super.key,
    required this.player,
    required this.tracks,
  });

  List<Track> get _orderedTracks {
    final ordered = List<Track>.from(tracks);
    if (ordered.any((track) => track.trackNumber != null)) {
      ordered.sort((a, b) {
        final an = a.trackNumber;
        final bn = b.trackNumber;
        if (an == null && bn == null) return 0;
        if (an == null) return 1;
        if (bn == null) return -1;
        return an.compareTo(bn);
      });
    }
    return ordered;
  }

  Track? get _coverTrack {
    for (final track in tracks) {
      if (track.artwork != null && track.artwork!.isNotEmpty) {
        return track;
      }
    }
    return tracks.isEmpty ? null : tracks.first;
  }

  Future<void> _playAlbum() async {
    if (tracks.isEmpty) return;
    await player.setQueue(_orderedTracks, startIndex: 0, preserveCurrent: false);
    await player.play();
  }

  Future<void> _playTrack(int index) async {
    final ordered = _orderedTracks;
    if (index < 0 || index >= ordered.length) return;
    await player.setQueue(ordered, startIndex: index, preserveCurrent: false);
    await player.play();
  }

  Future<void> _queueAlbum(BuildContext context) async {
    if (tracks.isEmpty) return;
    await player.addTracksToQueue(_orderedTracks);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${tracks.length} Titel aus "${tracks.first.album}" zur Queue hinzugefügt.',
          ),
        ),
      );
  }

  String _time(Duration? duration) {
    if (duration == null) return '';
    return '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Album ist leer')),
      );
    }

    final orderedTracks = _orderedTracks;
    final first = orderedTracks.first;
    final cover = _coverTrack;
    final total = tracks.fold<Duration>(
      Duration.zero,
      (sum, track) => sum + (track.duration ?? Duration.zero),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Album'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Column(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: cover?.artwork == null
                            ? Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: const Icon(Icons.album, size: 120),
                              )
                            : Image.memory(
                                cover!.artwork!,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    first.album,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    first.artist,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${tracks.length} Titel'
                    '${total > Duration.zero ? ' · ${total.inMinutes} Min.' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _playAlbum,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Album abspielen'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _queueAlbum(context),
                        icon: const Icon(Icons.queue_music),
                        label: const Text('Queue'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: Divider(height: 1)),
          SliverList.builder(
            itemCount: orderedTracks.length,
            itemBuilder: (_, index) {
              final track = orderedTracks[index];
              return ListTile(
                leading: SizedBox(
                  width: 34,
                  child: Center(
                    child: Text(
                      '${track.trackNumber ?? index + 1}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: track.bpm == null
                    ? null
                    : Text('${track.bpm!.round()} BPM'),
                trailing: Text(_time(track.duration)),
                onTap: () => _playTrack(index),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
