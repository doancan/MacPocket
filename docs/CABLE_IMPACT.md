# Kablo Etki Haritası

7 Kasım 2026 · MacPocket 0.1.5 (8) · macOS 27 / Apple Silicon.

**Araçlar → Kablo Etki Haritası**, “Bu kabloyu çekersem ne olur?” sorusuna seçilen aygıtın bilinen donanım ilişkileri ve o anda okunabilen kullanım bilgileriyle yanıt verir. Kablo çıkarmaz, diski ayırmaz, süreç sonlandırmaz veya ağ/ses/ekran ayarı değiştirmez.

## Uygulanan davranış

- Çıkarılabilir USB aygıtları ve uzak Thunderbolt switch’leri seçilebilir. Mac’e gömülü USB işlevleri ve Thunderbolt host switch’leri seçim dışındadır. USB 2/3 işlevleri geçerli, sıfır olmayan ortak `kUSBContainerID` bildirdiğinde birlikte değerlendirilir. Aynı ad veya model eşleştirme kanıtı değildir.
- IOService sağlayıcı/istemci ilişkilerinden disk, ağ, ekran, ses ve alt USB aygıtlarının etki kümesi çıkarılır. Çoklu ebeveynler ve döngüler sonlu ziyaret kümesiyle ele alınır. Harita olası etkileri gösterir; bir kaynağın her koşulda tamamen kopacağını iddia etmez.
- DiskArbitration/diskutil envanteriyle fiziksel harici diskler ve APFS birimleri ilişkilendirilir. Seçili bağlantıya ait ilk 8 diskin açık dosyaları mevcut USB Çıkarma servisiyle okunur; süreçler ve dosya adları gösterilir. Güvenli çıkarma için var olan araca geçiş sunulur; bu ekrandan çıkarma başlatılmaz.
- Ethernet arayüzleri, varsayılan IPv4/IPv6 ağ yolu ve görünür yerleşik TCP oturumları okunur. Oturumlar benzersiz yerel IP adresiyle ilişkilendirilir. Tüm arayüzlerin adres sahipliği hesaba katılır; aynı adres başka Ethernet, Wi-Fi veya VPN arayüzünde de varsa ilişki tahmin edilmez. `ssh`/`sshd` süreçleri SSH etiketi alır; yalnız port 22 kullanmak yeterli değildir.
- Harici ekranlar CoreGraphics/NSScreen üzerinden; harici kablolu ses aygıtları Core Audio üzerinden okunur. Varsayılan ekran, ses çıkışı, mikrofon ve okunabilen ses süreci kullanımları gösterilir. Ekran eşleştirmesinde aynı vendor/product/serial değerlerine sahip birden fazla ekran varsa registry sırasına göre seçim yapılmaz.
- Donanım ağacında gösterilemeyen kaynaklar ayrıca listelenir. Kullanıcı aynı kablodaki başka bir aygıtı veya kaynağı ekleyebilir. Bu etkiler **Senin eşleştirmen** etiketi taşır; otomatik kanıtla karıştırılmaz. Eşleştirmeler yalnız bu ekranın modelinde tutulur ve donanım değiştiğinde sıfırlanır.
- Ekran açıkken donanım değişiklikleri 5 saniyelik aralıkla gözlenir. Kullanım verileri Yenile ile güncellenir; donanım ve kullanım okumalarının zamanları ayrıdır. Seçim değiştirme, iptal, ekranı kapatma veya bağımlı aygıtın kaybolması gecikmiş sonucu geçersiz kılar.

## Veri ve güven sınırları

IOService ağacı fiziksel kabloların eksiksiz şeması değildir. Özellikle Apple Silicon ekran/ses dalları veya Thunderbolt PCI tünelleri USB aygıtının doğrudan altında görünmeyebilir. Böyle bir durumda “aynı dock modelidir” veya “aynı anda bağlıdır” gerekçesiyle otomatik ilişki kurulmaz.

TCP ilişkilendirmesi gerçek paket güzergâhını ölçmez. VPN, bridge, multipath ve ağ geçişinin sürekliliği bütünüyle doğrulanmaz. Dosya ve oturum listeleri bu kullanıcının okuyabildiği kapsamdır. Yazma önbelleği, güç dağıtımı, şarj, kaydedilmemiş belge içeriği ve tüm işlerin devam edebilmesi değerlendirilmez. “Kaynak bulunamadı” sonucu güvenle çıkarılabilir anlamına gelmez.

Ürün ekran/ses içeriği kaydetmez ve bu araç için yeni bir izin isteme akışı eklenmedi. Donanım ve oturum envanteri uzak bir servise gönderilmez. Tarama hataları eksik kapsam olarak gösterilir; başarılı bir boş sonuç gibi sunulmaz.

Birincil kaynaklar: Apple [I/O Registry açıklaması](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/IOKitFundamentals/TheRegistry/TheRegistry.html),
[IORegistryEntryGetParentEntry](https://developer.apple.com/documentation/iokit/1514454-ioregistryentrygetparententry),
[SCDynamicStore](https://developer.apple.com/documentation/systemconfiguration/scdynamicstore-gb2),
[USB ses kimlikleri](https://developer.apple.com/documentation/technotes/tn3190-usb-audio-device-design-considerations).
`USBPortType` için yerel SDK `IOUSBHostFamilyDefinitions.h` kullanıldı: `Internal = 2`; bu değer genel USB portu olarak yorumlanmadı.

## Doğrulama

Kaynak uygulaması, otomatik test ve canlı gözlem ayrı tutulur:

- Yeni 9 Core ve 6 App modeli testi: iç içe/çoklu ebeveyn/döngülü ağaç, USB container gruplama, yanlış ad eşleşmesi, IPv4/IPv6, çakışan adresler, dosya yolu sınırı, okuma hataları, iptal, eski sonuç, aygıt kaybı ve elle eşleştirme yaşam döngüsü.
- Kök `swift test`: 1.467 test, 0 hata; 4 isteğe bağlı disk/sistem ve 1 bağlı trackpad testi atlandı. Core 984, App 100, ağ politikası 6, AI köprüsü 22, SSH köprüsü 355.
- Yerelleştirme kapısı: Türkçe kaynak ve İngilizce; 0 eksik çeviri ve 0 biçim uyuşmazlığı.
- İmzalı Debug uygulamasında `scripts/audit-cable-impact.sh --skip-build`: Türkçe/açık ve İngilizce/koyu, her dilde 16 kontrol; gerçek salt okunur donanım envanteri, bu teste ait gerçek loopback TCP oturumu, kontrollü dock örneğinde dört kaynak türü, açık dosya/SSH verisinin ekrana bağlanması ve açıkça işaretlenen elle eşleştirme.
- 700/1060 pt içerik genişliklerinde native erişilebilirlik ağacı ve yalnız uygulamanın test penceresini içeren gerçek ScreenCaptureKit görüntüleri incelendi. Fixture ekran görüntüleri gerçek bir fiziksel dock’un kabul kanıtı değildir. QA görüntüsü alımı önceden verilmiş ekran izni varsa çalışır; izin istemez.

Yerel kanıtlar `.build/cable-impact/` altındadır: `all-tests.log`, `final-related-tests.log`, `localizations.log`, `debug-build.log`, `ui-{tr,en}/report.json` ve `ui-{700,1060}.png`. Kullanıcı dosya içerikleri ve gerçek kullanıcı ekran görüntüleri bu raporlara eklenmedi; UI örnekleri kontrollü veridir.

QA komutu Debug paket gerektirir. Son paket Release ise `--skip-build` kullanılmadan çalıştırılmalıdır; betik Release pakette normal uygulamayı yanlışlıkla açmak yerine durur.

**Yapılmayan kabul:** fiziksel dock/kablo çıkarma ve yeniden takma, gerçek disk yazımı sırasında kesinti, gerçek SSH oturumunun kopması, ağ failover, çoklu fiziksel dock/aynı model monitör matrisi ve tam VoiceOver/klavye kullanımı. Uzaktan çalışma bağlantısı veya kullanıcının donanımı bu testler için değiştirilmedi. Bu özellik için rakiplerde bulunmadığı veya tam donanım desteği iddiası yoktur.
