import 'dart:io';
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
  }) async {
    final candidates = files
        .where((file) => extensions.contains(_extension(file.path)))
        .toList(growable: false);
    final result = <Track>[];
    for (var i = 0; i < candidates.length; i++) {
      result.add(await _readTrack(candidates[i]));
      onProgress?.call(i + 1, candidates.length);
      if (i % 8 == 7) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    result.sort(
      (a, b) => (a.artist + a.title)
          .toLowerCase()
          .compareTo((b.artist + b.title).toLowerCase()),
    );
    return result;
  }

  Future<List<Track>> scanDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return const [];

    final files = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    return scanFiles(files);
  }

  Future<Track> _readTrack(File file) async {
    dynamic metadata;
    Uint8List? artwork;

    try {
      metadata = readMetadata(file, getImage: true);
      if (metadata.pictures.isNotEmpty) {
        final bytes = metadata.pictures.first.bytes as List<int>;
        if (bytes.isNotEmpty) artwork = Uint8List.fromList(bytes);
      }
    } catch (_) {
      // Some otherwise valid files contain artwork tags that a metadata
      // parser cannot decode. Retry without images so title/artist/album
      // are still preserved.
      try {
        metadata = readMetadata(file, getImage: false);
      } catch (_) {
        return Track(
          id: file.path,
          path: file.path,
          title: _filename(file.path),
          artwork: await _folderArtwork(file),
        );
      }
    }

    artwork ??= await _folderArtwork(file);

    return Track(
      id: file.path,
      path: file.path,
      title: metadata.title?.trim().isNotEmpty == true
          ? metadata.title!.trim()
          : _filename(file.path),
      artist: metadata.artist?.trim().isNotEmpty == true
          ? metadata.artist!.trim()
          : 'Unbekannt',
      album: metadata.album?.trim().isNotEmpty == true
          ? metadata.album!.trim()
          : 'Unbekannt',
      year: metadata.year?.year,
      duration: metadata.duration,
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
