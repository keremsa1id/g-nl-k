import 'package:flutter/material.dart';

class ItemCategory {
  const ItemCategory(this.name, this.icon);

  final String name;
  final IconData icon;
}

/// Etkinlik kategorileri. Sıra kayıtlarda saklandığı için yalnızca sona ekleme yap.
const categories = <ItemCategory>[
  ItemCategory('Spor', Icons.fitness_center_rounded),
  ItemCategory('Ders', Icons.school_rounded),
  ItemCategory('İş', Icons.work_rounded),
  ItemCategory('Kitap', Icons.menu_book_rounded),
  ItemCategory('Yemek', Icons.restaurant_rounded),
  ItemCategory('Uyku', Icons.bedtime_rounded),
  ItemCategory('Meditasyon', Icons.self_improvement_rounded),
  ItemCategory('Yürüyüş', Icons.directions_walk_rounded),
  ItemCategory('Su iç', Icons.water_drop_rounded),
  ItemCategory('İlaç', Icons.medication_rounded),
];

ItemCategory? categoryOf(int? index) =>
    index == null || index < 0 || index >= categories.length ? null : categories[index];
