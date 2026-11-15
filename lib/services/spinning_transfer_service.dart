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

class SpinningCsvImportResult {
  final Map<String, bool> selected;
  final Map<String, Set<SpinningPhase>> phases;
  final List<String> unmatched;
  const SpinningCsvImportResult(this.selected, this.phases, this.unmatched);
  int get matchedCount => selected.length;
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


  static const csvPhases = <SpinningPhase>[
    SpinningPhase.warmup, SpinningPhase.build, SpinningPhase.load,
    SpinningPhase.peak, SpinningPhase.recovery, SpinningPhase.cooldown,
  ];
  // Keep the columns people edit first. The final ID and path columns
  // are for reliable round-trip matching, not for spreadsheet editing.
  static const csvColumns = <String>[
    'Interpret', 'Album', 'Titel', 'DauerSekunden', 'BPM',
    'Spinning', 'Warm-up', 'Aufbau', 'Belastung', 'Peak',
    'Erholung', 'Cool-down', 'ID', 'Pfad',
  ];
  static const csvPhaseColumns = <String>[
    'Warm-up', 'Aufbau', 'Belastung', 'Peak', 'Erholung', 'Cool-down',
  ];

  String exportLibraryCsv({
    required List<Track> library,
    required Set<String> spinningTrackIds,
    required Map<String, Set<SpinningPhase>> phasesByTrackId,
  }) {
    final rows = <List<String>>[
      csvColumns,
      for (final track in library)
        [
          track.artist, track.album, track.title,
          track.duration?.inSeconds.toString() ?? '',
          track.bpm?.toStringAsFixed(1) ?? '',
          spinningTrackIds.contains(track.id) ? '1' : '0',
          for (final phase in csvPhases)
            phasesByTrackId[track.id]?.contains(phase) == true ? '1' : '0',
          track.id, track.path,
        ],
    ];
    return '\uFEFF${rows.map((r) => r.map(_escapeCsv).join(';')).join('\r\n')}\r\n';
  }

  SpinningCsvImportResult importLibraryCsv(String raw, List<Track> library) {
    final rows = _parseCsv(raw.replaceFirst('\uFEFF', ''));
    if (rows.length < 2) throw const FormatException('CSV enthält keine Titel.');
    final columns = rows.first.map((v) => v.trim()).toList();
    // Also accept exports from earlier versions (with Jahr and Nummer).
    // Resolve by header, not by position, so reordering Excel columns is safe.
    if (!csvColumns.every(columns.contains)) {
      throw const FormatException('Unbekanntes CSV-Format. Bitte Bibliotheks-Export verwenden.');
    }
    final indices = <String, int>{for (var i = 0; i < columns.length; i++) columns[i]: i};
    String field(List<String> row, String key) =>
        indices[key]! < row.length ? row[indices[key]!].trim() : '';
    bool flag(String raw) {
      switch (raw.toLowerCase()) {
        case '1': case 'ja': case 'yes': case 'true': case 'x': return true;
        case '0': case 'nein': case 'no': case 'false': case '': return false;
        default: throw FormatException('Ungültiger Wert "$raw": nur 1 oder 0 verwenden.');
      }
    }
    final byId = {for (final t in library) t.id: t};
    final byPath = <String, List<Track>>{};
    final byMetadata = <String, List<Track>>{};
    for (final t in library) {
      byPath.putIfAbsent(t.path.toLowerCase(), () => []).add(t);
      byMetadata.putIfAbsent(
        '${_artistTitleKey(t.artist, t.title)}|${_normalizeText(t.album)}',
        () => [],
      ).add(t);
    }
    final selected = <String, bool>{};
    final phases = <String, Set<SpinningPhase>>{};
    final unmatched = <String>[];
    for (final row in rows.skip(1)) {
      if (row.every((v) => v.trim().isEmpty)) continue;
      Track? match = byId[field(row, 'ID')];
      if (match == null) {
        final path = field(row, 'Pfad').toLowerCase();
        final candidates = byPath[path] ?? [];
        if (path.isNotEmpty && candidates.length == 1) match = candidates.single;
      }
      if (match == null) {
        final key = '${_artistTitleKey(field(row, 'Interpret'), field(row, 'Titel'))}|${_normalizeText(field(row, 'Album'))}';
        final candidates = byMetadata[key] ?? [];
        if (candidates.length == 1) match = candidates.single;
      }
      if (match == null) {
        unmatched.add("${field(row, 'Interpret')} - ${field(row, 'Titel')}");
        continue;
      }
      final marked = flag(field(row, 'Spinning'));
      final choices = <SpinningPhase>{};
      for (var i = 0; i < csvPhases.length; i++) {
        if (flag(field(row, csvPhaseColumns[i]))) choices.add(csvPhases[i]);
      }
      if (selected.containsKey(match.id)) {
        throw FormatException('Doppelter Titel: ${match.artist} - ${match.title}');
      }
      selected[match.id] = marked;
      phases[match.id] = marked ? choices : <SpinningPhase>{};
    }
    return SpinningCsvImportResult(selected, phases, unmatched);
  }

  String _escapeCsv(String cell) => '"${cell.replaceAll('"', '""')}"';

  List<List<String>> _parseCsv(String raw) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (char == '"') {
        if (quoted && i + 1 < raw.length && raw[i + 1] == '"') {
          cell.write('"'); i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ';' && !quoted) {
        row.add(cell.toString()); cell = StringBuffer();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' && i + 1 < raw.length && raw[i + 1] == '\n') i++;
        row.add(cell.toString()); cell = StringBuffer();
        if (row.any((value) => value.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(char);
      }
    }
    if (quoted) throw const FormatException('CSV-Anführungszeichen nicht geschlossen.');
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString()); rows.add(row);
    }
    return rows;
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
