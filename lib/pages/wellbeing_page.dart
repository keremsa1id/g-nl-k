import 'package:flutter/material.dart';

import '../widgets.dart';
import 'health_page.dart';
import 'profile_page.dart';
import 'screen_time_page.dart';

/// Alt menüdeki "Sağlık" sekmesi: Health Connect verileri ve ekran süresi.
class WellbeingPage extends StatefulWidget {
  const WellbeingPage({super.key});

  @override
  State<WellbeingPage> createState() => _WellbeingPageState();
}

class _WellbeingPageState extends State<WellbeingPage> {
  int _tab = 0; // 0 = Sağlık, 1 = Ekran süresi
  // Ekran süresi ilk açılınca yüklenir (her açılışta 8 sorgu yapıyor).
  final _opened = <int>{0};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              eyebrow: 'Sağlık ve telefon',
              title: _tab == 0 ? 'Sağlık' : 'Ekran süresi',
              actions: const [ProfileButton()],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: 0, icon: Icon(Icons.favorite_rounded), label: Text('Sağlık')),
                    ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.phone_android_rounded),
                        label: Text('Ekran süresi')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() {
                    _tab = s.first;
                    _opened.add(_tab);
                  }),
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  const HealthPage(embedded: true),
                  if (_opened.contains(1))
                    const ScreenTimePage(embedded: true)
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
