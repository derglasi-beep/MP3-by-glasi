import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';
import 'services/audio_handler.dart';
import 'services/audio_player_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();

  final player = AudioPlayerService();

  if (Platform.isAndroid) {
    await AudioService.init(
      builder: () => GlasiAudioHandler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'de.glasi.mp3byglasi.audio',
        androidNotificationChannelName: 'MP3 by Glasi',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
        androidResumeOnClick: true,
      ),
    );
  }

  runApp(Mp3ByGlasiApp(player: player));
}
