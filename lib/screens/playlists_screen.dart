import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/library_service.dart';
import '../services/playlist_transfer_service.dart';

class PlaylistsScreen extends StatefulWidget {
  final AudioPlayerService player;
  final List<Track> tracks;
  const PlaylistsScreen({super.key, required this.player, required this.tracks});
  @override State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final library = LibraryService();
  final transfer = PlaylistTransferService();
  Map<String, List<String>> playlists = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final value = await library.loadPlaylists();
    if (mounted) setState(() => playlists = value);
  }

  Future<void> _importPlaylist() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'm3u', 'm3u8'],
    );
    final path = picked?.files.single.path;
    if (path == null || path.isEmpty) return;

    PlaylistImportResult result;
    try {
      result = await transfer.importFile(File(path), widget.tracks);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Playlist konnte nicht importiert werden: $error'),
          ),
        );
      return;
    }

    if (!mounted) return;

    final fileName = path.replaceAll('\\', '/').split('/').last;
    final dot = fileName.lastIndexOf('.');
    final suggestedName = dot > 0 ? fileName.substring(0, dot) : fileName;
    final controller = TextEditingController(text: suggestedName);

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Playlist importieren'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Playlist-Name',
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${result.matched.length} Titel gefunden · '
                '${result.unmatched.length} nicht gefunden',
              ),
              if (result.unmatched.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Nicht gefunden:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: result.unmatched.length,
                    itemBuilder: (_, index) => Text(
                      '• ${result.unmatched[index].raw}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          if (result.matched.isNotEmpty)
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'spinning'),
              icon: const Icon(Icons.directions_bike),
              label: const Text('Für Spinning markieren'),
            ),
          FilledButton(
            onPressed: result.matched.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Playlist anlegen'),
          ),
        ],
      ),
    );

    final name = controller.text.trim();
    controller.dispose();
    if (action == null || result.matched.isEmpty) return;

    if (action == 'spinning') {
      final ids = await library.loadSpinningTrackIds();
      ids.addAll(result.matched.map((track) => track.id));
      await library.saveSpinningTrackIds(ids);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${result.matched.length} importierte Titel für Spinning markiert.',
            ),
          ),
        );
      return;
    }

    if (name.isEmpty) return;

    var finalName = name;
    var suffix = 2;
    while (playlists.containsKey(finalName)) {
      finalName = '$name ($suffix)';
      suffix++;
    }

    playlists[finalName] =
        result.matched.map((track) => track.id).toList(growable: false);
    await library.savePlaylists(playlists);
    if (!mounted) return;
    setState(() {});

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Playlist „$finalName“ mit ${result.matched.length} Titeln importiert.',
          ),
        ),
      );
  }

  Future<void> _exportPlaylist(String name) async {
    final ids = playlists[name] ?? const <String>[];
    final byId = {for (final track in widget.tracks) track.id: track};
    final tracks = <Track>[
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
    if (tracks.isEmpty) return;

    final format = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('„$name“ exportieren'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'txt'),
            child: const ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('TXT'),
              subtitle: Text('Interpret - Titel'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'csv'),
            child: const ListTile(
              leading: Icon(Icons.table_chart_outlined),
              title: Text('CSV'),
              subtitle: Text('Interpret, Titel, Album und Pfad'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'm3u8'),
            child: const ListTile(
              leading: Icon(Icons.queue_music),
              title: Text('M3U8'),
              subtitle: Text('Playlist mit lokalen Dateipfaden'),
            ),
          ),
        ],
      ),
    );
    if (format == null) return;

    final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Playlist exportieren',
      fileName: '$safeName.$format',
      type: FileType.custom,
      allowedExtensions: [format],
    );
    if (savePath == null || savePath.isEmpty) return;

    final raw = switch (format) {
      'csv' => transfer.exportCsv(tracks),
      'm3u8' => transfer.exportM3u(tracks),
      _ => transfer.exportTxt(tracks),
    };

    try {
      await File(savePath).writeAsString(raw, flush: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $error')),
        );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Playlist „$name“ exportiert.')),
      );
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
    final byId = {for (final track in widget.tracks) track.id: track};
    final selected = <Track>[
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _PlaylistDetail(
      name: name,
      tracks: selected,
      libraryTracks: widget.tracks,
      player: widget.player,
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
      IconButton(
        onPressed: _importPlaylist,
        icon: const Icon(Icons.file_download_outlined),
        tooltip: 'Playlist importieren',
      ),
      IconButton(
        onPressed: _create,
        icon: const Icon(Icons.add),
        tooltip: 'Playlist erstellen',
      ),
    ]),
    body: playlists.isEmpty
        ? const Center(child: Text('Noch keine Playlists. Mit + eine Playlist erstellen.'))
        : ListView(
            children: playlists.keys.map((name) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.queue_music)),
              title: Text(name),
              subtitle: Text((playlists[name]?.length ?? 0).toString() + ' Titel'),
              onTap: () => _open(name),
              trailing: PopupMenuButton<String>(
                tooltip: 'Playlist-Aktion',
                onSelected: (action) {
                  if (action == 'export') {
                    _exportPlaylist(name);
                  } else if (action == 'delete') {
                    _delete(name);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(Icons.upload_file),
                      title: Text('Exportieren'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Löschen'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
  );
}

class _PlaylistDetail extends StatefulWidget {
  final String name;
  final List<Track> tracks;
  final List<Track> libraryTracks;
  final AudioPlayerService player;
  final Future<void> Function(List<Track>) onChanged;
  const _PlaylistDetail({
    required this.name,
    required this.tracks,
    required this.libraryTracks,
    required this.player,
    required this.onChanged,
  });
  @override State<_PlaylistDetail> createState() => _PlaylistDetailState();
}

class _PlaylistDetailState extends State<_PlaylistDetail> {
  late List<Track> tracks;
  @override void initState() { super.initState(); tracks = [...widget.tracks]; }

  Future<void> _add() async {
    final available = widget.libraryTracks
        .where((t) => !tracks.any((x) => x.id == t.id))
        .toList()
      ..sort((a, b) {
        final artist = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        if (artist != 0) return artist;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
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
    await widget.player.setQueue(
      tracks,
      startIndex: index,
      preserveCurrent: false,
    );
    await widget.player.play();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.name), actions: [
      IconButton(onPressed: _add, icon: const Icon(Icons.add), tooltip: 'Titel hinzufügen'),
    ]),
    body: tracks.isEmpty
        ? const Center(child: Text('Playlist ist leer. + öffnet die Bibliothek.'))
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
