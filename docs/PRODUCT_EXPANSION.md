# Menü çubuğu, bağımsız güncellemeler ve internet kontrolü

7 Kasım 2026 · MacPocket 0.1.5 (8) · macOS 27 / Mac Studio.
Üç araç **Araçlar** kataloğundan açılır. Türkçe kaynak metinleri ve İngilizce çevirileri vardır.

## Menü Çubuğu Düzenleyici

- Uygulamaları gizli gruba ekleme, ok düğmesiyle gizleme/gösterme, sağ tıkla aranabilir simge listesi ve simgeyi açma.
- Aynı bundle kimliğinin simgeleri birlikte yönetilir. Apple sistem simgeleri ve MacPocket görünür tutulur. Sıralama macOS’un ⌘-sürükle davranışıdır.
- Listeleme/açma Erişilebilirlik izni ister. Özellik başlangıçta kapalıdır; kapatılması veya modülün durdurulması görünürlük kısıtlamasını bırakır.
- macOS 27’de eski geniş NSStatusItem ayırıcı yöntemi canlı testte çalışmadı. Uygulama `MenuBarClientCore` içindeki `MBAssessmentModeAssertion` arayüzünü çalışma anında çözümler; sınıf veya selector yoksa özelliği kullanılamaz gösterir. Bu özel Apple arayüzünün sonraki macOS sürümlerindeki uyumu garanti edilmez.
- Gizleme açıkken Bildirim Merkezi gibi bazı sistem panelleri etkilenebilir; açmadan önce simgeler gösterilmelidir. Bu sınır araçta da yazılıdır.

Arayüz araştırmasının birincil kaynakları: [MenuBarHider](https://github.com/happy666End/MenuBarHider),
[baaar](https://github.com/bylaaabs/baaar), [Ice macOS 27 bildirimi](https://github.com/jordanbaird/Ice/issues/992).
REA yalnız sahip olunan kısa ömürlü araştırma sürecindeki Objective-C yöntemlerini okumak için kullanıldı.
Çalışan referans uygulamalara müdahale edilmedi.

## Güncelleme Merkezi

- Yerel envanterde Homebrew ve Setapp dışındaki uygulamaları gösterir. macOS sistem uygulamaları ve MacPocket’ın kendi güncelleyicisi ayrı tutulur.
- Var olan Sparkle ve isteğe bağlı App Store tarayıcılarını kullanır. Kullanıcı uygulama başına `sahibi/depo` biçiminde herkese açık GitHub kaynağı bağlayabilir.
- Sayfayı açmak üretici sorgusu başlatmaz. Denetim düğmeyle başlar; iptal, kaynak hataları, denetlenen uygulama sayısı ve son kontrol zamanı gösterilir.
- Taslaklar ve varsayılan olarak ön sürümler dışarıda kalır. Sayısal sürümler Sparkle karşılaştırıcısıyla kıyaslanır; bilinmeyen kurulu sürüm güncel sayılmaz. GitHub sonuçları aynı depodaki HTTPS sürüm sayfalarıyla sınırlandırılır.
- Kurulum uygulamanın kendi güncelleyicisi, App Store veya sürüm sayfasında devam eder. Sessiz toplu kurulum, özel GitHub deposu kimlik doğrulaması ve tüm üreticilere otomatik kaynak bulma uygulanmadı. Kaynaksız veya hata veren uygulamalar güncel kabul edilmez.

## İnternet Kontrolü

- Gerçek `NEFilterDataProvider` sistem uzantısı ve host arayüzü eklendi. İmzalı uygulama kimliği + geliştirici takımıyla izin/engel kuralları tutulur; ad-hoc imzalarda kod hash’i eşleşir.
- Kurallar yalnız **yeni bağlantılara** uygulanır. Açık bağlantıları sonlandırma, alan adı kuralı, TLS içeriğini okuma veya başka imza kimlikleriyle çalışan yardımcı süreçleri otomatik gruplama uygulanmadı. Kimliği belirlenemeyen ve kuralı olmayan süreçlere izin verilir.
- Kural düzenlemek ve filtreye uygulamak ayrı adımlardır. Kayıtlı kurallar okunamıyorsa veri korunur ve açık sıfırlama gerekir. Yapılandırmanın kayıtlı olması ile uzantının sistemde etkin olması ayrı izlenir.
- Görünür TCP/UDP bağlantıları `lsof` ile okunur; liste tüm sistem süreçlerinin eksiksiz dökümü değildir.
- Sayfa açılması filtreyi yüklemez veya etkinleştirmez. **Bu geliştirme turunda sistem filtresi etkinleştirilmedi ve gerçek ağ engelleme kabulü yapılmadı.** Uzaktan çalışma bağlantısı engelleme testine konu edilmedi.

Apple gereksinimleri: [Network Extension entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.networking.networkextension),
[ağ filtreleme örneği](https://developer.apple.com/documentation/networkextension/filtering-network-traffic).
Dağıtımda uygun Developer ID profilleri, notarization, uygulamanın uygun konumdan kurulması ve macOS uzantı/ağ filtresi onayı gerekir.

### Filtreli paket

Bu Mac’te mevcut Apple Developer hesabıyla iki gerçek Developer ID profili alındı; ana uygulama ve uzantı doğru takım, tam bundle kimlikleri ve `content-filter-provider-systemextension` yetkisiyle imzalandı. Profiller `.build/network-profiles/` altında özel derleme girdisidir; Git’e eklenmez.

```sh
MACPOCKET_FILTER_HOST_PROFILE="$PWD/.build/network-profiles/host.provisionprofile" \
MACPOCKET_FILTER_PROVIDER_PROFILE="$PWD/.build/network-profiles/provider.provisionprofile" \
./scripts/build-app.sh release
```

İki profil birlikte sağlanmalıdır. Süre, takım, bundle kimliği ve yetki kontrol edilir. Profil verilmezse standart paket uzantısız üretilir ve araç bunu açıkça bildirir. Notarization için mevcut derleyicinin `MACPOCKET_NOTARY_PROFILE` seçeneği kullanılır; imza kontrolü notarization veya sistem onayının yerine geçmez.

## Doğrulama

Kaynak uygulaması, otomatik test ve canlı kabul aşağıda ayrı tutulur. Tam rakip ürün eşdeğerliği iddiası yoktur.

- `swift test`: 1.452 test, 0 hata; 4 isteğe bağlı disk/sistem ve 1 bağlı trackpad testi atlandı. Dağılım: Core 975, App 94, ağ politikası 6, AI köprüsü 22, SSH köprüsü 355.
- `scripts/check-localizations.sh`: 4.318 anahtar, 0 eksik İngilizce çeviri, 0 biçim uyuşmazlığı; kısayol paketinde 0 eksik Türkçe çeviri.
- İmzalı Debug uygulamasının normal AppKit çalışma döngüsünde ayrı, sahip olunan fixture uygulamasıyla gerçek MenuBarAgent gizleme/gösterme ve AXPress teslimi denetlenir. ScreenCaptureKit yalnız menü çubuğundaki test işaretini bellekte sayar; kullanıcı ekran görüntüleri kaydedilmez. AX’in önbellekte kalan geometrisi gizleme kanıtı sayılmaz.
- `scripts/audit-product-expansion.sh --skip-build`: 13 kontrol; filtreyi etkinleştirmez. Canlı GitHub sorgusu herkese açık `sparkle-project/Sparkle` sürümlerini çözümler. Yerel rapor `.build/product-expansion-audit/report.json` içindedir.
- Son başarılı canlı ölçümde test işareti görünürken 450, gizliyken 0, geri gösterilince 480 piksel eşleşmesi verdi. Kontrol düğmesi erişilebilir kaldı ve sahip olunan fixture kapatıldı.
- Son Debug/Release derleme ve katı kod imzası kontrolleri yerel `.build/expansion-*-build.log` dosyalarındadır. Sürüm/build numarası değişmedi; yeni GitHub Release oluşturulmadı.

Bekleyen kabul: notarization ve macOS kurulum/onayından sonra sahip olunan iki ağ istemcisiyle gerçek allow/deny, kuralların güncellenmesi, filtreyi kapatma ve yeniden başlatma davranışı. Yeni üç ekranın tam VoiceOver, açık/koyu ve fiziksel etkileşim matrisi ayrıca doğrulanmadı.
