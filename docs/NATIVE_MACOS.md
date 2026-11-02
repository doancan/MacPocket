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

## Apple kaynakları

- [SwiftUI ile yeni tasarım](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Özel görünümlerde Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Ana uygulamanın giriş kaydı](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
