import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class BpmCache {
  static const _key = 'bpm_cache_v1';
  Future<Map<String, int>> _read() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw)).map((k, v) => MapEntry(k, (v as num).round()));
    } catch (_) {
      return {};
    }
  }

  Future<int?> get(String path) async => (await _read())[path];

  Future<void> put(String path, int bpm) async {
    final p = await SharedPreferences.getInstance();
    final data = await _read();
    data[path] = bpm;
    await p.setString(_key, jsonEncode(data));
  }

  Future<void> remove(String path) async {
    final p = await SharedPreferences.getInstance();
    final data = await _read()..remove(path);
    await p.setString(_key, jsonEncode(data));
  }
}
