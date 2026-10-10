import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'streaming_provider.dart';

class SpotifyStreamingProvider implements StreamingProvider {
  static const _clientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static const _redirectUri = String.fromEnvironment(
    'SPOTIFY_REDIRECT_URI',
    defaultValue: 'mp3byglasi://spotify-callback',
  );

  static const _accessTokenKey = 'spotify_access_token_v1';
  static const _refreshTokenKey = 'spotify_refresh_token_v1';
  static const _expiresAtKey = 'spotify_expires_at_v1';

  static const _scopes = <String>[
    'user-library-read',
    'playlist-read-private',
    'playlist-read-collaborative',
    'user-read-playback-state',
    'user-modify-playback-state',
  ];

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  bool _tokensLoaded = false;

  @override
  StreamingProviderId get id => StreamingProviderId.spotify;

  @override
  String get displayName => 'Spotify';

  @override
  StreamingAvailability get availability =>
      StreamingAvailability.readyForIntegration;

  @override
  bool get isAuthenticated =>
      _accessToken != null &&
      _expiresAt != null &&
      _expiresAt!.isAfter(DateTime.now().add(const Duration(seconds: 30)));

  void _requireConfiguration() {
    if (_clientId.trim().isEmpty) {
      throw StateError(
        'Spotify Client-ID fehlt. Starte die App mit '
        '--dart-define=SPOTIFY_CLIENT_ID=DEINE_CLIENT_ID.',
      );
    }

    final redirect = Uri.tryParse(_redirectUri);
    if (redirect == null || redirect.scheme.isEmpty) {
      throw StateError('Ungültige Spotify Redirect-URI: $_redirectUri');
    }
  }

  Future<void> _loadTokens() async {
    if (_tokensLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    final expiresAtMs = prefs.getInt(_expiresAtKey);
    _expiresAt = expiresAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    _tokensLoaded = true;
  }

  Future<void> _storeTokens({
    required String accessToken,
    String? refreshToken,
    required int expiresIn,
  }) async {
    _accessToken = accessToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      _refreshToken = refreshToken;
    }
    _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));

    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_accessTokenKey, accessToken),
      if (_refreshToken != null)
        prefs.setString(_refreshTokenKey, _refreshToken!),
      prefs.setInt(_expiresAtKey, _expiresAt!.millisecondsSinceEpoch),
    ]);
  }

  String _randomUrlSafe(int length) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final secure = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[secure.nextInt(alphabet.length)],
    ).join();
  }

  String _challenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier)).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }

  @override
  Future<void> signIn() async {
    _requireConfiguration();
    await _loadTokens();

    final verifier = _randomUrlSafe(96);
    final state = _randomUrlSafe(40);
    final redirect = Uri.parse(_redirectUri);

    final authUri = Uri.https(
      'accounts.spotify.com',
      '/authorize',
      {
        'client_id': _clientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'scope': _scopes.join(' '),
        'code_challenge_method': 'S256',
        'code_challenge': _challenge(verifier),
        'state': state,
      },
    );

    final result = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: redirect.scheme,
    );

    final callback = Uri.parse(result);
    final error = callback.queryParameters['error'];
    if (error != null) {
      throw StateError('Spotify-Anmeldung abgebrochen: $error');
    }

    if (callback.queryParameters['state'] != state) {
      throw StateError('Spotify-Anmeldung konnte nicht verifiziert werden.');
    }

    final code = callback.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw StateError('Spotify hat keinen Autorisierungscode geliefert.');
    }

    final response = await http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'client_id': _clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': _redirectUri,
        'code_verifier': verifier,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Spotify Token-Austausch fehlgeschlagen '
        '(${response.statusCode}): ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    await _storeTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
    );
  }

  @override
  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _tokensLoaded = true;

    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_accessTokenKey),
      prefs.remove(_refreshTokenKey),
      prefs.remove(_expiresAtKey),
    ]);
  }

  Future<String> _validAccessToken() async {
    _requireConfiguration();
    await _loadTokens();

    final token = _accessToken;
    final expiry = _expiresAt;
    if (token != null &&
        expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return token;
    }

    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('Spotify ist nicht angemeldet.');
    }

    final response = await http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'client_id': _clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await signOut();
      throw StateError(
        'Spotify-Sitzung ist abgelaufen '
        '(${response.statusCode}). Bitte erneut anmelden.',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    await _storeTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 3600,
    );
    return _accessToken!;
  }

  Future<http.Response> _request(
    String method,
    Uri uri, {
    Object? body,
  }) async {
    final token = await _validAccessToken();
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };

    Future<http.Response> send(Map<String, String> requestHeaders) {
      return switch (method) {
        'GET' => http.get(uri, headers: requestHeaders),
        'PUT' => http.put(
            uri,
            headers: requestHeaders,
            body: body == null ? null : jsonEncode(body),
          ),
        'POST' => http.post(
            uri,
            headers: requestHeaders,
            body: body == null ? null : jsonEncode(body),
          ),
        _ => throw ArgumentError('Nicht unterstützte HTTP-Methode: $method'),
      };
    }

    var response = await send(headers);

    if (response.statusCode == 401) {
      _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
      final retryToken = await _validAccessToken();
      response = await send({
        ...headers,
        'Authorization': 'Bearer $retryToken',
      });
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Spotify API-Fehler (${response.statusCode}): ${response.body}',
      );
    }

    return response;
  }

  StreamingTrack _trackFromJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((artist) => artist['name']?.toString())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .join(', ');

    final album = json['album'] as Map<String, dynamic>?;
    final images = album?['images'] as List<dynamic>? ?? const [];
    Uri? artworkUri;
    for (final image in images) {
      if (image is Map<String, dynamic>) {
        final url = image['url']?.toString();
        if (url != null && url.isNotEmpty) {
          artworkUri = Uri.tryParse(url);
          break;
        }
      }
    }

    return StreamingTrack(
      id: json['id']?.toString() ?? '',
      provider: StreamingProviderId.spotify,
      title: json['name']?.toString() ?? 'Unbekannter Titel',
      artist: artists.isEmpty ? 'Unbekannter Interpret' : artists,
      album: album?['name']?.toString() ?? '',
      duration: json['duration_ms'] is num
          ? Duration(milliseconds: (json['duration_ms'] as num).toInt())
          : null,
      artworkUri: artworkUri,
      playable: json['is_playable'] != false &&
          json['restrictions'] == null,
    );
  }

  StreamingPlaylist _playlistFromJson(Map<String, dynamic> json) {
    final images = json['images'] as List<dynamic>? ?? const [];
    Uri? artworkUri;
    for (final image in images) {
      if (image is Map<String, dynamic>) {
        final url = image['url']?.toString();
        if (url != null && url.isNotEmpty) {
          artworkUri = Uri.tryParse(url);
          break;
        }
      }
    }

    final items = json['items'] as Map<String, dynamic>?;
    final tracks = json['tracks'] as Map<String, dynamic>?;

    return StreamingPlaylist(
      id: json['id']?.toString() ?? '',
      provider: StreamingProviderId.spotify,
      name: json['name']?.toString() ?? 'Spotify Playlist',
      trackCount: (items?['total'] as num?)?.toInt() ??
          (tracks?['total'] as num?)?.toInt(),
      artworkUri: artworkUri,
    );
  }

  @override
  Future<List<StreamingTrack>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final response = await _request(
      'GET',
      Uri.https(
        'api.spotify.com',
        '/v1/search',
        {
          'q': q,
          'type': 'track',
          'limit': '10',
        },
      ),
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tracks = json['tracks'] as Map<String, dynamic>?;
    final items = tracks?['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_trackFromJson)
        .where((track) => track.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<StreamingTrack>> libraryTracks() async {
    final results = <StreamingTrack>[];
    var offset = 0;

    while (true) {
      final response = await _request(
        'GET',
        Uri.https(
          'api.spotify.com',
          '/v1/me/tracks',
          {
            'limit': '50',
            'offset': '$offset',
          },
        ),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? const [];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final track = item['track'];
        if (track is Map<String, dynamic>) {
          final parsed = _trackFromJson(track);
          if (parsed.id.isNotEmpty) results.add(parsed);
        }
      }

      if (json['next'] == null || items.isEmpty) break;
      offset += items.length;
    }

    return results;
  }

  @override
  Future<List<StreamingPlaylist>> playlists() async {
    final results = <StreamingPlaylist>[];
    var offset = 0;

    while (true) {
      final response = await _request(
        'GET',
        Uri.https(
          'api.spotify.com',
          '/v1/me/playlists',
          {
            'limit': '50',
            'offset': '$offset',
          },
        ),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? const [];
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final parsed = _playlistFromJson(item);
        if (parsed.id.isNotEmpty) results.add(parsed);
      }

      if (json['next'] == null || items.isEmpty) break;
      offset += items.length;
    }

    return results;
  }

  @override
  Future<List<StreamingTrack>> playlistTracks(String playlistId) async {
    final id = playlistId.trim();
    if (id.isEmpty) return const [];

    final results = <StreamingTrack>[];
    var offset = 0;

    while (true) {
      final response = await _request(
        'GET',
        Uri.https(
          'api.spotify.com',
          '/v1/playlists/$id/items',
          {
            'limit': '50',
            'offset': '$offset',
          },
        ),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = json['items'] as List<dynamic>? ?? const [];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final raw = item['item'] ?? item['track'];
        if (raw is Map<String, dynamic> &&
            (raw['type'] == null || raw['type'] == 'track')) {
          final parsed = _trackFromJson(raw);
          if (parsed.id.isNotEmpty) results.add(parsed);
        }
      }

      if (json['next'] == null || items.isEmpty) break;
      offset += items.length;
    }

    return results;
  }

  @override
  Future<void> play(StreamingTrack track) async {
    if (track.provider != StreamingProviderId.spotify) {
      throw ArgumentError('Der Titel gehört nicht zu Spotify.');
    }

    await _request(
      'PUT',
      Uri.https('api.spotify.com', '/v1/me/player/play'),
      body: {
        'uris': ['spotify:track:${track.id}'],
      },
    );
  }

  @override
  Future<void> pause() async {
    await _request(
      'PUT',
      Uri.https('api.spotify.com', '/v1/me/player/pause'),
    );
  }

  @override
  Future<void> resume() async {
    await _request(
      'PUT',
      Uri.https('api.spotify.com', '/v1/me/player/play'),
    );
  }

  @override
  Future<void> next() async {
    await _request(
      'POST',
      Uri.https('api.spotify.com', '/v1/me/player/next'),
    );
  }

  @override
  Future<void> previous() async {
    await _request(
      'POST',
      Uri.https('api.spotify.com', '/v1/me/player/previous'),
    );
  }
}
