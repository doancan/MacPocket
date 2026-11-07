# Pencere geçişini geliştirme ve doğrulama

Son teslim kontrolü — 7 Kasım 2026: `swift test` **1439 test / 5 isteğe bağlı
atlama / 0 hata**; ayar formunda TR/EN **30'ar native kontrol**; yerelleştirme
**4242 anahtar / 0 eksik / 0 biçim uyuşmazlığı**. İmzalı Debug ve Release
paketlemesi geçti. Release executable'ında Debug denetim girişleri bulunmaz;
üretim sistem kısayolu geri yükleme yardımcısı korunur. Yerel paket:
`.build/MacPocket-0.1.5-arm64.zip` (**0.1.5 / build 8**).

Formun native eylemleri ve AX adları doğrulandı. Bitmap ekran görüntüleri cam
yüzeylerde eksik bileşim içerdiğinden tam görsel veya VoiceOver kabulü sayılmaz.
Fiziksel klavye/trackpad kabulü yerel erişim bekler.

Ürün: animasyonlu Alt+Tab kartları. Tools → Pencere Geçişi, ayarlar ve ayrıntılı
pencere listesidir. İlk açılışta kısayollar ve görünüm gösterilir; diğer bölümler
**Gelişmiş ayarları göster** ile açılır. Bu seçim yalnız görünümü düzenler;
mevcut tercihler ve etkin özellikler korunur.

## Kaynak düzeni

- `Sources/MacPocketApp/WindowSwitcherSettingsForm.swift`: kısayol, görünüm ve
  gelişmiş ayar bileşenleri.
- `Sources/MacPocketApp/WindowSwitcherView.swift`: izinler ve Tools pencere listesi.
- `Sources/MacPocketApp/Diagnostics/WindowSwitcher/`: yalnız `#if DEBUG` altında
  derlenen native denetimler, örnek kataloglar ve giriş probları.
- `Sources/MacPocketCore/Diagnostics/`: sahipli test pencerelerine ait Debug köprüsü.
- `Tests/MacPocketAppTests/`, `Tests/MacPocketCoreTests/`: model ve entegrasyon testleri.
- `scripts/fixtures/`: ayrı süreçte açılan sahipli test uygulaması.

SwiftPM alt klasörleri otomatik derler; dosyaların taşınması tür adlarını ve
komutları değiştirmez. Üretimde gereken CLI ve sistem kısayolu geri yükleme
yardımcısı ürün kaynaklarında kalır. Araştırma ve build çıktıları `.build/`
altındadır; Git'e eklenmez.

## Otomatik kontroller

Depo kökünden:

```sh
swift test
scripts/check-localizations.sh
scripts/build-app.sh debug
scripts/audit-window-switcher.sh --skip-build --only-settings
```

Son komut izole Debug kopyalarında Türkçe/İngilizce ayar formunu açar; gelişmiş
seçenekleri native erişilebilirlik eylemiyle açıp kapatır. Kullanıcı tercihlerini
değiştirmez. Bu kontrol VoiceOver veya fiziksel klavye kabulü değildir.
Release paketi için `scripts/build-app.sh release` kullanılır; sürüm/build
yalnız kullanıcı isterse değiştirilir.

Gerçek trackpad bağlı bir makinede adaptörün başlatılıp durdurulması isteğe bağlıdır:

```sh
MACPOCKET_TEST_TRACKPAD=1 swift test --filter SwitcherGestureAdapterTests
```

Bu test fiziksel kaydırma, haptik hissi veya bağlantıyı kesip yeniden bağlama
kabulü sayılmaz. Root test toplamı 1439'dur; standart koşuda 4 disk/sistem ve
1 bağlı trackpad testi atlanır.

## Yerel erişim gerektiren kabul

Uzaktan çalışırken fiziksel test başlatılmaz. Kullanıcı hazır olduğunda:

```sh
scripts/audit-window-switcher-external.sh --skip-build --only-manual-keyboard
```

Bu mod gerçek Carbon kısayollarını kaydeder ve çakışan AltTab'ı geçici olarak
kapatır. İki sahipli test penceresinde önce Option+Tab, sonra Command+Tab için
basılı tutma, ileri/geri gezinme ve bırakınca odak denetlenir. İptal/bitirme
sonunda sistem kısayolları geri yüklenir ve AltTab yeniden açılır. Debug paket
gerektirir; Release paketlemesinden sonra önce `scripts/build-app.sh debug`
çalıştırılmalıdır. Fiziksel trackpad, gerçek uyku/uyanma ve haptik kabulü ayrıca
yapılır.

Ayrıntılı özellik kanıtları ve tarihsel sonuçlar [ana belgede](../WINDOW_SWITCHER.md),
ücretsiz/Pro ayrımı [araştırma raporundadır](../research/2026-11-06-alttab-free-pro.md).
