import 'streaming_provider.dart';

class AmazonMusicStreamingProvider implements StreamingProvider {
  static const _apiKey = String.fromEnvironment('AMAZON_MUSIC_API_KEY');
  static const _baseUrl = String.fromEnvironment('AMAZON_MUSIC_BASE_URL');

  @override
  StreamingProviderId get id => StreamingProviderId.amazonMusic;

  @override
  String get displayName => 'Amazon Music';

  @override
  StreamingAvailability get availability =>
      StreamingAvailability.requiresDeveloperAccess;

  bool get isConfigured =>
      _apiKey.trim().isNotEmpty && _baseUrl.trim().isNotEmpty;

  String get integrationStatus => isConfigured
      ? 'Amazon-Music-Zugang konfiguriert; Authentifizierung muss an die '
          'freigeschaltete Partnerkonfiguration angebunden werden.'
      : 'Amazon Music Web API ist derzeit Closed Beta. '
          'MP3 by Glasi ist für einen späteren Partnerzugang vorbereitet.';

  @override
  bool get isAuthenticated => false;

  Never _requiresPartnerAccess() {
    throw StateError(
      'Amazon Music Web API ist derzeit nur mit freigeschaltetem '
      'Partner-/Beta-Zugang nutzbar. Sobald Zugangsdaten und die für '
      'MP3 by Glasi freigegebene Authentifizierung vorliegen, kann dieser '
      'Provider direkt vervollständigt werden.',
    );
  }

  @override
  Future<void> signIn() async => _requiresPartnerAccess();

  @override
  Future<void> signOut() async {}

  @override
  Future<List<StreamingTrack>> search(String query) async =>
      _requiresPartnerAccess();

  @override
  Future<List<StreamingTrack>> libraryTracks() async =>
      _requiresPartnerAccess();

  @override
  Future<List<StreamingPlaylist>> playlists() async =>
      _requiresPartnerAccess();

  @override
  Future<List<StreamingTrack>> playlistTracks(String playlistId) async =>
      _requiresPartnerAccess();

  @override
  Future<void> play(StreamingTrack track) async => _requiresPartnerAccess();

  @override
  Future<void> pause() async => _requiresPartnerAccess();

  @override
  Future<void> resume() async => _requiresPartnerAccess();

  @override
  Future<void> next() async => _requiresPartnerAccess();

  @override
  Future<void> previous() async => _requiresPartnerAccess();
}
