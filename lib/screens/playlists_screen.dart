import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';

class PlaylistsScreen extends StatefulWidget {
  final AudioPlayerService player;
  final List<Track> tracks;
  const PlaylistsScreen({super.key, required this.player, required this.tracks});
  @override State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final library = LibraryService();
  Map<String, List<String>> playlists = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final value = await library.loadPlaylists();
    if (mounted) setState(() => playlists = value);
  }

  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Neue Playlist'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Playlist-Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Anlegen')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || playlists.containsKey(name)) return;
    playlists[name] = [];
    await library.savePlaylists(playlists);
    if (mounted) setState(() {});
  }

  Future<void> _open(String name) async {
    final ids = playlists[name] ?? [];
    final selected = widget.tracks.where((t) => ids.contains(t.id)).toList();
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _PlaylistDetail(
      name: name, tracks: selected, player: widget.player,
      onChanged: (next) async {
        playlists[name] = next.map((t) => t.id).toList();
        await library.savePlaylists(playlists);
        if (mounted) setState(() {});
      },
    )));
  }

  Future<void> _delete(String name) async {
    playlists.remove(name);
    await library.savePlaylists(playlists);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Playlists'), actions: [
      IconButton(onPressed: _create, icon: const Icon(Icons.add), tooltip: 'Playlist erstellen'),
    ]),
    body: playlists.isEmpty
        ? const Center(child: Text('Noch keine Playlists. Mit + eine Playlist erstellen.'))
        : ListView(
            children: playlists.keys.map((name) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.queue_music)),
              title: Text(name),
              subtitle: Text((playlists[name]?.length ?? 0).toString() + ' Titel'),
              onTap: () => _open(name),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(name)),
            )).toList(),
          ),
  );
}

class _PlaylistDetail extends StatefulWidget {
  final String name;
  final List<Track> tracks;
  final AudioPlayerService player;
  final Future<void> Function(List<Track>) onChanged;
  const _PlaylistDetail({required this.name, required this.tracks, required this.player, required this.onChanged});
  @override State<_PlaylistDetail> createState() => _PlaylistDetailState();
}

class _PlaylistDetailState extends State<_PlaylistDetail> {
  late List<Track> tracks;
  @override void initState() { super.initState(); tracks = [...widget.tracks]; }

  Future<void> _add() async {
    final available = widget.player.queue.where((t) => !tracks.any((x) => x.id == t.id)).toList();
    if (available.isEmpty) return;
    final selected = <String>{};
    final result = await showDialog<List<Track>>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setDialog) => AlertDialog(
        title: const Text('Titel hinzufügen'),
        content: SizedBox(width: 420, height: 360, child: ListView(
          children: available.map((t) => CheckboxListTile(
            value: selected.contains(t.id),
            title: Text(t.title),
            subtitle: Text(t.artist),
            onChanged: (v) => setDialog(() => v == true ? selected.add(t.id) : selected.remove(t.id)),
          )).toList(),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, available.where((t) => selected.contains(t.id)).toList()), child: const Text('Hinzufügen')),
        ],
      )),
    );
    if (result == null || result.isEmpty) return;
    tracks.addAll(result);
    await widget.onChanged(tracks);
    if (mounted) setState(() {});
  }

  Future<void> _play(int index) async {
    await widget.player.setQueue(tracks, startIndex: index);
    await widget.player.play();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name), actions: [
      IconButton(onPressed: _add, icon: const Icon(Icons.add), tooltip: 'Titel hinzufügen'),
    ]),
    body: tracks.isEmpty
        ? const Center(child: Text('Playlist ist leer. + öffnet die aktuelle Bibliothek.'))
        : ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) {
              final t = tracks[i];
              return ListTile(
                leading: const Icon(Icons.music_note),
                title: Text(t.title),
                subtitle: Text(t.artist),
                onTap: () => _play(i),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () async {
                    tracks.removeAt(i);
                    await widget.onChanged(tracks);
                    if (mounted) setState(() {});
                  },
                ),
              );
            },
          ),
  );
}
