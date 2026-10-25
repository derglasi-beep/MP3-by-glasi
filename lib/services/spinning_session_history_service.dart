import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SpinningSessionHistoryEntry {
  final String id;
  final DateTime startedAt;
  final int durationSeconds;
  final int? averageHeartRate;
  final int? maxHeartRate;
  final int? configuredMaxHeartRate;
  final Map<int, int> zoneSeconds;
  final List<SpinningHistoryTrack> tracks;
  final bool completed;
  final String name;
  final String note;

  const SpinningSessionHistoryEntry({
    required this.id,
    required this.startedAt,
    required this.durationSeconds,
    required this.averageHeartRate,
    required this.maxHeartRate,
    required this.configuredMaxHeartRate,
    required this.zoneSeconds,
    required this.tracks,
    required this.completed,
    this.name = '',
    this.note = '',
  });

  factory SpinningSessionHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawZones = json['zoneSeconds'];
    final zones = <int, int>{};
    if (rawZones is Map) {
      for (final entry in rawZones.entries) {
        final zone = int.tryParse(entry.key.toString());
        final seconds = entry.value;
        if (zone != null && seconds is num) {
          zones[zone] = seconds.toInt();
        }
      }
    }

    final rawTracks = json['tracks'];
    final tracks = <SpinningHistoryTrack>[];
    if (rawTracks is List) {
      for (final item in rawTracks) {
        if (item is Map) {
          tracks.add(
            SpinningHistoryTrack.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return SpinningSessionHistoryEntry(
      id: json['id']?.toString() ?? '',
      startedAt:
          DateTime.tryParse(json['startedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      durationSeconds:
          (json['durationSeconds'] as num?)?.toInt() ?? 0,
      averageHeartRate:
          (json['averageHeartRate'] as num?)?.toInt(),
      maxHeartRate: (json['maxHeartRate'] as num?)?.toInt(),
      configuredMaxHeartRate:
          (json['configuredMaxHeartRate'] as num?)?.toInt(),
      zoneSeconds: zones,
      tracks: tracks,
      completed: json['completed'] == true,
      name: json['name']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'durationSeconds': durationSeconds,
        'averageHeartRate': averageHeartRate,
        'maxHeartRate': maxHeartRate,
        'configuredMaxHeartRate': configuredMaxHeartRate,
        'zoneSeconds': {
          for (final entry in zoneSeconds.entries)
            entry.key.toString(): entry.value,
        },
        'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
        'completed': completed,
        'name': name,
        'note': note,
      };
}

class SpinningHistoryTrack {
  final String title;
  final String artist;

  const SpinningHistoryTrack({
    required this.title,
    required this.artist,
  });

  factory SpinningHistoryTrack.fromJson(Map<String, dynamic> json) =>
      SpinningHistoryTrack(
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
      };
}

class SpinningSessionHistoryService {
  static const _key = 'spinning_session_history_v1';
  static const _maxEntries = 100;

  Future<List<SpinningSessionHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const <SpinningSessionHistoryEntry>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <SpinningSessionHistoryEntry>[];
      }

      final result = <SpinningSessionHistoryEntry>[];
      for (final item in decoded) {
        if (item is Map) {
          final entry = SpinningSessionHistoryEntry.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (entry.id.isNotEmpty) result.add(entry);
        }
      }
      result.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return result;
    } catch (_) {
      return const <SpinningSessionHistoryEntry>[];
    }
  }

  Future<void> add(SpinningSessionHistoryEntry entry) async {
    final entries = await load();
    final next = <SpinningSessionHistoryEntry>[
      entry,
      ...entries.where((item) => item.id != entry.id),
    ];
    if (next.length > _maxEntries) {
      next.removeRange(_maxEntries, next.length);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(next.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  Future<void> updateDetails({
    required String id,
    required String name,
    required String note,
  }) async {
    final entries = await load();
    final next = <SpinningSessionHistoryEntry>[
      for (final entry in entries)
        if (entry.id == id)
          SpinningSessionHistoryEntry(
            id: entry.id,
            startedAt: entry.startedAt,
            durationSeconds: entry.durationSeconds,
            averageHeartRate: entry.averageHeartRate,
            maxHeartRate: entry.maxHeartRate,
            configuredMaxHeartRate: entry.configuredMaxHeartRate,
            zoneSeconds: entry.zoneSeconds,
            tracks: entry.tracks,
            completed: entry.completed,
            name: name.trim(),
            note: note.trim(),
          )
        else
          entry,
    ];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(next.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
