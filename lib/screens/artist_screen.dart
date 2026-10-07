import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/audio_player_service.dart';
import 'album_screen.dart';

class ArtistScreen extends StatelessWidget {
  final AudioPlayerService player;
  final String artist;
  final List<Track> tracks;

  const ArtistScreen({
    super.key,
    required this.player,
    required this.artist,
    required this.tracks,
  });

  List<List<Track>> get _albums {
    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      final album = track.album.trim().isEmpty ? 'Unbekannt' : track.album.trim();
      groups.putIfAbsent(album.toLowerCase(), () => <Track>[]).add(track);
    }

    final albums = groups.values.toList()
      ..sort((a, b) {
        final ay = a.map((t) => t.year ?? 0).where((y) => y > 0).fold<int>(0, (p, y) => p == 0 || y < p ? y : p);
        final by = b.map((t) => t.year ?? 0).where((y) => y > 0).fold<int>(0, (p, y) => p == 0 || y < p ? y : p);
        if (ay != 0 && by != 0 && ay != by) return ay.compareTo(by);
        return a.first.album.toLowerCase().compareTo(b.first.album.toLowerCase());
      });

    return albums;
  }

  List<Track> get _orderedTracks {
    final result = <Track>[];
    for (final album in _albums) {
      final ordered = List<Track>.from(album);
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
      result.addAll(ordered);
    }
    return result;
  }

  Track? get _coverTrack {
    for (final track in tracks) {
      if (track.artwork != null && track.artwork!.isNotEmpty) return track;
    }
    return tracks.isEmpty ? null : tracks.first;
  }

  Future<void> _playAll() async {
    final ordered = _orderedTracks;
    if (ordered.isEmpty) return;
    await player.setQueue(ordered, startIndex: 0);
    await player.play();
  }

  Future<void> _queueAll(BuildContext context) async {
    final ordered = _orderedTracks;
    if (ordered.isEmpty) return;
    await player.addTracksToQueue(ordered);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${ordered.length} Titel von $artist zur Queue hinzugefügt.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final albums = _albums;
    final cover = _coverTrack;

    return Scaffold(
      appBar: AppBar(title: const Text('Interpret')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 72,
                    backgroundImage: cover?.artwork == null
                        ? null
                        : MemoryImage(cover!.artwork!),
                    child: cover?.artwork == null
                        ? const Icon(Icons.person, size: 70)
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    artist,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${albums.length} Alben · ${tracks.length} Titel',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _playAll,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Alles abspielen'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _queueAll(context),
                        icon: const Icon(Icons.queue_music),
                        label: const Text('Queue'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Alben',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: albums.length,
            itemBuilder: (_, index) {
              final albumTracks = albums[index];
              final first = albumTracks.first;
              Track coverTrack = first;
              for (final track in albumTracks) {
                if (track.artwork != null && track.artwork!.isNotEmpty) {
                  coverTrack = track;
                  break;
                }
              }

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: coverTrack.artwork == null
                        ? Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Icon(Icons.album),
                          )
                        : Image.memory(
                            coverTrack.artwork!,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                title: Text(
                  first.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${first.year ?? ''}${first.year != null ? ' · ' : ''}${albumTracks.length} Titel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlbumScreen(
                      player: player,
                      tracks: albumTracks,
                    ),
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
