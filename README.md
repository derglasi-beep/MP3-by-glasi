# MP3 by Glasi

PowerAmp-inspirierter, plattformübergreifender Musikplayer für Android, Windows und Linux.

## Aktueller Stand

- lokale MP3/FLAC/M4A/WAV-Wiedergabe
- Mehrfachauswahl von Audiodateien
- Play/Pause, Vor/Zurück, Seek
- Lautstärke
- Warteschlange
- BPM-Analyse-Modul als eigenständige Dart-Komponente
- Provider-Abstraktion für Local / Spotify / Amazon Music
- dunkle Player-Oberfläche als Ausgangspunkt

## Voraussetzungen

Flutter 3.x und Dart 3.x.

Nach dem Klonen:

    flutter create .
    flutter pub get
    flutter run

Für Windows:

    flutter run -d windows

Für Linux:

    flutter run -d linux

Für Android:

    flutter run -d android

Hinweis: Die BPM-Engine ist algorithmisch vorbereitet, benötigt aber noch einen plattformspezifischen PCM-Decoder, damit MP3-Dateien direkt analysiert werden können. Spotify und Amazon Music sind bewusst nur als Provider-Schnittstellen angelegt; Wiedergabe muss über die jeweils zulässigen offiziellen APIs/SDKs erfolgen und nicht über extrahierte Audiodaten.

## Architektur

lib/
- main.dart
- app.dart
- models/track.dart
- services/audio_player_service.dart
- services/bpm_analyzer.dart
- services/music_provider.dart
- screens/player_screen.dart
