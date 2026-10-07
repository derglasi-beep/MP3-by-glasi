import 'dart:io';

import 'package:flutter/services.dart';

class AndroidMusicLibraryService {
  static const _channel = MethodChannel('de.glasi.mp3byglasi/storage');

  Future<List<File>> getMusicFiles() async {
    if (!Platform.isAndroid) return const [];

    try {
      final paths = await _channel.invokeListMethod<String>('getMusicFiles');
      if (paths == null) return const [];
      return paths
          .where((path) => path.trim().isNotEmpty)
          .map(File.new)
          .toList(growable: false);
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Musikbibliothek konnte nicht gelesen werden.',
      );
    }
  }
}
