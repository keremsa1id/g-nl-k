import 'package:flutter/material.dart';

import '../categories.dart';
import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import 'item_editor.dart';

/// 7 sütunlu haftalık tablo. Bir güne dokununca o gün seçilerek geri döner.
class WeekViewPage extends StatefulWidget {
  const WeekViewPage({super.key, required this.initialDay});

  final DateTime initialDay;

  @override
  State<WeekViewPage> createState() => _WeekViewPageState();
}

class _WeekViewPageState extends State<WeekViewPage> {
  static const _hourH = 44.0;
  static const _labelW = 40.0;

  final store = Store.instance;
  late DateTime _monday;
  final _scroll = ScrollController(initialScrollOffset: 7 * _hourH);

  @override
  void initState() {
    super.initState();
    final d = widget.initialDay;
    _monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _shift(int weeks) =>
      setState(() => _monday = DateTime(_monday.year, _monday.month, _monday.day + 7 * weeks));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final days = [for (var i = 0; i < 7; i++) DateTime(_monday.year, _monday.month, _monday.day + i)];
    final sunday = days.last;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${_monday.day} ${trMonths[_monday.month - 1].substring(0, 3)} – '
            '${sunday.day} ${trMonths[sunday.month - 1].substring(0, 3)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shift(-1)),
          IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _shift(1)),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) _shift(1);
          if (v > 200) _shift(-1);
        },
        child: Column(
          children: [
            // Gün başlıkları
            Padding(
              padding: const EdgeInsets.fromLTRB(_labelW, 0, 4, 8),
              child: Row(
                children: [
                  for (final (i, d) in days.indexed)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, d),
                        child: Column(
                          children: [
                            Text(trWeekdaysShort[i],
                                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            Container(
                              width: 30,
                              height: 30,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: sameDay(d, now) ? AppTheme.red : Colors.transparent,
                              ),
                              child: Text('${d.day}',
                                  style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  height: 24 * _hourH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: _labelW,
                        child: Stack(
                          children: [
                            for (var h = 1; h < 24; h++)
                              Positioned(
                                top: h * _hourH - 7,
                                left: 0,
                                right: 6,
                                child: Text('${two(h)}:00',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                              ),
                          ],
                        ),
                      ),
                      for (final d in days) Expanded(child: _dayColumn(context, d, now)),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayColumn(BuildContext context, DateTime day, DateTime now) {
    final items = store.items.where((i) => i.occursOn(day)).toList();
    final isToday = sameDay(day, now);
    return GestureDetector(
      onTap: () => Navigator.pop(context, day),
      child: Container(
        decoration: BoxDecoration(
          color: isToday ? AppTheme.red.withValues(alpha: 0.05) : null,
          border: const Border(left: BorderSide(color: AppTheme.border)),
        ),
        child: Stack(
          children: [
            for (var h = 1; h < 24; h++)
              Positioned(
                top: h * _hourH,
                left: 0,
                right: 0,
                child: Container(height: 1, color: AppTheme.border.withValues(alpha: 0.6)),
              ),
            for (final i in items) _block(i, day),
            if (isToday)
              Positioned(
                top: (now.hour * 60 + now.minute) / 60 * _hourH,
                left: 0,
                right: 0,
                child: Container(height: 2, color: AppTheme.redBright),
              ),
          ],
        ),
      ),
    );
  }

  Widget _block(ScheduleItem i, DateTime day) {
    final c = itemColors[i.colorIndex % itemColors.length];
    final done = store.isDone(i, day);
    final cat = categoryOf(i.category);
    final h = i.durationMinutes / 60 * _hourH;
    return Positioned(
      top: i.startMinutes / 60 * _hourH + 1,
      left: 2,
      right: 2,
      height: (h - 2).clamp(18.0, double.infinity),
      child: Container(
        padding: const EdgeInsets.all(3),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.withValues(alpha: done ? 0.15 : 0.35),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: c, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(done ? Icons.check_circle_rounded : (cat?.icon ?? Icons.circle),
                    size: 11, color: c),
              ],
            ),
            if (h > 30)
              Flexible(
                child: Text(i.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      decoration: done ? TextDecoration.lineThrough : null,
                    )),
              ),
          ],
        ),
      ),
    );
  }
}
