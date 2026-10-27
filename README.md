# Günlük — Program + Sigara Bırakma (Android)

Flutter ile yazılmış, tamamen ücretsiz ve çevrimdışı çalışan Android uygulaması. Veriler sadece telefonda saklanır.

## Özellikler

**1. Program**
- Günlük zaman çizelgesi (00:00–23:30, yarım saatlik dilimler); boş dilime dokun → o saatte ekle
- Tekrar: tek sefer / her gün / haftalık (gün seçmeli) / aylık
- Etkinlikten **5 dk önce bildirim** (örn. her gün 22:00 spor → 21:55 bildirim); telefon yeniden başlasa da kurulur
- Kart: dokun = düzenle, basılı tut = sil · Üstteki liste ikonu = tüm kayıtlar · ⋮ menü = bildirim testi

**2. Sigara bırakma**
- Son sigaradan beri canlı sayaç; “Sigara içtim” → kaydeder ve sıfırlar (geri al var)
- Basılı tut → geçmiş bir saat gir
- “Paket aldım” → fiyat + adet
- İstatistik: bugün, son 7 gün, en uzun ara, toplam, harcanan ₺, paketten kalan; sıradaki hedef çubuğu

## APK'yı GitHub'dan almak (bilgisayarda Flutter gerekmez)
1. Bu klasörü GitHub repona yükle (`.github/workflows` klasörü dahil).
2. Repo → **Actions** → “APK Derle” çalışır (~5-8 dk). Çalışmazsa **Run workflow** de.
3. Biten işin altındaki **Artifacts → gunluk-apk** zip'ini indir, içindeki `app-release.apk`'yı telefona at ve kur (bilinmeyen kaynaklara izin ver).

> Her CI derlemesi farklı debug anahtarıyla imzalanır; güncellerken “uygulama yüklenmedi” derse eskisini kaldırıp kur (veriler silinir).

## VS Code'da çalıştırmak
Gereken: Flutter SDK (önerilen **3.35.x**), Android SDK, VS Code + Flutter eklentisi.

```bash
# proje klasöründe, bir kez:
flutter create --platforms=android --org com.kerem --project-name gunluk .
flutter pub get

# telefonda USB hata ayıklama açık ve bağlıyken:
flutter run
# ya da APK:
flutter build apk --release   # -> build/app/outputs/flutter-apk/app-release.apk
```

## Telefonda ilk açılış
- Bildirim iznini **ver**.
- Xiaomi/Huawei/Samsung gibi markalarda: Ayarlar → Uygulamalar → Günlük → Pil → **Kısıtlama yok**; aksi halde bildirimler gecikebilir.

## Proje yapısı
```
lib/
  main.dart               # uygulama + alt menü
  models.dart             # veri modelleri, tarih biçimleri
  storage.dart            # SharedPreferences kayıt
  notifications.dart      # zamanlanmış bildirimler (5 dk önce)
  pages/schedule_page.dart
  pages/item_editor.dart
  pages/smoke_page.dart
android/app/              # izinler, desugaring (bildirim paketi için)
.github/workflows/build-apk.yml
```
