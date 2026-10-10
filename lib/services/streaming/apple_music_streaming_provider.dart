import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'streaming_provider.dart';

class AppleMusicStreamingProvider implements StreamingProvider {
  static const _developerToken = String.fromEnvironment('APPLE_MUSIC_DEVELOPER_TOKEN');
  static const _storefront = String.fromEnvironment(
    'APPLE_MUSIC_STOREFRONT',
    defaultValue: 'de',
  );
  static const _channel = MethodChannel('de.glasi.mp3byglasi/apple_music');
  static const _secureStorage = FlutterSecureStorage();
  static const _userTokenKey = 'apple_music_user_token_v1';

  String? _userToken;
  bool _tokenLoaded = false;

  @override
  StreamingProviderId get id => StreamingProviderId.appleMusic;

  @override
  String get displayName => 'Apple Music';

  @override
  StreamingAvailability get availability =>
      StreamingAvailability.requiresDeveloperAccess;

  bool get isConfigured => _developerToken.trim().isNotEmpty;

  @override
  bool get isAuthenticated => _userToken?.isNotEmpty == true;

  Future<void> _loadUserToken() async {
    if (_tokenLoaded) return;
    _userToken = await _secureStorage.read(key: _userTokenKey);
    _tokenLoaded = true;
  }

  Future<bool> restoreSession() async {
    await _loadUserToken();
    return isAuthenticated;
  }

  void _requireDeveloperToken() {
    if (!isConfigured) {
      throw StateError(
        'Apple Music Developer Token fehlt. '
        'Der private Apple-Schlüssel darf nicht in die App; '
        'starte zum Testen mit --dart-define=APPLE_MUSIC_DEVELOPER_TOKEN=TOKEN.',
      );
    }
  }

  @override
  Future<void> signIn() async {
    _requireDeveloperToken();

    try {
      final token = await _channel.invokeMethod<String>(
        'signIn',
        <String, Object?>{'developerToken': _developerToken},
      );
      if (token == null || token.trim().isEmpty) {
        throw StateError('Apple Music hat keinen Music User Token geliefert.');
      }
      _userToken = token.trim();
      _tokenLoaded = true;
      await _secureStorage.write(key: _userTokenKey, value: _userToken);
    } on PlatformException catch (e) {
      throw StateError(
        e.message ??
            'Apple-Music-Anmeldung ist auf Android noch nicht verfügbar.',
      );
    } on MissingPluginException {
      throw StateError(
        'Die Apple-Music-Android-Bridge ist noch nicht installiert.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    _userToken = null;
    _tokenLoaded = true;
    await _secureStorage.delete(key: _userTokenKey);
    try {
      await _channel.invokeMethod<void>('signOut');
    } on PlatformException {
      // Local token removal is sufficient even if the native SDK is absent.
    } on MissingPluginException {
      // Local token removal is sufficient even if the native SDK is absent.
    }
  }

  Future<http.Response> _get(
    Uri uri, {
    bool personalized = false,
  }) async {
    _requireDeveloperToken();
    if (personalized) await _loadUserToken();

    if (personalized && !isAuthenticated) {
      throw StateError('Apple Music ist nicht angemeldet.');
    }

    final response = await http.get(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer $_developerToken',
        'Accept': 'application/json',
        if (personalized) 'Music-User-Token': _userToken!,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Apple Music API-Fehler (${response.statusCode}): ${response.body}',
      );
    }
    return response;
  }

  Uri? _artworkUri(Map<String, dynamic>? artwork) {
    final raw = artwork?['url']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return Uri.tryParse(
      raw.replaceAll('{w}', '512').replaceAll('{h}', '512'),
    );
  }

  StreamingTrack _trackFromResource(Map<String, dynamic> resource) {
    final attributes = resource['attributes'] as Map<String, dynamic>? ?? const {};
    return StreamingTrack(
      id: resource['id']?.toString() ?? '',
      provider: StreamingProviderId.appleMusic,
      title: attributes['name']?.toString() ?? 'Unbekannter Titel',
      artist: attributes['artistName']?.toString() ?? 'Unbekannter Interpret',
      album: attributes['albumName']?.toString() ?? '',
      duration: attributes['durationInMillis'] is num
          ? Duration(
              milliseconds: (attributes['durationInMillis'] as num).toInt(),
            )
          : null,
      artworkUri: _artworkUri(attributes['artwork'] as Map<String, dynamic>?),
      playable: attributes['playParams'] != null ||
          attributes['playParameters'] != null,
    );
  }

  StreamingPlaylist _playlistFromResource(Map<String, dynamic> resource) {
    final attributes = resource['attributes'] as Map<String, dynamic>? ?? const {};
    return StreamingPlaylist(
      id: resource['id']?.toString() ?? '',
      provider: StreamingProviderId.appleMusic,
      name: attributes['name']?.toString() ?? 'Apple Music Playlist',
      artworkUri: _artworkUri(attributes['artwork'] as Map<String, dynamic>?),
    );
  }

  List<Map<String, dynamic>> _dataList(Map<String, dynamic> json) {
    final data = json['data'] as List<dynamic>? ?? const [];
    return data.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  @override
  Future<List<StreamingTrack>> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];

    final response = await _get(
      Uri.https(
        'api.music.apple.com',
        '/v1/catalog/$_storefront/search',
        <String, String>{
          'term': term,
          'types': 'songs',
          'limit': '25',
        },
      ),
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = json['results'] as Map<String, dynamic>? ?? const {};
    final songs = results['songs'] as Map<String, dynamic>? ?? const {};
    return _dataList(songs)
        .map(_trackFromResource)
        .where((track) => track.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<StreamingTrack>> libraryTracks() async {
    final response = await _get(
      Uri.https(
        'api.music.apple.com',
        '/v1/me/library/songs',
        const <String, String>{'limit': '100'},
      ),
      personalized: true,
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _dataList(json)
        .map(_trackFromResource)
        .where((track) => track.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<StreamingPlaylist>> playlists() async {
    final response = await _get(
      Uri.https(
        'api.music.apple.com',
        '/v1/me/library/playlists',
        const <String, String>{'limit': '100'},
      ),
      personalized: true,
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _dataList(json)
        .map(_playlistFromResource)
        .where((playlist) => playlist.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<StreamingTrack>> playlistTracks(String playlistId) async {
    final id = playlistId.trim();
    if (id.isEmpty) return const [];

    final response = await _get(
      Uri.https(
        'api.music.apple.com',
        '/v1/me/library/playlists/$id/tracks',
        const <String, String>{'limit': '100'},
      ),
      personalized: true,
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _dataList(json)
        .map(_trackFromResource)
        .where((track) => track.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _nativeCommand(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    _requireDeveloperToken();
    await _loadUserToken();
    if (!isAuthenticated) {
      throw StateError('Apple Music ist nicht angemeldet.');
    }

    try {
      await _channel.invokeMethod<void>(
        method,
        <String, Object?>{
          'developerToken': _developerToken,
          'userToken': _userToken,
          ...?arguments,
        },
      );
    } on PlatformException catch (e) {
      throw StateError(
        e.message ?? 'Apple-Music-Wiedergabe ist nicht verfügbar.',
      );
    } on MissingPluginException {
      throw StateError(
        'Die Apple-Music-Android-Playback-Bridge ist noch nicht installiert.',
      );
    }
  }

  @override
  Future<void> play(StreamingTrack track) async {
    if (track.provider != StreamingProviderId.appleMusic) {
      throw ArgumentError('Der Titel gehört nicht zu Apple Music.');
    }
    await _nativeCommand(
      'play',
      <String, Object?>{'trackId': track.id},
    );
  }

  @override
  Future<void> pause() => _nativeCommand('pause');

  @override
  Future<void> resume() => _nativeCommand('resume');

  @override
  Future<void> next() => _nativeCommand('next');

  @override
  Future<void> previous() => _nativeCommand('previous');
}
