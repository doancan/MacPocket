# AI kota arayüzü düzeni — 6 Kasım 2026

## Uygulanan tasarım

Takip ekranının ana işi hesap kotalarını karşılaştırmaktır. Çoklu Claude hesabını ayırt etme ve Türkçe/İngilizce arayüz gereği korunarak üç yüzey düzenlendi:

- **Yüzen şerit:** Başlık çubuğu ve büyük kartlar yerine şeffaf native NSPanel üzerinde cam yüzey. Dikey genişlik 96 pt, yatay yükseklik 88 pt. Hesap adı ve sağlayıcı simgesi; oturum/haftalık için ayrı küçük göstergeler; sürükleme tutamacı, yön, ayar ve kapatma kontrolleri var. Fazla hesap kendi içinde kaydırılır.
- **Menü paneli:** Bölücülerle ayrılmış sıkı kota listesi. Yüzdeler, limit adları, çubuklar, sıfırlanma süreleri ve veri yaşı öne alındı. Limit yoksa yüzde üretilmez; güncel olmayan değer durum simgesi ve açıklaması taşır.
- **Ana pencere:** Genel Bakış / Hesaplar / Ayarlar. İlk görünüm hesap limitlerini gösterir; hesap adı/takip/kaynak yönetimi ve genel tercihler ayrı sekmelerdedir. Boş görünüm ilk hesabı eklemeye gider. Ekleme sheet’inde sağlayıcılar simgeli seçimlerdir; Claude klasörü bulma ve yol seçimi korunur.

Menü çubuğu sağlayıcı simgesi ve yüzde gösterir; aynı sağlayıcıdan birden çok hesap varsa kısa ad eklenir. Önizleme aynı çizimi kullanır. Template simgelerin kaynak ve lisansı `Packages/AIUsageKit/UPSTREAM.json` ve `LICENSE` içinde kaydedildi. Uygulamada `Licenses/AIUsageKit.txt` paketlenir. SSH simgesine dokunulmadı.

## Doğrulama

- `swift test --filter 'AIUsage|ClaudeProfileDiscovery|MenuBar'`: 22 AI/profil + 28 menü testi, 0 hata.
- `scripts/check-localizations.sh`: 4.130 anahtar, 0 eksik İngilizce, 0 biçim uyuşmazlığı, 0 kullanılmayan çeviri.
- `.build/ai-redesign-tr.json` ve `.build/ai-redesign-en.json`: 42’şer native kontrol. İki Claude, bir Codex ve bekleyen bir Grok hesabı sahte sağlayıcılardan geldi.
- Gerçek NSStatusItem çizimi, paketli simgeler, popover, SwiftUI hesap sahnesi; 620/800 pt genel bakış ve sekme geçişleri doğrulandı. Native press eylemleri sonrası Hesaplar’ın kaynak satırları ve Ayarlar’ın yenileme seçenekleri gözlendi; yalnız eylem API’sının bool dönüşüne dayanılmadı.
- Klasör bulma/seçim korunması, boş durum, kalan/kullanılan değişimi, iki şerit yönü ve boyutu, kapatınca polling’in durması kontrol edildi. Uygulamanın kendi pencereleri ScreenCaptureKit ile görüntülendi.
- Türkçe genel bakış, menü paneli, hesap ekleme, ayarlar, menü çubuğu ve iki şerit yönü; İngilizce/açık genel bakış ve yatay şerit görsel olarak incelendi. Görseller `.build/ai-redesign-{tr,en}-*.png` dosyalarındadır.
- Debug paketleme ve `codesign --verify --deep --strict` başarılı. Sürüm 0.1.4 / build 7 korundu.

## Kabul sınırları

Canlı hesap, gerçek Anahtar Zinciri izni veya bildirim teslimi denenmedi. VoiceOver, fiziksel sürükleme ve global klavye etkileşimlerinin tamamı kabul edilmiş sayılmaz. Genel testlerin tamamı ve Release bu görsel turda yeniden çalıştırılmadı; önceki rapordaki OCR/Vision hatasına başarı denmedi. Harici System Events pencere odak kontrolü Assistive Access izni olmadığı için sonuçlanmadı; uygulama içindeki native kontrollerden ayrı tutuldu.
