import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/bpm_service.dart';
import '../services/bpm_cache.dart';
import '../services/online_bpm_service.dart';
import '../services/bpm_fusion_service.dart';
import '../services/library_service.dart';
import '../services/music_scanner.dart';
import '../widgets/bpm_badge.dart';
import '../widgets/glasi_visualizer.dart';
import 'playlists_screen.dart';
import 'queue_screen.dart';
import 'now_playing_screen.dart';
import 'spinning_screen.dart';

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
  final onlineBpm = OnlineBpmService();
  final bpmFusion = BpmFusionService();
  final library = LibraryService();
  List<Track> tracks = [];

  String search = '';
  int? bpmMin;
  int? bpmMax;
  bool analyzing = false;
  int analyzedCount = 0;
  int analysisTotal = 0;
  double volume = .8;
  _SortMode sortMode = _SortMode.title;
  bool sortAscending = true;
  String? onlineBpmTrackId;
  OnlineBpmResult? onlineBpmResult;
  BpmFusionResult? bpmFusionResult;

  @override
  void initState() {
    super.initState();
    _restoreLibrary();
  }

  @override
  void dispose() {
    onlineBpm.dispose();
    super.dispose();
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
    ).where((t) {
      final tempo = t.bpm;
      if (tempo == null) return bpmMin == null && bpmMax == null;
      return (bpmMin == null || tempo >= bpmMin!) &&
          (bpmMax == null || tempo <= bpmMax!);
    }).toList();

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

  String _bpmLabel(double? value) => value == null ? '—' : '${value.round()} BPM';

  String _tempoDelta(Track? current, Track next) {
    if (current?.bpm == null || next.bpm == null || current!.bpm! <= 0) return 'BPM n/a';
    final delta = ((next.bpm! - current.bpm!) / current.bpm!) * 100;
    final sign = delta > 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)}% Tempo';
  }

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
      final cached = await bpmCache.get(t.path);
      hydrated.add(cached == null ? t : t.copyWith(bpm: cached.bpm, bpmConfidence: cached.confidence));
    }
    setState(() => tracks = hydrated);
    await library.saveTracks(tracks);
    await widget.player.setQueue(tracks);
  }

  Future<void> _analyzeTrack(Track t) async {
    if (analyzing) return;
    if (mounted) {
      setState(() {
        analyzing = true;
        onlineBpmTrackId = t.id;
        onlineBpmResult = null;
        bpmFusionResult = null;
      });
    }

    try {
      final cached = await bpmCache.get(t.path);
      final localResult = cached == null ? await bpm.analyzeFileResult(t.path) : null;
      final localValue = cached?.bpm ?? localResult?.bpm;
      if (localValue != null) {
        if (cached == null) await bpmCache.put(t.path, localValue, confidence: localResult?.confidence);
        _setBpm(t.id, localValue, localResult?.confidence ?? cached?.confidence);
      }

      final online = await onlineBpm.lookup(
        title: t.title,
        artist: t.artist,
        duration: t.duration,
      );
      final fusion = bpmFusion.fuse(
        localBpm: localValue,
        localConfidence: localResult?.confidence ?? cached?.confidence,
        online: online,
      );
      if (fusion.bpm > 0 && localValue != null) {
        _setBpm(t.id, fusion.bpm, fusion.confidence);
      }
      if (mounted && onlineBpmTrackId == t.id) {
        setState(() {
          onlineBpmResult = online;
          bpmFusionResult = fusion;
        });
      }
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  Future<void> _analyzeLibrary() async {
    if (analyzing || tracks.isEmpty) return;
    setState(() {
      analyzing = true;
      analyzedCount = 0;
      analysisTotal = tracks.length;
    });

    try {
      var changed = false;
      for (final track in List<Track>.from(tracks)) {
        if (!mounted) return;

        // High-confidence results are already stable. Lower-confidence or
        // legacy results get a fresh online verification pass.
        if (track.bpm != null && (track.bpmConfidence ?? 0) >= 0.75) {
          setState(() => analyzedCount++);
          continue;
        }

        final cached = await bpmCache.get(track.path);
        final localResult = track.bpm == null && cached == null
            ? await bpm.analyzeFileResult(track.path)
            : null;
        final value = track.bpm ?? cached?.bpm ?? localResult?.bpm;
        final localConfidence = track.bpmConfidence ?? cached?.confidence ?? localResult?.confidence;
        if (value != null) {
          if (track.bpm == null && cached == null) {
            await bpmCache.put(
              track.path,
              value,
              confidence: localResult?.confidence,
            );
          }
          final online = await onlineBpm.lookup(
            title: track.title,
            artist: track.artist,
            duration: track.duration,
          );
          final fusion = bpmFusion.fuse(
            localBpm: value,
            localConfidence: localConfidence,
            online: online,
          );
          final index = tracks.indexWhere((x) => x.id == track.id);
          if (index >= 0) {
            tracks[index] = tracks[index].copyWith(
              bpm: fusion.bpm,
              bpmConfidence: fusion.confidence,
            );
            changed = true;
          }
        }
        if (mounted) setState(() => analyzedCount++);
      }

      if (changed && mounted) {
        await library.saveTracks(List<Track>.from(tracks));
        await widget.player.setQueue(tracks);
        setState(() {});
      }
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  void _setBpm(String id, double value, double? confidence) {
    if (!mounted) return;
    setState(() {
      final i = tracks.indexWhere((x) => x.id == id);
      if (i >= 0) tracks[i] = tracks[i].copyWith(bpm: value, bpmConfidence: confidence);
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

  String _fusionLabel(BpmFusionResult result) {
    final confidence = (result.confidence * 100).round();
    if (result.possibleRemix) return '⚠ Mögliches Remix/Alternate-Take · gemeinsame Sicherheit $confidence%';
    switch (result.relation) {
      case BpmRelation.exact: return '✓ Lokal + Online bestätigt · Sicherheit $confidence%';
      case BpmRelation.halfTempo: return '↕ Halbtempo erkannt · Sicherheit $confidence%';
      case BpmRelation.doubleTempo: return '↕ Doppeltempo erkannt · Sicherheit $confidence%';
      case BpmRelation.close: return '≈ Nahe beieinander · Sicherheit $confidence%';
      case BpmRelation.mismatch: return '⚠ Unterschiedliche BPM · Sicherheit $confidence%';
      case BpmRelation.localOnly: return 'Lokal erkannt · Sicherheit $confidence%';
      case BpmRelation.onlineOnly: return 'Online erkannt · Sicherheit $confidence%';
    }
  }

  String time(Duration d) => '\${d.inMinutes}:\${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _playTrack(Track t) async {
    final n = tracks.indexWhere((x) => x.id == t.id);
    if (n < 0) return;

    final queueMatchesLibrary =
        widget.player.queue.length == tracks.length &&
        widget.player.queue.asMap().entries.every(
              (entry) => entry.value.id == tracks[entry.key].id,
            );

    if (!queueMatchesLibrary) {
      await widget.player.setQueue(tracks, startIndex: n);
    } else {
      await widget.player.playAt(n);
    }

    unawaited(_analyzeTrack(t));
    if (mounted) setState(() {});
  }

  Future<void> _openQueue() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => QueueScreen(player: widget.player)));
    if (mounted) setState(() {});
  }

  Future<void> _openPlaylists() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistsScreen(player: widget.player, tracks: tracks)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MP3 by Glasi'), actions: [
      IconButton(onPressed: _openQueue, icon: const Icon(Icons.queue_music), tooltip: 'Queue'),
      IconButton(onPressed: _openPlaylists, icon: const Icon(Icons.playlist_play), tooltip: 'Playlists'),
      IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpinningScreen(player: widget.player, tracks: tracks))), icon: const Icon(Icons.directions_bike), tooltip: 'Spinning DJ'),
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
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final zone in const <({String label, int? min, int? max})>[
              (label: 'Alle', min: null, max: null),
              (label: '120–130', min: 120, max: 130),
              (label: '130–140', min: 130, max: 140),
              (label: '140–150', min: 140, max: 150),
              (label: '150+', min: 150, max: null),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(zone.label),
                  selected: bpmMin == zone.min && bpmMax == zone.max,
                  onSelected: (_) => setState(() { bpmMin = zone.min; bpmMax = zone.max; }),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(children: [
          const Icon(Icons.sort, size: 20),
          const SizedBox(width: 8),
          Text('Sortierung: \${_sortLabel()}'),
          if (analyzing) ...[
            const SizedBox(width: 12),
            Text('\${analyzedCount}/\${analysisTotal}'),
          ],
          const Spacer(),
          IconButton(
            onPressed: () => setState(() => sortAscending = !sortAscending),
            tooltip: sortAscending ? 'Absteigend' : 'Aufsteigend',
            icon: Icon(sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
          ),
          IconButton(
            tooltip: 'BPM für Bibliothek analysieren',
            onPressed: analyzing || tracks.isEmpty ? null : _analyzeLibrary,
            icon: analyzing
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.speed),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (t.bpm != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(_bpmLabel(t.bpm), style: Theme.of(context).textTheme.labelLarge),
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'Queue-Aktion',
                        onSelected: (action) async {
                          if (action == 'next') await widget.player.playNext(t);
                          if (action == 'queue') await widget.player.addToQueue(t);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'next', child: Text('Als Nächstes abspielen')),
                          PopupMenuItem(value: 'queue', child: Text('An Queue anhängen')),
                        ],
                        icon: const Icon(Icons.more_vert),
                      ),
                    ],
                  ),
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
                GestureDetector(
                  onTap: t == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NowPlayingScreen(player: widget.player),
                            ),
                          ),
                  child: Hero(
                    tag: 'now-playing-cover',
                    child: SizedBox(
                      width: 170,
                      height: 170,
                      child: t?.artwork == null
                          ? const Card(child: Icon(Icons.album, size: 90))
                          : Image.memory(t!.artwork!, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(t?.title ?? 'Keine Wiedergabe',
                  style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                Text(t?.artist ?? 'Lokale Bibliothek'),
                if (t?.bpm != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Spinning: ${_bpmLabel(t!.bpm)}${t.bpmConfidence != null ? ' · Sicherheit ${(t.bpmConfidence! * 100).round()}%' : ''}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                const SizedBox(height: 6),
                GlasiVisualizer(playing: ps.data?.playing ?? false, bpm: t?.bpm),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  BpmBadge(bpm: t?.bpm, loading: analyzing && t != null && t.bpm == null),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: t == null ? null : () => _analyzeTrack(t),
                    icon: const Icon(Icons.speed), label: const Text('BPM')),
                ]),
                if (t != null && onlineBpmTrackId == t.id && onlineBpmResult != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Online: ${onlineBpmResult!.bpm.round()} BPM · ${onlineBpmResult!.source} · Treffer ${(onlineBpmResult!.matchScore * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  if (bpmFusionResult != null)
                    Text(
                      _fusionLabel(bpmFusionResult!),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                ],
                Slider(value: value, max: max,
                  onChanged: (v) => widget.player.seek(Duration(milliseconds: v.toInt()))),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(time(p)), Text(time(d))]),
                if (t != null && widget.player.queue.length > 1) ...[
                  const SizedBox(height: 4),
                  Builder(builder: (_) {
                    final index = widget.player.queue.indexWhere((x) => x.id == t.id);
                    final next = index >= 0 && index + 1 < widget.player.queue.length
                        ? widget.player.queue[index + 1]
                        : null;
                    return Text(
                      next == null ? 'Nächster Titel: Ende der Queue' : 'Nächster: ${next.title} · ${_tempoDelta(t, next)}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  }),
                ],
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
