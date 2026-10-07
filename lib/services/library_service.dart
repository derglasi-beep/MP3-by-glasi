import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

class LibraryService {
  static const _tracksKey = 'library_tracks_v1';
  static const _playlistsKey = 'library_playlists_v1';
  static const _libraryFileName = 'library_tracks_v2.json';

  Future<void> _trackSaveTail = Future.value();

  Future<File> _libraryFile() async {
    final support = await getApplicationSupportDirectory();
    return File(
      '${support.path}${Platform.pathSeparator}$_libraryFileName',
    );
  }

  Future<Directory> _artworkDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}artwork',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _artworkFileName(String id) {
    final bytes = utf8.encode(id);
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '${hash.toRadixString(16)}.img';
  }

  Future<List<Track>> loadTracks() async {
    String? raw;
    final file = await _libraryFile();

    if (await file.exists()) {
      try {
        raw = await file.readAsString();
      } catch (_) {
        raw = null;
      }
    }

    // One-time migration from the old SharedPreferences library.
    if (raw == null || raw.isEmpty) {
      final p = await SharedPreferences.getInstance();
      raw = p.getString(_tracksKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          await _writeLibraryFile(file, raw);
        } catch (_) {
          // Keep using the legacy copy if migration cannot be written yet.
        }
      }
    }

    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List;
      final artworkDirectory =
          Platform.isAndroid ? null : await _artworkDirectory();
      final tracks = <Track>[];

      for (final entry in list) {
        final json = Map<String, dynamic>.from(entry as Map);
        Uint8List? artwork;

        // On Android the library must restore quickly even with 10k+ tracks.
        // Artwork loading is intentionally skipped here and can be handled
        // separately/lazily later.
        if (artworkDirectory != null) {
          final id = json['id'] as String;
          final artworkFile = File(
            '${artworkDirectory.path}${Platform.pathSeparator}${_artworkFileName(id)}',
          );

          if (await artworkFile.exists()) {
            artwork = await artworkFile.readAsBytes();
          } else if (json['artwork'] is String &&
              (json['artwork'] as String).isNotEmpty) {
            artwork = base64Decode(json['artwork'] as String);
          }
        }

        tracks.add(_trackFromJson(json, artwork: artwork));
      }

      return tracks;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTracks(List<Track> tracks) {
    final snapshot = List<Track>.from(tracks);
    _trackSaveTail = _trackSaveTail.then((_) => _saveTracksNow(snapshot));
    return _trackSaveTail;
  }

  Future<void> _saveTracksNow(List<Track> tracks) async {
    final artworkDirectory = await _artworkDirectory();
    final liveArtworkFiles = <String>{};

    for (final track in tracks) {
      final fileName = _artworkFileName(track.id);
      liveArtworkFiles.add(fileName);

      final artwork = track.artwork;
      if (artwork == null || artwork.isEmpty) continue;

      final file = File(
        '${artworkDirectory.path}${Platform.pathSeparator}$fileName',
      );

      if (!await file.exists()) {
        await file.writeAsBytes(artwork, flush: false);
      }
    }

    await for (final entity in artworkDirectory.list()) {
      if (entity is File &&
          entity.path.endsWith('.img') &&
          !liveArtworkFiles.contains(entity.uri.pathSegments.last)) {
        try {
          await entity.delete();
        } catch (_) {
          // A stale artwork file is harmless and can be retried next save.
        }
      }
    }

    final raw = jsonEncode(tracks.map(_trackToJson).toList());
    final file = await _libraryFile();
    await _writeLibraryFile(file, raw);

    // The file is now the authoritative library store. Remove the large
    // legacy SharedPreferences value after a successful write.
    final p = await SharedPreferences.getInstance();
    await p.remove(_tracksKey);
  }

  Future<void> _writeLibraryFile(File file, String raw) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(raw, flush: true);

    try {
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
    } catch (_) {
      await file.writeAsString(raw, flush: true);
      if (await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  Future<Map<String, List<String>>> loadPlaylists() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_playlistsKey);
    if (raw == null) return {};
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw));
      return data.map((k, v) => MapEntry(k, List<String>.from(v as List)));
    } catch (_) {
      return {};
    }
  }

  Future<void> savePlaylists(Map<String, List<String>> playlists) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_playlistsKey, jsonEncode(playlists));
  }

  Map<String, dynamic> _trackToJson(Track t) => {
        'id': t.id,
        'path': t.path,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'year': t.year,
        'durationMs': t.duration?.inMilliseconds,
        'bpm': t.bpm,
        'bpmConfidence': t.bpmConfidence,
      };

  Track _trackFromJson(
    Map<String, dynamic> j, {
    List<int>? artwork,
  }) =>
      Track(
        id: j['id'] as String,
        path: j['path'] as String,
        title: j['title'] as String? ?? 'Unbekannt',
        artist: j['artist'] as String? ?? 'Unbekannt',
        album: j['album'] as String? ?? 'Unbekannt',
        year: (j['year'] as num?)?.toInt(),
        duration: (j['durationMs'] as num?) == null
            ? null
            : Duration(milliseconds: (j['durationMs'] as num).toInt()),
        bpm: (j['bpm'] as num?)?.toDouble(),
        bpmConfidence: (j['bpmConfidence'] as num?)?.toDouble(),
        artwork: artwork == null ? null : Uint8List.fromList(artwork),
      );
}
