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
