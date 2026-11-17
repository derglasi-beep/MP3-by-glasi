import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mp3_by_glasi/services/music_scanner.dart';

void main() {
  test('network scan handles metadata failures and reports full progress',
      () async {
    final root = await Directory.systemTemp.createTemp('glasi-scanner-');
    try {
      final files = <File>[];
      for (var i = 0; i < 15; i++) {
        // Deliberately incomplete audio headers: a damaged file must not
        // abort an entire scan or drop the title from the library.
        final file = File('${root.path}${Platform.pathSeparator}Song-$i.mp3');
        await file.writeAsBytes([0, 1, 2, 3]);
        files.add(file);
      }
      final progress = <int>[];
      final tracks = await MusicScanner().scanFiles(
        files,
        loadArtwork: false,
        networkOptimized: true,
        onProgress: (done, total) {
          expect(total, 15);
          progress.add(done);
        },
      );
      expect(tracks, hasLength(15));
      expect(tracks.map((track) => track.id).toSet(),
          files.map((file) => file.path).toSet());
      expect(tracks.every((track) => track.title.startsWith('Song-')), isTrue);
      expect(progress, isNotEmpty);
      expect(progress.last, 15);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('directory discovery reports the final count', () async {
    final root = await Directory.systemTemp.createTemp('glasi-discovery-');
    try {
      final subfolder = Directory(
          '${root.path}${Platform.pathSeparator}Album');
      await subfolder.create();
      await File('${subfolder.path}${Platform.pathSeparator}Track.mp3')
          .writeAsBytes([0, 1, 2, 3]);
      await File('${subfolder.path}${Platform.pathSeparator}readme.txt')
          .writeAsString('not music');
      final discovered = <int>[];
      final tracks = await MusicScanner().scanDirectory(
        root.path,
        loadArtwork: false,
        onDiscoveryProgress: discovered.add,
      );
      expect(tracks, hasLength(1));
      expect(discovered.last, 1);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
