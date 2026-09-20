import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/bpm_service.dart';
import '../services/bpm_cache.dart';
import '../services/music_scanner.dart';
import '../widgets/bpm_badge.dart';

class PlayerScreen extends StatefulWidget {
  final AudioPlayerService player;
  const PlayerScreen({super.key, required this.player});
  @override State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final scanner = MusicScanner();
  final bpm = BpmService();
  final bpmCache = BpmCache();
  List<Track> tracks = [];
  String search = '';
  bool analyzing = false;
  double volume = .8;

  List<Track> get visible => tracks.where((t) {
    final q = search.toLowerCase().trim();
    return q.isEmpty || t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q) || t.album.toLowerCase().contains(q);
  }).toList();

  Future<void> addFiles() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowMultiple: true, allowedExtensions: ['mp3','flac','wav','m4a','mp4','ogg','opus','ape']);
    if (r == null) return;
    await _add(await scanner.scanFiles(r.files.where((f) => f.path != null).map((f) => File(f.path!))));
  }

  Future<void> addFolder() async {
    final p = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Musikordner auswählen');
    if (p != null) await _add(await scanner.scanDirectory(p));
  }

  Future<void> _add(List<Track> found) async {
    final map = {for (final t in tracks) t.id: t};
    for (final t in found) map[t.id] = t;
    final merged = map.values.toList();
    final hydrated = <Track>[];
    for (final t in merged) {
      final cachedBpm = t.bpm ?? await bpmCache.get(t.path);
      hydrated.add(cachedBpm == null ? t : t.copyWith(bpm: cachedBpm));
    }
    setState(() => tracks = hydrated);
    await widget.player.setQueue(tracks);
  }

  Future<void> analyze() async {
    final t = widget.player.currentTrack;
    if (t == null || analyzing) return;
    setState(() => analyzing = true);
    final cached = await bpmCache.get(t.path);
    final value = cached ?? await bpm.analyzeFile(t.path);
    if (cached == null && value != null) await bpmCache.put(t.path, value);
    if (!mounted) return;
    setState(() {
      analyzing = false;
      final i = tracks.indexWhere((x) => x.id == t.id);
      if (i >= 0 && value != null) tracks[i] = tracks[i].copyWith(bpm: value);
    });
  }

  String time(Duration d) => d.inMinutes.toString() + ':' + (d.inSeconds % 60).toString().padLeft(2,'0');

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MP3 by Glasi'), actions: [
      IconButton(onPressed: addFiles, icon: const Icon(Icons.library_music), tooltip: 'Dateien hinzufügen'),
      IconButton(onPressed: addFolder, icon: const Icon(Icons.folder_open), tooltip: 'Ordner scannen'),
    ]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() => search=v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Titel, Interpret oder Album', border: OutlineInputBorder()))),
      Expanded(flex: 5, child: _player()),
      const Divider(height: 1),
      Expanded(flex: 5, child: ListView.builder(itemCount: visible.length, itemBuilder: (_, i) {
        final t = visible[i];
        return ListTile(selected: widget.player.currentTrack?.id == t.id,
          leading: t.artwork == null ? const CircleAvatar(child: Icon(Icons.music_note)) : Image.memory(t.artwork!, width: 48, height: 48, fit: BoxFit.cover),
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(t.artist + ' • ' + t.album, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: BpmBadge(bpm: t.bpm),
          onTap: () async { final n=tracks.indexWhere((x)=>x.id==t.id); await widget.player.setQueue(tracks,startIndex:n); await widget.player.play(); setState((){}); },
        );
      }))
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
          final t=current.data; final d=dur.data ?? t?.duration ?? Duration.zero; final p=pos.data ?? Duration.zero;
          final max=d.inMilliseconds > 0 ? d.inMilliseconds.toDouble() : 1; final value=p.inMilliseconds.clamp(0,max.toInt()).toDouble();
          return SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(children: [
            SizedBox(width: 170,height:170,child:t?.artwork==null ? const Card(child: Icon(Icons.album,size:90)) : Image.memory(t!.artwork!,fit:BoxFit.cover)),
            const SizedBox(height:8), Text(t?.title ?? 'Keine Wiedergabe',style:Theme.of(context).textTheme.headlineSmall,textAlign:TextAlign.center),
            Text(t?.artist ?? 'Lokale Bibliothek'),
            const SizedBox(height:8), Row(mainAxisAlignment:MainAxisAlignment.center,children:[BpmBadge(bpm:t?.bpm,loading:analyzing),const SizedBox(width:8),FilledButton.tonalIcon(onPressed:t==null?null:analyze,icon:const Icon(Icons.speed),label:const Text('BPM'))]),
            Slider(value:value,max:max,onChanged:(v)=>widget.player.seek(Duration(milliseconds:v.toInt()))),
            Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(time(p)),Text(time(d))]),
            Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              IconButton(onPressed:widget.player.toggleShuffle,color:widget.player.shuffle?Theme.of(context).colorScheme.primary:null,icon:const Icon(Icons.shuffle),tooltip:'Zufallswiedergabe'),
              IconButton(onPressed:widget.player.previous,icon:const Icon(Icons.skip_previous),iconSize:38),
              IconButton(onPressed:t==null?null:((ps.data?.playing??false)?widget.player.pause:widget.player.play),icon:Icon((ps.data?.playing??false)?Icons.pause_circle:Icons.play_circle),iconSize:66),
              IconButton(onPressed:widget.player.next,icon:const Icon(Icons.skip_next),iconSize:38),
              IconButton(onPressed:widget.player.toggleRepeat,color:widget.player.loopMode!=LoopMode.off?Theme.of(context).colorScheme.primary:null,icon:Icon(widget.player.loopMode==LoopMode.one?Icons.repeat_one:Icons.repeat),tooltip:'Wiederholung'),
            ]),
            Row(children:[const Icon(Icons.volume_down),Expanded(child:Slider(value:volume,onChanged:(v){setState(()=>volume=v);widget.player.setVolume(v);})),const Icon(Icons.volume_up)])
          ]));
          },
        ),
      ),
    ),
  );
}
