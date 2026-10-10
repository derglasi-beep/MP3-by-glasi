import 'amazon_music_streaming_provider.dart';
import 'apple_music_streaming_provider.dart';
import 'spotify_streaming_provider.dart';
import 'streaming_provider.dart';

class StreamingService {
  StreamingService({
    List<StreamingProvider>? providers,
  }) : providers = providers ??
            <StreamingProvider>[
              SpotifyStreamingProvider(),
              AppleMusicStreamingProvider(),
              AmazonMusicStreamingProvider(),
            ];

  final List<StreamingProvider> providers;

  StreamingProvider provider(StreamingProviderId id) =>
      providers.firstWhere((item) => item.id == id);
}
