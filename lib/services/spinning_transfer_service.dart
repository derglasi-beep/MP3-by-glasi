import 'dart:convert';
import 'dart:io';

import '../models/track.dart';
import 'spinning_playlist_service.dart';

class SpinningImportResult {
  final Map<String, Set<SpinningPhase>> matched;
  final List<String> unmatched;

  const SpinningImportResult({
    required this.matched,
    required this.unmatched,
  });

  int get matchedCount => matched.length;
}

class SpinningTransferService {
  static const format = 'mp3-by-glasi-spinning';
  static const version = 1;

  String exportProfile({
    required List<Track> library,
    required Set<String> spinningTrackIds,
    required Map<String, Set<SpinningPhase>> phasesByTrackId,
  }) {
    final selected = library
        .where((track) => spinningTrackIds.contains(track.id))
        .toList(growable: false);

    final payload = <String, dynamic>{
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'tracks': [
        for (final track in selected)
          <String, dynamic>{
            'artist': track.artist,
            'title': track.title,
            'album': track.album,
            'year': track.year,
            'durationMs': track.duration?.inMilliseconds,
            'phases': [
              for (final phase in SpinningPhase.values)
                if (phasesByTrackId[track.id]?.contains(phase) == true)
                  phase.name,
            ],
          },
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<SpinningImportResult> importFile(
    File file,
    List<Track> library,
  ) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Ungültige Spinning-Datei.');
    }

    final root = Map<String, dynamic>.from(decoded);
    if (root['format'] != format) {
      throw const FormatException(
        'Die Datei ist kein MP3-by-Glasi-Spinning-Export.',
      );
    }

    final fileVersion = (root['version'] as num?)?.toInt();
    if (fileVersion != version) {
      throw FormatException(
        'Spinning-Dateiversion $fileVersion wird nicht unterstützt.',
      );
    }

    final entries = root['tracks'];
    if (entries is! List) {
      throw const FormatException('Spinning-Datei enthält keine Titelliste.');
    }

    final byArtistTitle = <String, List<Track>>{};
    for (final track in library) {
      byArtistTitle
          .putIfAbsent(
            _artistTitleKey(track.artist, track.title),
            () => <Track>[],
          )
          .add(track);
    }

    final matched = <String, Set<SpinningPhase>>{};
    final unmatched = <String>[];

    for (final rawEntry in entries) {
      if (rawEntry is! Map) continue;
      final entry = Map<String, dynamic>.from(rawEntry);
      final artist = entry['artist']?.toString().trim() ?? '';
      final title = entry['title']?.toString().trim() ?? '';
      final album = entry['album']?.toString().trim() ?? '';
      final year = (entry['year'] as num?)?.toInt();
      final durationMs = (entry['durationMs'] as num?)?.toInt();

      if (artist.isEmpty || title.isEmpty) {
        unmatched.add(
          [artist, title].where((value) => value.isNotEmpty).join(' - '),
        );
        continue;
      }

      final candidates = List<Track>.from(
        byArtistTitle[_artistTitleKey(artist, title)] ?? const <Track>[],
      );

      Track? match;
      if (candidates.length == 1) {
        match = candidates.first;
      } else if (candidates.length > 1) {
        final albumMatches = album.isEmpty
            ? candidates
            : candidates
                .where(
                  (track) => _normalizeText(track.album) == _normalizeText(album),
                )
                .toList(growable: false);

        final narrowed = albumMatches.isNotEmpty ? albumMatches : candidates;
        if (narrowed.length == 1) {
          match = narrowed.first;
        } else {
          final detailMatches = narrowed.where((track) {
            final yearFits = year == null || track.year == null || track.year == year;
            final durationFits = durationMs == null ||
                track.duration == null ||
                (track.duration!.inMilliseconds - durationMs).abs() <= 3000;
            return yearFits && durationFits;
          }).toList(growable: false);
          if (detailMatches.length == 1) match = detailMatches.first;
        }
      }

      if (match == null) {
        unmatched.add('$artist - $title');
        continue;
      }

      final phases = <SpinningPhase>{};
      final rawPhases = entry['phases'];
      if (rawPhases is List) {
        for (final value in rawPhases) {
          final name = value.toString();
          for (final phase in SpinningPhase.values) {
            if (phase.name == name) {
              phases.add(phase);
              break;
            }
          }
        }
      }
      matched[match.id] = phases;
    }

    return SpinningImportResult(
      matched: matched,
      unmatched: unmatched,
    );
  }

  String _artistTitleKey(String artist, String title) =>
      '${_normalizeText(artist)}|${_normalizeText(title)}';

  String _normalizeText(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9äöüß]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
