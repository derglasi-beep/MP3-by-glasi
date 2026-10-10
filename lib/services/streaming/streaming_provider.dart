enum StreamingProviderId { spotify, appleMusic, amazonMusic }

enum StreamingAvailability {
  readyForIntegration,
  requiresDeveloperAccess,
  unavailable,
}

class StreamingTrack {
  final String id;
  final StreamingProviderId provider;
  final String title;
  final String artist;
  final String album;
  final Duration? duration;
  final Uri? artworkUri;
  final double? bpm;
  final bool playable;

  const StreamingTrack({
    required this.id,
    required this.provider,
    required this.title,
    required this.artist,
    required this.album,
    this.duration,
    this.artworkUri,
    this.bpm,
    this.playable = true,
  });
}

class StreamingPlaylist {
  final String id;
  final StreamingProviderId provider;
  final String name;
  final int? trackCount;
  final Uri? artworkUri;

  const StreamingPlaylist({
    required this.id,
    required this.provider,
    required this.name,
    this.trackCount,
    this.artworkUri,
  });
}

abstract class StreamingProvider {
  StreamingProviderId get id;
  String get displayName;
  StreamingAvailability get availability;

  bool get isAuthenticated;

  Future<void> signIn();
  Future<void> signOut();

  Future<List<StreamingTrack>> search(String query);
  Future<List<StreamingTrack>> libraryTracks();
  Future<List<StreamingPlaylist>> playlists();
  Future<List<StreamingTrack>> playlistTracks(String playlistId);

  Future<void> play(StreamingTrack track);
  Future<void> pause();
  Future<void> resume();
  Future<void> next();
  Future<void> previous();
}
