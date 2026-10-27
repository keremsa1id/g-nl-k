import 'package:flutter/material.dart';

import '../categories.dart';
import '../models.dart';
import '../storage.dart';

const itemColors = <Color>[
  Color(0xFFE53935),
  Color(0xFFFF4D6D),
  Color(0xFFFF7A45),
  Color(0xFFFFB020),
  Color(0xFF9B5DE5),
  Color(0xFF2EC4B6),
];

/// Etkinlik ekleme / düzenleme alt sayfası. Kaydedince ScheduleItem döner.
class ItemEditor extends StatefulWidget {
  const ItemEditor({
    super.key,
    this.existing,
    required this.day,
    required this.startMinutes,
  });

  final ScheduleItem? existing;
  final DateTime day;
  final int startMinutes;

  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  late final TextEditingController _title;
  late int _start;
  late int _duration;
  late Repeat _repeat;
  late DateTime _date;
  late Set<int> _weekdays;
  late bool _notify;
  late int _color;
  int? _category;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _start = e?.startMinutes ?? widget.startMinutes;
    _duration = e?.durationMinutes ?? 60;
    _repeat = e?.repeat ?? Repeat.daily;
    _date = e?.startDate ?? widget.day;
    _weekdays = {...(e?.weekdays ?? [widget.day.weekday])};
    _notify = e?.notify ?? true;
    _color = e?.colorIndex ?? 0;
    _category = e?.category;
  }

  void _pickCategory(int i) {
    setState(() {
      final prev = categoryOf(_category)?.name;
      final t = _title.text.trim();
      // Başlık boşsa ya da önceki kategorinin adıysa yeni kategorinin adını yaz.
      if (t.isEmpty || t == prev) _title.text = categories[i].name;
      _category = _category == i ? null : i;
      _error = null;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Bir başlık gir');
      return;
    }
    if (_repeat == Repeat.weekly && _weekdays.isEmpty) {
      setState(() => _error = 'En az bir gün seç');
      return;
    }
    final maxDuration = 24 * 60 - _start;
    Navigator.pop(
      context,
      ScheduleItem(
        id: widget.existing?.id ?? Store.instance.newId(),
        title: title,
        startMinutes: _start,
        durationMinutes: _duration > maxDuration ? maxDuration : _duration,
        repeat: _repeat,
        startDate: dateOnly(_date),
        weekdays: _weekdays.toList()..sort(),
        notify: _notify,
        colorIndex: _color,
        category: _category,
      ),
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Yeni etkinlik' : 'Etkinliği düzenle',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Ne yapacaksın? (örn. Spor)'),
            ),
            const SizedBox(height: 16),
            Text('Kategori', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: [
                for (var i = 0; i < categories.length; i++) _categoryTile(context, i),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownMenu<int>(
                    label: const Text('Başlangıç'),
                    initialSelection: _start,
                    expandedInsets: EdgeInsets.zero,
                    menuHeight: 300,
                    onSelected: (v) {
                      if (v != null) setState(() => _start = v);
                    },
                    dropdownMenuEntries: [
                      for (var m = 0; m < 24 * 60; m += 30)
                        DropdownMenuEntry(value: m, label: fmtMinutes(m)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownMenu<int>(
                    label: const Text('Süre'),
                    initialSelection: _duration,
                    expandedInsets: EdgeInsets.zero,
                    menuHeight: 300,
                    onSelected: (v) {
                      if (v != null) setState(() => _duration = v);
                    },
                    dropdownMenuEntries: [
                      for (var d = 30; d <= 12 * 60; d += 30)
                        DropdownMenuEntry(value: d, label: fmtDuration(d)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Tekrar', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<Repeat>(
              showSelectedIcon: false,
              segments: [
                for (final r in Repeat.values)
                  ButtonSegment(
                    value: r,
                    label: Text(r.label, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              selected: {_repeat},
              onSelectionChanged: (s) => setState(() => _repeat = s.first),
            ),
            if (_repeat == Repeat.weekly) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(trWeekdaysShort[d - 1]),
                      selected: _weekdays.contains(d),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _weekdays.add(d);
                        } else {
                          _weekdays.remove(d);
                        }
                      }),
                    ),
                ],
              ),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_repeat == Repeat.once ? 'Tarih' : 'Başlangıç tarihi'),
              subtitle: Text(fmtDate(_date) +
                  (_repeat == Repeat.monthly ? ' · her ayın ${_date.day}. günü' : '')),
              onTap: _pickDate,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notify,
              onChanged: (v) => setState(() => _notify = v),
              title: const Text('5 dakika önce bildirim'),
              subtitle: Text('Bildirim saati: ${fmtMinutes((_start - 5 + 1440) % 1440)}'),
            ),
            const SizedBox(height: 4),
            Text('Renk', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (var i = 0; i < itemColors.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: itemColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == i ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: _color == i
                            ? [BoxShadow(color: itemColors[i].withValues(alpha: 0.6), blurRadius: 12)]
                            : null,
                      ),
                      child: _color == i
                          ? const Icon(Icons.check, size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryTile(BuildContext context, int i) {
    final c = categories[i];
    final selected = _category == i;
    final accent = itemColors[_color];
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: () => _pickCategory(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.22) : const Color(0xFF151518),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : const Color(0xFF26262B),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(c.icon, size: 26, color: selected ? accent : muted),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(c.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : muted,
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
