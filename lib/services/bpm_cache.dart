import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class BpmCacheEntry {
  final double bpm;
  final double? confidence;

  const BpmCacheEntry({required this.bpm, this.confidence});
}

class BpmCache {
  static const _key = 'bpm_cache_v3';
  static const _legacyKey = 'bpm_cache_v2';
  static const _legacyKeyV1 = 'bpm_cache_v1';

  Future<Map<String, BpmCacheEntry>> _read() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key) ??
        p.getString(_legacyKey) ??
        p.getString(_legacyKeyV1);
    if (raw == null) return {};
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw));
      return decoded.map((k, v) {
        if (v is num) {
          return MapEntry(k, BpmCacheEntry(bpm: v.toDouble()));
        }
        final entry = Map<String, dynamic>.from(v as Map);
        return MapEntry(
          k,
          BpmCacheEntry(
            bpm: (entry['bpm'] as num).toDouble(),
            confidence: (entry['confidence'] as num?)?.toDouble(),
          ),
        );
      });
    } catch (_) {
      return {};
    }
  }

  Future<BpmCacheEntry?> get(String path) async => (await _read())[path];

  Future<void> put(String path, double bpm, {double? confidence}) async {
    final p = await SharedPreferences.getInstance();
    final data = await _read();
    data[path] = BpmCacheEntry(bpm: bpm, confidence: confidence);
    await p.setString(_key, jsonEncode({
      for (final e in data.entries)
        e.key: {
          'bpm': e.value.bpm,
          'confidence': e.value.confidence,
        }
    }));
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
    await p.remove(_legacyKey);
    await p.remove(_legacyKeyV1);
  }

  Future<void> remove(String path) async {
    final p = await SharedPreferences.getInstance();
    final data = await _read()..remove(path);
    await p.setString(_key, jsonEncode({
      for (final e in data.entries)
        e.key: {
          'bpm': e.value.bpm,
          'confidence': e.value.confidence,
        }
    }));
  }
}
