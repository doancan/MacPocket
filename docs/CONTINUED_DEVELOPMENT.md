# Mevcut sürüm üzerinde devam eden geliştirme — 29 Ekim 2026

Kullanıcının isteğiyle sürüm/build numarası değiştirilmedi, tag veya GitHub Release
oluşturulmadı. AI Dosyaları katalogdan ve ürün kapsamından çıkarıldı.

## Uygulananlar

- Menü çubuğu: tek birleşik grup veya ayrı native status item; CPU/RAM/disk/pil/güç
  seçimi ve sıra; etiket/simge, sıkılık, yazı boyutu, birim, ondalık, değer/mini
  gösterge; RAM alanı ve oranı, disk birimi/boş alan/doluluk seçenekleri.
  Mac Studio’da pil göstergesi gizlenir. Seçili disk kaybolursa veri uydurulmaz.
- Pencere geçişi: isteğe bağlı Carbon kısayol kaydı, ayrı native panel, ileri/geri
  döngü, ok/Tab/Enter/Escape, tuş bırakınca seçme; MRU/uygulama/başlık sırası,
  gizli/küçültülmüş/penceresiz/tek uygulama filtreleri ve kalıcı hariç tutma.
  AX yetenek denetimli kapatma/küçültme/geri açma/tam ekran/gizleme; kapatma
  onayının özgün hedef kimliği korunur. Seçili pencere SCK önizlemesi açık izin
  ve kullanıcı isteğiyle bellekte alınır, diske yazılmaz.
- macOS araçları: 11 sınırlı salt okunur sorgu; Time Machine, launchd, portlar,
  disk/bölümler, Spotlight, DNS, rotalar, sistem güncelleme geçmişi, SIP, Gatekeeper.
  Native sonuç arama/kopyalama/dışa aktarma ve iptal. Hiçbiri ayar değiştirmez.
- Uygulama kalıntıları: yedi Library konumunda tam bundle kimliği adayları;
  kurulu uygulama/alt bileşen isim alanları ve Apple öğeleri korunur, symlink
  kaynaklar izlenmez. Eksik envanter bir öğenin gereksiz olduğuna kanıt sayılmaz.
  Başlangıçta seçim yok; Çöp öncesi envanter ve LaunchServices tekrar okunur.
- Benzer görseller: Vision rev2, mesafe eşikleri, görsel-only tarama, yerel ve
  küçültülmüş analiz, gerçek önizlemeler/Finder. Silme/yükleme yok. Sınırlar ve
  algısal benzerliğin dosya eşitliği olmadığı arayüzde açıklanır.
- Ekran temizleme: tüm ekranlarda siyah native panel, 3 sn geri sayım, 15–60 sn
  süre, Escape/iki saniye fare basılı tutma ve uygulama değişimi/uyku/ekran
  değişimi/çıkış temizliği. Yalnız MacPocket içindeki girişler tutulur;
  bütün sistem klavyesinin kilitlendiği iddia edilmez.

## Doğrulama

- 66 XCTest testi, 0 hata; optimize uygulama derlemesi başarılı.
- 11 macOS sorgusu bu Mac Studio’da exit 0 verdi. Ham kullanıcı ağ/görev
  çıktıları Git’e konmadı; yalnız sayım kaydı .build altında.
- Native Menü Çubuğu ayarlarında CPU/RAM/disk/güç seçimi ve birleşik/ayrı
  seçenek değişimi görüldü; ortak gerçek popover açıldı. Sistem genelindeki
  menü çubuğu öğelerinin fiziksel sürükleme kabulü ayrıca gerekir.
- Native SIP raporu exit 0 ve enabled sonucu verdi.
- Native geçiş paneli manuel açıldı; Tab/ok ve Escape çalıştı. İlk otomasyon
  kısayol testi kayıt başarılı olsa da panel açmadı. Tam eşleşmeli uygulama içi
  olay yolu eklendi; sonraki Ctrl+Option+Space paneli açtı, tekrar ileri ve
  Shift ile geri birer adım geçti. Üç yerel olay kaydedildi, Carbon global
  callback gözlenmedi. Bu sonuç fiziksel global klavye teslimini kanıtlamaz.
  Global kısayol test sonrası kapalı varsayılana döndürüldü.
- Native Benzer Görseller’de yalnız üretilen üç örnek analiz edildi: kopya
  mesafesi 0.000, küçük varyant mesafesi 0.039 gösterildi. Kullanıcı fotoğrafı
  okunmadı. Fixture Vision testi de gerçek analizle geçti.
- Ekran temizleme native paneli açıldı ve Escape ile kapandı. Ayrı 15 saniyelik
  seans, 3 saniyelik geri sayımın ardından süre sonunda kendiliğinden kapandı.

## Üretim sağlamlaştırması ve arayüz yenilemesi — 29 Ekim 2026

Sürüm numarası değiştirilmedi.

Core düzeltmeleri (her biri regresyon testiyle, `CoreHardeningTests`):
- Paket içi dosyalar (.app, .photoslibrary…) toplamlara sayılır ama tek tek
  listelenmez; `FileTrashRequest.validate` paket içindeki öğeyi reddeder.
- Kopya karşılaştırması okunamayan/değişen dosyada durmaz; iCloud yer tutucuları
  indirilmez; ilerleme her dosyada ilerler.
- Komut çalıştırıcı: stdout/stderr ayrımı (brew JSON), uzun brew işleminin çıktı
  sınırında öldürülmemesi, iptalde önce SIGINT sonra SIGKILL, pipe’ı tutan yetim
  alt süreçte süreli bekleme (askıda kalma giderildi).
- Oturum için kritik süreçler (loginwindow, WindowServer, OS daemon’ları)
  sonlandırılamaz; SIGTERM’i yok sayan süreç için “Zorla Sonlandır” çalışır.
- Kalıntılar: büyük/küçük harf duyarsız ve `App-Helper` eşleşmesi; aynı üreticinin
  kurulu uygulaması varsa aday “Üretici uygulaması kurulu” diye işaretlenir; boş
  envanterde liste oluşturulmaz.
- Güç geçmişi JSON Lines’a geçti (dakikada ~4 MB yeniden yazım yerine tek satır);
  eski biçim otomatik taşınır, bozuk dosya `.corrupt` olarak saklanıp kayıt sürer.
- Bellek: Activity Monitor uyumlu “Kullanılan Bellek” (uygulama + wired +
  sıkıştırılmış) ve swap; açık kalma süresi uykuyu içerir; boş alan Finder ile
  aynı (“important usage”). Başlıksız pencere önizlemesi eşleşir.

Arayüz:
- Ortak tasarım sistemi `PocketDesign.swift`: boşluk/köşe token’ları, kart,
  başlık, mesaj, rozet, metrik kutucuğu, halka gösterge, ikon önbelleği,
  Türkçe biçimlendiriciler. Sabit 9–11 pt fontlar semantik stillere çevrildi.
- Genel Bakış (canlı halkalar), Sistem İzleme (Swift Charts CPU ve bellek
  bileşimi), Güç Merkezi, menü çubuğu, Görev Yöneticisi, Araçlar, dosya ve
  uygulama ekranları yeniden düzenlendi; her ekranda yükleniyor/hata/boş durumu.
- Araçlar’da çalışmayan beş kart ve yinelenen “Bakım Görevleri” kaldırıldı;
  uyanık tutma tek kaynaktan (`PocketModel`) yönetilir. “Tools” → “Araçlar”.
- Görünüm varsayılanı sistem teması; minimum pencere 960 × 620.
- Paketleme: hardened runtime, isteğe bağlı `MACPOCKET_SIGN_IDENTITY` ve
  `MACPOCKET_NOTARY_PROFILE` ile Developer ID imzası ve notarization.

Doğrulama: 76 XCTest geçti. Uygulama Mac Studio’da çalıştırıldı; Genel Bakış,
Sistem İzleme, Güç, Araçlar, Görev Yöneticisi, Uygulamalar ve Temizlik ekranları
görsel olarak kontrol edildi. Silme/sonlandırma akışları canlı uygulanmadı.

## Çok dilli arayüz ve genişletilmiş ayarlar — 29 Ekim 2026

- Türkçe kaynak dil olarak kaldı; İngilizce eklendi (`Resources/tr.lproj`, `Resources/en.lproj`,
  `CFBundleLocalizations`). `scripts/build-app.sh` her `Resources/*.lproj` klasörünü pakete kopyalar.
- Ayarlar → Genel → “Dil / Language”: Sistem, Türkçe, English. Seçim uygulama alanındaki
  `AppleLanguages` değerine yazılır (Sistem’de silinir); “Yeniden Başlat / Relaunch” uygulamayı
  `/usr/bin/open -n` ile yeniden açar. Biçimlendiriciler (`pocketLocale`) çalışan dili izler.
- `scripts/check-localizations.sh`, derleyicinin çıkardığı anahtarları İngilizce tabloyla karşılaştırır.
- Yeni ayarlar: Dock’ta göster, açılış sayfası, ana pencereyi açılışta göster, uyanık tutarken çıkış onayı,
  vurgu rengi, kenar çubuğu simgeleri, kart yoğunluğu, hareketleri azalt, güç geçmişi süresi,
  disk/termal/bellek bildirimleri (saatte en çok bir), Gelişmiş sekmesinde ayarları JSON olarak
  dışa/içe aktarma, tüm ayarları sıfırlama ve güç geçmişini temizleme.

## Devam eden kabul ve eksikler

MacPocket için Erişilebilirlik ve Ekran Kaydı izinleri kullanıcıdan istendi;
izinler otomatik verilmedi. AX pencere eylemleri ve SCK yakalama bu nedenle
bu Mac’te henüz canlı kabulden geçmedi. Fiziksel global kısayol, gerçek
modifier bırakma ve diğer uygulama/Space’den açılış ayrıca test edilecek.

Tam AltTab eşdeğerliği tamamlanmadı: özel Spaces entegrasyonu, bütün pencere
küçük resimleri, tam pencere bazlı MRU ve bütün temalar/seçenekler bekliyor.
Homebrew dışı updater, malware motoru, tarayıcı/e-posta hesap entegrasyonları,
Mail ekleri/gizlilik kaynak servisleri, ayrıcalıklı bakım mutasyonları ve
MacBook şarj denetimi de tamamlanmış sayılmaz. Bunlar katalogda hazır işlev
olarak sunulmaz. Kullanıcı tüm kapsamı istedi; bu belge kalan işleri açık tutar.

## Kanıt kaynakları

- [AltTab incelemesi ve sınırlar](research/2026-10-29-alttab-parity.md)
- [iStat görünüm seçenekleri](research/2026-10-29-istat-display-options.md)
- [macOS sorgu kaynakları](research/2026-10-29-macos-utilities.md)
- [Vision benzer görseller](research/2026-10-29-similar-images.md)

## Canlı işlev testi ve performans analizi — 29 Ekim 2026

Kurulu uygulamada, kullanıcı verisine dokunmadan, test için oluşturulan dosya/süreçlerle:

| İşlev | Sonuç |
|---|---|
| Uyanık tutma başlat/durdur | Geçti — `pmset` kaydı oluştu ve kalktı |
| Uygulama kaldırma planı + Çöp | Geçti — sahte uygulamanın 4 ilişkili öğesi bulundu, hepsi Çöp’e taşındı |
| Görev Yöneticisi ara/seç/sonlandır | Geçti — test sürecine SIGTERM gitti |
| macOS Araçları | 11/11 sorgu çıkış 0 |
| Sistem Raporları | 8/8 (açık dosyalar 256 KB sınırında bilinçli olarak kısmi) |
| Disk Analizi kategorileri | Geçti — 1,75 M öğe, ~14 sn |
| Space Lens | Geçti — ev klasörü ~24 sn, içine girme/geri dönme |
| Menü çubuğu gruplu/ayrı, Liquid Glass sekmeler | Geçti |
| Windows tarzı Alt+Tab, yazarak arama, stiller | Geçti (küçük resimler Ekran Kaydı izni bekliyor) |
| Türkçe/İngilizce | Geçti — dil seçilmemişse Türkçe; İngilizce yeniden başlatınca |

Performans (Mac Studio, sayfa yerleştikten sonra 10 sn ortalama): açılış 0,76–0,81 sn;
boşta CPU %0,2–2,2 (Güç Merkezi ve Görev Yöneticisi canlı ölçümle ~%6–7).
Ölçümle bulunup düzeltilenler: tablo kapsayıcısında `clipShape` (+230 MB GPU, Uygulamalar
387 → 146 MB), kart içeriğine uygulanan gölge, tam çözünürlükte tutulan simgeler, MacPocket
öne geldiğinde gereksiz AX pencere taraması, her ölçümde değişmeyen değerlerin yayımlanması,
canlı metriklerde sürekli animasyon (~%10 → ~%2 CPU).

Bilinen konular: disk kategori taraması sırasında bellek tepe noktası ~650 MB (tarama
bitince ~200 MB’a iner); Güç Merkezi/Görev Yöneticisi’nde geçici GPU tepeleri; bu Mac’te
pil denetleyicisi sistem gücü telemetrisi güncellenmediği için Güç halkası “Süreç gücü”
gösterir. Temizlik’in “Temizle” adımı, Space Lens’ten Çöp’e taşıma, Benzer Görseller,
Uygulama Kalıntıları, Ekran Temizleme ve Ayarlar canlı olarak henüz tıklanarak test edilmedi.


## Vorssaint karşılaştırmasından sonraki geliştirmeler — 5 Kasım 2026

Kullanıcının onayladığı sıra: modül yaşam döngüsü → Komut Çubuğu → Dosya Rafı →
Dock önizlemeleri → uygulama başına ses yönlendirme. Önceki önerilerdeki fare tuşu
atamaları, kaydırmalı/sabitlenebilir ekran görüntüsü, kanal bazlı uygulama
güncelleme ve koşullu uyanık tutma da kapsamda kalır. Dinamik izin–etkin modül
listesi bu altyapının sonraki genişletmesidir. Bu işler tek aşama tamamlandı diye
bitmiş sayılmaz; aşağıda yalnız doğrulanmış aşama kaydedilir.

### Uygulanan: modül yaşam döngüsü

- Ayarlar → Modüller: aranabilir 19 modül, 22 servis. Eksik tercih açık kabul
  edilir; mevcut kurulumun araçları kendiliğinden kapatılmaz. Modül tercihi,
  aracın kendi etkinlik ayarından ayrıdır; kapatma ayar/geçmiş silmez.
- `ModuleLifecycle`: gecikmeli singleton erişimi, tek seferlik başlat/durdur,
  içe aktarma/sıfırlamayı izleyen uzlaştırma, ters sırayla kapanış. Hiç
  başlatılmamış kapalı servisin durdurma closure'ı bile çalıştırılmaz.
- Devam eden kayıt/kaydetme, ekran yakalama, masa düzeni geri yükleme ve odak
  oturumu sırasında modül kapatma gerekçeli olarak reddedilir. Odak oturumunun
  kullandığı ekran/makro/koruma modülleri de oturum sırasında kapatılamaz.
- Kapalı aracın ayrıntısında tekrar açma eylemi vardır. Genel Bakış, sağ tık
  menüsü ve araçlar arası başvurular kapalı servisi istemeden oluşturmaz.
- Bildirim ve Core Audio dinleyicileri, event tap'ler, kısayollar ve
  zamanlayıcılar bırakılır. Dondurulmuş uygulamalar çözülür; ekranın geçici renk
  ayarları geri alınır. Çökme sonrası kurtarma modül kullanılabilirliğinden
  bağımsızdır.

### Düzeltilen kaynak yönetimi sorunları

- Yeniden başlatmada biriken bildirim ve Core Audio dinleyicileri.
- Kısayollar kaldırıldığında global işlem tablosunda kalan closure'lar ve
  gereksiz Carbon handler; artık son kısayolla birlikte bırakılır.
- Eski ses mikseri kurulumunun, yeni çıkış/oturum için bekleyen isteği veya hata
  durumunu değiştirmesi. Nesil değişiminde eski istekler geçersizleşir.
- Kapalı modüle sonradan dönen DDC/pil sorgularının servis durumunu yeniden
  yayımlaması; ekran kontrol kanallarını süresiz tutan güçlü ortak önbellek.
- Fare kaydırma kapatıldığında kalan yumuşak kaydırma çerçeveleri.
- Ekran Süresi modülü aç/kapat döngüsünde birden fazla geçmiş yüklemesi.

### Doğrulama ve sınırlar

- `swift test`: 642 test, 4 isteğe bağlı test atlandı, 0 hata. İlk tam koşuda
  Vision OCR `e5rtError` verdi; aynı gerçek OCR testi tek başına, ardından tam
  takım tekrar çalıştırıldı ve geçti. Test atlama veya OCR uygulama değişikliği
  ile hata gizlenmedi.
- `scripts/check-localizations.sh`: 3.400 anahtar, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı, 0 kullanılmayan çeviri.
- Geliştirme paketi oluşturuldu; derin/sıkı kod imzası doğrulandı.
- Ayrı `com.doancan.MacPocket.ModuleAudit` deneme paketinde Türkçe ve İngilizce
  canlı denetim: kapalı açılışta 0 servis oluşturuldu; her dilde 19 modülün
  üç aç/kapat döngüsü, 22 servisin tamamı; kapatma sonrasında ölçülen
  zamanlayıcı/dinleyici/kısayol/tap kaynakları 0. 19 native anahtarın erişilebilir
  adları ve klavye odağı doğrulandı. JSON raporları ve uygulamanın kendi görünüm
  görüntüleri `.build/module-audit-tr.*` ve `.build/module-audit-en.*` içindedir.
- Bu kabul, API üzerinden kullanılabilirlik değişimini ve native ayar
  görünümünü kapsar. Gerçek ekran/ses kaydı sırasında kapatma, dolu pano/makro
  geçmişleri, DDC yazımı ve çökme kurtarmasının gerçek donanım kabulü, VoiceOver
  ile uçtan uca kullanım ve koyu görünüm ayrıca test edilmelidir.
- Sürüm/build değiştirilmedi; tag veya Release oluşturulmadı. AI Dosyaları
  kapsam dışındadır. MacBook pil/şarj davranışı doğrulanmış sayılmadı.


### Uygulanan: Komut Çubuğu

- Araçlar → Komut Çubuğu; Git menüsünde ⌘⇧K ve menü çubuğu sağ tık menüsünde
  açma eylemi. Varsayılan global kısayol ⌥Space; kaydedilemezse gerekçe ve yeni
  kombinasyon seçimi gösterilir. Kısayol kapatılabilir; modül bağımsız kapanır.
- Tek aramada ortak araç kataloğu, 11 Pratik Araç, hızlı işlemler, kurulu
  uygulamalar, açık pencereler, mevcut pano geçmişi ve etkin metin kısaltmaları.
  Uygulama/pencere/pano/kısaltma sağlayıcıları ayrı kapatılabilir. Yeni pano
  kaydı veya klavye dinleme kendiliğinden açılmaz.
- Türkçe karakter/klavye varyantlarına tolerans; ortak katalog hem Türkçe hem
  İngilizce adlarını aratır. Çok sözcüklü sıralama, tür filtresi, sabitleme ve
  son kullanılan komut kimlikleri. Ham arama/pano metni arama geçmişine yazılmaz.
- `parlaklık 40` / `brightness 40`: imleç altındaki desteklenen harici ekran;
  `uyanık tut 30 dk` / `keep awake 30 min`: mevcut uyku servisi. Sayısal aralık
  ve sözdizimi doğrulanır; arama metni shell'e gönderilmez. Onay isteyen hızlı
  işlemler mevcut onaylı araç akışına yönlendirilir.
- Yerel ve etkinleşmeyen NSPanel; gerçekten ilk odağı alan NSTextField,
  ok/Enter/Escape, IME işaretli metni koruma, kontrol odağına göre tuş teslimi.
  Pencere ve uygulama keşfi yalnız panel açıkken yapılır; kapatma bekleyen
  sonuçları geçersizleştirir ve tuş dinleyicisini bırakır.
- Araç yönlendirmesi `PocketModel.openCatalogTool` altında birleştirildi; ana
  pencere ve palet aynı uygulama, klasör, tanı ve Pratik Araç durumunu açar.
- Pano düzeltmeleri: kayıp görsel çözülmeden mevcut pano silinmez; yazma başarısı
  doğrulanır; yapıştırma gecikmesinde hedef uygulama veya modül değişirse tuş
  gönderilmez. Metin kısaltması değişkenleri tek geçişte açılır; pano içindeki
  `{date}` gibi ifadeler sözlük sırasına göre yanlışlıkla yeniden genişlemez.

Doğrulama:

- `swift test`: 647 test, 4 isteğe bağlı test atlandı, 0 hata; arama ve sayısal
  komut sınırları ile kısaltma değişkeni regresyon testi dahil.
- Yerelleştirme: 3.438 anahtar, 0 eksik, 0 biçim uyuşmazlığı, 0 kullanılmayan
  çeviri. Sonuç/dakika çoğulları İngilizce `Localizable.stringsdict` içindedir.
- Türkçe/açık ve İngilizce/koyu izole native denemeler: gerçek `json` tuş girişi,
  arama odağı, oklarla seçim, Enter ile JSON aracına yönlendirme, Escape ve panel
  kaynaklarının bırakılması; çift dilli arama, doğrulanmış parametre satırı,
  boş sonuç, gerçek uygulama/pencere keşfi geçti. 20 modül/23 servis için üç
  aç/kapat döngüsü ve 0 kapalı-açılış servisi de tekrar doğrulandı.
- Geliştirme paketi ve derin/sıkı imza doğrulandı; `swift build -c release
  --product MacPocket` 82,32 saniyede başarılı oldu. Sürüm/build korundu.
- `.build/command-audit-tr.json`, `.build/command-audit-en.json`, aynı kökteki
  `.palette.png` ve ayar görünümü PNG'leri kanıttır; sağlayıcı keşfi yalnız
  sayım/başarı olarak kaydedilir. Palet görüntüsü kullanıcı pano veya pencere
  başlıklarını içermeyen araç kataloğuyla alınır.
- Bir erken deneme paketinde kontrollerden sonra kapanışta `objc_release`
  çökmesi görüldü. Deneme penceresinin sahipliği açık tutuldu, kapanışta metin
  düzenleyicisi bitirildi; sonraki normal Türkçe/İngilizce koşularda pencere
  kapat/yeniden aç döngüsü geçti ve çökme tekrarlanmadı. Eski koşulun tam kök
  nedeni stack'ten tek başına kanıtlanmış sayılmaz.
- Fiziksel global kısayol, dış uygulamaya gerçek yapıştırma, farklı Space'deki
  pencereye odaklama ve gerçek DDC parlaklık yazımı bu palet denetiminin kabul
  kapsamına dahil değildir. AltTab kart deneyimi değiştirilmedi.

### Uygulanan: Dosya Rafı

- Araçlar → Dosya Rafı; Git menüsü, menü çubuğu sağ tık menüsü ve Komut Çubuğu
  üzerinden erişim. Varsayılan global kısayol ⌃⌥S; değiştirilebilir veya
  kaldırılabilir. İsteğe bağlı, sürüklerken fareyi sallama ile imleç yanında
  açılış; bu seçenek kapalıyken global fare izleyicisi oluşturulmaz.
- Native NSTableView: çoklu seçim, klavye okları, Delete, ⌘C/⌘V; dosyaları,
  metinleri ve bağlantıları native pasteboard yazarlarıyla dışarı sürükleme.
  Çıkış işlemi kopyadır. Dosya seçici, pano ekleme, Finder'da gösterme ve native
  paylaşım seçicisi vardır. Karışık seçimler kopyalanırken düz metne çevrilir;
  yalnız URL/dosya seçimleri native URL listesi olarak korunur.
- Quick Look, rafa ait ayrı pencerede QLPreviewView ile açılır. Birden çok
  dosyada önceki/sonraki ve Escape vardır; ortak sistem önizleme panelinin
  denetimi devralınmaz. Raf kapanınca önizleme ve içerik de bırakılır.
- En fazla 100 öğe; yinelenen dosyalar aygıt/inode kimliğiyle elenir. Dolu raf
  eski öğeyi kendiliğinden atmaz. Metin başına 256 KB, doğrudan görsel girişinde
  20 MB kodlanmış veri ve 25 megapiksel sınırı vardır. Görsel çözme/kaydetme
  arka plandadır; hazırlık ve iptal görünür. Kaynak dosya boyutu bu görsel
  sınırına tabi değildir; büyük görsel normal dosya olarak eklenebilir.
- Dosyalar yerlerinde kalır. Bookmark ve dosya referansı yeniden adlandırmayı
  izler; eski konuma başka dosya gelirse onun kimliği yanlışlıkla kullanılmaz.
  Eksik/değişmiş dosya açıkça işaretlenir. Kopyalama/paylaşım/önizleme öncesi
  erişim tekrar doğrulanır; başarısız kopyalama mevcut panoyu silmez.
- Raf ve sabitlemeler Application Support/MacPocket/Shelf altında atomik JSON
  olarak saklanır. Pano görselleri ve teslim edilen dosyaların rafa ait
  kopyaları özel Files/UUID klasörlerindedir. Raftan kaldırma özgün dosyayı
  silmez; yalnız bu yönetilen kopyalar kendi doğrulanmış köklerinde temizlenir.
  Sabitlenmiş öğeler toplu temizlemede kalır. Bozuk/okunamayan arşiv otomatik
  üzerine yazılmaz; yeniden yükleme sunulur.
- NSFilePromiseReceiver ile kabul edilmiş bırakmadan sonra dosya hazırlanır.
  fileNames ancak istek başlatıldıktan sonra okunur. AppKit'in koordineli okuma
  callback'i içinde özel alana kopyalama yapılır; hazırlanan öğeler kapasiteyi
  rezerve eder. Hata, 90 saniyelik zaman aşımı, iptal ve geç dönen sonuçların
  temizliği vardır. İptal, başka uygulamanın yazma işlemini zorla durdurduğu
  anlamına gelmez.
- Yeni shelf modülüyle 21 modül/24 servis vardır. Modül kapanınca kısayol,
  fare izleyicisi, yükleme/görsel işleri, aktarım takibi, security scope'lar,
  raf ve önizleme bırakılır; kayıtlı raf içeriği korunur.

Bulunup düzeltilenler:

- Bookmark'ın eski yoldaki yeni dosyayı tercih etmesi: aygıt/inode doğrulaması
  ve CF dosya referansı geri dönüşü eklendi; Swift URL köprüsünün dosya referansını
  normal yola çevirmesi ayrıca hesaba katıldı.
- İlk açılışta NSPanel'in varsayılan boş contentView'ının gerçek arayüzün
  kurulmasını engellemesi.
- Etkinleşmeyen yüzen panelin ortak Quick Look denetimini alamaması; rafa ait
  native önizleme kullanıldı.
- Büyük görsel hazırlığında ana iş parçacığının meşgul edilmesi; işlem arka
  plana taşındı. Paylaşımda eski URL önbelleği yerine tıklamada yeniden doğrulama.
- Uzun metinlerde ortadan kesilen anlamsız özetler, boş rafın şeritli arka planı,
  temizleme sonrasında kalan eski kopyalama mesajı ve ağ bağlamından yanlış
  çevrilen bağlantı etiketi.

Doğrulama ve sınırlar:

- `swift test`: 653 test, 4 isteğe bağlı test atlandı, 0 hata. Altı yeni raf testi;
  kapasite/rezerve alan, yinelenen öğeler, sabitleme, arşiv, Unicode/metin sınırı,
  gerçek dosya yeniden adlandırma/değiştirme ve kaynak dosyaların korunması.
- `scripts/check-shelf-promises.sh`: 29 kontrol geçti. Gerçek aktarım yardımcısı,
  sentetik AppKit üreticisiyle başarı, kapasite, hata, iptal, gecikmiş teslim ve
  seçilen dizin dışındaki dosyanın reddi için çalıştırıldı. Bu, Mail/Photos ile
  gerçek uygulamalar arası sürükleme kabulünün yerine geçmez.
- İzole ModuleAudit uygulamasında Türkçe/açık ve İngilizce/koyu 55'er kontrol
  geçti. Dosya/metin/link/görsel ekleme, native çoklu seçim/yazarlar, ok/Delete/
  Escape, önizleme ileri/geri/Escape, diskten yeniden yükleme ve sabitlemeler,
  eksik dosya, başarısız kopyalamada pano koruma, görsel hazırlığı iptali ve
  kaynak bırakma doğrulandı. 21 modül/24 servisin üç aç/kapat döngüsü, kapalı
  açılışta sıfır servis oluşturma da tekrar geçti.
- Kanıt: `.build/shelf-audit-tr.json`, `.build/shelf-audit-en.json`, aynı adlara
  eklenen `.shelf.png` / `.shelf-empty.png`; `.build/shelf-promise-probe.json`.
  Dolu ve boş İngilizce/koyu görüntüler ile Türkçe/açık dolu görüntü incelendi.
  Yalnız üretilen fixture'lar ve özel pasteboard kullanıldı; kullanıcı panosu
  değiştirilmedi, gerçek paylaşım gönderilmedi.
- `scripts/check-localizations.sh`: 3.487 anahtar, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı, 0 kullanılmayan çeviri. Karakter/öğe sayıları çoğul
  kurallarıyla çevrilir. Debug uygulama paketi ve derin/sıkı imza kontrolü
  başarılı; son `swift build -c release --product MacPocket` başarılı.
  Info.plist sürüm/build değerleri HEAD ile aynı (0.1.4 / 7); tag/Release yok.
- Native yazar kontrolleri gerçek Finder/Mail/Photos sürüklemesini, fare sallama
  hareketinin fiziksel teslimini veya global ⌃⌥S kısayolunun fiziksel kabulünü
  kanıtlamaz. Bu uçtan uca kontroller ve VoiceOver ayrıca gerekir.

### Uygulanan: Dock Önizlemeleri

- Araçlar → Dock Önizlemeleri; katalog ve Komut Çubuğu yönlendirmesi. Yeni
  özellik başlangıçta kapalıdır. Modül kullanılabilirliği ile hover özelliğinin
  kendi açık/kapalı ayarı ayrıdır; tercihler korunur.
- Erişilebilirlik izni varsa pasif global/yerel fare izleyicileri Dock
  simgesini arar. Ana iş parçacığı dışında, yalnız ilgili ekran kenarında
  AX hit test; kısa mesaj zaman aşımı, sınırlı üst öğe yürüyüşü ve .app URL
  doğrulaması. Başlığa göre uygulama tahmini yapılmaz. İkonun URL'si çalışan
  uygulamaların URL'siyle eşleştirilir; birden çok örnek aynı grupta bulunabilir.
- Açılma/kapanma gecikmesi, geçerli masaüstü filtresi, görseller ve canlı
  yenileme ayrı ayarlanabilir. Uygulama hariç tutma listesi vardır. Alt/sol/sağ
  Dock ve negatif koordinatlı ekranlar için yerleşim hesaplanır; panel görünür
  ekran alanına sınırlandırılır. Son ikon çerçevesi ile panel arasındaki geçiş
  alanı, Dock gizlenirken de korunur. Dock tercihleri değiştirilmez.
- Başlık, görsel/simge, küçültülmüş/başka masaüstü durumu, öne getirme,
  küçültme/geri açma ve normal kapatma eylemleri. Desteklenen pencerelerde
  yarı/çeyrek/büyüt/ortala ve önceki/sonraki ekran yerleşimleri. Tek ekranda
  ekran değiştirme seçenekleri kapalıdır. Pencerenin AX yetenekleri kullanılır;
  işletim sisteminin kaydetme/onay akışları zorla atlanmaz.
- Kartlar kaydırılır; panel klavye odağı alınca oklar ve Enter/Escape çalışır.
  Klavyeyle seçim sırasında sabit fare konumu seçimi geri alamaz. Eylem
  sırasında yinelenen istekler engellenir; hata kullanıcıya gösterilir.
- Yeni katalog sorgusu processID ve uygulama URL'sine sınırlandırılır. Pencere
  işlemleri katalog kimliği/uygulama başlama zamanı üzerinden tekrar doğrulanır.
  Yerleşim, kartta seçilen AX penceresine uygulanır; öndeki pencereye gönderilmez.
  Var olan Alt+Tab kart akışı ve varsayılan katalog kapsamı korunur.
- Pencere görselleri yalnız izin varken, paneldeki kartlar için ve en çok üç
  paralel istekle alınır. Bellekte tutulur; panel kapanınca bırakılır. Simgeli
  görünüm Ekran Kaydı izni olmadan kullanılabilir. Küçültülmüş/yakalanamayan
  pencereler için görsel uydurulmaz. Liste yenileme yalnız açık panelde çalışır.
- Dışarı tıklama/kaydırma, başka uygulamaya geçme, Space/ekran değişimi, uyku,
  oturum kilidi veya hedef uygulamanın çıkışı paneli kapatır. İlgisiz uygulama
  çıkışı ve MacPocket'in kendi etkinleşmesi paneli gereksiz kapatmaz. Kapatmada
  işler iptal edilir, eski sonuçlar nesil kontrolünden geçemez; izleyiciler ve
  bildirim gözlemcileri modül durdurulunca kaldırılır. 22 modül/25 servis vardır.

Ortak pencere kodunda düzeltilenler:

- Önizleme kimliği artık WindowServer ID yanında sahip processID'yi ve
  uygulamanın hâlâ aynı oturumda çalıştığını da doğrular. İptal edilmiş iş
  yakalamadan önce durur. Geçersiz görsel boyutları reddedilir.
- Başka Space'deki pencere AX üzerinden bulunup yükseltilemezse yalnız uygulama
  etkinleşti diye başarı bildirilmez. Bekleyen pencere işlemlerinde iptal
  kontrolleri ve kısa AX mesaj zaman aşımı korunur.

Doğrulama ve sınırlar:

- `swift test`: 658 test, 4 isteğe bağlı atlama, 0 hata. Beş yeni Dock testi;
  üç kenar ve negatif/ikincil ekran koordinatları, simge–panel geçiş alanı,
  ekran kenarı sorgu sınırı, ayar/gecikme sınırları ve processID/URL kapsamı.
  Son ortak katalog değişiminden sonra ilgili 18 test ayrıca tekrar geçti.
- `scripts/check-localizations.sh`: 3.527 anahtar, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı, 0 kullanılmayan çeviri. Pencere sayısı İngilizce çoğul
  kurallarını kullanır; yeni ayar anahtarlarının açık erişilebilirlik adları vardır.
- İzole ModuleAudit uygulamasında Türkçe/açık ve İngilizce/koyu 80'er kontrol
  geçti; bunların 24'ü Dock kontrolleridir. Önceki modül/raf/Komut Çubuğu
  regresyonları da aynı koşuda çalıştırılır. 22 modül/25 servis için üç
  aç/kapat döngüsü ve kapalı açılışta sıfır servis oluşturma doğrulandı.
- Gerçek pencere kaynağı: `scripts/build-dock-fixture.sh`, yalnız .build içinde
  ayrı bundle kimlikli, iki pencereli `MacPocketDockFixture.app` üretir. Audit
  bu uygulamayı açıp gerçek WindowServer/katalog yoluyla iki pencereyi buldu;
  yalnız o processID'ye ait pencereler listelendi. Normal uygulama çıkışı isteği
  ve gerçek NSWorkspace hedef-çıkış bildirimiyle önizlemenin kapanması geçti.
  Yalnız döndürülen PID ve doğrulanan fixture URL/bundle kimliği sonlandırılır;
  kurulu kullanıcı uygulaması kapatılmaz. Yardımcı test uygulaması ürüne eklenmez.
- Kartların uzun başlık, küçültülmüş/başka masaüstü durumu, görünüm ve klavye
  testlerinde üretilmiş görseller ve temsili pencere tanımları kullanılır.
  Bu kontrollü görünümde dış fare/yaşam olayları fixture'ı değiştirmez; normal
  gerçek uygulama testi ayrı, olağan servis/olay yolunda çalışır. Sağ/sol/
  yukarı/aşağı, Escape, eski pencere kimliğinde hata, hariç tutma ve kaynak
  bırakma geçti. Kart alanı kendi kabul eden NSHostingView'ında ilk odağı alır.
- Bir ara Komut Çubuğu denemesinde paletin anahtar pencereyi kaybedip olağan
  resignKey kuralıyla kapandığı gözlendi; bu sırada uygulama etkin değildi.
  Arama/tuş kontrolleri bu nedenle geçmedi. Etkinleşmeyen panel için uygulamanın etkin olmasını
  şart koşan yanlış test önkoşulu kaldırıldı; doğru koşul panelin anahtar
  pencere olmasıdır. Kapanış/odak tanıları rapora eklenmiştir. Sahte sistem
  bildirimleri AppKit'e postalanmaz; sentetik olaylar yalnız servis işleyicisine
  verilir. Son Türkçe/İngilizce koşularda palet/klavye kontrolleri geçti.
- Kanıt: `.build/dock-audit-tr.json`, `.build/dock-audit-en.json`, eklenen
  `.dock.png`, `.dock-empty.png`, `.dock-live.png`, `.dock-settings.png`,
  `.dock-settings.ax.json` ve `.dock-keyboard.json`. Görünüm ve erişilebilirlik
  ağacı denetimi VoiceOver testi olarak sayılmaz. Temsili görseller ile gerçek
  pencere kaynağı ayrı kanıt türleri olarak kaydedilir.
- Fiziksel Dock hover teslimi, gerçek AX Dock hit testi, gizlenen Dock'a
  fareyle giriş/çıkış, gerçek başka-Space pencere eylemleri ve ScreenCaptureKit
  küçük resim yakalaması bu izole bundle'da izin/donanım kabulü değildir.
  Kapatma/yerleştirme kullanıcı pencerelerinde denenmedi. Geometri testleri ve
  temsili görseller bu kontrollerin yerine geçmez; tam eşdeğerlik iddiası yoktur.
- Debug uygulama paketi, derin/sıkı imza doğrulaması ve son release derlemesi
  başarılıdır. Sürüm/build HEAD ile aynıdır (0.1.4 / 7); tag veya Release yoktur.

Sıradaki iş uygulama başına ses çıkışıdır. Fare tuşları, kaydırmalı/sabitlenebilir
görüntü, güncelleme kanalları ve koşullu uyanık tutma kapsamda kalır. Dinamik
izin–modül eşlemesi altyapının sonraki genişletmesidir. Sürüm/build değiştirilmedi.


### Uygulanan: uygulama başına ses çıkışı

- Ses Mikseri satırlarında uygulamaya özel çıkış seçimi vardır. Tercih aygıt UID'si
  ve gösterim adıyla saklanır; ses düzeyi/sessize alma değişimleri bu tercihi silmez.
  Sıfırla, hem düzeyi hem çıkış tercihini kaldırır. Önceki yalnız volume/muted
  alanlı tercihler geriye uyumlu okunur. Yeni modül/servis eklenmedi: 22/25 korunur.
- Tercih edilen aygıt ayrıldığında mevcut sistem çıkışına yönlendirilir; tercih
  saklanır ve yeniden bağlantıda geri yüklenir. Varsayılan çıkış da yoksa başka
  bir aygıt rastgele seçilmez. %100/susturulmamış ve çıkış tercihsiz uygulama doğal
  ses yolunda bırakılır. Açık aygıt tercihi sistem varsayılanıyla aynı olsa da,
  uygulamanın kendi aygıt seçimini aşabilmek için yönlendirme kurulur.
- AppAudioTap, özel Core Audio process tap ve yalnız yakalama yapan özel aggregate
  ile girdiyi alır. Ayrı AVAudioEngine/AUHAL çıkışı seçilen aygıta bağlanır;
  sistemin varsayılan çıkışı veya fiziksel aygıt ses düzeyi değiştirilmez.
  Gerçek PCM biçimi doğrulanır; desteklenmeyen biçim açık hatayla reddedilir.
- Doğrudan giriş→çıkış tampon kopyası kaldırıldı. Önceden ayrılan tek üretici/tek
  tüketici stereo halka tamponu, nominal örnekleme dönüşümünü yapan AVAudioEngine
  ve sınırlı saat sapması düzeltmesi kullanılır. Float32/64 ve signed PCM
  16/24/32, endian/padding ve planar/interleaved düzenleri ele alınır. NaN/sonsuz
  örnekler susturulur, başlangıç kısa geçişle açılır; render gain atomiktir.
- Çıkış motoru çalışmadan kaynak uygulama susturulmaz. Kapanış yakalamadan başlar;
  eski yolun temizliği başka uygulamanın izin bekleyen kurulumu arkasında kalmaz.
  İptal edilmiş/geç kalan kurulumlar token ve atomik iptal bayrağıyla bırakılır;
  aynı satırda eski kurulum bitmeden yenisi başlatılmaz.
- Aygıt/süreç envanteri ve kurulum/kapanış UI iş parçacığından çıkarıldı. Envanter
  okumaları birleştirilir; başlatma/kapatma nesli doğrulanır. Yardımcı süreçler
  en uzun bundle önekiyle gruplanır. Core Audio nesnesi, PID ve libproc başlangıç
  zamanı kurulumdan önce/başlatmada tekrar doğrulanır. Aynı UID altında değişen
  nesne, biçim/hız ve yeniden açılan süreçte yol yeniden kurulur.
- Aygıt, varsayılan çıkış ve süreç olayları izlenir; modül kapanınca dinleyiciler
  kaldırılır. Callback durması veya AVAudioEngine yapılandırma değişiminde tek
  otomatik kurtarma denenir; tekrarlayan hatada doğal sese dönülür ve Yeniden
  Dene sunulur. Envanter okunamazsa eski varsayımla ses yakalamaya devam edilmez.
- Hazırlanıyor, geri dönülüyor, etkin, aygıt yok ve hata durumları ayrıdır. Aygıt
  yokken kayıtlı seçim menüden düşmez. Ses düzeyi/çıkış kontrolleri uygulama adını
  içeren erişilebilirlik adları taşır. İngilizce ortak “Çıkış: %@” anahtarının
  “Exit” anlamı ses durumunda kullanılmaz; bağlama özel “Ses çıkışı” anahtarı vardır.

Doğrulama:

- Tam `swift test`: 673 test, 4 isteğe bağlı atlama, 0 hata. Yeni 15 çekirdek testi;
  tercih taşıma ve bağlantı kaybı/dönüşü, stale token, PCM/endian/padding, tampon
  taşması/sarma/başlangıç/sessize alma, sayısal sınırlar, eşzamanlı üretici/tüketici
  ve ±yaklaşık 1000 ppm sürekli saat farkını kapsar.
- Native ModuleAudit, üretim VolumeMixerService koordinatörünü enjekte edilmiş
  envanter ve ses üretmeyen yollarla çalıştırır. Kurulum hatası/yeniden deneme,
  aygıt ayrılması/dönüşü, aynı UID'de nesne/hız değişimi, süreç yeniden açılışı,
  sınırlı otomatik kurtarma, callback durması, envanter hatası, modül kapanışı
  sırasında geç kalan kurulum ve kayıtlı sessiz tercihle yeniden başlatma sınanır.
- Ayrıca gerçek AVAudioEngine yalnız çevrimdışı modda 44,1 kHz stereo kaynağı
  48 kHz stereo çıktıya dönüştürdü; sonlu/sınırlı örnekler, kanal ilişkisi ve
  6.144 çıktı frame'i doğrulandı. Bu işlem fiziksel çıkışta ses çalmaz.
- Gerçek Core Audio aygıt/süreç envanteri salt okunur sorgulandı. Sayımlar
  `.build/audio-audit-{tr,en}.json.mixer-inventory.json` içindedir. Bu, process
  tap yakalaması veya duyulan sesin doğrulanması olarak sayılmaz.
- Türkçe/açık ve İngilizce/koyu native koşularda 111’er kontrol geçti; 31’i
  yeni mikser kontrolleridir. Çıkış menüsü, ses slider’ı ve yeniden deneme
  düğmesinin erişilebilirlik adları in-process AX ağacında doğrulandı. Başarılı,
  bağlantısı kesilmiş, hazırlanan, hata ve boş görünümler görüntülendi.
- Yerelleştirme: 3.548 anahtar, 0 eksik İngilizce çeviri, 0 biçim uyuşmazlığı,
  0 kullanılmayan çeviri. Debug paket ve derin/sıkı imza doğrulaması başarılı;
  optimize derleme 92,66 sn’de geçti. Sürüm/build HEAD ile aynı: 0.1.4 / 7.
- Kanıtlar
  `.build/audio-full-tests.log`, `.build/audio-tests.log`,
  `.build/audio-native-audits.log`, `.build/audio-audit-{tr,en}.json`, eklenen
  `.mixer*.png` ve `.ax.json`, `.build/audio-localizations.log`,
  `.build/audio-app-build.log` ve `.build/audio-release.log` içindedir.

Sınırlar: gerçek Core Audio process tap + aggregate yakalama, fiziksel aygıtlar
arasında duyulan ses, Bluetooth/AirPlay gecikmesi, çok kanallı kaynak düzeyi ve
canlı aygıt çıkarma/takma ayrıca kabul testi gerektirir. Temsili renderer
koordinasyon testleri ile çevrimdışı SRC bu donanım kabulünün yerine geçmez.
Sistem sesi izni otomatik verilmedi; kullanıcı uygulamalarının sesi değiştirilmedi.
VoiceOver ile kullanım ayrıca doğrulanmalıdır.

Sıradaki geliştirme fare tuşu atamalarıdır; kaydırmalı/sabitlenebilir görüntü,
kanal bazlı güncellemeler, koşullu uyanık tutma ve dinamik izin–modül eşlemesi
kapsamda kalır. Sürüm/build değiştirilmedi; tag veya GitHub Release oluşturulmadı.


### Uygulanan: Fare Tuşları

- Araçlar → Fare Tuşları ve ayrı açılıp kapatılan mouseButtons modülü eklendi.
  Katalog, Komut Çubuğu, araç yönlendirmesi, modül ekranı ve Erişilebilirlik
  açıklamasına bağlandı. 23 modül/26 servis vardır. Yeni atama özelliği varsayılan
  kapalıdır; açıldığında yalnız iki yan tuşun geri/ileri varsayılanı vardır.
- Orta/ek tuşlar (Core Graphics 2…31) ve yan tekerin iki yönü; geri/ileri,
  kopyala/yapıştır, özel KeyCombo, Komut Çubuğu, Pano Geçmişi veya Dosya Rafı'na
  atanabilir. Sol/sağ tıklama numaraları atama modeline alınmaz. Eksik/geçersiz
  kısayol, kapalı hedef modül ve kapalı Pano aracı girdiyi değiştirmez.
- Uygulama profili, belirtilmeyen tuşlarda genel atamayı devralır. Açık
  “Değiştirme” seçimi devralmayı durdurur. Hariç tutulan uygulama bütün atamaları
  aşar. Tercihler UserDefaults/ayar aktarımı kapsamında saklanır; modül kapanınca
  silinmez. Mevcut aktarım arayüzündeki yeniden başlatma kuralı korunur.
- Tuş algılama yalnız MacPocket penceresindeki yerel AppKit olaylarını dinler;
  10 sn sonunda, iptalde, uygulamadan ayrılınca, görünüm/modül kapanınca bırakılır.
  Elle tuş seçimi de bulunur. Aynı satırı tekrar eklemek var olan atamayı silmez;
  kaldırılan profil ataması yeniden genel ayarı devralır.
- Aktif event tap yalnız gerekli fare olaylarını izler. Basılı tuş sahipliği,
  sürükleme/bırakma ve tekrarlı down paketlerini ayırır. Yan tekerin kesintisiz
  paket serisi tek eylemdir; sürekli trackpad/Magic Mouse kaydırması dışarıda kalır.
- Fare Kaydırma, atanan yatay tekeri zayıf sahiplik kaydı üzerinden değiştirmeden
  bırakır; kapalı modülün singleton'ını oluşturmaz. Sıra değişse de iki servis
  aynı olayı hem kaydırma hem kısayol olarak işlemez. MacPocket'in ürettiği
  yumuşak kaydırma paketleri atama tetiklemez.
- Event tap içinde panel açma/tuş gönderme yapılmaz. Sonraki main-run-loop turunda
  nesil, hedef uygulama PID/başlatılma zamanı, izin/oturum ve modül durumu tekrar
  doğrulanır. Klavye olayları özel CGEventSource, açık modifier'lar ve dengeli
  down/up çiftiyle işaretlenir. Özel kısayollar normal oturum yoluna gönderilir.
- Uyku ve etkin kullanıcı oturumu ayrı izlenir; uyanma, etkin olmayan oturumu
  kendiliğinden açmaz. Güvenli giriş sırasında atama uygulanmaz. Modül kapatma
  bekleyen eylemleri iptal eder; tap, run-loop kaynağı, gözlemciler, algılama
  monitörü, zamanlayıcılar ve basılı tuş durumu bırakılır. Yeniden başlatmada
  modül kapalıyken kaçırılmış uyku durumuna takılmaz.

Aynı kapsamda düzeltilenler:

- MouseScrollTransform'taki abs(Int32.min) ve sınırsız delta→Int32 dönüşümü
  taşmaları giderildi; bozuk hız/süre ve yumuşak kaydırma kuyruğu sınırlanır.
  Uygulama değişiminde bekleyen glide iptal edilir. Uzayan hariç tutma listesi
  için Fare Kaydırma ekranı kaydırılabilir hale getirildi.
- KeyComboRecorder'da ikinci alan kayda girince ilk kayıt durur; uygulama odağı
  kaybında yerel klavye monitörü bırakılır. Görünen tuş adı geçerli klavye
  düzeninden okunur. Türkçe QWERTY-PC düzeninde sabit 33/30 kodlarının ğ/ü
  ürettiği gerçek CGEvent→NSEvent okumasıyla görüldü. Hazır geri/ileri ve
  kopyala/yapıştır olaylarına açık komut karakteri eklenir; kaydedilmiş özel
  kısayolun fiziksel tuş/yerleşim anlamı korunur. Kaynak: [Apple CGEvent Unicode
  API](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring%28stringlength%3Aunicodestring%3A%29).
- Dosya Rafı native ok testi boş karakterle NSEvent üretiyordu. NSTableView'in
  yerel key-binding yoluna gerçek ok function-key karakteri ve bayrakları
  gönderilir; önce/sonra anahtar pencere, responder ve seçim kaydı tutulur.
- Raf ilk tablo testinde sabit 300 ms yerine gerçek NSHostingView tablosu ve
  satırlarının oluşması sınırlı süre beklenir; zaman aşımı başarısızlıktır.
- Dock audit'i, Dock girintisi olmayan ikincil ekranda simgeyi ekran dışına
  koyabiliyordu. Temsili anchor hedef ekranın içinde oluşturulur; anchor/panel/
  ekran geometrisi ayrıca kaydedilir. Bu fixture düzeltmeleri üretim pencere
  klavyesini veya Dock geometri algoritmasını test için değiştirmez.
- Komut Çubuğu, gerçek alan editörü hazırken tuşları dengeli down/up ve gerçek
  function-key karakterleriyle, tek main-actor turunda NSApplication.sendEvent
  üzerinden alır; yerel monitör ve responder yolu çalışır. Uygulama/alan odağı,
  metin uzunlukları ve marked-text tanıları kaydedilir; kullanıcı metni rapora
  yazılmaz. Ek fare pencere testi palet klavyesi kontrolünden sonra çalışır ve
  kapanırken hosting içeriğini bırakır. Üretimde resignKey kapanışı korunur.

Doğrulama:

- swift test: 686 test, 4 isteğe bağlı atlama, 0 hata. Yeni 13 test; profil
  devralma/native override/hariç tutma, izin verilen tuş aralığı, kısayol
  geçerliliği, down/drag/up sahipliği, tekrarlı down, teker serileri, JSON taşıma
  ve bozuk/uç kaydırma değerleri. İlgili 21 test de ayrı geçti.
- Native audit, üretim fare handler'ını ses/klavye göndermeyen enjekte edilmiş
  eylem alıcısıyla çalıştırır. Tuş olayı oluşturma, modifier/marker ve down/up
  çifti ayrıca gerçek CGEvent nesnelerinde okunur; bunlar oturuma postalanmaz.
  Hazır komutun basma karakteri, bırakmada aynı fiziksel kod, kaydedilmiş
  kısayolun mevcut düzeni ve kayıt düğmesinin düzeni izleyen etiketi doğrulanır.
  AppKit, bırakma karakterini düzenden yeniden çıkarabildiği için komut
  karakteri basma olayına eklenir; bırakma aynı sanal tuşu serbest bırakır.
  Yerel algılama testi, fazladan tuş içeren NSEvent'i yalnız audit uygulamasının
  normal AppKit kuyruğuna postalar ve gerçek monitörde algılanmasını doğrular.
- Türkçe/açık ve İngilizce/koyu koşularda 152’şer native kontrol geçti; 41’i
  fare kontrolleridir. Genel yaşam döngüsü 23 modül/26 servisle üç aç/kapat
  döngüsünü ve kapalı açılışta servis oluşturmamayı doğruladı. Atama seçicileri
  ve açma düğmesinin adları AX ağacında kontrol edildi; 960 ve 760 genişlikte
  genel/profil ve izinsiz durumlar görüntülendi.
- Yerelleştirme: 3.582 anahtar, 0 eksik İngilizce çeviri, 0 biçim uyuşmazlığı,
  0 kullanılmayan çeviri. Debug paket ve derin/sıkı imza doğrulaması başarılı;
  optimize derleme 90,05 sn’de geçti. Sürüm/build HEAD ile aynı: 0.1.4 / 7.
- Kanıtlar:
  .build/mouse-tests.log, .build/mouse-full-tests.log,
  .build/mouse-audit-{tr,en}.json, .mouse-buttons.png/.mouse-profile.png ve AX
  ağaçları, .shelf-keyboard.json, .dock-geometry.json,
  .build/mouse-localizations.log, .build/mouse-app-build.log,
  .build/mouse-release.log. İlk Raf/Dock fixture hataları ayrı
  .shelf-arrow-failure.json, .shelf-readiness-failure.json ve
  .dock-fixture-failure.json raporlarıyla korunur. Odağını kaybeden palet
  denemesi ayrıca .focus-loss.json içinde tutulur; bütün koşu bu durumda
  başarılı sayılmaz.

Sınırlar: fiziksel fare/yan tekerin global event tap'e teslimi ve gerçek hedef
uygulamalarda tuşların etkisi ayrıca kabul testi gerektirir. Bu izole audit
bundle'ına Erişilebilirlik izni verilmedi; kullanıcı uygulamalarına kısayol
postalanmadı. Yerel AppKit algılama, genel HID teslimi değildir. VoiceOver
kullanımı ve farklı sürücülerin teker paketlemesi henüz kabul edilmedi.

Sıradaki geliştirme kaydırmalı/sabitlenebilir ekran görüntüsüdür. Kanal bazlı
uygulama güncellemeleri, koşullu uyanık tutma ve dinamik izin–modül eşlemesi
kapsamda kalır. Önceki ses/Dock donanım kabul sınırları da geçerlidir.
Sürüm/build değiştirilmedi; tag veya GitHub Release oluşturulmadı.

### Uygulanan: kaydırmalı ve sabitlenebilir ekran görüntüsü

- Araç ve Hepsi Bir Arada seçim çubuğuna Kaydırmalı modu eklendi. Kullanıcı
  yalnız kayan içeriği seçip kendisi kaydırır; durum penceresinden Bitir veya
  Vazgeç'i seçer. Sınırlı bölge ScreenCaptureKit ile alınır; fare/klavye
  müdahalesi veya yeni Erişilebilirlik/Giriş İzleme izni eklenmedi.
- Birleştirme aktörü durulan kareleri değerlendirir. Örtüşen satırları
  doğrular, sabit üst/alt alanları bir kez tutar; geri dönüşler içeriği
  çoğaltmaz. Belirsiz/örtüşmeyen hareketler eklenmez; son doğrulanmış görüntü
  korunur ve durum açıklanır. Dokulu sabit yan panel reddedilir; kullanıcı
  seçimi yalnız kayan içeriğe daraltmalıdır. Üst sınırlar 40 milyon piksel,
  60 bin satır, 120 bölüm ve 90 saniyedir; bunlar performans kabul iddiası
  değil, kodun kaynak sınırlarıdır.
- Önizleme, geçmiş, son çekim ve düzenleyiciden ekranda sabitleme eklendi.
  Tüm Space'lerde yüzen pencerede sığdır/%50/%100/%200, kaydırma, saydamlık,
  kopyalama, kaydetme/Finder'da gösterme ve düzenleme bulunur. En çok sekiz
  pin/48 milyon piksel tutulur; devam eden kapatılmış pin çıktıları da
  bütçeden düşülmez. Uzun resmin yalnız görünen kesiti çizilir. Pinler
  oturumluk bellektedir; modül durdurulunca kapanır.
- Yakalama sahipliği Task açılmadan alınarak çift başlatma yarışı giderildi.
  Ekran değişimi, uyku ve oturum kapanışı çekimi iptal eder. Geç dönen kare
  iptalden sonra yayımlanmaz. Hazırlık hatasında HUD ve monitörler kapanır;
  pin/düzenleyici pencereleri ve sahiplikleri temizlenir. Modül kapatma,
  kaydedilmemiş düzenlemeler ve devam eden çıktı için açıklama verir.
- PNG kodlama, kayıt, geçmişten tam görüntü okuma ve pano verisi hazırlama
  arka plana alındı. DPI kaynak ölçeğiyle saklanır/okunur. Yeni kayıtlar aynı
  dizindeki geçici dosyadan exclusive rename ile tamamlanır; eşzamanlı veya
  aynı saniyedeki kayıtlar birbirini ezmez. Düzenleyicinin açıkça seçilen
  dosyaya Kaydet işlemi atomik değiştirme kullanır. İşleme başarısız olursa
  işaretlenmemiş asıl resme sessizce dönüp dışa aktarmaz.
- Kaydedilmemiş önizlemeyi sürükleme, AppKit dosya vaadiyle bırakma sonrası
  arka planda hazırlanır. Bu, kullanıcı tarafından kabul edilmiş bırakma
  işidir; pinin kapanmasıyla iptal edilen kopyalama işiyle aynı değildir.

Doğrulama: 705 birim testi, dört isteğe bağlı atlama, sıfır hata. Yeni 19 test;
piksel sırası/yön, sabit alan, geri kaydırma, belirsizlik, gerçek CoreText
metni, yan panel, sınırlar, 12 eşzamanlı dosya yazarı, iptal, DPI ve negatif/
küçük ekran geometrisini kapsar. İlgili 26 test ayrıca geçti. İlk tam koşuda
mevcut Vision OCR testi e5rt yürütme hatası verdi; ayrı tekrar ve son tam
koşu geçti. İlk hata .build/scroll-full-first-vision-failure.log içinde
korunur; bu geçici işletim sistemi hatası için üretim kodu değiştirilmedi.

Türkçe/Aqua ve İngilizce/DarkAqua koşularda 185'er native kontrol geçti;
33'ü bu akışa ait. Kontrollü kareler üretim oturum/birleştirme/sonlandırma
yolundan geçirilir; aynı anda başlatma, geç tamamlanan iptal, kaynak hatasında
güvenilir bölüm, ekran değişimi, modül durdurma, pinin native kapanışı,
yakınlaştırma/saydamlık ve AX denetim adları doğrulanır. Dosya vaadinin
arka plan yazarı geçici alanda PNG üretir; geri okunan geometri/ölçek ve
üzerine yazmama kontrol edilir. Kullanıcı panosu ve masaüstü yakalanmadı.
İlk AX denemesinde yinelenen slider/picker adı bulundu ve düzeltildi; hata
.build/scroll-audit-tr.first-ax-failure.json ve scroll-pin-first-ax-failure.json
içinde tutulur. Gerçek araç/HUD/pin pencereleri iki dilde görüntülendi.

Yerelleştirme: 3.616 anahtar, sıfır eksik İngilizce, biçim uyuşmazlığı veya
kullanılmayan çeviri. Debug paket ve derin/sıkı imza kontrolü geçti; son optimize
derleme 89,55 saniyede tamamlandı. Kanıtlar:
.build/scroll-focused-tests.log, scroll-full-tests.log, scroll-vision-recheck.log,
scroll-audit-{tr,en}.json ve .scroll-hud.png/.screenshot-pin.png/
.screenshot-tool.png/.screenshot-tool-pins.png ile AX ağaçları,
scroll-localizations.log, scroll-app-build.log, scroll-release.log.

API dayanakları: Apple'ın SCStreamConfiguration.sourceRect tanımı seçimi
ekranın mantıksal noktalarıyla alır; piksel boyutu kaynak ekran ölçeğiyle
ayarlanır. SCScreenshotManager aynı filtreyle tek kareler sağlar. AppKit'in
NSFilePromiseProviderDelegate operationQueue kılavuzu dosya hazırlamayı ana
kuyruktan ayırır:
https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect
https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager
https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate/operationqueue(for:)

Sınırlar: test kareleri gerçek uygulamada ScreenCaptureKit teslimi değildir.
Safari/PDF/editör gibi hedeflerde gerçek kaydırma, Retina/çoklu ekran, sabit
araç çubukları, animasyon/video, HDR ve hedef uygulamaya sürükleyip bırakma
henüz kabul edilmedi. Sürekli değişen veya yinelenen içerikte eşleştirme
başarısız olabilir; sistem doğrulanmamış satırları tahmin etmez. Bitir/Vazgeç
HUD üzerinden kullanılır; global Escape kancası eklenmedi. VoiceOver ile
elle kullanım ayrıca test edilmelidir. Tam araç eşdeğerliği iddiası yoktur.

Sıradaki geliştirme uygulama güncelleme kaynakları/kanallarıdır. Koşullu
uyanık tutma ve dinamik izin–modül listesi kapsamda kalır. Sürüm/build
0.1.4 / 7 olarak korundu; tag veya GitHub Release oluşturulmadı.

### Uygulanan: uygulama güncelleme kaynakları ve kanalları

Uygulamalar → Güncellemeler ekranına Homebrew, App Store ve uygulama içi
Sparkle listesi seçimi eklendi. Başlangıçta yalnız mevcut Homebrew kaynağı
açıktır. Ağ kaynakları kullanıcı seçip Denetle'ye bastığında çalışır; tercih,
mağaza ülkesi ve ön sürüm seçimi saklanır. Kaynak değişikliği eski sonuçları
ve önceki iptal bilgisini geçersiz kılar. Denetim ilerlemesi/iptali vardır; tamamlanan kaynakların
sonuçları korunur, eşleşmeyen/atlanan/hatalı kaynaklar güncel sayılmaz.

- App Store en fazla 20 bundle kimliğini desktopSoftware sorgusunda toplar;
  ülke doğrulanır, istekler arasında en az 3,2 saniye bırakılır. Yanıtta hem
  bundle kimliği hem mac-software türü eşleşmelidir. Kaldırılmış veya o
  mağazada bulunamayan kayıt, boş katalog sonucu olarak ayrı sayılır.
  Bulunan sürüm App Store'da açılır; MacPocket mağaza güncellemesi kurmaz.
- Uygulama içi kaynak, kurulu paketin SUFeedURL değerini yeniden okur;
  envanterdeki dosya kimliği değişmişse kullanmaz. Atomik ya da toplu
  uygulama değiştirme eklenmedi. Sonuç uygulamayı açar; kullanıcı kendi
  Güncellemeleri Denetle komutunu kullanır. MacPocket'in kendi güncelleyicisi
  mevcut ayrı Sparkle akışında kalır.
- Feed sürümü CFBundleVersion ile, kullanıcıya gösterilen sürüm ise ayrı
  shortVersionString ile değerlendirilir. Sparkle'ın sürüm karşılaştırıcısı
  kullanılır; minimum/maksimum macOS ve donanım gereksinimleri uygulanır.
  Ön sürüm kanalları varsayılan olarak dışarıda kalır. Delta, Windows ve
  geçersiz dosya bağlantıları aday değildir; paket URL'leri indirilmez.
  Aynı feed bir denetimde bir kez okunur. Homebrew ile eşleşen uygulamalar
  diğer kaynaklarda çoğaltılmaz; Homebrew yerel katalog davranışı korunur.
- Metadata taşıyıcısı ephemeral HTTPS oturumu kullanır: cookie/credential
  deposu ve URL cache yoktur, TLS doğrulaması değiştirilmez. Yanıt/akış
  2 MiB, redirect sayısı beş, istek 15/oturum 25 saniye ile sınırlıdır;
  HTTPS dışına veya kullanıcı/parola içeren adrese yönlendirme reddedilir.
  XML UTF-8/UTF-16 olarak, namespace'leriyle okunur; DTD/entity reddedilir,
  derinlik ve öğe sayısı sınırlıdır. Parser harici entity çözmez.

Doğrulama: tam pakette 722 test, dört isteğe bağlı atlama, sıfır hata. Yeni
17 test; sürüm/build ayrımı, eski enclosure biçimi, namespace takma adı ve
sahte namespace, kanal/sistem/donanım, delta/platform, bozuk/büyük/entity XML,
mağaza kimliği/Mac türü, boş sonuç, ülke/batch, tercih saklama ve gerçek
URLSession yolunda kontrollü HTTP 429/boyut/iptal senaryolarını kapsar.
İlgili 17 test ayrıca geçti; UTF-16LE/BE listelerinde BOM olmadan
entity bildiriminin reddi de doğrulandı. Debug paket ve derin/sıkı imza denetimi geçti;
son optimize derleme 87,65 saniyede tamamlandı. Yerelleştirme 3.639 anahtar,
sıfır eksik İngilizce, biçim uyuşmazlığı veya kullanılmayan çeviri.

Native audit, geçici uygulama paketlerini gerçek envanter okuyucusundan
geçirip üretim scanner/model/arayüz yolunu kullanır. Store kimliği, eşleşmeyen
kayıt, feedsiz uygulama, aynı build'in yeniden önerilmemesi, ortak feed,
ön sürüm seçimi, hata yalıtımı, iptal, tüm kaynaklar kapalıyken ağsızlık,
adlandırılmış anahtarlar/sağlayıcı düğmeleri ve 960/760 genişlik doğrulanır.
İsteğe bağlı ağ koşusu yalnız açıkça seçilmiş herkese açık Xcode/Things
kimliklerini ve Sparkle'ın resmi örnek feed'ini sorgular. Kullanıcının kurulu
uygulama listesi gönderilmez; uygulama açılmaz veya güncelleme kurulmaz.
Son kaynak-odaklı koşuda Türkçe ve İngilizce 20’şer kontrol geçti;
raporun scope alanı application-update-sources, sessionLocked alanı true’dur.
Bu sonuç bütün uygulamanın klavye odağı kabulü değildir.
İlk AX denemesi boş switch adlarını gösterdi; açık erişilebilirlik etiketi
eklendi. Ham NSHostingView'in pencereyi içerik ölçüsüne büyütmesi, fixture'da
ölçü seçenekleri ve açık viewport ile giderildi. Sonraki bir palet odak
kaybı bütün koşuyu başarısız yaptı; .build/update-focus-loss.json korunur.
Tekrarlar sırasında CGSessionCopyCurrentDictionary oturumu kilitli bildirdi
(CGSSessionScreenIsLocked = 1); normal pencere de key olamadı. Ek host/yeniden
açma denemeleri kaldırıldı; üretim paletinin resignKey davranışı değiştirilmedi.
Kilitli son bütünleşik koşu 205 kontrolden 204’ünü geçirdi, commandBarTestPaletteKey
geçmedi. Kilit açılınca bütünleşik koşu tekrarlanmalıdır; kullanıcıya kilidi
açtığında bildirmesi istendi. Önceki 202’şer kontrol geçen iki dil koşusu ve
sonraki başarısız raporlar birbirinin yerine kabul edilmez.
Bitmapler AppKit view cache çıktısıdır; masaüstü kompozitörü veya fiziksel
klavye/global kısayol kabulü olarak sunulmaz.

Kanıtlar: .build/update-focused-tests.log, update-full-tests.log,
update-source-audit-{tr,en}.json (yalnız kaynaklar),
update-audit-tr.json (kilitli bütünleşik başarısız koşu) ve .update-sources.png/.update-source-error.png/
.update-sources-off.png ile AX ağaçları, update-first-ax-failure.json,
update-localizations.log, update-app-build.log, update-release.log.
Herkese açık ön inceleme yanıtları appstore-current-fixture.json ve
sparkle-public-fixture.xml içinde tutulur. İlk Pages örneği mağazada
bulunamadığı için güncel kabul edilmedi; canlı fixture mevcut Xcode/Things
kayıtlarıyla doğrulandı.

Dayanaklar: Apple Search API ülke/tür/batch ve yaklaşık istek sınırlarını,
Sparkle yayınlama belgesi build, gösterilen sürüm, kanal ve sistem alanlarını
tanımlar. Bundle kimliğiyle toplu desktopSoftware lookup davranışı ayrıca
gerçek HTTPS yanıtıyla doğrulandı; arşiv belgesindeki tüm örneklerin hâlâ
mevcut olduğu varsayılmadı.
https://performance-partners.apple.com/search-api
https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/LookupExamples.html
https://sparkle-project.org/documentation/publishing/
https://sparkle-project.org/documentation/api-reference/Classes/SUStandardVersionComparator.html

Sınırlar: App Store bölgesel, aşamalı veya kaldırılmış dağıtımlarda kayıt
vermeyebilir; katalog bulunamaması kurulu uygulamanın güncel olduğu değildir.
Üreticinin özel kimlik doğrulaması, çalışma anında değiştirdiği URL/kanallar,
info-only feed'leri ve uygulamaya özel uygunluk kuralları desteklenmiş
sayılmaz. Metadata imzası/kurulum kabulü üreticinin güncelleyicisine aittir;
MacPocket metadata okumasını imza doğrulaması olarak sunmaz. Gerçek mağazada
açma, üretici uygulamasında kurma, tüm yayıncı biçimleri ve VoiceOver ile
elle kullanım ayrıca kabul testi gerektirir. Setapp/GitHub repo tahminiyle
otomatik güncelleme ve tam araç eşdeğerliği iddiası eklenmedi.

Sıradaki geliştirme koşullu uyanık tutmadır; dinamik izin–etkin modül
eşlemesi de kapsamda kalır. Sürüm/build 0.1.4 / 7 olarak korundu; tag veya
GitHub Release oluşturulmadı.

### Uygulanan: koşullu uyanık tutma

Güç Merkezi'ndeki Uyanık Tut kartına otomasyon kuralları, Tools oturum
penceresine bu kurallara bağlantı eklendi. Başlangıçta kapalıdır. Seçilen
uygulama, harici ekran ve şebeke gücü koşulları Tümü/En Az Bir seçenekleriyle
birleştirilir; koşul listesi veya seçilen uygulama listesi boşken etkinleşmez.
Uygulama seçimi yerel paket kimliği/adı olarak saklanır; ağ sorgusu yapılmaz.
Her koşulun eşleşmesi gösterilir. Ekranı açık tutma ayrı seçilir; varsayılan
otomasyon yalnız sistemin boşta uykusunu etkiler. Kilitte duraklatma açıktır.

Tek koşul döngüsünün varsayılan sınırı iki saattir; 30 dk–8 saat seçilebilir.
Monotonik süre kilitte geçen zamanı da içerir. Süre bittiğinde, koşullar
sağlanmaya devam ediyor diye yeni oturum açılmaz. Yeniden değerlendirme
kullanıcının açık eylemidir. Elle başlat/durdur önceliklidir; uygunluk önce
bozulup yeniden sağlanmadan otomasyon geri gelmez. Manuel süre bitimi de
kendiliğinden otomasyonu başlatmaz.

Ayrı genel zamanlayıcı veya izleyici eklenmedi: mevcut PocketModel tick'i
kullanılır. Kapalıyken çevre sensörleri okunmaz veya assertion alınmaz.
Etkin değerlendirme canlı IOPS, NSScreen ve çalışan uygulama kimliklerini
kullanır; duraklatılmış metriklerin eski güç örneğine dayanmaz. Oturum kilit
bilgisi alınamazsa varsayılan davranış duraklatmadır.

SleepController'a atomik startIfIdle ve UUID denetimli stop eklendi. Otomasyon
yalnız kendi UUID'sini durdurabilir; kontrol ile oluşturma arasına giren
manuel oturumu değiştiremez. Geç sonuç da aynı kuralla temizlenir. Oluşturma
ve başarısız geri alma durumunda UUID daha önce kaydedildiğinden kısmi native
sahiplik kaybolmaz. Oluşturma 30, bırakma beş saniye aralıkla yeniden denenir;
hata gizlenmez. Yerel sürücü bırakmayı reddederse sahiplik korunur; süre sınırı
bu başarısız native bırakmanın mutlaka gerçekleştiği iddiası değildir.

Bulunan ek hata: Odak Oturumu bittiğinde, kullanıcı sonradan yeni bir manuel
oturum başlatmış olsa bile genel stop çağrılıyordu. Odak artık yalnız
kendisinin aldığı UUID'yi bırakır; başarısız başlatmayı uygulanmış saymaz.
Bu bütünleşme statik kodla ve gerçek SleepController eski UUID/yenisi
testiyle doğrulandı; Odak'ın bütün yan etkileriyle elle kabulü yapılmadı.

Doğrulama: 734 test, dört isteğe bağlı atlama, sıfır hata. Yeni on politika
testi ve iki gerçek IOKit sahiplik testi var; ilgili 19 test ayrıca geçti.
16 eşzamanlı startIfIdle çağrısından tek sahip çıkar; eski UUID sonraki
oturumu durduramaz. Kilit, elle müdahale, saat sapması, süre sınırı ve
bilinmeyen güç/kilit bilgisi politika testleriyle kapsanır.

Türkçe/Aqua ve İngilizce/DarkAqua koşularda 25'er kontrol geçti: gerçek
koordinatör/politika, kontrollü sürücüde geç sonuç, manuel öncelik, limit,
hata sonrası tekrar, kısmi oluşturma, kapatma ve AX denetim adları.
Ek native bölüm Mac Studio'nun gerçek şebeke girdisiyle, audit sürecinde
tek sistem-idle assertion oluşturup IOPMCopyAssertionsByProcess'te UUID ve
türünü gördü; otomasyon kapatılınca kaybolduğunu doğruladı. Bu kısa testte
ekran assertion'ı, uyandırma/kilit açma API'si veya kalıcı güç ayarı kullanılmadı.
Testin özel tercihi kilitte duraklatmayı bu kısa sistem-idle kontrolü için
kapatır; üretim varsayılanı değişmez. Canlı girdiler harici ekran/şebeke/kilit
true olarak kaydedildi. Pil, AC çıkarma, fiziksel ekran çıkarma ve gerçek
uygulama yaşam döngüsü kabulü bu test değildir; MacBook pil donanımı doğrulanmadı.

İlk seçici AX adı hatası düzeltildi; önceki başarısız rapor korundu.
Kanıtlar: .build/awake-focused-tests.log, awake-full-tests.log,
awake-audit-{tr,en}.json ve .awake-rules.png/.awake-app-rule.png/
.awake-live-input.json, awake-first-picker-ax-failure.json,
awake-localizations.log, awake-app-build.log, awake-release.log.
Yerelleştirme 3.671 anahtar/sıfır eksik veya biçim hatası; debug paket,
imza ve 91,90 sn optimize derleme başarılı. Sürüm/build 0.1.4 / 7 korundu.

Apple'ın [idle-sleep assertion tanımı](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
bu isteğin yalnız hareketsizlikten doğan uykuyu engellediğini belirtir;
elle uyku, kapak ve düşük pil davranışını macOS yönetir. Bu çalışma
PreventSystemSleep veya kapak kapalı uyku davranışı eklemez.

### Uygulanan: dinamik izin–modül eşlemesi

İzin ekranındaki sabit araç cümleleri yerini çekirdekteki PermissionUsageMap'e
bıraktı. Açık/kapalı modüller ayrı tutulur; kapalı modüller daraltılabilir
listede görünür. İlerleme/eksik sayımı yalnız mevcut modüller ve sürekli
kullanılabilen çekirdek araçlar içindir. Temizlik, Disk Analizi, Uygulama
Kalıntıları, Wi-Fi ve izleme uyarıları modül kapatılınca yanlışlıkla yok sayılmaz.

Ekrandan Al'ın ekran kaydı bağımlılığı ve Odak/Gizlilik bildirim bağımlılıkları
eklendi. Ses Mikseri'nin ses-only izni, CGPreflightScreenCaptureAccess sonucuyla
verilmiş sayılmaz; satır açıkça ayrı denetimi açıklar. Fare tuşları, pil HID
okumasının Giriş İzleme iznini otomatik olarak gerektiriyormuş gibi sunulmaz.

Mevcut izin yok sayılmaz veya geri alınmaz. Kapalı modül için eylem ve
önerilen etiketi gizlenir; request anında güncel tercihler yeniden okunur.
Kapalı bir bağımlılık eski yeniden başlatma önerisini veya sürükleme yardımını
açık tutmaz. Onboarding mevcut durum yenilemesinde modül değişikliklerini
de izler; sırf bu ekran açıldı diye servis başlatılmaz veya izin istenmez.

Beş yeni çekirdek test; tümü kapalıyken kalan çekirdek izinleri, bölümlenen
modül listesi, ekran araçları, HID ayrımı ve bildirim/ses ayrımını doğruladı.
Türkçe/Aqua ve İngilizce/DarkAqua koşularda dokuzar kontrol geçti: gerçek
modelde tercih değişimi, kapalı isteğin engellenmesi ve gerçek satır
bileşenlerinde 3/4/6 izin eylemi. Satır eylemleri kontrollü sayaçtır;
macOS'tan izin istenmedi, ayar açılmadı. Kanıtlar .build/permission-tests.log,
permission-audit-{tr,en}.json ve .permissions-off.png/
.permissions-screenshot.png/.permissions-all.png ile AX ağaçları,
permission-localizations.log ve permission-app-build.log içindedir.
Yerelleştirme 3.671 anahtarda sıfır eksik/biçim hatası/kullanılmayan çeviriyle geçti.

### Son kapsam doğrulaması

739 test, dört isteğe bağlı atlama, sıfır hata: .build/final-scope-tests.log.
Optimize derleme 89,00 sn: .build/final-scope-release.log. Debug paket ve
sıkı/derin imza: .build/permission-app-build.log ve final-scope-signature.log.
Yerelleştirme .build/permission-localizations.log içinde 3.671 anahtarda
sıfır eksik, biçim uyuşmazlığı ve kullanılmayan çeviriyle geçti. Info.plist'in
sürüm/build değerleri HEAD ile aynı: 0.1.4 / 7. Kurulu uygulama değiştirilmedi;
yalnız çalışma alanındaki paket üretildi. Audit/fixture süreçleri kapandı.

Kilitli son bütünleşik koşu 239 kontrolün 238'ini geçirdi. Tek başarısızlık
commandBarTestPaletteKey'dir; rapor hem sessionLocked=true hem appActive=false
kaydeder. Bu bütün koşunun başarıyla geçtiği anlamına gelmez. Kanıtlar
.build/final-scope-native.log ve final-scope-native-tr.json içindedir.
Önceki güncelleme aşamasındaki 205 kontrol ifadesi tarihsel sonuçtur; daha
sonra eklenen 25 otomasyon ve dokuz izin kontrolü toplamı 239'a çıkarmıştır.
Türkçe/İngilizce kaynak-odaklı koşular ayrı ayrı 20, otomasyon 25 ve izin
kullanımı dokuz kontrolle geçti. Bunlar kilit gerektiren klavye kabulünün
ve önceki aşamalarda açıkça belirtilmiş donanım sınırlarının yerine geçmez.

Planlanan yazılım aşamaları uygulanmıştır: modüller, Komut Çubuğu, Dosya Rafı,
Dock önizlemeleri, uygulama başına ses, fare atamaları, kaydırmalı/sabit
çekim, güncelleme kaynakları ve koşullu uyanık tutma; dinamik izin eşlemesi de
bağlanmıştır. Hedefin tamamı başarılmış sayılmadan önce son gereksinim/kanıt
denetimi ve kilit açıldıktan sonra klavye odağı doğrulaması gereklidir.
Bu kayıt tam AltTab/iStat/CleanMyMac eşdeğerliği iddiası değildir.

### Gereksinim bazlı tamamlanma denetimi

Kaynak kapsamı, bu belgenin kullanıcı tarafından onaylanan dokuz aşaması ve
sonraki dinamik izin eşlemesidir. Salt dosya varlığı tamamlanma sayılmadı:
üretim bağlantıları, ilgili testlerin neyi ölçtüğü, mevcut native raporun
kontrolleri ve önceki gerçek/temsili kanıt ayrımı incelendi. Kaynak/test SHA-256
özetleri ve gözlenen sonuçlar .build/goal-completion-audit.json içindedir.

| Gereksinim | İncelenen uygulama | Güncel kanıt | Pratik sınır / açık nokta |
| --- | --- | --- | --- |
| Modül yaşam döngüsü | Core ModuleLifecycle ve gecikmeli PocketModuleRuntime bağları | Native 16 kontrol; üç döngü, kapalı açılış, 26 servis ve kaynak bırakma | Gerçek kayıt/DDC/çökme yan etkileri önceki bölümlerde ayrı |
| Komut Çubuğu | Arama/sayısal ayrıştırıcı, sağlayıcılar, panel ve yönlendirme | 13 native kontrolden 12'si geçti; geçmiş iki dil koşuları ayrıca mevcut | Güncel key-window kabulü kilit nedeniyle başarısız; eski başarı bunu değiştirmez |
| Dosya Rafı | Model, bookmark/kimlik, özel depolama, panel ve aktarım yardımcısı | Native 27 kontrol; ayrıca korunmuş 29 dosya-vaadi kontrolü ve Core testleri | Finder/Mail/Photos gerçek bırakma ve fiziksel sallama ayrıca |
| Dock önizlemesi | Hedef uygulama/URL kapsamı, geometri, kart/eylemler, iptal | Native 24 kontrol; gerçek iki pencereli fixture ve geometri testleri | Gerçek Dock AX hover ve ekran küçük resmi izni kabulü ayrıca |
| Uygulama başına ses | Tercih/aygıt yaşam döngüsü, process tap, halka tamponu ve çıkış motoru | Native 31 kontrol, gerçek çevrimdışı AVAudioEngine dönüşümü, PCM/yarış testleri | Fiziksel iki aygıt arasında duyulan ses ve process-tap izin kabulü kanıtlanmadı |
| Fare atamaları | Bağlama/profil/teker politikası, üretim handler'ı ve tuş üretimi | Native 41 kontrol; gerçek CGEvent nesneleri ve yerel algılama | Fiziksel HID teslimi ve kullanıcı uygulamasında tuş etkisi ayrıca |
| Kaydırmalı/sabit çekim | Stabil kare birleştirme, ScreenCaptureKit kaynağı, pin ve çıktı ömrü | Native 33 kontrol, piksel/gerçek metin, dosya çakışma ve bütçe testleri | Gerçek Safari/PDF kaydırması, izin ve dış uygulamaya bırakma ayrıca |
| Güncelleme kaynakları | Homebrew/Store/Sparkle seçimleri, bounded HTTPS ve uygunluk | Native 20 kontrol; iki dil kaynak-odaklı rapor, gerçek Apple/resmi Sparkle yanıtı | Kurulum bilerek sağlayıcıya ait; gerçek mağaza açma/kurma yapılmadı |
| Koşullu uyanık tutma | Monotonik politika, UUID sahipliği, manuel öncelik ve mevcut tick | Native 30 kontrol; gerçek audit UUID'sinde IOKit alma/bırakma ve dokuz SleepController testi | MacBook pil donanımı, fiziksel AC/ekran çıkarma ve tam Odak akışı ayrıca |
| Dinamik izin eşlemesi | PermissionUsageMap, model yenileme, ilgili sayaç/eylem/yardım | Native dokuz kontrol ve beş Core testi; eylemler OS isteği göndermeden kontrol edildi | VoiceOver ile elle kullanım ayrıca; ekran durumu ses izni sayılmıyor |

Pencere geçişi değişmezi de kaynakta tekrar kontrol edildi: panel kökü
WindowSwitcherOverlayView'dır; Tab/Shift+Tab seçimi ve normal arama-boş
oturumda tutulan modifier bırakılınca commit akışı korunur. Tools ayar
sayfası birincil geçiş yüzeyi yapılmadı. Fiziksel global teslim için bu
statik kontrol kabul testi diye sunulmaz.

Tamamlanma denetiminde ek bir sahiplik yarışı bulundu ve giderildi. Odak,
startAwake'ten dönen oturum kimliğini almak yerine sonradan değişebilen
model.awakeSession'ı okuyordu. startAwake artık oluşturduğu oturumu döndürür;
Odak o dönüşe bağlanır. Geciken eski manuel başlatma/durdurma/status sonucu,
yeni manuel işlemin arayüzünü ezemez. Varsayılan üretim davranışını değiştirmeyen
izleme-kapalı model ve kontrollü controller ile beş yeni native regresyon
kontrolü eklendi: eski dönüş, yeni arayüz, eski UUID temizliği, açık durdurma
ve durdurmadan sonra gelen geç başlatma. Türkçe/Aqua ve İngilizce/DarkAqua
koşularda otomasyonun 30'ar kontrolü geçti. Kanıt
.build/completion-awake-audits.log ile güncel awake-audit-{tr,en}.json'dır.

Bu düzeltmeyle son tam takım .build/completion-tests.log içinde 739 test,
dört isteğe bağlı atlama ve sıfır hata verdi; 55,25 sn. Atlananlar üç gerçek
home-folder taraması ve bir özel disk-image çıkarma testidir; kaynakları
incelendi, eklenen özelliklerin yerine geçecek kanıt olarak kullanılmadılar.
Optimize derleme .build/completion-release.log içinde 92,33 sn'de geçti.
Yerelleştirme .build/completion-localizations.log içinde 3.671 anahtarda
sıfır eksik/biçim hatası/kullanılmayan çeviriyle geçti. Son debug paket
completion-app-build.log, derin/sıkı imza completion-signature.log içindedir.

Güncel bütünleşik rapor .build/completion-audit-tr.json: 244 kontrol,
243 başarı, yalnız commandBarTestPaletteKey başarısız. sessionLocked=true,
appActive=false. Başarısız Türkçe koşu üzerine script'in İngilizce bütünleşik
koşuyu başlatmaması olağan davranıştır; İngilizce bütünleşik başarı iddiası
yoktur. Aynı engel üç ardışık hedef çalışma turunda gözlendi. Mac'in kilidi
kullanıcı tarafından açılmadan bu kabulü tamamlamak mümkün olmadığından
hedefin tümünün tamamlanması kanıtlanmış sayılmadı. Kilit açma otomasyonu,
izinleri kendiliğinden verme veya başarısız kontrolü geçer sayma yapılmadı.

Sürüm/build 0.1.4 / 7 olarak HEAD ile karşılaştırıldı. AI Dosyaları/AI Clutter
kaynak/arayüz kapsamına geri eklenmedi. Kaynak dil Türkçe ve İngilizce tablolar
korundu; sürüm etiketi veya GitHub Release oluşturulmadı. Kurulu uygulama
ve kullanıcı uygulamalarının ses/klavye/pano içeriği kabul için değiştirilmedi.
Tam araç eşdeğerliği ve MacBook şarj donanımı iddiası yoktur.

### Kilit açıldıktan sonraki son kabul — 5 Kasım 2026

Kullanıcı devam istediğinde oturum yeniden kontrol edildi: konsolda ve giriş
tamamlanmış durumdaydı; kilit bayrağı artık yoktu. Son başarılı paket/kaynak
üstünden bütünleşik koşu tekrar çalıştırıldı. Türkçe/Aqua ve
İngilizce/DarkAqua koşuların her birinde 244 kontrolün tamamı geçti.
commandBarTestPaletteKey, gerçek alan düzenleyicisi odağı, json girişi,
ok/Enter/Escape ve yönlendirme kontrolleri bu kez başarılıdır. Bu, önceki
kilitli koşuların başarı sayılması değildir; başarısız eski raporlar
completion-audit-*-before-resume-* adlarıyla korundu. Son koşu kanıtı
.build/completion-resume-native.log ve completion-audit-{tr,en}.json'dır.

Son kaynak/test hash'leri tamamlanma denetimiyle birebir aynı bulundu;
Sources/Resources içinde başarılı debug paketlemeden sonra değişiklik yok.
Dolayısıyla gereksiz test tekrarı yapılmadı: güncel kod için 739 test,
dört açık isteğe bağlı atlama ve sıfır hata; release derlemesi, sıkı/derin
imza, diff kontrolü ve 3.671 anahtarda sıfır eksik/biçim/kullanılmayan çeviri
kanıtları korunuyor. Sürüm/build HEAD ile aynı: 0.1.4 / 7. Kurulu uygulama
ve sürüm etiketleri değiştirilmedi; GitHub Release oluşturulmadı.

Onaylanan geliştirme kapsamı ve proje kontrolleri tamamlandı. Güncel
.build/goal-completion-audit.json her başlık için iki dildeki son native
sonucunu ve kaynak/test özetlerini içerir. Önceki engel bu koşuyla giderildi.
Bu tamamlanma, belgelenmiş donanım/izin sınırlarını değiştirmez: gerçek
uygulamalar arasında fiziksel ses yönlendirmesi, ekran yakalama/drag-drop,
global HID ve farklı cihaz/Space davranışları için belirtilen kabul
sınırları sürer. MacBook pil/şarj desteği veya tam referans araç eşdeğerliği
kanıtlanmış sayılmaz.
