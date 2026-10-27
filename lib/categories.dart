import 'package:flutter/material.dart';

class Category {
  const Category(this.name, this.icon);

  final String name;
  final IconData icon;
}

/// Etkinlik kategorileri. Sıra kayıtlarda saklandığı için yalnızca sona ekleme yap.
const categories = <Category>[
  Category('Spor', Icons.fitness_center_rounded),
  Category('Ders', Icons.school_rounded),
  Category('İş', Icons.work_rounded),
  Category('Kitap', Icons.menu_book_rounded),
  Category('Yemek', Icons.restaurant_rounded),
  Category('Uyku', Icons.bedtime_rounded),
  Category('Meditasyon', Icons.self_improvement_rounded),
  Category('Yürüyüş', Icons.directions_walk_rounded),
  Category('Su iç', Icons.water_drop_rounded),
  Category('İlaç', Icons.medication_rounded),
];

Category? categoryOf(int? index) =>
    index == null || index < 0 || index >= categories.length ? null : categories[index];
