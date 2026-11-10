# AI kota görünümü — 10 Kasım 2026

Önceki düzenin hesap/oturum kaynağı ayrımı, gerçek limit verileri ve üç yüzeyi korundu. Bu tur hesap ayarlarını veya sağlayıcı sorgularını değiştirmez.

- Genel bakış ve menü panelinde hesap başlığındaki tekrar yüzde kaldırıldı. Oturum/haftalık yüzdeler büyütülüp ait oldukları limit başlığının yanına alındı. Menü panelindeki iki sütun daha çok hesabı aynı anda gösterir.
- Tek limit tam genişliktedir. Uzun modele özel haftalık limitler de tam genişlikte ayrı satırda kalır; 320 pt görünümde model adı dar bir sütunda kelime kelime bölünmez. Hesap adı ortadan kısaltılır, tam adı yardım metninde bulunur.
- Kota eşiği uyarıları metin ve simge taşır: “Kota azalıyor”, “Az kota kaldı”, “Kota doldu”. Hesap geneli uyarısı önceki headlineLimit tanımını kullanır; yalnız tek modele uygulanan bir limit tüm hesabın kotası gibi gösterilmez.
- Yenilenme, açık bir etiketle ve kısa yerel birimlerle gösterilir: “Yenilenme: 59 dk.”. Geçmiş tarih “Sıfırlanma bekleniyor” olarak kalır. Son bilinen veriler ve eksik/giriş gerektiren veriler birbirinden ayrıdır.
- Çubuklarda düz renk, daha belirgin iz ve açık tema için koyu renk karşılıkları kullanılır. Yüzde/metin rengi okunur kalır; eşik anlamı yalnız renge bırakılmaz. Ek animasyon veya bağımlılık eklenmedi.

## Doğrulama

`swift test --filter 'AIUsage|ClaudeProfileDiscovery|MenuBar'`: 28 Core, 3 App, 22 AI/profil olmak üzere **53 test, 0 hata**. Sonraki değişiklikler renk sabiti ve DEBUG doğrulama beklemesidir; bunların ardından normal derleme ve native görsel kabulü çalıştırıldı. Tam 1.575 testlik kök grup bu görsel turda yeniden çalıştırılmadı.

`scripts/check-localizations.sh`: **4.524 anahtar, 0 eksik İngilizce/biçim uyuşmazlığı**. Release paketi sıkı imza doğrulamasını geçti ve normal uygulama yeniden açıldı. Sürüm/build **0.1.6 / 9** korundu.

İzole `.AIUsageAudit` paketi ve sahte sağlayıcılar kullanıldı; gerçek credential, kota isteği veya CLI girişi yoktur. Genel bakış 620/800 pt, menü paneli, boş durum, hesap/ayar sekmeleri, hesap ekleme ve iki yüzen panel yönü denetlendi. Ek altı 320×360 pt görünüm kritik, dolu/kullanılan, eski veri, giriş gerekli, yükleme ve uzun model adı durumlarını çizer. Profil keşfinin placeholder metnini hazır satır sanan test, gerçek press eylemini en fazla bir saniye bekleyerek doğrular; seçilen yol ve yeniden arama sonrası korunması ayrıca kontrol edilir.

Görüntüler ve raporlar `.build/ai-quota-polish/{tr,en}-final*` dosyalarındadır. Önceki `tr.json`, ilk yerleşimin ve başlangıçta erişilebilirlik ağacı henüz hazır olmayan kontrollerin başarısız denemesidir; nihai kabul olarak kullanılmaz. Geçici test paketi ilk paketlemede Sparkle rpath'i eksik olduğu için açılamadı; yalnız bu deneme paketinin rpath'i tamamlandı. Normal Release paketleyicisi bu yolu zaten ekler.

Erişilebilirlik etiketleri ve native press eylemleri denetlendi; VoiceOver, fiziksel klavye/sürükleme veya 200% metin büyütme ile uçtan uca kabul yapılmış sayılmaz. Açık tema kontrastı ölçümü yalnız örneklenen genel bakış renk çiftleri içindir; tüm uygulama için erişilebilirlik sertifikası iddiası yoktur. [Apple süre biçimleme belgesi](https://developer.apple.com/documentation/foundation/datecomponentsformatter/maximumunitcount) zaman birimi sayısını sınırlama davranışını açıklar.

Nihai Türkçe/koyu ve İngilizce/açık raporlarında **48'er kontrolün tamamı geçti** (önceki 42 kontrol + altı durum görüntüsü). Native ağaçtan hesap adları ve değerler okundu; sekme ve profil press eylemlerinden sonra beklenen durumun oluşması kontrol edildi. Test paketi kapatıldı.

Açık genel bakış görüntüsünde sRGB'ye dönüştürülmüş piksel çiftleri: uyarı çubuğu/iz **4,32:1**, haftalık çubuk/iz **4,17:1**, sağlıklı çubuk/iz **4,38:1**. Yenilenme metni **#656565 / #FFFFFF**, **5,84:1**. Koyu tema, uzun model ve eski veri görüntüleri ayrıca gözle incelendi. Ölçüm betiği/günlüğü `.build/ai-quota-polish/contrast.{swift,log}` içindedir.
