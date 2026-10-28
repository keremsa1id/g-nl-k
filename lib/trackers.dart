import 'models.dart';

/// Bırakılmak / azaltılmak istenen bir alışkanlığın takibi (sigara, alkol, gazlı içecek…).
class Tracker {
  Tracker({
    required this.id,
    required this.name,
    required this.emoji,
    required this.unit,
    required this.logLabel,
    this.packName = '',
    this.packSize = 1,
    this.packPrice = 0,
    List<DateTime>? events,
    List<PackPurchase>? packs,
    this.quitStart,
  })  : events = events ?? [],
        packs = packs ?? [];

  final String id;
  String name;
  String emoji;
  String unit; // tek kaydın birimi: sigara, kadeh, kutu…
  String logLabel; // ana buton: "Sigara içtim", "İçtim"…
  String packName; // alım birimi: Paket, Şişe…; boşsa alım takibi yok
  int packSize; // bir alımdaki adet
  double packPrice; // alım penceresinde varsayılan fiyat

  final List<DateTime> events; // sıralı
  final List<PackPurchase> packs; // sıralı
  DateTime? quitStart; // kayıt olmadan sayacı başlatmak için

  bool get tracksPurchases => packName.trim().isNotEmpty;

  /// Sayacın başladığı an: son kayıt veya manuel başlangıç (hangisi sonraysa).
  DateTime? get counterStart {
    final last = events.isEmpty ? null : events.last;
    if (last == null) return quitStart;
    if (quitStart == null) return last;
    return last.isAfter(quitStart!) ? last : quitStart;
  }

  int countOn(DateTime day) => events.where((t) => sameDay(t, day)).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'unit': unit,
        'log': logLabel,
        'pack': packName,
        'packSize': packSize,
        'packPrice': packPrice,
        'events': events.map((e) => e.toIso8601String()).toList(),
        'packs': packs.map((p) => p.toJson()).toList(),
        if (quitStart != null) 'quit': quitStart!.toIso8601String(),
      };

  factory Tracker.fromJson(Map<String, dynamic> j) => Tracker(
        id: j['id'] as String,
        name: j['name'] as String,
        emoji: (j['emoji'] as String?) ?? '🎯',
        unit: (j['unit'] as String?) ?? 'kez',
        logLabel: (j['log'] as String?) ?? 'Yaptım',
        packName: (j['pack'] as String?) ?? '',
        packSize: (j['packSize'] as int?) ?? 1,
        packPrice: ((j['packPrice'] as num?) ?? 0).toDouble(),
        events: ((j['events'] as List<dynamic>?) ?? [])
            .map((e) => DateTime.parse(e as String))
            .toList()
          ..sort(),
        packs: ((j['packs'] as List<dynamic>?) ?? [])
            .map((e) => PackPurchase.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time)),
        quitStart: DateTime.tryParse((j['quit'] as String?) ?? ''),
      );
}

/// Hazır takip seçenekleri.
class TrackerPreset {
  const TrackerPreset(this.name, this.emoji, this.unit, this.logLabel,
      [this.packName = '', this.packSize = 1, this.packPrice = 0]);

  final String name;
  final String emoji;
  final String unit;
  final String logLabel;
  final String packName;
  final int packSize;
  final double packPrice;

  Tracker create(String id) => Tracker(
        id: id,
        name: name,
        emoji: emoji,
        unit: unit,
        logLabel: logLabel,
        packName: packName,
        packSize: packSize,
        packPrice: packPrice,
      );
}

const trackerPresets = <TrackerPreset>[
  TrackerPreset('Sigara', '🚬', 'sigara', 'Sigara içtim', 'Paket', 20, 120),
  TrackerPreset('Alkol', '🍺', 'kadeh', 'İçtim', 'Şişe', 1, 150),
  TrackerPreset('Gazlı içecek', '🥤', 'kutu', 'İçtim', 'Kutu', 1, 40),
  TrackerPreset('Kahve', '☕', 'fincan', 'İçtim', 'Fincan', 1, 90),
  TrackerPreset('Tatlı / şeker', '🍫', 'adet', 'Yedim', 'Adet', 1, 50),
  TrackerPreset('Fast food', '🍔', 'porsiyon', 'Yedim', 'Sipariş', 1, 300),
  TrackerPreset('Sosyal medya', '📱', 'kez', 'Girdim'),
  TrackerPreset('Elektronik sigara', '💨', 'çekim', 'Kullandım', 'Kartuş', 1, 200),
];

/// Kendi takibini oluştururken seçilebilecek emojiler.
const trackerEmojis = [
  '🚬', '🍺', '🍷', '🥃', '🥤', '☕', '🍫', '🍬', '🍔', '🍕', '📱', '🎮',
  '🎰', '💨', '💊', '🛒', '📺', '😤', '🍟', '🧃', '🎯', '⛔',
];
