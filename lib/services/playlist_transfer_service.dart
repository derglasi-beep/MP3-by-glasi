import 'dart:convert';
import 'dart:io';

import '../models/track.dart';

class PlaylistImportEntry {
  final String raw;
  final String? artist;
  final String? title;
  final String? path;

  const PlaylistImportEntry({
    required this.raw,
    this.artist,
    this.title,
    this.path,
  });
}

class PlaylistImportResult {
  final List<Track> matched;
  final List<PlaylistImportEntry> unmatched;

  const PlaylistImportResult({
    required this.matched,
    required this.unmatched,
  });
}

class PlaylistTransferService {
  Future<PlaylistImportResult> importFile(
    File file,
    List<Track> library,
  ) async {
    final raw = await file.readAsString();
    final extension = _extension(file.path);
    final entries = switch (extension) {
      'm3u' || 'm3u8' => _parseM3u(raw),
      'csv' => _parseCsv(raw),
      _ => _parseTxt(raw),
    };
    return matchEntries(entries, library);
  }

  PlaylistImportResult matchEntries(
    List<PlaylistImportEntry> entries,
    List<Track> library,
  ) {
    final byPath = <String, Track>{};
    final byArtistTitle = <String, List<Track>>{};

    for (final track in library) {
      final normalizedPath = _normalizePath(track.path);
      if (normalizedPath.isNotEmpty) {
        byPath[normalizedPath] = track;
      }

      final key = _artistTitleKey(track.artist, track.title);
      byArtistTitle.putIfAbsent(key, () => <Track>[]).add(track);
    }

    final matched = <Track>[];
    final unmatched = <PlaylistImportEntry>[];
    final used = <String>{};

    for (final entry in entries) {
      Track? match;

      final path = entry.path;
      if (path != null && path.trim().isNotEmpty) {
        match = byPath[_normalizePath(path)];
      }

      if (match == null && entry.artist != null && entry.title != null) {
        final candidates = byArtistTitle[
          _artistTitleKey(entry.artist!, entry.title!)
        ];
        if (candidates != null && candidates.length == 1) {
          match = candidates.first;
        }
      }

      if (match == null) {
        final parsed = _splitArtistTitle(entry.raw);
        if (parsed != null) {
          final candidates = byArtistTitle[
            _artistTitleKey(parsed.$1, parsed.$2)
          ];
          if (candidates != null && candidates.length == 1) {
            match = candidates.first;
          }
        }
      }

      if (match == null) {
        unmatched.add(entry);
        continue;
      }

      if (used.add(match.id)) {
        matched.add(match);
      }
    }

    return PlaylistImportResult(
      matched: matched,
      unmatched: unmatched,
    );
  }

  String exportTxt(List<Track> tracks) => tracks
      .map((track) => '${track.artist} - ${track.title}')
      .join('\n');

  String exportCsv(List<Track> tracks) {
    final lines = <String>['artist,title,album,path'];
    for (final track in tracks) {
      lines.add([
        track.artist,
        track.title,
        track.album,
        track.path,
      ].map(_csvField).join(','));
    }
    return lines.join('\n');
  }

  String exportM3u(List<Track> tracks) {
    final lines = <String>['#EXTM3U'];
    for (final track in tracks) {
      final duration = track.duration?.inSeconds ?? -1;
      lines.add('#EXTINF:$duration,${track.artist} - ${track.title}');
      lines.add(track.path);
    }
    return lines.join('\n');
  }

  List<PlaylistImportEntry> _parseTxt(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) {
          final split = _splitArtistTitle(line);
          return PlaylistImportEntry(
            raw: line,
            artist: split?.$1,
            title: split?.$2,
          );
        })
        .toList(growable: false);
  }

  List<PlaylistImportEntry> _parseM3u(String raw) {
    final entries = <PlaylistImportEntry>[];
    String? pendingLabel;

    for (final sourceLine in raw.split(RegExp(r'\r?\n'))) {
      final line = sourceLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        final comma = line.indexOf(',');
        pendingLabel = comma >= 0 ? line.substring(comma + 1).trim() : null;
        continue;
      }

      if (line.startsWith('#')) continue;

      final split = pendingLabel == null
          ? null
          : _splitArtistTitle(pendingLabel!);
      entries.add(
        PlaylistImportEntry(
          raw: pendingLabel?.isNotEmpty == true ? pendingLabel! : line,
          artist: split?.$1,
          title: split?.$2,
          path: line,
        ),
      );
      pendingLabel = null;
    }

    return entries;
  }

  List<PlaylistImportEntry> _parseCsv(String raw) {
    final rows = raw
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .map(_parseCsvLine)
        .toList(growable: false);

    if (rows.isEmpty) return const [];

    final header = rows.first.map((value) => value.trim().toLowerCase()).toList();
    final artistIndex = header.indexOf('artist');
    final titleIndex = header.indexOf('title');
    final pathIndex = header.indexOf('path');

    final hasHeader = artistIndex >= 0 || titleIndex >= 0 || pathIndex >= 0;
    final start = hasHeader ? 1 : 0;
    final entries = <PlaylistImportEntry>[];

    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      if (hasHeader) {
        String? valueAt(int index) =>
            index >= 0 && index < row.length ? row[index].trim() : null;

        final artist = valueAt(artistIndex);
        final title = valueAt(titleIndex);
        final path = valueAt(pathIndex);
        entries.add(
          PlaylistImportEntry(
            raw: row.join(' | '),
            artist: artist?.isEmpty == true ? null : artist,
            title: title?.isEmpty == true ? null : title,
            path: path?.isEmpty == true ? null : path,
          ),
        );
        continue;
      }

      if (row.length >= 2) {
        entries.add(
          PlaylistImportEntry(
            raw: row.join(' | '),
            artist: row[0].trim(),
            title: row[1].trim(),
            path: row.length >= 4 ? row[3].trim() : null,
          ),
        );
      } else {
        final value = row.first.trim();
        final split = _splitArtistTitle(value);
        entries.add(
          PlaylistImportEntry(
            raw: value,
            artist: split?.$1,
            title: split?.$2,
          ),
        );
      }
    }

    return entries;
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    var quoted = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
        continue;
      }

      if (char == ',' && !quoted) {
        result.add(buffer.toString());
        buffer.clear();
        continue;
      }

      buffer.write(char);
    }

    result.add(buffer.toString());
    return result;
  }

  (String, String)? _splitArtistTitle(String value) {
    for (final separator in const [' - ', ' – ', ' — ', '\t']) {
      final index = value.indexOf(separator);
      if (index <= 0) continue;
      final artist = value.substring(0, index).trim();
      final title = value.substring(index + separator.length).trim();
      if (artist.isNotEmpty && title.isNotEmpty) return (artist, title);
    }
    return null;
  }

  String _artistTitleKey(String artist, String title) =>
      '${_normalizeText(artist)}|${_normalizeText(title)}';

  String _normalizeText(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9äöüß]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _normalizePath(String value) =>
      value.replaceAll('\\', '/').trim().toLowerCase();

  String _csvField(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _extension(String path) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }
}
