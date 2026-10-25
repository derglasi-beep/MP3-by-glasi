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