import 'dart:async';

import 'package:flutter/material.dart';

import '../categories.dart';
import '../game.dart';
import '../models.dart';
import '../notifications.dart';
import '../storage.dart';
import '../streaks.dart';
import '../templates.dart';
import '../theme.dart';
import '../widgets.dart';
import 'health_page.dart';
import 'item_detail_page.dart';
import 'item_editor.dart';
import 'journal_page.dart';
import 'profile_page.dart';
import 'screen_time_page.dart';
import 'stats_page.dart';
import 'tracker_setup.dart';
import 'voice_sheet.dart';
import 'week_view_page.dart';

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
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Görünen satırlar arasında şu anki saatin 1 saat öncesine kaydır.
    final idx = _visibleSlots(_dayItems).where((sl) => sl ~/ 2 < now.hour - 1).length;
    _scroll = ScrollController(initialScrollOffset: idx * slotHeight);
    Notifier.changes.addListener(_refresh);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    Notifier.changes.removeListener(_refresh);
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleDone(ScheduleItem item) async {
    if (_day.isAfter(dateOnly(DateTime.now()))) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('İleri bir tarih henüz tamamlanamaz')));
      return;
    }
    final value = !store.isDone(item, _day);
    await store.setDone(item.id, _day, value);
    unawaited(Notifier.refreshExtras());
    Game.instance.changes.value++;
    if (!mounted) return;
    setState(() {});
    if (!value) return;

    final n = store.streak(item, _day);
    final tier = tierReached(n);
    final dayItems = _dayItems;
    final allDone = dayItems.every((i) => store.isDone(i, _day));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (tier != null) {
      final (min, emoji, name) = tier;
      await showCelebration(context,
          emoji: emoji,
          title: '$name rozet!',
          message: '${item.title}: $min ${item.repeat == Repeat.daily ? 'gün' : 'kez'} '
              'üst üste tamamladın. Harika gidiyorsun!');
    } else if (allDone && dayItems.length > 1) {
      await showCelebration(context,
          emoji: '🎉',
          title: 'Günü tamamladın!',
          message: 'Bugünkü ${dayItems.length} etkinliğin hepsi bitti.');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n > 1
            ? '🔥 ${item.title}: ${streakLabel(item, n)}! · +$xpPerDone XP'
            : '✅ ${item.title} tamamlandı · +$xpPerDone XP'),
        action: SnackBarAction(label: 'Geri al', onPressed: () => _toggleDone(item)),
      ));
    }
  }

  Future<void> _snooze(ScheduleItem item) async {
    await Notifier.snooze(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('⏰ ${item.title} 10 dk sonra tekrar hatırlatılacak')));
  }

  Future<void> _openDetail(ScheduleItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ItemDetailPage(
          itemId: item.id,
          onEdit: (i) => _openEditor(existing: i),
          onDelete: _delete,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openWeek() async {
    final d = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute(builder: (_) => WeekViewPage(initialDay: _day)),
    );
    if (d != null && mounted) setState(() => _day = dateOnly(d));
  }

  void _openStats() => Navigator.push(
      context, MaterialPageRoute<void>(builder: (_) => const StatsPage()));

  Future<void> _showTemplates() async {
    final t = await showModalBottomSheet<RoutineTemplate>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _TemplateSheet(),
    );
    if (t == null) return;
    final today = dateOnly(DateTime.now());
    final added = <ScheduleItem>[];
    for (final e in t.entries) {
      if (store.items.any((i) => i.title == e.title && i.startMinutes == e.start)) continue;
      added.add(ScheduleItem(
        id: store.newId(),
        title: e.title,
        startMinutes: e.start,
        durationMinutes: e.duration,
        repeat: Repeat.daily,
        startDate: today,
        weekdays: [today.weekday],
        notify: true,
        colorIndex: e.category % itemColors.length,
        category: e.category,
      ));
    }
    setState(() => store.items.addAll(added));
    await store.saveItems();
    for (final i in added) {
      await Notifier.scheduleItem(i);
    }
    unawaited(Notifier.refreshExtras());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(added.isEmpty
              ? '${t.name} zaten ekli'
              : '${t.emoji} ${t.name}: ${added.length} etkinlik eklendi (her gün)')));
  }

  /// Görünen yarım saatlik satırlar: tüm tam saatler + yalnızca etkinlik başlayan buçuklar.
  static List<int> _visibleSlots(List<ScheduleItem> items) {
    final halfStarts = {
      for (final i in items)
        if (i.startMinutes % 60 == 30) i.startMinutes ~/ 30,
    };
    return [
      for (var sl = 0; sl < 48; sl++)
        if (sl.isEven || halfStarts.contains(sl)) sl,
    ];
  }

  Future<void> _openJournal() async {
    await Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => JournalPage(day: _day)));
    if (mounted) setState(() {});
  }

  List<ScheduleItem> get _dayItems =>
      store.items.where((i) => i.occursOn(_day)).toList()
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

  Future<void> _openEditor(
      {ScheduleItem? existing, int? startMinutes, int? initialCategory}) async {
    final result = await showModalBottomSheet<ScheduleItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ItemEditor(
        existing: existing,
        day: _day,
        startMinutes: startMinutes ?? existing?.startMinutes ?? 18 * 60,
        initialCategory: initialCategory,
      ),
    );
    if (result == null) return;
    await _saveItem(result);
  }

  Future<void> _saveItem(ScheduleItem result) async {
    setState(() {
      store.items.removeWhere((i) => i.id == result.id);
      store.items.add(result);
    });
    await store.saveItems();
    if (result.hasAlarm) await Notifier.requestAlarmPermissions();
    await Notifier.scheduleItem(result);
    unawaited(Notifier.refreshExtras());
  }

  /// Sesli komut: etkinliği doğrudan ekler ya da düzenleyicide açar.
  Future<void> _testAlarm() async {
    final err = await Notifier.testAlarm();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(err ??
          '⏰ Alarm 15 saniye sonra çalacak. Ekranı kilitleyip bekle; '
              'çalmazsa telefonun pil/otomatik başlatma ayarlarına bakmak gerekir.'),
    ));
  }

  Future<void> _voice() async {
    final r = await showVoiceSheet(context);
    if (r == null || !mounted) return;
    final (draft, edit) = r;
    // Taslağa kalıcı bir id ver.
    final item = ScheduleItem.fromJson({...draft.toJson(), 'id': store.newId()});
    if (edit) {
      await _openEditor(existing: item);
      return;
    }
    await _saveItem(item);
    if (!mounted) return;
    // Eklenen günü göster.
    final first = _firstOccurrence(item);
    if (first != null) setState(() => _day = first);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('🎙️ ${item.title} eklendi · ${item.timeLabel} · ${item.repeatLabel}'),
        action: SnackBarAction(label: 'Düzenle', onPressed: () => _openEditor(existing: item)),
      ));
  }

  DateTime? _firstOccurrence(ScheduleItem item) {
    final today = dateOnly(DateTime.now());
    for (var i = 0; i < 400; i++) {
      final d = DateTime(today.year, today.month, today.day + i);
      if (item.occursOn(d)) return d;
    }
    return null;
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
    unawaited(Notifier.refreshExtras());
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
    final slots = _visibleSlots(items);
    // Buçuk satırı gizliyse "şimdi" vurgusu tam saat satırında kalır.
    final halfNow = now.hour * 2 + 1;
    final nowSlot = now.minute >= 30 && slots.contains(halfNow) ? halfNow : now.hour * 2;

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
                    onSelected: (v) => switch (v) {
                      'week' => _openWeek(),
                      'templates' => _showTemplates(),
                      'stats' => _openStats(),
                      // Profildeki uyanma saati, yarım saate yuvarlanmış.
                      'wake' => _openEditor(
                          startMinutes: Game.instance.profile.wakeMinutes ~/ 30 * 30,
                          initialCategory: wakeCategory),
                      'screen' => Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) => const ScreenTimePage())),
                      'health' => Navigator.push(context,
                          MaterialPageRoute<void>(builder: (_) => const HealthPage())),
                      'tracker' => showTrackerSetup(context),
                      'alarmtest' => _testAlarm(),
                      _ => Notifier.showTest(),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'week',
                          child: ListTile(
                              leading: Icon(Icons.view_week_rounded),
                              title: Text('Haftalık görünüm'))),
                      PopupMenuItem(
                          value: 'templates',
                          child: ListTile(
                              leading: Icon(Icons.auto_awesome_rounded),
                              title: Text('Hazır şablonlar'))),
                      PopupMenuItem(
                          value: 'wake',
                          child: ListTile(
                              leading: Icon(Icons.alarm_add_rounded),
                              title: Text('Sabah alarmı kur'))),
                      PopupMenuItem(
                          value: 'stats',
                          child: ListTile(
                              leading: Icon(Icons.insights_rounded),
                              title: Text('İstatistikler'))),
                      PopupMenuItem(
                          value: 'health',
                          child: ListTile(
                              leading: Icon(Icons.favorite_rounded),
                              title: Text('Sağlık (adım, uyku)'))),
                      PopupMenuItem(
                          value: 'screen',
                          child: ListTile(
                              leading: Icon(Icons.phone_android_rounded),
                              title: Text('Ekran süresi'))),
                      PopupMenuItem(
                          value: 'tracker',
                          child: ListTile(
                              leading: Icon(Icons.add_task_rounded),
                              title: Text('Takip ekle (sigara, alkol…)'))),
                      PopupMenuItem(
                          value: 'alarmtest',
                          child: ListTile(
                              leading: Icon(Icons.alarm_on_rounded),
                              title: Text('Alarmı test et'))),
                      PopupMenuItem(
                          value: 'test',
                          child: ListTile(
                              leading: Icon(Icons.notifications_none_rounded),
                              title: Text('Bildirimi test et'))),
                    ],
                  ),
                ),
                const ProfileButton(),
              ],
            ),
            _weekStrip(context, now),
            _todayPanel(context, items, isToday, now),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: slots.length + 1,
                itemBuilder: (ctx, k) => k == slots.length
                    ? _dayFooter(ctx, items, isToday, now)
                    : _slot(ctx, slots[k], items, isToday && slots[k] == nowSlot),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'voice',
            tooltip: 'Sesle ekle',
            backgroundColor: AppTheme.surface3,
            foregroundColor: Colors.white,
            onPressed: _voice,
            child: const Icon(Icons.mic_rounded),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'add',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ekle', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Seçili günün haftası; sağa/sola kaydırınca hafta değişir.
  Widget _weekStrip(BuildContext context, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final monday = DateTime(_day.year, _day.month, _day.day - (_day.weekday - 1));
    return GestureDetector(
      onLongPress: _openWeek,
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

  /// Günün ilerleme halkası + şu an devam eden / sıradaki etkinlik.
  Widget _todayPanel(BuildContext context, List<ScheduleItem> items, bool isToday, DateTime now) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final total = items.length;
    final doneCount = items.where((i) => store.isDone(i, _day)).length;
    final allDone = total > 0 && doneCount == total;
    final nowMin = now.hour * 60 + now.minute;
    final current = isToday
        ? items.where((i) => i.startMinutes <= nowMin && i.endMinutes > nowMin).firstOrNull
        : null;
    final next = isToday
        ? items.where((i) => i.startMinutes > nowMin).firstOrNull
        : items.firstOrNull;

    Widget pill(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          child: Text(text,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Colors.white)),
        );

    Widget info;
    if (current != null) {
      final c = itemColors[current.colorIndex % itemColors.length];
      final left = current.endMinutes - nowMin;
      final p = (nowMin - current.startMinutes) / current.durationMinutes;
      info = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              pill('ŞİMDİ', AppTheme.red),
              const SizedBox(width: 8),
              Flexible(
                child: Text(current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: p.clamp(0.0, 1.0),
            minHeight: 6,
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 4),
          Text(
              '${fmtDuration(left)} kaldı'
              '${next != null ? ' · Sıradaki: ${next.title} ${fmtMinutes(next.startMinutes)}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: muted)),
        ],
      );
    } else if (next != null) {
      info = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              pill(isToday ? 'SIRADAKİ' : 'İLK', AppTheme.surface3),
              const SizedBox(width: 8),
              Flexible(
                child: Text(next.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              isToday
                  ? '${fmtMinutes(next.startMinutes)} · ${fmtDuration(next.startMinutes - nowMin)} sonra'
                  : next.timeLabel,
              style: TextStyle(fontSize: 12, color: muted)),
        ],
      );
    } else {
      info = Text(
        total == 0
            ? 'Boş gün. Bir saate dokun ya da menüden hazır şablon ekle.'
            : allDone
                ? 'Günü tamamladın! 🎉'
                : 'Bugün için başka etkinlik yok',
        style: TextStyle(
            color: allDone ? AppTheme.redBright : muted,
            fontWeight: allDone ? FontWeight.w800 : FontWeight.w500),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: allDone ? AppTheme.red.withValues(alpha: 0.7) : AppTheme.border),
          boxShadow: allDone
              ? [BoxShadow(color: AppTheme.red.withValues(alpha: 0.3), blurRadius: 20)]
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              height: 62,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: total == 0 ? 0 : doneCount / total),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => CustomPaint(
                      size: const Size.square(62),
                      painter: RingPainter(v, stroke: 7),
                    ),
                  ),
                  allDone
                      ? const Icon(Icons.check_rounded, color: AppTheme.redBright, size: 28)
                      : Text('$doneCount/$total',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: info),
          ],
        ),
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
    return Dismissible(
      key: ValueKey('card-${i.id}-${dayKey(_day)}'),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await _toggleDone(i);
        } else {
          await _snooze(i);
        }
        return false; // kart yerinde kalır
      },
      background: _swipeBg(Icons.check_rounded, done ? 'Geri al' : 'Tamamla', c, true),
      secondaryBackground:
          _swipeBg(Icons.snooze_rounded, '10 dk ertele', const Color(0xFF5C6BC0), false),
      child: AnimatedContainer(
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
          onTap: () => _openDetail(i),
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
                            if (i.reminders.length > 1)
                              Text('${i.reminders.length}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurfaceVariant)),
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
    ),
    );
  }

  Widget _swipeBg(IconData icon, String label, Color color, bool left) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: left ? Alignment.centerLeft : Alignment.centerRight,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          ],
        ),
      );

  /// 🔥 "12 gün üst üste" rozeti; renk seriye göre değişir, eşiklerde madalya çıkar.
  Widget _streakChip(ScheduleItem i, int n) {
    final flame = flameColor(n);
    final badge = badgeFor(n);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 10, 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          flame.withValues(alpha: 0.28),
          flame.withValues(alpha: 0.08),
        ]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: flame.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, size: 16, color: flame),
          const SizedBox(width: 3),
          Text(streakLabel(i, n),
              style: TextStyle(color: flame, fontSize: 12, fontWeight: FontWeight.w800)),
          if (badge != null) ...[
            const SizedBox(width: 4),
            Text(badge, style: const TextStyle(fontSize: 12)),
          ],
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

  /// Listenin en altı: gün özeti ve günlük.
  Widget _dayFooter(BuildContext context, List<ScheduleItem> items, bool isToday, DateTime now) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final today = dateOnly(now);
    final past = _day.isBefore(today);
    final doneItems = items.where((i) => store.isDone(i, _day)).toList();
    final openItems = items.where((i) => !store.isDone(i, _day)).toList();
    final plannedMin = items.fold<int>(0, (a, i) => a + i.durationMinutes);
    final doneMin = doneItems.fold<int>(0, (a, i) => a + i.durationMinutes);

    // Takipler: o günkü sayı ve önceki 7 günün ortalaması
    final trackerStats = [
      for (final t in store.trackers)
        (
          t,
          t.countOn(_day),
          [for (var k = 1; k <= 7; k++) t.countOn(DateTime(_day.year, _day.month, _day.day - k))]
                  .fold<int>(0, (a, b) => a + b) /
              7,
        ),
    ];

    // En uzun seri
    ScheduleItem? topItem;
    var topStreak = 0;
    for (final i in items) {
      final n = store.streak(i, _day);
      if (n > topStreak) {
        topStreak = n;
        topItem = i;
      }
    }

    final journal = store.journalFor(_day);
    final box = BoxDecoration(
      color: AppTheme.surface1,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppTheme.border),
    );

    Widget stat(IconData icon, Color color, String value, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: muted)),
            ],
          ),
        );

    Widget chip(ScheduleItem i, bool done) {
      final c = itemColors[i.colorIndex % itemColors.length];
      return Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
        decoration: BoxDecoration(
          color: done ? c.withValues(alpha: 0.18) : AppTheme.surface3,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(done ? Icons.check_circle_rounded : (categoryOf(i.category)?.icon ?? Icons.circle_outlined),
                size: 14, color: done ? c : muted),
            const SizedBox(width: 4),
            Text(i.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: done ? null : muted,
                )),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Gün özeti'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: box,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    stat(Icons.task_alt_rounded, AppTheme.redBright,
                        '${doneItems.length}/${items.length}', 'tamamlandı'),
                    stat(Icons.schedule_rounded, const Color(0xFF4DA3FF),
                        fmtDuration(doneMin), '${fmtDuration(plannedMin)} planlı'),
                    stat(Icons.local_fire_department_rounded, flameColor(topStreak),
                        '$topStreak', topItem == null ? 'seri' : topItem.title),
                  ],
                ),
                if (trackerStats.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (t, n, avg) in trackerStats)
                        Container(
                          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                          decoration: BoxDecoration(
                            color: (n <= avg ? const Color(0xFF2EC4B6) : AppTheme.red)
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(t.emoji, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 6),
                              Text('$n ${t.unit}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: n <= avg ? const Color(0xFF2EC4B6) : AppTheme.redBright,
                                  )),
                              Text(' · ort. ${avg.toStringAsFixed(1)}',
                                  style: TextStyle(fontSize: 11, color: muted)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (doneItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Tamamlananlar',
                      style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final i in doneItems) chip(i, true)]),
                ],
                if (openItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(past ? 'Kaçırılanlar' : 'Kalanlar',
                      style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final i in openItems) chip(i, false)]),
                ],
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Bu gün için planlanmış etkinlik yok.',
                        style: TextStyle(color: muted)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionLabel('Günlük',
              trailing: journal == null
                  ? null
                  : Text(journal.mood == null ? '' : moods[journal.mood!].$2,
                      style: TextStyle(fontSize: 12, color: muted))),
          Material(
            color: AppTheme.surface1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                  color: journal == null ? AppTheme.border : AppTheme.red.withValues(alpha: 0.4)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _openJournal,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.red.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: journal?.mood != null
                          ? Text(moods[journal!.mood!].$1, style: const TextStyle(fontSize: 26))
                          : const Icon(Icons.edit_note_rounded, color: AppTheme.redBright, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              journal == null
                                  ? (isToday ? 'Bugün nasıl geçti?' : 'Bu güne not düş')
                                  : 'Günlüğün',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            journal == null || journal.text.trim().isEmpty
                                ? 'Düşüncelerini, ruh halini ve günün notlarını yazmak için dokun.'
                                : journal.text.trim(),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: muted),
                  ],
                ),
              ),
            ),
          ),
        ],
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

/// Hazır rutin şablonlarını listeleyen alt sayfa; seçileni döndürür.
class _TemplateSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Hazır şablonlar',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Tek dokunuşla her gün tekrar eden etkinlikler ekle.', style: TextStyle(color: muted)),
        const SizedBox(height: 16),
        for (final t in routineTemplates)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: AppTheme.surface2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppTheme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.pop(context, t),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Text(t.emoji, style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final e in t.entries)
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surface3,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(categoryOf(e.category)?.icon, size: 13,
                                            color: AppTheme.redBright),
                                        const SizedBox(width: 4),
                                        Text('${fmtMinutes(e.start)} ${e.title}',
                                            style: const TextStyle(fontSize: 11)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.add_circle_rounded, color: AppTheme.red, size: 28),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
