/// Uygulamanın dış bağlantıları (web sitesi, mağaza).

/// Android paket adı (build.gradle.kts'teki applicationId).
const androidPackage = 'com.kerem.gunluk';

/// Uygulama Google Play'de yayınlanınca true yap: web sitesindeki QR kod ve
/// "Google Play'den indir" butonu gerçek mağaza sayfasına yönlendirir.
const playStoreReady = false;

/// Google Play mağaza sayfası (yayınlanınca bu adreste olur).
const playStoreUrl = 'https://play.google.com/store/apps/details?id=$androidPackage';
