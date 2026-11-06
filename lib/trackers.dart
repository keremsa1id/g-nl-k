import 'models.dart';
import 'screen_time.dart' show AppGroup;

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
    this.autoMode = AutoMode.off,
    this.autoGroup = AppGroup.social,
    List<String>? autoApps,
    this.autoSync,
    this.autoExit,
  })  : events = events ?? [],
        packs = packs ?? [],
        autoApps = autoApps ?? [];

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

  /// Telefondaki uygulama kullanımından otomatik kayıt: her girişte bir kayıt eklenir.
  AutoMode autoMode;
  AppGroup autoGroup; // autoMode == group iken izlenen grup
  List<String> autoApps; // autoMode == apps iken izlenen paketler
  DateTime? autoSync; // otomatik algılamanın en son baktığı an
  DateTime? autoExit; // izlenen uygulamadan en son çıkış (sayaç buradan başlar)

  bool get tracksPurchases => packName.trim().isNotEmpty;
  bool get isAuto => autoMode != AutoMode.off;

  /// Sayacın başladığı an: son kayıt, manuel başlangıç veya izlenen uygulamadan
  /// çıkış (hangisi sonraysa) — uygulamanın içinde geçen süre sayılmaz.
  DateTime? get counterStart {
    DateTime? best;
    for (final d in [events.isEmpty ? null : events.last, quitStart, autoExit]) {
      if (d != null && (best == null || d.isAfter(best))) best = d;
    }
    return best;
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
        if (isAuto) 'auto': autoMode.name,
        if (autoMode == AutoMode.group) 'autoGroup': autoGroup.name,
        if (autoApps.isNotEmpty) 'autoApps': autoApps,
        if (autoSync != null) 'autoSync': autoSync!.toIso8601String(),
        if (autoExit != null) 'autoExit': autoExit!.toIso8601String(),
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
        autoMode: j['auto'] == 'social'
            ? AutoMode.group // ilk sürümde kaydedilmiş sosyal medya modu
            : AutoMode.values.firstWhere((m) => m.name == j['auto'],
                orElse: () => AutoMode.off),
        autoGroup: AppGroup.values.firstWhere((g) => g.name == j['autoGroup'],
            orElse: () => AppGroup.social),
        autoApps: ((j['autoApps'] as List<dynamic>?) ?? []).cast<String>().toList(),
        autoSync: DateTime.tryParse((j['autoSync'] as String?) ?? ''),
        autoExit: DateTime.tryParse((j['autoExit'] as String?) ?? ''),
      );
}

/// Otomatik algılama: kapalı, bir uygulama grubu (sosyal medya, oyun…) ya da seçilen uygulamalar.
enum AutoMode { off, group, apps }

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

  /// Hazır seçeneğin otomatik algılaması: sosyal medya ve oyun gruba, YouTube tek uygulamaya bağlı.
  AutoMode get autoMode => switch (name) {
        'Sosyal medya' || 'Oyun' => AutoMode.group,
        'YouTube' => AutoMode.apps,
        _ => AutoMode.off,
      };

  AppGroup get autoGroup => name == 'Oyun' ? AppGroup.game : AppGroup.social;

  List<String> get autoApps =>
      name == 'YouTube' ? const ['com.google.android.youtube'] : const [];
}

const trackerPresets = <TrackerPreset>[
  TrackerPreset('Sigara', '🚬', 'sigara', 'Sigara içtim', 'Paket', 20, 120),
  TrackerPreset('Alkol', '🍺', 'kadeh', 'İçtim', 'Şişe', 1, 150),
  TrackerPreset('Gazlı içecek', '🥤', 'kutu', 'İçtim', 'Kutu', 1, 40),
  TrackerPreset('Kahve', '☕', 'fincan', 'İçtim', 'Fincan', 1, 90),
  TrackerPreset('Tatlı / şeker', '🍫', 'adet', 'Yedim', 'Adet', 1, 50),
  TrackerPreset('Fast food', '🍔', 'porsiyon', 'Yedim', 'Sipariş', 1, 300),
  TrackerPreset('Sosyal medya', '📱', 'kez', 'Girdim'),
  TrackerPreset('YouTube', '▶️', 'kez', 'Girdim'),
  TrackerPreset('Oyun', '🎮', 'kez', 'Oynadım'),
  TrackerPreset('Elektronik sigara', '💨', 'çekim', 'Kullandım', 'Kartuş', 1, 200),
];

/// Kendi takibini oluştururken seçilebilecek emojiler.
const trackerEmojis = [
  '🚬', '🍺', '🍷', '🥃', '🥤', '☕', '🍫', '🍬', '🍔', '🍕', '📱', '🎮',
  '🎰', '💨', '💊', '🛒', '📺', '😤', '🍟', '🧃', '🎯', '⛔',
];
