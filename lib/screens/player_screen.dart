import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/android_music_library_service.dart';
import '../services/bpm_service.dart';
import '../services/bpm_cache.dart';
import '../services/online_bpm_service.dart';
import '../services/online_artwork_service.dart';
import '../services/bpm_fusion_service.dart';
import '../services/library_service.dart';
import '../services/music_scanner.dart';
import '../services/settings_service.dart';
import '../widgets/bpm_badge.dart';
import '../widgets/glasi_visualizer.dart';
import 'playlists_screen.dart';
import 'queue_screen.dart';
import 'now_playing_screen.dart';
import 'spinning_screen.dart';
import 'album_screen.dart';
import 'artist_screen.dart';

enum _SortMode { title, artist, album, bpm, year }

class PlayerScreen extends StatefulWidget {
  final AudioPlayerService player;
  const PlayerScreen({super.key, required this.player});
  @override State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  final scanner = MusicScanner();
  final androidMusicLibrary = AndroidMusicLibraryService();
  final bpm = BpmService();
  final bpmCache = BpmCache();
  final onlineBpm = OnlineBpmService();
  final onlineArtwork = OnlineArtworkService();
  final bpmFusion = BpmFusionService();
  final library = LibraryService();
  final settings = SettingsService();
  List<Track> tracks = [];
  final Map<String, int> _trackIndexById = <String, int>{};
  List<Track>? _visibleCache;
  String? _visibleCacheKey;

  String search = '';
  int? bpmMin;
  int? bpmMax;
  bool analyzing = false;
  bool scanningMusic = false;
  int scanDone = 0;
  int scanTotal = 0;
  int analyzedCount = 0;
  int analysisTotal = 0;
  double volume = .8;
  _SortMode sortMode = _SortMode.title;
  bool sortAscending = true;
  String? onlineBpmTrackId;
  OnlineBpmResult? onlineBpmResult;
  BpmFusionResult? bpmFusionResult;
  late final StreamSubscription<String> _playerErrorSub;
  late final StreamSubscription<Track?> _playerTrackSub;
  Track? _pendingBpmAnalysis;
  Timer? _librarySaveTimer;
  Timer? _backgroundUiRefreshTimer;
  Timer? _artworkMissSaveTimer;
  bool _backgroundUiDirty = false;
  bool _libraryScrolling = false;
  bool _artworkWorkerRunning = false;
  final Set<String> _artworkLoads = <String>{};
  final Set<String> _artworkMisses = <String>{};
  static const int _maxArtworkInMemory = 80;
  final List<String> _artworkLru = <String>[];
  bool _backgroundBpmWorkerRunning = false;
  bool _backgroundOnlineBpmWorkerRunning = false;
  int _backgroundBpmDone = 0;
  int _backgroundBpmTotal = 0;
  int _backgroundBpmExisting = 0;
  int _backgroundBpmCached = 0;
  int _backgroundBpmNew = 0;
  int _backgroundArtworkDone = 0;
  int _backgroundArtworkTotal = 0;
  int _backgroundArtworkCached = 0;
  int _backgroundArtworkNew = 0;
  int _backgroundArtworkMissSkipped = 0;

  void _rebuildTrackIndex() {
    _trackIndexById
      ..clear()
      ..addEntries(
        tracks.asMap().entries.map(
          (entry) => MapEntry(entry.value.id, entry.key),
        ),
      );
  }

  void _invalidateVisibleCache() {
    _visibleCache = null;
    _visibleCacheKey = null;
  }

  int _trackIndex(String id) => _trackIndexById[id] ?? -1;

  String _albumArtworkKey(Track track) {
    final album = track.album.trim().toLowerCase();
    if (album.isEmpty || album == 'unbekannt' || album == 'unknown') {
      return 'track:${track.id}';
    }

    // Album title + year alone collides for common names such as
    // "Greatest Hits". The containing folder separates unrelated albums
    // while still allowing compilations with multiple artists to share art.
    final normalizedPath = track.path.replaceAll('\\', '/');
    final slash = normalizedPath.lastIndexOf('/');
    final folder = slash > 0
        ? normalizedPath.substring(0, slash).toLowerCase()
        : '';
    return 'album:$album|${track.year ?? 0}|$folder';
  }

  void _touchArtworkInMemory(String id) {
    _artworkLru.remove(id);
    _artworkLru.add(id);

    while (_artworkLru.length > _maxArtworkInMemory) {
      final evictId = _artworkLru.removeAt(0);
      if (widget.player.currentTrack?.id == evictId) {
        _artworkLru.add(evictId);
        if (_artworkLru.length <= _maxArtworkInMemory + 1) break;
        continue;
      }

      final index = _trackIndex(evictId);
      if (index < 0) continue;
      final track = tracks[index];
      if (track.artwork == null || track.artwork!.isEmpty) continue;

      final cleared = track.copyWith(clearArtwork: true);
      tracks[index] = cleared;

      if (_visibleCache != null) {
        final visibleIndex =
            _visibleCache!.indexWhere((item) => item.id == evictId);
        if (visibleIndex >= 0) {
          _visibleCache![visibleIndex] = cleared;
        }
      }
    }
  }

  void _loadVisibleArtwork(Track track) {
    if (track.artwork != null && track.artwork!.isNotEmpty) {
      _touchArtworkInMemory(track.id);
      return;
    }
    unawaited(_loadArtworkForVisibleTrack(track));
  }

  Future<void> _loadArtworkForVisibleTrack(Track track) async {
    if (_artworkLoads.contains(track.id)) return;

    final index = _trackIndex(track.id);
    if (index < 0) return;
    final current = tracks[index];
    if (current.artwork != null && current.artwork!.isNotEmpty) return;

    _artworkLoads.add(track.id);
    try {
      final albumKey = _albumArtworkKey(current);
      Uint8List? artwork = await library.loadAlbumArtwork(albumKey);
      artwork ??= await library.loadArtwork(current.id);

      if (!mounted || artwork == null || artwork.isEmpty) return;

      final freshIndex = _trackIndex(current.id);
      if (freshIndex < 0) return;

      final updated = tracks[freshIndex].copyWith(artwork: artwork);
      tracks[freshIndex] = updated;
      _touchArtworkInMemory(current.id);

      if (_visibleCache != null) {
        final visibleIndex =
            _visibleCache!.indexWhere((item) => item.id == current.id);
        if (visibleIndex >= 0) {
          _visibleCache![visibleIndex] = updated;
        }
      }

      if (widget.player.currentTrack?.id == current.id) {
        widget.player.updateTrack(updated);
      }

      // Visible artwork should appear immediately instead of waiting for the
      // throttled five-second background refresh.
      if (mounted) setState(() {});
    } finally {
      _artworkLoads.remove(track.id);
    }
  }

  void _scheduleArtworkMissSave() {
    _artworkMissSaveTimer?.cancel();
    _artworkMissSaveTimer = Timer(const Duration(seconds: 3), () {
      _artworkMissSaveTimer = null;
      unawaited(library.saveArtworkMisses(Set<String>.from(_artworkMisses)));
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playerErrorSub = widget.player.errorStream.listen(_showPlayerError);
    _playerTrackSub = widget.player.currentTrackStream.listen(_onCurrentTrackChanged);
    _restoreLibrary();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || tracks.isEmpty) return;
    unawaited(_loadArtworkInBackground());
    unawaited(_analyzeBpmInBackground());
  }

  void _onCurrentTrackChanged(Track? track) {
    if (track == null) return;

    // The currently playing track always gets artwork priority, regardless
    // of whether playback was started from the library, queue, notification,
    // lock screen or automatic next-track handling.
    unawaited(() async {
      await _loadArtworkForVisibleTrack(track);
      final currentIndex = _trackIndex(track.id);
      if (currentIndex < 0) return;
      final current = tracks[currentIndex];
      if (current.artwork == null || current.artwork!.isEmpty) {
        await _ensureArtwork(
          current,
          allowMetadataRead: true,
          allowOnlineLookup: true,
        );
      }
    }());
    if (widget.player.audio.processingState != ProcessingState.idle ||
        widget.player.audio.playing) {
      unawaited(_analyzeTrack(track));
    }
  }

  void _showPlayerError(String message) {
    if (!mounted) return;
    final text = message.trim().isEmpty
        ? 'Wiedergabe konnte nicht gestartet werden.'
        : message.trim();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.info_outline, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
          ),
        ),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _librarySaveTimer?.cancel();
    _backgroundUiRefreshTimer?.cancel();
    _artworkMissSaveTimer?.cancel();
    if (_librarySaveTimer != null) {
      unawaited(library.saveTrackMetadata(List<Track>.from(tracks)));
    }
    if (_artworkMissSaveTimer != null) {
      unawaited(library.saveArtworkMisses(Set<String>.from(_artworkMisses)));
    }
    _playerErrorSub.cancel();
    _playerTrackSub.cancel();
    onlineBpm.dispose();
    onlineArtwork.dispose();
    super.dispose();
  }

  Future<void> _restoreLibrary() async {
    final results = await Future.wait([
      library.loadTracks(),
      library.loadArtworkMisses(),
    ]);
    final saved = results[0] as List<Track>;
    final artworkMisses = results[1] as Set<String>;
    if (!mounted || saved.isEmpty) return;
    _artworkMisses
      ..clear()
      ..addAll(artworkMisses);

    // Android tracks are restored from our persisted MediaStore snapshot.
    // File.exists() is not a reliable validity check for scoped-storage
    // media paths and previously caused a valid library to be emptied
    // after restarting the app.
    if (Platform.isAndroid) {
      setState(() {
        tracks = saved;
        _artworkLru.clear();
        _rebuildTrackIndex();
        _invalidateVisibleCache();
      });
      final lastTrackId = await settings.lastTrackId;
      final lastIndex = lastTrackId == null ? -1 : _trackIndex(lastTrackId);
      debugPrint(
        '[Restore] letzter Track: id=${lastTrackId ?? 'null'} '
        'index=$lastIndex '
        'title=${lastIndex >= 0 ? tracks[lastIndex].title : 'nicht gefunden'}',
      );
      await widget.player.setQueue(
        tracks,
        startIndex: lastIndex >= 0 ? lastIndex : 0,
        load: false,
        preserveCurrent: false,
      );
      unawaited(_loadArtworkInBackground());
      unawaited(_analyzeBpmInBackground());
      return;
    }

    final checks = await Future.wait(
      saved.map((t) async => MapEntry(t, await File(t.path).exists())),
    );
    final valid = <Track>[
      for (final check in checks)
        if (check.value) check.key,
    ];
    if (!mounted) return;

    setState(() {
      tracks = valid;
      _rebuildTrackIndex();
      _invalidateVisibleCache();
    });
    if (valid.length != saved.length) {
      await library.saveTracks(valid);
    }
    final lastTrackId = await settings.lastTrackId;
    final lastIndex = lastTrackId == null ? -1 : _trackIndex(lastTrackId);
    debugPrint(
      '[Restore] letzter Track: id=${lastTrackId ?? 'null'} '
      'index=$lastIndex '
      'title=${lastIndex >= 0 ? tracks[lastIndex].title : 'nicht gefunden'}',
    );
    await widget.player.setQueue(
      tracks,
      startIndex: lastIndex >= 0 ? lastIndex : 0,
      load: false,
      preserveCurrent: false,
    );
    unawaited(_analyzeBpmInBackground());
  }

  void _scheduleBackgroundUiRefresh() {
    if (!mounted) return;
    _backgroundUiDirty = true;
    if (_libraryScrolling) return;
    if (_backgroundUiRefreshTimer?.isActive ?? false) return;

    _backgroundUiRefreshTimer = Timer(const Duration(seconds: 5), () {
      _backgroundUiRefreshTimer = null;
      if (!mounted || _libraryScrolling || !_backgroundUiDirty) return;
      _backgroundUiDirty = false;
      setState(() {});
    });
  }

  bool _onLibraryScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _libraryScrolling = true;
      _backgroundUiRefreshTimer?.cancel();
      _backgroundUiRefreshTimer = null;
    } else if (notification is ScrollEndNotification) {
      _libraryScrolling = false;
      if (_backgroundUiDirty) {
        _backgroundUiRefreshTimer?.cancel();
        _backgroundUiRefreshTimer = Timer(
          const Duration(milliseconds: 500),
          () {
            _backgroundUiRefreshTimer = null;
            if (!mounted || _libraryScrolling || !_backgroundUiDirty) return;
            _backgroundUiDirty = false;
            setState(() {});
          },
        );
      }
    }
    return false;
  }

  Future<void> _analyzeBpmInBackground() async {
    if (_backgroundBpmWorkerRunning || tracks.isEmpty) return;
    _backgroundBpmWorkerRunning = true;
    _backgroundBpmDone = 0;
    _backgroundBpmExisting = 0;
    _backgroundBpmCached = 0;
    _backgroundBpmNew = 0;
    var pendingLibraryChanges = 0;

    try {
      await Future<void>.delayed(const Duration(seconds: 2));

      final cache = await bpmCache.snapshot();
      final failures = await bpmCache.loadFailures();
      final pending = <Track>[];

      // Fast preparation pass: existing library BPM and cache hits never enter
      // the expensive FFmpeg queue.
      for (final snapshot in List<Track>.from(tracks)) {
        final index = _trackIndex(snapshot.id);
        if (index < 0) continue;
        final current = tracks[index];

        if (current.bpm != null && current.bpm! > 0) {
          _backgroundBpmExisting++;
          continue;
        }

        final cached = cache[current.path];
        if (cached != null && cached.bpm > 0) {
          tracks[index] = current.copyWith(
            bpm: cached.bpm,
            bpmConfidence: cached.confidence,
          );
          _backgroundBpmCached++;
          pendingLibraryChanges++;
          continue;
        }

        if (failures.contains(current.path)) {
          continue;
        }

        pending.add(current);
      }

      _backgroundBpmTotal = pending.length;
      if (pendingLibraryChanges > 0) {
        await library.saveTrackMetadata(List<Track>.from(tracks));
        pendingLibraryChanges = 0;
        _invalidateVisibleCache();
        _scheduleBackgroundUiRefresh();
      }

      for (final snapshot in pending) {
        if (!mounted) return;

        try {
          while (mounted && analyzing) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          if (!mounted) return;

          final index = _trackIndex(snapshot.id);
          if (index < 0) continue;
          final current = tracks[index];

          if (current.bpm != null && current.bpm! > 0) continue;

          if (widget.player.currentTrack?.id == current.id) {
            await Future<void>.delayed(const Duration(seconds: 1));
            continue;
          }

          final result = await bpm.analyzeFileResult(current.path);
          if (!mounted) return;

          if (result != null && result.bpm > 0) {
            failures.remove(current.path);
            _backgroundBpmNew++;
            await bpmCache.putDeferred(
              current.path,
              result.bpm,
              confidence: result.confidence,
            );

            final freshIndex = _trackIndex(current.id);
            if (freshIndex >= 0) {
              final updated = tracks[freshIndex].copyWith(
                bpm: result.bpm,
                bpmConfidence: result.confidence,
              );
              tracks[freshIndex] = updated;
              if (widget.player.currentTrack?.id == current.id) {
                widget.player.updateTrack(updated);
              }
              if (sortMode == _SortMode.bpm || bpmMin != null || bpmMax != null) {
                _invalidateVisibleCache();
              }
              _scheduleBackgroundUiRefresh();
            }

            pendingLibraryChanges++;
            if (pendingLibraryChanges >= 20) {
              await library.saveTrackMetadata(List<Track>.from(tracks));
              pendingLibraryChanges = 0;
            }
          } else {
            failures.add(current.path);
          }

          await Future<void>.delayed(const Duration(milliseconds: 350));
        } catch (error) {
          failures.add(snapshot.path);
          debugPrint(
            '[BPM] Hintergrundanalyse überspringt '
            '"${snapshot.artist} - ${snapshot.title}": $error',
          );
        } finally {
          _backgroundBpmDone++;
          _scheduleBackgroundUiRefresh();
        }
      }

      await bpmCache.saveFailures(failures);
    } finally {
      _backgroundBpmWorkerRunning = false;
      try {
        await bpmCache.flush();
        if (pendingLibraryChanges > 0) {
          await library.saveTrackMetadata(List<Track>.from(tracks));
        }
      } catch (_) {
        // Persistence can be retried later; never leave the worker locked.
      }
      _scheduleBackgroundUiRefresh();
    }

    if (mounted) {
      unawaited(_verifyBpmOnlineInBackground());
    }
  }

  Future<void> _verifyBpmOnlineInBackground() async {
    if (_backgroundOnlineBpmWorkerRunning || tracks.isEmpty) return;

    final pending = <Track>[];
    for (final track in tracks) {
      final artist = track.artist.trim().toLowerCase();
      if (track.bpm != null && track.bpm! > 0) continue;
      if (artist.isEmpty || artist == 'unbekannt' || artist == 'unknown') {
        continue;
      }
      pending.add(track);
    }

    if (pending.isEmpty) return;

    _backgroundOnlineBpmWorkerRunning = true;
    var pendingOnlineLibraryChanges = 0;

    try {
      await Future<void>.delayed(const Duration(seconds: 3));

      for (final snapshot in pending) {
        if (!mounted) return;

        try {
          while (mounted && (analyzing || _backgroundBpmWorkerRunning)) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          if (!mounted) return;

          final index = _trackIndex(snapshot.id);
          if (index < 0) continue;
          final current = tracks[index];

          // A BPM may have been filled while this pass was waiting.
          if (current.bpm != null && current.bpm! > 0) continue;

          final online = await onlineBpm.lookup(
            title: current.title,
            artist: current.artist,
            duration: current.duration,
          );
          if (!mounted) return;

          if (online != null && online.bpm > 0) {
            final freshIndex = _trackIndex(current.id);
            if (freshIndex >= 0) {
              final updated = tracks[freshIndex].copyWith(
                bpm: online.bpm,
                bpmConfidence: online.matchScore,
              );
              tracks[freshIndex] = updated;
              if (widget.player.currentTrack?.id == current.id) {
                widget.player.updateTrack(updated);
              }
              if (sortMode == _SortMode.bpm || bpmMin != null || bpmMax != null) {
                _invalidateVisibleCache();
              }
              _scheduleBackgroundUiRefresh();
            }

            pendingOnlineLibraryChanges++;
            if (pendingOnlineLibraryChanges >= 20) {
              await library.saveTrackMetadata(List<Track>.from(tracks));
              pendingOnlineLibraryChanges = 0;
            }
          }

          await Future<void>.delayed(const Duration(milliseconds: 500));
        } catch (error) {
          debugPrint(
            '[BPM] Online-Prüfung überspringt '
            '"${snapshot.artist} - ${snapshot.title}": $error',
          );
        }
      }
    } finally {
      _backgroundOnlineBpmWorkerRunning = false;
      try {
        if (pendingOnlineLibraryChanges > 0) {
          await library.saveTrackMetadata(List<Track>.from(tracks));
        }
      } catch (_) {
        // A transient storage error must not permanently block verification.
      }
      _scheduleBackgroundUiRefresh();
    }
  }

  Future<void> _loadArtworkInBackground() async {
    if (!Platform.isAndroid || _artworkWorkerRunning || tracks.isEmpty) return;
    _artworkWorkerRunning = true;
    _backgroundArtworkDone = 0;
    _backgroundArtworkCached = 0;
    _backgroundArtworkNew = 0;
    _backgroundArtworkMissSkipped = 0;

    try {
      await Future<void>.delayed(const Duration(seconds: 2));

      // One representative track per album is enough. Existing album covers
      // and known misses are removed before the real worker starts.
      final representatives = <String, Track>{};
      for (final track in tracks) {
        representatives.putIfAbsent(_albumArtworkKey(track), () => track);
      }

      final pending = <Track>[];
      for (final entry in representatives.entries) {
        if (!mounted) return;
        final albumKey = entry.key;
        final track = entry.value;

        if (await library.hasAlbumArtwork(albumKey)) {
          _backgroundArtworkCached++;
          continue;
        }

        if (_artworkMisses.contains(albumKey)) {
          _backgroundArtworkMissSkipped++;
          continue;
        }

        // Migrate one old per-track cache entry into the album cache.
        if (await library.hasArtwork(track.id)) {
          final legacyArtwork = await library.loadArtwork(track.id);
          if (legacyArtwork != null && legacyArtwork.isNotEmpty) {
            await library.saveAlbumArtwork(albumKey, legacyArtwork);
            _backgroundArtworkCached++;
            continue;
          }
        }

        pending.add(track);
      }

      _backgroundArtworkTotal = pending.length;
      _scheduleBackgroundUiRefresh();

      for (final track in pending) {
        if (!mounted) return;

        try {
          await _ensureArtwork(
            track,
            allowMetadataRead: true,
            allowOnlineLookup: true,
          );

          if (await library.hasAlbumArtwork(_albumArtworkKey(track))) {
            _backgroundArtworkNew++;
          }
        } catch (error) {
          debugPrint(
            '[Artwork] Hintergrundlauf überspringt '
            '"${track.artist} - ${track.title}": $error',
          );
        } finally {
          _backgroundArtworkDone++;
          _scheduleBackgroundUiRefresh();
        }

        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    } finally {
      _artworkWorkerRunning = false;
      _scheduleBackgroundUiRefresh();
    }
  }

  Future<void> _ensureArtwork(
    Track track, {
    required bool allowMetadataRead,
    bool allowOnlineLookup = false,
  }) async {
    if (_artworkLoads.contains(track.id)) return;

    final index = _trackIndex(track.id);
    if (index < 0) return;
    final current = tracks[index];
    if (current.artwork != null && current.artwork!.isNotEmpty) return;

    _artworkLoads.add(track.id);
    final albumKey = _albumArtworkKey(track);
    try {
      var artwork = await library.loadAlbumArtwork(albumKey);

      if (artwork == null || artwork.isEmpty) {
        artwork = await library.loadArtwork(track.id);
        if (artwork != null && artwork.isNotEmpty) {
          await library.saveAlbumArtwork(albumKey, artwork);
        }
      }

      if ((artwork == null || artwork.isEmpty) && allowMetadataRead) {
        artwork = await scanner.loadArtwork(track.path);
      }

      String? onlineSource;
      if ((artwork == null || artwork.isEmpty) && allowOnlineLookup) {
        final online = await onlineArtwork.lookup(
          title: track.title,
          artist: track.artist,
          duration: track.duration,
        );
        if (online != null) {
          artwork = online.bytes;
          onlineSource = online.source;
        }
      }

      if (artwork != null && artwork.isNotEmpty) {
        await library.saveAlbumArtwork(albumKey, artwork);
        await library.saveArtwork(track.id, artwork);
        if (_artworkMisses.remove(albumKey)) {
          _scheduleArtworkMissSave();
        }
        if (widget.player.currentTrack?.id == track.id) {
          debugPrint(
            '[Artwork] Cover geladen für "${track.artist} - ${track.title}"'
            '${onlineSource == null ? ' (lokal/cache)' : ' von $onlineSource'}',
          );
        }
      } else {
        if (allowOnlineLookup && _artworkMisses.add(albumKey)) {
          _scheduleArtworkMissSave();
        }
        if (widget.player.currentTrack?.id == track.id) {
          debugPrint(
            '[Artwork] Kein Cover gefunden für '
            '"${track.artist} - ${track.title}"',
          );
        }
      }

      if (!mounted || artwork == null || artwork.isEmpty) return;

      final freshIndex = _trackIndex(track.id);
      if (freshIndex < 0) return;

      final updated = tracks[freshIndex].copyWith(artwork: artwork);
      tracks[freshIndex] = updated;
      _touchArtworkInMemory(track.id);
      if (_visibleCache != null) {
        final cachedIndex =
            _visibleCache!.indexWhere((item) => item.id == track.id);
        if (cachedIndex >= 0) {
          _visibleCache![cachedIndex] = updated;
        }
      }
      if (widget.player.currentTrack?.id == track.id) {
        widget.player.updateTrack(updated);
      }
      _scheduleBackgroundUiRefresh();
    } finally {
      _artworkLoads.remove(track.id);
    }
  }

  List<Track> get visible {
    final q = search.toLowerCase().trim();
    final cacheKey =
        '$q|$bpmMin|$bpmMax|${sortMode.name}|$sortAscending|${tracks.length}';
    if (_visibleCache != null && _visibleCacheKey == cacheKey) {
      return _visibleCache!;
    }

    final result = tracks.where((t) =>
      q.isEmpty ||
      t.title.toLowerCase().contains(q) ||
      t.artist.toLowerCase().contains(q) ||
      t.album.toLowerCase().contains(q),
    ).where((t) {
      final tempo = t.bpm;
      if (tempo == null) return bpmMin == null && bpmMax == null;
      return (bpmMin == null || tempo >= bpmMin!) &&
          (bpmMax == null || tempo <= bpmMax!);
    }).toList();

    int compare(Track a, Track b) {
      switch (sortMode) {
        case _SortMode.artist: return _text(a.artist).compareTo(_text(b.artist));
        case _SortMode.album: return _text(a.album).compareTo(_text(b.album));
        case _SortMode.bpm: return (a.bpm ?? 0).compareTo(b.bpm ?? 0);
        case _SortMode.year: return (a.year ?? 0).compareTo(b.year ?? 0);
        case _SortMode.title: return _text(a.title).compareTo(_text(b.title));
      }
    }

    result.sort((a, b) {
      final primary = compare(a, b);
      if (primary != 0) return sortAscending ? primary : -primary;
      final fallback = _text(a.title).compareTo(_text(b.title));
      return sortAscending ? fallback : -fallback;
    });
    _visibleCache = result;
    _visibleCacheKey = cacheKey;
    return result;
  }

  List<List<Track>> get matchingArtists {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      final artist = track.artist.trim();
      if (artist.isEmpty || artist.toLowerCase() == 'unbekannt') continue;
      if (!artist.toLowerCase().contains(q)) continue;
      groups.putIfAbsent(artist.toLowerCase(), () => <Track>[]).add(track);
    }

    final result = groups.values.toList()
      ..sort((a, b) {
        final aa = a.first.artist.toLowerCase();
        final bb = b.first.artist.toLowerCase();
        final aExact = aa == q;
        final bExact = bb == q;
        if (aExact != bExact) return aExact ? -1 : 1;
        return aa.compareTo(bb);
      });
    return result;
  }

  List<List<Track>> get matchingAlbums {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return const [];

    final groups = <String, List<Track>>{};
    for (final track in tracks) {
      final album = track.album.trim();
      if (album.isEmpty || album.toLowerCase() == 'unbekannt') continue;
      if (!album.toLowerCase().contains(q)) continue;

      final key = '${track.artist.trim().toLowerCase()}|${album.toLowerCase()}';
      groups.putIfAbsent(key, () => <Track>[]).add(track);
    }

    final result = groups.values.toList()
      ..sort((a, b) {
        final aa = a.first.album.toLowerCase();
        final bb = b.first.album.toLowerCase();
        final aExact = aa == q;
        final bExact = bb == q;
        if (aExact != bExact) return aExact ? -1 : 1;
        final albumCompare = aa.compareTo(bb);
        if (albumCompare != 0) return albumCompare;
        return a.first.artist.toLowerCase().compareTo(
              b.first.artist.toLowerCase(),
            );
      });
    return result;
  }

  List<Track> _orderedAlbumTracks(List<Track> albumTracks) {
    final ordered = List<Track>.from(albumTracks);
    if (ordered.any((track) => track.trackNumber != null)) {
      ordered.sort((a, b) {
        final an = a.trackNumber;
        final bn = b.trackNumber;
        if (an == null && bn == null) return 0;
        if (an == null) return 1;
        if (bn == null) return -1;
        return an.compareTo(bn);
      });
    }
    return ordered;
  }

  Future<void> _playAlbum(List<Track> albumTracks) async {
    if (albumTracks.isEmpty) return;
    await widget.player.setQueue(
      _orderedAlbumTracks(albumTracks),
      startIndex: 0,
      preserveCurrent: false,
    );
    await widget.player.play();
    if (mounted) setState(() {});
  }

  Future<void> _queueAlbum(List<Track> albumTracks) async {
    if (albumTracks.isEmpty) return;
    await widget.player.addTracksToQueue(_orderedAlbumTracks(albumTracks));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${albumTracks.length} Titel aus "${albumTracks.first.album}" zur Queue hinzugefügt.',
          ),
        ),
      );
  }

  String _text(String value) => value.trim().toLowerCase();

  String _bpmLabel(double? value) => value == null ? '—' : '${value.round()} BPM';

  String _tempoDelta(Track? current, Track next) {
    if (current?.bpm == null || next.bpm == null || current!.bpm! <= 0) return 'BPM n/a';
    final delta = ((next.bpm! - current.bpm!) / current.bpm!) * 100;
    final sign = delta > 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)}% Tempo';
  }

  String _sortLabel() => switch (sortMode) {
    _SortMode.title => 'Titel',
    _SortMode.artist => 'Interpret',
    _SortMode.album => 'Album',
    _SortMode.bpm => 'BPM',
    _SortMode.year => 'Jahr',
  };

  Future<void> addFiles() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowMultiple: true,
      allowedExtensions: ['mp3','flac','wav','m4a','mp4','ogg','opus','ape','aif','aiff'],
    );
    if (r == null) return;
    await _add(await scanner.scanFiles(
      r.files.where((f) => f.path != null).map((f) => File(f.path!)),
    ));
  }

  Future<void> addFolder() async {
    if (Platform.isAndroid) {
      if (scanningMusic) return;
      setState(() {
        scanningMusic = true;
        scanDone = 0;
        scanTotal = 0;
      });
      try {
        final found = await androidMusicLibrary.getMusicTracks().timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'Android-Musikbibliothek antwortet nicht.',
          ),
        );
        if (found.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('Keine Musikdateien in der Android-Medienbibliothek gefunden.'),
              ),
            );
          return;
        }
        if (mounted) {
          setState(() {
            scanDone = found.length;
            scanTotal = found.length;
          });
        }
        await _add(found);
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('${found.length} Musikdateien eingelesen.'),
              ),
            );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                e.toString().replaceFirst('Exception: ', ''),
              ),
            ),
          );
      } finally {
        if (mounted) {
          setState(() {
            scanningMusic = false;
            scanDone = 0;
            scanTotal = 0;
          });
        }
      }
      return;
    }

    final p = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Musikordner auswählen',
    );
    if (p != null) await _add(await scanner.scanDirectory(p));
  }

  Future<void> _add(List<Track> found) async {
    final map = {for (final t in tracks) t.id: t};
    for (final t in found) {
      final existing = map[t.id];
      if (existing == null) {
        map[t.id] = t;
        continue;
      }

      map[t.id] = t.copyWith(
        bpm: existing.bpm,
        bpmConfidence: existing.bpmConfidence,
        artwork: (t.artwork == null || t.artwork!.isEmpty)
            ? existing.artwork
            : t.artwork,
      );
    }

    final hydrated = <Track>[];
    for (final t in map.values) {
      final cached = await bpmCache.get(t.path);
      hydrated.add(
        cached == null
            ? t
            : t.copyWith(
                bpm: cached.bpm,
                bpmConfidence: cached.confidence,
              ),
      );
    }
    setState(() {
      tracks = hydrated;
      _rebuildTrackIndex();
      _invalidateVisibleCache();
    });
    await library.saveTracks(tracks);
    await widget.player.setQueue(tracks, load: false);
    if (Platform.isAndroid) {
      unawaited(_loadArtworkInBackground());
    }
    unawaited(_analyzeBpmInBackground());
  }

  Future<void> _analyzeTrack(Track t) async {
    if (analyzing) {
      _pendingBpmAnalysis = t;
      return;
    }
    if (mounted) {
      setState(() {
        analyzing = true;
        onlineBpmTrackId = t.id;
        onlineBpmResult = null;
        bpmFusionResult = null;
      });
    }

    try {
      final cached = await bpmCache.get(t.path);
      final localResult = cached == null ? await bpm.analyzeFileResult(t.path) : null;
      final localValue = cached?.bpm ?? localResult?.bpm;
      if (localValue != null) {
        if (cached == null) await bpmCache.put(t.path, localValue, confidence: localResult?.confidence);
        _setBpm(t.id, localValue, localResult?.confidence ?? cached?.confidence);
      }

      final online = await onlineBpm.lookup(
        title: t.title,
        artist: t.artist,
        duration: t.duration,
      );
      final fusion = bpmFusion.fuse(
        localBpm: localValue,
        localConfidence: localResult?.confidence ?? cached?.confidence,
        online: online,
      );
      if (fusion.bpm > 0 && localValue != null) {
        _setBpm(t.id, fusion.bpm, fusion.confidence);
      }
      if (mounted && onlineBpmTrackId == t.id) {
        setState(() {
          onlineBpmResult = online;
          bpmFusionResult = fusion;
        });
      }
    } finally {
      if (mounted) setState(() => analyzing = false);
      final pending = _pendingBpmAnalysis;
      _pendingBpmAnalysis = null;
      if (pending != null && pending.id != t.id) {
        unawaited(_analyzeTrack(pending));
      }
    }
  }

  Future<void> _analyzeLibrary() async {
    if (analyzing || tracks.isEmpty) return;
    setState(() {
      analyzing = true;
      analyzedCount = 0;
      analysisTotal = tracks.length;
    });

    try {
      var changed = false;
      for (final track in List<Track>.from(tracks)) {
        if (!mounted) return;

        // High-confidence results are already stable. Lower-confidence or
        // legacy results get a fresh online verification pass.
        if (track.bpm != null && (track.bpmConfidence ?? 0) >= 0.75) {
          setState(() => analyzedCount++);
          continue;
        }

        final cached = await bpmCache.get(track.path);
        final localResult = track.bpm == null && cached == null
            ? await bpm.analyzeFileResult(track.path)
            : null;
        final value = track.bpm ?? cached?.bpm ?? localResult?.bpm;
        final localConfidence = track.bpmConfidence ?? cached?.confidence ?? localResult?.confidence;
        if (value != null) {
          if (track.bpm == null && cached == null) {
            await bpmCache.put(
              track.path,
              value,
              confidence: localResult?.confidence,
            );
          }
          final online = await onlineBpm.lookup(
            title: track.title,
            artist: track.artist,
            duration: track.duration,
          );
          final fusion = bpmFusion.fuse(
            localBpm: value,
            localConfidence: localConfidence,
            online: online,
          );
          final index = tracks.indexWhere((x) => x.id == track.id);
          if (index >= 0) {
            tracks[index] = tracks[index].copyWith(
              bpm: fusion.bpm,
              bpmConfidence: fusion.confidence,
            );
            changed = true;
          }
        }
        if (mounted) setState(() => analyzedCount++);
      }

      if (changed && mounted) {
        await library.saveTrackMetadata(List<Track>.from(tracks));
        await widget.player.setQueue(tracks, load: false);
        setState(() {});
      }
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  void _setBpm(String id, double value, double? confidence) {
    if (!mounted) return;
    Track? updated;
    setState(() {
      final i = _trackIndex(id);
      if (i >= 0) {
        updated = tracks[i].copyWith(
          bpm: value,
          bpmConfidence: confidence,
        );
        tracks[i] = updated!;
        if (sortMode == _SortMode.bpm || bpmMin != null || bpmMax != null) {
          _invalidateVisibleCache();
        } else if (_visibleCache != null) {
          final cachedIndex =
              _visibleCache!.indexWhere((track) => track.id == id);
          if (cachedIndex >= 0) {
            _visibleCache![cachedIndex] = updated!;
          }
        }
      }
    });

    if (updated != null && widget.player.currentTrack?.id == id) {
      widget.player.updateTrack(updated!);
    }
    _scheduleLibrarySave();
  }

  void _scheduleLibrarySave() {
    _librarySaveTimer?.cancel();
    _librarySaveTimer = Timer(const Duration(milliseconds: 500), () {
      _librarySaveTimer = null;
      unawaited(library.saveTrackMetadata(List<Track>.from(tracks)));
    });
  }

  void _setSort(_SortMode mode) {
    setState(() {
      if (sortMode == mode) {
        sortAscending = !sortAscending;
      } else {
        sortMode = mode;
        sortAscending = true;
      }
      _invalidateVisibleCache();
    });
  }

  String _fusionLabel(BpmFusionResult result) {
    final confidence = (result.confidence * 100).round();
    if (result.possibleRemix) return '⚠ Mögliches Remix/Alternate-Take · gemeinsame Sicherheit $confidence%';
    switch (result.relation) {
      case BpmRelation.exact: return '✓ Lokal + Online bestätigt · Sicherheit $confidence%';
      case BpmRelation.halfTempo: return '↕ Halbtempo erkannt · Sicherheit $confidence%';
      case BpmRelation.doubleTempo: return '↕ Doppeltempo erkannt · Sicherheit $confidence%';
      case BpmRelation.close: return '≈ Nahe beieinander · Sicherheit $confidence%';
      case BpmRelation.mismatch: return '⚠ Unterschiedliche BPM · Sicherheit $confidence%';
      case BpmRelation.localOnly: return 'Lokal erkannt · Sicherheit $confidence%';
      case BpmRelation.onlineOnly: return 'Online erkannt · Sicherheit $confidence%';
    }
  }

  String time(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _playTrack(Track t) async {
    final n = tracks.indexWhere((x) => x.id == t.id);
    if (n < 0) return;

    final queueMatchesLibrary =
        widget.player.queue.length == tracks.length &&
        widget.player.queue.asMap().entries.every(
              (entry) => entry.value.id == tracks[entry.key].id,
            );

    if (!queueMatchesLibrary) {
      await widget.player.setQueue(tracks, startIndex: n, preserveCurrent: false);
      await widget.player.play();
    } else {
      await widget.player.playAt(n);
    }

    unawaited(_analyzeTrack(t));
    if (mounted) setState(() {});
  }

  Future<void> _openQueue() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => QueueScreen(player: widget.player)));
    if (mounted) setState(() {});
  }

  Future<void> _openPlaylists() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistsScreen(player: widget.player, tracks: tracks)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final visibleTracks = visible;
    final artistMatches = matchingArtists;
    final albumMatches = matchingAlbums;

    return Scaffold(
    appBar: AppBar(title: const Text('MP3 by Glasi'), actions: [
      IconButton(onPressed: _openQueue, icon: const Icon(Icons.queue_music), tooltip: 'Queue'),
      IconButton(onPressed: _openPlaylists, icon: const Icon(Icons.playlist_play), tooltip: 'Playlists'),
      IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpinningScreen(player: widget.player, tracks: tracks))), icon: const Icon(Icons.directions_bike), tooltip: 'Spinning DJ'),
      IconButton(onPressed: addFiles, icon: const Icon(Icons.library_music), tooltip: 'Dateien hinzufügen'),
      IconButton(onPressed: addFolder, icon: const Icon(Icons.folder_open), tooltip: Platform.isAndroid ? 'Smartphone-Musik scannen' : 'Ordner scannen'),
    ]),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          onChanged: (v) => setState(() {
            search = v;
            _invalidateVisibleCache();
          }),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Titel, Interpret oder Album',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: scanningMusic ? null : addFolder,
                icon: scanningMusic
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open),
                label: Text(
                  Platform.isAndroid
                      ? (scanningMusic
                          ? (scanTotal > 0
                              ? 'Musik wird eingelesen: $scanDone / $scanTotal'
                              : 'Musik wird gesucht…')
                          : 'Smartphone-Musik scannen')
                      : 'Musikordner hinzufügen',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: addFiles,
              tooltip: 'Einzelne Dateien hinzufügen',
              icon: const Icon(Icons.library_music),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final zone in const <({String label, int? min, int? max})>[
              (label: 'Alle', min: null, max: null),
              (label: '120–130', min: 120, max: 130),
              (label: '130–140', min: 130, max: 140),
              (label: '140–150', min: 140, max: 150),
              (label: '150+', min: 150, max: null),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(zone.label),
                  selected: bpmMin == zone.min && bpmMax == zone.max,
                  onSelected: (_) => setState(() {
                    bpmMin = zone.min;
                    bpmMax = zone.max;
                    _invalidateVisibleCache();
                  }),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(children: [
          const Icon(Icons.sort, size: 20),
          const SizedBox(width: 8),
          Text('Sortierung: ${_sortLabel()}'),
          if (analyzing) ...[
            const SizedBox(width: 12),
            Text('${analyzedCount}/${analysisTotal}'),
          ],
          const Spacer(),
          IconButton(
            onPressed: () => setState(() {
              sortAscending = !sortAscending;
              _invalidateVisibleCache();
            }),
            tooltip: sortAscending ? 'Absteigend' : 'Aufsteigend',
            icon: Icon(sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
          ),
          IconButton(
            tooltip: 'BPM für Bibliothek analysieren',
            onPressed: analyzing || tracks.isEmpty ? null : _analyzeLibrary,
            icon: analyzing
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.speed),
          ),
          PopupMenuButton<_SortMode>(
            tooltip: 'Sortieren nach',
            onSelected: _setSort,
            itemBuilder: (_) => [
              for (final mode in _SortMode.values)
                PopupMenuItem(value: mode, child: Text(switch (mode) {
                  _SortMode.title => 'Titel',
                  _SortMode.artist => 'Interpret',
                  _SortMode.album => 'Album',
                  _SortMode.bpm => 'BPM',
                  _SortMode.year => 'Jahr',
                })),
            ],
            child: const Icon(Icons.filter_list),
          ),
        ]),
      ),
      if (_backgroundBpmWorkerRunning || _artworkWorkerRunning)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              [
                if (_backgroundBpmWorkerRunning)
                  'BPM offen $_backgroundBpmDone/$_backgroundBpmTotal'
                  ' · vorhanden $_backgroundBpmExisting'
                  ' · Cache $_backgroundBpmCached'
                  ' · neu $_backgroundBpmNew',
                if (_artworkWorkerRunning)
                  'Cover offen $_backgroundArtworkDone/$_backgroundArtworkTotal'
                  ' · Cache $_backgroundArtworkCached'
                  ' · neu $_backgroundArtworkNew'
                  ' · ohne Treffer $_backgroundArtworkMissSkipped',
              ].join(' · '),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      Expanded(
        child: Column(
          children: [
            if (artistMatches.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 4, 14, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Interpreten',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                  itemCount: artistMatches.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final artistTracks = artistMatches[index];
                    final first = artistTracks.first;
                    Track coverTrack = first;
                    for (final track in artistTracks) {
                      if (track.artwork != null && track.artwork!.isNotEmpty) {
                        coverTrack = track;
                        break;
                      }
                    }

                    return SizedBox(
                      width: 280,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ArtistScreen(
                                player: widget.player,
                                artist: first.artist,
                                tracks: artistTracks,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundImage: coverTrack.artwork == null
                                      ? null
                                      : MemoryImage(coverTrack.artwork!),
                                  child: coverTrack.artwork == null
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        first.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      Text(
                                        '${artistTracks.length} Titel',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (albumMatches.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 4, 14, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Alben',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  itemCount: albumMatches.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final albumTracks = albumMatches[index];
                    final first = albumTracks.first;
                    Track coverTrack = first;
                    for (final track in albumTracks) {
                      if (track.artwork != null && track.artwork!.isNotEmpty) {
                        coverTrack = track;
                        break;
                      }
                    }

                    return SizedBox(
                      width: 300,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AlbumScreen(
                                player: widget.player,
                                tracks: albumTracks,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 58,
                                    height: 58,
                                    child: coverTrack.artwork == null
                                        ? Container(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            child: const Icon(Icons.album),
                                          )
                                        : Image.memory(
                                            coverTrack.artwork!,
                                            cacheWidth: 116,
                                            cacheHeight: 116,
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        first.album,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      Text(
                                        '${first.artist} · ${albumTracks.length} Titel',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Album-Aktion',
                                  onSelected: (action) async {
                                    if (action == 'play') {
                                      await _playAlbum(albumTracks);
                                    } else if (action == 'queue') {
                                      await _queueAlbum(albumTracks);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'play',
                                      child: Text('Album abspielen'),
                                    ),
                                    PopupMenuItem(
                                      value: 'queue',
                                      child: Text('Album zur Queue'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (search.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Titel (${visibleTracks.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            Expanded(
              child: visibleTracks.isEmpty
                  ? const Center(
                      child: Text('Keine Titel in der Bibliothek'),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: _onLibraryScroll,
                      child: ListView.builder(
                      itemCount: visibleTracks.length,
                      itemBuilder: (_, i) {
                        final t = visibleTracks[i];
                        _loadVisibleArtwork(t);
                        return ListTile(
                          selected: widget.player.currentTrack?.id == t.id,
                          leading: t.artwork == null
                              ? const CircleAvatar(
                                  child: Icon(Icons.music_note),
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    t.artwork!,
                                    width: 48,
                                    height: 48,
                                    cacheWidth: 96,
                                    cacheHeight: 96,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                                ),
                          title: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${t.artist} • ${t.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (t.bpm != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: 4),
                                  child: Text(
                                    _bpmLabel(t.bpm),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                ),
                              PopupMenuButton<String>(
                                tooltip: 'Queue-Aktion',
                                onSelected: (action) async {
                                  if (action == 'next') {
                                    await widget.player.playNext(t);
                                  }
                                  if (action == 'queue') {
                                    await widget.player.addToQueue(t);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'next',
                                    child: Text(
                                      'Als Nächstes abspielen',
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'queue',
                                    child: Text('An Queue anhängen'),
                                  ),
                                ],
                                icon: const Icon(Icons.more_vert),
                              ),
                            ],
                          ),
                          onTap: () => _playTrack(t),
                        );
                      },
                    ),
                    ),
            ),
          ],
        ),
      ),
    ]),
  );
  }

  Widget _player() => StreamBuilder<PlayerState>(
    stream: widget.player.playerStateStream,
    builder: (_, ps) => StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (_, pos) => StreamBuilder<Duration?>(
        stream: widget.player.durationStream,
        builder: (_, dur) => StreamBuilder<Track?>(
          stream: widget.player.currentTrackStream,
          initialData: widget.player.currentTrack,
          builder: (_, current) {
            final t = current.data;
            final d = dur.data ?? t?.duration ?? Duration.zero;
            final p = pos.data ?? Duration.zero;
            final max = d.inMilliseconds > 0 ? d.inMilliseconds.toDouble() : 1.0;
            final value = p.inMilliseconds.clamp(0, max.toInt()).toDouble();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                GestureDetector(
                  onTap: t == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NowPlayingScreen(player: widget.player),
                            ),
                          ),
                  child: Hero(
                    tag: 'now-playing-cover',
                    child: SizedBox(
                      width: 170,
                      height: 170,
                      child: t?.artwork == null
                          ? const Card(child: Icon(Icons.album, size: 90))
                          : Image.memory(t!.artwork!, fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(t?.title ?? 'Keine Wiedergabe',
                  style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                Text(t?.artist ?? 'Lokale Bibliothek'),
                if (t?.bpm != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Spinning: ${_bpmLabel(t!.bpm)}${t.bpmConfidence != null ? ' · Sicherheit ${(t.bpmConfidence! * 100).round()}%' : ''}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                const SizedBox(height: 6),
                GlasiVisualizer(playing: ps.data?.playing ?? false, bpm: t?.bpm),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  BpmBadge(bpm: t?.bpm, loading: analyzing && t != null && t.bpm == null),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: t == null ? null : () => _analyzeTrack(t),
                    icon: const Icon(Icons.speed), label: const Text('BPM')),
                ]),
                if (t != null && onlineBpmTrackId == t.id && onlineBpmResult != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Online: ${onlineBpmResult!.bpm.round()} BPM · ${onlineBpmResult!.source} · Treffer ${(onlineBpmResult!.matchScore * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  if (bpmFusionResult != null)
                    Text(
                      _fusionLabel(bpmFusionResult!),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                ],
                Slider(value: value, max: max,
                  onChanged: (v) => widget.player.seek(Duration(milliseconds: v.toInt()))),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(time(p)), Text(time(d))]),
                if (t != null && widget.player.queue.length > 1) ...[
                  const SizedBox(height: 4),
                  Builder(builder: (_) {
                    final index = widget.player.queue.indexWhere((x) => x.id == t.id);
                    final next = index >= 0 && index + 1 < widget.player.queue.length
                        ? widget.player.queue[index + 1]
                        : null;
                    return Text(
                      next == null ? 'Nächster Titel: Ende der Queue' : 'Nächster: ${next.title} · ${_tempoDelta(t, next)}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  }),
                ],
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(onPressed: widget.player.toggleShuffle,
                    color: widget.player.shuffle ? Theme.of(context).colorScheme.primary : null,
                    icon: const Icon(Icons.shuffle), tooltip: 'Zufallswiedergabe'),
                  IconButton(onPressed: widget.player.previous, icon: const Icon(Icons.skip_previous), iconSize: 38),
                  IconButton(
                    onPressed: t == null ? null : ((ps.data?.playing ?? false)
                        ? widget.player.pause : widget.player.play),
                    icon: Icon((ps.data?.playing ?? false) ? Icons.pause_circle : Icons.play_circle),
                    iconSize: 66),
                  IconButton(onPressed: widget.player.next, icon: const Icon(Icons.skip_next), iconSize: 38),
                  IconButton(onPressed: widget.player.toggleRepeat,
                    color: widget.player.loopMode != LoopMode.off ? Theme.of(context).colorScheme.primary : null,
                    icon: Icon(widget.player.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat),
                    tooltip: 'Wiederholung'),
                ]),
                Row(children: [
                  const Icon(Icons.volume_down),
                  Expanded(child: Slider(value: volume, onChanged: (v) {
                    setState(() => volume = v);
                    widget.player.setVolume(v);
                  })),
                  const Icon(Icons.volume_up),
                ])
              ]),
            );
          },
        ),
      ),
    ),
  );
}
