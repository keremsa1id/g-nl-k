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
  Color(0xFF4DA3FF),
  Color(0xFF66BB6A),
  Color(0xFF5C6BC0),
  Color(0xFFB0BEC5),
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

/// Düzenleyicide tek bir hatırlatma satırı.
class _ReminderRow {
  _ReminderRow(this.offset, String note) : note = TextEditingController(text: note);

  int offset;
  final TextEditingController note;
}

class _ItemEditorState extends State<ItemEditor> {
  late final TextEditingController _title;
  late int _start;
  late int _duration;
  late Repeat _repeat;
  late DateTime _date;
  late Set<int> _weekdays;
  late List<_ReminderRow> _reminders;
  late int _color;
  int? _category;
  String? _group; // kategori filtresi, null = tümü
  bool _durationTouched = false;
  DateTime? _endDate;
  late final TextEditingController _note;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _endDate = e?.endDate;
    _group = categoryOf(e?.category)?.group;
    _durationTouched = e != null;
    _start = e?.startMinutes ?? widget.startMinutes;
    _duration = e?.durationMinutes ?? 60;
    _repeat = e?.repeat ?? Repeat.daily;
    _date = e?.startDate ?? widget.day;
    _weekdays = {...(e?.weekdays ?? [widget.day.weekday])};
    _reminders = [
      for (final r in e?.reminders ?? const [Reminder(5)]) _ReminderRow(r.minutesBefore, r.note),
    ];
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
      // Yeni etkinlikte süreye dokunulmadıysa kategorinin önerdiği süreyi kullan.
      if (_category != null && !_durationTouched) _duration = categories[i].minutes;
      _error = null;
    });
  }

  /// Başlık bir kategorinin adıyla aynıysa (örn. "koşu") kategoriyi kendiliğinden seç.
  void _onTitleChanged(String v) {
    final match = categoryForTitle(v);
    setState(() {
      _error = null;
      if (_category == null && match != null) {
        _category = match;
        _group = categories[match].group;
        if (!_durationTouched) _duration = categories[match].minutes;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final d = await showDatePicker(
      context: context,
      helpText: 'Son gün',
      initialDate: _endDate ?? DateTime(_date.year, _date.month + 1, _date.day),
      firstDate: _date,
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) setState(() => _endDate = d);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    for (final r in _reminders) {
      r.note.dispose();
    }
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
    final end = _repeat == Repeat.once ? null : _endDate;
    if (end != null && dateOnly(end).isBefore(dateOnly(_date))) {
      setState(() => _error = 'Bitiş tarihi başlangıçtan önce olamaz');
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
        reminders: [
          for (final r in _reminders) Reminder(r.offset, r.note.text.trim()),
        ],
        colorIndex: _color,
        category: _category,
        endDate: end == null ? null : dateOnly(end),
        note: _note.text.trim(),
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
              onChanged: _onTitleChanged,
              decoration: const InputDecoration(labelText: 'Ne yapacaksın? (örn. Spor)'),
            ),
            const SizedBox(height: 16),
            _categorySection(context),
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
                      if (v != null) {
                        setState(() {
                          _duration = v;
                          _durationTouched = true;
                        });
                      }
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
                  for (final (label, days) in const [
                    ('Hafta içi', {1, 2, 3, 4, 5}),
                    ('Hafta sonu', {6, 7}),
                    ('Pzt · Çar · Cum', {1, 3, 5}),
                    ('Sal · Per', {2, 4}),
                  ])
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _weekdays.length == days.length && _weekdays.containsAll(days),
                      onSelected: (_) => setState(() => _weekdays = {...days}),
                    ),
                ],
              ),
              const SizedBox(height: 8),
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
            if (_repeat != Repeat.once)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy_rounded),
                title: const Text('Bitiş tarihi'),
                subtitle: Text(_endDate == null
                    ? 'Yok · süresiz devam eder'
                    : '${fmtDate(_endDate!)} · ${dateOnly(_endDate!).difference(dateOnly(_date)).inDays + 1} gün'),
                trailing: _endDate == null
                    ? const Icon(Icons.add_rounded)
                    : IconButton(
                        tooltip: 'Bitiş tarihini kaldır',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _endDate = null),
                      ),
                onTap: _pickEndDate,
              ),
            const SizedBox(height: 8),
            _remindersSection(context),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Not (isteğe bağlı)',
                hintText: 'Adres, link, yapılacaklar…',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Text('Renk', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
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

  /// Grup filtresi + yatay kayan iki satırlık kategori ızgarası.
  Widget _categorySection(BuildContext context) {
    final theme = Theme.of(context);
    final visible = [
      for (var i = 0; i < categories.length; i++)
        if (_group == null || categories[i].group == _group) i,
    ];
    final selected = categoryOf(_category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Kategori', style: theme.textTheme.labelLarge),
            const Spacer(),
            if (selected != null)
              Text(selected.name,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: itemColors[_color])),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final g in <String?>[null, ...categoryGroups])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(g ?? 'Tümü', style: const TextStyle(fontSize: 12)),
                    selected: _group == g,
                    onSelected: (_) => setState(() => _group = g),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 2 * 78 + 8,
          child: GridView.count(
            key: ValueKey(_group),
            scrollDirection: Axis.horizontal,
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 78 / 74,
            children: [for (final i in visible) _categoryTile(context, i)],
          ),
        ),
      ],
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

  void _addReminder() {
    final used = _reminders.map((r) => r.offset).toSet();
    final next = reminderOffsets.firstWhere((o) => !used.contains(o), orElse: () => 15);
    setState(() => _reminders.add(_ReminderRow(next, '')));
  }

  void _removeReminder(_ReminderRow r) {
    setState(() => _reminders.remove(r));
    r.note.dispose();
  }

  /// "Hatırlatmalar" bölümü: her biri ayrı zamanlı ve isteğe bağlı notlu.
  Widget _remindersSection(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = itemColors[_color];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Hatırlatmalar', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            if (_reminders.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${_reminders.length}',
                    style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            const Spacer(),
            Icon(Icons.vibration_rounded, size: 16, color: muted),
            const SizedBox(width: 4),
            Text('titreşimli', style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
        const SizedBox(height: 8),
        if (_reminders.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Bildirim yok. Aşağıdan hatırlatma ekleyebilirsin.',
                style: TextStyle(color: muted, fontSize: 13)),
          ),
        for (final r in _reminders)
          Container(
            key: ObjectKey(r),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF151518),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF26262B)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.notifications_active_rounded, size: 20, color: accent),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: r.offset,
                      underline: const SizedBox(),
                      borderRadius: BorderRadius.circular(14),
                      dropdownColor: const Color(0xFF1D1D21),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                      items: [
                        for (final o in {...reminderOffsets, r.offset}.toList()..sort())
                          DropdownMenuItem(value: o, child: Text(fmtOffset(o))),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => r.offset = v);
                      },
                    ),
                    const Spacer(),
                    Text(
                      r.offset >= 1440
                          ? 'önceki gün ${fmtMinutes((_start - r.offset) % 1440)}'
                          : r.offset > _start
                              ? 'önceki gün ${fmtMinutes((_start - r.offset + 1440) % 1440)}'
                              : fmtMinutes(_start - r.offset),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    IconButton(
                      tooltip: 'Kaldır',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => _removeReminder(r),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextField(
                    controller: r.note,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Not ekle (isteğe bağlı) · örn. Spor çantasını hazırla',
                      isDense: true,
                      prefixIcon: Icon(Icons.edit_note_rounded, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _reminders.length >= 12 ? null : _addReminder,
          icon: const Icon(Icons.add_alert_rounded),
          label: Text(_reminders.isEmpty ? 'Hatırlatma ekle' : 'Başka bir hatırlatma ekle'),
        ),
      ],
    );
  }
}
