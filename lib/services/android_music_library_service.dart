import 'dart:io';

import 'package:flutter/services.dart';

import '../models/track.dart';

class AndroidMusicLibraryService {
  static const _channel = MethodChannel('de.glasi.mp3byglasi/storage');

  Future<List<Track>> getMusicTracks() async {
    if (!Platform.isAndroid) return const [];

    try {
      final raw = await _channel.invokeListMethod<dynamic>('getMusicTracks');
      if (raw == null) return const [];

      final tracks = <Track>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final path = (map['path'] as String?)?.trim();
        if (path == null || path.isEmpty) continue;

        final fallbackTitle = _filename(path);
        final title = _clean(map['title'] as String?) ?? fallbackTitle;
        final artist = _clean(map['artist'] as String?) ?? 'Unbekannt';
        final album = _clean(map['album'] as String?) ?? 'Unbekannt';
        final durationMs = (map['durationMs'] as num?)?.toInt();
        final year = (map['year'] as num?)?.toInt();
        final trackNumber = (map['trackNumber'] as num?)?.toInt();

        tracks.add(
          Track(
            id: path,
            path: path,
            title: title,
            artist: artist,
            album: album,
            duration: durationMs == null || durationMs <= 0
                ? null
                : Duration(milliseconds: durationMs),
            year: year == null || year <= 0 ? null : year,
            trackNumber: trackNumber == null || trackNumber <= 0
                ? null
                : trackNumber,
          ),
        );
      }
      return tracks;
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Musikbibliothek konnte nicht gelesen werden.',
      );
    }
  }

  String? _clean(String? value) {
    final cleaned = value?.trim();
    if (cleaned == null ||
        cleaned.isEmpty ||
        cleaned == '<unknown>') {
      return null;
    }
    return cleaned;
  }

  String _filename(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
