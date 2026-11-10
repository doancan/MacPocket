# Native macOS deneyimi — 0.3.0

Kullanıcının kalite hedefi Apple uygulamaları düzeyinde, Liquid Glass destekli
bir macOS yardımcı uygulamasıdır. Bu belge uygulanan platform temelini kaydeder;
bütün ürün modüllerinin veya nihai kalite kabulünün tamamlandığı anlamına gelmez.

## Pencere ve kontroller

- SwiftUI NavigationSplitView/List ile native kenar çubuğu; standart pencere
  kontrolleri, yeniden boyutlandırma, kenar çubuğunu gizleme ve toolbar.
- Özelleştirilebilir native toolbar: yenileme, duraklatma, örnekleme aralığı,
  Ayarlar. Varsayılan pencere menüleri ve klavye komutları.
- macOS 26 ve üzerinde gerçek glassEffect; native gezinme/kontrol materyalleri.
  macOS 14–25 için sistem materyali geri dönüşü. Veri tablosu ve araç kutuları
  içerik yüzeyidir; üzerine gereksiz cam efekti uygulanmaz.
- Sistem renklerine bağlı içerik, AppKit tablosu ve açık/koyu/sistem teması.
  Özel cam yüzey saydamlığı azalt tercihini takip eder. Native bileşenlerin
  erişilebilirlik davranışı sistemden gelir; VoiceOver kabulü henüz yapılmadı.
- App Store varlıklarından bağımsız, vektör kaynaklı MacPocket uygulama ikonu.

## Menü çubuğu ve pencere yaşam döngüsü

NSStatusItem + NSPopover + NSHostingController kullanılır. Menü çubuğu nesnesi
ana pencerenin ömründen bağımsızdır. CPU, fiziksel RAM, boş disk alanı ve pil
varsa seviye gerçek ölçümlerden gelir. Örnekleme, uyanık tutma, ana pencereye
ve Ayarlar'a geçiş ile çıkış eylemleri bulunur.

Pencerenin kapatılması uygulamayı sonlandırmaz. Süreç listesi yalnız Görev Yöneticisi açıkken periyodik örneklenir.
Pencere kapalıyken özet izleme sürer. Tam çıkış Cmd+Q veya menüdeki Çık iledir.
Menü çubuğu simgesi ve CPU yazısı Genel ayarlarından seçilir.

## Ayarlar ve otomatik başlatma

Native Settings sahnesi; Genel, Görünüm ve İzleme sekmeleriyle açılır. Tema,
menü çubuğu tercihleri, örnekleme aralığı ve tablo sütunları saklanır. Uygulama Genel Bakış ile açılır.

Otomatik başlatma SMAppService.mainApp ile kaydedilir. Durum kaynağı macOS'tur;
UserDefaults'ta bir başarılı-kayıt taklidi tutulmaz. Etkin, kayıtlı değil,
onay gerekiyor, bulunamadı ve bilinmeyen durumlar ayrıdır. Sistem onayı
gerekiyorsa Giriş Öğeleri ayarına gitme eylemi gösterilir. Hata açık gösterilir.
Buradaki giriş, macOS kullanıcı oturumu açıldığında uygulamanın başlatılmasıdır.

## Kısayollar

| Kısayol | Eylem |
| --- | --- |
| Cmd+, | Ayarlar |
| Cmd+0 | Ana pencereyi aç/öne getir |
| Cmd+1…7 | Genel Bakış, Sistem İzleme, Güç Merkezi, Temizlik, Disk Analizi, Uygulamalar, Tools |
| Shift+Cmd+T | Tools → Görev Yöneticisi |
| Cmd+[ | Açık araçtan Tools listesine dön |
| Cmd+F | Etkin araçta veya dosya/uygulama listesinde arama |
| Cmd+R | Şimdi yenile |
| Shift+Cmd+P | İzlemeyi duraklat/sürdür |
| Shift+Cmd+M | Menü çubuğu hızlı bakışını aç |
| Cmd+W | Pencereyi kapat |
| Cmd+Q | Uygulamadan çık |

## Canlı kontrol — Mac Studio, 28 Ekim 2026

- Release derlemesi ve paket imza doğrulaması başarılı; 32 test geçti.
- Native Ayarlar Cmd+, ile açıldı. Açık ve koyu tema ana pencere/tabloya uygulandı;
  görünüm yeniden açılışta korundu. Son durumda koyu tema seçili.
- SMAppService kaydı uygulama içinden etkinleştirildi; sistem durumu enabled
  olarak okundu. Ardından kaldırıldı ve notRegistered okundu. Kullanıcının önceki
  kapalı tercihi korundu. Gerçek oturum kapatma/açma testi yapılmadı.
- Menü çubuğu gizleme/gösterme ayarı ve bağlı kontrol durumu doğrulandı.
- Gerçek status-item popover'ı Shift+Cmd+M ile açıldı; ölçümler ve zaman güncellendi.
- Popover üzerinden uyanık tutma başlatıldı. pmset'te yalnız MacPocket'a ait
  assertion görüldü; durdurulduğunda bu kayıt kalktı.
- Popover'dan Ayarlar açıldı. Ana pencere kapatıldı; popover açıkken güncel ölçüm
  devam etti ve MacPocket'ı Aç ile aynı native ana pencere yeniden açıldı.
- Cmd+5, Cmd+F ve Shift+Cmd+P arayüzde doğrulandı.
- İlk geliştirme açılışındaki MenuBarExtra/UserDefaults geri bildirim döngüsü,
  NSStatusItem sahipliğinin açıkça yönetilmesiyle giderildi. Tablo sadece veri veya
  sütun yapısı değiştiğinde yeniden yüklenir. Sorunlu test süreçleri kapatıldı.

Bu sürüm ad-hoc imzalı geliştirme paketidir. Developer ID/notarization, eski
macOS sürümleri, VoiceOver ve MacBook donanım kabulü ayrıca tamamlanacaktır.
0.3.0’da dosya/uygulama işlem servisleri ve izin durumunu izleyen pencere geçişi
eklendi. Gelişmiş şarj denetimleri tamamlanmadı. [Güncel kapsam ve testler](NATIVE_BUILD.md).

## Gece modu

Ekran Parlaklığı → Zaman çizelgesi → Güneşe göre. f.lux ile eşdeğerlik iddiası yoktur.

Uygulanan (statik): gün doğumu/batımı cihaz üzerinde NOAA formülüyle hesaplanır;
konum Konum Servisleri'nden ya da şehir listesinden gelir. Akşam geçişi gün
batımının ortasında 20/60/120 dk, sabah 30 dk sürer. Her ekran kendi gündüz
parlaklığına göre kısılır (varsayılan %60) ve renk 3400 K'e ısınır. Renk MacPocket
gama tablosuyla ya da macOS Night Shift ile verilir; Night Shift'in önceki durumu
diskte saklanır, çıkışta veya çökme sonrası açılışta geri yazılır. Bir saatliğine
kapatma, seçili uygulamalar ve tam ekran video istisnaları; gama okuması tutmayan
ekranda ekran başına uyarı.

### Canlı kontrol — Mac Studio, 2 Kasım 2026

Dahili ekransız Mac Studio, iki harici DDC ekran (MateView, LG HDR 4K), macOS 27.
Saat yalnız `MacPocket.night.debugNow` ile taklit edildi; konum İstanbul (şehir
listesinden), gün batımı 17:58. Gama tabloları ayrı bir süreçten
`CGGetDisplayTransferByTable` ile okundu. Ekran görüntüsü gamayı içermediği için
sıcaklık gözle değil tablo okumasıyla doğrulandı.

- Gündüz: tablolar nötr, iki ekran da gündüz parlaklığında (%85).
- Gün batımı ortası (17:59): iki ekranda %68 (= %85 × 0,8), kanal çarpanları
  1 / 0,890 / 0,801 (4950 K). Durum rozeti "Geçişte".
- Gece (22:00): %51 (= %85 × 0,6), çarpanlar 1 / 0,744 / 0,530 (3400 K).
  LG HDR 4K dahil iki ekranda tablo yazıldığı gibi okundu; uyarı görünmedi.
- Bir saatliğine kapat: renk ~2,2 sn'de nötre, parlaklık gündüz düzeyine döndü;
  Yeniden aç ile gece değerleri geri geldi.
- Night Shift yöntemi: Night Shift açık, güç 0,674 (= (6500−3400)/4600), gama nötr.
  MacPocket yöntemine dönüşte ve çıkışta önceki durum (kapalı, 0,5, takvim yok)
  aynen geri geldi. Takvimli bir durumla (güç 0,3, gün batımından doğumuna)
  `kill -9` sonrası yeniden açılışta önceki durum geri yazıldı.
- Çıkış: iki yöntemde de tablolar nötr. Gündüz yeniden açılışta DDC parlaklığı
  gündüz düzeyine (%85) döndü.
- Türkçe ve İngilizce arayüz açık temada kontrol edildi.

Doğrulanmayanlar: dahili ekran ve MacBook'lar (yazılım kısma/pil), yazılım
kısmalı (DDC'siz) ekranda gama birleşimi, HDR açıkken gamanın tutmadığı bir ekranda
uyarı, tarayıcıların tam ekran videosu (oynatma yardımcı süreçte olduğu için
kaçırılabilir), uygulama istisnası, menü çubuğu hızlı menüsünden kapatma, konum
izni hiç verilmeden şehirle çalışma (izin istemi testte yanıtlandı) ve gerçek gün
batımının saat taklidi olmadan izlenmesi.

## Monitör hoparlörü (ses tuşları)

Araçlar → Ses Mikseri → Monitör hoparlörü.

Uygulanan (statik): ses çıkışı HDMI/DisplayPort monitörse ve macOS o çıkışın sesini
değiştiremiyorsa, ses aç/kıs/sessiz tuşlarını MacPocket yakalar ve monitörün sesini
DDC/CI (VCP 0x62) ile 16 adımda (⌥⇧ ile 64) değiştirir. Monitör, ses aygıtının adı
ekran adıyla eşleştirilerek bulunur. Kendi sessiz komutu (VCP 0x8D) olan monitörde o
kullanılır; olmayanda sessiz sesi 0'a indirir ve seviyeyi saklar. Diğer tüm çıkışlarda
(Mac hoparlörü, kulaklık, USB, Bluetooth) tuşlar macOS'ta kalır. Gösterge parlaklık
göstergesinin stil ve konum ayarını kullanır. Parlaklık ve ses aynı monitöre tek DDC
kanalından yazar (aynı anda okuma yanıtları karıştırıyordu).

### Canlı kontrol — 3 Kasım 2026

Ses çıkışı MateView (DisplayPort, macOS ses ayarı yok), macOS 27. Tuş basışları
`NX_SYSDEFINED` medya olayı olarak sentezlendi; seviye ayrı bir süreçten DDC ile
geri okundu. Başlangıç %20: aç → 25, sessiz → 0, sessiz → 25, kıs → 19, kıs → 13.
Gösterge Modern stilde "MateView %25" olarak seçili konumda göründü. MateView sessiz
komutuna yanıt vermiyor (sessiz = ses 0); LG HDR 4K yanıt veriyor.

Doğrulanmayanlar: gerçek klavyenin ses tuşları (yalnız sentezlenmiş olay denendi),
LG'nin kendi sessiz komutuyla sessize alma (LG o sırada ses çıkışı değildi), çıkış
Mac hoparlörüne geçince tuşların macOS'a kalması (birim testiyle), aynı adlı iki
monitör, Kapsül ve Klasik stillerde ses göstergesi.

## Ekran görüntüsü (1. aşama)

Araçlar → Ekran Görüntüsü. CleanShot X ile tam eşdeğerlik iddiası yok; özellik listesi
resmî sayfalarından çıkarıldı, kodu incelenmedi. Tasarım:
[2026-11-03-screenshot-tool-design.md](superpowers/specs/2026-11-03-screenshot-tool-design.md).

Uygulanan (statik): alan, pencere, tam ekran ve önceki alan çekimi; ⇧⌘5 hepsi bir arada
mod çubuğu. Alan seçiminde ekranlar dondurulur (ScreenCaptureKit ile yerel çözünürlükte),
artı imleç, piksel ızgaralı büyüteç ve piksel boyutu gösterilir; Boşluk pencere moduna
geçer, Esc iptal eder. Pencere, gölgesiyle ve saydam arka planla çekilir. Çekimden sonra
panoya kopyalama, klasöre kaydetme (PNG/JPG/HEIC) ve sol altta önizleme kartı (kopyala,
kaydet/göster, düzenle, sürükle-bırak, isteğe bağlı otomatik kapanma). Son 30 günün
geçmişi. Düzenleyici: ok, vurgulayıcı, pikselleştirme, metin; geri al/yinele, kopyala,
kaydet, farklı kaydet. macOS'un kendi ekran görüntüsü kısayolları açıksa ya da CleanShot X
çalışıyorsa sayfada uyarı gösterilir (`RegisterEventHotKey` başka uygulamanın tuttuğu
kısayolu reddetmiyor).

### Canlı kontrol — 3 Kasım 2026

İki harici ekran (5120 piksel genişlik), macOS 27; tıklama ve sürüklemeler sentezlendi.
Tam ekran 5120 × 3414 PNG; 400 × 300 noktalık alan 800 × 600 piksel ve doğru bölge,
katman görüntüye girmedi; pencere modu vurguladı, MacPocket penceresi saydam PNG olarak
çekildi; önizleme kartı göründü (kullanıcı gördü, kapattı); geçmiş küçük resimleri;
düzenleyicide dört araç ve kaydet (ok, pikselleştirme, metin dosyaya işlendi); mod çubuğu
ve Esc ile iptal. CleanShot X açıkken uyarı çıktı.

Doğrulanmayanlar: kısayollarla çekim (CleanShot X ⇧⌘3/4/5'i tutuyordu), önizleme
kartından başka uygulamaya sürükle-bırak, önceki alan, HEIC/JPG ile gerçek çekim,
iki ekran arasında taşan seçim, Retina olmayan ekran, saydam arka planlı pencerenin
JPG'de beyaza basılması (birim testiyle).

## Bluetooth pilleri ve ekran ayarları

Bluetooth Pilleri (statik): Magic aygıtlar I/O Registry'den (`BatteryPercent`), adlar ve
AirPods sol/sağ/kutu `system_profiler`'dan, Logitech Bluetooth aygıtları HID++ 2.0 ile
(0x1004 / 0x1000 / 0x1001) okunur; Logitech için Giriş İzleme izni gerekir. Düşük pil
bildirimi aygıt başına bir kez, eşiğin 10 puan üstüne şarjla yeniden kurulur.
Canlı (3 Kasım 2026): Magic Keyboard %65, Magic Trackpad 2 %4, MX Master %50 (HID++
0x1000, dizin 6). Doğrulanmayan: AirPods (bağlı değildi), diğer Logitech modelleri,
bildirimin ekranda görünmesi.

Ekran Ayarları (statik): `CGDisplayCopyAllDisplayModes` (düşük çözünürlüklü kopyalar
dahil) ile gizli HiDPI modları; çözünürlük, yenileme hızı, ana ekran ve yansıtma. Değişiklik
önce oturum için uygulanır, değişen ekranda 15 sn'lik "kalsın mı?" sorulur; yanıt yoksa
geri alınır, onaylanınca kalıcı yazılır.
Canlı (3 Kasım 2026): LG HDR 4K 60 → 50 Hz uygulandı, onaysız 15 sn sonra 60 Hz'e döndü;
onay penceresi LG ekranında göründü, Esc geri aldı. Doğrulanmayan: çözünürlük değişikliğini
"Kalsın" ile kalıcı yapma, ana ekran değiştirme, yansıtma, dahili ekranlı Mac.

## Apple kaynakları

- [SwiftUI ile yeni tasarım](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Özel görünümlerde Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Ana uygulamanın giriş kaydı](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)

## Ağ Trafiği ve en sıcak sensör

**Statik:** `nettop -P -L 1 -n -x -J bytes_in,bytes_out` yönetici izni olmadan her süreç için toplam baytı verir;
adlar ~15 karakterde kesildiği için tam ad `NSRunningApplication` / `proc_pidpath` ile alınır. Yardımcı süreçler
yolundaki en dıştaki `.app` paketine toplanır (`/System/Library` altındakiler hariç). Hız, iki saniyelik iki örnek
arasındaki farktır; sayaç geriye giderse (PID yeniden kullanıldı) süreç sıfırdan başlar. Okuma yalnız sayfa açıkken yapılır.
En sıcak sensör, kalibrasyon (`tcal`) dışındaki sıcaklık okumalarının en yükseğidir.

**Canlı (Mac mini, 3 Kasım 2026):** 57 süreç listelendi; toplam indirme (117 KB/s) Genel Bakış ağ kartıyla
(114 KB/s) uyumlu. VS Code'un 7 süreci tek satırda toplandı, Chrome/Telegram/Slack simgeleriyle göründü.
Sensör kartında en sıcak sensör grafiği çizildi (SoC en yüksek 58,2 °C ile aynı değer).

**Doğrulanmadı:** Kapat/Zorla kapat düğmesi denenmedi; menü çubuğundaki "En sıcak sensör (°C)" modülü kullanıcı
ayarı değiştirilmeden yalnız birim testleriyle doğrulandı.

## USB/Thunderbolt, Disk Sağlığı, Wi-Fi Analizi ve Hosts Dosyası

**Uygulanan kod**
- `Peripherals.swift`: `IOUSBHostDevice` ağacı (ad, üretici, `UsbLinkSpeed`, `UsbPowerSinkAllocation`, arayüz sınıfları), hub gizleme, USB 2 hızındaki depolama uyarısı; Thunderbolt/USB4 portları `system_profiler SPThunderboltDataType -json` ile.
- `DiskHealth.swift`: NVMeSMARTLib eklentisi (`IONVMeSMARTInterface.SMARTReadData`) ile NVMe SMART günlüğü; yönetici izni gerekmez. Değerlendirme: kritik uyarı bitleri, yedek blok eşiği, kullanılan ömür %80/%100, veri hataları.
- `WiFiAnalysis.swift` + `WiFiView.swift`: CoreWLAN bağlantı bilgisi ve tarama; kanal yükü (2,4 GHz taşma, 5/6 GHz geniş kanal blokları), DFS’siz kanal önerisi. Kendi ağın ve yalnız BSSID’si aynı radyodan geldiğini gösteren ek SSID’ler hesaptan çıkar; ayrı cihazlar sayılır, bir cihazın birden çok SSID’si yükte bir kez sayılır. Ağ listesinde BSSID, güvenlik, standart, “Bağlı/Aynı modem” etiketi, arama, bant filtresi, sıralama ve 30 sn otomatik tarama var. Ağ adları ve BSSID konum izni ister.
- `HostsFile.swift` + `HostsView.swift`: `/etc/hosts` ayrıştırma (dokunulmayan satırlar bayt bayt korunur), `## Ad - Start/End ##` grupları, satır/grup aç-kapa (# ile), ekleme doğrulaması, sistem satırları kilitli. Kaydetme `do shell script … with administrator privileges` ile: önce `/etc/hosts.macpocket-backup`, sonra `cat >` ve DNS önbelleği temizliği.

**Canlı doğrulama (Mac mini, macOS 27)**
- Disk Sağlığı: APPLE SSD AP1024Z, %97 ömür, 47,18 TB yazılmış, 2.744 saat, 47 °C — bağımsız SMART okumasıyla aynı.
- USB: Magic Trackpad (12 Mb/s, 1.300 mA) ve VIA Billboard ioreg ile aynı; 3 Thunderbolt portu boş, en fazla 120 Gb/s.
- Wi-Fi: −40 dBm, gürültü −90, kanal 48 / 5 GHz / 80 MHz, 1200 Mb/s, 18–20 ağ; adlar ve BSSID’ler göründü. KM WiFi/KM Office (1a:/1e:27:f5:db:d0:31) “Aynı modem” işaretlendi; ayrı cihaz 0a:a6:f7:98:91:ba/bb/bc tek cihaz sayıldı (kanal başına 3 cihaz).
- Hosts: mevcut dosya ve `Local` grubu doğru okundu; satır kapatma ve Vazgeç denendi, dosya değişmedi.

**Doğrulanmadı**
- Hosts kaydetme ve yedekten geri yükleme (yönetici parolası gerektirir; birim testleri komutu ve dosya içeriğini kapsar).
- Thunderbolt’a bağlı aygıt listesi (bu makinede bağlı aygıt yok; ayrıştırma birim testiyle).
- USB 2 hızındaki depolama uyarısı (bağlı harici disk yok).

## Bakım aracı

**Uygulanan kod:** `MaintenanceTasks.swift` sekiz görev tanımlar (Quick Look, Launch Services `lsregister -gc`, yazı tipi önbelleği, DNS, `diskutil verifyVolume /`, `purge`, Dock/Finder/SystemUIServer yeniden başlatma, `mdutil -E /`). Kullanıcı düzeyindeki görevler sırayla çalışır; yönetici görevleri `AdministratorShell` üzerinden tek parola sorusunda toplanır ve her görevin çıkış kodu ayrı işaretle okunur. Komutlar katalogda sabittir ve kabuğa gitmeden önce katı karakter denetiminden geçer. Periyodik Bakım, macOS 27’de `periodic` bulunmadığı için kaldırıldı. Hosts yazıcısı da aynı `AdministratorShell` yardımcısını kullanır.

**Canlı doğrulama:** Bakım sayfasında “Başlangıç Diskini Doğrula” tek başına çalıştırıldı: “Tamamlandı · 7,4 sn · Dosya sisteminde hata bulunmadı”; son çalıştırma bilgisi uygulama yeniden açıldıktan sonra korundu.

**Doğrulanmadı:** Yönetici görevlerinin (DNS, bellek, Spotlight) gerçek parola sorusuyla çalışması; Launch Services, Quick Look ve Dock/Finder görevlerinin uygulamadan çalıştırılması (yalnız birim testleri).

## Kurulum sihirbazı

- **Uygulanan:** İlk açılışta (ve `OnboardingRecord.currentVersion` artınca bir kez) açılan 4 adımlı pencere: karşılama, izinler, tercihler, hazır. İzinler: Erişilebilirlik, Ekran Kaydı, Tam Disk Erişimi (korunan dosya okunarak denetlenir), Giriş İzleme, Konum, Bildirimler; durum saniyede bir yoklanır. Liste tabanlı panellerde Sistem Ayarları penceresinin yanında uygulama simgesini sürüklemek için yüzen kart çıkar. macOS izni uygulamak için uygulamayı kapatırsa sihirbaz kaldığı adımdan sürer; pencereyi kullanıcı kapatırsa tamamlanmış sayılır. Ayarlar › Genel ve uygulama menüsünden yeniden açılır.
- **Canlı doğrulanan:** İlk açılışta otomatik açılma; karşılama animasyonu; 6 iznin gerçek durumu (5/6 verildi); Tam Disk Erişimi panelinin açılması ve kartın pencerenin sağına yerleşmesi; Sistem Ayarları kapanınca kartın gizlenmesi; izin verilince yeniden açılışta İzinler adımından devam ve iznin “Verildi” görünmesi; tercihler ve bitiş adımı, tamamlanma kaydı.
- **Doğrulanmayan:** Simgenin listeye gerçekten sürüklenip bırakılması; Bildirim ve Konum için macOS istem penceresi; Ekran Kaydı/Giriş İzleme için “Yeniden Başlat” kartı.

## Menü çubuğu genişletmesi (GPU, ağ durumu, yeni görünümler)

- **Referans incelemesi (statik):** iStat Menus 7 ikili dosyalarında REA ile sınıf ve ayar anahtarı incelemesi yapıldı (`BBRGPUMenubar`, `Network.Menubar.Mode.Ping/VPN/Wifi`, `CPU.Menubar.Mode.Cores`, `PieGraph`, `DiskActivity ReadWrite`). Bu yalnız özellik listesi çıkarımıdır; iStat ile eşdeğerlik iddiası yoktur.
- **Uygulanan:** GPU modülü (`IOAccelerator` → `PerformanceStatistics`: kullanım, işleyici, döşeyici, kullanılan bellek; ayrıntı paneli). Ağ modülüne gecikme (yalnız seçiliyken 10 sn’de bir `/sbin/ping -c 1 1.1.1.1`), Wi-Fi sinyali (CoreWLAN RSSI), VPN kilidi (ağ hizmeti taşıyan utun/ipsec/ppp arayüzleri) ve `NWPathMonitor` ile çevrimdışı durumu. Disk için okuma/yazma iki satır ve ayna grafik. Yeni görünümler: pasta, CPU çekirdek çubukları. Sıcaklık için sensör seçici (yoksa en sıcak sensöre düşer).
- **Canlı doğrulanan:** Ayrı düzende CPU çekirdek çubukları, GPU grafik + değer, disk O/Y ayna grafik, sıcaklık pasta + 59°, ping 16 ms gerçek değerlerle çizildi; erişilebilirlik etiketleri doğru (ör. “GPU: %23 kullanım”, “Gecikme: 33 ms”).
- **Doğrulanmayan:** GPU ve ağ ayrıntı panelleri (ekran kilitlendi), VPN bağlıyken kilit simgesi (Tailscale bağlı değildi), çevrimdışı görünümü, ayarlardaki sensör seçici ve görünüm sekmeleri.

## Ekran Süresi

- **Uygulanan:** Kullanıcı açınca başlayan takip (`MacPocket.screenTime.enabled`). Öndeki uygulama `NSWorkspace` bildirimleriyle izlenir; kilit, uyku ve ekran uykusunda durur; `CGEventSource` boşta süresi eşiği (2/5/10 dk) aşılınca son girdiye kadar sayılır. Ekran uykusunu engelleyen (video) uygulama boşta sayılmaz (`IOPMCopyAssertionsByProcess`). Kayıt saat ve gün sınırında bölünür, `~/Library/Application Support/MacPocket/screen-time.json` içinde 30 gün tutulur, 20 sn’de bir ve çıkışta yazılır. Sayfa: Bugün/Dün/7/30 gün, özet kutuları, saatlik/günlük grafik, uygulama listesi, uygulama kaydı silme, tüm verileri silme.
- **Canlı doğrulanan:** Takibi başlatma, Finder/Safari/MacPocket arasında geçiş sonrası süre, pay, geçiş sayısı (4) ve en yoğun saat; 7 gün görünümü ve okunur eksen; sayfanın sonuna kadar kaydırma.
- **Doğrulanmayan:** Boşta duraklatma, kilit/uyku duraklatması, video uygulamasının sayılmaya devam etmesi, gece yarısını geçen kayıt (yalnız birim testi), silme onayı.

## Menü çubuğu düzenleyici ve eşik renkleri

- **Uygulanan:** Ayarlar › Menü Çubuğu üstte canlı bir menü çubuğu şeridi (öğeler gerçek çizimle), sürükleyerek sıralama, kapalı modüller rafı (rafa bırakınca kapanır, raftan sürükleyince/tıklayınca açılır), seçili modülün ayar paneli, açık/koyu/sistem önizleme; gruplu düzende açılır pencere sekme sırası. Ayarlar penceresi 760×620. Eşik renkleri: `MenuBarColorMode` (tek renk/eşiğe göre), değer birimine göre eşikler (`MenuBarThresholdUnit`: %, °C, ms, dBm), düşükken kötü değerlerde (pil, Wi-Fi) ters yön, varsayılan eşikler; uyarı turuncu, kritik kırmızı (yalnız alarmda şablon dışı görüntü). Gruplu canlı simge de izlediği modülün eşiğine göre renklenir.
- **Canlı doğrulanan:** Sürükleyerek sıralama (RAM → CPU önüne, kayıtlı sıra değişti), raftan Disk ekleme, GPU’yu rafa bırakıp kapatma; gerçek menü çubuğu anında güncellendi. CPU %14 > %5 uyarı → turuncu, sıcaklık 66° > 50° kritik → kırmızı hem önizlemede hem gerçek menü çubuğunda.
- **Doğrulanmayan:** Gruplu düzende sekme sürükleme ve renkli gruplu simge, koyu önizleme seçeneği, eşik kaydırıcılarını sürükleme.

## Otomatik güncelleme (Sparkle)

- **Uygulanan:** Sparkle 2.10.1 (SwiftPM, yalnız uygulama hedefi). `scripts/build-app.sh` framework’ü `Contents/Frameworks` içine koyar, `@executable_path/../Frameworks` rpath’i ekler ve Sparkle’ın iç bileşenlerini (Installer.xpc, Downloader.xpc, Autoupdate, Updater.app, framework) içten dışa imzalar. Info.plist: `SUFeedURL` = son GitHub sürümünün `appcast.xml`’i, `SUPublicEDKey`, günlük otomatik denetim, sistem profili kapalı. `scripts/make-appcast.sh` zip’i EdDSA ile imzalar (CI’da `SPARKLE_ED_PRIVATE_KEY` stdin’den, yerelde anahtar zincirindeki `MacPocket` hesabından) ve CHANGELOG bölümünden sürüm notlu appcast üretir; release iş akışı appcast’i sürüme ekler. Arayüz: uygulama menüsünde “Güncellemeleri Denetle…”, Ayarlar › Genel › Güncellemeler, kurulum sihirbazında otomatik denetim seçeneği.
- **Canlı doğrulanan:** Debug ve release paketlerinde `codesign --verify --deep --strict` geçerli; release’te Sparkle bileşenleri Developer ID + hardened runtime ile imzalı. Framework uygulama içinden yükleniyor. Menüden denetim Sparkle’ın Türkçe arayüzünü açtı (v0.1.2’de appcast olmadığı için beklenen “Güncelleme Hatası”). Ayarlar’da son denetim zamanı güncellendi. Yerel appcast üretimi ve `sign_update --verify` ile imza doğrulaması geçti.
- **Doğrulanmayan:** Gerçek bir sürümden diğerine güncelleme (ilk Sparkle’lı sürüm yayımlandıktan sonra mümkün), CI’daki appcast adımı (`SPARKLE_ED_PRIVATE_KEY` secret’ı gerekli), notarization’ın Sparkle bileşenleriyle kabulü.

## Yerel Ağ

- **Sihirbaz kaydı uyumluluk düzeltmesi (4 Kasım 2026):** Yeni kayıt açıp tekrar onay istemeye yol açan helper adlandırması geri alındı; kurulum kimliği, plist MachServices anahtarı, kurulu yürütülebilir yol ve XPC protokol adı için regresyon testi eklendi. İlgili 49 test ve 3.144 anahtarlı yerelleştirme kontrolü geçti. Kurulu uygulamanın özgün kimlikle yapılan denemesinde macOS `needsApproval` bildiriyor; sistemde çalışan eski helper kaydı yok. Önceki sürümün kaldırdığı bir sistem onayı uygulama tarafından yeniden verilmez. Bu nedenle otomatik root/XPC taraması bu makinede henüz canlı doğrulanmış sayılmaz.
- **Güncel akış — otomatik helper entegrasyonu (4 Kasım 2026):** Normal tarama, her yönlendirilen ağın sonucunu `LANHelperDiscovery.complete` ile tamamlar. Uygulama, imzalı aynı takım/uygulama kimliği koşulunu koruyan XPC bağlantısından yardımcı servise yalnız CIDR ve arayüz gönderir. Root helper bunları yeniden doğrular, arayüzün bağlı olduğunu denetler ve komutu kendisi üretir; istemciden shell komutu veya serbest host listesi kabul etmez. Tüm /22–/30 aralığı 32 eşzamanlı ping sınırıyla taranır; geçici rota çıkışta temizlenir. Ağ işleri fan kalp atışı ve sıcaklık denetimi kuyruğunu engellemeden sırayla çalışır. SMC erişimi yoksa da ağ servisi başlayabilir. Ayrı “MAC Adreslerini Bul” düğmesi kaldırıldı; aşağıdaki düğme/osascript kayıtları geçmiş akışa aittir, uygulamanın normal taraması bunları kullanmaz.
- **Helper kurulumu ve geçiş:** Kurulum yalnız mevcut sihirbaz/yardımcı servis kartında yapılır. Normal tarama `register` veya `unregister` çağırmaz; mevcut kaydı kullanır. Sihirbazın özgün `com.doancan.MacPocket.FanHelper` servis kimliği, `MacPocketFanHelper` kurulu dosya yolu ve `FanHelperXPC` Objective-C protokol adı korunur. Swift ürününün genel bir ad alması bu kalıcı kurulum kimliklerini değiştirmez. Etkin servis yeniden kaydedilmez veya kaldırılmaz. Önceki hatalı geliştirme sürümlerinin oluşturduğu farklı `com.doancan.MacPocket.Helper` kaydı, normal taramadan bağımsız debug onarımında kaldırılmaya çalışılır. Etkin olmayan servis, sonuçlar gizlenmeden durum hatası olarak bildirilir; sihirbazın tamamlanmış olması macOS yetkilendirmesinin yerine geçmez. Normal taramayı imzalı kurulu uygulamadan sınamak için debug argümanı: `/Applications/MacPocket.app/Contents/MacOS/MacPocket --diagnose-lan /tmp/macpocket-auto-helper-live.json`.
- **Bu entegrasyonun otomatik doğrulaması:** Ağ/helper/fan/bakım kapsamındaki 48 test geçti. Yeni testler tüm yönlendirilen ağların otomatik tamamlanmasını, ICMP’de görünmeyen cihazın eklenmesini, helper tarafında geçersiz CIDR/arayüz reddini ve helper hatasının boş başarı olarak gizlenmemesini kapsar. Paket ve imza kontrolü geçti; yerelleştirme 3.144 anahtar, 0 eksik/biçim uyuşmazlığı. İlk kurulu uygulama denemesinde macOS helper için arka plan servisi onayını açtı (`Operation not permitted`, BTM onay kaydı); Son kurulu kopyanın tanı raporu `helper: needsApproval` ve bir defalık Giriş Öğeleri onayı mesajını doğruladı; canlı XPC taramasının doğrulanması sistem onayı bekliyor.
- **Tam aralık MAC araması düzeltmesi ve canlı doğrulama (4 Kasım 2026):** Önceki düğme yalnız normal taramada bulunan IP’leri sorguluyordu; yönlendirilmiş ICMP’ye yanıt vermeyen `.12` bu yüzden atlanıyordu. Artık tüm kullanılabilir alt ağ adresleri 32 eşzamanlı ping sınırıyla sorgulanır; ARP bağımsız keşif kaynağı olarak yeni cihaz ekler, mevcut ad/gecikmeyi korur ve arayüz tahmininin yerine doğrudan MAC’i koyar. Yeni `macpocket-probe lan-macs 192.168.2.0/24` aynı komut ve birleştirme kodunu kullanır. Deneme aracında `NSAppleScript` yolu `Authorization failed` üretirken ayrı `osascript` başarılı oldu; yalnız MAC aramasının yönetici yürütmesi bu yola taşındı. Diğer yönetici araçlarının mevcut yolu değiştirilmedi. İptal/hata kodları korunur, işlem 300 saniyeyle sınırlıdır.
- **Bu düzeltmenin canlı sonucu:** Yeni deneme komutu 17 cihaz listeledi ve şu beş doğrudan MAC’i gösterdi: `.8` → `18:A6:F7:DF:91:B7`, `.9` → `18:A6:F7:DF:8F:5C`, `.11` → `2C:C8:1B:B6:FD:09`, `.12` → `3C:52:A1:3E:DA:A8`, `.103` → `10:27:F5:DB:D0:30`. Hepsinin kaynağı `arp`; diğer 12 cihaz için doğrudan ARP yanıtı alınmadı. Sonrasında `route get 192.168.2.8` yeniden varsayılan `192.168.0.1` geçidini gösterdi. Uygulama derlenip yeniden açıldı; erişilebilirlik izni olmadığından uygulama içi düğmeye otomatik basılarak kabul testi yapılamadı. Düz tarama bu yönetici adımını kendiliğinden çalıştırmaz; kullanıcı Yerel Ağ’daki “MAC Adreslerini Bul” düğmesini kullanır.
- **Bu düzeltmenin otomatik doğrulaması:** Ağ, güç zamanlaması ve bakım kapsamındaki 38 test geçti. Yeni test, normal taramada olmayan ARP cihazının eklenmesini, doğrudan MAC’in önceliğini, mevcut ad/gecikmenin korunmasını, arayüz/alt ağ filtresini ve yönetici süreç hatalarının/iptalin yorumlanmasını kapsar. Uygulama paketleme ve imza kontrolü geçti; 3.143 yerelleştirme anahtarında 0 eksik/biçim uyuşmazlığı var. Aşağıdaki kayıtlar önceki doğrulama aşamalarına aittir.
- **MACLookup (4 Kasım 2026):** Kullanıcının verdiği [JSON indirme adresinden](https://maclookup.app/downloads/json-database/get-db) alınan 77.719 kayıt, `Resources/maclookup.json.lzfse` içinde yaklaşık 928 KiB olarak paketlenir. [Kaynak şemaya](https://maclookup.app/downloads/json-database) göre `private` kayıtlar ve donanım ataması olmayan CID blokları atlanır; 58.990 kullanılabilir MA-L/MA-M/MA-S/IAB öneki kalır. MACLookup aynı önekte öncelikli, IEEE ek kayıtları korunan yedektir; en uzun önek önce seçilir. Rastgele/yerel yönetilen ve multicast MAC’lere üretici atanmaz. Ek dosya eksik/bozuksa IEEE ile devam edilir. Güncelleme: `scripts/update-maclookup.sh`; uygulama çalışma anında internete üretici sorgusu göndermez.
- **Diğer alt ağlarda uygulanan düzeltmeler (4 Kasım 2026):** SNMP, hedef IPv4 için hem `ipAdEntIfIndex` hem `ipAddressIfIndex` sorgular; varsa ilgili `ifPhysAddress` adresini alır ([RFC 1213](https://www.rfc-editor.org/rfc/rfc1213.html), [RFC 4293](https://www.rfc-editor.org/rfc/rfc4293.html)). Eşleştirme yoksa ilk geçerli arayüz MAC’i korunur ancak kaynak `snmpInterface` olur ve ayrıntıda hedef IP ile eşleşmesinin doğrulanamadığı belirtilir. IP ile eşleşen sonuç, eşleşmeyen arayüzden önceliklidir. SNMP’de istek kimliği ve kaynak IP/port; NetBIOS’ta kaynak IP/port ve işlem kimliği denetlenir. Doğrudan ARP araması yalnız istenen IP’leri seçilen arayüzden kabul eder; bulunan doğrudan adres, önceki SNMP/NetBIOS adresini ve kaynak etiketini günceller. Arayüz açıklamalarındaki “diğer ağlarda MAC görünmez” iddiası kaldırıldı.
- **Yeni canlı doğrulama (4 Kasım 2026):** `macpocket-probe lan 192.168.2.0/24` ile 16 cihaz bulundu; yalnız `.11` MikroTik SNMP MAC’i verdi: `2C:C8:1B:B6:FD:09`, kaynak `snmpInterface`. Sistem `snmpget`/`snmpwalk` ile bu cihazda 17 farklı arayüz MAC’i olduğu, ilk adresin bu değer olduğu ve her iki IP–arayüz OID’sinin `No Such Object` döndürdüğü doğrulandı. Rota `192.168.0.1` üzerinden `en1` kullanıyor, bu alt ağda doğrudan ARP kaydı yok. Bu tur yönetici yetkisiyle on-link rota ekleme çalıştırılmadı; diğer cihazların MAC adresleri canlı doğrulanmış sayılmaz.
- **Yeni otomatik doğrulama (4 Kasım 2026):** İlgili 27 test geçti; MACLookup şema/filtre/öncelik kuralları, paket verisinin yüklenmesi ve bozuk ek dosyada IEEE’ye dönüş, SNMP IP OID’leri ve adres önceliği, ARP arayüz/IP filtresi kapsandı. Uygulama paketi üretildi ve imza kontrolü geçti. Yerelleştirme: 3.143 anahtar, 0 eksik/biçim uyuşmazlığı. IP eşleşmeli SNMP yolu bu cihazda desteklenmediğinden canlı doğrulanmadı; aşağıdaki eski canlı doğrulama kayıtları ayrı tutulmuştur.
- **Uygulanan düzeltmeler:** MAC araması yönetici yanıtından sonra sonucu ağ kimliğiyle yeniden bulur; kaldırılan aralığa yazmaz, güncel cihaz bilgilerini korur. Normal tarama ve MAC araması karşılıklı olarak çakışmayı engeller. Geçici rota eklenemezse işlem başarısızlıkla durur; yalnız başarıyla eklenen rota için çıkış/sinyal temizliği kurulur. Bonjour, ping/ARP kaydı olmasa da bağlı alt ağda cihaz oluşturur; diğer alt ağların hizmetleri eklenmez. ARP tablosu Bonjour bittikten sonra okunur.
- **Otomatik doğrulama (4 Kasım 2026):** İlgili 23 test geçti. Yeni regresyon testleri gerçek ağ/rota değişikliği olmadan shell akışında rota ekleme başarısızlığını, normal çıkışı, erken hatayı ve TERM sinyalinde temizliği; Bonjour cihaz keşfini, mevcut bilgilerin korunmasını ve alt ağ sınırını kapsar. Uygulama derlemesi ve yerelleştirme kontrolü geçti (3.142 anahtar, 0 eksik/biçim uyuşmazlığı). Bu düzeltmelerden sonra canlı ağ/arayüz kabul testi yapılmadı; MAC aramasında aralığı kaldırma senaryosu kod incelemesi ve derlemeyle kontrol edildi.
- **Uygulanan:** Varsayılan rota arayüzünün alt ağında (en çok /22; daha büyükse kendi /24’ü) ayrıcalıksız ICMP datagram soketiyle tek seferde ping taraması; ARP tablosundan MAC (`arp -an`); 20 Bonjour hizmet türünden ad ve tür (IPv4’e zorlanmış bağlantıyla çözülür, `_device-info` modeli adla eşleşir); ters DNS. Üretici: IEEE MA-L/MA-M/MA-S/IAB kayıtlarından üretilmiş 58.704 önek `Resources/oui.tsv.lzfse` (598 KB) içinde, en uzun önek önce; kullanıcı tarafında ağ isteği yok (`scripts/update-oui.sh` ile yenilenir). Liste ve ağ haritası; ayrıntı panelinde saniyede bir ping (grafik, ortalama, oynaklık, kayıp), 21 yaygın TCP portu ve risk notları, web arayüzü başlığı, Wake-on-LAN, ilk/son görülme, yeniden adlandırma. Bilinen cihazlar MAC ile saklanır; isteğe bağlı 15 dakikalık taramayla yeni cihaz bildirimi. `NSLocalNetworkUsageDescription` ve `NSBonjourServices` Info.plist’te.
- **Canlı doğrulanan:** Yerel Ağ izni verildikten sonra 10 cihaz, 8’i yanıtlı, gerçek gecikmeler (yönlendirici 21 ms) ve MAC adresleri; deneme aracında Bonjour adları (EV-Charger-01/02, Doğancan’s Mac Studio → bilgisayar, Office → TV, BRAVIA → TV). İzin yokken ping’lerin engellendiği ve ARP’nin izinsiz araçtan boş döndüğü gözlendi.
- **Canlı doğrulanan (uygulama):** Liste 10 cihaz / 9 yanıtlı, Bonjour adları ve üreticiler (Espressif → akıllı ev, Apple, Intel); ilk açılıştaki boş taramada otomatik tekrar; ayrıntı panelinde yönlendirici için canlı ping (ort. 5 ms, oynaklık 1 ms, %0 kayıp), açık portlar 22/53/80/443 ve web başlığı “Login | OPNsense”; ağ haritası. `.inspector` değiştiricisi özelleştirilebilir araç çubuğuyla yerleşim sırasında çakışıp uygulamayı çökertiyordu (NSWindow kısıt istisnası); panel sayfa içi yan panele taşındı.
- **Çoklu ağ:** Bağlı tüm IPv4 arayüzleri (SystemConfiguration yerel adlarıyla; 169.254 “Doğrudan bağlantı”) ve elle eklenen CIDR aralıkları (/22–/30, yönlendirici üzerinden: yalnız ping ve ters DNS) birlikte taranır; seçim ve aralıklar kalıcıdır. Her taramanın rastgele ICMP kimliği ve yanıt kaynak adresi denetimi paralel taramaları ayırır; gönderim ayrı iş parçacığında yapıldığı için gecikmeler yanıt geldiği anda ölçülür. Canlı: Wi-Fi + Doğrudan bağlantı + kullanıcının eklediği 192.168.2.0/24 birlikte; yönlendirilen ağda 16 cihaz, ters DNS “firewall”, ayrıntı panelinde ping ve SSH.
- **NetBIOS:** Yanıt veren her adrese UDP 137 “node status” sorgusu; yanıttan bilgisayar adı, çalışma grubu ve (yönlendirici arkasında da) MAC adresi alınır. Canlı: yerel ağda GORKEM-HUAWEI (Windows) ve Doğancan’s Mac Studio MAC’leri ARP’siz geldi; yönlendirilen 192.168.2.0/24 yönetim ağındaki 17 cihazın hiçbiri NetBIOS yanıtlamadı (switch/AP/sunucu), bu yüzden orada MAC yok — `route get` GATEWAY bayrağı, traceroute’ta 192.168.0.1 ara adımı ve 0 ARP kaydıyla doğrulandı.
- **SNMP ve aynı kablo MAC araması:** Yanıt veren adreslere SNMP v2c (“public”) ile sysName, sysDescr ve ilk arayüz MAC’i sorulur (canlı: 192.168.2.11 MikroTik CRS317, 2C:C8:1B:B6:FD:09). Yönlendirilen aralıklarda “MAC Adreslerini Bul” düğmesi, yönetici parolasıyla aralığı birkaç saniyeliğine on-link işaretler, macOS’un doğrudan ARP sormasını sağlar ve rotayı aynı komutta kaldırır (canlı: .8, .9, .11, .12, .103 MAC’leri — Advanced IP Scanner’la aynı beş cihaz; rota sonra temizlendi). Bu işlem bilinçli olarak yalnız istek üzerine ve parolayla çalışır; kök yardımcıya taşınmadı.
- **Doğrulanmayan:** Wake-on-LAN’ın gerçek bir cihazı uyandırması, yeni cihaz bildirimi; Ethernet + Wi-Fi aynı anda bağlıyken tarama (bu Mac’te Ethernet bağlı değil); “MAC Adreslerini Bul” düğmesinin uygulama içinden çalıştırılması (aynı komut terminalden doğrulandı).

## Güç Zamanlaması

- **Uygulanan:** Mevcut program IOKit’ten (`IOPMCopyRepeatingPowerEvents`/`IOPMCopyScheduledPowerEvents`, Swift’e aktarılmadığı için `dlsym`) okunur; sistemin görünmez zamanlayıcıları gizlenir. Tekrarlayan bir açılış (uyandır veya aç / uyandır / aç) ve bir kapanış (uyut / kapat) olayı gün seçimiyle; tek seferlik olay ekleme ve iptal. Yazma `pmset repeat` / `pmset schedule` ile yönetici onayıyla; komutlar sabit sözcüklerden kurulur.
- **Canlı doğrulanan:** Okuma (bu Mac’te kullanıcı programı yok → boş); sayfa, açılış satırının eylem/saat/gün seçicileri, özet ve kaydedilmemiş değişiklik uyarısı, Geri Al.
- **Doğrulanmayan:** Yönetici parolasıyla kaydetme ve iptal, olayların gerçekten tetiklenmesi.

## USB Çıkarma Yöneticisi

- **Uygulanan:** Araçlar › USB Çıkarma Yöneticisi. `diskutil` plist çıktısından harici fiziksel diskler okunur; APFS fiziksel depoları ve bütün bölümler tek disk altında gruplanır. Dahili diskler, başlangıç diskinin fiziksel depoları, çok depolu APFS konteynerleri ve disk imajları çıkarma listesinden dışlanır. Tekli ve seçilenleri toplu çıkarma; işlem sırasında devre dışı eylemler, başarı/hata/boş/yükleniyor durumları. Liste sayfa açıkken üç saniyede bir yenilenir. Finder’da açma, süreç uygulamasına geçme ve kullanım inceleme bulunur.
- **Güvenli çıkarma:** Her işlemden hemen önce disk tekrar okunur; bölüm UUID’leri ve mevcut IOMedia kayıt kimliğiyle yeniden takılmış/farklı diskin aynı BSD adını devralması denetlenir. Eski seçim yeni diske aktarılmaz. Apple Disk Arbitration ile önce bütün disk normal olarak unmount edilir (`kDADiskUnmountOptionWhole`), başarıdan sonra `DADiskEject` çağrılır. Force seçeneği veya otomatik süreç sonlandırma yoktur. İşlem hatasında kullanım incelemesi otomatik açılır; başarılı diğer disklerin sonucu korunur. Bu özellik mevcut fan/ağ helper’ına bağlı değildir.
- **Kullanım incelemesi:** `lsof -nP +c 0 -F0pcfn +f -- <mount paths>`; dizin ağacı taranmaz. NUL alanlarıyla boşluk/satır sonu içeren yollar ayrılır; PID başına benzersiz açık dosyalar listelenir, ekranda ilk beşi gösterilir. `realpath` ile `/var` ve `/private/var` eşleşmesi korunur. Yalnız bu oturumda okunabilen süreçlerin görülebildiği açıkça belirtilir; izin/okuma hatası “disk boşta” diye gösterilmez. macOS’un çıkarma kararı asıldır.
- **Otomatik ve yerel çalışma doğrulaması (4 Kasım 2026):** `MACPOCKET_USB_EJECT_IMAGE_TESTS=1 swift test --filter USBEjectTests`: 10 test geçti. APFS gruplama, dahili/harici başlangıç diski koruması, çok depolu konteyner dışlama, kimlik değişimi, NUL dosya adı/PID ayrıştırma, Türkçe adlarda lsof byte kaçışları, bölüm tablosuz USB dosya sistemleri, izin hataları ve eylem öncesi yeniden doğrulama kapsandı. Testin kendi oluşturduğu 16 MB HFS+ disk imajında gerçek `lsof` ile açık dosyanın sahibi bulundu; açık dosya normal çıkarmayı engelledi, dosya kapatılınca native unmount/eject başarılı oldu. Üretim listesi bu imajı USB disk diye göstermedi. İmaj test sonunda temizlendi.
- **Derleme ve yerelleştirme:** Uygulama paketlemesi ve imza kontrolü geçti. Türkçe/İngilizce 3.173 anahtar, 0 eksik çeviri/biçim uyuşmazlığı; açık dosya sayısının İngilizce tekil/çoğulu stringsdict içindedir. `/Applications/MacPocket.app` güncellendi ve yeni araç açık olarak çalıştırıldı; sürüm/build numarası değiştirilmedi. Uygulamanın kendi görünümünden boş durum görüntüsü alındı; katmanlı kontrollerin görüntüye tam yansımaması nedeniyle bu tam görsel kabul testi sayılmadı.
- **Doğrulanmayan:** Bu Mac’te takılı harici fiziksel disk olmadığı için gerçek USB/Thunderbolt disk ve birden fazla fiziksel aygıtta toplu çıkarma kabul testi yapılmadı. Klavye ve VoiceOver kabul testi yapılmadı. Disk imajı denemesi gerçek USB donanım testi yerine sayılmaz.

## Menü çubuğunda hava durumu

- **Uygulanan:** Hava durumu, gruplu ve ayrı düzenlerde kendi status item’ında sıcaklık/koşul simgesi gösterir. Açılır panelde hissedilen sıcaklık, nem, rüzgâr, sonraki sekiz saat ve beş günlük tahmin ile kaynak bağlantısı bulunur. Şehir/ilçe adı Apple MapKit ile aranır; adres ve bölge içeren sonuçlar arasından kullanıcı seçer. Aynı konum seçici Menü Çubuğu ayarlarında da vardır. GPS izni istenmez. Ad, koordinatlar ve saat dilimi UserDefaults’ta saklanır; sabit İzmir varsayılanı yoktur.
- **Veri akışı:** `WeatherClient`, kaynak koda daha önce kullanıcı isteğiyle eklenen yapılandırmayı kullanır; istek gövdesi ve kimlik günlüklenmez. Ölçü birimleri °C, yüzde ve API’nin m/s rüzgâr değerinden dönüştürülen km/sa’dir. Hava durumu modülü görünürken saatte bir yenilenir; elle yenilemeler arasında en az bir dakika beklenir. Devre dışı bırakma/konum değişimi eski isteğin yeni konumu ezmesini engeller. Ağ/API hatası aynı oturumdaki son başarılı veriyi silmez; ilk veri yoksa sıcaklık yerine bekleme işareti gösterilir.
- **Otomatik doğrulanan (4 Kasım 2026):** `swift test --filter 'WeatherTests|MenuBar'`: 35 test geçti. Yeni yedi test; seçilen koordinatların JSON isteğine aktarılması, geçersiz koordinatların reddi, konum depolama turu, API hata gövdeleri, isteğe bağlı tahmin alanları, sağlayıcı birimleri/saat dilimi ve sistem snapshot’ından bağımsız menü sıcaklığı gösterimini kapsar. Yerelleştirme: 3.202 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı.
- **Canlı doğrulanan:** İmzalı `/Applications/MacPocket.app` içindeki gerçek arama ve istemci ile “Ankara, Türkiye” arandı; 39.9210643 / 32.8562777 koordinatları ve Europe/Istanbul saat dilimi döndü. API 10,6 °C, 167 saat ve 10 günlük tahmin verdi; menü formatlayıcısı `11°` üretti. Gerçek weather status item’ı ve görseli oluştu; 368 px genişliğindeki konum seçme popover’ı açıldı. Deneme kullanıcının konum seçimini değiştirmedi. Paketleme ve imza doğrulaması geçti; sürüm/build numarası değiştirilmedi.
- **Doğrulanmayan:** Arama sonucuna fiziksel tıklama, uygulama arayüzünde konum seçip yeniden başlatma, saatlik zamanlayıcıyı bir saat bekleyerek doğrulama, klavye/VoiceOver ve tam görsel kabul testi yapılmadı. Konumun kodlama/çözme kalıcılığı otomatik testle, seçicideki saklama ve iptal akışı kaynak incelemesiyle kontrol edildi. Test raporu `/tmp/macpocket-weather-live.json` konumundadır ve kimlik içermez.

## Araç performansı — 5 Kasım 2026

- **Ağ trafiği:** Değişmez `NetworkTrafficGroup` satırlarının indirme/yükleme ve oturum toplamları oluşturulurken tek geçişte hesaplanır. Sıralama ve arayüz okumaları aynı toplamları tekrar satır satır hesaplamaz. `NetworkTrafficModel` aynı anda yalnız bir örnekleme yapar; oturumu sıfırlamak ikinci bir `nettop` süreci başlatmaz. Sıfırlamadan önce başlayan sonucun uygulanması nesil kimliğiyle engellenir; iptal edilen örnekleme görünümü güncellemez. Aynı grup verileri tekrar yayımlanmaz.
- **USB çıkarma:** Önce harici fiziksel disk listesi okunur. Liste geçerli ve boşsa tüm disklerin APFS topolojisi ve başlangıç diski bilgisi sorgulanmaz: yenileme başına üç yerine bir `diskutil` süreci. Disk varsa başlangıç diski/APFS ve çıkarma öncesi aygıt kimliği doğrulamaları korunur. Değişmeyen disk dizisi tekrar yayımlanmaz; eski kimlik eşleştirmesi bir küme üzerinden yapılır.
- **Hava durumu (kaynak incelemesi):** Dakikada bir kalkan döngü kaldırıldı. İstek başladıktan sonra tek iptal edilebilir görev bir saat sonraki yenilemeyi bekler; konum yoksa görev kurulmaz. Konum değiştirme, elle yenileme veya modülü kapatma eski zamanlayıcıyı iptal eder. Saatlik ağ yenileme aralığı korunur. Bir saat beklenerek canlı zamanlayıcı kabul testi yapılmadı; güç tüketiminde yüzdesel kazanç iddiası yoktur.
- **Önce/sonra ölçümü:** Aynı debug testinde 24.000 süreç satırı, 240 uygulama grubu ve 20 gruplama/sıralama tekrarı: önce **3,712605 sn**, sonra **0,159603167 sn** (yaklaşık 23 kat). Bu yapay büyük liste ölçümüdür; tüm uygulamanın veya olağan küçük listenin aynı oranda hızlandığı anlamına gelmez. Boş USB listesi için enjekte edilen komut yürütücü önce **3**, sonra **1** çağrı kaydetti. Ölçümler `/tmp/macpocket-optimization-before.log` ve `/tmp/macpocket-optimization-after.log` içindedir.
- **Doğrulama:** `MACPOCKET_USB_EJECT_IMAGE_TESTS=1 swift test --filter 'NetworkTraffic|USBEjectTests|WeatherTests|MenuBar'`: **53 test, 0 hata, 0 atlanan**. Büyük listede toplamlar/sıralama, boş listede komut sayısı, bozuk plist’in boş başarı sayılmaması, başlangıç diski ve yeniden takılma korumaları kapsandı. Testin kendi disk imajında açık dosya çıkarma işlemini engelledi; dosya kapatıldığında native unmount/eject başarılı oldu. Gerçek USB donanımı ve arayüzde hızlı sıfırlama/sekme değiştirme kabul testi yapılmadı. Yerelleştirme kontrolü: **3.202 anahtar, 0 eksik/biçim uyuşmazlığı**.
- **Kurulum:** Paketleme ve derin/sıkı kod imzası kontrolü geçti. `/Applications/MacPocket.app` atomik olarak güncellendi; kurulu uygulama ikilisi derlemeyle eşleşti ve USB çıkarma sayfası açılarak çalıştırıldı. Canlı `macpocket-probe usb-eject` bu makinede boş liste döndürdü. Sürüm 0.1.3 korundu.

## Araç arayüzü kontrolü — 5 Kasım 2026

- **Envanter:** 57 katalog girişi, ekran kaynağı ve yönlendirmesiyle `.design/tool-ui-report.md` içinde ayrı ayrı kaydedildi. Ortak başlık/arama bileşenleri ve yüklenme/boş/hata/işlem/izin durumları tarandı. Yüksek öncelikli doğrulanmış eksikler uygulandı; tasarım sistemi ve sürüm numarası korundu.
- **Uygulanan:** Dar içerikte başlık eylemlerini alt satıra alma; Ses Çıkışı, Hızlı İşlemler, Ekran Temizleme ve Ekran Kaydı’nda kaydırma. USB/Thunderbolt, Disk Sağlığı, Bluetooth, Ağ Trafiği ve Başlangıç Öğeleri’nde gerçek ilerleme ve yenileme kilitleri; USB okuma hatası için yeniden deneme. Ses çıkışı geçiş hatası ve boş durum, son kısayol döngüsü öğesini koruma. Destek Raporu hazırlanırken eski raporun dışa aktarımını kilitleme ve kısmi veri uyarısı. Araçlar/Görev Yöneticisi/Sistem Raporları arama bağının doğrudan metin alanına verilmesi; Başlangıç Öğeleri’nde arama komutu. Yerel ağ kartları/harita cihazları native düğme; harita hareketi azaltılmış hareket tercihini izler.
- **Ekran kaydı:** Başlatma/kaydetme geçişlerinde eylemler kilitlenir; izin için Ayarlar’a gitme eylemi ve ilerleme görünür. Kaydedildi bildirimi yalnız kayıt çıkışının `recordingOutputDidFinishRecording` callback’i ve dosya varlığıyla üretilir. Hata veya gecikmiş eski callback yeni kaydın sonucunu ezmez. Gerçek ekran/ses/mikrofon kaydı bu turda yapılmadı.
- **Canlı:** İmzalı kurulu uygulamada 56 ekran × 960/1280 px = 112 Türkçe açılış, 14 değişen ekran × 2 genişlik + Uyanık Tut sheet’i × 2 = 30 İngilizce/koyu kayıt. Her ekranda uygulamanın kendi native erişilebilirlik nesneleri okundu. Üç arama yüzeyinde komut sonrası metin editörü odağı doğrulandı. Eski genel geometri kaydı doğrulanmış ölçüm kanıtından çıkarıldı; yeni Pratik Araçlar ölçümü kendi raporunda yer alır. Native ağaç okuması tam görsel/VoiceOver kabul testi sayılmaz. Uyanık Tut penceresi açıldı, oturum başlatılmadı. Kayıtlar `.build/tool-ui-audit*.json` altında; yönetici veya silme işlemi çalıştırılmadı.
- **Kontroller:** İlgili 73 test: 0 hata, 1 isteğe bağlı disk imajı testi atlandı. Yerelleştirme: 3.229 anahtar, 0 eksik çeviri/biçim uyuşmazlığı/kullanılmayan çeviri. Derleme ve kod imzası geçti. Donanım/izin akışlarının tümü, dolu haritada klavye, VoiceOver ve tam görsel karşılaştırma açık doğrulama kapsamıdır; raporda ayrı belirtildi.

## Pratik Araçlar — 5 Kasım 2026

- **Uygulanan:** Sol menüde ayrı çevrimdışı çalışma alanı; JSON, Base64, URL, JWT, hash, UUID, parola/token, Unix zamanı, metin farkı, QR/Wi-Fi QR ve 14 biçimli Case Converter olmak üzere 11 araç. Arama/favori, örnek veri, geçici taslaklar, ilerleme/iptal/hata, kopyalama, metin ve PNG dışa aktarma. Renk seçme/QR okuma ve ağ/MAC ekranlarına bağlantı. Girdi/sonuçlar otomatik kaydedilmez; yalnız favoriler ve seçilen araç kalıcıdır. Pano çıktıları geçici işaretlenir. Ayrıntılar `.design/practical-tools-report.md` içindedir.
- **Doğruluk:** JSON özgün sayı tokenlarını ve anahtar sırasını korur, fazladan son virgülü reddeder; Base64 kanonik bit/dolgu ve UTF-8 kontrolü yapar. JWT zaman durumları imza doğrulaması iddiası taşımaz. Rastgelelik Security’den alınır. Tarih normalleştirmesi takvim bileşenleriyle denetlenir; çalışma boyutu ve fark satır sayısı sınırlıdır.
- **Case Converter:** Türkçe/İngilizce kuralları, 300 ms beklemeli canlı önizleme, tüm 14 biçimi karşılaştırma ve tek tek/toplu kopyalama, satır satır dönüşüm, Latin-ASCII sadeleştirme, kısaltma ve sayı seçenekleri, metin istatistikleri. Girdi 64 KiB; önizlemeler toplamı 4 MiB ile sınırlı. Hazır biçim seçimi tekrar hesaplama yapmaz; bekleyen işler temizle/iptal ile durdurulur. Cümle biçimi noktalama temellidir; kod biçimleri her dil için tanımlayıcı doğrulaması yapmaz.
- **Kontroller:** 49 ilgili test, 0 hata; gerçek QR PNG üretme ve Vision ile Türkçe/emoji/Wi-Fi geri okuma. Türkçe/açık ve İngilizce/koyu, 960/1280 px genişliklerde 44 örnek sonuç ve her dilde 18 ek model/odak kontrolü başarılı. Dil başına 840 native çerçevede yatay taşma sezgisi 0 uyarı verdi. Yerelleştirme: 3.385 anahtar, 0 eksik/biçim uyuşmazlığı. Bunlar tam görsel/VoiceOver kabul testi sayılmaz; açık sınırlar raporda ayrı kaydedildi.
- **Derleme/kurulum:** Yeni paket başarıyla derlendi; derin/sıkı imza ve kurulu ikilinin eşleşmesi doğrulandı. `/Applications/MacPocket.app` normal tercihlerle Case Converter açık çalışıyor. Sürüm/build numarası korunur.


## Hava durumu kaynak sepeti — 9 Kasım 2026

- **Uygulanan:** Menü Çubuğu ayarları ve hava durumu açılır panelinde Kaynak Sepeti bulunur. Kullanıcı kaynakları onay kutularıyla ekler/çıkarır, Veri Kaynağı menüsünden etkin kaynağı seçer. En az bir kaynak kalır. Sepete eklemek arka planda her kaynağı sorgulamaz; kaynaklar kendiliğinden karıştırılmaz veya değiştirilmez.
- **Kapsam:** Anahtarsız Visual Crossing, MET Norway ve Open-Meteo; Open-Meteo üzerinden ayrı ECMWF IFS, ECMWF AIFS Single, GFS ve ICON seçenekleri. WeatherAPI.com, Pirate Weather, OpenWeather 2.5 mevcut hava + 5 gün/3 saat tahmin ve Tomorrow.io için kullanıcının kendi ücretsiz hesap anahtarı gerekir. Ücretli One Call veya dakika dakika yağış uçları çağrılmaz. Open-Meteo’nun ücretsiz sunucusu ticari olmayan kullanımla sınırlıdır; arayüzde hesap kotası ve koşul bağlantıları gösterilir.
- **Geçiş:** Yeni kurulumda etkin kaynak Visual Crossing’dir. Daha önce konum seçmiş kullanıcıların iStat bağlantısı korunur; kullanıcı istediğinde başka kaynağa geçer. Eski kurulum kimliği ücretsiz sağlayıcıların isteklerine eklenmez.
- **Durum ve yenileme:** Kaynak/konum değişiminde önceki istek iptal edilir ve gecikmiş yanıt yayımlanmaz. Önbellek kaynak ve konuma göre ayrıdır; kaynak değiştirerek veya elle yenileyerek tazelik sınırı aşılamaz. MET Norway için en az üç saat, diğerleri için bir saat ve daha ileri Expires zamanı uygulanır. Hata sonrası aynı kaynağın son başarılı verisi korunur; kaynak değişiminde başka kaynağın verisi gösterilmez. Kapalı modül ağ sorgusu veya yenileme zamanlayıcısı çalıştırmaz.
- **Veri anlamı:** Rüzgâr ortak modelde m/s’ye dönüştürülür, görünümde km/sa gösterilir. Eksik hissedilen sıcaklık, nem, simge veya tahmin sıfırla doldurulmaz. MET Norway ve OpenWeather günlük aralıkları mevcut tahmin örneklerinden hesaplanır; tam günlük ekstrem değerler gibi sunulmaz. MET Norway Türkiye verisi ECMWF tabanlıdır; bağımsız API sayısı bağımsız model sayısı olarak yorumlanmaz.
- **Anahtarlar:** Yalnız ilgili kaynak için Anahtar Zinciri girdisi okunur/yazılır. Tercihlere, dışa aktarıma, raporlara veya hata metinlerine anahtar yazılmaz. Arka plan okumaları kilit açma penceresi göstermez; erişim reddi arayüzde açıklanır.
- **Tekrarlama:** `MACPOCKET_WEATHER_LIVE=1 swift test --filter WeatherProviderTests` yalnız açık şehir koordinatlarıyla yedi anahtarsız seçeneğe gerçek istek gönderir. `scripts/audit-weather-basket.sh` ayrı tercih alanı ve ayrı Anahtar Zinciri ad alanında yerel arayüzü denetler. Çıktılar `.build/weather-basket/` altındadır. Dört anahtarlı sağlayıcının gerçek ücretsiz hesaplarıyla uçtan uca kabulü, kullanıcı anahtarları sağlanmadığından yapılmaz; yanıt dönüştürme ve hata akışı kontrollü örneklerle sınanır.
- **Kaynak belgeleri:** [Open-Meteo](https://open-meteo.com/en/docs), [AIFS](https://open-meteo.com/en/docs/ecmwf-api), [Visual Crossing](https://www.visualcrossing.com/resources/documentation/weather-api/free-weather-api-no-key/), [MET Norway](https://api.met.no/weatherapi/locationforecast/2.0/documentation), [WeatherAPI](https://www.weatherapi.com/docs/), [Pirate Weather](https://docs.pirateweather.net/en/latest/API/), [OpenWeather](https://openweathermap.org/api/forecast5), [Tomorrow.io](https://docs.tomorrow.io/reference/weather-forecast).
- **Doğrulanan:** Tam kök test grubunda 1.498 test, 0 hata, 6 isteğe bağlı atlama. Yedi anahtarsız seçenek İstanbul için gerçek veri döndürdü. Türkçe/açık ve İngilizce/koyu görünümde toplam 28 yerel kontrol geçti: onay kutusuyla kaynak ekleme/çıkarma, model ve hesap gruplarını açma, GFS seçeneğini sepete ekleme, kalıcılık, 368 px genişliği koruma, anahtar eksikliğinde başka kaynağın verisini göstermeme ve yalnız denetime ait Anahtar Zinciri girdisini kaydetme/okuma/silme. VoiceOver ve dört sağlayıcının gerçek kullanıcı API anahtarlarıyla kabulü yapılmadı.


### Hava durumu paneli görünümü

Tahmin görünümü ve Konum ve Kaynaklar ayarları panel içinde ayrılır. Üstte konum ve ayar düğmesi, altında Celsius sıcaklığı/koşul/hissedilen değer, nem-rüzgâr-basınç satırı, saatlik örnekler ve günlük sıcaklık aralıkları bulunur. Kaynak menüsü, atıflar, güncelleme zamanı ve yenileme düğmesi alttadır. Sıcaklık çubuklarının ortak ölçeği yalnız gösterilen günlerden hesaplanır; ayrı sağlayıcıların değerleri karıştırılmaz. Boş, yükleniyor, hata, eksik anahtar ve eksik tahmin durumları için ayrı görünüm ve uygun sonraki eylem vardır. Türkçe ve İngilizce yerel kabul kapsamı `.design/tool-ui-report.md` içinde kaydedilir.

### Saatlik tahmin ayrıntıları — 9 Kasım 2026

- **Uygulanan:** Saat kartı panel içinde ayrı ayrıntı sayfası açar; geri düğmesi tahmine döner. Tarih ve koşul yanında kaynağın bu saate ait hissedilen sıcaklık, nem, rüzgâr/hamle/yön, basınç, bulut örtüsü, yağış olasılığı/miktarı/şiddeti, görüş, UV ve çiy noktası varsa gösterilir. Seçili kaynak veya konum değişince saat seçimi temizlenir. Eksik alanlar mevcut hava değerleriyle veya sıfırla tamamlanmaz; yalnız sıcaklık veren kaynakta açıklama ve kaynak seçme eylemi bulunur.
- **Veri anlamı:** Open-Meteo yağışı önceki bir saatin, OpenWeather 2.5 yağışı önceki üç saatin toplamıdır. MET Norway için mevcut 1/6/12 saatlik sonraki dönem korunur. Diğer saatlik toplamlar dönem uzunluğuyla gösterilir. Pirate Weather yağış şiddeti ve Tomorrow.io yağmur şiddeti mm/sa olarak ayrı tutulur; saatlik miktara çevrilmez. WeatherAPI yağmur ve kar olasılıkları ayrı kalır. MET açık gökyüzü UV değeri normal UV ile karıştırılmaz. Görüş ortak modelde metre, görünümde km; rüzgâr m/s → km/sa olarak gösterilir.
- **Kontroller:** Sekiz yeni ayrıntı testi yedi yanıt biçimini, eksik/geçersiz değerleri, gerçek sıfırları, birim dönüşümlerini ve yağış dönemlerini sınar. Tam kök test grubunda 1.506 test, 0 hata, 6 isteğe bağlı atlama. İstanbul için yedi anahtarsız kaynağın tamamı gerçek saatlik ayrıntı döndürdü; dört anahtarlı sağlayıcı kontrollü yanıtlarla sınandı. Günlükler `.build/weather-hour-details/`, canlı kaynak özeti `.build/weather-basket/live-report.json` içindedir. Yerelleştirme: 4.518 anahtar, 0 eksik İngilizce çeviri, 0 biçim uyuşmazlığı.
- **Yerel arayüz:** Türkçe/açık ve İngilizce/koyu görünümde 31’er kontrol geçti; saat ayrıntısını açma/geri dönme, gerçek sağlayıcı alanları ve eksik saat verisi açıklaması doğrulandı. Son raporlar `.build/weather-basket/ui-{tr,en}/report.json` içindedir. VoiceOver kabulü yapılmadı.
- **Belgeler:** [Yağış dönemleri: Open-Meteo](https://open-meteo.com/en/docs), [MET ForecastJSON](https://docs.api.met.no/doc/ForecastJSON.html), [OpenWeather 5 gün](https://openweathermap.org/forecast5), [Pirate Weather alanları](https://docs.pirateweather.net/en/latest/API/data-blocks/), [Tomorrow.io birimleri](https://docs.tomorrow.io/reference/data-layers-core).

### Menü çubuğu panel geçişi — 9 Kasım 2026

- **Statik neden:** Önceki akış aynı olay içinde `performClose` ve `show` çağırıyordu. Animasyon sürerken `isShown` hâlâ doğru olduğundan açılış isteği atlanabiliyor; gecikmiş kapanış bildirimi de paylaşılan içeriği temizliyordu. Geçici panel mouse-down sırasında kapanmaya başlayabildiği için sonraki simgenin mouse-up eylemi bu aralığa denk gelebilir.
- **Uygulanan:** `StatusItemPopoverPresenter` paylaşılan panelin sahipliğini ve bekleyen hedefi tutar. Yeni içerik yalnız `popoverDidClose` tamamlanıp ana olay döngüsüne dönüldükten sonra açılır. Hızlı seçimlerde son hedef korunur; aynı hedefe tekrar tıklama bekleyen açılışı iptal eder. Sağ menü, simgelerin yeniden kurulması ve açık kapatma bekleyen geçişi temizler. İçerik ve simge vurgusu eski panel kapanırken bırakılır.
- **Yerel doğrulama:** `scripts/audit-status-popover.sh --skip-build` imzalı Debug uygulamada gerçek NSStatusBarButton ve NSPopover ile ayrı deneme simgeleri/panel şablonları kullanır. Animasyon açık/kapalı, hava durumu ↔ AI tek eylemle geçişi, aynı simgeyle kapatma/açma, kapanıştan sonra içeriğin kalması, hızlı seçim, geçici kapanışın eylemden önce başlaması, bekleyen geçişin iptali ve hızlı bakış isteği dahil 29 kontrol geçti. Uygulamanın kendi menü çubuğu pencerelerine gönderilen mouse-down/up olaylarında da tek tıkla açılma ve geçiş geçti. Kullanıcı tercihleri, gerçek API anahtarları ve hesaplar kullanılmaz; fiziksel fare testi veya gerçek AI hesap verileriyle kabul iddia edilmez. Rapor `.build/status-popover/runtime.json` içindedir.
- **Diğer kontroller:** 118 uygulama testi, 0 hata, 1 isteğe bağlı donanım atlaması. İmzalı Debug derleme ve sıkı kod imzası kontrolü geçti. Yerelleştirme kapısı 4.518 anahtarda 0 eksik İngilizce çeviri ve 0 biçim uyuşmazlığıyla geçti. Sürüm/build numarası korunur.

### Menü çubuğu gecikmesinin azaltılması — 9 Kasım 2026

Bu bölüm animasyonsuz ara denemenin kaydıdır; güncel uygulama aşağıdaki animasyonlu geçişi kullanır. Önceki ham ölçüm `.build/status-popover/animations-disabled-runtime.json` içinde korunur.

- **Araştırma:** Apple’ın [NSPopover.animates](https://developer.apple.com/documentation/appkit/nspopover/animates) belgesi açılış, kapanış ve içerik/boyut değişimlerinin animasyon uygulayabildiğini açıklar. [NSPopover bildirimleri](https://developer.apple.com/documentation/appkit/nspopover) `didShow` ve `didClose` bildirimlerinin ilgili animasyon tamamlandığında gönderildiğini belirtir. [SwiftUI performans rehberi](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) ölçülen darboğaza odaklanmayı ve gereksiz görünüm güncellemelerini azaltmayı önerir.
- **Uygulanan:** Menü çubuğunun paylaşılan panelinde `animates = false`. Önceki tek tık düzeltmesindeki kapanış bildirimi sıralaması korunur, ancak ardışık kapanış/açılış animasyonları beklenmez. Bar panelleri menüler gibi doğrudan açılır/kapanır. Gizli SwiftUI görünümlerini canlı tutan bir önbellek eklenmedi.
- **Ölçüm:** Aynı imzalı Debug uygulamada, aynı gerçek NSStatusBarButton/NSPopover ve basit yerel deneme içeriğiyle animasyon açık/kapalı karşılaştırıldı. Durum düğmesi eyleminden `NSPopover.didShowNotification` bildirimine kadar ölçülen dokuz geçişin ortancası **1.044,83 ms → 12,30 ms** oldu. Açık animasyonda aralık 1.039,29–1.057,56 ms, kapalıyken 4,24–30,66 ms. Bu bir AppKit geçiş ölçümüdür; gerçek AI hesapları veya ağdan gelen hava durumu içeriğinin tüm oluşturma süresini kapsadığı iddia edilmez. Ağ/API süresi ölçüme dahil değildir. Ham kayıtlar `.build/status-popover/runtime.json` içindeki `timings` alanındadır.
- **Kabul:** Animasyon açık/kapalı davranışları ve 20 zamanlı açılış/geçiş dahil 49 yerel kontrol geçti. Tek tıkla panel değiştirme, hızlı seçim, aynı simgeyle kapatma, kapanan panelin yeni içeriği temizlememesi ve uygulamanın kendi menü çubuğu penceresine gönderilen mouse olayları doğrulandı. İmzalı Debug derleme geçti; yerelleştirme 4.518 anahtarda 0 eksik çeviri/biçim uyuşmazlığı. Sürüm/build korunur.

### Açık panelde animasyonlu geçiş — 9 Kasım 2026

- **Uygulanan:** İlk açılış, kapanış ve içerik/boyut değişiminde AppKit animasyonları açıktır; uygulama veya sistem Hareketi Azalt tercihi etkinse kapatılır. Açık panelde başka bir simge seçilince içerik ve `show(relativeTo:of:preferredEdge:)` ile bağlanan simge değiştirilir. Geçiş kapatma/açma döngüsüne girmez. [Apple API sözleşmesi](https://developer.apple.com/documentation/appkit/nspopover/show%28relativeto%3Aof%3Apreferrededge%3A%29) açık panelin yeni görünüme bağlanmasını destekler.
- **Fare davranışı:** `popoverShouldClose` yalnız başka bir MacPocket simgesine yapılan birincil tıklama için geçici kapanışı önler. Mevcut simgeye tıklama, dışarı tıklama ve Escape kapatır. Global mouse-down sırasında önce canlı imleç/tuş durumu kontrol edilir; uygulamanın önceki tıklamadan kalan `currentEvent` değeri dışarı tıklamayı engellemez. Gerçek bir kapanış zaten sürüyorsa bekleyen son seçim kapanış sonrasında açılır. Yeni içerik boyutu görünümün ideal boyutundan alınır; önceki panel yüksekliği taşınmaz.
- **Yerel kabul:** `scripts/audit-status-popover.sh --skip-build` ile 58 kontrol geçti: animasyon açık/kapalı, aynı NSWindow ile sıfır kapanışlı geçiş, farklı içerik yüksekliği, AppKit ve SwiftUI deneme içeriği, hızlı seçim, kendi status penceresine gönderilen gerçek AppKit mouse olaylarıyla geçiş/aynı simgeyle kapatma, dışarı tıklama ve Escape. Deneme paneli ve simgeler ayrı oluşturulur; gerçek hesap veya anahtar okunmaz. Fiziksel fare ve gerçek hava/AI verisinin tüm çizim süresi için kabul iddia edilmez. Ön girişte uygulamanın etkinlik durumu raporda bilgi olarak kaydedilir; hedef pencerelere yerel olayların teslim edilmesi ayrıca sınanır.
- **Ölçüm:** Animasyon açıkken dokuz geçişte yeni hedef görünümün aynı görünür pencereye bağlanma ortancası **49,02 ms** (47,75–57,86 ms); bütün geçişlerde pencere aynı kaldı ve kapanış sayısı sıfırdı. Bu süre animasyonun bitişi değildir; önceki bölümdeki `didShow` bitiş ölçümüyle hız çarpanı hesaplanmaz. İlk açılış hâlâ `didShow` ile, geçişler `target-view-attached` sınırıyla kaydedilir. Ham veriler `.build/status-popover/runtime.json`, günlük `.build/status-popover/retarget-runtime.log` içindedir.
- **Kontroller:** 118 uygulama testi, 0 hata, 1 isteğe bağlı atlama. İmzalı Debug derleme ve kod imzası doğrulandı. Yerelleştirme 4.518 anahtarda 0 eksik çeviri/biçim uyuşmazlığı. Sürüm/build korunur.

### Küçük canlı grafiklerin çizim maliyeti — 9 Kasım 2026

- **Profil:** Çalışan Debug uygulama 8 saniye, gizli durumdayken 6 saniye örneklendi; kayıtlarda SwiftUI/Charts yerleşim ve çizim işi ile sıcaklık I/O okumaları görüldü. Ana pencere başlangıçta açıktı; ilk anlık CPU değeri boşta kullanım olarak değerlendirilmedi. Kayıtlar `.build/performance/{before,before-hidden}.sample.txt` ve `before-*-top.txt` içindedir. Bu incelemeden tüm uygulama için bir CPU veya bellek azalma oranı çıkarılmaz.
- **Uygulanan:** `PocketSparkline`, örnek başına AreaMark/LineMark yerine tek Canvas üzerinde alan ve çizgi yolları çizer. Monoton kübik eğri kontrol noktaları komşu değer aralığında kalır; eğri örnekler arasında taşmaz. Dolgu, çizgi kalınlığı, negatif RSSI alanı ve otomatik üst sınır korunur. Sonlu olmayan değerler çizilmez; geçerli örneklerin zaman konumu korunur. Önceden de dekoratif/erişilebilirlikten gizli olan bu grafiklerin yanında okunan sayılar kalır. [Apple Canvas belgesi](https://developer.apple.com/documentation/swiftui/canvas) dinamik, metin ve etkileşim gerektirmeyen çizimlerde bu yöntemi önerir.
- **Aynı koşullarda karşılaştırma:** `MACPOCKET_SPARKLINE_BENCHMARK=1 swift test --filter 'SparklineCurveTests|SparklineRenderingTests'`. Önceki renderer yalnız testte referans olarak tutulur. Aynı Debug XCTest sürecinde üç grafik × 60 örnek, 2× ölçekte ImageRenderer içerik güncellemesinden eşzamanlı CGImage üretimine kadar ölçülür. İlk beş çizim dışarıda bırakılır; her yol için 40 ölçüm alınır. Son ölçümde ortanca **3,659 ms → 0,210 ms**, p95 **3,728 ms → 0,292 ms**; çizim mikrotestinde yaklaşık 17 kat iyileşme. Bu oran uygulamanın toplam CPU, enerji veya bellek kullanımı için geçerli sayılmaz.
- **Görsel/doğruluk kabulü:** Referans ve yeni PNG görselleri `.build/performance/sparklines/{reference,optimized}.png` içinde incelendi. Matematik testleri uç değerleri, sabit/artan/azalan/dalgalı serileri, negatif ve otomatik ölçekleri, boş/tek/geçersiz örnekleri ve taşmayan kontrol noktalarını sınar. Çizim testi 720×288 görüntü boyutunu, renkli pikselleri ve yeni örnekle piksel içeriğinin değişmesini doğrular. Son ham süreler `benchmark.json` içindedir.
- **Kontroller:** Tam kök grupta 1.513 test, 0 hata, 6 isteğe bağlı atlama; son ek çizim kontrolünde 7 test, 0 hata. Yerelleştirme 4.517 anahtarda 0 eksik İngilizce çeviri ve 0 biçim uyuşmazlığı. Sensör ve menü çubuğu yenileme süreleri değişmez. Normal kullanım için optimize Release paketi hazırlandı ve kod imzası doğrulandı; sürüm/build numarası korunur.

### Görünürlük gerektiren süreç taraması — 9 Kasım 2026

- **Sorun:** Ana pencerenin görünürlüğü yalnız SwiftUI `onAppear/onDisappear` ile tutuluyordu. Uygulamayı gizlemek, pencereyi küçültmek veya tamamen örtmek bu görünümün kaybolmasını garanti etmez; Görev Yöneticisi için süreç taraması arka planda devam edebilirdi. Ayrıca genel `refresh()` çağrıları başlangıçta ve süreç verisi kullanmayan sayfalarda da süreç listesini okuyordu.
- **Uygulanan:** `MainWindowVisibility` yalnız kendi penceresinin occlusion, küçültme/geri getirme, kapatma ve uygulamanın gizleme/gösterme bildirimlerini izler; zamanlayıcı kurmaz. `PocketModel` otomatik süreç talebini görünür Görev Yöneticisi veya açık menü çubuğu süreç paneli üzerinden hesaplar. Genel yenileme artık bu talebi izler. Rapor/port işlemlerinin açık `includeProcesses: true` istekleri korunur. Sistem telemetrisi, uyarılar, güç geçmişi ve menü çubuğu yenilemeleri sürer.
- **Yeniden gösterme ve eşzamanlılık:** Pencere görünür olduğunda yeni süreç talebi hemen yenileme başlatır. Devam eden sistem okumasından sonra görünürlük tekrar değerlendirilir. Bu sırada gelen istekler birleştirilir; süreç okuması başladıktan sonra gelen yeni talep tek takip okumasıyla karşılanır. Kullanıcı tekrar gizlerse bekleyen otomatik istek çalışmaz. Kullanıcının duraklatma tercihi otomatik yeniden başlamayı engeller.
- **Kontrollü doğrulama:** Yedi testte ayrı süreç/sistem okuyucuları ve geçici güç geçmişi kullanılır. Gizli Görev Yöneticisi için üç sistem yenilemesinde **0 süreç okuması**, açık menü çubuğu süreç paneli için üç yenilemede **3 süreç okuması** doğrulandı. Görünürlükte anında başlatma, gizlemede durma, açık rapor isteği, duraklatma ve gecikmiş okuma yarışları sınandı. Bunlar kontrollü çağrı sayılarıdır; toplam CPU tasarrufu yüzdesi olarak sunulmaz.
- **Gerçek macOS penceresi:** `scripts/audit-window-visibility.sh`, üretimdeki aynı gözlemciyi ayrı bir deneme uygulamasında derler. Gösterme, orderOut/geri getirme, küçültme/geri yükleme, tamamen örtme/açma, uygulamayı gizleme/gösterme ve kapatma olmak üzere **10 native kontrol geçti**. Üretimle aynı 1×1 pt, hit-test almayan bağlantı kullanılır. Yalnız denemenin kendi pencereleri yönetilir; MacPocket tercihleri değiştirilmez. Rapor `.build/background-performance/visibility.json`, günlük `native.log` içindedir. Gerçek pencere bildirimleri ve kontrollü okuyucu politikası ayrı doğrulanır; fiziksel Space/tam ekran kabulü iddia edilmez.
- **Tekrarlama ve kapsam:** `swift test --filter ProcessSamplingDemandTests`; tam kök grupta **1.520 test, 0 hata, 6 isteğe bağlı atlama**. Son menü çubuğu bağlantısının ardından 132 uygulama testi de 0 hata, 1 isteğe bağlı atlama ile geçti; mevcut sistem okuması sırasında açılan menü panelinin isteğinin kaybolmaması ayrıca sınandı. Yerelleştirme **4.517 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. [Apple görünürlük ve enerji rehberi](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html) doğrultusunda pencereye özel iş görünürlüğe bağlanır. Optimize Release paketi mevcut 0.1.6 / 9 üzerinde hazırlandı ve kod imzası doğrulandı.

### Yinelenen yayınlar ve son tarihli arayüz güncellemesi — 9 Kasım 2026

- **Apple araştırması:** [SwiftUI performans rehberi](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) gereksiz model yayınlarının ve sık görünüm güncellemelerinin azaltılmasını; [zamanlayıcı rehberi](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html) gereksiz periyodik işlerin kaldırılmasını önerir. [View.task(id:)](https://developer.apple.com/documentation/swiftui/view/task%28id%3Aname%3Apriority%3Afile%3Aline%3A_%3A%29) kimlik değişiminde bekleyen işi iptal edip yeniden başlatır; işin yaşamı görünümün yaşamına bağlanır.
- **Geçmiş tamponları:** Menü çubuğu (90 örnek) ve sistem (150 örnek) geçmişi doluyken önce ekleme, ardından kırpma ayrı ayrı `@Published` yayını yapıyordu. Yerel kopyada ekleme/kırpma tamamlanıp tek atama yapılır. Eski kod üzerinde regresyon testleriyle 20 ölçümde 40 yayın ve ara 91/151 elemanlı değerler doğrulandı; yeni kodda 20 yayın ve sürekli 90/150 sınırı doğrulandı. Aynı menü örneğinin tekrar kaydedilmesi yayın üretmez. Ölçüm frekansı, saklanan örnekler ve sıralama korunur. Bu, ilgili geçmiş yayınlarında %50 azalmadır; tüm uygulamanın CPU veya çizim sayısı için aynı oran iddia edilmez.
- **Hava durumu düğmesi:** Saniyelik `TimelineView` yerine `DeadlineRefreshView`, `nextRefreshAt` için tek iptal edilebilir asenkron bekleme kurar. Son tarih değişirse eski bekleme iptal edilir; kapanan görünüm beklemeyi bırakır. Süre verilmemiş veya zaten geçmişse periyodik iş kurulmaz. Düğme saat dolduğunda etkinleşir. Özellikle hata sonrasındaki 60 saniyelik manuel yeniden deneme hakkı, daha ilerideki otomatik API yenilemesini beklemeden korunur. Ağ isteği hâlâ servisin gerçek saat/kota denetiminden geçer; arayüz tarihi bu sınırı aşamaz.
- **Gerçek SwiftUI kontrolü:** `scripts/audit-deadline-timeline.sh` üretimdeki aynı bileşeni ayrı deneme uygulamasında derler. İlk 3,4 saniyede periyodik referans dört tarih bağlamı, yeni bileşen yalnız başlangıç ve süre dolumu için iki bağlam üretti. Süresiz/geçmiş tarih bir kez çizildi. Yeni sürenin eski beklemeyi iptal etmesi, yeni sürenin yalnız bir kez çalışması ve kaldırılan görünümün yeniden güncellenmemesi dahil **9 native kontrol geçti**. Bunlar görünüm bağlamı sayılarıdır; donanım uyanması veya pil tüketimi ölçümü değildir. Tercih veya gerçek API anahtarı kullanılmaz; rapor `.build/updates-performance/deadline.json` içindedir.
- **Tekrarlama:** `swift test --filter 'HistoryPublicationTests|WeatherServiceTests'`. Eski/yeni yayın karşılaştırması `baseline-tests.log` ve `tests.log`; tam kök grupta **1.525 test, 0 hata, 6 isteğe bağlı atlama**. Yerelleştirme **4.517 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. Kayıtlar `.build/updates-performance/` içindedir. Sürüm/build mevcut 0.1.6 / 9 olarak korunur.

### GPU kayıt tablosunun daraltılmış okunması — 9 Kasım 2026

- **Apple araştırması ve statik bulgu:** [IORegistryEntryCreateCFProperty](https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty) tek bir özelliğin anlık kopyasını döndürür; oluşturulan nesnenin sahipliği çağırana aittir. Önceki örnekleyici her GPU için tüm sürücü özellik tablosunu kopyalıyor, yalnız `PerformanceStatistics`, `model` ve `gpu-core-count` alanlarını kullanıyordu. [Apple CPU işi rehberi](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently) doğrultusunda gereksiz kopyalama azaltıldı.
- **Uygulanan:** Üç alan ayrı okunur; Core Foundation sahipliği `takeRetainedValue()` ile yönetilir. GPU listesi, kullanım değerleri ve model/çekirdek bilgileri her ölçümde yeniden okunur. Canlı değer veya aygıt tanıtıcısı önbelleği eklenmez. Mevcut ayrıştırıcı, en yoğun GPU seçimi ve I/O nesnelerini serbest bırakma akışı korunur.
- **Gerçek donanım ölçümü:** `scripts/benchmark-gpu-sampler.sh` üretimdeki aynı kaynak dosyayı `swiftc -O` ile derler. Eski yöntem yalnız karşılaştırma aracında tutulur. Mac Studio (Mac16,11) üzerinde beş ısınma çifti ardından sırası dönüşümlü 80 çift ölçümde ortanca **1,000 ms → 0,038 ms**, p95 **1,353 ms → 0,064 ms** oldu. Aralık; aygıt listeleme, özellik kopyalama, ayrıştırma ve GPU seçimini kapsar. Yaklaşık 26 kat oran yalnız bu okuma mikrotestine aittir; toplam uygulama CPU/enerji tüketimi veya GPU çizim hızı için geçerli sayılmaz. Her iki yöntemde okunabilir GPU, geçerli kullanım aralığı ve eşleşen model/çekirdek bilgileri doğrulandı. Ardışık canlı kullanım yüzdelerinin eşit olması beklenmez.
- **Kontrollü doğruluk ve kapsam:** Dört yeni test aynı girdide eski ayrıştırıcıyla eşdeğerliği, ilgisiz büyük alanların okunmamasını, eksik/geçersiz istatistikleri, gerçek sıfırı, isteğe bağlı model bilgilerini ve sonraki ölçümde değişen değerlerin yeniden okunmasını sınar. İlgili mevcut testlerle birlikte 14 kontrol geçti. Tam kök grupta **1.529 test, 0 hata, 6 isteğe bağlı atlama**; yerelleştirmede **4.517 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. İmzalı Release paketi ve sıkı kod imzası kontrolü geçti. Intel veya harici GPU üzerinde fiziksel kabul yapılmadı. Sürüm/build mevcut 0.1.6 / 9 olarak korunur.
- **Tekrarlama:** `swift test --filter 'GPUSamplerTests|MenuBarExtrasTests'` ve `scripts/benchmark-gpu-sampler.sh`. Ham ölçümler `.build/hardware-performance/gpu.json`; günlükler aynı dizindeki `native.log`, `gpu-tests.log`, `full-tests.log`, `localization.log` ve `release-build.log` dosyalarındadır.

### Fan panelinde gereksiz sıcaklık okumaları ve ana iş parçacığı — 9 Kasım 2026

- **Apple araştırması:** [Yanıt verebilirlik rehberi](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), arayüz gerektirmeyen eşzamanlı I/O işinin ana iş parçacığında yapılmamasını önerir; yalnız `Task` içine almak MainActor bağlamını değiştirmez. [Zamanlayıcı rehberi](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html) gerekmeyen periyodik işin iptal edilmesini önerir.
- **Statik neden ve gerçek okuma maliyeti:** `FanControlService.apply` profili değerlendirmeden önce MainActor üzerinde tüm sıcaklık sensörlerini okuyordu. Bu nedenle yardımcı hazırken panelin otomatik/sabit profili de her iki saniyelik turda fazladan okuma yapabiliyordu. Ayrıca gizli panelde manuel profilden otomatiğe dönmek döngüyü sonlandırmıyordu. Mac Studio üzerinde üretimdeki `TemperatureSensor` kaynağı `swiftc -O` ile derlenerek 15 kez okundu: 70 hizmetten 64 geçerli değer alındı, okuma ortancası **84,331 ms** oldu. Bu sensör okumasının süresidir; tüm uygulamanın CPU kullanımı veya ölçülmüş kullanıcı etkileşim gecikmesi değildir. Yerel inceleme aracı ve çıktılar `.build/thermal-performance/` içindedir.
- **Uygulanan:** Uygulama tarafındaki ek sıcaklık okuması yalnız eğri profilinde yapılır. `FanTemperatureReader` ayrı actor üzerinde okumaları sıralar ve HID okuyucusunu ilk ihtiyaçta oluşturur. Otomatik/sabit profiller bu okuyucuyu çağırmaz. Asenkron yanıt geldiğinde seçilen profil tekrar doğrulanır; eski eğri veya hedef yeni profile uygulanmaz. Otomatiğe geçiş, hedef yanıtı beklerken bile sisteme bırakma isteğini saklar. Gizli panel bu isteği tamamlayınca döngüyü durdurur; görünür panel fan devrini göstermeye, gizli manuel profil kalp atışı göndermeye devam eder. Ayrıcalıklı yardımcının bağımsız sıcaklık denetimi, hedef doğrulaması ve zaman aşımı değiştirilmedi; gerçek fan ayarı yapılmadı.
- **Kontrollü kabul:** `swift test --filter FanControlSamplingTests` ile yedi test geçti. Ayrı tercih alanı ve sahte XPC yardımcısıyla otomatik/sabit profilde **0 ek sıcaklık okuması**, gizli manuel profilin kalp atışı, iki eğri turunda iki taze okuma ve doğru hedefler, eksik sıcaklıkta sisteme bırakma, sıcaklık/hedef yanıtı beklerken otomatiğe geçme ve gizli döngünün durması sınandı. Durdurulduktan sonra 2,1 saniye daha beklenerek yeni durum sorgusu yapılmadığı doğrulandı. Gerçek `FanTemperatureReader` actor içindeki okuyucu kapanışının ana iş parçacığında çalışmadığı ayrıca sınandı. Bunlar kontrollü çağrı ve yürütme kontrolleridir; fiziksel fan eğrisi kabulü veya toplam enerji tasarrufu yüzdesi iddia edilmez. Günlükler `.build/fan-performance/` içindedir.
- **Son kontroller:** Tam kök grupta **1.536 test, 0 hata, 6 isteğe bağlı atlama**. Yerelleştirme **4.517 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. Optimize Release paketi ve sıkı kod imzası doğrulaması geçti. Sürüm/build mevcut 0.1.6 / 9 olarak korunur.

### USB Çıkarma sayfasında olayla yenileme — 9 Kasım 2026

- **Apple araştırması ve statik neden:** [Disk Arbitration bildirim rehberi](https://developer.apple.com/library/archive/documentation/DriversKernelHardware/Conceptual/DiskArbitrationProgGuide/ArbitrationBasics/ArbitrationBasics.html), aygıt/bölüm görünmesi, kaybolması ve açıklama değişikliği bildirimlerini, GCD kuyruğuyla oturum planlamayı ve abonelikleri kaldırmayı tanımlar. [Apple zamanlayıcı rehberi](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html) durum değişikliklerini periyodik sorgulamak yerine bildirimle izlemeyi önerir. Önceki sayfa üç saniyede bir disk listesini yüklüyordu: harici disk yokken bile her turda bir `diskutil`, disk varken ek topoloji/kök disk/aygıt sorguları başlatılıyordu.
- **Uygulanan:** `DiskChangeObservation` yalnız appeared/disappeared/description-changed bildirimlerini kaydeder; onay, bağlama veya çıkarma işlemi yapmaz. Ana Dispatch kuyruğundaki bildirimler 150 ms tek seferlik beklemeyle birleştirilir. Başlangıç keşfi aynı akışa katılır. `USBEjectModel` kapasitesi bir olan AsyncStream üzerinden değişiklik geldikçe okur. Sabit durumda önceki 20/dakika periyodik yenileme kaldırılır; bu bir toplam CPU veya enerji tasarrufu yüzdesi değildir. Disk Arbitration oturumu oluşturulamazsa üç saniyelik eski yöntem yedek olarak sürer. Manuel Yenile ve çıkarma sonrasındaki açık yenileme korunur.
- **Yarışlar ve yaşam döngüsü:** Okuma sürerken gelen bildirimler tek takip okumasında güncel listeye uygulanır. Manuel yenilemeyle çakışan bildirim ve iptal edilmiş eski okuma sırasında yeniden açılan sayfanın ilk isteği kaybolmaz. Yeni kimlikle aynı BSD adını kullanan disk eski seçim/genişletme durumunu devralmaz. Sayfa görevi iptal edildiğinde akış biter; tek seferlik bekleme iptal edilir, oturum kuyruktan çıkarılır ve aynı C callback/context çiftleriyle üç abonelik kaldırılır.
- **Kontrollü model kabulü:** `swift test --filter USBEjectObservationTests` ile **6 test geçti**. Değişmeyen listede 3,2 saniye boyunca yalnız ilk okuma yapıldı. Bekleyen okumada 100 olay tek takip okumasına dönüştü. Kimliği değişen disk, manuel okuma sırasında bildirim, iptal/yeniden açılma yarışı ve bildirim kurulamazken periyodik yedek ayrıca sınandı. Sahte disk listeleri kullanılır; gerçek diske çıkarma isteği gönderilmez.
- **Gerçek macOS kabulü:** `scripts/audit-disk-changes.sh` üretimdeki aynı gözlemciyi optimize ayrı uygulamada derler. İlk keşif, 3,2 saniyelik sessiz aralıkta tekrarsızlık, yalnız denetim için oluşturulan 64 MB seyrek APFS imajını bağlama, birimini yeniden adlandırma, ayırma, durdurma ve yeniden başlatma dahil **8 native kontrol geçti**. Denetimin kendi imajı normal yolla ayrıldı ve kendi geçici dizini temizlendi; mevcut kullanıcı diskleri değiştirilmedi. Bu, Disk Arbitration olaylarının canlı doğrulamasıdır; fiziksel USB kablosu çıkarma veya dolu bir diskte güvenli çıkarma kabulü değildir. Rapor `.build/disk-events-performance/native.json`, günlükler aynı dizindedir.
- **Son kontroller:** Tam kök grupta **1.542 test, 0 hata, 6 isteğe bağlı atlama**. Yerelleştirme **4.517 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. Optimize Release paketi ve sıkı kod imzası doğrulaması geçti. Sürüm/build mevcut 0.1.6 / 9 olarak korunur.

### Uygulama kalıntılarında kurulu kimlik eşleştirmesi — 9 Kasım 2026

- **Apple araştırması ve statik neden:** Apple, [Set.contains(where:)](https://developer.apple.com/documentation/swift/set/contains%28where%3A%29) için O(n), [Set.contains(_:)](https://developer.apple.com/documentation/swift/set/contains%28_%3A%29) için O(1) karmaşıklık belirtir. Kalıntı taraması her adayda kurulu kimlik kümesinin tamamını koşulla dolaşıyor; eşitlik ve kimlik + nokta/tire öneklerini deniyordu. Kurulu uygulama sayısı arttıkça her adayın eşleştirme işi de büyüyordu.
- **Uygulanan:** `InstalledBundleIndex` kurulu kimlikleri tarama başında bir kez küçük harfe çevirip kümeye alır. Aday için tam kimlik ve yalnız nokta/tire sınırlarında biten önekler kümeden sorgulanır. Büyük/küçük harf, nokta ve tireyle ayrılmış iç içe yardımcılar korunur. Örneğin kurulu `com.example.app`, `com.example.app.Helper` öğesini korur; `com.example.app2` veya `com.example.application` öğesini gizlemez. Aynı üretici uyarısı, dosya kimliği/simgesel bağ kontrolleri, yedi kaynak konum, tarama sınırları ve açık silme onayı akışı değişmez. Kalıcı bir kurulu uygulama önbelleği eklenmez; her tarama verilen envanterle yeni indeks oluşturur.
- **Ölçüm:** `scripts/benchmark-bundle-index.sh` üretimdeki aynı indeks kaynağını `swiftc -O` ile derler; eski koşul yalnız karşılaştırma aracında tutulur. 500 kurulu kimlik ve 5.000 kontrollü adayda üç ısınma çifti sonrası dönüşümlü sırayla 15 çift ölçüm alındı. Kurulum, küçük harfe çevirme ve eşleştirme dahil ortanca **186,674 ms → 3,499 ms**, p95 **191,810 ms → 4,143 ms** oldu. Bu Mac’te bu girdilerle yaklaşık 53 kat iyileşme yalnız kimlik eşleştirmesine aittir; dosya I/O’su, toplam tarama süresi veya tüm uygulama CPU kullanımı için aynı oran iddia edilmez. Tüm karşılaştırmalarda 5.000 sonuç birebir aynı, 2.500 aday eşleşti. Ham süreler `.build/bundle-index-performance/benchmark.json` içindedir.
- **Kontrollü doğruluk:** Dört yeni test tam kimlik/ayırıcı sınırlarını, benzer başlangıçlı farklı uygulamaları, boş ve alışılmadık kimliklerde eski davranışı, Unicode/büyük-küçük harfi ve üretilmiş 960 adayda eski koşulla eşdeğerliği sınar. Geçici gerçek dizinlerde yedi konumun tamamı taranarak kalan adaylar, aynı üretici uyarısı ve dosya kimliği doğrulandı. İlgili mevcut testlerle birlikte **21 test, 0 hata**. Kullanıcının Library dizininde silme veya taşıma işlemi yapılmadı. Tekrarlama: `swift test --filter 'InstalledBundleIndexTests|ApplicationLeftoversTests|ApplicationServicesTests|FileServicesTests'`; günlükler `.build/bundle-index-performance/` içindedir.
- **Son kontroller:** Tam kök grupta **1.546 test, 0 hata, 6 isteğe bağlı atlama**. Yerelleştirme **4.517 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. Optimize Release paketi ve sıkı kod imzası doğrulaması geçti. Sürüm/build mevcut 0.1.6 / 9 olarak korunur.

### Değişmemiş pano geçmişinde gereksiz disk yazımları — 9 Kasım 2026

- **Apple araştırması ve statik neden:** [Apple disk yazımı rehberi](https://developer.apple.com/documentation/xcode/reducing-disk-writes) gereksiz yazma işlemlerini kaldırmayı; [yanıt verebilirlik rehberi](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) ana iş parçacığında eşzamanlı I/O işini azaltmayı önerir. `ClipboardService.flushSave` daha önce diskte saklama açıkken her çağrıda JSON kodlama/atomik yazma yapıyordu. Başlangıçtaki değişikliksiz sınır uygulaması da kayıt planlıyor; durdurma/kapanış yolu aynı geçmişi yeniden yazıyordu. Yükleme yapılmamış bir servis durdurulduğunda bellekteki boş geçmişin diske yazılması da mümkündü.
- **Uygulanan:** Geçmişin gerçekten değişmesi bekleyen kayıt işaretini ayarlar. Başarılı yükleme/kayıt veya tüm arşivin silinmesi işareti temizler. Sınır uygulama, aynı sabitleme değeri, bulunmayan öğeyi silme veya yalnız sabitlenmişleri koruyarak temizleme içerikte değişiklik yapmazsa kayıt planlanmaz. `flushSave` değişiklik yoksa kodlama/yazmayı atlar; ilk kez yüklenmemiş geçmişi de yazmaz. Başarısız kayıt işareti temizlemez, sonraki açık kayıt tekrar dener. Diskte saklama yeniden açılırken mevcut bellek geçmişi zorunlu kaydedilir. Mevcut bir saniyelik birleştirme, atomik dosya yazımı ve 0600/0700 izinleri korunur. Gerçek değişiklikteki dosya I/O’su hâlâ eşzamanlıdır; tüm pano depolamasının arka plana taşındığı iddia edilmez.
- **Kontrollü gerçek dosya karşılaştırması:** 200 öğeli geçici arşivde önceki `archive.save(history)` davranışı dört kez çalıştırıldı; dosya kimlikleriyle dört atomik dosya yenilemesi doğrulandı. Aynı geçmiş yüklenip yeni servisin `flushSave` yolu dört kez çağrıldığında **0 dosya yenilemesi** oldu ve okunan geçmiş aynı kaldı. Bu, değişmemiş dört çağrıdaki yazma sayısıdır; fiziksel SSD blokları, toplam uygulama yazımları veya enerji tüketimi için bir yüzde değildir.
- **Kabul:** `swift test --filter 'ClipboardPersistenceTests|ClipboardArchiveTests|ClipboardHistoryTests'` ile **18 test, 0 hata**. Altı yeni uygulama testi; yüklenmemiş geçmişin korunması, değişikliksiz kayıtlar, gerçek sabitleme/bağlantı temizleme/silme, kayıt hatasından sonra yeniden deneme, bellek/diske saklama geçişinde görsel verisinin korunması ve tümünü sildikten sonra boş arşivin oluşturulmamasını sınar. Yalnız geçici dizin, ayrı tercih alanı ve adlandırılmış deneme panosu kullanılır; kullanıcının genel panosu okunmaz/yazılmaz. Günlükler `.build/clipboard-save-performance/` içindedir.
- **Son kontroller:** Tam kök grupta **1.552 test, 0 hata, 6 isteğe bağlı atlama**. Yerelleştirme **4.517 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. Optimize Release paketi ve sıkı kod imzası doğrulaması geçti. Sürüm/build mevcut 0.1.6 / 9 olarak korunur.

### Uzun pano metinlerinin başlık hesabı — 9 Kasım 2026

- **Apple araştırması ve statik neden:** [SwiftUI performans rehberi](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) sık hesaplanan görünüm gövdelerinde pahalı işlemleri azaltmayı önerir. [Swift String belgesi](https://developer.apple.com/documentation/swift/string) `split` sonucunun alt dizilerden oluşan bir dizi olduğunu ve Unicode karakter modelini açıklar. Pano satırının kullandığı `ClipboardItem.title`, yalnız ilk dolu satırı göstermek için önce metnin tamamını `split` ile ayırıyordu; uzun günlüklerin görünmeyen devamı da her başlık hesabında işleniyordu.
- **Uygulanan:** `ClipboardTextPreview` satır sonunu bulur, aynı boşluk temizliğini uygular ve ilk dolu satırda döner. Tüm satırlar için bir dizi oluşturmaz. CRLF dahil `Character.isNewline` davranışı, Unicode karakterler, 200 karakter sınırı ve yalnız boş satırlardan oluşan metnin önceki geri dönüşü korunur. Kaydedilen metin, tam metin araması, kopyalama, bağlantı/görsel/dosya başlıkları değişmez. Kalıcı başlık önbelleği eklenmez. İlk dolu satır çok ilerideyse veya tek satır çok uzunsa o kısım yine taranır; her girdi için sabit süre iddia edilmez.
- **Kontrollü ölçüm:** `scripts/benchmark-clipboard-preview.sh` üretimdeki aynı yardımcı kaynağını `swiftc -O` ile derler. Eski başlık hesabı yalnız karşılaştırma aracındadır. Her biri 896.030 karakter olan, ilk birkaç satırında kısa başlık bulunan 10 yapay günlük metninde üç ısınma çifti sonrası dönüşümlü sırayla 15 çift ölçüm alındı. On başlığın toplam hesabında ortanca **102,206 ms → 0,0066 ms**, p95 **115,093 ms → 0,0097 ms** oldu. Tüm sonuçlar aynı ve çıktı özeti tüketilerek doğrulandı. Bu süreler yalnız bu metinlerdeki başlık hesabıdır; tüm pano paneli çizimi, gerçek pano okuması veya tüm uygulama hızlanması değildir. Ham süreler `.build/clipboard-preview-performance/benchmark.json` içindedir.
- **Doğruluk:** Dört yeni test boş/boşluklu metinleri, CR/LF/CRLF/NEL/Unicode satır ve paragraf ayırıcılarını, 486 üretilmiş satır birleşimini, birleşik Unicode/emoji karakterleri, 200 karakter kesimini ve büyük günlük girdisinde gerçek `ClipboardItem.title` bağlantısını eski yöntemle karşılaştırır. İlgili pano geçmişi/kayıt testleriyle birlikte **18 test, 0 hata**. Kullanıcının genel panosu veya özel verileri kullanılmaz. Tekrarlama: `swift test --filter 'ClipboardTextPreviewTests|ClipboardHistoryTests|ClipboardPersistenceTests'`; günlükler `.build/clipboard-preview-performance/` içindedir.
- **Son kontroller:** Tam kök grupta **1.556 test, 0 hata, 6 isteğe bağlı atlama**. Yerelleştirme **4.517 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. Optimize Release paketi ve sıkı kod imzası doğrulaması geçti. Sürüm/build mevcut 0.1.6 / 9 olarak korunur.

### Ekran Süresi kartlarında ve grafikte ortak özet — 9 Kasım 2026

- **Apple araştırması ve statik neden:** [SwiftUI performans rehberi](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) görünüm gövdesindeki tekrarlanan pahalı hesaplamaları azaltmayı; [CPU işi rehberi](https://developer.apple.com/documentation/xcode/scheduling-cpu-work-efficiently) tekrar kullanılan hesap sonuçlarını paylaşmayı önerir. Çok günlük Ekran Süresi görünümünde toplam, aktif günler, eğilim, grafik ortalaması, ortalamanın paydası, çubuklar ve ölçek olmak üzere yedi ayrı ifade aynı günlük uygulama sürelerini topluyordu. Saat toplamları kart ve en yoğun saat için iki; tek günlük grafikte üç ayrı yerde hesaplanıyordu. Bunlar statik hesaplama yollarıdır; SwiftUI’nin her çizimde tüm çocuk gövdelerini yeniden çalıştırdığı iddia edilmez.
- **Uygulanan:** `UsagePeriodSummary`, gün toplamlarını ve 24 saatlik diziyi bir kez hesaplar. Kartlar, grafik çubukları, ortalama çizgisi, tepe saat ve Y ölçeği bunları kullanır. Aktif gün paydası en az bir kalır; boş günler ortalamaya aktif gün olarak eklenmez. Düne göre karşılaştırma, görünümün başında oluşturulan aynı canlı defteri kullanır; ikinci bir canlı segment kaydı oluşturmaz. Her görünüm güncellemesinde özet yeniden üretilir; kalıcı önbellek veya yeni zamanlayıcı yoktur. Uygulama sıralaması, gün/saat bölme, kaydetme ve takip frekansı değişmez.
- **Kontrollü ölçüm:** `scripts/benchmark-screen-time-summary.sh` üretimdeki `ScreenTime.swift` ve özet kaynağını `swiftc -O` ile derler. 30 gün, aktif günde 500 uygulama ve sekiz yapay veri kümesinde üç ısınma çifti ardından dönüşümlü 15 çift ölçüm alınır; her grupta 80 özet hesaplanır ve sonuç tüketilir. Önceki kart/grafik ifadelerinin toplamıyla ortak özet, bütün çıktı dizileri dahil eşdeğerdir. Özet başına ortanca **0,07975 ms → 0,01547 ms**, p95 **0,08125 ms → 0,01677 ms** oldu. Bu küçük kazanç yalnız gün/saat özetleme mikrotestidir; uygulama sıralaması, canlı segment kaydı, SwiftUI/Charts çizimi veya tüm sayfa açılış süresi değildir. Ham süreler `.build/screen-time-performance/benchmark.json` içindedir.
- **Doğruluk:** Dört yeni test boş/pasif dönemleri, sıfıra bölünmeyen ortalamayı, eksik saatlerin sıfır kalmasını, gün sırasını, kesirli süreleri, önceki toplamlarla eşdeğerliği ve güncel veriden yeni özet oluşturulurken eski anlık görüntünün değişmemesini sınar. Mevcut ekran süresi testleriyle birlikte **10 test, 0 hata**. Tekrarlama: `swift test --filter 'UsagePeriodSummaryTests|ScreenTimeTests'`. Günlükler `.build/screen-time-performance/` içindedir; gerçek kullanıcı ekran süresi defteri kullanılmaz.
- **Son kontroller:** Tam kök grupta **1.560 test, 0 hata, 6 isteğe bağlı atlama**. Yerelleştirme **4.517 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. Optimize Release paketi ve sıkı kod imzası doğrulaması geçti. Sürüm/build mevcut 0.1.6 / 9 olarak korunur.

### Beş optimizasyon adayının ölçümü — 9 Kasım 2026

Bu inceleme ürün davranışını değiştirmez. Kaynak sürüm `f17c12b`, ürün 0.1.6 / 9. Ayrı, detached çalışma kopyasında yalnız ölçüm hedefi ve SwiftUI gövde giriş sayaçları eklenerek Release (`-O`, test erişimi açık) derlendi. Kayıt/arama/görsel işlemleri üretimdeki gerçek `ClipboardService`, `ClipboardHistory` ve `ClipboardArchive` üzerinden; donanım okuması gerçek okuyucularla çalıştırıldı. Kullanıcı arşivi veya genel pano kullanılmadı. Tercihler ayrı suite veya yalnız süreç içi volatile domain üzerinden sağlandı; hiçbir özellik, fan profili veya ağ filtresi etkinleştirilmedi.

| Alan | Girdi / sınır | Sonuç |
| --- | --- | --- |
| Ana iş parçacığında kayıt | 1.000 kayıt, yaklaşık 20.000 karakterlik gövde, 20,15 MB JSON; 2 ısınma + 10 ölçüm | Değişiklikli kayıtta ortanca **53,91 ms**, p95 **54,85 ms**; önceden ana kuyruğa bırakılan probun beklemesi **53,97 ms**. Yükleme **13,87 ms**. Değişikliksiz flush **0,009 ms**. |
| Pano araması | 1.000 uzun kayıt; 1 ısınma + 6 ölçüm, tek eşzamanlı çağrı | `fixture`: **200,87 ms**; Türkçe harf dönüşümü gerektiren `ıstanbul`: **4.036,38 ms**; bulunmayan `missing-token`: **3.140,17 ms**. Boş sorgu **0,10 ms**. |
| Görsel belleği | 8 × 3840×2160 PNG; gerçek servis önbelleği ve 36 px NSImage çizimi | Düz renkli PNG toplamı **1,16 MiB**, ayrıntılı PNG toplamı **106,87 MiB**. Önizleme sonrasında süreç RSS artışı **253–256 MiB**, `phys_footprint` artışı **0,36–2,22 MiB**. Ayrı tam çözünürlüklü TIFF stresinde footprint artışı **254–261 MiB**. |
| Donanım okuması | 2 ısınma + 12 canlı okuma; ping kapalı | Sıcaklık **86,87 ms duvar süresi / 4,26 ms süreç CPU**, GPU **0,095 / 0,096 ms**, fan **0,179 / 0,028 ms**, SMC güç **0,451 / 0,100 ms**, ağ sayaçları **0,046 / 0,046 ms**, disk I/O **0,177 / 0,178 ms**. Tam sıcak sistem özeti **93,33 ms duvar / 6,00 ms CPU**. |
| İlgisiz SwiftUI güncellemeleri | Gerçek Genel/İzleme ayarları ve Araçlar görünümleri; 20 CPU-only atama, 80 ms aralık; aynı uzunlukta boşta kontrol | Genel ve İzleme sekmeleri **40'ar gövde hesabı**; Araçlar **20 ToolsHub + 600 kart = 620 hesap**. Boşta kontrolde **0**. Boşta süreç CPU yükü çıkarılınca güncelleme başına tahmini ek CPU: Genel **12,97 ms**, İzleme **16,84 ms**, Araçlar **13,25 ms**. |

**Boyut etkisi:** 200 kısa kayıtta (yaklaşık 200 karakter gövde) JSON **69,7 KB**, kayıt **0,94 ms**, yükleme **0,76 ms**; Türkçe arama **18,42 ms**, bulunmayan sorgu **14,18 ms**. 1.000 kısa kayıtta kayıt **3,74 ms**, Türkçe arama **89,71 ms**. 200 uzun kayıtta kayıt **9,76 ms**, Türkçe arama **804,87 ms**. Büyük dosyalarda ana iş parçacığı yükü ve aramada tam metin dönüşümü açıkça büyür. Buradaki 1.000 kayıt, desteklenen yüksek kapasite senaryosudur; varsayılan kapasite 200'dür.

**Bellek yorumunun sınırı:** RSS ve `task_vm_info.phys_footprint` ayrı ölçümlerdir; tek bir RAM sayısı gibi birleştirilmez. Tam TIFF temsili, önizlemeden ayrı stres aşamasıdır ve gerçek kullanıcı yapıştırması olarak sunulmaz. Önbellek temizlendikten sonra weak referanslarla sekiz NSImage nesnesinin de serbest kaldığı doğrulandı. Süreç footprint'inin hemen eski seviyeye dönmemesi tek başına sızıntı veya uygulama önbelleğinin hâlâ nesne tuttuğu anlamına gelmez. Önbellekte `countLimit` ve `totalCostLimit` sıfırdır; bütçe eklemenin bu sayıları ne kadar azaltacağı ayrıca karşılaştırılmadan iddia edilmez.

**Arayüz yorumunun sınırı:** Sayaçlar kopyadaki gerçek görünüm gövdelerine girer; 620 hesap, 620 tam ekran çizimi demek değildir. CPU farkı tüm deneme sürecini kapsar, GPU/WindowServer maliyetini kapsamaz; tek kontrol pencereli çalışma üzerinden tahmindir. 80 ms aralık, olayları ayrı gözlemek içindir; ürünün normal iki saniyelik yenileme frekansı değildir. Çalışan ürünün beş saniyelik Instruments kaydı ayrıca alındı. XCTest'e bağlanan ikinci SwiftUI kaydı SwiftUI verisi üretmedi; kesin gövde sayıları bu kayda değil yerel sayaçlara dayanır.

**Öncelik:** En güçlü ilk hedef tam metin araması, ardından büyük geçmişin ana iş parçacığında kaydı ve ilgisiz görünüm güncellemeleridir. Sensörün duvar süresi büyük ölçüde I/O beklemesidir; CPU süresiyle eş tutulmaz ve okunmayan sensörlerin maliyetini azaltmak için önce gösterge/uyarı/koruma talepleri doğrulanmalıdır. Üretimde sistem özeti actor üzerinde okunur; bileşen okuma süresi doğrudan ana arayüz donma süresi değildir. Görsel tarafında küçük önizleme ve tam çözünürlük temsilinin bellek davranışı ayrı ele alınmalıdır.

**Tekrarlama ve kanıt:** `scripts/measure-performance-survey.sh [yeni-çıktı-dizini]` ayrı çalışma kopyası oluşturur, yalnız ölçüm hedefini derler, sonuçları doğrular ve kopyayı temizler. İlk ölçümler `.build/performance-survey/report.json` içindedir: disk ve arama ilk çalışmadan; görsel ve arayüz ayrıntıları aynı kaynakla yapılan takip çalışmasından gelir. Günlükler `run.log` ve `final-detail-run.log`, gövde/konum eşlemesi `body-map.json` dosyasındadır. Nihai ölçüm çalışmaları hatasız geçti. Normal uygulama yeniden derlenmedi veya yeniden başlatılmadı. [Apple SwiftUI ölçüm rehberi](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance), [yanıt verebilirlik](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).

### Pano aramasının ortak bellek indeksi — 10 Kasım 2026

**İnceleme ve uygulama:** Hızlı panelde `items`, seçim ve ok tuşları; araç sayfasında ise görünüm gövdesi eşzamanlı `ClipboardHistory.search` çağırıyordu. İki görünüm artık `ClipboardSearchModel` kullanır. `ClipboardService`, geçmiş değiştiğinde ortak `ClipboardSearchIndex` actor'üne yeni revizyonu hazırlar; metin dönüşümü ve eşleştirme MainActor dışında çalışır. Değişmeyen içerik/kaynak adı yeniden dönüştürülmez; sabitleme ve kullanım tarihi değişikliklerinde güncel öğe bilgileri döner. Silinen belgeler indeksten çıkarılır. İndeks RAM'de ek bir normalize metin temsili tutar; disk arşiv biçimi değişmez.

Yazma 120 ms beklemeyle birleştirilir. Yeni sorgu önceki sonucu hemen kaldırır; sonuç beklenirken Enter, rakam kısayolları ve satır seçimi eski öğeyi yapıştıramaz. Geçmiş veya filtre değişikliği beklemeden yeni sorgu başlatır. Boş sorgu doğrudan mevcut listeyi gösterir. Panel kapanınca/görünüm ayrılınca gözlem ve UI isteği iptal edilir; ortak hazırlık diğer görünüm için kullanılabilir. Hem actor revizyonu hem UI istek kimliği eski yanıtların uygulanmasını engeller.

**Eşleştirme sınırı:** Türkçe İ/I/ı dönüşümü ve Foundation büyük/küçük harf/aksan katlama seçenekleri korunur. Normalize sonucu tamamen ASCII olan belgelerde tek bir `Data` temsiliyle alt dizi aranır; diğer alfabelerde kanonik `String` karşılaştırması sürer. ASCII dışı sorguların önbellek kaçırmalarında Foundation'ın önceki karşılaştırması da uygulanır: örneğin `ß`/`ﬁ` gibi genişleyen karakterler yalnız katlanmış sorgunun alt dizi testiyle aynı sonucu vermeyebilir. Bu özel sorguların maliyeti normal hızlı yolun süresi olarak sunulmaz. Kaynak uygulama adı aranır; paket kimliği aramaya eklenmez.

**Doğruluk:** Beş Core ve üç App testi; eski API ile Türkçe/aksan/Unicode/emoji/bağlantı/dosya/görsel eşleşmelerini, alanlar arasındaki satır sonlarını, NUL içeren metni, tüm tür filtrelerini ve sabitlenenlerin sırasını karşılaştırır. Metadata değişikliklerinde hazırlanan belge sayısı artmaz; içerik/kaynak değişiminde yalnız ilgili belge yenilenir. Eşzamanlı tüketiciler hazırlığı paylaşır; iptal edilen tüketici indeksi bozmaz. Hazırlık sürerken yeni revizyon silinmiş kayıtları geri getiremez. UI testleri hızlı yazmada tek son sorguyu, iptali dikkate almayan geç yanıtı, silme/sabitleme/filtre değişimini ve kapanıp yeniden bağlanmayı sınar. Kullanıcı arşivi veya genel pano kullanılmaz.

**Tekrarlama:** `swift test --filter 'ClipboardSearch(Index|Model)Tests'`; ölçüm için `scripts/measure-clipboard-search.sh [çıktı-dizini]`. Ölçüm üretimdeki Core kaynaklarını `swiftc -O -whole-module-optimization` ile derler. Geçmiş/sorgu başına aynı süreçte üç önce/sonra çifti alınır ve sonuçlar tam öğe eşitliğiyle karşılaştırılır. İlk hazırlık, sonraki sorgular ve tek kayıt ekleme ayrı ölçülür. Bu arama çekirdeği mikrotestidir; 120 ms yazma beklemesi, SwiftUI çizimi ve uçtan uca panel gecikmesi dahil değildir. Kaynak özetleri `source-sha256.json`, ham süreler `search-report.json` içindedir; `.build/clipboard-search-performance/` altında tutulur.

**Apple kaynakları:** [Foundation folding](https://developer.apple.com/documentation/foundation/nsstring/folding(options:locale:)) karşılaştırma için karakter ayrımlarını kaldırır; `nil` locale sistem yerelini kullanır. [Task.cancel()](https://developer.apple.com/documentation/swift/task/cancel()) işbirlikçi iptal uygular; bu nedenle döngülerde açık iptal kontrolleri ve sonuç uygulanmadan önce istek/revizyon kontrolü vardır.

**Son kontrollü ölçüm:** 1.000 × yaklaşık 20.000 karakter, üç çiftin ortancası; derleme işleri bittikten sonra alındı.

| Sorgu | Önce | İndeks hazırken |
| --- | --- | --- |
| `fixture` | 207,38 ms | 0,63 ms |
| `ıstanbul` | 3984,34 ms | 0,64 ms |
| `missing-token` | 3113,01 ms | 2,01 ms |
| `ß` | 207,23 ms | 215,59 ms |
| `olmayan-öğe` | 3121,39 ms | 1764,67 ms |

Büyük geçmişin ilk hazırlığı **1248,84 ms**; bu sırada 5 ms aralıklı MainActor probunun en büyük ek gecikmesi **2,62 ms** oldu. Bu prob kare süresi ölçümü değildir. Hazır indekse bir kayıt eklenmesi **0,73 ms** sürdü. Varsayılan kapasiteye yakın 200 kısa kayıtta ilk hazırlık **8,95 ms**, `ıstanbul` sorgusu **0,19 ms** oldu.

Normalleştirilmiş hızlı yol belirgin biçimde ucuzladı; Foundation karşılaştırması gereken özel sorgular hâlâ pahalı olabilir. `ß` örneğinde küçük ek maliyet, `olmayan-öğe` örneğinde yaklaşık 1,76 saniyelik arka plan işi kaldı. Bunlar gizlenmez ve bütün Unicode sorguları için milisaniye düzeyinde sonuç iddia edilmez. İlk hazırlığın RAM maliyeti bu turda ayrı ölçülmedi.

**Son kontroller ve canlı sınır:** Tam kök test grubunda **1.568 test, 0 hata, 6 isteğe bağlı atlama**. Yerelleştirme **4.518 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. İmzalı Release derlemesi ve sıkı kod imzası doğrulaması geçti; ürün mevcut **0.1.6 / 9** olarak yeniden açıldı. Canlı doğrulama uygulamanın açılışıdır; fiziksel klavyeyle panelde uçtan uca arama kabulü yapılmış sayılmaz. Disk yazımı, görsel önbelleği, sensör talepleri ve genel gözlem kapsamı bu değişikliğin dışındadır.

### Pano geçmişinin otomatik kaydını arka plana taşıma — 10 Kasım 2026

**İnceleme:** Bir saniyelik birleştirme gecikmesi bittikten sonra `ClipboardService.flushSave()` ana aktörde `ClipboardArchive.save()` çağırıyordu. JSON kodlama, atomik değiştirme ve dosya izinleri aynı çağrıyı bekletiyordu. Değişikliksiz kayıtların atlanması önceki turda yapılmıştı; burada gerçek değişikliklerin otomatik kaydı hedeflendi.

**Uygulama:** Otomatik kayıt artık `ClipboardArchiveWriter` içindeki utility öncelikli seri Dispatch kuyruğuna sabit bir geçmiş anlık görüntüsü gönderir. Mevcut JSON/ISO8601 biçimi, atomik değiştirme ve owner-only izinler korunur. Ana aktör en fazla bir otomatik yazıyı takip eder; bu sırada gelen hazır kayıt istekleri bir bayrakta birleştirilir ve sonraki yazı güncel geçmişi alır. Ara anlık görüntüler kuyrukta birikmez. Başarılı yazı yalnız kendi revizyonu hâlâ güncelse dirty durumunu temizler; hata yeniden deneme için değişiklikleri dirty bırakır. İstek kimliği, eski tamamlanma/hata yanıtlarının yeni duruma uygulanmasını engeller.

**Bilinçli sınır:** Normal otomatik kayıt arayüzü bekletmez. Açık `flushSave()` çağrıları (modül/özellik kapanışı ve uygulama çıkışı), arşivi yükleme, tamamen silme ve disk/bellek saklama geçişleri aynı kuyruğu senkron bekleyen dayanıklılık sınırlarıdır. Bu işlemler önceki yazının üzerine son durumun yazılmasını veya silmenin en son gerçekleşmesini sağlar; aynı başarılı revizyon ikinci kez yazılmaz. Bu tur, bütün dosya erişimlerini veya çıkış akışını asenkron yaptığını iddia etmez. Görsel dosyalarının okuma/yazımı da kapsam dışıdır. Disk tercihinin yakalama kapalıyken atlanması giderildi; kapatma tercihi artık bu durumda da arşivi siler.

**Doğruluk:** `ClipboardPersistenceTests` grubundaki 13 testin yedisi yeni akışı sınar. Kontrol edilebilir yavaş/yazma hatalı disk testlerinde; yazı beklerken arayüz tarafının ilerleyebilmesi ve worker'ın ana iş parçacığında olmaması, 20 ara isteğin yalnız son durumla birleştirilmesi, başarısız yazının yeniden denenmesi, silme/saklama geçişlerinin eski yazıdan sonra tamamlanması, aynı revizyondaki kapanış flush'ının ikinci disk yazısı üretmemesi, kapalı yakalamada disk tercihi ve geç hata yanıtının başarılı açık yeniden denemeyi ezmemesi doğrulandı. Önceki değişikliksiz yazı/izin/bellek görseli testleri de geçti. Genel pano ve kullanıcı arşivi kullanılmadı.

**Ölçüm yöntemi:** `scripts/measure-clipboard-writes.sh [çıktı-dizini]`, üretimdeki `ClipboardArchive` ve `ClipboardArchiveWriter` kaynaklarını `swiftc -O -whole-module-optimization` ile derler. 200/1.000 kayıt ve yaklaşık 200/20.000 karakterlik gövdelerde bir ısınma sonrası 10 eşleştirilmiş yazı alınır. Önceki ana aktör çağrısı ile yeni worker'ın kuyruğa verme/tamamlama süresi ayrı tutulur. Her çağrıdan önce sıraya bırakılan MainActor probunun beklemesi kaydedilir. Her yazıdan sonra iki arşiv de okunup tam geçmiş eşitliği ve 0600 dosya izni doğrulanır. Bir saniyelik birleştirme gecikmesi ve SwiftUI çizimi bu mikroteste dahil değildir; bu, uçtan uca uygulama kare süresi ölçümü değildir. Ham veriler `.build/clipboard-write-performance/write-report.json`, kaynak özetleri `source-sha256.json` içindedir.

**Apple kaynakları:** [Yanıt verebilirlik rehberi](https://developer.apple.com/documentation/xcode/improving-app-responsiveness), normal arka plan işinin ana iş parçacığına asenkron sonuç bildirmesini önerir. [Dispatch kuyrukları](https://developer.apple.com/documentation/dispatch/dispatch-queue) seri FIFO çalışmayı ve `sync` ile `async` arasındaki bekleme farkını tanımlar. Üründe normal otomatik kayıt `async` kullanır; yukarıdaki açık dayanıklılık sınırları hâlâ bekler.

**Son kontrollü ölçüm:** Derleme işleri bittikten sonra aynı kaynakla alınan 10 çiftin ortancaları:

| Geçmiş | Önce MainActor probu | Worker kuyruğuna verme | Sonra MainActor probu | Arka plan kaydının tamamlanması |
| --- | --- | --- | --- | --- |
| 200 × 200 karakter | 0,9488 ms | 0,0040 ms | 0,0075 ms | 0,9274 ms |
| 1000 × 200 karakter | 3,4380 ms | 0,0055 ms | 0,0101 ms | 3,3040 ms |
| 200 × 20000 karakter | 8,5306 ms | 0,0073 ms | 0,0118 ms | 8,6748 ms |
| 1000 × 20000 karakter | 40,1884 ms | 0,0082 ms | 0,0144 ms | 40,0552 ms |

1.000 uzun kayıttaki JSON 20.15 MB'dir. Kazanç ana aktörün yazıyı beklememesidir; toplam JSON/disk işi yaklaşık 40 ms sürer. Worker'a gönderme süresi, tüm `ClipboardService` veya SwiftUI güncellemesinin maliyeti olarak sunulmaz. Kapanış/silme/geçiş sınırlarının bekleme süresine bu iyileştirme uygulanmaz.

**Son kontroller ve canlı sınır:** Tam kök grupta **1.575 test, 0 hata, 6 isteğe bağlı atlama**. Yerelleştirme **4.518 anahtar, 0 eksik İngilizce çeviri/biçim uyuşmazlığı**. İmzalı Release derlemesi ve sıkı kod imzası doğrulaması geçti. Ürün sürüm/build değiştirilmeden **0.1.6 / 9** olarak yeniden açıldı. Canlı kabul bu paketin normal açılışını kapsar; kullanıcının gerçek panosuna deneme verisi yazılmadı. Arama indeksi korunur; genel SwiftUI gözlem kapsamı, sensör talepleri ve görsel önbelleği bu turun dışındadır.

### Observation geçişi, görsel önbellek bütçesi ve zamanlayıcı toleransı — 10 Kasım 2026

Kaynak `ec81011` üzerine uygulanan değişiklik; ürün 0.1.6 / 9 korunur. Dayanak: Apple [ObservableObject'ten Observable makrosuna geçiş](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro), [SwiftUI performansını anlama ve iyileştirme](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance), [NSCache](https://developer.apple.com/documentation/foundation/nscache) ve [Energy Efficiency Guide: zamanlayıcı toleransı](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MinimizeTimerUse.html).

- **`PocketModel` → `@Observable`:** `@Published` kaldırıldı; iç durum (`historyStore`, görevler, aboneler, görünürlük bayrakları) `@ObservationIgnored`. 38 görünüm `@ObservedObject` yerine düz referans, bağlama gereken dört yer `@Bindable` kullanır. Menü çubuğu `model.$system`/`$paused` Combine aboneliklerinden Swift `Observations` dizisine geçti. Artık bir görünüm yalnız gövdesinde okuduğu özellik değişince güncellenir.
- **Pano görsel önbelleği:** `countLimit` 48, `totalCostLimit` 96 MiB; maliyet çözülmüş piksel baytı (genişlik × yükseklik × 4). Çıkarılan görsel arşivden yeniden okunur.
- **Zamanlayıcılar:** Ağ izleme (15 dk → 60 sn tolerans), Ekran Süresi tik'i (1,5 sn), Odak geri sayımı ve pencere geçişi yerel tuş denetimi (0,2 sn), iki 30 sn'lik SwiftUI saati (5 sn) toleranslı. Kurulum sihirbazındaki fan kartı `body` içinde her güncellemede yeniden kurulan `Timer.publish` yerine kart ömrü boyunca tek `.task` döngüsü kullanır.

**Ölçüm (uygulanan kod):** Aynı `scripts/measure-performance-survey.sh` hedefi; çalışma ağacı değişiklikleri ayrı detached kopyada geçici commit'e alınıp Release ile ölçüldü (ana dal ve çalışan uygulama değişmedi).

| Alan | Önce (9 Kasım) | Sonra |
| --- | --- | --- |
| 20 `system` ataması · Genel ayarlar | 40 gövde hesabı, ~12,97 ms ek CPU/atama | **0** gövde, ~0,01 ms |
| · İzleme ayarları | 40 gövde, ~16,84 ms | **0** gövde, ~0,09 ms |
| · Araçlar | 620 gövde (20 hub + 600 kart), ~13,25 ms | **0** gövde, ~0,08 ms |
| 8 × 4K görsel önizleme sonrası RSS artışı | 253–256 MiB | **95–96 MiB** (`phys_footprint` artışı 0,3–0,7 MiB) |

Değişiklik bildirimi her atamada 20/20 ulaştı; yani ölçüm gerçekten tetiklendi, yalnız ilgisiz görünümler yeniden hesaplanmadı. Yeni `PocketModelObservationTests`, örnekleme yenilemesinin `refreshSeconds`/`paused`/`awakeSession` okuyucularını geçersiz kılmadığını ve `system` okuyucusunu tam bir kez bildirdiğini sınar.

**Sınırlar:** Gövde sayıları ölçüm kopyasındaki sayaçlara dayanır; GPU/WindowServer maliyeti kapsanmaz. Önbellek bütçesi bellek tavanını sınırlar, ama sınırı aşan geçmiş görselleri yeniden diskten çözülür (gezinirken ek I/O). Zamanlayıcı toleranslarının enerji etkisi ayrı ölçülmedi. Çalışan uygulamada canlı Instruments kaydı bu turda alınmadı. Tam kök grupta XCTest **1.026 test, 0 hata, 5 atlama** ve Swift Testing **355 test** geçti; yerelleştirme **4.524 anahtar, 0 eksik**.

### Observation geçişinin ikinci grubu — 10 Kasım 2026

Kaynak `ca7b794`. Aynı kural yedi modele uygulandı: `PowerCenterModel` (20 alan, 2 sn döngü), `ApplicationWorkspaceModel` (20), `CleanupModel` (13), `LANScannerModel` (11), `WeatherService` (8), `ScreenTimeService` ve `VolumeMixerService` (1 sn). `@Published` kaldırıldı. Önceden yayın yapmayan saklı alanlar `@ObservationIgnored` oldu, böylece bildirim davranışı korunur. Tüketicilerde `@ObservedObject` yerine düz referans ya da `@Bindable` (6 yer), `@StateObject` yerine `@State` kullanılır.

- `FileWorkspaceModel`'in `junk.objectWillChange` aktarımı kaldırıldı; Genel Bakış'taki temizlik kutusu `CleanupModel`'i doğrudan izler.
- Menü çubuğu hava durumunu `objectWillChange` yerine `Observations` ile yalnız `snapshot`/`location` değişince yeniden çizer; yükleme ve sonraki yenileme zamanı gibi iç alanlar çizim tetiklemez.
- Kapsam dışı: `WindowSwitcherModel` (elle `objectWillChange.send()`, Alt+Tab ana deneyimi), `FileWorkspaceModel` (elle bildirim), `DisplayBrightnessService` (Gece Modu Combine `$settings`/`$displays` hatları) ve tek alanlı `MenuBarHistory` (Observation kazanç sağlamaz).

**Doğrulama:** Statik inceleme ve derleme; bu grup için ayrı gövde sayacı ölçümü alınmadı, kazanç ilk gruptaki ölçülen mekanizmaya dayanır (bir sekmenin okumadığı alan değişince o sekme yeniden hesaplanmaz). Gövdesinde `Date()` okuyan görünümler (Güç zaman çizelgesi, hava durumu saat/gün süzgeci) artık ilgisiz yayınlarla değil, okudukları model alanı değişince tazelenir. Tam kök grupta XCTest **1.026 test, 0 hata, 5 atlama**, Swift Testing **355 test** geçti. Çalışan uygulamada canlı doğrulama yapılmadı.

### Canlı Instruments ölçümü — 10 Kasım 2026

**Yöntem:** `ec81011` (önce) ve `14dd3f3` (sonra) ayrı detached kopyalarda `scripts/build-app.sh release` ile derlendi ve imzalandı. İki kopyaya da yalnız ölçüm için aynı `--profile-page <sayfa>` başlatma yaması eklendi. Bu yama ana dala girmez. Her çalıştırmada uygulama kapatıldı, sayfa açık başlatıldı, 20 sn beklendi, ardından 45 sn ölçüldü. Ölçüm türleri: bir tur `xctrace` SwiftUI şablonu (Time Profiler dahil), iki tur yalnız `ps` süreç CPU süresi. Sürüm sırası turlar arasında ters çevrildi. Makine: pilsiz Mac Studio, gerçek kullanıcı oturumu ve gerçek donanım. Kayıtlar oturum çalışma alanındadır ve depoya eklenmedi.

| Sayfa | 45 sn'de SwiftUI güncellemesi (önce → sonra) | Düğme gövdesi yeniden hesabı | Süreç CPU, 3 eşleşmiş tur (önce → sonra, s) |
| --- | --- | --- | --- |
| Araçlar | 83.455 → **14.106** | 7.054 → **14** | 2,66→2,02 · 0,96→0,66 · 2,19→1,40 |
| Güç Merkezi | 272.327 → **207.454** | 4.209 → 1.270 | 9,41→7,60 · 3,66→2,93 · 12,96→8,81 |
| Genel Bakış | 58.830 → **24.331** | 3.962 → **0** | 2,45→2,78 · 1,47→1,18 · 2,30→1,76 |

Dokuz eşleşmiş CPU ölçümünün sekizinde yeni sürüm daha düşük çıktı. Oranlar: Araçlar 0,64–0,76, Güç 0,68–0,81, Genel Bakış 0,77–1,13. Mutlak saniyeler turlar arasında 3–4 kat değişiyor (arka plan yükü; iki CPU turu sırasında depoda `swift build` da çalıştı). Bu yüzden yalnız aynı turdaki önce/sonra oranı yorumlanır. Kayıt sırasında örneklerin ~%18'i Instruments'ın SwiftUI izleme desteğine düşer, yani izlemeli tur CPU'yu şişirir.

**Kalan sıcak nokta — Güç Merkezi:** 45 sn'de 207 bin güncelleme; ana kalemler `Text Content` ~0,4–0,53 sn ve `DynamicContainerInfo<DynamicLayoutViewAdaptor>` ~0,5 sn. Sayfadaki dört `ViewThatFits` her iki düzen seçeneğini de kurup ölçüyor. Zaman damgası değişen `overview` her 2 sn'de bütün kartları yenilediği için bu maliyet her turda tekrarlanıyor. Time Profiler örneklerinin büyük kısmı SwiftUI'nin kendi kodunda; tek başına öne çıkan bir uygulama fonksiyonu yok.

**Eşit değer yazımı kontrolü:** `PowerCenterModel` (onaylar, termal, enerji, ayarlar, zamanlama) ve `VolumeMixerService` (uygulamalar, aygıtlar, varsayılan çıkış, satır durumları) artık yalnız değer değişince yazıyor. Güç sayfasında dört eşleşmiş turda CPU farkı ±%6 içinde iki yöne de değişti; SwiftUI güncellemesi 207.218 / 207.854. **Ölçülebilir kazanç yok.** Değişiklik `PocketModel`'deki kuralla tutarlılık için tutuldu. Mikser etkisi ayrıca ölçülmedi.

### Güç Merkezi: zaman damgası ve kart kapsamı — 10 Kasım 2026

- `PowerOverview.hasSameReading(as:)`: `capturedAt` dışındaki bütün alanlar aynıysa `overview` yeniden yayımlanmaz; watt ortalaması ham son okumayla (`lastOverviewReading`) sürer. 2 test.
- `PowerOverviewPanel` gövdesi artık `model.system` okumaz. Sensör ve fan kartı `PowerLiveSensors`'a, durum, enerji ve zamanlama kartları kendi görünüm tiplerine taşındı; her kart yalnız okuduğu alan değişince yenilenir.

**Canlı ölçüm** (Güç sayfası, `c70e3de` ile karşılaştırma, aynı yöntem): Yalnız `overview` koruması güncellemeleri 175.084 → 166.338 (-%5) indirdi. Kart ayrımıyla birlikte 154.008 → 140.313 (-%9) oldu; düğme gövdesi 1.087 → 277, `Preference List` 2.109 → 800. Süreç CPU'su üç CPU turunda 9,33→9,08 · 8,96→8,17 · 8,61→9,00 s; **CPU'da net fark yok**. Bu turlarda makine genel olarak daha yüklüydü; SwiftUI süreleri önceki turların 4–5 katıydı.

**Asıl CPU kaynağı (Time Profiler, kapsayıcı):** Ana iş parçacığı örneklerinin ~5.500'ü, yani 45 sn'de ~0,55 sn, SwiftUI'nin `Text(LocalizedStringKey)` çözümlemesinden `-[NSBundle localizedAttributedStringForKey:value:table:localization:]` çağrısına gider. Bu yol metin tablosunu her çağrıda diskten yeniden okur (`open`/`statfs`/`_CFDataCreateFromURL`). Mikro ölçüm (paketlenmiş uygulama, 2.000 çağrı): `localization: nil` **0,11–0,19 µs**; açık `tr` **24–32 µs**; açık `en` (359 KB tablo) **312–315 µs**. SwiftUI, environment `locale` kimliği `Locale.current` ile aynı olduğunda `nil`, değilse açık dili geçirir. `pocketLocale` bölgesiz olduğu için (`"tr"`/`"en"`) her kullanıcı açık yola düşer. Heceleme sözlüğü `stat` çağrıları (~1.900 örnek) ve izleme desteğinin SHA256'sı (~1.350 örnek, Instruments kaynaklı) ayrıca görüldü.

**Not:** `PowerLiveSystemTests.testStreamingLogReaderFindsEventsWithBoundedOutput` bu makinede şu an commit'lenmiş kodda da başarısız; canlı `pmset -g log` içeriğine bağlı, değişiklikle ilgisiz. Diğer 1.027 XCTest ve 355 Swift Testing testi geçti; yerelleştirme 0 eksik.

### Metin literal'leri için önbellekli yerelleştirme yolu — 10 Kasım 2026

**Sorun:** SwiftUI, environment `locale` kimliği `Locale.current` ile aynı değilse her `Text` literal'ini `-[NSBundle localizedAttributedStringForKey:value:table:localization:]` ile belirli bir dilde çözer. Bu yol metin tablosunu her çağrıda diskten yeniden okur. Ayrı bir SwiftUI sondası çağrıları saydı: environment'ta yerel ayar yoksa, `.current`, `.autoupdatingCurrent` ya da `Locale(identifier: Locale.current.identifier)` verildiğinde `localization: nil`; `tr`, `en` gibi farklı bir kimlik verildiğinde açık dil geçiyor. Uygulama alanındaki `AppleLanguages` `Locale.current`'ı değiştirmez; `AppleLocale` değiştirir (`en_TR` → `tr_TR`, Türkçe tarih ve ondalık virgülle). Eski `pocketLocale` bölgesiz olduğundan (`"tr"`/`"en"`) bütün kullanıcılar yavaş yoldaydı.

**Değişiklik:** `AppLanguage` Türkçe/İngilizce kaydedilince uygulama alanına sistem yerel ayarından türetilmiş `AppleLocale` yazar. Yalnız dil değişir; bölge, takvim ve diğer anahtar sözcükler korunur (`en_TR` → `tr_TR`, `de_DE@calendar=buddhist` → `en_DE@calendar=buddhist`). "Sistem" seçilince kayıt kaldırılır. Açılışta `applyLanguageDefault` aynı değeri yeniden hesaplar, böylece sistem bölgesi değişikliği de izlenir. `pocketLocale`, dili uygulama diliyle eşleşiyorsa `Locale.current`'tır; eşleşmiyorsa, ör. hizalamadan önceki ilk açılışta, bölgesi korunmuş doğru dilde bir yerel ayar kullanılır (doğru ama yavaş yol). Biçimlendirme artık seçilen dil ve kullanıcının bölgesiyle yapılır (`tr` → `tr_TR`, `en` → `en_TR`/`en_GB`). `AppleLocale` ayar aktarımına girmez. 2 yeni test.

**Canlı ölçüm** (Güç sayfası, `165fdb8` ile karşılaştırma, 45 sn, aynı yöntem):

| Arayüz dili | Tablo yükleme örnekleri | Süreç CPU, eşleşmiş turlar (önce → sonra, s) |
| --- | --- | --- |
| Türkçe (kalıcı tercih, ısınma açılışından sonra `AppleLocale=tr_TR`) | 1.632 → **34** | 6,88→6,13 · 3,16→3,04 · 3,23→2,97 · 3,02→3,04 |
| İngilizce (`-AppleLanguages (en)`; yeni sürümde hizalanmış `-AppleLocale en_TR`, argüman alanıyla) | 15.005 → **26** | 8,81→6,12 · 4,35→3,03 · 4,41→2,92 (**-%30–34**) |

Mikro ölçüm (paketlenmiş uygulama): `localization: nil` 0,11–0,19 µs; açık `tr` 24–32 µs; açık `en` 312–315 µs. İngilizce senaryo kullanıcının kalıcı ayarı değiştirilmeden komut satırı argümanlarıyla canlandırıldı; ekrandaki metinlerin gerçekten İngilizce çıktığı görsel olarak doğrulanmadı, yalnız arama yolu ve dili doğrulandı.

**Etkisi:** Ölçüm sürümü bu makinede uygulama alanına kalıcı olarak `AppleLocale=tr_TR` yazdı. Bu, tasarımın normal davranışı. Önceki derlemeler bu anahtarı okumaz ama `Locale.current` üzerinden AppKit biçimlendirmesi Türkçeleşir. Tam kök grupta XCTest **1.030 testte 1 hata** var: `PowerLiveSystemTests.testStreamingLogReaderFindsEventsWithBoundedOutput`, önceki commit'te de aynı nedenle başarısız. Swift Testing **355 test** geçti; yerelleştirme 0 eksik.
