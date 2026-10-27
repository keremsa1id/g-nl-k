import 'package:flutter/material.dart';

import '../models.dart';
import '../notifications.dart';
import '../storage.dart';
import 'item_editor.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const double slotHeight = 60;
  final store = Store.instance;
  DateTime _day = dateOnly(DateTime.now());
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final slot = now.hour * 2 + (now.minute >= 30 ? 1 : 0);
    _scroll = ScrollController(initialScrollOffset: (slot - 2).clamp(0, 47).toDouble() * slotHeight);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<ScheduleItem> get _dayItems =>
      store.items.where((i) => i.occursOn(_day)).toList()
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

  Future<void> _openEditor({ScheduleItem? existing, int? startMinutes}) async {
    final result = await showModalBottomSheet<ScheduleItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ItemEditor(
        existing: existing,
        day: _day,
        startMinutes: startMinutes ?? existing?.startMinutes ?? 18 * 60,
      ),
    );
    if (result == null) return;
    setState(() {
      store.items.removeWhere((i) => i.id == result.id);
      store.items.add(result);
    });
    await store.saveItems();
    await Notifier.scheduleItem(result);
  }

  Future<void> _delete(ScheduleItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Silinsin mi?'),
        content: Text('"${item.title}" (${item.repeatLabel}) tamamen silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => store.items.removeWhere((i) => i.id == item.id));
    await store.saveItems();
    await Notifier.cancelItem(item);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) setState(() => _day = dateOnly(d));
  }

  void _shift(int days) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));

  Future<void> _showAll() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AllItemsPage(
          onEdit: (i) => _openEditor(existing: i),
          onDelete: _delete,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _dayItems;
    final now = DateTime.now();
    final isToday = sameDay(_day, now);
    final nowSlot = now.hour * 2 + (now.minute >= 30 ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Program'),
        actions: [
          if (!isToday)
            IconButton(
              tooltip: 'Bugün',
              icon: const Icon(Icons.today),
              onPressed: () => setState(() => _day = dateOnly(DateTime.now())),
            ),
          IconButton(
            tooltip: 'Tüm kayıtlar',
            icon: const Icon(Icons.list_alt),
            onPressed: _showAll,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'test') Notifier.showTest();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'test', child: Text('Bildirimi test et')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: scheme.surfaceContainer,
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(fmtDate(_day),
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center),
                          Text(
                            '${isToday ? 'Bugün · ' : ''}${items.length} etkinlik',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: 48,
              itemBuilder: (ctx, slot) =>
                  _slot(ctx, slot, items, isToday && slot == nowSlot),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Ekle'),
      ),
    );
  }

  Widget _slot(BuildContext context, int slot, List<ScheduleItem> items, bool isNow) {
    final scheme = Theme.of(context).colorScheme;
    final minute = slot * 30;
    final starting = items.where((i) => i.startMinutes == minute).toList();
    final ongoing = items
        .where((i) => i.startMinutes < minute && i.endMinutes > minute)
        .toList();
    final isHour = minute % 60 == 0;

    Widget content;
    if (starting.isNotEmpty) {
      content = Column(children: [for (final i in starting) _card(context, i)]);
    } else if (ongoing.isNotEmpty) {
      content = _ongoing(context, ongoing);
    } else {
      content = InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openEditor(startMinutes: minute),
        child: const SizedBox(height: slotHeight - 8),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: slotHeight),
      decoration: BoxDecoration(
        color: isNow ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isHour ? 0.8 : 0.3),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(
                fmtMinutes(minute),
                style: TextStyle(
                  fontWeight: isHour ? FontWeight.w600 : FontWeight.w400,
                  color: isHour ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 12, 4),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, ScheduleItem i) {
    final c = itemColors[i.colorIndex % itemColors.length];
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: c.withValues(alpha: 0.18),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => _openEditor(existing: i),
        onLongPress: () => _delete(i),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: c, width: 5))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${i.timeLabel} · ${i.repeatLabel}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (i.notify) Icon(Icons.notifications_active, size: 18, color: c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ongoing(BuildContext context, List<ScheduleItem> list) {
    final i = list.first;
    final c = itemColors[i.colorIndex % itemColors.length];
    return InkWell(
      onTap: () => _openEditor(existing: i),
      child: Container(
        height: slotHeight - 8,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          border: Border(left: BorderSide(color: c.withValues(alpha: 0.6), width: 5)),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Text('↳ ${list.map((e) => e.title).join(', ')} devam ediyor',
            style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

/// Tekrar eden dahil tüm kayıtların listesi.
class AllItemsPage extends StatefulWidget {
  const AllItemsPage({super.key, required this.onEdit, required this.onDelete});

  final Future<void> Function(ScheduleItem) onEdit;
  final Future<void> Function(ScheduleItem) onDelete;

  @override
  State<AllItemsPage> createState() => _AllItemsPageState();
}

class _AllItemsPageState extends State<AllItemsPage> {
  @override
  Widget build(BuildContext context) {
    final items = [...Store.instance.items]..sort((a, b) {
        final r = a.repeat.index.compareTo(b.repeat.index);
        return r != 0 ? r : a.startMinutes.compareTo(b.startMinutes);
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Tüm kayıtlar')),
      body: items.isEmpty
          ? const Center(child: Text('Henüz kayıt yok'))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, idx) {
                final i = items[idx];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 8,
                    backgroundColor: itemColors[i.colorIndex % itemColors.length],
                  ),
                  title: Text(i.title),
                  subtitle: Text('${i.timeLabel} · ${i.repeatLabel}'),
                  onTap: () async {
                    await widget.onEdit(i);
                    if (mounted) setState(() {});
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.onDelete(i);
                      if (mounted) setState(() {});
                    },
                  ),
                );
              },
            ),
    );
  }
}
