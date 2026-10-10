import 'package:flutter/material.dart';

import '../services/streaming/amazon_music_streaming_provider.dart';
import '../services/streaming/apple_music_streaming_provider.dart';
import '../services/streaming/spotify_streaming_provider.dart';
import '../services/streaming/streaming_provider.dart';

class StreamingScreen extends StatefulWidget {
  const StreamingScreen({super.key});

  @override
  State<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends State<StreamingScreen> {
  final spotify = SpotifyStreamingProvider();
  final appleMusic = AppleMusicStreamingProvider();
  final amazonMusic = AmazonMusicStreamingProvider();
  final searchController = TextEditingController();

  bool restoring = true;
  bool busy = false;
  bool connected = false;
  String? error;
  List<StreamingTrack> tracks = const [];
  List<StreamingPlaylist> playlists = const [];
  String section = 'search';

  @override
  void initState() {
    super.initState();
    _restoreSpotify();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _restoreSpotify() async {
    final restored = await spotify.restoreSession();
    if (!mounted) return;
    setState(() {
      connected = restored;
      restoring = false;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        await spotify.signIn();
        if (!mounted) return;
        setState(() => connected = true);
      });

  Future<void> _signOut() => _run(() async {
        await spotify.signOut();
        if (!mounted) return;
        setState(() {
          connected = false;
          tracks = const [];
          playlists = const [];
        });
      });

  Future<void> _search() => _run(() async {
        final result = await spotify.search(searchController.text);
        if (!mounted) return;
        setState(() {
          tracks = result;
          playlists = const [];
          section = 'search';
        });
      });

  Future<void> _loadLibrary() => _run(() async {
        final result = await spotify.libraryTracks();
        if (!mounted) return;
        setState(() {
          tracks = result;
          playlists = const [];
          section = 'library';
        });
      });

  Future<void> _loadPlaylists() => _run(() async {
        final result = await spotify.playlists();
        if (!mounted) return;
        setState(() {
          playlists = result;
          tracks = const [];
          section = 'playlists';
        });
      });

  Future<void> _openPlaylist(StreamingPlaylist playlist) => _run(() async {
        final result = await spotify.playlistTracks(playlist.id);
        if (!mounted) return;
        setState(() {
          tracks = result;
          playlists = const [];
          section = playlist.name;
        });
      });

  Future<void> _play(StreamingTrack track) => _run(() async {
        await spotify.play(track);
      });

  Widget _providerCard({
    required String name,
    required IconData icon,
    required String text,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(name),
        subtitle: Text(text),
        trailing: const Chip(label: Text('später')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Streaming')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.music_note, size: 32),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Spotify',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (restoring)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Chip(
                            label: Text(connected ? 'Verbunden' : 'Nicht verbunden'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      spotify.isConfigured
                          ? 'Spotify ist konfiguriert und kann per PKCE angemeldet werden.'
                          : 'Für Spotify fehlt noch die Client-ID. Danach kann die Anmeldung direkt hier erfolgen.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (!connected)
                      FilledButton.icon(
                        onPressed: restoring || busy ? null : _signIn,
                        icon: const Icon(Icons.login),
                        label: const Text('Mit Spotify verbinden'),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: busy ? null : _loadLibrary,
                              icon: const Icon(Icons.favorite_outline),
                              label: const Text('Bibliothek'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: busy ? null : _loadPlaylists,
                              icon: const Icon(Icons.queue_music),
                              label: const Text('Playlists'),
                            ),
                          ),
                          IconButton(
                            onPressed: busy ? null : _signOut,
                            tooltip: 'Spotify trennen',
                            icon: const Icon(Icons.logout),
                          ),
                        ],
                      ),
                    if (connected) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Spotify durchsuchen',
                          suffixIcon: IconButton(
                            onPressed: busy ? null : _search,
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _providerCard(
              name: appleMusic.displayName,
              icon: Icons.apple,
              text: 'Als nächster Streaming-Provider vorbereitet.',
            ),
            _providerCard(
              name: amazonMusic.displayName,
              icon: Icons.shopping_bag_outlined,
              text: amazonMusic.integrationStatus,
            ),
            if (connected && (tracks.isNotEmpty || playlists.isNotEmpty)) ...[
              const SizedBox(height: 18),
              Text(
                section == 'search'
                    ? 'Suchergebnisse'
                    : section == 'library'
                        ? 'Spotify-Bibliothek'
                        : section == 'playlists'
                            ? 'Spotify-Playlists'
                            : section,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
            ],
            for (final playlist in playlists)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: playlist.trackCount == null
                      ? null
                      : Text('${playlist.trackCount} Titel'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy ? null : () => _openPlaylist(playlist),
                ),
              ),
            for (final track in tracks)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.album.isEmpty
                        ? track.artist
                        : '${track.artist} · ${track.album}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Über Spotify abspielen',
                    onPressed: busy || !track.playable ? null : () => _play(track),
                    icon: const Icon(Icons.play_arrow),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
