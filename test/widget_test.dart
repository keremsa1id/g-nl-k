import 'package:flutter_test/flutter_test.dart';

import 'package:gunluk/models.dart';

void main() {
  test('Haftalık etkinlik doğru günlerde görünür', () {
    final item = ScheduleItem(
      id: 1,
      title: 'Spor',
      startMinutes: 22 * 60,
      durationMinutes: 60,
      repeat: Repeat.weekly,
      startDate: DateTime(2026, 1, 1),
      weekdays: const [1, 3],
      notify: true,
      colorIndex: 0,
    );
    expect(item.occursOn(DateTime(2026, 10, 26)), isTrue); // Pazartesi
    expect(item.occursOn(DateTime(2026, 10, 27)), isFalse); // Salı
  });
}
