import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/bpm_service.dart';
import '../services/bpm_cache.dart';
import '../services/library_service.dart';
import '../services/music_scanner.dart';
import '../widgets/bpm_badge.dart';
import '../widgets/glasi_visualizer.dart';
import 'playlists_screen.dart';

enum _SortMode { title, artist, album, bpm, year }

class PlayerScreen extends StatefulWidget {
  final AudioPlayerService player;
  const PlayerScreen({super.key, required this.player});
  @override State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final scanner = MusicScanner();
  final bpm = BpmService();
  final bpmCache = BpmCache();
  final library = LibraryService();
  List<Track> tracks = [];

  String search = '';
  bool analyzing = false;
  double volume = .8;
  _SortMode sortMode = _SortMode.title;
  bool sortAscending = true;

  @override
  void initState() {
    super.initState();
    _restoreLibrary();
  }

  Future<void> _restoreLibrary() async {
    final saved = await library.loadTracks();
    if (!mounted || saved.isEmpty) return;
    final valid = <Track>[];
    for (final t in saved) {
      if (await File(t.path).exists()) valid.add(t);
    }
    if (!mounted) return;
    setState(() => tracks = valid);
    if (valid.length != saved.length) await library.saveTracks(valid);
    await widget.player.setQueue(tracks);
  }

  List<Track> get visible {
    final q = search.toLowerCase().trim();
    final result = tracks.where((t) =>
      q.isEmpty ||
      t.title.toLowerCase().contains(q) ||
      t.artist.toLowerCase().contains(q) ||
      t.album.toLowerCase().contains(q),
    ).toList();

    int compare(Track a, Track b) {
      switch (sortMode) {
        case _SortMode.artist: return _text(a.artist).compareTo(_text(b.artist));
        case _SortMode.album: return _text(a.album).compareTo(_text(b.album));
        case _SortMode.bpm: return (a.bpm ?? 0).compareTo(b.bpm ?? 0);
        case _SortMode.year: return (a.year ?? 0).compareTo(b.year ?? 0);
        case _SortMode.title: return _text(a.title).compareTo(_text(b.title));
      }
    }

    result.sort((a, b) {
      final primary = compare(a, b);
      if (primary != 0) return sortAscending ? primary : -primary;
      final fallback = _text(a.title).compareTo(_text(b.title));
      return sortAscending ? fallback : -fallback;
    });
    return result;
  }

  String _text(String value) => value.trim().toLowerCase();

  String _sortLabel() => switch (sortMode) {
    _SortMode.title => 'Titel',
    _SortMode.artist => 'Interpret',
    _SortMode.album => 'Album',
    _SortMode.bpm => 'BPM',
    _SortMode.year => 'Jahr',
  };

  Future<void> addFiles() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowMultiple: true,
      allowedExtensions: ['mp3','flac','wav','m4a','mp4','ogg','opus','ape','aif','aiff'],
    );
    if (r == null) return;
    await _add(await scanner.scanFiles(
      r.files.where((f) => f.path != null).map((f) => File(f.path!)),
    ));
  }

  Future<void> addFolder() async {
    final p = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Musikordner auswählen');
    if (p != null) await _add(await scanner.scanDirectory(p));
  }

  Future<void> _add(List<Track> found) async {
    final map = {for (final t in tracks) t.id: t};
    for (final t in found) map[t.id] = t;
    final hydrated = <Track>[];
    for (final t in map.values) {
      final cached = t.bpm ?? await bpmCache.get(t.path);
      hydrated.add(cached == null ? t : t.copyWith(bpm: cached.toDouble()));
    }
    setState(() => tracks = hydrated);
    await library.saveTracks(tracks);
    await widget.player.setQueue(tracks);
  }

  Future<void> _analyzeTrack(Track t) async {
    if (analyzing) return;
    final cached = await bpmCache.get(t.path);
    if (cached != null) {
      _setBpm(t.id, cached.toDouble());
      return;
    }
    setState(() => analyzing = true);
    final value = await bpm.analyzeFile(t.path);
    if (value != null) {
      await bpmCache.put(t.path, value.round());
      _setBpm(t.id, value);
    }
    if (mounted) setState(() => analyzing = false);
  }

  void _setBpm(String id, double value) {
    if (!mounted) return;
    setState(() {
      final i = tracks.indexWhere((x) => x.id == id);
      if (i >= 0) tracks[i] = tracks[i].copyWith(bpm: value);
    });
    unawaited(library.saveTracks(tracks));
  }

  void _setSort(_SortMode mode) {
    setState(() {
      if (sortMode == mode) {
        sortAscending = !sortAscending;
      } else {
        sortMode = mode;
        sortAscending = true;
      }
    });
  }

  String time(Duration d) => '\${d.inMinutes}:\${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _playTrack(Track t) async {
    final n = tracks.indexWhere((x) => x.id == t.id);
    await widget.player.setQueue(tracks, startIndex: n);
    await widget.player.play();
    unawaited(_analyzeTrack(t));
    if (mounted) setState(() {});
  }

  Future<void> _openPlaylists() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistsScreen(player: widget.player, tracks: tracks)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MP3 by Glasi'), actions: [
      IconButton(onPressed: _openPlaylists, icon: const Icon(Icons.queue_music), tooltip: 'Playlists'),
      IconButton(onPressed: addFiles, icon: const Icon(Icons.library_music), tooltip: 'Dateien hinzufügen'),
      IconButton(onPressed: addFolder, icon: const Icon(Icons.folder_open), tooltip: 'Ordner scannen'),
    ]),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          onChanged: (v) => setState(() => search = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Titel, Interpret oder Album',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(children: [
          const Icon(Icons.sort, size: 20),
          const SizedBox(width: 8),
          Text('Sortierung: \${_sortLabel()}'),
          const Spacer(),
          IconButton(
            onPressed: () => setState(() => sortAscending = !sortAscending),
            tooltip: sortAscending ? 'Absteigend' : 'Aufsteigend',
            icon: Icon(sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
          ),
          PopupMenuButton<_SortMode>(
            tooltip: 'Sortieren nach',
            onSelected: _setSort,
            itemBuilder: (_) => [
              for (final mode in _SortMode.values)
                PopupMenuItem(value: mode, child: Text(switch (mode) {
                  _SortMode.title => 'Titel',
                  _SortMode.artist => 'Interpret',
                  _SortMode.album => 'Album',
                  _SortMode.bpm => 'BPM',
                  _SortMode.year => 'Jahr',
                })),
            ],
            child: const Icon(Icons.filter_list),
          ),
        ]),
      ),
      Expanded(flex: 5, child: _player()),
      const Divider(height: 1),
      Expanded(flex: 5, child: visible.isEmpty
          ? const Center(child: Text('Keine Titel in der Bibliothek'))
          : ListView.builder(
              itemCount: visible.length,
              itemBuilder: (_, i) {
                final t = visible[i];
                return ListTile(
                  selected: widget.player.currentTrack?.id == t.id,
                  leading: t.artwork == null
                      ? const CircleAvatar(child: Icon(Icons.music_note))
                      : Image.memory(t.artwork!, width: 48, height: 48, fit: BoxFit.cover),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('\${t.artist} • \${t.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: BpmBadge(bpm: t.bpm),
                  onTap: () => _playTrack(t),
                );
              },
            ))
    ]),
  );

  Widget _player() => StreamBuilder<PlayerState>(
    stream: widget.player.playerStateStream,
    builder: (_, ps) => StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (_, pos) => StreamBuilder<Duration?>(
        stream: widget.player.durationStream,
        builder: (_, dur) => StreamBuilder<Track?>(
          stream: widget.player.currentTrackStream,
          initialData: widget.player.currentTrack,
          builder: (_, current) {
            final t = current.data;
            final d = dur.data ?? t?.duration ?? Duration.zero;
            final p = pos.data ?? Duration.zero;
            final max = d.inMilliseconds > 0 ? d.inMilliseconds.toDouble() : 1;
            final value = p.inMilliseconds.clamp(0, max.toInt()).toDouble();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                SizedBox(width: 170, height: 170,
                  child: t?.artwork == null
                      ? const Card(child: Icon(Icons.album, size: 90))
                      : Image.memory(t!.artwork!, fit: BoxFit.cover)),
                const SizedBox(height: 8),
                Text(t?.title ?? 'Keine Wiedergabe',
                  style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                Text(t?.artist ?? 'Lokale Bibliothek'),
                const SizedBox(height: 6),
                GlasiVisualizer(playing: ps.data?.playing ?? false, bpm: t?.bpm),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  BpmBadge(bpm: t?.bpm, loading: analyzing && t != null && t.bpm == null),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: t == null ? null : () => _analyzeTrack(t),
                    icon: const Icon(Icons.speed), label: const Text('BPM')),
                ]),
                Slider(value: value, max: max,
                  onChanged: (v) => widget.player.seek(Duration(milliseconds: v.toInt()))),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(time(p)), Text(time(d))]),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(onPressed: widget.player.toggleShuffle,
                    color: widget.player.shuffle ? Theme.of(context).colorScheme.primary : null,
                    icon: const Icon(Icons.shuffle), tooltip: 'Zufallswiedergabe'),
                  IconButton(onPressed: widget.player.previous, icon: const Icon(Icons.skip_previous), iconSize: 38),
                  IconButton(
                    onPressed: t == null ? null : ((ps.data?.playing ?? false)
                        ? widget.player.pause : widget.player.play),
                    icon: Icon((ps.data?.playing ?? false) ? Icons.pause_circle : Icons.play_circle),
                    iconSize: 66),
                  IconButton(onPressed: widget.player.next, icon: const Icon(Icons.skip_next), iconSize: 38),
                  IconButton(onPressed: widget.player.toggleRepeat,
                    color: widget.player.loopMode != LoopMode.off ? Theme.of(context).colorScheme.primary : null,
                    icon: Icon(widget.player.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat),
                    tooltip: 'Wiederholung'),
                ]),
                Row(children: [
                  const Icon(Icons.volume_down),
                  Expanded(child: Slider(value: volume, onChanged: (v) {
                    setState(() => volume = v);
                    widget.player.setVolume(v);
                  })),
                  const Icon(Icons.volume_up),
                ])
              ]),
            );
          },
        ),
      ),
    ),
  );
}
