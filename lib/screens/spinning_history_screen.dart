import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/spinning_session_history_service.dart';

class SpinningHistoryScreen extends StatefulWidget {
  const SpinningHistoryScreen({super.key});

  @override
  State<SpinningHistoryScreen> createState() => _SpinningHistoryScreenState();
}

class _SpinningHistoryScreenState extends State<SpinningHistoryScreen> {
  final SpinningSessionHistoryService _history =
      SpinningSessionHistoryService();
  late Future<List<SpinningSessionHistoryEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _entries = _history.load();
  }

  String _duration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.'
        '${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _heartRateValue(
    int? bpm,
    int? configuredMaxHeartRate,
  ) {
    if (bpm == null) return '—';
    if (configuredMaxHeartRate == null || configuredMaxHeartRate <= 0) {
      return '$bpm bpm';
    }
    final percent = (bpm / configuredMaxHeartRate * 100).round();
    return '$percent % · $bpm bpm';
  }

  String _percent(int part, int total) {
    if (total <= 0) return '0 %';
    return '${(part / total * 100).round()} %';
  }

  int? _dominantZone(Map<int, int> zoneSeconds) {
    int? bestZone;
    var bestSeconds = 0;
    for (var zone = 1; zone <= 5; zone++) {
      final seconds = zoneSeconds[zone] ?? 0;
      if (seconds > bestSeconds) {
        bestSeconds = seconds;
        bestZone = zone;
      }
    }
    return bestZone;
  }

  String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    if (text.contains(';') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  String _sessionCsv(SpinningSessionHistoryEntry entry) {
    final totalZoneSeconds = entry.zoneSeconds.values
        .fold<int>(0, (sum, value) => sum + value);
    final rows = <List<Object?>>[
      ['MP3 by Glasi - Spinning Session'],
      ['Datum', _date(entry.startedAt)],
      ['Name', entry.name],
      ['Notiz', entry.note],
      ['Status', entry.completed ? 'abgeschlossen' : 'beendet'],
      ['Dauer', _duration(entry.durationSeconds)],
      ['HFmax', entry.configuredMaxHeartRate],
      ['Ø Puls bpm', entry.averageHeartRate],
      [
        'Ø Puls % HFmax',
        entry.averageHeartRate == null ||
                entry.configuredMaxHeartRate == null ||
                entry.configuredMaxHeartRate! <= 0
            ? null
            : (entry.averageHeartRate! /
                    entry.configuredMaxHeartRate! *
                    100)
                .round(),
      ],
      ['Max Puls bpm', entry.maxHeartRate],
      [
        'Max Puls % HFmax',
        entry.maxHeartRate == null ||
                entry.configuredMaxHeartRate == null ||
                entry.configuredMaxHeartRate! <= 0
            ? null
            : (entry.maxHeartRate! /
                    entry.configuredMaxHeartRate! *
                    100)
                .round(),
      ],
      ['HF erfasst', _duration(totalZoneSeconds)],
      [
        'HF Abdeckung %',
        entry.durationSeconds <= 0
            ? 0
            : (totalZoneSeconds / entry.durationSeconds * 100)
                .clamp(0, 100)
                .round(),
      ],
      [],
      ['Zone', 'Zeit', 'Anteil %'],
      for (var zone = 1; zone <= 5; zone++)
        [
          'Zone $zone',
          _duration(entry.zoneSeconds[zone] ?? 0),
          totalZoneSeconds <= 0
              ? 0
              : ((entry.zoneSeconds[zone] ?? 0) /
                      totalZoneSeconds *
                      100)
                  .round(),
        ],
      [],
      ['Titel', 'Interpret'],
      for (final track in entry.tracks) [track.title, track.artist],
    ];

    return rows
        .map((row) => row.map(_csvCell).join(';'))
        .join('\r\n');
  }

  Future<void> _exportSession(
    SpinningSessionHistoryEntry entry,
  ) async {
    try {
      final local = entry.startedAt.toLocal();
      final date =
          '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}_'
          '${local.hour.toString().padLeft(2, '0')}-'
          '${local.minute.toString().padLeft(2, '0')}';
      final csv = _sessionCsv(entry);
      final encoded = utf8.encode(csv);
      final bytes = Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...encoded]);

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Spinning-Session exportieren',
        fileName: 'MP3-by-Glasi-Spinning-$date.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: bytes,
      );

      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Session wurde als CSV exportiert.'),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('CSV-Export fehlgeschlagen: $error'),
          ),
        );
    }
  }

  String _allSessionsCsv(
    List<SpinningSessionHistoryEntry> entries,
  ) {
    final rows = <List<Object?>>[
      [
        'Datum',
        'Name',
        'Notiz',
        'Status',
        'Dauer',
        'HFmax',
        'Ø Puls bpm',
        'Ø Puls % HFmax',
        'Max Puls bpm',
        'Max Puls % HFmax',
        'HF erfasst',
        'HF Abdeckung %',
        'Zone 1 Zeit',
        'Zone 1 %',
        'Zone 2 Zeit',
        'Zone 2 %',
        'Zone 3 Zeit',
        'Zone 3 %',
        'Zone 4 Zeit',
        'Zone 4 %',
        'Zone 5 Zeit',
        'Zone 5 %',
        'Hauptzone',
        'Titelanzahl',
      ],
      for (final entry in entries)
        (() {
          final totalZoneSeconds = entry.zoneSeconds.values
              .fold<int>(0, (sum, value) => sum + value);
          final dominantZone = _dominantZone(entry.zoneSeconds);
          int? heartRatePercent(int? bpm) {
            final max = entry.configuredMaxHeartRate;
            if (bpm == null || max == null || max <= 0) return null;
            return (bpm / max * 100).round();
          }

          return <Object?>[
            _date(entry.startedAt),
            entry.name,
            entry.note,
            entry.completed ? 'abgeschlossen' : 'beendet',
            _duration(entry.durationSeconds),
            entry.configuredMaxHeartRate,
            entry.averageHeartRate,
            heartRatePercent(entry.averageHeartRate),
            entry.maxHeartRate,
            heartRatePercent(entry.maxHeartRate),
            _duration(totalZoneSeconds),
            entry.durationSeconds <= 0
                ? 0
                : (totalZoneSeconds / entry.durationSeconds * 100)
                    .clamp(0, 100)
                    .round(),
            for (var zone = 1; zone <= 5; zone++) ...[
              _duration(entry.zoneSeconds[zone] ?? 0),
              totalZoneSeconds <= 0
                  ? 0
                  : ((entry.zoneSeconds[zone] ?? 0) /
                          totalZoneSeconds *
                          100)
                      .round(),
            ],
            dominantZone == null ? null : 'Zone $dominantZone',
            entry.tracks.length,
          ];
        })(),
    ];

    return rows
        .map((row) => row.map(_csvCell).join(';'))
        .join('\r\n');
  }

  Future<void> _exportAllSessions(
    List<SpinningSessionHistoryEntry> entries,
  ) async {
    if (entries.isEmpty) return;

    try {
      final csv = _allSessionsCsv(entries);
      final encoded = utf8.encode(csv);
      final bytes = Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...encoded]);
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Alle Spinning-Sessions exportieren',
        fileName: 'MP3-by-Glasi-Spinning-Historie-$date.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: bytes,
      );

      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${entries.length} Sessions wurden als CSV exportiert.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Gesamtexport fehlgeschlagen: $error'),
          ),
        );
    }
  }

  ({
    int totalDurationSeconds,
    int totalHeartRateSeconds,
    int? averageHeartRate,
    int? maxHeartRate,
    Map<int, int> zoneSeconds,
  }) _aggregateHistory(List<SpinningSessionHistoryEntry> entries) {
    var totalDurationSeconds = 0;
    var totalHeartRateSeconds = 0;
    var weightedHeartRateTotal = 0;
    var weightedHeartRateSeconds = 0;
    int? maxHeartRate;
    final zones = <int, int>{
      for (var zone = 1; zone <= 5; zone++) zone: 0,
    };

    for (final entry in entries) {
      totalDurationSeconds += entry.durationSeconds;
      final recorded = entry.zoneSeconds.values
          .fold<int>(0, (sum, value) => sum + value);
      totalHeartRateSeconds += recorded;

      if (entry.averageHeartRate != null && recorded > 0) {
        weightedHeartRateTotal += entry.averageHeartRate! * recorded;
        weightedHeartRateSeconds += recorded;
      }

      final entryMax = entry.maxHeartRate;
      if (entryMax != null &&
          (maxHeartRate == null || entryMax > maxHeartRate)) {
        maxHeartRate = entryMax;
      }

      for (var zone = 1; zone <= 5; zone++) {
        zones[zone] = (zones[zone] ?? 0) + (entry.zoneSeconds[zone] ?? 0);
      }
    }

    return (
      totalDurationSeconds: totalDurationSeconds,
      totalHeartRateSeconds: totalHeartRateSeconds,
      averageHeartRate: weightedHeartRateSeconds <= 0
          ? null
          : (weightedHeartRateTotal / weightedHeartRateSeconds).round(),
      maxHeartRate: maxHeartRate,
      zoneSeconds: zones,
    );
  }

  Future<void> _editSessionDetails(
    SpinningSessionHistoryEntry entry,
  ) async {
    final nameController = TextEditingController(text: entry.name);
    final noteController = TextEditingController(text: entry.note);

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Session benennen'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'z. B. Bergintervalle',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Notiz',
                    hintText: 'Wie lief das Training?',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (accepted != true) return;

    await _history.updateDetails(
      id: entry.id,
      name: nameController.text,
      note: noteController.text,
    );
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _clearHistory() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Historie löschen?'),
        content: const Text(
          'Alle lokal gespeicherten Spinning-Sessions werden entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (accepted != true) return;
    await _history.clear();
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spinning-Historie'),
        actions: [
          IconButton(
            onPressed: _clearHistory,
            tooltip: 'Historie löschen',
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<SpinningSessionHistoryEntry>>(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data ?? const <SpinningSessionHistoryEntry>[];
          final aggregate = _aggregateHistory(entries);
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Noch keine Spinning-Sessions gespeichert.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final trendEntries = entries.take(8).toList(growable: false);

          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: entries.length + 3,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              if (index == 0) {
                return _HistoryOverviewCard(
                  sessionCount: entries.length,
                  totalDurationText:
                      _duration(aggregate.totalDurationSeconds),
                  averageHeartRate: aggregate.averageHeartRate,
                  maxHeartRate: aggregate.maxHeartRate,
                  totalHeartRateSeconds: aggregate.totalHeartRateSeconds,
                  zoneSeconds: aggregate.zoneSeconds,
                  durationText: _duration,
                  percentText: _percent,
                );
              }

              if (index == 1) {
                return _HistoryTrendCard(
                  entries: trendEntries,
                  dominantZone: _dominantZone,
                  heartRateValue: _heartRateValue,
                );
              }

              if (index == 2) {
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _exportAllSessions(entries),
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(
                      'Alle Sessions exportieren (${entries.length})',
                    ),
                  ),
                );
              }

              final entry = entries[index - 3];
              final totalZoneSeconds = entry.zoneSeconds.values
                  .fold<int>(0, (sum, value) => sum + value);
              final dominantZone = _dominantZone(entry.zoneSeconds);
              final heartRateCoverage = entry.durationSeconds <= 0
                  ? 0
                  : (totalZoneSeconds / entry.durationSeconds * 100)
                      .clamp(0, 100)
                      .round();

              return Card(
                child: ExpansionTile(
                  leading: Icon(
                    entry.completed
                        ? Icons.check_circle_outline
                        : Icons.stop_circle_outlined,
                  ),
                  title: Text(
                    entry.name.trim().isEmpty
                        ? '${_duration(entry.durationSeconds)} · '
                            '${entry.completed ? 'abgeschlossen' : 'beendet'}'
                        : entry.name,
                  ),
                  subtitle: Text(
                    '${_date(entry.startedAt)}'
                    '${entry.averageHeartRate == null ? '' : ' · Ø ${_heartRateValue(entry.averageHeartRate, entry.configuredMaxHeartRate)}'}'
                    '${entry.maxHeartRate == null ? '' : ' · max ${_heartRateValue(entry.maxHeartRate, entry.configuredMaxHeartRate)}'}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if (entry.name.trim().isNotEmpty ||
                        entry.note.trim().isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          entry.name.trim().isEmpty
                              ? 'Session-Notiz'
                              : entry.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (entry.note.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(entry.note),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _editSessionDetails(entry),
                        icon: const Icon(Icons.edit_note),
                        label: Text(
                          entry.name.trim().isEmpty &&
                                  entry.note.trim().isEmpty
                              ? 'Name / Notiz hinzufügen'
                              : 'Name / Notiz bearbeiten',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _SummaryChip(
                          icon: Icons.timer_outlined,
                          label: 'Dauer',
                          value: _duration(entry.durationSeconds),
                        ),
                        _SummaryChip(
                          icon: Icons.monitor_heart_outlined,
                          label: 'HF erfasst',
                          value: totalZoneSeconds <= 0
                              ? '—'
                              : '${_duration(totalZoneSeconds)} · $heartRateCoverage %',
                        ),
                        _SummaryChip(
                          icon: Icons.stacked_bar_chart,
                          label: 'Hauptzone',
                          value: dominantZone == null
                              ? '—'
                              : 'Zone $dominantZone · ${_percent(entry.zoneSeconds[dominantZone] ?? 0, totalZoneSeconds)}',
                        ),
                        _SummaryChip(
                          icon: Icons.queue_music,
                          label: 'Titel',
                          value: '${entry.tracks.length}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (entry.averageHeartRate != null ||
                        entry.maxHeartRate != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _HistoryValue(
                              label: 'Ø Puls',
                              value: _heartRateValue(
                                entry.averageHeartRate,
                                entry.configuredMaxHeartRate,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _HistoryValue(
                              label: 'Max Puls',
                              value: _heartRateValue(
                                entry.maxHeartRate,
                                entry.configuredMaxHeartRate,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'HF-Zonen',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var zone = 1; zone <= 5; zone++) ...[
                      _ZoneRow(
                        zone: zone,
                        seconds: entry.zoneSeconds[zone] ?? 0,
                        totalSeconds: totalZoneSeconds,
                        durationText: _duration(entry.zoneSeconds[zone] ?? 0),
                        percentText: _percent(
                          entry.zoneSeconds[zone] ?? 0,
                          totalZoneSeconds,
                        ),
                      ),
                      if (zone < 5) const SizedBox(height: 6),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _exportSession(entry),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Session als CSV exportieren'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Gehörte Titel (${entry.tracks.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (entry.tracks.isEmpty)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Keine Titel erfasst.'),
                      )
                    else
                      for (final track in entry.tracks)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.music_note),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _HistoryTrendCard extends StatelessWidget {
  final List<SpinningSessionHistoryEntry> entries;
  final int? Function(Map<int, int>) dominantZone;
  final String Function(int?, int?) heartRateValue;

  const _HistoryTrendCard({
    required this.entries,
    required this.dominantZone,
    required this.heartRateValue,
  });

  String _shortDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Letzte Trainings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Trend der letzten ${entries.length} Sessions',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < entries.length; i++) ...[
              Builder(
                builder: (context) {
                  final entry = entries[i];
                  final zone = dominantZone(entry.zoneSeconds);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _shortDate(entry.startedAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              zone == null ? '—' : 'Zone $zone',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Ø ${heartRateValue(entry.averageHeartRate, entry.configuredMaxHeartRate)}',
                          ),
                          Text(
                            entry.maxHeartRate == null
                                ? 'Max —'
                                : 'Max ${heartRateValue(entry.maxHeartRate, entry.configuredMaxHeartRate)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              if (i < entries.length - 1) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryOverviewCard extends StatelessWidget {
  final int sessionCount;
  final String totalDurationText;
  final int? averageHeartRate;
  final int? maxHeartRate;
  final int totalHeartRateSeconds;
  final Map<int, int> zoneSeconds;
  final String Function(int) durationText;
  final String Function(int, int) percentText;

  const _HistoryOverviewCard({
    required this.sessionCount,
    required this.totalDurationText,
    required this.averageHeartRate,
    required this.maxHeartRate,
    required this.totalHeartRateSeconds,
    required this.zoneSeconds,
    required this.durationText,
    required this.percentText,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gesamtauswertung',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SummaryChip(
                  icon: Icons.fitness_center,
                  label: 'Sessions',
                  value: '$sessionCount',
                ),
                _SummaryChip(
                  icon: Icons.timer_outlined,
                  label: 'Gesamtzeit',
                  value: totalDurationText,
                ),
                _SummaryChip(
                  icon: Icons.monitor_heart_outlined,
                  label: 'Ø Puls',
                  value: averageHeartRate == null
                      ? '—'
                      : '$averageHeartRate bpm',
                ),
                _SummaryChip(
                  icon: Icons.favorite,
                  label: 'Max Puls',
                  value: maxHeartRate == null ? '—' : '$maxHeartRate bpm',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'HF-Zonen gesamt',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (var zone = 1; zone <= 5; zone++) ...[
              _ZoneRow(
                zone: zone,
                seconds: zoneSeconds[zone] ?? 0,
                totalSeconds: totalHeartRateSeconds,
                durationText: durationText(zoneSeconds[zone] ?? 0),
                percentText: percentText(
                  zoneSeconds[zone] ?? 0,
                  totalHeartRateSeconds,
                ),
              ),
              if (zone < 5) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: .55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ],
        ),
      );
}

class _HistoryValue extends StatelessWidget {
  final String label;
  final String value;

  const _HistoryValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      );
}

class _ZoneRow extends StatelessWidget {
  final int zone;
  final int seconds;
  final int totalSeconds;
  final String durationText;
  final String percentText;

  const _ZoneRow({
    required this.zone,
    required this.seconds,
    required this.totalSeconds,
    required this.durationText,
    required this.percentText,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = totalSeconds <= 0 ? 0.0 : seconds / totalSeconds;
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            'Zone $zone',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: LinearProgressIndicator(value: fraction.clamp(0.0, 1.0)),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 58,
          child: Text(
            percentText,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(durationText, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}