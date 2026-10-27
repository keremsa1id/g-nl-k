import 'package:flutter/material.dart';

import '../categories.dart';
import '../models.dart';
import '../notifications.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_editor.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const double slotHeight = 64;
  final store = Store.instance;
  DateTime _day = dateOnly(DateTime.now());
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final slot = now.hour * 2 + (now.minute >= 30 ? 1 : 0);
    _scroll = ScrollController(initialScrollOffset: (slot - 2).clamp(0, 47).toDouble() * slotHeight);
    Notifier.changes.addListener(_refresh);
  }

  @override
  void dispose() {
    Notifier.changes.removeListener(_refresh);
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  static const _flame = Color(0xFFFF8A1F);

  static String _streakLabel(ScheduleItem i, int n) =>
      '$n ${i.repeat == Repeat.daily ? 'gün' : 'kez'} üst üste';

  Future<void> _toggleDone(ScheduleItem item) async {
    if (_day.isAfter(dateOnly(DateTime.now()))) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('İleri bir tarih henüz tamamlanamaz')));
      return;
    }
    final value = !store.isDone(item, _day);
    await store.setDone(item.id, _day, value);
    if (!mounted) return;
    setState(() {});
    if (!value) return;
    final n = store.streak(item, _day);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(n > 1
            ? '🔥 ${item.title}: ${_streakLabel(item, n)}!'
            : '✅ ${item.title} tamamlandı'),
        action: SnackBarAction(label: 'Geri al', onPressed: () => _toggleDone(item)),
      ));
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
    setState(() {
      store.items.removeWhere((i) => i.id == item.id);
      store.done.remove(item.id);
    });
    await store.saveItems();
    await store.saveDone();
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
    final items = _dayItems;
    final now = DateTime.now();
    final isToday = sameDay(_day, now);
    final nowSlot = now.hour * 2 + (now.minute >= 30 ? 1 : 0);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              eyebrow: '${trMonths[_day.month - 1]} ${_day.year}',
              title: isToday ? 'Bugün' : '${_day.day} ${trWeekdays[_day.weekday - 1]}',
              onTitleTap: _pickDate,
              actions: [
                if (!isToday)
                  SquareIconButton(
                    tooltip: 'Bugün',
                    icon: Icons.today_rounded,
                    onPressed: () => setState(() => _day = dateOnly(DateTime.now())),
                  ),
                SquareIconButton(
                  tooltip: 'Tüm kayıtlar',
                  icon: Icons.view_agenda_outlined,
                  onPressed: _showAll,
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (v) {
                      if (v == 'test') Notifier.showTest();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'test', child: Text('Bildirimi test et')),
                    ],
                  ),
                ),
              ],
            ),
            _weekStrip(context, now),
            _summary(context, items, isToday, now),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: 48,
                itemBuilder: (ctx, slot) =>
                    _slot(ctx, slot, items, isToday && slot == nowSlot),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ekle', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  /// Seçili günün haftası; sağa/sola kaydırınca hafta değişir.
  Widget _weekStrip(BuildContext context, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final monday = DateTime(_day.year, _day.month, _day.day - (_day.weekday - 1));
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) _shift(7);
        if (v > 200) _shift(-7);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Builder(builder: (_) {
                final d = DateTime(monday.year, monday.month, monday.day + i);
                final selected = sameDay(d, _day);
                final today = sameDay(d, now);
                final hasItems = store.items.any((it) => it.occursOn(d));
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _day = d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppTheme.red : AppTheme.surface1,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected
                              ? AppTheme.red
                              : today
                                  ? AppTheme.red.withValues(alpha: 0.7)
                                  : AppTheme.border,
                        ),
                        boxShadow: selected
                            ? [BoxShadow(color: AppTheme.red.withValues(alpha: 0.4), blurRadius: 14)]
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(trWeekdaysShort[i],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: selected ? Colors.white70 : scheme.onSurfaceVariant,
                              )),
                          const SizedBox(height: 4),
                          Text('${d.day}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: selected ? Colors.white : scheme.onSurface,
                              )),
                          const SizedBox(height: 4),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: !hasItems
                                  ? Colors.transparent
                                  : selected
                                      ? Colors.white
                                      : AppTheme.redBright,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  /// Gün özeti: etkinlik sayısı ve sıradaki etkinlik.
  Widget _summary(BuildContext context, List<ScheduleItem> items, bool isToday, DateTime now) {
    final theme = Theme.of(context);
    final nowMin = now.hour * 60 + now.minute;
    final next = isToday
        ? items.where((i) => i.startMinutes >= nowMin).firstOrNull
        : items.firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(
        children: [
          Text(
              items.isEmpty
                  ? '0 etkinlik'
                  : '${items.where((i) => store.isDone(i, _day)).length}/${items.length} tamamlandı',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          if (next != null)
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.red.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${isToday ? 'Sıradaki' : 'İlk'}: ${next.title} · ${fmtMinutes(next.startMinutes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.redBright, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            )
          else
            Flexible(
              child: Text('Boş bir saate dokunarak ekle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
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
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openEditor(startMinutes: minute),
        child: SizedBox(
          height: slotHeight - 8,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: isHour ? 0.9 : 0.35),
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: slotHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Padding(
              padding: const EdgeInsets.only(top: 22, left: 4),
              child: isNow
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(fmtMinutes(minute),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                    )
                  : Text(
                      fmtMinutes(minute),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isHour ? FontWeight.w700 : FontWeight.w400,
                        color: isHour
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, ScheduleItem i) {
    final c = itemColors[i.colorIndex % itemColors.length];
    final theme = Theme.of(context);
    final cat = categoryOf(i.category);
    final done = store.isDone(i, _day);
    final streak = store.streak(i, _day);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: done
              ? [c.withValues(alpha: 0.10), c.withValues(alpha: 0.03)]
              : [c.withValues(alpha: 0.28), c.withValues(alpha: 0.08)],
        ),
        border: Border.all(color: c.withValues(alpha: done ? 0.2 : 0.4)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openEditor(existing: i),
          onLongPress: () => _delete(i),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              children: [
                // Kategori ikonu (yoksa renk çubuğu)
                if (cat != null)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.withValues(alpha: 0.5)),
                    ),
                    child: Icon(cat.icon, color: c, size: 24),
                  )
                else
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)],
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: done ? theme.colorScheme.onSurfaceVariant : null,
                            decoration: done ? TextDecoration.lineThrough : null,
                          )),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded,
                              size: 13, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('${i.timeLabel} · ${i.repeatLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                          ),
                          if (i.notify) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.notifications_active_rounded,
                                size: 13, color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ],
                      ),
                      if (streak > 0) ...[
                        const SizedBox(height: 6),
                        _streakChip(i, streak),
                      ],
                    ],
                  ),
                ),
                _doneButton(i, c, done),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 🔥 "12 gün üst üste" rozeti.
  Widget _streakChip(ScheduleItem i, int n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          _flame.withValues(alpha: 0.28),
          AppTheme.red.withValues(alpha: 0.12),
        ]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _flame.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded, size: 16, color: _flame),
          const SizedBox(width: 3),
          Text(_streakLabel(i, n),
              style: const TextStyle(color: _flame, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _doneButton(ScheduleItem i, Color c, bool done) {
    return IconButton(
      tooltip: done ? 'Tamamlanmadı olarak işaretle' : 'Tamamlandı',
      onPressed: () => _toggleDone(i),
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? c : Colors.transparent,
          border: Border.all(color: done ? c : c.withValues(alpha: 0.7), width: 2),
          boxShadow: done ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10)] : null,
        ),
        child: Icon(Icons.check_rounded,
            size: 20, color: done ? Colors.white : c.withValues(alpha: 0.5)),
      ),
    );
  }

  Widget _ongoing(BuildContext context, List<ScheduleItem> list) {
    final i = list.first;
    final c = itemColors[i.colorIndex % itemColors.length];
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openEditor(existing: i),
      child: Container(
        height: slotHeight - 8,
        margin: const EdgeInsets.only(left: 10),
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.withValues(alpha: 0.5), width: 2)),
        ),
        alignment: Alignment.centerLeft,
        child: Text('${list.map((e) => e.title).join(', ')} devam ediyor',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: c.withValues(alpha: 0.9),
                  fontStyle: FontStyle.italic,
                )),
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
  int _streak(ScheduleItem i) => Store.instance.streak(i, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <Repeat, List<ScheduleItem>>{};
    for (final i in Store.instance.items) {
      groups.putIfAbsent(i.repeat, () => []).add(i);
    }
    for (final g in groups.values) {
      g.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tüm kayıtlar')),
      body: groups.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_busy_rounded,
                      size: 56, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  const Text('Henüz kayıt yok'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                for (final r in Repeat.values)
                  if (groups[r] != null) ...[
                    SectionLabel(r.label, trailing: Text('${groups[r]!.length}')),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surface1,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (idx, i) in groups[r]!.indexed) ...[
                            if (idx > 0) const Divider(indent: 56),
                            ListTile(
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: itemColors[i.colorIndex % itemColors.length]
                                      .withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(categoryOf(i.category)?.icon ?? Icons.circle,
                                    size: categoryOf(i.category) == null ? 12 : 20,
                                    color: itemColors[i.colorIndex % itemColors.length]),
                              ),
                              title: Text(i.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${i.timeLabel} · ${i.repeatLabel}'
                                  '${_streak(i) > 0 ? ' · 🔥 ${_streak(i)}' : ''}'),
                              onTap: () async {
                                await widget.onEdit(i);
                                if (mounted) setState(() {});
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () async {
                                  await widget.onDelete(i);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
              ],
            ),
    );
  }
}
