import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

class OnlineBpmResult {
  final double bpm;
  final String source;
  final String? isrc;
  final double matchScore;

  const OnlineBpmResult({
    required this.bpm,
    required this.source,
    this.isrc,
    required this.matchScore,
  });
}

/// Looks up BPM in an online music catalogue.
///
/// The service is deliberately best-effort: network/API failures never affect
/// local playback or local BPM analysis.
class OnlineBpmService {
  static const _source = 'Deezer';
  static const _cachePrefix = 'online_bpm_v1:';
  static const _cacheTtl = Duration(days: 30);
  final HttpClient _client;

  OnlineBpmService({HttpClient? client}) : _client = client ?? HttpClient();

  Future<OnlineBpmResult?> lookup({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    final cleanTitle = _clean(title);
    final cleanArtist = _clean(artist);
    if (cleanTitle.isEmpty || cleanArtist.isEmpty) return null;

    final cacheKey = _cacheKey(cleanTitle, cleanArtist, duration);
    final cached = await _readCache(cacheKey);
    if (cached != null) return cached;

    try {
      final query = 'artist:"$cleanArtist" track:"$cleanTitle"';
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
        final score = _matchScore(candidate, cleanTitle, cleanArtist, duration);
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }

      if (best == null || bestScore < 0.82) return null;
      final id = best['id'];
      if (id == null) return null;

      final details = await _getJson(
        Uri.https('api.deezer.com', '/track/$id'),
      );
      if (details == null) return null;

      final bpm = (details['bpm'] as num?)?.toDouble();
      if (bpm == null || bpm < 40 || bpm > 240) return null;

      final result = OnlineBpmResult(
        bpm: double.parse(bpm.toStringAsFixed(1)),
        source: _source,
        isrc: details['isrc']?.toString(),
        matchScore: double.parse(bestScore.toStringAsFixed(2)),
      );
      await _writeCache(cacheKey, result);
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'MP3-by-Glasi/0.3');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) return null;
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  double _matchScore(
    Map<String, dynamic> item,
    String title,
    String artist,
    Duration? duration,
  ) {
    final candidateTitle = _clean(item['title']?.toString() ?? '');
    final artistMap = item['artist'];
    final candidateArtist = _clean(
      artistMap is Map ? artistMap['name']?.toString() ?? '' : '',
    );

    final titleScore = _similarity(candidateTitle, title);
    final artistScore = _similarity(candidateArtist, artist);
    var score = titleScore * 0.6 + artistScore * 0.4;

    if (duration != null) {
      final seconds = (item['duration'] as num?)?.toDouble();
      if (seconds != null && duration.inSeconds > 0) {
        final delta = (seconds - duration.inSeconds).abs();
        if (delta <= 2) {
          score += 0.08;
        } else if (delta <= 6) {
          score += 0.04;
        } else if (delta > 15) {
          score -= 0.08;
        }
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

  String _cacheKey(String title, String artist, Duration? duration) {
    final seconds = duration?.inSeconds ?? 0;
    return '$_cachePrefix${Uri.encodeComponent('$artist|$title|$seconds')}';
  }

  Future<OnlineBpmResult?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final parts = raw.split('|');
      if (parts.length < 5) {
        await prefs.remove(key);
        return null;
      }
      final savedAt = DateTime.tryParse(parts[0]);
      final bpm = double.tryParse(parts[1]);
      final score = double.tryParse(parts[4]);
      if (savedAt == null || bpm == null || score == null ||
          DateTime.now().difference(savedAt) > _cacheTtl) {
        await prefs.remove(key);
        return null;
      }
      return OnlineBpmResult(
        bpm: bpm,
        source: parts[2],
        isrc: parts[3].isEmpty ? null : parts[3],
        matchScore: score,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, OnlineBpmResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, [
        DateTime.now().toIso8601String(),
        result.bpm.toString(),
        result.source,
        result.isrc ?? '',
        result.matchScore.toString(),
      ].join('|'));
    } catch (_) {}
  }

  void dispose() => _client.close(force: true);
}
