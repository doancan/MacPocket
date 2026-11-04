# Pratik Araçlar — uygulama ve doğrulama

5 Kasım 2026 · MacPocket 0.1.3 · pilsiz Mac Studio · SwiftUI/AppKit

## Kapsam

Sol menüde **Üretkenlik › Pratik Araçlar**; Araçlar kataloğunda aynı çalışma alanına kısayol. IT-Tools’un araç kategorileri fikir kaynağı olarak incelendi; Case Converter eklemesiyle paket aşağıdaki 11 yerel araçtan oluşur. Uygulama Foundation, CryptoKit, Security, Core Image ve mevcut Vision okuyucusuyla bağımsız olarak yazıldı. Ek paket, web görünümü veya uzaktaki dönüştürme hizmeti eklenmedi.

| Araç | Uygulanan davranış |
|---|---|
| JSON Düzenleyici | Sözdizimi kontrolü, iki boşlukla biçimleme ve küçültme. Sayı tokenları, anahtar sırası ve kaçışlar korunur; sondaki fazladan virgül reddedilir. Biçimlenmiş sonuç yaklaşık 4 MiB ile sınırlıdır. |
| Base64 Dönüştürücü | UTF-8 metin, standart/URL uyumlu alfabe, kodlama ve çözme. Geçersiz karakter, dolgu, kanonik olmayan son bitler ve ikili UTF-8 dışı veri için açıklama. |
| URL Kodlayıcı | RFC 3986 unreserved karakterleri dışındaki parametre değerleri yüzde kodlanır; çözme işleminde + korunur. Bozuk yüzde kaçışları reddedilir. |
| JWT İnceleyici | Üç parçalı token başlığı/içeriği ve sayısal exp/nbf/iat. Bildirilen zaman durumu, ayrı imza doğrulanmadı açıklaması. JWE şifre çözümü/imza doğrulaması kapsam dışıdır. |
| Hash Hesaplayıcı | UTF-8 metnin SHA-256/SHA-512 özeti; boş metin dahil. |
| UUID Üretici | 1–100 UUID v4; büyük/küçük harf seçimi. |
| Parola ve Token | 8–128 karakter; büyük/küçük harf, rakam ve sembol grupları. Security rastgeleliği ve yanlılık içermeyen indeks örneklemesi; seçilen her gruptan en az bir karakter. Sonuç varsayılan olarak maskeli, göster/gizle düğmesi var. |
| Unix Zaman Dönüştürücü | Saniye/milisaniye, iki yön, UTC/yerel sonuç, açık saat dilimli ISO 8601 ve Şimdi. Takvimde bulunmayan günler, normalleştirilen 24:00 gibi saatler ve geçersiz ofsetler reddedilir. |
| Metin Karşılaştırma | Satır bazında ekleme/silme/aynı satır; +/- ile renk dışındaki ipuçları. Metinler düzeyinde eski ve yeni içerik yeniden kurulabilir; metin başına 2.000 satır sınırı. |
| Harf Biçimleri (Case Converter) | 14 biçim: büyük/küçük harf, başlık, cümle, ters/dönüşümlü harf, camel/Pascal/snake/constant/kebab/train/dot/path. Açık Türkçe/İngilizce kuralları, satır başına dönüşüm, tüm biçimleri önizleme ve kopyalama. |
| QR Oluşturucu | Metin/bağlantı ve WPA/parolasız/gizli Wi-Fi. SSID/parola kaçışları; sessiz kenarlı, tam modül ölçekli siyah/beyaz PNG. 2.048 UTF-8 bayt sınırı. |

## Etkileşim ve veri

- Arama ve favori filtresi; kategori listesi, sonuçsuz arama için kurtarma eylemi. Favoriler ve son seçilen araç UserDefaults’ta tutulur.
- Araç taslakları/sonuçları yalnız süreç belleğinde kalır. Araç değiştirmek içeriği korur ve çalışma panelini başa alır. Temizle içeriği ve sonucu temizler.
- Panodan alma yalnız düğmeyle; kopyalama açık eylemdir. Kopyalanan geçici çıktılar `org.nspasteboard.TransientType` taşır; mevcut MacPocket pano geçmişi bu işareti arşivlemez. Kullanıcının açık Kaydet eylemi metin veya PNG dosyası üretir.
- Örnek Veri, uygun araca özel örnekler; ayrı oluşturma parametreleri; ilerleme/iptal, hata sonrası tekrar çalıştırma, boş çıktı açıklaması; parola göster/gizle.
- Dönüştürme işleri ana aktör dışında çalışır. Case Converter varsayılan olarak yazma durduktan 300 ms sonra önizler; diğer araçlar açık çalıştırma eylemiyle başlar. Eski/iptal edilmiş sonuçların yeni işi ezmesi nesil kimliğiyle engellenir. Case Converter girdi sınırı 64 KiB, diğer araçlar 256 KiB; aşırı JSON biçimleme ve fark işlemleri ayrıca sınırlıdır.
- Sistemin izleme yenile/duraklat/örnekleme kontrolleri bu sayfada gösterilmez. Mevcut renk seçme, QR okuma ve ağ/MAC ekranlarına bağlantı bulunur.

## Kaynaklar

- [Dönüştürme motoru ve katalog](../Sources/MacPocketCore/PracticalTools.swift)
- [Çalışma alanı, durum modeli ve arayüz](../Sources/MacPocketApp/PracticalToolsView.swift)
- [Çekirdek testleri](../Tests/MacPocketCoreTests/PracticalToolsTests.swift)
- [IT-Tools kategori envanteri](https://github.com/CorentinTh/it-tools/blob/main/src/tools/index.ts)
- [JWT zaman alanları — RFC 7519](https://www.rfc-editor.org/rfc/rfc7519.html)

## İlk paketin doğrulaması

- `swift test --filter 'PracticalToolsTests|AppPreferencesTests|MenuBarPreferencesTests'`: **37 test, 0 hata**. Yeni 12 test; sayı/anahtar/kaçış koruma ve JSON genişleme sınırı, iki Base64 alfabesi, bozuk yüzdeler, JWT sınır anı/sayısal zamanlar, SHA vektörleri, UUID v4, parola grup/uzunluk kuralları, takvim/ofset hataları, fark satırlarından iki metni yeniden kurma ve girdi sınırlarını kapsar.
- QR PNG’ler gerçek Core Image ile üretildi; Türkçe/emoji metin ve Wi-Fi payload’ı mevcut Vision okuyucusuyla geri çözüldü.
- İmzalı `/Applications/MacPocket.app` içinde **10 araç × 960/1280 px × Türkçe/açık ve İngilizce/koyu = 40 canlı sonuç**. Her örnek sonuç üretti; hata sayısı 0. Dışa taşma sezgisinde uyarı 0; her dilde 760 native erişilebilirlik çerçevesi ölçüldü.
- Her dilde 10 ek durum kontrolü geçti: Base64/URL çözme, tarih → Unix, Wi-Fi QR, hatalı JSON, hata sonrası başarılı sonuç, favori aç/kapat, temizle ve arama odağı. Deneme gerçek girdilere/favorilere yazmayan ayrı `PracticalWorkspace(defaults: nil)` kullandı. Raporlar `.build/practical-ui-tr.json` ve `.build/practical-ui-en.json` içindedir; sonuç metinleri/parolalar rapora yazılmaz.
- `scripts/check-localizations.sh`: **3.341 anahtar, 0 eksik İngilizce çeviri, 0 biçim uyuşmazlığı, 0 kullanılmayan çeviri**.
- Paketleme başarılı; derin/sıkı kod imzası ve kurulu ikilinin derlemeyle eşleşmesi doğrulandı. Sürüm/build değiştirilmedi; son başlatma normal tercihlerle Pratik Araçlar sayfasında yapıldı.

## Bekleyen kabul kontrolleri

Tam görsel ekran görüntüsü/kontrast karşılaştırması, VoiceOver ile uçtan uca kullanım, Kaydet panelinin fiziksel klavye/fareyle tamamlanması, telefon kamerasıyla Wi-Fi’ye katılma ve dış uygulamaya gerçek pano yapıştırma bu turda yapılmadı. Native çerçeve ölçümü ve süreç içi model kontrolleri bu kabul testlerinin yerine sayılmaz. İlk paket, IT-Tools’un tüm araçlarını kapsamaz.

## Case Converter genişletmesi — 5 Kasım 2026

- **Uygulanan:** 14 çıktı aynı işlemde üretilir. Sonuç biçimi değiştirilince hazır çıktı seçilir; yeniden hesaplama yapılmaz. Kartlar en fazla 240 karakter/üç satır gösterir; kopyalama tam çıktıyı alır. Tek çıktı, tüm çıktılar ve seçilen sonucu girdi yapma açık eylemlerdir. Karakter sayısı grapheme, sözcük sayısı Foundation sözcük sınırları, satır sayısı boş/son satır dahil hesaplanır.
- **Kurallar:** Türkçe `tr_TR` ve İngilizce `en_US_POSIX` açık seçilir. NFC normalleştirmesi uygulanır. Metin biçimleri yerleşimi/noktalama/emojileri korur; kod biçimleri harf/rakam olmayan karakterleri ayraç sayar. Cümle biçimi noktalama temellidir; dilbilimsel cümle çözümlemesi değildir. Ondalık nokta yeni cümle başlatmaz. Kod çıktısının her programlama dilinde geçerli tanımlayıcı olduğu iddia edilmez.
- **Seçenekler:** Satır satır/tek parça, boş satırları koru, Latin-ASCII sadeleştirme, HTTPServer benzeri kısaltmaları ayır, rakamları ayır, tamamen büyük yazılmış sözcükleri koru, değişken biçimlerinde sayıyla başlayan ada `_` ekle. camelCase ilk sözcüğü küçük harfe çevirir; kısaltma koruması sonraki sözcüklerde uygulanır. Latin sadeleştirme harf dönüşümünden sonra yapılır.
- **Sınırlar:** Girdi 64 KiB, birleşik önizlemeler 4 MiB ile sınırlı; iptal/yeni nesil koruması bulunur. Satır sonları CRLF/CR/LF ve Unicode satır ayraçlarıyla korunur. Canlı önizleme kapatılabilir. Taslak/sonuçlar bu süreçte kalır.
- **Kaynak:** [Motor](../Sources/MacPocketCore/CaseConverter.swift), [12 yeni çekirdek testi](../Tests/MacPocketCoreTests/CaseConverterTests.swift), [Unicode özel harf kuralları](https://www.unicode.org/Public/UCD/latest/ucd/SpecialCasing.txt).

### Genişletmenin doğrulaması

- `swift test --filter 'CaseConverterTests|PracticalToolsTests|AppPreferencesTests|MenuBarPreferencesTests'`: **49 test, 0 hata**. 12 yeni test, 14 biçimi; Türkçe/İngilizce ayrımını, CRLF/CR/LF ve boş satırları, İ/ı/ß/œ ve birleşik aksanları, emoji grapheme’lerini, cümle/ondalık noktasını, kısaltma/rakam seçeneklerini ve 1.000 satırlık toplu önizlemeyi kapsar.
- Kurulu imzalı uygulamada **11 araç × 960/1280 px × Türkçe/açık ve İngilizce/koyu = 44 canlı sonuç**, hepsinde başarı. Dil başına 840 native çerçeve ölçümü, yatay taşma sezgisinde 0 uyarı. Bunlar tam görsel veya VoiceOver kabulü değildir; yukarıdaki kabul sınırları sürer.
- Her dilde **18 durum kontrolü** geçti; önceki 10 kontrole ek olarak 14 önizleme, hesaplamasız biçim seçimi, Türkçe+ASCII sonucu, otomatik önizleme, hızlı düzenlemede son girdinin kazanması, otomatik kapalıyken bekleme, manuel çalıştırma ve temizlemenin bekleyen önizlemeyi iptal etmesi doğrulandı. Ayrı bellek çalışma alanı kullanıldı; gerçek pano/kaydet eylemleri çalıştırılmadı. Raporlar `.build/case-ui-tr.json` ve `.build/case-ui-en.json`.
- `scripts/check-localizations.sh`: **3.385 anahtar, 0 eksik İngilizce çeviri, 0 biçim uyuşmazlığı, 0 kullanılmayan çeviri**.
- Başarılı yeni derlemeden paket oluşturuldu; derin/sıkı imza ve kurulu ikiliyle SHA-256 eşleşmesi doğrulandı. `/Applications/MacPocket.app` normal tercihlerle Case Converter sayfasında çalışıyor. Sürüm 0.1.3 ve build 6 korundu.
