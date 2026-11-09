# MacPocket araç arayüzü kontrolü — 5 Kasım 2026

## Kapsam ve çalışma ortamı

MacPocket 0.1.3; SwiftUI/AppKit; pilsiz Mac Studio. Türkçe kaynak arayüzü, İngilizce yerelleştirme. Mevcut tasarım bileşenleri, araç davranışları ve sürüm numarası korundu. Katalogdaki 57 giriş için yönlendirme ve ekran kaynakları eşleştirildi; ortak sayfa başlığı, arama, yüklenme/boş/hata/sonuç ve izin durumları incelendi.

## Düzeltilen bulgular

| Öncelik | Bulgu ve kanıt | Değişiklik | Doğrulama |
|---|---|---|---|
| P1 | Ekran Kaydı başlatma/durdurma sürerken yeni tıklama kabul ediyordu; `stopCapture` hatasında da dosya kaydedildi bildirimi üretilebiliyordu. | Geçiş/kaydetme durumu, kilitli eylemler ve ilerleme; başarı yalnız `recordingOutputDidFinishRecording` ve dosya varlığıyla gösterilir. Eski kaydın gecikmiş callback’i kimlik kontrolünden geçer. | Derleme, SDK delegate sözleşmesi ve kaynak incelemesi; gerçek kayıt kabul testi bekliyor. |
| P1 | Ses Çıkışı, Hızlı İşlemler, Ekran Temizleme ve Ekran Kaydı kaydırmasız sabit içerikti. | Formlar kaydırılabilir oldu; ortak başlık 760 px altındaki içerik genişliğinde eylemleri alt satıra alır. | 960/1280 px pencerede canlı açılış ve yerleşim. |
| P2 | Bazı yenilemeler ilk yüklenmeyi boş/başarısız sonuçla aynı yüzeyde gösteriyordu. | USB/Thunderbolt, Disk Sağlığı, Bluetooth, Ağ Trafiği ve Başlangıç Öğeleri için ayrı ilerleme; yenileme sırasında tekrar tıklama kilidi. Başarılı boş sonuç ile okuma hatası ayrılır. | Kaynak incelemesi; canlı mevcut cihaz/ilk yükleme açılışı. |
| P2 | Thunderbolt komutunun sıfır olmayan çıkışı boş port listesi gibi işleniyordu. | Çıkış kodu kontrolü, hata ve yeniden deneme yönlendirmesi. | Derleme/kaynak incelemesi; hata enjeksiyonu yapılmadı. |
| P2 | Araçlar, Görev Yöneticisi ve Sistem Raporları `FocusState` bağını arama bileşeninin dışına uyguluyordu. | Bağ doğrudan metin alanına taşındı; Başlangıç Öğeleri de arama komutunu karşılar. Temizleme sonrası metin odağı korunur. | Araçlar, Görev Yöneticisi ve Başlangıç Öğeleri’nde arama komutundan sonra gerçek `NSWindow.firstResponder` metin alanı/editörü oldu. Sistem Raporları çıktı araması kaynak/derleme ile kontrol edildi. |
| P2 | Yerel ağ kartları ve harita düğümleri yalnız fare hareketiyle seçiliyordu. | Ağ ve cihazlar native Button oldu; seçili durumu ve simgeli kapatma/kaldırma eylemleri adlandırıldı; harita hover hareketi azaltılmış hareket tercihini izler. | Kaynak, derleme, mevcut boş açılış; dolu ağ haritası klavye/VoiceOver kabul testi bekliyor. |
| P2 | Ses Çıkışı başarısız aygıt geçişini bildirmiyordu; son döngü öğesi çıkarılınca boş dizi “tüm aygıtlar” anlamına geri dönüyordu. | Kalıcı hata, boş aygıt durumu ve son döngü öğesini koruyan açıklamalı kontrol. | Kaynak incelemesi; mevcut aygıtlarla açılış; temel ses kuralları testleri. |
| P2 | Destek Raporu hazırlanırken kopyalama/kaydetme eski içeriği kullanabiliyordu. | Hazırlanma ilerlemesi, kilitli dışa aktarma, kısmi veri uyarısı. | Kaynak, derleme ve canlı açılış. |

## Araç bazında izleme

“TR 960/1280” gerçek uygulamadaki sayfanın iki genişlikte açılması ve uygulama içi erişilebilirlik ağacının okunmasıdır. “EN 960/1280” değişen ekranların İngilizce/koyu görünümde açılmasıdır. Bu kayıtlar eylemlerin bütün olası sonuçlarını veya görsel kabulü onaylamaz. Paylaşılan ekran kullanan katalog girişleri ayrı ayrı açıldı.

| # | Katalog aracı | Ekran kaynağı | Bu turdaki durum | Canlı açılış |
|---|---|---|---|---|
| 1 | macOS Araçları | [MacUtilitiesView.swift](../Sources/MacPocketApp/MacUtilitiesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 2 | Bakım | [MaintenanceView.swift](../Sources/MacPocketApp/MaintenanceView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 3 | Başlangıç Öğeleri | [StartupItemsView.swift](../Sources/MacPocketApp/StartupItemsView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 4 | Başlatma Görevleri | [MacUtilitiesView.swift](../Sources/MacPocketApp/MacUtilitiesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 5 | Ağ Hız Testi | [SpeedTestView.swift](../Sources/MacPocketApp/SpeedTestView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 6 | Ağ Trafiği | [NetworkTrafficView.swift](../Sources/MacPocketApp/NetworkTrafficView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 7 | Yerel Ağ | [LANScannerView.swift](../Sources/MacPocketApp/LANScannerView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 8 | Güç Zamanlaması | [PowerScheduleView.swift](../Sources/MacPocketApp/PowerScheduleView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 9 | Wi-Fi Analizi | [WiFiView.swift](../Sources/MacPocketApp/WiFiView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 10 | Ekran Süresi | [ScreenTimeView.swift](../Sources/MacPocketApp/ScreenTimeView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 11 | Hosts Dosyası | [HostsView.swift](../Sources/MacPocketApp/HostsView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 12 | USB ve Thunderbolt | [PeripheralsView.swift](../Sources/MacPocketApp/PeripheralsView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 13 | USB Çıkarma Yöneticisi | [USBEjectView.swift](../Sources/MacPocketApp/USBEjectView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 14 | Port Yöneticisi | [PortManagerView.swift](../Sources/MacPocketApp/PortManagerView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 15 | Disk Sağlığı | [DiskHealthView.swift](../Sources/MacPocketApp/DiskHealthView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 16 | Disk Bilgileri | [MacUtilitiesView.swift](../Sources/MacPocketApp/MacUtilitiesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 17 | Spotlight Durumu | [MacUtilitiesView.swift](../Sources/MacPocketApp/MacUtilitiesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 18 | DNS Yapılandırması | [MacUtilitiesView.swift](../Sources/MacPocketApp/MacUtilitiesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 19 | Ağ Rotaları | [MacUtilitiesView.swift](../Sources/MacPocketApp/MacUtilitiesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 20 | macOS Güncellemeleri | [MacUtilitiesView.swift](../Sources/MacPocketApp/MacUtilitiesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 21 | Gizlilik Kontrolü | [PrivacyCheckView.swift](../Sources/MacPocketApp/PrivacyCheckView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 22 | Sistem Güvenliği | [MacUtilitiesView.swift](../Sources/MacPocketApp/MacUtilitiesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 23 | Görev Yöneticisi | [TaskManagerView.swift](../Sources/MacPocketApp/TaskManagerView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 24 | Gizli Ayarlar | [HiddenSettingsView.swift](../Sources/MacPocketApp/HiddenSettingsView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 25 | Destek Raporu | [SupportReportView.swift](../Sources/MacPocketApp/SupportReportView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 26 | Sistem Raporları | [SystemToolsView.swift](../Sources/MacPocketApp/SystemToolsView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 27 | Mac'i Uyanık Tut | [ToolsHubView.swift](../Sources/MacPocketApp/ToolsHubView.swift) | Arayüz durumu düzeltildi | EN 960/1280; gerçek sheet açıldı |
| 28 | Uygulama Dondurucu | [AppFreezerService.swift](../Sources/MacPocketApp/AppFreezerService.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 29 | Ekran Ayarları | [DisplaySettingsView.swift](../Sources/MacPocketApp/DisplaySettingsView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 30 | Bluetooth Pilleri | [BluetoothBatteryView.swift](../Sources/MacPocketApp/BluetoothBatteryView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 31 | Ekran Görüntüsü | [ScreenshotView.swift](../Sources/MacPocketApp/ScreenshotView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 32 | Ekran Kaydı | [ScreenRecorderView.swift](../Sources/MacPocketApp/ScreenRecorderView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 33 | Ekrandan Al | [ScreenGrabView.swift](../Sources/MacPocketApp/ScreenGrabView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 34 | Ses Mikseri | [VolumeMixerView.swift](../Sources/MacPocketApp/VolumeMixerView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 35 | Ses Çıkışı | [AudioOutputView.swift](../Sources/MacPocketApp/AudioOutputView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 36 | Fare Kaydırma | [MouseScrollView.swift](../Sources/MacPocketApp/MouseScrollView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 37 | Metin Kısaltmaları | [SnippetsView.swift](../Sources/MacPocketApp/SnippetsView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 38 | Makrolar | [MacrosView.swift](../Sources/MacPocketApp/MacrosView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 39 | Hızlı İşlemler | [QuickActionsView.swift](../Sources/MacPocketApp/QuickActionsView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 40 | Ekran Parlaklığı | [DisplayBrightnessView.swift](../Sources/MacPocketApp/DisplayBrightnessView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 41 | Odak Oturumu | [FocusSessionView.swift](../Sources/MacPocketApp/FocusSessionView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 42 | Kapatma Koruması | [QuitGuardView.swift](../Sources/MacPocketApp/QuitGuardView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 43 | Pano Geçmişi | [ClipboardHistoryView.swift](../Sources/MacPocketApp/ClipboardHistoryView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 44 | Masa Düzenleri | [WorkspacesView.swift](../Sources/MacPocketApp/WorkspacesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 45 | Pencere Yerleşimi | [WindowLayoutView.swift](../Sources/MacPocketApp/WindowLayoutView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 46 | Pencere Geçişi | [WindowSwitcherView.swift](../Sources/MacPocketApp/WindowSwitcherView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 47 | Uygulama Kalıntıları | [ApplicationLeftoversView.swift](../Sources/MacPocketApp/ApplicationLeftoversView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 48 | Uygulama Güncelleme | [ApplicationsView.swift](../Sources/MacPocketApp/ApplicationsView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 49 | İndirilenler | [StorageView.swift](../Sources/MacPocketApp/StorageView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 50 | Yinelenen Dosyalar | [StorageView.swift](../Sources/MacPocketApp/StorageView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 51 | Büyük ve Eski Dosyalar | [StorageView.swift](../Sources/MacPocketApp/StorageView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 52 | Ekran Temizleme Modu | [ScreenCleaningView.swift](../Sources/MacPocketApp/ScreenCleaningView.swift) | Arayüz durumu düzeltildi | TR 960/1280; EN 960/1280 |
| 53 | Benzer Görseller | [SimilarImagesView.swift](../Sources/MacPocketApp/SimilarImagesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 54 | Sistem Gereksiz Dosyaları | [CleanupView.swift](../Sources/MacPocketApp/CleanupView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 55 | Time Machine Anlık Görüntüleri | [MacUtilitiesView.swift](../Sources/MacPocketApp/MacUtilitiesView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 56 | Çöp Kutuları | [CleanupView.swift](../Sources/MacPocketApp/CleanupView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |
| 57 | Tam Uygulama Kaldırma | [ApplicationsView.swift](../Sources/MacPocketApp/ApplicationsView.swift) | Yönlendirme ve mevcut durum dalları incelendi | TR 960/1280 |

## Çalıştırılan kontroller

- Türkçe: `.build/tool-ui-audit.json` — 56 ayrı katalog girişi × 2 genişlik = 112 sayfa açılışı, her açılışta gerçek native erişilebilirlik nesneleri bulundu.
- İngilizce/koyu: `.build/tool-ui-audit-en.json` — değişen 14 ekran × 2 genişlik + Uyanık Tut sheet’i × 2 = 30 kayıt. Araç araması, Görev Yöneticisi ve Başlangıç Öğeleri arama odağı iki genişlikte de doğrulandı. Uyanık tutma oturumu başlatılmadı.
- `swift test --filter 'ScreenRecording|AudioOutput|HardwareTools|NetworkTraffic|USBEject|LocalNetwork|Startup|MenuBar'` — 73 test; 0 hata, 1 isteğe bağlı disk imajı testi atlandı. Bu turdaki UI değişiklikleri fiziksel disk işlemi yapmadığından disk imajı kabul testi tekrar çalıştırılmadı.
- `scripts/check-localizations.sh` — 3.229 anahtar, 0 eksik İngilizce çeviri, 0 biçim uyuşmazlığı, 0 kullanılmayan çeviri.
- Uygulama paketlemesi ve derin/sıkı kod imzası doğrulandı. Sürüm/build numarası değiştirilmedi.


## Açık doğrulama kapsamı

Gerçek ekran/sistem sesi/mikrofon kaydı; izin reddi/onayı akışlarının tamamı; gerçek USB/Thunderbolt/çoklu monitör donanımı; dolu ağ haritasında klavye; VoiceOver ile uçtan uca kullanım; tüm ekranların açık/koyu tam görsel karşılaştırması bekliyor. Native ağaçtaki adsız düğme ve taşma sayıları sezgisel denetimdir; kaydırılan içerik ve sistem kontrolleri için elle incelenmelidir. Uygulamanın kendi NSView görüntüsünü önbelleklemesi katmanlı içeriği tam vermediğinden tam ekran görüntüsü kabul testi yerine kullanılmadı. Pil donanımıyla ilgili doğrulama yapılmadı.

## Sonraki derleme doğrulaması

Pratik Araçlar geliştirmesinde denetim yardımcısının `CGFloat` değerlerini metne dönüştürme hatası düzeltildi. Eski genel geometri kaydı için tam ölçüm doğrulanamadığından yatay taşma sonucu bu raporun kabul kanıtından çıkarıldı. Pratik Araçlar’ın kendi canlı raporunda ölçülen native öğe sayıları açıkça yer alır.


## Hava durumu kaynak sepeti — 9 Kasım 2026

Mevcut hava durumu paneline ve Menü Çubuğu ayarlarına etkin kaynak menüsü ve açılabilir Kaynak Sepeti eklendi. Anahtarsız kaynaklar, ayrı Open-Meteo modelleri ve ücretsiz hesap isteyen kaynaklar ayrıdır. Onay kutuları yalnız sepeti değiştirir; veri almak için etkin kaynağın seçilmesi gerekir. Koşul bağlantıları ve ücretsiz hesap kotaları görünürdür; API anahtarları SecureField ile girilir ve Anahtar Zinciri’nde tutulur.

Türkçe/açık ve İngilizce/koyu görünümde 14’er yerel kontrol geçti. 368 px menü paneli ve 640 px sepet görünümü; canlı tahmin, anahtar eksikliği, kaynak ekleme/çıkarma, GFS ekleme ve grupları açma sınandı. Yerel NSHostingController denetim penceresinin boyut değiştirmesi, sabit denetim alanı ve genişlik kabul kontrolleriyle düzeltildi. Model grubu sola hizalandı; koşul bağlantıları satır içi sunulur. Erişilebilirlik ağacı/eylemleri kontrol edildi; VoiceOver kabulü yapılmadı. Görüntü ve raporlar `.build/weather-basket/ui-{tr,en}/` altındadır.


## Hava durumu paneli yenilemesi — 9 Kasım 2026

- Ana görünüm tahmine odaklanır: Celsius birimi görünür büyük sıcaklık, koşul ve hissedilen sıcaklık; nem, rüzgâr ve basınç tek kompakt satır; en fazla 12 yaklaşan tahmin örneği; en fazla beş gün için ortak ölçekte düşük/yüksek sıcaklık çubukları. Sağlayıcının eksik örnekleri doldurulmaz. Örneklerden hesaplanan günlük aralıklar ayrıca belirtilir.
- Konum ve Kaynaklar görünümü panel içinde açılır, geri düğmesi tahmine döner. Kaynak seçimi ve yenileme alttadır. Anahtar isteyen etkin kaynak ayarlar açılınca ilk grupta ve ilk sırada yer alır.
- Açık görünümde kaybolan beyaz bulut katmanı palet renkleriyle görünür kılındı. İçerik yüksekliği, beş günlük satırlar kesilmeden görünecek şekilde düzenlendi; küçük ekranlarda kaydırma korunur.
- **Çalıştırılan:** hava durumu için 26 odaklı test, 0 hata, 1 açık API denemesinin isteğe bağlı atlaması. Türkçe/açık ve İngilizce/koyu görünümde 24’er yerel kontrol geçti: ayarlara gitme/geri dönme, kaynak ekleme/çıkarma, model grubu, anahtar eksikliği eylemi, anahtar grubunun otomatik açılması, boş konum, yükleme, kaynak hatası ve yalnız mevcut hava içeren yanıt. Anahtar Zinciri denetimi yalnız denetimin kendi ad alanını kullandı. Yerelleştirme kapısı 4.484 anahtarda 0 eksik ve 0 biçim uyuşmazlığıyla geçti.
- **Yöntem/sınır:** dış CLI ve REA host’unda AX izni yoktu. Denetim uygulamanın mevcut izniyle yalnız kendi AX sunucusunu başlattı; gerektiğinde yalnız kendi penceresine AppKit olayları gönderir. Deneme geometrisi Debug derlemesine aittir, sistem genelinde girdi göndermez. VoiceOver ve gerçek kullanıcı API anahtarlarıyla yeni bir kabul yapılmadı.
- Önceki görüntüler `.build/weather-ui/before-{tr,en}.png`; yeni görüntüler ve durumlar `.build/weather-basket/ui-{tr,en}/{popover,settings,missing-key,key-settings,no-location,loading,unavailable,current-only}.png`; rapor `.build/weather-ui/runtime.log` ve aynı UI klasörlerindeki `report.json` içindedir.


## Saatlik tahmin etkileşimi — 9 Kasım 2026

Saatlik Tahmin başlığındaki sağ ok eylemi olmayan bir Image idi. ScrollViewReader ile ileri/geri düğmeleri ve gerçek kaydırma geometrisine bağlı sınır durumları eklendi. Fare/trackpad kaydırması korunur. Saat kartları artık Button’dır; seçilince yalnız sağlayıcının gerçekten sunduğu tarih/saat ve Celsius sıcaklığı açılır, kapatma düğmesi seçimi temizler. Kaynak/veri değişimi ve hareketi azalt tercihi ele alınır.

Türkçe/açık ve İngilizce/koyu görünümde 28’er yerel kontrol geçti. Yeni kontroller sağ düğmenin ilk kartı gerçekten sola taşıdığını, sol düğmenin ilk konumu geri getirdiğini, karta gerçek pencere tıklamasıyla ayrıntı açıldığını ve kapatılabildiğini doğrular. Saat ayrıntısı görüntüleri `.build/weather-basket/ui-{tr,en}/hour-details.png`, günlük `.build/weather-hourly/runtime.log` içindedir. Yerelleştirme kapısı 4.488 anahtarda 0 eksik çeviri ve 0 biçim uyuşmazlığıyla geçti. VoiceOver kabulü yapılmadı.


## Saatlik tahmin ayrıntı sayfası — 9 Kasım 2026

Saat kartı artık sıcaklık satırı yerine ayrı bir ayrıntı sayfası açar. Üstte yerel tarih/saat, sıcaklık ve koşul; altında iki sütunda yalnız seçili kaynağın o saate ait ölçümleri vardır. Sayfa kaydırılır, kaynak altlığı sabit kalır ve geri düğmesi tahmine döner. Yağış miktarı, olasılığı ve şiddeti ayrı etiketlenir; toplamın dönemi gösterilir. Sağlayıcının sunmadığı alanlar gösterilmez. Yalnız sıcaklık varsa açıklama ve kaynak düzenleme eylemi sunulur.

Türkçe/açık ve İngilizce/koyu görünümde 31’er yerel kontrol geçti. Saat kartı tıklaması ve geri dönüş yanında gerçek Visual Crossing yanıtındaki yağış, nem ve rüzgâr alanlarının gösterilmesi; kontrollü eksik yanıtta değer uydurulmadan açıklama verilmesi sınandı. Tam kök test grubunda 1.506 test, 0 hata, 6 isteğe bağlı atlama; yedi anahtarsız kaynakta canlı saatlik ayrıntı doğrulaması; 4.518 yerelleştirme anahtarında 0 eksik çeviri ve biçim uyuşmazlığı. Ekran görüntüleri `.build/weather-basket/ui-{tr,en}/{hour-details,hour-no-details}.png`, son raporlar aynı klasörlerdeki `report.json` içindedir. İlk denemelerde pencerenin etkinlik kontrolü geçici olarak başarısız oldu; normal test süreci bitince TR, ardından ayrı EN çalıştırmasında bütün kontroller geçti. VoiceOver ve gerçek kullanıcı API anahtarlarıyla kabul yapılmadı.
