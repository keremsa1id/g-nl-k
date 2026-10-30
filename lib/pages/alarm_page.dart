import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../categories.dart';
import '../models.dart';
import '../notifications.dart';
import '../storage.dart';
import '../theme.dart';

/// Alarm çaldığında (kilit ekranında da) açılan tam ekran sayfa.
class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key, required this.item, required this.notificationId});

  final ScheduleItem item;
  final int notificationId;

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  static const _channel = MethodChannel('gunluk/alarm');

  @override
  void dispose() {
    _pulse.dispose();
    _clock?.cancel();
    // Alarm bitti: uygulama artık kilit ekranının üstünde açılmasın.
    _channel.invokeMethod<void>('clearLockScreen').catchError((Object _) {});
    super.dispose();
  }

  Future<void> _stop() async {
    await Notifier.stopAlarm(widget.item, widget.notificationId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _snooze() async {
    await Notifier.stopAlarm(widget.item, widget.notificationId);
    await Notifier.snoozeAlarm(widget.item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('😴 5 dakika sonra tekrar çalacak')));
    Navigator.pop(context);
  }

  Future<void> _done() async {
    await Notifier.stopAlarm(widget.item, widget.notificationId);
    await Store.instance.setDone(widget.item.id, DateTime.now(), true);
    Notifier.changes.value++;
    await Notifier.refreshExtras();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final cat = categoryOf(item.category);
    final now = DateTime.now();
    final before = item.alarmMinutesBefore ?? 0;
    return PopScope(
      // Geri tuşu alarmı susturmadan kapatmasın.
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.redDeep, AppTheme.black],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Text('${two(now.hour)}:${two(now.minute)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 72, fontWeight: FontWeight.w900, letterSpacing: -2)),
                  Text(fmtDate(now),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70)),
                  const Spacer(),
                  Center(
                    child: ScaleTransition(
                      scale: Tween(begin: 0.92, end: 1.08).animate(
                          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.red.withValues(alpha: 0.25),
                          border: Border.all(color: AppTheme.redBright, width: 3),
                          boxShadow: [
                            BoxShadow(
                                color: AppTheme.red.withValues(alpha: 0.6), blurRadius: 40),
                          ],
                        ),
                        child: Icon(cat?.icon ?? Icons.alarm_rounded,
                            size: 64, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (cat != null && cat.name != item.title)
                    Text(cat.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppTheme.redBright,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                  Text(item.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    before == 0
                        ? 'Zamanı geldi · ${item.timeLabel}'
                        : '${fmtDuration(before)} sonra başlıyor · ${item.timeLabel}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  if (item.note.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text('📝 ${item.note}', textAlign: TextAlign.center),
                    ),
                  ],
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    onPressed: _stop,
                    icon: const Icon(Icons.alarm_off_rounded),
                    label: const Text('Kapat'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          onPressed: _snooze,
                          icon: const Icon(Icons.snooze_rounded),
                          label: const Text('5 dk ertele'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          onPressed: _done,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Tamamlandı'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
