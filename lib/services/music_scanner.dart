import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import '../models/track.dart';

class MusicScanner {
  static const extensions = {'.mp3','.flac','.wav','.m4a','.mp4','.ogg','.opus','.aif','.aiff','.ape'};

  Future<List<Track>> scanFiles(Iterable<File> files) async {
    final result = <Track>[];
    for (final file in files) {
      if (!extensions.contains(_extension(file.path))) continue;
      result.add(_readTrack(file));
    }
    result.sort((a,b) => (a.artist + a.title).toLowerCase().compareTo((b.artist + b.title).toLowerCase()));
    return result;
  }

  Future<List<Track>> scanDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return const [];
    return scanFiles(dir.listSync(recursive: true, followLinks: false).whereType<File>());
  }

  Track _readTrack(File file) {
    try {
      final m = readMetadata(file, getImage: true);
      return Track(
        id: file.path, path: file.path,
        title: m.title?.trim().isNotEmpty == true ? m.title!.trim() : _filename(file.path),
        artist: m.artist?.trim().isNotEmpty == true ? m.artist!.trim() : 'Unbekannt',
        album: m.album?.trim().isNotEmpty == true ? m.album!.trim() : 'Unbekannt',
        year: m.year?.year, duration: m.duration,
        artwork: m.pictures.isNotEmpty ? m.pictures.first.data : null,
      );
    } catch (_) {
      return Track(id: file.path, path: file.path, title: _filename(file.path));
    }
  }

  String _extension(String p) { final i = p.lastIndexOf('.'); return i < 0 ? '' : p.substring(i).toLowerCase(); }
  String _filename(String p) { final n = p.replaceAll('\\\\','/').split('/').last; final i = n.lastIndexOf('.'); return i > 0 ? n.substring(0,i) : n; }
}
