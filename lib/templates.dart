/// Tek dokunuşla eklenen hazır rutinler. Kategoriler categories.dart sırasına göre.
class TemplateEntry {
  const TemplateEntry(this.title, this.category, this.start, this.duration);

  final String title;
  final int category;
  final int start; // gün içi dakika, 30'un katı
  final int duration; // dakika, 30'un katı
}

class RoutineTemplate {
  const RoutineTemplate(this.name, this.emoji, this.entries);

  final String name;
  final String emoji;
  final List<TemplateEntry> entries;
}

const routineTemplates = <RoutineTemplate>[
  RoutineTemplate('Sabah rutini', '🌅', [
    TemplateEntry('Su iç', 8, 7 * 60, 30),
    TemplateEntry('Meditasyon', 6, 7 * 60 + 30, 30),
    TemplateEntry('Spor', 0, 8 * 60, 60),
  ]),
  RoutineTemplate('Çalışma günü', '💼', [
    TemplateEntry('İş', 2, 9 * 60, 240),
    TemplateEntry('Öğle yemeği', 4, 12 * 60, 60),
    TemplateEntry('İş', 2, 13 * 60, 240),
  ]),
  RoutineTemplate('Öğrenci', '🎓', [
    TemplateEntry('Ders', 1, 9 * 60, 180),
    TemplateEntry('Ders tekrarı', 1, 19 * 60, 60),
    TemplateEntry('Kitap', 3, 21 * 60, 30),
  ]),
  RoutineTemplate('Sağlıklı yaşam', '💪', [
    TemplateEntry('Su iç', 8, 10 * 60, 30),
    TemplateEntry('Yürüyüş', 7, 18 * 60, 60),
    TemplateEntry('İlaç', 9, 21 * 60, 30),
  ]),
  RoutineTemplate('Akşam rutini', '🌙', [
    TemplateEntry('Kitap', 3, 21 * 60 + 30, 30),
    TemplateEntry('Meditasyon', 6, 22 * 60, 30),
    TemplateEntry('Uyku', 5, 23 * 60, 30),
  ]),
];
