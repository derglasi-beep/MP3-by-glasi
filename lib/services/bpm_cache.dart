import 'dart:async';
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
  static const _failuresKey = 'bpm_analysis_failures_v1';

  Future<Map<String, BpmCacheEntry>>? _dataFuture;
  Future<void> _writeTail = Future.value();
  Timer? _deferredWriteTimer;
  bool _deferredWriteDirty = false;

  Future<Map<String, BpmCacheEntry>> _data() =>
      _dataFuture ??= _readFromStorage();

  Future<Map<String, BpmCacheEntry>> _readFromStorage() async {
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

  Future<BpmCacheEntry?> get(String path) async => (await _data())[path];

  Future<Map<String, BpmCacheEntry>> snapshot() async =>
      Map<String, BpmCacheEntry>.from(await _data());

  Future<Set<String>> loadFailures() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_failuresKey);
    return raw == null ? <String>{} : raw.toSet();
  }

  Future<void> saveFailures(Set<String> paths) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_failuresKey, paths.toList(growable: false));
  }

  Future<void> put(
    String path,
    double bpm, {
    double? confidence,
  }) async {
    final data = await _data();
    data[path] = BpmCacheEntry(bpm: bpm, confidence: confidence);
    await _queueWrite(Map<String, BpmCacheEntry>.from(data));
  }

  Future<void> putDeferred(
    String path,
    double bpm, {
    double? confidence,
  }) async {
    final data = await _data();
    data[path] = BpmCacheEntry(bpm: bpm, confidence: confidence);
    _deferredWriteDirty = true;
    _deferredWriteTimer?.cancel();
    _deferredWriteTimer = Timer(const Duration(seconds: 8), () {
      _deferredWriteTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _deferredWriteTimer?.cancel();
    _deferredWriteTimer = null;
    if (!_deferredWriteDirty) {
      await _writeTail;
      return;
    }

    _deferredWriteDirty = false;
    final data = await _data();
    await _queueWrite(Map<String, BpmCacheEntry>.from(data));
  }

  Future<void> remove(String path) async {
    final data = await _data();
    if (data.remove(path) == null) return;
    await _queueWrite(Map<String, BpmCacheEntry>.from(data));
  }

  Future<void> clear() async {
    _deferredWriteTimer?.cancel();
    _deferredWriteTimer = null;
    _deferredWriteDirty = false;
    final data = await _data();
    data.clear();

    _writeTail = _writeTail
        .catchError((_) {})
        .then((_) async {
          final p = await SharedPreferences.getInstance();
          await p.remove(_key);
          await p.remove(_legacyKey);
          await p.remove(_legacyKeyV1);
          await p.remove(_failuresKey);
        });
    await _writeTail;
  }

  Future<void> _queueWrite(Map<String, BpmCacheEntry> snapshot) {
    _writeTail = _writeTail
        .catchError((_) {})
        .then((_) async {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key,
        jsonEncode({
          for (final e in snapshot.entries)
            e.key: {
              'bpm': e.value.bpm,
              'confidence': e.value.confidence,
            },
        }),
      );
    });
    return _writeTail;
  }
}
