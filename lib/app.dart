import 'package:flutter/material.dart';
import 'services/audio_player_service.dart';
import 'screens/player_screen.dart';

class Mp3ByGlasiApp extends StatefulWidget {
  const Mp3ByGlasiApp({super.key});

  @override
  State<Mp3ByGlasiApp> createState() => _Mp3ByGlasiAppState();
}

class _Mp3ByGlasiAppState extends State<Mp3ByGlasiApp> {
  late final AudioPlayerService player;

  @override
  void initState() {
    super.initState();
    player = AudioPlayerService();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 by Glasi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF101114),
        cardColor: const Color(0xFF181A1F),
      ),
      home: PlayerScreen(player: player),
    );
  }
}
