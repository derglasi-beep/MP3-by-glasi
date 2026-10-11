import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

class LyricsEntry {
  final String text;
  final String source;

  const LyricsEntry({
    required this.text,
    required this.source,
  });
}

class LyricsService {
  static const _userAgent =
      'MP3 by Glasi/0.3.0 (https://github.com/derglasi-beep/MP3-by-glasi)';

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}lyrics',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _fileName(String trackId) =>
      '${sha1.convert(utf8.encode(trackId))}.json';

  Future<File> _file(String trackId) async {
    final dir = await _directory();
    return File(
      '${dir.path}${Platform.pathSeparator}${_fileName(trackId)}',
    );
  }

  Future<LyricsEntry?> load(String trackId) async {
    try {
      final file = await _file(trackId);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;

      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final text = (data['text'] as String? ?? '').trim();
      if (text.isEmpty) return null;

      return LyricsEntry(
        text: text,
        source: (data['source'] as String? ?? 'Gespeichert').trim(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    String trackId,
    String text, {
    required String source,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      await clear(trackId);
      return;
    }

    final file = await _file(trackId);
    final temp = File('${file.path}.tmp');
    final raw = jsonEncode({
      'text': cleaned,
      'source': source,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    await temp.writeAsString(raw, flush: true);
    try {
      if (await file.exists()) await file.delete();
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

  Future<void> clear(String trackId) async {
    try {
      final file = await _file(trackId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<LyricsEntry?> searchOnline(Track track) async {
    final direct = await _getLrclib(track);
    if (direct != null) return direct;

    final lrclibSearch = await _searchLrclib(track);
    if (lrclibSearch != null) return lrclibSearch;

    return _getLyricsOvh(track);
  }

  Future<LyricsEntry?> _getLrclib(Track track) async {
    final params = <String, String>{
      'track_name': track.title,
      'artist_name': track.artist,
    };

    final album = track.album.trim();
    if (album.isNotEmpty &&
        album.toLowerCase() != 'unbekannt' &&
        album.toLowerCase() != 'unknown') {
      params['album_name'] = album;
    }

    final seconds = track.duration?.inSeconds;
    if (seconds != null && seconds >= 1 && seconds <= 3600) {
      params['duration'] = seconds.toString();
    }

    final uri = Uri.https('lrclib.net', '/api/get', params);
    final response = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 404) return null;
    if (response.statusCode == 429) {
      throw Exception('Lyrics-Dienst ist gerade ausgelastet. Bitte später erneut versuchen.');
    }
    if (response.statusCode != 200) return null;

    final data = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map,
    );
    return _entryFromLrclib(data);
  }

  Future<LyricsEntry?> _searchLrclib(Track track) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': track.title,
      'artist_name': track.artist,
    });
    final response = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 12));

    if (response.statusCode == 429) {
      throw Exception('Lyrics-Dienst ist gerade ausgelastet. Bitte später erneut versuchen.');
    }
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List || decoded.isEmpty) return null;

    for (final item in decoded) {
      if (item is! Map) continue;
      final entry = _entryFromLrclib(
        Map<String, dynamic>.from(item),
      );
      if (entry != null) return entry;
    }
    return null;
  }

  Future<LyricsEntry?> _getLyricsOvh(Track track) async {
    final artist = track.artist.trim();
    final title = track.title.trim();
    if (artist.isEmpty ||
        title.isEmpty ||
        artist.toLowerCase() == 'unbekannt' ||
        artist.toLowerCase() == 'unknown') {
      return null;
    }

    final uri = Uri.https(
      'api.lyrics.ovh',
      '/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}',
    );

    try {
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 404) return null;
      if (response.statusCode == 429) {
        throw Exception(
          'Lyrics-Dienst ist gerade ausgelastet. Bitte später erneut versuchen.',
        );
      }
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;

      final lyrics = (decoded['lyrics'] as String? ?? '').trim();
      if (lyrics.isEmpty) return null;

      return LyricsEntry(
        text: lyrics,
        source: 'Lyrics.ovh',
      );
    } catch (error) {
      if (error is Exception &&
          error.toString().contains('ausgelastet')) {
        rethrow;
      }
      return null;
    }
  }

  LyricsEntry? _entryFromLrclib(Map<String, dynamic> data) {
    if (data['instrumental'] == true) {
      return const LyricsEntry(
        text: 'Instrumental – keine Lyrics vorhanden.',
        source: 'LRCLIB',
      );
    }

    var text = (data['plainLyrics'] as String? ?? '').trim();
    if (text.isEmpty) {
      text = _plainFromSynced(
        (data['syncedLyrics'] as String? ?? '').trim(),
      );
    }
    if (text.isEmpty) return null;

    return LyricsEntry(
      text: text,
      source: 'LRCLIB',
    );
  }

  String _plainFromSynced(String value) {
    if (value.isEmpty) return '';
    final timestamp = RegExp(r'^\[\d{2}:\d{2}(?:\.\d+)?\]\s*');
    return value
        .split('\n')
        .map((line) => line.replaceFirst(timestamp, '').trimRight())
        .join('\n')
        .trim();
  }
}
