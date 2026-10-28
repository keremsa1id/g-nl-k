import 'package:flutter/material.dart';

import '../categories.dart';
import '../models.dart';
import '../storage.dart';
import '../streaks.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_editor.dart';

/// Etkinliğin seri, ısı haritası ve rozetlerini gösteren detay sayfası.
class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({
    super.key,
    required this.itemId,
    required this.onEdit,
    required this.onDelete,
  });

  final int itemId;
  final Future<void> Function(ScheduleItem) onEdit;
  final Future<void> Function(ScheduleItem) onDelete;

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  static const _weeks = 15;
  static const _cell = 16.0;
  static const _gap = 4.0;

  final store = Store.instance;

  @override
  Widget build(BuildContext context) {
    final item = store.items.where((i) => i.id == widget.itemId).firstOrNull;
    if (item == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Kayıt silindi')));
    }
    final theme = Theme.of(context);
    final c = itemColors[item.colorIndex % itemColors.length];
    final cat = categoryOf(item.category);
    final today = dateOnly(DateTime.now());
    final current = store.streak(item, today);
    final best = store.bestStreak(item);
    final (done30, total30) =
        store.tally(item, DateTime(today.year, today.month, today.day - 29), today);
    final totalDone = store.done[item.id]?.length ?? 0;
    final flame = flameColor(current);

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Düzenle',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await widget.onEdit(item);
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Sil',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              await widget.onDelete(item);
              if (!mounted) return;
              if (!store.items.any((i) => i.id == item.id)) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // Başlık
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.withValues(alpha: 0.5)),
                ),
                child: Icon(cat?.icon ?? Icons.event_rounded, color: c, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text('${item.timeLabel} · ${item.repeatLabel}',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Seri kartı
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [flame.withValues(alpha: 0.30), AppTheme.surface1],
              ),
              border: Border.all(color: flame.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.local_fire_department_rounded, size: 56, color: flame),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('$current',
                              style: const TextStyle(
                                  fontSize: 44, fontWeight: FontWeight.w900, height: 1)),
                          const SizedBox(width: 6),
                          if (badgeFor(current) != null)
                            Text(badgeFor(current)!, style: const TextStyle(fontSize: 28)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                          current == 0
                              ? 'Henüz seri yok, bugün başla!'
                              : streakLabel(item, current),
                          style: TextStyle(color: flame, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    const Text('EN İYİ',
                        style: TextStyle(
                            fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w700)),
                    Text('$best',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _miniStat(context, 'Son 30 gün',
                      total30 == 0 ? '-' : '%${(done30 * 100 / total30).round()}', '$done30/$total30')),
              const SizedBox(width: 10),
              Expanded(child: _miniStat(context, 'Toplam', '$totalDone', 'kez yapıldı')),
              const SizedBox(width: 10),
              Expanded(child: _miniStat(context, 'En iyi seri', '$best', 'rekor')),
            ],
          ),
          if (item.reminders.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionLabel('Hatırlatmalar'),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface1,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  for (final (idx, r) in item.reminders.indexed) ...[
                    if (idx > 0) const Divider(indent: 56),
                    ListTile(
                      leading: Icon(Icons.notifications_active_rounded, color: c),
                      title: Text(fmtOffset(r.minutesBefore),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: r.note.isEmpty ? null : Text('📝 ${r.note}'),
                      trailing: Text(
                          fmtMinutes((item.startMinutes - r.minutesBefore) % 1440),
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const SectionLabel('Son 15 hafta'),
          _heatmap(context, item, c, today),
          const SizedBox(height: 24),
          const SectionLabel('Rozetler'),
          Row(
            children: [
              for (final (idx, (min, emoji, name)) in badgeTiers.indexed) ...[
                if (idx > 0) const SizedBox(width: 10),
                Expanded(child: _badge(context, emoji, name, min, best)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value, String sub) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.redBright, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(sub, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// GitHub tarzı ısı haritası: sütunlar haftalar, satırlar Pzt..Paz.
  Widget _heatmap(BuildContext context, ScheduleItem item, Color c, DateTime today) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final thisMonday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final firstMonday =
        DateTime(thisMonday.year, thisMonday.month, thisMonday.day - 7 * (_weeks - 1));

    Widget cell(DateTime d) {
      final future = d.isAfter(today);
      final planned = item.occursOn(d);
      final done = store.isDone(item, d);
      return Container(
        width: _cell,
        height: _cell,
        margin: const EdgeInsets.only(bottom: _gap),
        decoration: BoxDecoration(
          color: done
              ? c
              : planned && !future
                  ? AppTheme.surface3
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: sameDay(d, today)
              ? Border.all(color: Colors.white, width: 1.5)
              : planned && future
                  ? Border.all(color: c.withValues(alpha: 0.4))
                  : !planned
                      ? Border.all(color: AppTheme.border)
                      : null,
          boxShadow: done ? [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 4)] : null,
        ),
      );
    }

    final labelStyle = TextStyle(fontSize: 9, color: muted);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gün adları
                Column(
                  children: [
                    const SizedBox(height: 14),
                    for (var d = 0; d < 7; d++)
                      SizedBox(
                        width: 26,
                        height: _cell + _gap,
                        child: Text(d.isEven ? trWeekdaysShort[d] : '', style: labelStyle),
                      ),
                  ],
                ),
                for (var w = 0; w < _weeks; w++)
                  Builder(builder: (_) {
                    final monday =
                        DateTime(firstMonday.year, firstMonday.month, firstMonday.day + 7 * w);
                    final prev = DateTime(monday.year, monday.month, monday.day - 7);
                    final showMonth = w == 0 || prev.month != monday.month;
                    return Padding(
                      padding: const EdgeInsets.only(right: _gap),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 14,
                            width: _cell,
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              maxWidth: 40,
                              child: Text(
                                  showMonth ? trMonths[monday.month - 1].substring(0, 3) : '',
                                  style: labelStyle),
                            ),
                          ),
                          for (var d = 0; d < 7; d++)
                            cell(DateTime(monday.year, monday.month, monday.day + d)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legend(c, 'Yapıldı', labelStyle),
              const SizedBox(width: 12),
              _legend(AppTheme.surface3, 'Kaçırıldı', labelStyle),
              const SizedBox(width: 12),
              _legend(Colors.transparent, 'Plan yok', labelStyle, border: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String text, TextStyle style, {bool border = false}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: border ? Border.all(color: AppTheme.border) : null,
            ),
          ),
          const SizedBox(width: 4),
          Text(text, style: style),
        ],
      );

  Widget _badge(BuildContext context, String emoji, String name, int min, int best) {
    final earned = best >= min;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: earned ? AppTheme.red.withValues(alpha: 0.14) : AppTheme.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: earned ? AppTheme.red.withValues(alpha: 0.5) : AppTheme.border),
      ),
      child: Column(
        children: [
          Opacity(
            opacity: earned ? 1 : 0.25,
            child: Text(emoji, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('$min gün',
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (!earned) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (best / min).clamp(0.0, 1.0),
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ],
      ),
    );
  }
}
