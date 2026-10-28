import 'package:flutter/material.dart';

class ItemCategory {
  const ItemCategory(this.name, this.icon, this.group, [this.minutes = 60]);

  final String name;
  final IconData icon;
  final String group; // categoryGroups içinden
  final int minutes; // seçilince önerilen süre (30'un katı)
}

/// Editördeki filtre sekmeleri.
const categoryGroups = ['Sağlık', 'Üretkenlik', 'Ev & günlük', 'Sosyal', 'Hobi'];

/// Etkinlik kategorileri. Sıra kayıtlarda saklandığı için yalnızca sona ekleme yap.
const categories = <ItemCategory>[
  ItemCategory('Spor', Icons.fitness_center_rounded, 'Sağlık'),
  ItemCategory('Ders', Icons.school_rounded, 'Üretkenlik'),
  ItemCategory('İş', Icons.work_rounded, 'Üretkenlik', 240),
  ItemCategory('Kitap', Icons.menu_book_rounded, 'Hobi', 30),
  ItemCategory('Yemek', Icons.restaurant_rounded, 'Ev & günlük'),
  ItemCategory('Uyku', Icons.bedtime_rounded, 'Sağlık', 480),
  ItemCategory('Meditasyon', Icons.self_improvement_rounded, 'Sağlık', 30),
  ItemCategory('Yürüyüş', Icons.directions_walk_rounded, 'Sağlık', 30),
  ItemCategory('Su iç', Icons.water_drop_rounded, 'Sağlık', 30),
  ItemCategory('İlaç', Icons.medication_rounded, 'Sağlık', 30),
  // 10+
  ItemCategory('Koşu', Icons.directions_run_rounded, 'Sağlık', 30),
  ItemCategory('Yoga', Icons.sports_gymnastics_rounded, 'Sağlık'),
  ItemCategory('Bisiklet', Icons.directions_bike_rounded, 'Sağlık'),
  ItemCategory('Yüzme', Icons.pool_rounded, 'Sağlık'),
  ItemCategory('Doktor', Icons.local_hospital_rounded, 'Sağlık'),
  ItemCategory('Kişisel bakım', Icons.spa_rounded, 'Sağlık', 30),
  ItemCategory('Mola', Icons.coffee_rounded, 'Sağlık', 30),
  ItemCategory('Toplantı', Icons.groups_rounded, 'Üretkenlik'),
  ItemCategory('Kodlama', Icons.code_rounded, 'Üretkenlik', 120),
  ItemCategory('Dil öğrenme', Icons.translate_rounded, 'Üretkenlik', 30),
  ItemCategory('Proje', Icons.lightbulb_rounded, 'Üretkenlik', 120),
  ItemCategory('Planlama', Icons.checklist_rounded, 'Üretkenlik', 30),
  ItemCategory('E-posta', Icons.mail_rounded, 'Üretkenlik', 30),
  ItemCategory('Günlük yaz', Icons.edit_note_rounded, 'Üretkenlik', 30),
  ItemCategory('Temizlik', Icons.cleaning_services_rounded, 'Ev & günlük'),
  ItemCategory('Alışveriş', Icons.shopping_cart_rounded, 'Ev & günlük'),
  ItemCategory('Yemek yap', Icons.soup_kitchen_rounded, 'Ev & günlük'),
  ItemCategory('Çamaşır', Icons.local_laundry_service_rounded, 'Ev & günlük'),
  ItemCategory('Fatura / ödeme', Icons.receipt_long_rounded, 'Ev & günlük', 30),
  ItemCategory('Yol', Icons.directions_bus_rounded, 'Ev & günlük'),
  ItemCategory('Evcil hayvan', Icons.pets_rounded, 'Ev & günlük', 30),
  ItemCategory('Bitki sula', Icons.local_florist_rounded, 'Ev & günlük', 30),
  ItemCategory('Aile', Icons.family_restroom_rounded, 'Sosyal', 120),
  ItemCategory('Arkadaşlar', Icons.people_rounded, 'Sosyal', 120),
  ItemCategory('Arama', Icons.call_rounded, 'Sosyal', 30),
  ItemCategory('Randevu', Icons.event_available_rounded, 'Sosyal'),
  ItemCategory('Gönüllülük', Icons.volunteer_activism_rounded, 'Sosyal', 120),
  ItemCategory('İbadet', Icons.mosque, 'Sosyal', 30),
  ItemCategory('Müzik', Icons.music_note_rounded, 'Hobi'),
  ItemCategory('Enstrüman', Icons.piano_rounded, 'Hobi'),
  ItemCategory('Film / dizi', Icons.movie_rounded, 'Hobi', 120),
  ItemCategory('Oyun', Icons.sports_esports_rounded, 'Hobi'),
  ItemCategory('Çizim / sanat', Icons.palette_rounded, 'Hobi'),
  ItemCategory('Fotoğraf', Icons.photo_camera_rounded, 'Hobi'),
  ItemCategory('Podcast', Icons.podcasts_rounded, 'Hobi', 30),
  ItemCategory('Doğa / gezi', Icons.hiking_rounded, 'Hobi', 180),
];

ItemCategory? categoryOf(int? index) =>
    index == null || index < 0 || index >= categories.length ? null : categories[index];

/// Türkçe büyük/küçük harf duyarsız karşılaştırma için (İ→i, I→ı).
String trLower(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// Başlık bir kategorinin adıyla birebir aynıysa o kategorinin sırası.
int? categoryForTitle(String title) {
  final t = trLower(title.trim());
  if (t.isEmpty) return null;
  final i = categories.indexWhere((c) => trLower(c.name) == t);
  return i < 0 ? null : i;
}
