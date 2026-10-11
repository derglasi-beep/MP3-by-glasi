import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../models/track.dart';

class MusicScanner {
  static const extensions = {
    '.mp3', '.flac', '.wav', '.m4a', '.mp4', '.ogg', '.opus', '.aif', '.aiff', '.ape',
  };

  final Map<String, Future<Uint8List?>> _folderArtworkCache = {};

  Future<List<Track>> scanFiles(
    Iterable<File> files, {
    void Function(int done, int total)? onProgress,
    bool loadArtwork = true,
  }) async {
    final candidates = files
        .where((file) => extensions.contains(_extension(file.path)))
        .toList(growable: false);
    final result = <Track>[];

    // On desktop we deliberately skip artwork during the initial import.
    // Reading metadata in batches avoids starting one isolate per track,
    // which becomes extremely expensive for libraries with 10k+ files.
    if (!loadArtwork && candidates.isNotEmpty) {
      const batchSize = 96;
      for (var start = 0; start < candidates.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, candidates.length);
        final paths = <String>[
          for (var i = start; i < end; i++) candidates[i].path,
        ];
        final snapshots = await Isolate.run(() => _readMetadataBatch(paths));

        for (var i = 0; i < paths.length; i++) {
          final path = paths[i];
          final snapshot = snapshots[i];
          result.add(_trackFromMetadataSnapshot(path, snapshot));
        }

        onProgress?.call(end, candidates.length);
        await Future<void>.delayed(Duration.zero);
      }
    } else {
      for (var i = 0; i < candidates.length; i++) {
        result.add(await _readTrack(candidates[i], loadArtwork: loadArtwork));
        onProgress?.call(i + 1, candidates.length);
        if (i % 8 == 7) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    result.sort(
      (a, b) => (a.artist + a.title)
          .toLowerCase()
          .compareTo((b.artist + b.title).toLowerCase()),
    );
    return result;
  }

  Future<List<Track>> scanDirectory(
    String path, {
    bool loadArtwork = true,
    void Function(int found)? onDiscoveryProgress,
    void Function(int done, int total)? onMetadataProgress,
  }) async {
    final root = Directory(path);
    if (!await root.exists()) {
      throw FileSystemException('Ordner ist nicht erreichbar', path);
    }

    final files = <File>[];
    final pending = <Directory>[root];

    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is Directory) {
            pending.add(entity);
          } else if (entity is File &&
              extensions.contains(_extension(entity.path))) {
            files.add(entity);
            onDiscoveryProgress?.call(files.length);
          }
        }
      } on FileSystemException {
        // Ein einzelner gesperrter oder vorübergehend nicht erreichbarer
        // Unterordner darf den kompletten Bibliotheks-Scan nicht abbrechen.
        continue;
      }
    }

    return scanFiles(
      files,
      loadArtwork: loadArtwork,
      onProgress: onMetadataProgress,
    );
  }

  Future<Uint8List?> loadArtwork(String path) async {
    return Isolate.run(() => _readArtworkSnapshot(path));
  }

  Future<Track> _readTrack(
    File file, {
    required bool loadArtwork,
  }) async {
    final snapshot = await Isolate.run(
      () => _readMetadataSnapshot(file.path, loadArtwork),
    );

    if (snapshot == null) {
      return Track(
        id: file.path,
        path: file.path,
        title: _filename(file.path),
        artwork: loadArtwork ? await _folderArtwork(file) : null,
      );
    }

    Uint8List? artwork = snapshot['artwork'] as Uint8List?;
    if (loadArtwork) {
      artwork ??= await _folderArtwork(file);
    }

    return Track(
      id: file.path,
      path: file.path,
      title: snapshot['title'] as String? ?? _filename(file.path),
      artist: snapshot['artist'] as String? ?? 'Unbekannt',
      album: snapshot['album'] as String? ?? 'Unbekannt',
      year: snapshot['year'] as int?,
      duration: snapshot['durationMs'] == null
          ? null
          : Duration(milliseconds: snapshot['durationMs'] as int),
      artwork: artwork,
    );
  }

  Future<Uint8List?> _folderArtwork(File audioFile) {
    final directory = audioFile.parent.path;
    return _folderArtworkCache.putIfAbsent(
      directory,
      () => _findFolderArtwork(audioFile.parent),
    );
  }

  Future<Uint8List?> _findFolderArtwork(Directory directory) async {
    const preferredNames = [
      'cover.jpg',
      'cover.jpeg',
      'cover.png',
      'folder.jpg',
      'folder.jpeg',
      'folder.png',
      'front.jpg',
      'front.jpeg',
      'front.png',
      'album.jpg',
      'album.jpeg',
      'album.png',
      'albumart.jpg',
      'albumart.jpeg',
      'albumart.png',
    ];

    try {
      final images = <String, File>{};
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last.toLowerCase();
        if (name.endsWith('.jpg') ||
            name.endsWith('.jpeg') ||
            name.endsWith('.png')) {
          images[name] = entity;
        }
      }

      for (final name in preferredNames) {
        final file = images[name];
        if (file != null) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      }

      // If an album folder contains exactly one image, it is a strong
      // fallback candidate even when it has a non-standard filename.
      if (images.length == 1) {
        final bytes = await images.values.single.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (_) {
      // Missing folder access or an unreadable image is not fatal.
    }

    return null;
  }

  String _extension(String p) {
    final i = p.lastIndexOf('.');
    return i < 0 ? '' : p.substring(i).toLowerCase();
  }

  String _filename(String p) {
    final n = p.replaceAll('\\', '/').split('/').last;
    final i = n.lastIndexOf('.');
    return i > 0 ? n.substring(0, i) : n;
  }
}


List<Map<String, Object?>?> _readMetadataBatch(List<String> paths) {
  return [
    for (final path in paths) _readMetadataSnapshot(path, false),
  ];
}

Track _trackFromMetadataSnapshot(
  String path,
  Map<String, Object?>? snapshot,
) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last;
  final dot = name.lastIndexOf('.');
  final fallbackTitle = dot > 0 ? name.substring(0, dot) : name;

  if (snapshot == null) {
    return Track(
      id: path,
      path: path,
      title: fallbackTitle,
    );
  }

  return Track(
    id: path,
    path: path,
    title: snapshot['title'] as String? ?? fallbackTitle,
    artist: snapshot['artist'] as String? ?? 'Unbekannt',
    album: snapshot['album'] as String? ?? 'Unbekannt',
    year: snapshot['year'] as int?,
    duration: snapshot['durationMs'] == null
        ? null
        : Duration(milliseconds: snapshot['durationMs'] as int),
  );
}


Map<String, Object?>? _readMetadataSnapshot(
  String path,
  bool includeArtwork,
) {
  try {
    final metadata = readMetadata(File(path), getImage: includeArtwork);
    Uint8List? artwork;
    if (includeArtwork && metadata.pictures.isNotEmpty) {
      final bytes = metadata.pictures.first.bytes as List<int>;
      if (bytes.isNotEmpty) artwork = Uint8List.fromList(bytes);
    }
    return <String, Object?>{
      'title': metadata.title?.trim().isNotEmpty == true
          ? metadata.title!.trim()
          : null,
      'artist': metadata.artist?.trim().isNotEmpty == true
          ? metadata.artist!.trim()
          : null,
      'album': metadata.album?.trim().isNotEmpty == true
          ? metadata.album!.trim()
          : null,
      'year': metadata.year?.year,
      'durationMs': metadata.duration?.inMilliseconds,
      'artwork': artwork,
    };
  } catch (_) {
    if (!includeArtwork) return null;
    try {
      final metadata = readMetadata(File(path), getImage: false);
      return <String, Object?>{
        'title': metadata.title?.trim().isNotEmpty == true
            ? metadata.title!.trim()
            : null,
        'artist': metadata.artist?.trim().isNotEmpty == true
            ? metadata.artist!.trim()
            : null,
        'album': metadata.album?.trim().isNotEmpty == true
            ? metadata.album!.trim()
            : null,
        'year': metadata.year?.year,
        'durationMs': metadata.duration?.inMilliseconds,
        'artwork': null,
      };
    } catch (_) {
      return null;
    }
  }
}

Uint8List? _readArtworkSnapshot(String path) {
  final file = File(path);
  try {
    final metadata = readMetadata(file, getImage: true);
    if (metadata.pictures.isNotEmpty) {
      final bytes = metadata.pictures.first.bytes as List<int>;
      if (bytes.isNotEmpty) return Uint8List.fromList(bytes);
    }
  } catch (_) {}

  const preferredNames = <String>[
    'cover.jpg', 'cover.jpeg', 'cover.png',
    'folder.jpg', 'folder.jpeg', 'folder.png',
    'front.jpg', 'front.jpeg', 'front.png',
    'album.jpg', 'album.jpeg', 'album.png',
    'albumart.jpg', 'albumart.jpeg', 'albumart.png',
  ];

  try {
    final images = <String, File>{};
    for (final entity in file.parent.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      if (name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png')) {
        images[name] = entity;
      }
    }

    for (final name in preferredNames) {
      final image = images[name];
      if (image != null) {
        final bytes = image.readAsBytesSync();
        if (bytes.isNotEmpty) return bytes;
      }
    }

    if (images.length == 1) {
      final bytes = images.values.single.readAsBytesSync();
      if (bytes.isNotEmpty) return bytes;
    }
  } catch (_) {}

  return null;
}
