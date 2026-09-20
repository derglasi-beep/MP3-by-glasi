# MP3 by Glasi

PowerAmp-inspirierter, plattformübergreifender Musikplayer für Android, Windows und Linux.

## Aktueller Stand

- lokale MP3/FLAC/M4A/WAV/OGG/OPUS/APE/AIFF/AIF-Wiedergabe
- Dateiauswahl und rekursiver Musikordner-Scan
- persistente lokale Musikbibliothek
- Bibliothek wird beim nächsten Start automatisch wiederhergestellt; nicht mehr vorhandene Dateien werden ausgefiltert
- Titel-/Interpret-/Album-Suche
- Cover und ID3/Metadaten-Anzeige
- Play/Pause, Vor/Zurück, Seek und Lautstärke
- Repeat Off / All / One mit manueller Queue-Navigation
- plattformübergreifende Shuffle-Navigation
- Playlists erstellen, löschen, Titel hinzufügen/entfernen und direkt abspielen
- automatische BPM-Analyse beim Start eines Titels
- BPM-Cache, damit bereits analysierte Titel nicht erneut berechnet werden
- 10-Band-EQ-Oberfläche mit nativer Android-Effektpipeline
- Geschwindigkeit 0,5× bis 2×
- Preamp, Bass, Treble und Crossfade-Einstellungen als persistente Audio-Optionen
- Provider-Abstraktion für Local / Spotify / Amazon Music

## Spotify und Amazon Music

Spotify und Amazon Music sind als getrennte Provider-Schnittstellen vorbereitet. Eine echte Anmeldung und Wiedergabe wird nur über die jeweils offiziellen, zulässigen APIs/SDKs integriert; der Player extrahiert keine geschützten Audiodaten.

## BPM

Die BPM-Pipeline dekodiert die ersten bis zu 90 Sekunden einer Datei über FFmpeg in Mono-PCM und führt darauf eine Onset-/Tempo-Schätzung aus. Das Ergebnis wird lokal gecacht und beim nächsten Start automatisch wieder angezeigt.

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

## Architektur

lib/
- main.dart
- app.dart
- models/track.dart
- services/audio_player_service.dart
- services/bpm_analyzer.dart
- services/bpm_cache.dart
- services/bpm_service.dart
- services/equalizer_service.dart
- services/library_service.dart
- services/music_provider.dart
- services/music_scanner.dart
- services/settings_service.dart
- screens/player_screen.dart
- screens/playlists_screen.dart
- screens/settings_screen.dart
- theme/glasi_theme.dart
- widgets/bpm_badge.dart
