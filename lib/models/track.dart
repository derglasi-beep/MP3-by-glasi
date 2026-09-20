class Track {
  final String id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final Duration? duration;
  final double? bpm;

  const Track({
    required this.id,
    required this.path,
    required this.title,
    this.artist = 'Unbekannt',
    this.album = 'Unbekannt',
    this.duration,
    this.bpm,
  });

  Track copyWith({Duration? duration, double? bpm}) => Track(
    id: id,
    path: path,
    title: title,
    artist: artist,
    album: album,
    duration: duration ?? this.duration,
    bpm: bpm ?? this.bpm,
  );
}
