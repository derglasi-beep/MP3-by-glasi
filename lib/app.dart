import 'package:flutter/material.dart';

import 'services/audio_player_service.dart';
import 'screens/player_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/glasi_theme.dart';
import 'widgets/mini_player.dart';

class Mp3ByGlasiApp extends StatefulWidget {
  final AudioPlayerService player;

  const Mp3ByGlasiApp({super.key, required this.player});

  @override
  State<Mp3ByGlasiApp> createState() => _AppState();
}

class _AppState extends State<Mp3ByGlasiApp> {

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MP3 by Glasi',
        debugShowCheckedModeBanner: false,
        theme: GlasiTheme.dark(),
        home: _Shell(player: widget.player),
      );
}

class _Shell extends StatefulWidget {
  final AudioPlayerService player;

  const _Shell({required this.player});

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      PlayerScreen(player: widget.player),
      SettingsScreen(player: widget.player),
    ];

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: pages[index]),
          MiniPlayer(player: widget.player),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music),
            label: 'Player',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune),
            label: 'Audio',
          ),
        ],
      ),
    );
  }
}
