import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../models/track.dart';
import 'audio_player_service.dart';

class GlasiAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayerService player;
  late final StreamSubscription<PlayerState> _stateSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<Track?> _trackSub;

  GlasiAudioHandler(this.player) {
    _stateSub = player.playerStateStream.listen(_publishState);
    _positionSub = player.positionStream.listen((_) => _publishProgress());
    _durationSub = player.durationStream.listen((_) => _publishProgress());
    _trackSub = player.currentTrackStream.listen(_publishTrack);

    _publishState(player.audio.playerState);
    _publishTrack(player.currentTrack);
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.previous();

  @override
  Future<void> stop() async {
    await player.audio.stop();
    await super.stop();
  }

  void _publishTrack(Track? track) {
    if (track == null) {
      mediaItem.add(null);
      return;
    }

    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        extras: {'path': track.path},
      ),
    );

    queue.add(player.queue.map((item) {
      return MediaItem(
        id: item.id,
        title: item.title,
        artist: item.artist,
        album: item.album,
        duration: item.duration,
        extras: {'path': item.path},
      );
    }).toList());
  }

  void _publishState(PlayerState state) {
    final processingState = switch (state.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };

    final controls = <MediaControl>[
      if (player.canGoPrevious) MediaControl.skipToPrevious,
      state.playing ? MediaControl.pause : MediaControl.play,
      if (player.queue.length > 1) MediaControl.skipToNext,
    ];

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: processingState,
        playing: state.playing,
        updatePosition: player.audio.position,
        bufferedPosition: player.audio.bufferedPosition,
        speed: player.audio.speed,
        queueIndex:
            player.currentIndex >= 0 ? player.currentIndex : null,
        shuffleMode: player.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.all => AudioServiceRepeatMode.all,
          LoopMode.one => AudioServiceRepeatMode.one,
        },
      ),
    );
  }

  void _publishProgress() {
    playbackState.add(
      playbackState.value.copyWith(
        updatePosition: player.audio.position,
        bufferedPosition: player.audio.bufferedPosition,
        speed: player.audio.speed,
        queueIndex:
            player.currentIndex >= 0 ? player.currentIndex : null,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _stateSub.cancel();
    await _positionSub.cancel();
    await _durationSub.cancel();
  }
}
