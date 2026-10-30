import 'dart:async';

import 'package:flutter/material.dart';

import '../game.dart';
import '../models.dart';
import '../notifications.dart';
import '../storage.dart';
import '../theme.dart';
import '../widgets.dart';
import 'games.dart';
import 'screen_time_page.dart';
import 'stats_page.dart';

/// XP, seviye, günlük görevler, mini oyunlar ve kişisel bilgiler.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final game = Game.instance;
  final store = Store.instance;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    game.changes.addListener(_refresh);
    Notifier.changes.addListener(_refresh);
    store.trackersChanged.addListener(_refresh);
    // Saate bağlı görevler (öğleden önce, yatmadan önce…) kendiliğinden tamamlansın.
    game.refreshScreenTime();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      game.refreshScreenTime(); // bitince changes ile yeniden çizilir
      _refresh();
    });
  }

  @override
  void dispose() {
    game.changes.removeListener(_refresh);
    Notifier.changes.removeListener(_refresh);
    store.trackersChanged.removeListener(_refresh);
    _ticker?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _claim(Quest q, DateTime day) async {
    await game.claim(q, day);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${q.emoji} ${q.title} · +${q.xp} XP')));
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final leftover = yesterday.isBefore(game.start)
        ? <Quest>[]
        : [
            for (final q in game.questsFor(yesterday))
              if (!game.isClaimed(q, yesterday) && game.stateOf(q, yesterday) == QuestState.done) q,
          ];
    final p = game.profile;

    return Scaffold(
      appBar: AppBar(
        actions: [
          SquareIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Bilgilerimi düzenle',
            onPressed: () => showProfileEditor(context),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          PageHeader(
            eyebrow: 'Profil',
            title: p.name.isEmpty ? 'Merhaba 👋' : p.name,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _levelCard(context),
                const SizedBox(height: 24),
                SectionLabel('Bugünün görevleri',
                    trailing: Text(fmtDate(today),
                        style: TextStyle(
                            fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                const SizedBox(height: 8),
                for (final q in game.questsFor(today)) _questTile(context, q, today),
                if (leftover.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionLabel('Dünden kalan ödüller'),
                  const SizedBox(height: 8),
                  for (final q in leftover) _questTile(context, q, yesterday),
                ],
                const SizedBox(height: 24),
                SectionLabel('Mini oyunlar',
                    trailing: Text('Bugün ${game.gameXpOn(today)}/$dailyGameXpCap XP',
                        style: TextStyle(
                            fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                const SizedBox(height: 8),
                const GameCards(),
                const SizedBox(height: 24),
                const SectionLabel('Son 7 gün'),
                const SizedBox(height: 8),
                _weekCard(context),
                const SizedBox(height: 12),
                _rulesCard(context),
                const SizedBox(height: 24),
                SectionLabel('Kişisel bilgiler',
                    trailing: TextButton(
                        onPressed: () => showProfileEditor(context), child: const Text('Düzenle'))),
                const SizedBox(height: 8),
                _infoCard(context),
                const SizedBox(height: 12),
                _weightCard(context),
                const SizedBox(height: 24),
                const SectionLabel('Ekran süresi'),
                const SizedBox(height: 8),
                const ScreenTimeCard(),
                const SizedBox(height: 24),
                const SectionLabel('İstatistikler'),
                const SizedBox(height: 8),
                ...const StatsPage().sections(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Seviye ----------

  Widget _levelCard(BuildContext context) {
    final xp = game.totalXp;
    final (level, into, need) = levelFor(xp);
    final (emoji, title) = titleFor(level);
    final todayXp = game.xpOn(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.redDeep, AppTheme.surface1],
        ),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.black.withValues(alpha: 0.4),
                  border: Border.all(color: AppTheme.redBright, width: 2),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 34)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Seviye $level',
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    Text(title,
                        style: const TextStyle(
                            color: AppTheme.redBright, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${xp < 0 ? 0 : xp}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const Text('toplam XP', style: TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: into / need,
              minHeight: 12,
              backgroundColor: AppTheme.black.withValues(alpha: 0.5),
              color: AppTheme.redBright,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('$into / $need XP', style: const TextStyle(fontSize: 12)),
              const Spacer(),
              Text(
                'Bugün ${todayXp >= 0 ? '+' : ''}$todayXp XP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: todayXp >= 0 ? const Color(0xFF66BB6A) : AppTheme.redBright,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- Görevler ----------

  Widget _questTile(BuildContext context, Quest q, DateTime day) {
    final state = game.stateOf(q, day);
    final claimed = game.isClaimed(q, day);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    const green = Color(0xFF66BB6A);
    final color = switch (state) {
      _ when claimed => muted,
      QuestState.done => green,
      QuestState.failed => muted,
      QuestState.active => Colors.white,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: state == QuestState.done && !claimed
            ? green.withValues(alpha: 0.12)
            : AppTheme.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: state == QuestState.done && !claimed
                ? green.withValues(alpha: 0.6)
                : AppTheme.border),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: state == QuestState.failed ? 0.4 : 1,
            child: Text(q.emoji, style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                      decoration: state == QuestState.failed ? TextDecoration.lineThrough : null,
                    )),
                const SizedBox(height: 2),
                Text(
                  switch (state) {
                    _ when claimed => 'Ödül alındı ✓',
                    QuestState.failed => 'Bu sefer olmadı, yarın yeni görevler gelir',
                    QuestState.done => 'Tamamlandı!',
                    QuestState.active => q.hint,
                  },
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (state == QuestState.done && !claimed)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () => _claim(q, day),
              child: Text('+${q.xp} XP', style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          else
            Text('+${q.xp}',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: claimed || state == QuestState.failed ? muted : AppTheme.redBright)),
        ],
      ),
    );
  }

  // ---------- Son 7 gün ----------

  Widget _weekCard(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final days = [for (var i = 6; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    final values = [for (final d in days) game.xpOn(d)];
    final peak = values.map((v) => v.abs()).fold(1, (a, b) => a > b ? a : b);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, d) in days.indexed)
              Expanded(
                child: Column(
                  children: [
                    Text(values[i] == 0 ? '' : '${values[i] > 0 ? '+' : ''}${values[i]}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: values[i] >= 0 ? const Color(0xFF66BB6A) : AppTheme.redBright)),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (values[i].abs() / peak).clamp(0.03, 1.0),
                          child: Container(
                            width: 18,
                            decoration: BoxDecoration(
                              color: values[i] >= 0 ? const Color(0xFF66BB6A) : AppTheme.red,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(trWeekdaysShort[d.weekday - 1],
                        style: TextStyle(
                            fontSize: 11,
                            color: sameDay(d, today) ? Colors.white : muted,
                            fontWeight: sameDay(d, today) ? FontWeight.w800 : FontWeight.w500)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rulesCard(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget row(String emoji, String text, String xp, Color c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: muted))),
              Text(xp, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
            ],
          ),
        );
    const green = Color(0xFF66BB6A);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('XP nasıl kazanılır?', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          row('✅', 'Programdaki bir etkinliği tamamla', '+$xpPerDone', green),
          row('🎯', 'Günlük görevleri bitir', '+20–80', green),
          row('🎮', 'Mini oyun oyna (günde en fazla $dailyGameXpCap)', '+5–30', green),
          row('📵', 'Ekran süresi görevi (sosyal medya, oyun sınırı)', '+35–45', green),
          row('🚬', 'Takipteki her kayıt (sigara, alkol…)', '$xpPerEvent', AppTheme.redBright),
        ],
      ),
    );
  }

  // ---------- Kişisel bilgiler ----------

  static String _num(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.', ',');

  static (String, Color) _bmiLabel(double bmi) {
    if (bmi < 18.5) return ('Zayıf', const Color(0xFF4DA3FF));
    if (bmi < 25) return ('Normal', const Color(0xFF66BB6A));
    if (bmi < 30) return ('Fazla kilolu', const Color(0xFFFFB020));
    return ('Obez', AppTheme.redBright);
  }

  Widget _infoCard(BuildContext context) {
    final p = game.profile;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final empty = p.age == null && p.heightCm == null && p.weightKg == null;
    if (empty) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: () => showProfileEditor(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Yaş, boy, kilo bilgilerini ekle'),
      );
    }
    Widget cell(String label, String value, [Color? c]) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: muted)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c)),
              ),
            ],
          ),
        );
    final bmi = p.bmi;
    final tdee = p.tdee;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.35,
      children: [
        cell('Yaş', p.age == null ? '—' : '${p.age}'),
        cell('Boy', p.heightCm == null ? '—' : '${_num(p.heightCm!)} cm'),
        cell('Kilo', p.weightKg == null ? '—' : '${_num(p.weightKg!)} kg'),
        if (bmi != null)
          cell('VKİ · ${_bmiLabel(bmi).$1}', bmi.toStringAsFixed(1).replaceAll('.', ','),
              _bmiLabel(bmi).$2)
        else
          cell('VKİ', '—'),
        cell('Hedef kilo', p.goalWeightKg == null ? '—' : '${_num(p.goalWeightKg!)} kg'),
        cell('Günlük kalori', tdee == null ? '—' : '${tdee.round()} kcal'),
        cell('Cinsiyet', p.gender == null ? '—' : genders[p.gender!]),
        cell('Uyanma', fmtMinutes(p.wakeMinutes)),
        cell('Yatma', fmtMinutes(p.bedMinutes)),
      ],
    );
  }

  Widget _weightCard(BuildContext context) {
    final p = game.profile;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final w = p.weights;
    final recent = w.length > 6 ? w.sublist(w.length - 6) : w;
    String? toGoal;
    if (p.weightKg != null && p.goalWeightKg != null) {
      final diff = p.weightKg! - p.goalWeightKg!;
      toGoal = diff.abs() < 0.05
          ? 'Hedefe ulaştın 🎉'
          : 'Hedefe ${_num(diff.abs())} kg ${diff > 0 ? 'vermen' : 'alman'} kaldı';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('⚖️ Kilo takibi', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _logWeight(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Kilo gir'),
              ),
            ],
          ),
          if (toGoal != null) Text(toGoal, style: TextStyle(fontSize: 12, color: muted)),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Henüz kayıt yok. Haftada bir tartılıp girmen yeterli.',
                  style: TextStyle(fontSize: 12, color: muted)),
            )
          else ...[
            const SizedBox(height: 8),
            for (final (i, (d, kg)) in recent.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text('${d.day} ${trMonths[d.month - 1]}',
                        style: TextStyle(fontSize: 13, color: muted)),
                    const Spacer(),
                    if (i > 0 || w.length > recent.length)
                      Builder(builder: (_) {
                        final prev = i > 0 ? recent[i - 1].$2 : w[w.length - recent.length - 1].$2;
                        final diff = kg - prev;
                        if (diff.abs() < 0.05) return const SizedBox.shrink();
                        return Text('${diff > 0 ? '▲' : '▼'} ${_num(diff.abs())}  ',
                            style: TextStyle(
                                fontSize: 12,
                                color: diff > 0 ? const Color(0xFFFFB020) : const Color(0xFF66BB6A)));
                      }),
                    Text('${_num(kg)} kg', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _logWeight(BuildContext context) async {
    final c = TextEditingController(
        text: game.profile.weightKg == null ? '' : _num(game.profile.weightKg!));
    final kg = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bugünkü kilon'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'kg'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.replaceAll(',', '.'))),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    c.dispose();
    if (kg != null && kg > 20 && kg < 400) await game.logWeight(kg);
  }
}

// ---------------------------------------------------------------------------
// Profil düzenleme penceresi
// ---------------------------------------------------------------------------

Future<void> showProfileEditor(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const ProfileForm(),
    );

/// İlk açılışta zorunlu profil ekranı; geri tuşuyla kapatılamaz.
class ProfileSetupPage extends StatelessWidget {
  const ProfileSetupPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: ProfileForm(onboarding: true, onDone: onDone),
          ),
        ),
      ),
    );
  }
}

/// Profil bilgileri formu: düzenleme penceresinde ve ilk açılış ekranında.
class ProfileForm extends StatefulWidget {
  const ProfileForm({super.key, this.onboarding = false, this.onDone});

  final bool onboarding;
  final VoidCallback? onDone;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final game = Game.instance;
  late final Profile p = game.profile;
  late final _name = TextEditingController(text: p.name);
  late final _age = TextEditingController(text: p.age?.toString() ?? '');
  late final _height = TextEditingController(text: _fmt(p.heightCm));
  late final _weight = TextEditingController(text: _fmt(p.weightKg));
  late final _goal = TextEditingController(text: _fmt(p.goalWeightKg));
  late int? _gender = p.gender;
  late int _activity = p.activity;
  late int _wake = p.wakeMinutes;
  late int _bed = p.bedMinutes;
  String? _error;

  static String _fmt(double? v) =>
      v == null ? '' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1));

  static double? _parse(String s) => double.tryParse(s.replaceAll(',', '.').trim());

  @override
  void dispose() {
    for (final c in [_name, _age, _height, _weight, _goal]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(bool wake) async {
    final m = wake ? _wake : _bed;
    final t = await showTimePicker(
      context: context,
      helpText: wake ? 'Uyanma saati' : 'Yatma saati',
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null || !mounted) return;
    setState(() {
      if (wake) {
        _wake = t.hour * 60 + t.minute;
      } else {
        _bed = t.hour * 60 + t.minute;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final age = int.tryParse(_age.text.trim());
    final height = _parse(_height.text);
    final weight = _parse(_weight.text);
    final goal = _parse(_goal.text);
    final String? error;
    if (name.isEmpty) {
      error = 'Adını yaz';
    } else if (age == null || age < 5 || age > 120) {
      error = 'Geçerli bir yaş gir';
    } else if (_gender == null) {
      error = 'Cinsiyet seç';
    } else if (height == null || height < 50 || height > 250) {
      error = 'Boyunu cm olarak gir (ör. 175)';
    } else if (weight == null || weight < 20 || weight > 400) {
      error = 'Kilonu kg olarak gir (ör. 70)';
    } else {
      error = null;
    }
    if (error != null || age == null || weight == null) {
      setState(() => _error = error);
      return;
    }
    p
      ..name = name
      ..birthYear = DateTime.now().year - age
      ..gender = _gender
      ..heightCm = height
      ..goalWeightKg = goal != null && goal >= 20 && goal <= 400 ? goal : null
      ..activity = _activity
      ..wakeMinutes = _wake
      ..bedMinutes = _bed;
    if (weight != p.weightKg) {
      await game.logWeight(weight); // profili de kaydeder
    } else {
      p.weightKg = weight;
      await game.saveProfile();
    }
    if (!mounted) return;
    if (widget.onboarding) {
      widget.onDone?.call();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    Widget numField(TextEditingController c, String label, String suffix) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(labelText: label, suffixText: suffix),
          ),
        );
    Widget time(String label, int m, bool wake) => Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: () => _pickTime(wake),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: muted)),
                Text(fmtMinutes(m),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onboarding) ...[
              const Text('👋', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 8),
              Text('Hoş geldin!',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Başlamadan önce seni biraz tanıyalım. Bu bilgiler görevlerin, '
                  'kalori ihtiyacının ve vücut kitle indeksinin hesaplanmasında kullanılır.',
                  style: TextStyle(color: muted)),
            ] else
              Text('Kişisel bilgiler',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('* işaretli alanlar zorunlu. Bilgiler sadece telefonunda saklanır.',
                style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(labelText: 'Adın *'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              numField(_age, 'Yaş *', ''),
              const SizedBox(width: 10),
              numField(_height, 'Boy *', 'cm'),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              numField(_weight, 'Kilo *', 'kg'),
              const SizedBox(width: 10),
              numField(_goal, 'Hedef kilo', 'kg'),
            ]),
            const SizedBox(height: 16),
            Text('Cinsiyet *', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final (i, g) in genders.indexed)
                  ChoiceChip(
                    label: Text(g),
                    selected: _gender == i,
                    onSelected: (v) => setState(() {
                      _gender = v ? i : null;
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Hareket düzeyi', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, (name, _, _)) in activityLevels.indexed)
                  ChoiceChip(
                    label: Text(name),
                    selected: _activity == i,
                    onSelected: (_) => setState(() => _activity = i),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(activityLevels[_activity].$2, style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 8),
            Text('Uyku düzeni', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text('Görevlerde kullanılır (ör. "yatmadan 2 saat önce içme").',
                style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(children: [
              time('Uyanma', _wake, true),
              const SizedBox(width: 10),
              time('Yatma', _bed, false),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _save,
              icon: Icon(widget.onboarding ? Icons.arrow_forward_rounded : Icons.check),
              label: Text(widget.onboarding ? 'Başla' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sayfa başlıklarının sağ üstündeki profil düğmesi: seviye halkası + alınmamış ödül sayısı.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context) {
    final game = Game.instance;
    return ValueListenableBuilder<int>(
      valueListenable: game.changes,
      builder: (context, _, __) {
        final (level, into, need) = levelFor(game.totalXp);
        final unclaimed = game.unclaimedCount;
        final name = game.profile.name;
        return Tooltip(
          message: 'Profil',
          child: GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute<void>(builder: (_) => const ProfilePage())),
            child: Badge(
              isLabelVisible: unclaimed > 0,
              label: Text('$unclaimed'),
              child: SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: into / need,
                        strokeWidth: 3,
                        backgroundColor: AppTheme.border,
                        color: AppTheme.redBright,
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surface3,
                      ),
                      child: Text(
                        name.isEmpty ? '🙂' : name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('$level',
                            style: const TextStyle(
                                fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
