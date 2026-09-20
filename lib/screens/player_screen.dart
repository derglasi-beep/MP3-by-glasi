import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';

class PlayerScreen extends StatefulWidget {
  final AudioPlayerService player;
  const PlayerScreen({super.key, required this.player});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final List<Track> tracks = [];
  double volume = 0.8;

  Future<void> addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg'],
      allowMultiple: true,
    );
    if (result == null) return;

    final added = result.files
        .where((f) => f.path != null)
        .map((f) => Track(
              id: f.path!,
              path: f.path!,
              title: _titleFromPath(f.path!),
            ))
        .toList();

    setState(() => tracks.addAll(added));
    await widget.player.setQueue(tracks);
  }

  String _titleFromPath(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MP3 by Glasi'),
        actions: [
          IconButton(
            tooltip: 'Dateien hinzufügen',
            onPressed: addFiles,
            icon: const Icon(Icons.library_music),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildPlayer()),
          Expanded(child: _buildQueue()),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    return StreamBuilder<Duration?>(
      stream: widget.player.durationStream,
      builder: (context, durationSnap) {
        return StreamBuilder<Duration>(
          stream: widget.player.positionStream,
          builder: (context, positionSnap) {
            final duration = durationSnap.data ?? Duration.zero;
            final position = positionSnap.data ?? Duration.zero;
            final max = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1;
            final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.album, size: 120),
                  const SizedBox(height: 16),
                  Text(widget.player.currentTrack?.title ?? 'Keine Wiedergabe',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(widget.player.currentTrack?.artist ?? 'Lokale Bibliothek'),
                  const SizedBox(height: 16),
                  Slider(
                    value: value,
                    max: max,
                    onChanged: (v) => widget.player.seek(Duration(milliseconds: v.toInt())),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: widget.player.previous,
                        icon: const Icon(Icons.skip_previous),
                        iconSize: 40,
                      ),
                      StreamBuilder<PlayerState>(
                        stream: widget.player.playerStateStream,
                        builder: (context, snap) {
                          final playing = snap.data?.playing ?? false;
                          return IconButton(
                            onPressed: playing ? widget.player.pause : widget.player.play,
                            icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                            iconSize: 64,
                          );
                        },
                      ),
                      IconButton(
                        onPressed: widget.player.next,
                        icon: const Icon(Icons.skip_next),
                        iconSize: 40,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.volume_down),
                      Expanded(
                        child: Slider(
                          value: volume,
                          onChanged: (v) {
                            setState(() => volume = v);
                            widget.player.setVolume(v);
                          },
                        ),
                      ),
                      const Icon(Icons.volume_up),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQueue() {
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return ListTile(
          leading: const Icon(Icons.music_note),
          title: Text(track.title),
          subtitle: Text(track.artist),
          selected: widget.player.currentIndex == index,
          onTap: () async {
            await widget.player.setQueue(tracks, startIndex: index);
            await widget.player.play();
            setState(() {});
          },
        );
      },
    );
  }
}
