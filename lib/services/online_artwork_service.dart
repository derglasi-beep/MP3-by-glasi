import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class OnlineArtworkResult {
  final Uint8List bytes;
  final String source;

  const OnlineArtworkResult({
    required this.bytes,
    required this.source,
  });
}

class OnlineArtworkService {
  final HttpClient _client;

  OnlineArtworkService({HttpClient? client}) : _client = client ?? HttpClient();

  Future<OnlineArtworkResult?> lookup({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    final cleanTitle = _clean(title);
    final cleanArtist = _clean(artist);
    if (cleanTitle.isEmpty ||
        cleanArtist.isEmpty ||
        cleanArtist == 'unbekannt') {
      return null;
    }

    final deezer = await _lookupDeezer(
      cleanTitle,
      cleanArtist,
      duration,
    );
    if (deezer != null) return deezer;

    return _lookupITunes(
      cleanTitle,
      cleanArtist,
      duration,
    );
  }

  Future<OnlineArtworkResult?> _lookupDeezer(
    String title,
    String artist,
    Duration? duration,
  ) async {
    try {
      final query = 'artist:"$artist" track:"$title"';
      final searchUri = Uri.https('api.deezer.com', '/search/track', {
        'q': query,
        'limit': '5',
      });

      final search = await _getJson(searchUri);
      final items = search?['data'];
      if (items is! List || items.isEmpty) return null;

      Map<String, dynamic>? best;
      var bestScore = 0.0;

      for (final item in items) {
        if (item is! Map) continue;
        final candidate = Map<String, dynamic>.from(item);
        final score = _matchScore(
          candidateTitle: candidate['title']?.toString() ?? '',
          candidateArtist: candidate['artist'] is Map
              ? (candidate['artist'] as Map)['name']?.toString() ?? ''
              : '',
          candidateDurationSeconds:
              (candidate['duration'] as num?)?.toDouble(),
          title: title,
          artist: artist,
          duration: duration,
        );
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }

      if (best == null || bestScore < 0.78) return null;

      final album = best['album'];
      if (album is! Map) return null;

      final coverUrl = album['cover_xl']?.toString() ??
          album['cover_big']?.toString() ??
          album['cover_medium']?.toString() ??
          album['cover']?.toString();
      if (coverUrl == null || coverUrl.isEmpty) return null;

      final bytes = await _download(Uri.parse(coverUrl));
      if (bytes == null) return null;
      return OnlineArtworkResult(bytes: bytes, source: 'Deezer');
    } catch (_) {
      return null;
    }
  }

  Future<OnlineArtworkResult?> _lookupITunes(
    String title,
    String artist,
    Duration? duration,
  ) async {
    try {
      final searchUri = Uri.https('itunes.apple.com', '/search', {
        'term': '$artist $title',
        'entity': 'song',
        'limit': '8',
      });

      final search = await _getJson(searchUri);
      final items = search?['results'];
      if (items is! List || items.isEmpty) return null;

      Map<String, dynamic>? best;
      var bestScore = 0.0;

      for (final item in items) {
        if (item is! Map) continue;
        final candidate = Map<String, dynamic>.from(item);
        final milliseconds =
            (candidate['trackTimeMillis'] as num?)?.toDouble();
        final score = _matchScore(
          candidateTitle: candidate['trackName']?.toString() ?? '',
          candidateArtist: candidate['artistName']?.toString() ?? '',
          candidateDurationSeconds:
              milliseconds == null ? null : milliseconds / 1000,
          title: title,
          artist: artist,
          duration: duration,
        );
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }

      if (best == null || bestScore < 0.78) return null;

      var artworkUrl = best['artworkUrl100']?.toString();
      if (artworkUrl == null || artworkUrl.isEmpty) return null;

      artworkUrl = artworkUrl
          .replaceFirst('100x100bb', '600x600bb')
          .replaceFirst('100x100', '600x600');

      final bytes = await _download(Uri.parse(artworkUrl));
      if (bytes == null) return null;
      return OnlineArtworkResult(bytes: bytes, source: 'Apple Music');
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final request = await _client.getUrl(uri).timeout(
      const Duration(seconds: 8),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'MP3-by-Glasi/0.3');

    final response = await request.close().timeout(
      const Duration(seconds: 8),
    );
    if (response.statusCode != HttpStatus.ok) return null;

    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 8));
    final decoded = jsonDecode(body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  Future<Uint8List?> _download(Uri uri) async {
    final request = await _client.getUrl(uri).timeout(
      const Duration(seconds: 8),
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'MP3-by-Glasi/0.3');

    final response = await request.close().timeout(
      const Duration(seconds: 8),
    );
    if (response.statusCode != HttpStatus.ok) return null;

    final bytes = await response
        .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk))
        .timeout(const Duration(seconds: 8));
    return bytes.isEmpty ? null : Uint8List.fromList(bytes);
  }

  double _matchScore({
    required String candidateTitle,
    required String candidateArtist,
    required double? candidateDurationSeconds,
    required String title,
    required String artist,
    required Duration? duration,
  }) {
    final titleScore = _similarity(_clean(candidateTitle), title);
    final artistScore = _similarity(_clean(candidateArtist), artist);
    var score = titleScore * 0.6 + artistScore * 0.4;

    if (duration != null &&
        candidateDurationSeconds != null &&
        duration.inSeconds > 0) {
      final delta =
          (candidateDurationSeconds - duration.inSeconds).abs();
      if (delta <= 2) {
        score += 0.08;
      } else if (delta <= 6) {
        score += 0.04;
      } else if (delta > 20) {
        score -= 0.08;
      }
    }

    return score.clamp(0.0, 1.0);
  }

  double _similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.contains(b) || b.contains(a)) return 0.92;

    final aa = a.split(' ').where((x) => x.isNotEmpty).toSet();
    final bb = b.split(' ').where((x) => x.isNotEmpty).toSet();
    if (aa.isEmpty || bb.isEmpty) return 0;

    final intersection = aa.intersection(bb).length;
    final union = aa.union(bb).length;
    return union == 0 ? 0 : intersection / union;
  }

  String _clean(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9äöüß]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void dispose() => _client.close(force: true);
}
