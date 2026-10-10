import 'package:flutter/material.dart';

import 'services/audio_player_service.dart';
import 'screens/player_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/streaming_screen.dart';
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
  bool _playerShowsLibrary = false;
  late final PlayerScreen _playerPage;
  SettingsScreen? _settingsPage;
  late final StreamingScreen _streamingPage;

  @override
  void initState() {
    super.initState();
    _playerPage = PlayerScreen(
      player: widget.player,
      onLibraryVisibilityChanged: (visible) {
        if (!mounted || _playerShowsLibrary == visible) return;
        setState(() => _playerShowsLibrary = visible);
      },
    );
    _streamingPage = const StreamingScreen();
  }

  void _selectPage(int value) {
    if (value == 2) {
      // Recreate the audio page so a temporarily unavailable Android
      // equalizer gets a fresh availability check when the user returns.
      _settingsPage = SettingsScreen(player: widget.player);
    }
    setState(() => index = value);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _playerPage,
      _streamingPage,
      _settingsPage ?? const SizedBox.shrink(),
    ];

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: index,
              children: pages,
            ),
          ),
          if (index != 0 || _playerShowsLibrary)
            MiniPlayer(player: widget.player),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _selectPage,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music),
            label: 'Player',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_outlined),
            label: 'Streaming',
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
