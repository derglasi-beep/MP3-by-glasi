import 'dart:io';

import 'package:flutter/services.dart';

class AndroidMusicLibraryService {
  static const _channel = MethodChannel('de.glasi.mp3byglasi/storage');

  Future<String?> getMusicDirectory() async {
    if (!Platform.isAndroid) return null;

    try {
      return await _channel.invokeMethod<String>('getMusicDirectory');
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Musikordner konnte nicht geöffnet werden.');
    }
  }
}
