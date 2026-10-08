import 'dart:typed_data';

class Track {
  final String id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final int? year;
  final int? trackNumber;
  final Duration? duration;
  final double? bpm;
  final double? bpmConfidence;
  final Uint8List? artwork;

  const Track({
    required this.id, required this.path, required this.title,
    this.artist = 'Unbekannt', this.album = 'Unbekannt',
    this.year, this.trackNumber, this.duration, this.bpm, this.bpmConfidence, this.artwork,
  });

  Track copyWith({String? title, String? artist, String? album, int? year,
      int? trackNumber, Duration? duration, double? bpm, double? bpmConfidence,
      Uint8List? artwork, bool clearArtwork = false}) => Track(
    id: id, path: path, title: title ?? this.title,
    artist: artist ?? this.artist, album: album ?? this.album,
    year: year ?? this.year, trackNumber: trackNumber ?? this.trackNumber,
    duration: duration ?? this.duration,
    bpm: bpm ?? this.bpm, bpmConfidence: bpmConfidence ?? this.bpmConfidence,
    artwork: clearArtwork ? null : (artwork ?? this.artwork),
  );
}
