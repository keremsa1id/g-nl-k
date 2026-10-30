enum Repeat { once, daily, weekly, monthly }

extension RepeatX on Repeat {
  String get label => switch (this) {
        Repeat.once => 'Tek sefer',
        Repeat.daily => 'Her gün',
        Repeat.weekly => 'Haftalık',
        Repeat.monthly => 'Aylık',
      };
}

const trWeekdays = [
  'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
];
const trWeekdaysShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
const trMonths = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String two(int n) => n.toString().padLeft(2, '0');

/// Tamamlama kayıtları için gün anahtarı: "2026-10-27".
String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

/// Gün içindeki dakikayı "HH:MM" yapar.
String fmtMinutes(int m) => '${two((m ~/ 60) % 24)}:${two(m % 60)}';

String fmtDate(DateTime d) =>
    '${d.day} ${trMonths[d.month - 1]} ${d.year}, ${trWeekdays[d.weekday - 1]}';

String fmtDateTime(DateTime d) =>
    '${d.day} ${trMonths[d.month - 1]} ${two(d.hour)}:${two(d.minute)}';

String fmtDuration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m dk';
  if (m == 0) return '$h sa';
  return '$h sa $m dk';
}

/// Etkinlik hatırlatması hangi aralıkla seçilebilir (başlangıçtan kaç dakika önce).
const reminderOffsets = <int>[0, 5, 10, 15, 30, 45, 60, 120, 180, 360, 720, 1440];

String fmtOffset(int m) {
  if (m == 0) return 'Başlarken';
  if (m == 1440) return '1 gün önce';
  if (m < 60) return '$m dk önce';
  return m % 60 == 0 ? '${m ~/ 60} sa önce' : '${m ~/ 60} sa ${m % 60} dk önce';
}

/// Etkinliğe bağlı tek bir hatırlatma: başlangıçtan [minutesBefore] dk önce, isteğe bağlı notla.
class Reminder {
  const Reminder(this.minutesBefore, [this.note = '']);

  final int minutesBefore;
  final String note;

  Map<String, dynamic> toJson() => {'m': minutesBefore, if (note.isNotEmpty) 'n': note};

  factory Reminder.fromJson(Map<String, dynamic> j) =>
      Reminder(j['m'] as int, (j['n'] as String?) ?? '');
}

class ScheduleItem {
  const ScheduleItem({
    required this.id,
    required this.title,
    required this.startMinutes,
    required this.durationMinutes,
    required this.repeat,
    required this.startDate,
    required this.weekdays,
    required this.colorIndex,
    this.category,
    this.endDate,
    this.note = '',
    this.alarmMinutesBefore,
    List<Reminder>? reminders,
    bool notify = false,
  }) : reminders = reminders ?? (notify ? const [Reminder(5)] : const <Reminder>[]);

  final int id;
  final String title;
  final int startMinutes; // 0..1410, 30'un katı
  final int durationMinutes;
  final Repeat repeat;
  final DateTime startDate; // tek sefer: tarihi, diğerleri: başlangıç
  final List<int> weekdays; // 1=Pzt .. 7=Paz (haftalık için)
  final List<Reminder> reminders;
  final int colorIndex;
  final int? category; // categories listesindeki sıra, null = kategorisiz
  final DateTime? endDate; // tekrarlananlar için son gün (dahil), null = süresiz
  final String note; // etkinlik açıklaması
  final int? alarmMinutesBefore; // null = alarm yok; yoksa başlangıçtan kaç dk önce çalar

  bool get notify => reminders.isNotEmpty;

  bool get hasAlarm => alarmMinutesBefore != null;

  int get endMinutes => startMinutes + durationMinutes;

  String get timeLabel => '${fmtMinutes(startMinutes)} - ${fmtMinutes(endMinutes)}';

  bool get hasEnd => endDate != null && repeat != Repeat.once;

  String get repeatLabel {
    final base = switch (repeat) {
      Repeat.once => '${startDate.day} ${trMonths[startDate.month - 1]} ${startDate.year}',
      Repeat.daily => 'Her gün',
      Repeat.weekly =>
        'Her ${(weekdays.toList()..sort()).map((d) => trWeekdaysShort[d - 1]).join(', ')}',
      Repeat.monthly => 'Her ayın ${startDate.day}. günü',
    };
    return hasEnd ? '$base · ${endDate!.day} ${trMonths[endDate!.month - 1]} bitiş' : base;
  }

  bool occursOn(DateTime day) {
    final d = dateOnly(day);
    if (d.isBefore(dateOnly(startDate))) return false;
    if (hasEnd && d.isAfter(dateOnly(endDate!))) return false;
    return switch (repeat) {
      Repeat.once => sameDay(d, startDate),
      Repeat.daily => true,
      Repeat.weekly => weekdays.contains(d.weekday),
      Repeat.monthly => d.day == startDate.day,
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start': startMinutes,
        'duration': durationMinutes,
        'repeat': repeat.name,
        'startDate': startDate.toIso8601String(),
        'weekdays': weekdays,
        'reminders': reminders.map((r) => r.toJson()).toList(),
        'color': colorIndex,
        if (category != null) 'cat': category,
        if (endDate != null) 'endDate': endDate!.toIso8601String(),
        if (note.isNotEmpty) 'note': note,
        if (alarmMinutesBefore != null) 'alarm': alarmMinutesBefore,
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
        id: j['id'] as int,
        title: j['title'] as String,
        startMinutes: j['start'] as int,
        durationMinutes: j['duration'] as int,
        repeat: Repeat.values.byName(j['repeat'] as String),
        startDate: DateTime.parse(j['startDate'] as String),
        weekdays: (j['weekdays'] as List<dynamic>).cast<int>(),
        // Eski kayıtlarda yalnızca 'notify' vardı: 5 dk önce tek hatırlatma.
        reminders: (j['reminders'] as List<dynamic>?)
            ?.map((e) => Reminder.fromJson(e as Map<String, dynamic>))
            .toList(),
        notify: (j['notify'] as bool?) ?? false,
        colorIndex: (j['color'] as int?) ?? 0,
        category: j['cat'] as int?,
        endDate: DateTime.tryParse((j['endDate'] as String?) ?? ''),
        note: (j['note'] as String?) ?? '',
        alarmMinutesBefore: j['alarm'] as int?,
      );
}

class PackPurchase {
  const PackPurchase({required this.time, required this.price, required this.count});

  final DateTime time;
  final double price;
  final int count;

  Map<String, dynamic> toJson() =>
      {'time': time.toIso8601String(), 'price': price, 'count': count};

  factory PackPurchase.fromJson(Map<String, dynamic> j) => PackPurchase(
        time: DateTime.parse(j['time'] as String),
        price: (j['price'] as num).toDouble(),
        count: j['count'] as int,
      );
}

/// Günlük ruh hali seçenekleri: (emoji, ad).
const moods = <(String, String)>[
  ('😞', 'Kötü'),
  ('😕', 'Pek değil'),
  ('😐', 'Normal'),
  ('🙂', 'İyi'),
  ('😄', 'Harika'),
];

/// Bir günün günlük yazısı ve ruh hali.
class JournalEntry {
  const JournalEntry({this.text = '', this.mood, this.updated});

  final String text;
  final int? mood; // moods listesindeki sıra
  final DateTime? updated;

  bool get isEmpty => text.trim().isEmpty && mood == null;

  Map<String, dynamic> toJson() => {
        'text': text,
        if (mood != null) 'mood': mood,
        if (updated != null) 'updated': updated!.toIso8601String(),
      };

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
        text: (j['text'] as String?) ?? '',
        mood: j['mood'] as int?,
        updated: DateTime.tryParse((j['updated'] as String?) ?? ''),
      );
}
