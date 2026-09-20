import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';

class LibraryService {
  static const _tracksKey = 'library_tracks_v1';
  static const _playlistsKey = 'library_playlists_v1';

  Future<List<Track>> loadTracks() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_tracksKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => _trackFromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTracks(List<Track> tracks) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_tracksKey, jsonEncode(tracks.map(_trackToJson).toList()));
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
    'id': t.id, 'path': t.path, 'title': t.title,
    'artist': t.artist, 'album': t.album, 'year': t.year,
    'durationMs': t.duration?.inMilliseconds, 'bpm': t.bpm, 'bpmConfidence': t.bpmConfidence,
    'artwork': t.artwork == null ? null : base64Encode(t.artwork!),
  };

  Track _trackFromJson(Map<String, dynamic> j) => Track(
    id: j['id'] as String,
    path: j['path'] as String,
    title: j['title'] as String? ?? 'Unbekannt',
    artist: j['artist'] as String? ?? 'Unbekannt',
    album: j['album'] as String? ?? 'Unbekannt',
    year: (j['year'] as num?)?.toInt(),
    duration: (j['durationMs'] as num?) == null ? null : Duration(milliseconds: (j['durationMs'] as num).toInt()),
    bpm: (j['bpm'] as num?)?.toDouble(),
    bpmConfidence: (j['bpmConfidence'] as num?)?.toDouble(),
    artwork: j['artwork'] is String && (j['artwork'] as String).isNotEmpty
        ? base64Decode(j['artwork'] as String)
        : null,
  );
}
