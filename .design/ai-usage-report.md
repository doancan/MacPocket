# AI kotaları ve çoklu hesap doğrulaması — 6 Kasım 2026

## Uygulanan davranış

MacPocket 0.1.4 / build 7 üzerinde Claude, Codex/ChatGPT ve Grok CLI kota modülü eklendi. Sürüm/build değiştirilmedi. AI Dosyaları / AI Clutter eklenmedi.

Her hesabın UUID’sine bağlı ayrı sağlayıcı örneği, sorgu/bekleme zamanı, kota önbelleği ve bildirim durumu vardır. İki Claude hesabı birbirinin verisini veya bekleme süresini değiştirmez. Yeni Claude hesabı ayrı `CLAUDE_CONFIG_DIR` kullanır; mevcut varsayılan oturum korunur. Giriş komutu, login shell yapılandırmasından sonra profil ortamını uygular ve klasör yolunu shell ifadesi olarak çalıştırmaz.

Claude klasör seçimi açılışta yerel adayları bulur. Varsayılan oturum, bulunan profil, yol yapıştırma ve gizli klasörleri gösteren native seçici kullanılabilir. Arama tüm diske yayılmaz ve credential içeriği açmaz. Klasörler tekilleştirilir ve sonuç sayısı sınırlıdır. Özel profil, varsayılan hesabın Anahtar Zinciri kaydına kendiliğinden geçmez.

## Bağımlılık ve veri

- Kota kütüphanesi `Packages/AIUsageKit` içinde yerel paket olarak bulunur. Telif/izin metni `LICENSE`, üçüncü taraf kaynak ve yerel uyarlamalar `UPSTREAM.json` içindedir.
- Harici bir uygulamaya veya araştırma klasörüne çalışma zamanı bağımlılığı yoktur. MacPocket’ın kullanmadığı bağımsız uygulama güncelleyicisi ve ona ait test/fixture’lar çıkarıldı. MacPocket’ın Sparkle güncelleme sistemi korunur.
- Tercihler kaynak konumlarını; 0600 izinli önbellek kota verileri ve bildirim durumunu tutar. Token’lar kopyalanmaz. Profilin credential kaydı değişince önbellek reddedilir.
- HTTP yalnız sağlayıcıların üç sabit HTTPS kota adresine gider. Yönlendirme, çerez, credential storage ve kalıcı HTTP önbelleği kapalıdır. Yanıt boyutu/süre sınırları ve iptal kontrolü vardır.
- Otomatik ücretli model istemi veya CLI kurulumu başlatılmaz. Uygulama içindeki kullanıcı metinleri Türkçe ve İngilizcedir; sağlayıcıdan gelen ham hata/limit etiketleri gösterilmez.

## Kontroller

- AI/profil tarafında 22, menü çubuğunda 28 test başarılı. Hesap ayrılığı, HTTP 429 beklemesi, ayrı bildirimler, geç yanıtların reddi, tercih göçü, cache kaynak eşleşmesi, güvenli giriş komutu ve klasör keşfi kapsamda.
- `swift test --package-path Packages/AIUsageKit`: 420 test, 3 isteğe bağlı gerçek-credential testi atlandı, 0 hata. Güncelleyicinin çıkarılmasından sonra paket temiz bir scratch dizininde de doğrulandı.
- `scripts/check-localizations.sh`: 4.130 anahtar, 0 eksik İngilizce, 0 biçim uyuşmazlığı, 0 kullanılmayan çeviri.
- Debug paketleme ve derin/sıkı imza doğrulaması başarılı. Geliştirme sırasında Release de derlendi; son görsel/paket adı temizliği sonrası Release yeniden çalıştırılmış sayılmaz.
- `.build/ai-redesign-tr.json` ve `.build/ai-redesign-en.json`: ayrı deneme paketinde Türkçe/koyu ve İngilizce/açık olmak üzere 42’şer native kontrol başarılı. Sahte sağlayıcılar ve throwaway home kullanıldı; gerçek hesap/token okunmadı.

## Sınırlar

Genel test çalıştırmasında Core’da 739 test, 4 atlama ve değiştirilmeyen `ScreenTextVisionTests.testRecognizesTurkishTextOnDevice` testinde tek Apple Vision `e5rt_execution_stream_operation_create_precompiled_compute_operation_with_options` (13) hatası görüldü. Tek başına tekrarda aynı hata sürdü. SSH tarafında 355 test başarılıydı. Tüm proje testlerine başarı iddiası yoktur.

Canlı Claude/Codex/Grok oturumu, gerçek Anahtar Zinciri izinleri, bildirim teslimi ve VoiceOver ile uçtan uca kabul yapılmadı. Kota uç noktaları belgelenmemiştir; sağlayıcı değişiklikleri erişimi etkileyebilir. Başka ürünlerle tam özellik eşdeğerliği iddiası yoktur.
