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
