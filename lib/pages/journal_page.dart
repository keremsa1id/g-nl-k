import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';

/// Bir günün günlüğü: ruh hali + serbest yazı. Yazdıkça otomatik kaydedilir.
class JournalPage extends StatefulWidget {
  const JournalPage({super.key, required this.day});

  final DateTime day;

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  static const _prompts = [
    'Bugün seni ne mutlu etti?',
    'Neyi farklı yapmak isterdin?',
    'Bugün öğrendiğin bir şey',
    'Yarın için tek hedefin',
    'Minnettar olduğun bir şey',
  ];

  final store = Store.instance;
  late final TextEditingController _text;
  int? _mood;
  Timer? _debounce;
  bool _saved = true;

  @override
  void initState() {
    super.initState();
    final e = store.journalFor(widget.day);
    _text = TextEditingController(text: e?.text ?? '');
    _mood = e?.mood;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (!_saved) _save(); // bekleyen değişikliği kaybetme
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await store.setJournal(
      widget.day,
      JournalEntry(text: _text.text, mood: _mood, updated: DateTime.now()),
    );
    if (mounted) setState(() => _saved = true);
  }

  void _changed() {
    setState(() => _saved = false);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
  }

  void _insertPrompt(String p) {
    final t = _text.text;
    final prefix = t.isEmpty || t.endsWith('\n') ? '' : '\n\n';
    _text.text = '$t$prefix$p\n';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    _changed();
  }

  Future<void> _openHistory() async {
    final day = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute(builder: (_) => const _JournalHistoryPage()),
    );
    if (day == null || !mounted) return;
    await _save();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute<void>(builder: (_) => JournalPage(day: day)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final d = widget.day;
    final words = _text.text.trim().isEmpty ? 0 : _text.text.trim().split(RegExp(r'\s+')).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Günlük'),
            Text('${d.day} ${trMonths[d.month - 1]} ${d.year}, ${trWeekdays[d.weekday - 1]}',
                style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Tüm günlükler',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: _openHistory,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('Bugün nasıl hissediyorsun?',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, (emoji, label)) in moods.indexed)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _mood = _mood == i ? null : i);
                      _changed();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _mood == i ? AppTheme.red.withValues(alpha: 0.2) : AppTheme.surface1,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: _mood == i ? AppTheme.red : AppTheme.border,
                            width: _mood == i ? 1.6 : 1),
                      ),
                      child: Column(
                        children: [
                          AnimatedScale(
                            scale: _mood == i ? 1.25 : 1,
                            duration: const Duration(milliseconds: 180),
                            child: Text(emoji, style: const TextStyle(fontSize: 26)),
                          ),
                          const SizedBox(height: 4),
                          Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: _mood == i ? FontWeight.w800 : FontWeight.w500,
                                color: _mood == i ? Colors.white : muted,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _prompts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ActionChip(
                avatar: const Icon(Icons.lightbulb_outline_rounded, size: 16),
                label: Text(_prompts[i], style: const TextStyle(fontSize: 12)),
                onPressed: () => _insertPrompt(_prompts[i]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            onChanged: (_) => _changed(),
            minLines: 12,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 16, height: 1.5),
            decoration: const InputDecoration(
              hintText: 'Bugün neler oldu? Aklından geçenleri yaz…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('$words kelime', style: TextStyle(fontSize: 12, color: muted)),
              const Spacer(),
              Icon(_saved ? Icons.cloud_done_outlined : Icons.edit_outlined,
                  size: 14, color: muted),
              const SizedBox(width: 4),
              Text(_saved ? 'Kaydedildi' : 'Yazılıyor…',
                  style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Yazılmış tüm günlüklerin listesi; seçilen günü döndürür.
class _JournalHistoryPage extends StatelessWidget {
  const _JournalHistoryPage();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final entries = Store.instance.journal.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Scaffold(
      appBar: AppBar(title: const Text('Tüm günlükler')),
      body: entries.isEmpty
          ? const Center(child: Text('Henüz günlük yazılmadı'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final MapEntry(key: key, value: e) = entries[i];
                final d = DateTime.parse(key);
                return Material(
                  color: AppTheme.surface1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: AppTheme.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(context, d),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.mood == null ? '📝' : moods[e.mood!].$1,
                              style: const TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${d.day} ${trMonths[d.month - 1]} ${d.year}, '
                                    '${trWeekdays[d.weekday - 1]}',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                if (e.text.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(e.text.trim(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: muted, fontSize: 13)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
