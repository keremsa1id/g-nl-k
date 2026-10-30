import 'categories.dart';
import 'models.dart';
import 'trackers.dart';

/// Sesli komutun anlamı.
sealed class VoiceCommand {
  const VoiceCommand();
}

/// "Yarın akşam 10'da spor ekle, her gün tekrarlasın"
class VoiceEvent extends VoiceCommand {
  const VoiceEvent(this.item, {this.timeGuessed = false, this.roundedFrom});

  final ScheduleItem item;
  final bool timeGuessed; // saat söylenmedi, tahmin edildi
  final int? roundedFrom; // söylenen dakika (program yarım saatlik olduğu için yuvarlandı)
}

/// "Bir sigara içtim", "yarım saat önce iki bira içtim"
class VoiceLog extends VoiceCommand {
  const VoiceLog(this.tracker, this.count, this.at);

  final Tracker tracker;
  final int count;
  final DateTime at;
}

class VoiceUnknown extends VoiceCommand {
  const VoiceUnknown(this.message);

  final String message;
}

// ---------------------------------------------------------------------------
// Sözlükler
// ---------------------------------------------------------------------------

const _units = {
  'sıfır': 0, 'bir': 1, 'iki': 2, 'üç': 3, 'dört': 4, 'beş': 5,
  'altı': 6, 'yedi': 7, 'sekiz': 8, 'dokuz': 9,
};
const _tens = {'on': 10, 'yirmi': 20, 'otuz': 30, 'kırk': 40, 'elli': 50};

/// Saat bildiren ekli sayı sözcükleri: "ikide", "onda" (-de/-da) ve "ikiye", "dörde" (-e/-a).
/// "ona" (10'a) "ona söyle" ile karıştığı için yalnızca "saat ona" ise sayılır.
const _locativeNumbers = {
  'birde': 1, 'ikide': 2, 'üçte': 3, 'dörtte': 4, 'beşte': 5, 'altıda': 6,
  'yedide': 7, 'sekizde': 8, 'dokuzda': 9, 'onda': 10,
  'bire': 1, 'ikiye': 2, 'üçe': 3, 'dörde': 4, 'beşe': 5, 'altıya': 6,
  'yediye': 7, 'sekize': 8, 'dokuza': 9,
};

const _months = [
  'ocak', 'şubat', 'mart', 'nisan', 'mayıs', 'haziran',
  'temmuz', 'ağustos', 'eylül', 'ekim', 'kasım', 'aralık',
];

/// Uzun olan önce: "cumartesi" "cuma"dan, "pazartesi" "pazar"dan önce denenir.
const _weekdayStems = [
  ('pazartesi', 1), ('cumartesi', 6), ('salı', 2), ('çarşamba', 3),
  ('perşembe', 4), ('cuma', 5), ('pazar', 7),
];

/// Kategori adında geçmeyen ama aynı anlama gelen sözcükler (kök -> kategori sırası).
const _categorySynonyms = {
  'antrenman': 0, 'gym': 0, 'fitness': 0, 'idman': 0,
  'çalış': 1, 'ödev': 1, 'sınav': 1,
  'mesai': 2, 'ofis': 2,
  'oku': 3,
  'kahvaltı': 4, 'akşam yemeği': 4, 'öğle yemeği': 4,
  'uyu': 5,
  'uyan': wakeCategory, 'kalk': wakeCategory,
  'hap': 9,
  'futbol': 0, 'basketbol': 0, 'tenis': 0, 'pilates': 11,
  'ingilizce': 19, 'almanca': 19,
  'market': 25, 'temizle': 24,
  'doktor': 14, 'dişçi': 14, 'hastane': 14,
  'dizi': 40, 'film': 40,
  'oyun oyna': 41,
  'telefon': 34,
  'okul': 1, 'kurs': 1,
};

/// Takip edilenlerin (sigara, alkol…) halk arasındaki adları.
const _trackerSynonyms = {
  'sigara': ['sigara'],
  'alkol': ['alkol', 'bira', 'şarap', 'rakı', 'viski', 'votka', 'kadeh', 'içki'],
  'gazlı içecek': ['gazlı', 'kola', 'gazoz', 'soda', 'fanta', 'sprite'],
  'kahve': ['kahve', 'espresso', 'latte'],
  'tatlı / şeker': ['tatlı', 'çikolata', 'şeker', 'pasta', 'dondurma'],
  'fast food': ['fast', 'hamburger', 'burger', 'pizza', 'döner'],
  'sosyal medya': ['sosyal', 'instagram', 'tiktok', 'twitter'],
  'elektronik sigara': ['elektronik', 'vape', 'puff'],
};

const _planWords = {
  'ekle', 'ekler', 'ekleyin', 'koy', 'planla', 'kur', 'oluştur', 'hatırlat', 'yaz',
  'programla', 'ayarla',
};

/// Başlıktan atılan dolgu sözcükleri.
const _filler = {
  'ekle', 'ekler', 'ekleyin', 'eklesin', 'koy', 'planla', 'kur', 'oluştur', 'yaz', 'programla',
  'ayarla', 'tekrarlasın', 'tekrarla', 'tekrar', 'olsun', 'için', 'lütfen', 'bana', 've', 'de',
  'da', 'etkinlik', 'etkinliği', 'hatırlat', 'hatırlatma', 'hatırlatsın', 'programa',
  'takvime', 'saat', 'saatte', 'günü', 'günleri', 'bir', 'tane', 'alarm', 'alarmı', 'alarmlı',
  'kurar', 'misin', 'mısın', 'şunu', 'bunu', 'yap', 'sonra', 'önce', 'hafta', 'haftaya',
  'gelecek', 'bu',
};

// ---------------------------------------------------------------------------
// Belirteçler
// ---------------------------------------------------------------------------

class _Tok {
  _Tok(this.orig, this.w, {this.num, this.minute, this.locative = false});

  final String orig; // başlık için asıl hali
  final String w; // küçük harf, eksiz
  int? num; // sayı değeri
  int? minute; // "10:30" gibi yazıldıysa dakika
  bool locative; // "10'da", "onda" -> saat bildirir
  bool used = false;
}

/// "10", "10'da", "2'ye", "14:30'da", "22.00" — "-dan/-den" (…den itibaren) saat bildirmez.
final _timeRe =
    RegExp(r"^(\d{1,2})(?:[:.](\d{2}))?(?:'?(da|de|ta|te|ya|ye|a|e|dan|den|tan|ten))?$");
final _numRe = RegExp(r"^(\d+)(?:'?[a-zçğıöşü]*)?$");

List<_Tok> _tokenize(String text) {
  final raw = text
      .replaceAll('’', "'")
      .split(RegExp(r'[\s,;!?]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final toks = <_Tok>[];
  for (final r in raw) {
    final orig = r.replaceAll(RegExp(r'[.]$'), '');
    final w = trLower(orig);
    final t = _timeRe.firstMatch(w);
    if (t != null) {
      toks.add(_Tok(orig, t.group(1)!,
          num: int.parse(t.group(1)!),
          minute: t.group(2) == null ? null : int.parse(t.group(2)!),
          locative: t.group(3) != null && !t.group(3)!.endsWith('n')));
      continue;
    }
    final n = _numRe.firstMatch(w);
    if (n != null) {
      toks.add(_Tok(orig, w, num: int.parse(n.group(1)!)));
      continue;
    }
    final loc = _locativeNumbers[w];
    if (loc != null) {
      toks.add(_Tok(orig, w, num: loc, locative: true));
      continue;
    }
    if (w == 'ona' && toks.isNotEmpty && toks.last.w == 'saat') {
      toks.add(_Tok(orig, w, num: 10, locative: true));
      continue;
    }
    toks.add(_Tok(orig, w.replaceAll("'", ''), num: _units[w] ?? _tens[w]));
  }
  // "on bir", "yirmi iki", "on ikide" -> tek sayı
  for (var i = 0; i + 1 < toks.length; i++) {
    final a = toks[i], b = toks[i + 1];
    if (_tens.containsKey(a.w) && b.num != null && b.num! < 10 && _tens[a.w] == a.num) {
      toks[i] = _Tok('${a.orig} ${b.orig}', '${a.w} ${b.w}',
          num: a.num! + b.num!, locative: b.locative);
      toks.removeAt(i + 1);
    }
  }
  return toks;
}

bool _has(List<_Tok> toks, String w) => toks.any((t) => t.w == w);

// ---------------------------------------------------------------------------
// Ana fonksiyon
// ---------------------------------------------------------------------------

/// Türkçe sesli komutu çözer. [now] test için verilebilir.
VoiceCommand parseVoice(String text, List<Tracker> trackers, {DateTime? now}) {
  now ??= DateTime.now();
  final toks = _tokenize(text);
  if (toks.isEmpty) return const VoiceUnknown('Bir şey duyamadım, tekrar dener misin?');

  final log = _parseLog(toks, trackers, now);
  if (log != null) return log;
  return _parseEvent(toks, now);
}

// ---------- Takip kaydı: "bir sigara içtim" ----------

VoiceCommand? _parseLog(List<_Tok> toks, List<Tracker> trackers, DateTime now) {
  if (trackers.isEmpty || toks.any((t) => _planWords.contains(t.w))) return null;
  // Geçmiş zaman fiili: içtim, yedim, kullandım, girdim, yaptım…
  final verb = toks.any((t) => RegExp(r'(dım|dim|dum|düm|tım|tim|tum|tüm)$').hasMatch(t.w));
  if (!verb) return null;

  Tracker? best;
  var bestLen = 0;
  var at = -1;
  for (final t in trackers) {
    final words = {
      ...?_trackerSynonyms[trLower(t.name)],
      ...trLower(t.name).split(' ').where((w) => w.length > 2),
      if (t.unit.length > 3 && t.unit != 'adet') trLower(t.unit),
    };
    for (final w in words) {
      final i = toks.indexWhere((k) => k.w.startsWith(w));
      if (i >= 0 && w.length > bestLen) {
        best = t;
        bestLen = w.length;
        at = i;
      }
    }
  }
  if (best == null) return null;

  // Adet: takip sözcüğünden hemen önceki sayı ("iki bira"), yoksa 1.
  var count = 1;
  if (at > 0 && toks[at - 1].num != null && !toks[at - 1].locative) count = toks[at - 1].num!;
  if (count < 1 || count > 20) count = 1;

  // "yarım saat önce", "20 dakika önce", "2 saat önce"
  var when = now;
  final once = toks.indexWhere((t) => t.w == 'önce');
  if (once >= 2) {
    final unit = toks[once - 1].w;
    final n = toks[once - 2].w == 'yarım' ? 0.5 : (toks[once - 2].num ?? 1).toDouble();
    if (unit.startsWith('dakika') || unit == 'dk') {
      when = now.subtract(Duration(minutes: n.round()));
    } else if (unit.startsWith('saat')) {
      when = now.subtract(Duration(minutes: (n * 60).round()));
    }
  }
  return VoiceLog(best, count, when);
}

// ---------- Etkinlik: "yarın akşam 10'da spor ekle" ----------

VoiceCommand _parseEvent(List<_Tok> toks, DateTime now) {
  final today = dateOnly(now);
  DateTime? date;
  var repeat = Repeat.once;
  final weekdays = <int>{};
  var everyMarker = false; // "her", "-leri"

  // --- Tekrar ---
  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    if (t.w == 'hergün' || t.w == 'günlük') {
      repeat = Repeat.daily;
      t.used = true;
    }
    if (t.w != 'her') continue;
    t.used = true;
    everyMarker = true;
    final next = i + 1 < toks.length ? toks[i + 1] : null;
    if (next == null) continue;
    if (next.w.startsWith('gün') || next.w == 'sabah' || next.w == 'akşam' ||
        next.w == 'gece' || next.w == 'öğlen') {
      repeat = Repeat.daily;
      if (next.w.startsWith('gün')) next.used = true;
    } else if (next.w.startsWith('hafta')) {
      repeat = Repeat.weekly;
      next.used = true;
    } else if (next.w.startsWith('ay')) {
      repeat = Repeat.monthly;
      next.used = true;
    }
  }
  for (var i = 0; i + 1 < toks.length; i++) {
    if (toks[i].w != 'hafta') continue;
    final n = toks[i + 1].w;
    if (n.startsWith('içi')) {
      weekdays.addAll([1, 2, 3, 4, 5]);
    } else if (n.startsWith('sonu')) {
      weekdays.addAll([6, 7]);
    } else {
      continue;
    }
    repeat = Repeat.weekly;
    toks[i].used = toks[i + 1].used = true;
  }
  for (final t in toks) {
    if (t.w.startsWith('haftasonu')) {
      weekdays.addAll([6, 7]);
      repeat = Repeat.weekly;
      t.used = true;
    }
  }

  // --- Günler: "salı ve perşembe", "cumartesileri" ---
  final named = <int>[];
  for (final t in toks) {
    if (t.used) continue;
    for (final (stem, d) in _weekdayStems) {
      if (t.w.startsWith(stem)) {
        named.add(d);
        t.used = true;
        if (t.w.contains('leri') || t.w.contains('ları')) everyMarker = true;
        break;
      }
    }
  }
  final nextWeek = _has(toks, 'haftaya') || _has(toks, 'gelecek');
  for (final t in toks) {
    if (t.w == 'haftaya' || t.w == 'gelecek') t.used = true;
  }
  if (named.isNotEmpty) {
    if (everyMarker || named.length > 1 || repeat == Repeat.weekly) {
      repeat = Repeat.weekly;
      weekdays.addAll(named);
    } else if (nextWeek) {
      // "haftaya salı": gelecek haftanın salısı
      final nextMonday = DateTime(today.year, today.month, today.day + 8 - today.weekday);
      date = DateTime(nextMonday.year, nextMonday.month, nextMonday.day + named.first - 1);
    } else {
      // Tek gün: bir sonraki o gün (bugünse bugün).
      final diff = (named.first - today.weekday + 7) % 7;
      date = DateTime(today.year, today.month, today.day + diff);
    }
  }

  // --- Göreli gün ---
  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    if (t.used) continue;
    final next = i + 1 < toks.length ? toks[i + 1].w : '';
    if (t.w.startsWith('bugün')) {
      date ??= today;
      t.used = true;
    } else if (t.w == 'bu' && _periodOf(next, '') != null) {
      // "bu akşam", "bu sabah"
      date ??= today;
      t.used = true;
    } else if (t.w.startsWith('yarın')) {
      date = DateTime(today.year, today.month, today.day + 1);
      t.used = true;
    } else if ((t.w == 'öbür' || t.w == 'ertesi') &&
        i + 1 < toks.length &&
        toks[i + 1].w.startsWith('gün')) {
      date = DateTime(today.year, today.month, today.day + 2);
      t.used = toks[i + 1].used = true;
    }
  }

  // --- Tarih: "15 kasım" ---
  for (var i = 0; i + 1 < toks.length; i++) {
    final n = toks[i].num;
    if (n == null || n < 1 || n > 31) continue;
    final m = _months.indexWhere((x) => toks[i + 1].w.startsWith(x));
    if (m < 0) continue;
    var d = DateTime(today.year, m + 1, n);
    if (d.isBefore(today)) d = DateTime(today.year + 1, m + 1, n);
    date = d;
    toks[i].used = toks[i + 1].used = true;
  }

  // --- Süre: "1 saat", "45 dakika", "yarım saat", "bir buçuk saat" ---
  int? duration;
  int? reminder;
  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    if (t.used) continue;
    final isHour = t.w.startsWith('saat') && t.w != 'saat' || (t.w == 'saat' && i > 0);
    final isMin = t.w.startsWith('dakika') || t.w == 'dk';
    if (!isHour && !isMin) continue;
    // önceki: sayı, "yarım" ya da "X buçuk"
    double? value;
    var start = i;
    if (i > 0 && toks[i - 1].w == 'yarım') {
      value = 0.5;
      start = i - 1;
    } else if (i > 1 && toks[i - 1].w.startsWith('buçuk') && toks[i - 2].num != null) {
      value = toks[i - 2].num! + 0.5;
      start = i - 2;
    } else if (i > 0 && toks[i - 1].num != null && !toks[i - 1].locative) {
      value = toks[i - 1].num!.toDouble();
      start = i - 1;
    }
    if (value == null) continue;
    final minutes = isHour ? (value * 60).round() : value.round();
    final after = i + 1 < toks.length ? toks[i + 1].w : '';
    if (after == 'önce' || after.startsWith('önceden')) {
      reminder = minutes;
      toks[i + 1].used = true;
    } else {
      duration = minutes;
    }
    for (var k = start; k <= i; k++) {
      toks[k].used = true;
    }
  }

  // --- Saat: "saat 10", "10'da", "22:30", "on buçukta", "akşam 10" ---
  int? hour;
  var minute = 0;
  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    if (t.used || t.num == null) continue;
    final afterSaat = i > 0 && toks[i - 1].w == 'saat';
    final afterPeriod = i > 0 && _periodOf(toks[i - 1].w, '') != null; // "akşam 10"
    final nextBucuk = i + 1 < toks.length && toks[i + 1].w.startsWith('buçuk');
    if (!(t.locative || afterSaat || afterPeriod || t.minute != null || nextBucuk)) continue;
    if (t.num! > 24) continue;
    hour = t.num! % 24;
    minute = t.minute ?? (nextBucuk ? 30 : 0);
    t.used = true;
    if (afterSaat) toks[i - 1].used = true;
    if (nextBucuk) toks[i + 1].used = true;
    break;
  }

  // Gün dilimi
  String? period;
  for (var i = 0; i < toks.length; i++) {
    final next = i + 1 < toks.length ? toks[i + 1].w : '';
    final p = _periodOf(toks[i].w, next);
    if (p == null) continue;
    period = p;
    toks[i].used = true;
    if (toks[i].w.startsWith('öğleden') && next == 'sonra') toks[i + 1].used = true;
  }

  // Saat ekleriyle anlaşılamadıysa: cümlede tek başına kalan 1–24 arası sayı ("toplantı 2").
  if (hour == null) {
    for (final t in toks) {
      if (t.used || t.num == null || t.num! < 1 || t.num! > 24) continue;
      hour = t.num! % 24;
      minute = t.minute ?? 0;
      t.used = true;
      break;
    }
  }
  for (final t in toks) {
    if (t.w == 'saat') t.used = true;
  }

  // --- Kategori ---
  final textNorm = toks.map((t) => t.w).join(' ');
  int? category;
  var catLen = 0;
  for (var c = 0; c < categories.length; c++) {
    final name = trLower(categories[c].name);
    if (name.length > catLen && RegExp('(^| )${RegExp.escape(name)}').hasMatch(textNorm)) {
      category = c;
      catLen = name.length;
    }
  }
  if (category == null) {
    _categorySynonyms.forEach((stem, c) {
      if (stem.length > catLen && RegExp('(^| )${RegExp.escape(stem)}').hasMatch(textNorm)) {
        category = c;
        catLen = stem.length;
      }
    });
  }

  if (period != null) {
    if (hour == null) {
      hour = switch (period) { 'sabah' => 8, 'öğlen' => 12, 'akşam' => 20, _ => 22 };
    } else if (period == 'akşam' && hour < 12) {
      hour += 12;
    } else if (period == 'öğlen' && hour < 6) {
      hour += 12;
    } else if (period == 'gece' && hour >= 6 && hour < 12) {
      hour += 12;
    } else if (period == 'gece' && hour == 12) {
      hour = 0;
    }
  } else if (hour != null && hour >= 1 && hour <= 6 && !alarmCategories.contains(category)) {
    // "spor 6'da" büyük ihtimalle akşam 6
    hour += 12;
  }

  final alarm = toks.any((t) => t.w.startsWith('alarm')) ||
      (category != null && alarmCategories.contains(category));

  // --- Başlık: kalan sözcükler ---
  final rest = [
    for (final t in toks)
      if (!t.used && !_filler.contains(t.w) && t.num == null && !t.w.startsWith('buçuk')) t.orig,
  ];
  var title = rest.join(' ').trim();
  final cat = categoryOf(category);
  if (title.isEmpty || (cat != null && trLower(title) == trLower(cat.name))) {
    title = cat?.name ?? '';
  }
  if (title.isEmpty) {
    return const VoiceUnknown('Ne ekleyeceğimi anlayamadım. Örneğin "yarın 10\'da spor ekle" de.');
  }
  title = _capitalize(title);

  // --- Saat yoksa: bir sonraki yarım saat ---
  var guessed = false;
  if (hour == null) {
    guessed = true;
    final m = now.hour * 60 + now.minute;
    final next = ((m ~/ 30) + 1) * 30;
    hour = (next ~/ 60) % 24;
    minute = next % 60;
  }
  final spoken = hour * 60 + minute;
  final start = spoken ~/ 30 * 30;

  // Tarih: tekrarlananlarda başlangıç bugün; tek seferlikte söylenen gün.
  date ??= today;
  if (repeat == Repeat.weekly && weekdays.isEmpty) weekdays.add(date.weekday);
  if (repeat == Repeat.daily) weekdays.clear();

  var dur = duration ?? cat?.minutes ?? 60;
  dur = ((dur + 29) ~/ 30) * 30;
  if (dur < 30) dur = 30;
  if (start + dur > 24 * 60) dur = 24 * 60 - start;

  final item = ScheduleItem(
    id: 0, // kaydederken verilir
    title: title,
    startMinutes: start,
    durationMinutes: dur,
    repeat: repeat,
    startDate: date,
    weekdays: weekdays.isEmpty ? [date.weekday] : (weekdays.toList()..sort()),
    reminders: [Reminder(reminder ?? 5)],
    colorIndex: (category ?? 0) % 10,
    category: category,
    alarmMinutesBefore: alarm ? 0 : null,
  );
  return VoiceEvent(item, timeGuessed: guessed, roundedFrom: spoken == start ? null : spoken);
}

/// Gün dilimi sözcüğü: sabah, öğlen, akşam, gece. "akşam yemeği" gibi yemek adları sayılmaz.
String? _periodOf(String w, String next) {
  if (next.startsWith('yemeğ')) return null;
  if (w.startsWith('sabah')) return 'sabah';
  if (w.startsWith('öğleden')) return 'akşam';
  if (w.startsWith('öğlen') || w == 'öğle') return 'öğlen';
  if (w.startsWith('akşam')) return 'akşam';
  if (w.startsWith('gece')) return 'gece';
  return null;
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  final first = s[0] == 'i' ? 'İ' : (s[0] == 'ı' ? 'I' : s[0].toUpperCase());
  return first + s.substring(1);
}
