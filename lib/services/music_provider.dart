import '../models/track.dart';

abstract class MusicProvider {
  String get id;
  String get displayName;

  Future<bool> authenticate();
  Future<List<Track>> search(String query);
  Future<void> play(Track track);
}

/// Local files are the first fully implemented provider.
///
/// Spotify/Amazon adapters intentionally stay behind this interface.
/// Their playback must use the provider's official mechanisms.
class LocalMusicProvider implements MusicProvider {
  @override
  String get id => 'local';

  @override
  String get displayName => 'Lokale Dateien';

  @override
  Future<bool> authenticate() async => true;

  @override
  Future<List<Track>> search(String query) async => const [];

  @override
  Future<void> play(Track track) async {}
}

class SpotifyMusicProvider implements MusicProvider {
  @override
  String get id => 'spotify';

  @override
  String get displayName => 'Spotify';

  @override
  Future<bool> authenticate() async {
    throw UnimplementedError('Spotify OAuth/SDK adapter folgt in einem separaten Modul.');
  }

  @override
  Future<List<Track>> search(String query) async => throw UnimplementedError();

  @override
  Future<void> play(Track track) async => throw UnimplementedError();
}

class AmazonMusicProvider implements MusicProvider {
  @override
  String get id => 'amazon_music';

  @override
  String get displayName => 'Amazon Music';

  @override
  Future<bool> authenticate() async {
    throw UnimplementedError('Amazon Music adapter folgt nach API-Zugang.');
  }

  @override
  Future<List<Track>> search(String query) async => throw UnimplementedError();

  @override
  Future<void> play(Track track) async => throw UnimplementedError();
}
