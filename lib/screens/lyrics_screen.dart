import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/lyrics_service.dart';

class LyricsScreen extends StatefulWidget {
  final Track track;

  const LyricsScreen({
    super.key,
    required this.track,
  });

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  final LyricsService _lyrics = LyricsService();

  LyricsEntry? _entry;
  bool _loading = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entry = await _lyrics.load(widget.track.id);
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _loading = false;
    });
  }

  Future<void> _searchOnline() async {
    if (_searching) return;
    setState(() => _searching = true);

    try {
      final entry = await _lyrics.searchOnline(widget.track);
      if (!mounted) return;

      if (entry == null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Online wurden keine passenden Lyrics gefunden.'),
            ),
          );
        return;
      }

      await _lyrics.save(
        widget.track.id,
        entry.text,
        source: entry.source,
      );
      if (!mounted) return;
      setState(() => _entry = entry);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              error.toString().replaceFirst('Exception: ', ''),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _editManual() async {
    final controller = TextEditingController(
      text: _entry?.text ?? '',
    );

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lyrics bearbeiten'),
        content: SizedBox(
          width: 720,
          height: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: 'Songtext hier eingeben oder einfügen …',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text,
            ),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value == null) return;
    final cleaned = value.trim();

    if (cleaned.isEmpty) {
      await _lyrics.clear(widget.track.id);
      if (!mounted) return;
      setState(() => _entry = null);
      return;
    }

    await _lyrics.save(
      widget.track.id,
      cleaned,
      source: 'Manuell',
    );
    if (!mounted) return;
    setState(() {
      _entry = LyricsEntry(
        text: cleaned,
        source: 'Manuell',
      );
    });
  }

  Future<void> _clear() async {
    if (_entry == null) return;
    await _lyrics.clear(widget.track.id);
    if (!mounted) return;
    setState(() => _entry = null);
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lyrics'),
        actions: [
          IconButton(
            tooltip: 'Online suchen',
            onPressed: _searching ? null : _searchOnline,
            icon: _searching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore),
          ),
          IconButton(
            tooltip: 'Manuell bearbeiten',
            onPressed: _editManual,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Lyrics löschen',
            onPressed: entry == null ? null : _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (entry != null)
                      Text(
                        'Quelle: ${entry.source}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: entry == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.lyrics_outlined,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Noch keine Lyrics gespeichert.',
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed:
                                            _searching ? null : _searchOnline,
                                        icon: const Icon(Icons.travel_explore),
                                        label: const Text('Online suchen'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: _editManual,
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Manuell eingeben'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : Card(
                              margin: EdgeInsets.zero,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(18),
                                child: SelectableText(
                                  entry.text,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(height: 1.55),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
