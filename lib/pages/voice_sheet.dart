import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../categories.dart';
import '../game.dart';
import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../voice_parser.dart';

/// Sesli komut penceresi. Etkinlik onaylanırsa (taslak, düzenlensin mi) döner;
/// takip kaydı ("bir sigara içtim") pencerenin içinde yapılır ve null döner.
Future<(ScheduleItem, bool)?> showVoiceSheet(BuildContext context) =>
    showModalBottomSheet<(ScheduleItem, bool)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _VoiceSheet(),
    );

const _examples = [
  'Yarın akşam 10\'da spor ekle, her gün tekrarlasın',
  'Salı ve perşembe 18\'de İngilizce dersi',
  'Sabah 7\'de uyanma alarmı kur',
  'Cumartesi 14\'te 2 saat temizlik',
  'Bir sigara içtim',
  'Yarım saat önce iki bira içtim',
];

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _stt = SpeechToText();
  final _typed = TextEditingController();
  bool _ready = false;
  bool _listening = false;
  String? _sttError;
  String _heard = '';
  VoiceCommand? _cmd;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _stt.cancel();
    _typed.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _ready = await _stt.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') {
            setState(() => _listening = false);
            if (_cmd == null && _heard.isNotEmpty) _parse(_heard);
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _sttError = e.errorMsg == 'error_no_match' || e.errorMsg == 'error_speech_timeout'
                ? 'Seni duyamadım, tekrar dene.'
                : 'Ses tanıma hatası: ${e.errorMsg}';
          });
        },
      );
    } catch (_) {
      _ready = false;
    }
    if (!mounted) return;
    setState(() {
      if (!_ready) {
        _sttError = 'Mikrofon kullanılamıyor. Aşağıya yazarak da deneyebilirsin.';
      }
    });
    if (_ready) await _listen();
  }

  Future<String?> _turkishLocale() async {
    try {
      final locales = await _stt.locales();
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('tr')) return l.localeId;
      }
    } catch (_) {}
    return 'tr_TR';
  }

  Future<void> _listen() async {
    if (!_ready) return;
    setState(() {
      _listening = true;
      _heard = '';
      _cmd = null;
      _sttError = null;
    });
    await _stt.listen(
      localeId: await _turkishLocale(),
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult) _parse(r.recognizedWords);
      },
    );
  }

  Future<void> _stop() async {
    await _stt.stop();
    if (mounted) setState(() => _listening = false);
  }

  void _parse(String text) {
    setState(() {
      _heard = text;
      _cmd = parseVoice(text, Store.instance.trackers);
    });
  }

  Future<void> _saveLog(VoiceLog c) async {
    final store = Store.instance;
    for (var i = 0; i < c.count; i++) {
      // Aynı ana birden fazla kayıt düşmesin diye birer saniye arayla.
      c.tracker.events.add(c.at.subtract(Duration(seconds: i)));
    }
    c.tracker.events.sort();
    await store.saveTrackers();
    store.trackersChanged.value++;
    Game.instance.changes.value++;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      content: Text('${c.tracker.emoji} ${c.count} ${c.tracker.unit} kaydedildi · '
          '${c.count * xpPerEvent} XP'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sesle ekle',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Etkinlik planla ya da takibine kayıt gir.',
                style: TextStyle(color: muted)),
            const SizedBox(height: 20),
            Center(child: _micButton()),
            const SizedBox(height: 12),
            Text(
              _listening
                  ? (_heard.isEmpty ? 'Dinliyorum…' : _heard)
                  : (_heard.isEmpty ? 'Konuşmak için mikrofona dokun' : '"$_heard"'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _heard.isEmpty ? 14 : 18,
                fontWeight: _heard.isEmpty ? FontWeight.w500 : FontWeight.w700,
                color: _heard.isEmpty ? muted : Colors.white,
              ),
            ),
            if (_sttError != null) ...[
              const SizedBox(height: 8),
              Text(_sttError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            if (_cmd != null) _result(context, _cmd!) else _examplesCard(context),
            const SizedBox(height: 16),
            TextField(
              controller: _typed,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _parse(v.trim());
              },
              decoration: InputDecoration(
                hintText: 'ya da buraya yaz…',
                prefixIcon: const Icon(Icons.keyboard_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () {
                    final v = _typed.text.trim();
                    if (v.isNotEmpty) _parse(v);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _micButton() {
    return GestureDetector(
      onTap: !_ready ? null : (_listening ? _stop : _listen),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: _listening ? 96 : 84,
        height: _listening ? 96 : 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: !_ready ? AppTheme.surface3 : AppTheme.red,
          boxShadow: _listening
              ? [BoxShadow(color: AppTheme.red.withValues(alpha: 0.7), blurRadius: 36, spreadRadius: 6)]
              : null,
        ),
        child: Icon(
          _listening ? Icons.stop_rounded : (_ready ? Icons.mic_rounded : Icons.mic_off_rounded),
          size: 40,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _examplesCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Şöyle söyleyebilirsin:', style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 6),
          for (final e in _examples)
            InkWell(
              onTap: () {
                _typed.text = e;
                _parse(e);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text('“$e”', style: const TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, VoiceCommand cmd) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    BoxDecoration box(Color c) => BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.withValues(alpha: 0.6)),
        );
    Widget chip(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: muted),
              const SizedBox(width: 6),
              Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    switch (cmd) {
      case VoiceUnknown(:final message):
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: box(Theme.of(context).colorScheme.error),
          child: Text('🤔 $message'),
        );
      case VoiceLog(:final tracker, :final count, :final at):
        final ago = DateTime.now().difference(at).inMinutes;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: box(AppTheme.red),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${tracker.emoji} $count ${tracker.unit}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                  '${tracker.name} takibine · '
                  '${ago < 1 ? 'şimdi' : '${fmtDuration(ago)} önce (${fmtMinutes(at.hour * 60 + at.minute)})'}',
                  style: TextStyle(color: muted)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _saveLog(cmd as VoiceLog),
                icon: const Icon(Icons.check_rounded),
                label: Text('Kaydet · ${count * xpPerEvent} XP'),
              ),
            ],
          ),
        );
      case VoiceEvent():
        break;
    }
    final ev = cmd as VoiceEvent;
    final item = ev.item;
    final timeGuessed = ev.timeGuessed;
    final roundedFrom = ev.roundedFrom;
    {
        final cat = categoryOf(item.category);
        final now = dateOnly(DateTime.now());
        final d = item.startDate;
        final dayText = item.repeat != Repeat.once
            ? item.repeatLabel
            : sameDay(d, now)
                ? 'Bugün'
                : sameDay(d, DateTime(now.year, now.month, now.day + 1))
                    ? 'Yarın'
                    : '${d.day} ${trMonths[d.month - 1]} ${trWeekdays[d.weekday - 1]}';
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: box(const Color(0xFF66BB6A)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(cat?.icon ?? Icons.event_rounded, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.title,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  chip(Icons.event_rounded, dayText),
                  chip(Icons.schedule_rounded, item.timeLabel),
                  chip(Icons.timelapse_rounded, fmtDuration(item.durationMinutes)),
                  if (cat != null) chip(Icons.category_rounded, cat.name),
                  if (item.hasAlarm) chip(Icons.alarm_rounded, 'Alarm'),
                  chip(Icons.notifications_rounded,
                      fmtOffset(item.reminders.first.minutesBefore)),
                ],
              ),
              if (timeGuessed || roundedFrom != null) ...[
                const SizedBox(height: 10),
                Text(
                  timeGuessed
                      ? 'ℹ️ Saat söylemedin, en yakın yarım saate koydum.'
                      : 'ℹ️ ${fmtMinutes(roundedFrom!)} dedin; program yarım saatlik olduğu için '
                          '${fmtMinutes(item.startMinutes)} yaptım.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, (item, true)),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Düzenle'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, (item, false)),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Ekle'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }
}
