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
    return '$bpm bpm · $percent %';
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

          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final entry = entries[index];
              final totalZoneSeconds = entry.zoneSeconds.values
                  .fold<int>(0, (sum, value) => sum + value);

              return Card(
                child: ExpansionTile(
                  leading: Icon(
                    entry.completed
                        ? Icons.check_circle_outline
                        : Icons.stop_circle_outlined,
                  ),
                  title: Text(
                    '${_duration(entry.durationSeconds)} · '
                    '${entry.completed ? 'abgeschlossen' : 'beendet'}',
                  ),
                  subtitle: Text(
                    '${_date(entry.startedAt)}'
                    '${entry.averageHeartRate == null ? '' : ' · Ø ${_heartRateValue(entry.averageHeartRate, entry.configuredMaxHeartRate)}'}'
                    '${entry.maxHeartRate == null ? '' : ' · max ${_heartRateValue(entry.maxHeartRate, entry.configuredMaxHeartRate)}'}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
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
                      ),
                      if (zone < 5) const SizedBox(height: 6),
                    ],
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

  const _ZoneRow({
    required this.zone,
    required this.seconds,
    required this.totalSeconds,
    required this.durationText,
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
          width: 64,
          child: Text(durationText, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}