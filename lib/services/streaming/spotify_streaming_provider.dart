import 'streaming_provider.dart';

class SpotifyStreamingProvider implements StreamingProvider {
  @override
  StreamingProviderId get id => StreamingProviderId.spotify;

  @override
  String get displayName => 'Spotify';

  @override
  StreamingAvailability get availability =>
      StreamingAvailability.readyForIntegration;

  @override
  bool get isAuthenticated => false;

  Never _notConnected() =>
      throw StateError('Spotify ist noch nicht mit MP3 by Glasi verbunden.');

  @override
  Future<void> signIn() async => _notConnected();

  @override
  Future<void> signOut() async {}

  @override
  Future<List<StreamingTrack>> search(String query) async => _notConnected();

  @override
  Future<List<StreamingTrack>> libraryTracks() async => _notConnected();

  @override
  Future<List<StreamingPlaylist>> playlists() async => _notConnected();

  @override
  Future<List<StreamingTrack>> playlistTracks(String playlistId) async =>
      _notConnected();

  @override
  Future<void> play(StreamingTrack track) async => _notConnected();

  @override
  Future<void> pause() async => _notConnected();

  @override
  Future<void> resume() async => _notConnected();

  @override
  Future<void> next() async => _notConnected();

  @override
  Future<void> previous() async => _notConnected();
}
