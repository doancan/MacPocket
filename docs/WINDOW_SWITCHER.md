# Alt+Tab pencere geçişi

Hedef: AltTab’ın (alt-tab.app/features, alt-tab.app/pricing) vaat ettiği Windows
tarzı “canlı küçük resimlerle pencere geçişi”. MacPocket AltTab kodunu kopyalamaz;
AppKit, Carbon hotkey, Erişilebilirlik (AX), CGWindowList ve ScreenCaptureKit ile
bağımsız uygulanır. Tools → Pencere Geçişi ayar ve ayrıntı ekranıdır.

Günlük geliştirme komutları ve test sınırları için
[kısa doğrulama kılavuzu](development/WINDOW_SWITCHER_VALIDATION.md).

## Özellik eşlemesi (7 Kasım 2026, yirmi dokuzuncu geliştirme aşaması)

Ücretsiz/Pro ayrımı, gelişmiş ayar envanteri, sürüm kimlikleri ve geliştirme
sırası [güncel AltTab araştırmasında](research/2026-11-06-alttab-free-pro.md).
Aşağıdaki “var” ifadeleri kaynak durumudur. Saf model, sahipli native fixture,
gerçek AX/SCK ve fiziksel kısayol kabulü ayrı kaydedilir; birinin sonucu
diğerinin kapsamını kanıtlamaz.

| AltTab | MacPocket | Durum |
|---|---|---|
| Canlı küçük resimler | Yeni tercihlerde açık; seçili ve görünür kartlar öncelikli, küçük resim kuyruğunda dört eşzamanlı yakalama ve 48'lik partiler; küçültülmüşler son görüntüyü korur | Model testleri ve ayrı süreçte aynı başlıklı iki pencerenin gerçek SCK görüntüsü/piksel yenilemesi geçti; tüm üçüncü taraf uygulamaların kabulü değildir |
| Her pencere, her Space ve ekran | AX + CGWindowList; opsiyonel SkyLight okumasıyla Space kimlikleri, görünürlük ve Mission Control sırası; ekran filtresi çerçeveye dayanır | Kendi ayrı uygulamamızda normal/küçültülmüş/tam ekran üyeliği, diğer Space'e odak ve iki bağlı ekranda panel/filtre geçti; üçüncü taraf uygulama kabulü ayrı |
| Masaüstü sıralaması | Bilinen Space sırası, aynı Space içinde MRU; bilinmeyenler sonda MRU | Saf model ve native fixture gezinme kontrolü geçti |
| Küçültülmüş, gizli ve penceresiz öğeler | Kısayol başına göster / gizle / sona taşı; tam ekran pencerelerini gizleme | Birleşik filtre/sıralama testleri geçti; tam ekran durumu okunamayan kayıtlarda tahmin edilmez |
| Uygulama kapsamı | Tüm / öndeki / öndeki dışındakiler / imleç altındaki uygulama / imleç altındaki pencereler | İmleç konumu açılışta sabitlenir; fiziksel çoklu ekran kabulü ayrı |
| Uygulama gruplama | Her çalışan uygulamadan filtrelenmiş sıralamadaki ilk pencere | Arama, sona taşıma ve native panel fixture kontrolü geçti |
| Oluşturulma sırası | Gözlem sırasında alınan gerçek oluşturma olayları, eskiden yeniye; bilinmeyenler sonda MRU | Süreç başlangıcına bağlanır; önceden açık pencerelere tarih uydurulmaz |
| Pencere yaşam döngüsü | Ortak oluşturma/yok edilme dinleyicisi; eski tarama/eylem ve bilinen görüntü kimliklerini geçersizleştirme | Fiziksel yok edilme, kullanıcının kapatmasıyla eşdeğer sayılmaz; aktif abonelikler son sahipte kaldırılır |
| Yerel pencere sekmeleri | Doğrulanabilen AXTabButton grupları varsayılan tek kart; kısayol başına ayrı gösterme; önce doğrulanan grubu AX listesinde görünmese de güncel köküyle yeniden keşfetme | Ayrı süreçte gerçek AXUIElement keşif/seçim/yeniden adlandırma ve AXWindows'tan düşen grubun başka Space'te yeniden okunması geçti; Ayrı süreçte arka plan sekmesinin özgün Space'ine geçerek odağa gelmesi de geçti; üçüncü taraf uygulamalar ve tarayıcı sayfaları ayrı kapsam |
| Açık panelde Space/ekran değişimi | Eski tarama ve önbellek geçersizleştirilir, seçim korunarak yeni kapsama geçilir; kaybolan ekran kalan ekrana bağlanır | Bildirim/ekran kaybı fixture kontrolü ve kendi tam ekran Space giriş/çıkışının açık panele yansıması geçti; fiziksel ekran sökme kabulü ayrı |
| Pencere bazlı son kullanım | Öndeki uygulamanın AX odak değişimleri, uygulama aktivasyonu ve kendi odak işlemleri | Model/yaşam döngüsü testleri ve ayrı süreçte gerçek AX odak bildirimleriyle iki pencerenin MRU sırası geçti |
| Pencereye bağlı iletişim sayfası | Odaktaki AXSheet, aynı süreçteki sınırlı AXParent zinciriyle gerçek sahibi AXWindow'a bağlanır; MRU ve aktif kart sahibi izler, imleç hedefi gerçekten odaklı yüzeydir | Gerçek VS Code'da iki farklı pencerenin iki ayrı sayfası ve iTerm2 arasında CLI geçişi geçti; kardeş pencere odağı kabul edilmez |
| Seçmeden önce tam boy önizleme | Önceki hedef hemen gizlenir, geç kalan görüntü hedef/oturumla kontrol edilir; varsayılan kapalı | Eski görüntü yarış testi ve gerçek SCK hedefiyle ayrı görüntü panelinin açılması geçti; kapsam kendi ayrı test uygulamamızdır |
| Açık/koyu görünüm | Genel ve kısayol başına sistem/açık/koyu tema; azaltılmış saydamlık için düz zemin | Native fixture'da tema ve stil geçişi kontrol edildi |
| Üzerine gelince kapat/küçült/tam ekran | Desteklenen eylemler üç stilde de düğme ve erişilebilirlik eylemi olarak sunulur; yinelenen işlemler kilitlenir | Kaynak ve derleme geçti; gerçek AX eylemi kabulü bekliyor |
| Stiller | Küçük resim / uygulama simgesi / başlık listesi | Native fixture'da üç stil açıldı |
| Yazarak arama | Yazmak veya bırakınca arama moduna geçmek; metin silinse de arama modu korunur | Fixture'da boş arama, ⌫, Escape ve bırakınca yanlış seçim yapmama geçti |
| Otomatik boyut | Pencere sayısına göre küçülen ızgara, boyut kaydırıcısı | Kaynakta var; çok sayıda pencerede kaydırma gerekebilir |
| 9 kısayol, her biri kendi ayarlarıyla | Filtre, stil, tema, boyut, önizleme, sıralama, başlık, rozet, ekran, gecikme ve animasyon; ayarlanmayan tercihler geneli izler | Kayıpsız JSON geçişi, model ve native preset kontrolleri geçti |
| Başlık ve rozet tercihleri | Başlık / uygulama / ikisi / stile göre; baştan/ortadan/sondan kısaltma; durum, Space, hover düğmeleri ve küçük resimleri ayrı aç/kapat | Üç stil × dört başlık modu native fixture; tam ad ve durum erişilebilirlikte korunur; Dock rozeti ayrı uygulama etiketidir; on beşinci aşamada eklenmiştir |
| Panel ekranı ve gecikme | Fare / öndeki pencere / ana menü ekranı; 0–900 ms gecikme; hızlı seçme bırakıldığında beklemez | Sanal ekran model testleri ve native gecikme/bırakma yolları; iki gerçek bağlı ekranda üç panel politikası ve eşleşen filtre geçti; ekran sökme kabulü ayrı |
| Bırakma davranışı | Seçili pencereye geç / paneli açık tut / aramaya geç | Üç yol örnek katalogla doğrulandı; fiziksel tuş teslimi ayrı |
| Basılı tutulacak değiştiriciler ve devralma | Açma birleşiminden bir alt küme; manuel/trackpad panelini klavye devralır, eski hareket yeni oturumu kapatmaz | TR/EN yerel panel denetiminde hızlı bırakma, soğuk tarama ve üç bırakma modu geçti; fiziksel HID kabulü ayrı |
| Güvenli Klavye Girişi tanısı | Açık Pencere Geçişi sayfasında salt okunur durum/sahip; TR/EN bilgi | Carbon kaydını engelleyen gereksiz koşul kaldırıldı. Gerçek test sırasında Chrome PID 751 güvenli girişi açık tuttu; güvenli giriş değiştirilmedi |
| Saf ⌘Tab | Hazır kısayol menüsünden seçilir; Carbon ileri/geri çifti, yalnız etkin profilde macOS devralması ve kalp atışlı geri yükleme yardımcısı | Gerçek Carbon kayıtları, WindowServer durum geçişleri, yardımcı ölümü/yeniden deneme ve AltTab'ı geri açma 21 kontrolde geçti. Fiziksel ⌘Tab/⌘ShiftTab teslimi ayrıca açık |
| Panel içi eylem tuşları | Seç, geri, vazgeç, ara, kapat, küçült/geri al, tam ekran, gizle, çık; tuş kaydı ve çakışma kontrolü | Özel eylem eski tuşu değiştirir; gerçek AX işlemi kabulü bekliyor |
| İmleç seçimi izlesin | Kapalı / her geçişte / yalnız imleç başka ekrandaysa; başarılı odak sonrası gerçek görünür pencere ortası | Varsayılan kapalı; yeni giriş/iptal/geç sonuç taşımaz; iki gerçek ekranda, küçültmeden dönüşte ve çapraz Space sekmesinde kabul aşağıda |
| Oklar ve Vim | İki bağımsız global tercih; h/l önceki/sonraki, j/k alt/üst sıra, / arama; aramada harfler metindir | Saf çözümleyici, üç stilde yerel AppKit giriş ve native tercih kontrolleri; fiziksel klavye/gerçek farklı klavye düzeni kabulü ayrı |
| Animasyonlar | Açılış, kapanış, kart seçimi ve tam boy önizleme girişi ayrı tercihler; Reduce Motion hepsini kapatır | Yeniden açılma/iptal ve yerel Tab kontrolü geçti; fiziksel seri geçiş kabulü ayrı |
| İstisnalar | Tam yol / tam bundle kimliği / bundle öneki; her zaman, penceresizken veya başlık metniyle gizleme; öndeyken daima / yalnız odaktaki pencere tam ekranda kısayol kapatma | Tek editör, eski kayıtların tam eşleşmesi ve bozuk kaydı koruma; model, native kontrol ve kendi ayrı uygulamamızda AX tam ekran kabulü aşağıda |
| Trackpad hareketleri | 3/4 parmak yatay pencere/dikey satır gezinmesi, isteğe bağlı haptik; cihaz değişimi ve uyku/uyanma abonelikleri | Bağlı Bluetooth trackpad ile gerçek adaptör başlatma/durdurma geçti; temas fixture/native panel denetimi var. Fiziksel kaydırma, yeniden bağlama, gerçek uyku/uyanma ve haptik kabulü ayrı |
| Komut satırı | Paket executable'ında `--switcher list [--detailed]`, `focus <id>` / `focus --mru <n>`, `show [1…9]`, `hide`, `status`; probe istemcisi de aynı IPC'yi kullanır | Ayrı CLI süreciyle gerçek kendi AppKit pencerelerinde liste/odak/panel; ayrıca mevcut iTerm2/VS Code pencerelerinde odak ve MRU geçti; tüm üçüncü taraflar için garanti değildir |
| Ayar aktarımı | Genel Ayarlar → Gelişmiş üzerinden JSON; kısayol, görünüm, eylem ve istisnaları da taşır; seçiciler yalnız Settings penceresine bağlıdır | Gerçek SwiftUI Settings sahnesi, NSSavePanel/NSOpenPanel, dokuz profil, iptal/bozuk dosya, bağlı sayfa açıkken pencereyi kapatma ve yeniden açma TR/EN geçti; hazırlanan dosya konumu denetime aittir |
| Erişilebilir | VoiceOver etiketleri, seçim duyurusu, desteklenen pencere eylemleri ve birleşik durum açıklaması | Kısmi; gerçek VoiceOver/Sticky Keys kabulü bekliyor |
| Liste hesaplama maliyeti | Filtrelenmiş/sıralanmış sonuç, girdiler değişene kadar modelde yeniden kullanılır | 300 öğeli sentetik Debug ölçümünde 200 liste/seçim okuması medyanı 129,19 → 5,89 ms; yaklaşık %95,4 azalma. Bu, uygulamanın tamamı için hızlanma iddiası değildir |
| Pil dostu | Canlı yenileme yalnız panel açıkken | Gerçek pencere yakalama ve masaüstü gecikme ölçümü yapıldı; toplam CPU/enerji/pil ölçümü yok. Pilsiz Mac Studio pil kabulü sağlamaz |
| 21 dil | Türkçe ve İngilizce | Diğer diller kapsam dışı; yerelleştirme taraması 0 eksikle geçti |

## Teknik notlar

- Pencere kimliği AX ↔ WindowServer eşlemesiyle (`_AXUIElementGetWindow`, çalışma
  anında aranır; yoksa çerçeve eşleşmesi) bulunur. Aynı başlıklı pencereler artık
  karışmaz.
- WindowServer-only diğer Space pencereleri için okunabilen bir başlık gerekir
  (Ekran Kaydı). Daha önce doğrulanan sekme grubunun güncel AX kökü okunabiliyorsa
  pencere/sekme adları AX üzerinden yeniden alınabilir. Space üyeliği tek başına
  bu başlık/AX izinlerini sağlamaz;
  başlıksız ekran dışı yardımcı pencereler tahmin edilmez. Geometri yedeği yalnız
  tek aday varsa kimlik atar; aynı çerçevedeki sekmeler/pencereler ilk adaya bağlanmaz.
- Diğer Space’e geçiş: önce sekmenin güncel grup kökü veya tam kimlikle AX
  penceresi çözülür. Gerekirse isteğe bağlı özel Cocoa remote-token ABI’sinde
  tek hedef için en fazla 250 ms / 8192 aday aranır. PID, CGWindowID ve AXWindow
  rolü birlikte doğrulanır; başlık veya alt öğenin kapsayan pencere kimliği
  yeterli sayılmaz. İsteğe bağlı WindowServer etkinleştirmesi ve AXRaise
  sonrasında özgün Space üyeliği/görünürlüğü beklenir. Çözülemeyen hedefte
  başarı bildirilmez. Özel API’nin ve uygulamaların davranışı evrensel garanti değildir.
- Katalog uygulama değişimlerinde arka planda tazelenir; panel önbellekle anında
  açılır, ardından taze liste gelir.
- İzinler imza kimliğine bağlıdır. `scripts/build-app.sh` geçerli bir Developer ID /
  Apple Development sertifikası varsa onu kullanır; ad-hoc imzada her derlemede
  izinler sıfırlanır.
- Retina boyutu `SCContentFilter.contentRect` ve `pointPixelScale` ile piksel
  bütçesine sığdırılır; kaynak artık 1× ile sınırlanmaz. Bekleyen içerik keşfi
  eşzamanlı yakalamalar arasında paylaşılır.
- Canlı yenileme yaklaşık 1100 ms aralıkla istek üretir; bir parti sürerken
  istekler birleşir. Seçim değişirse ilk boşalan yakalama yuvası yeni hedefe
  verilir. Kapanan oturum yeni yakalama başlatamaz veya eski sonucu yayımlayamaz.
- Simge ve başlık stilleri küçük resim yakalama kuyruğunu çalıştırmaz; bu
  stillerde tam boy önizleme açılmışsa yalnız onun görüntüsü ayrıca alınır.
- Küçük resim önbelleği 64 MiB bütçe kullanır; görünür kartlar ve seçili hedef
  korunur, eski sayfalar önce çıkarılır. Görünür kartlar tek başına bu bütçeyi
  aşarsa korunurlar; toplam uygulama belleği için kesin üst sınır değildir.
  Kullanıcının önceden kaydettiği canlı önizleme kapalı tercihi korunur.

## İlk aşamada doğrulananlar

- `swift test`: toplam 1.131 vaka; 4 isteğe bağlı sistem testi atlandı, 0 hata.
  Yeni 4 çekirdek ve 11 uygulama testi; 48. sıra sonrası seçim, viewport,
  eşzamanlılık, gecikmiş sonuçlar, izin reddi/geri alma, önbellek tahliyesi ve
  yakalama hatasından toparlanmayı ve eski panelin geciken görünürlük olaylarının
  yeni oturuma karışmamasını kapsar.
- `scripts/build-app.sh`: Debug uygulaması derlendi, imzalandı ve
  `codesign --verify --strict` geçti. `swift build -c release --product MacPocket`
  de başarılı; sürüm/build numarası değiştirilmedi.
- `scripts/audit-window-switcher.sh --skip-build`: ayrı `.SwitcherAudit`
  bundle'larında Türkçe/İngilizce; üç stil × açık/koyu × cam/düz zemin =
  24 native fixture görünümü. Tab, Shift+Tab, arama, Escape, panel odağı ve
  görünüm kaydı ve gereksiz küçük resim yakalamama için 240 kontrol geçti.
- Denetim yalnız uygulamanın kendi fixture görüntülerini ve yerel AppKit
  olaylarını kullanır; global kısayol kaydetmez, izin istemez veya başka
  uygulamaların pencerelerini değiştirmez. Düz zemin görüntüleri görsel olarak
  incelendi. `cacheDisplay` camın WindowServer arka plan bileşimini yakalamaz;
  cam görüntüleri gerçek ekran bileşiminin kanıtı değildir. Araç içi AX ağacı,
  gerçek VoiceOver kullanım testi yerine geçmez.
- `scripts/check-localizations.sh`: 4081 anahtar, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı; kısayol kaydedicisinde 9 anahtar ve 0 eksik Türkçe çeviri.
- Yerel çıktılar: `.build/switcher-stage1-full-tests.log`,
  `.build/switcher-stage1-bundle.log`, `.build/switcher-stage1-localizations.log`,
  `.build/switcher-stage1-runtime.log`, `.build/switcher-audit/{tr,en}/report.json`.

## İkinci aşamada uygulananlar ve doğrulama

- `SwitcherPresentationOverrides` yalnız değiştirilen alanları saklar. `nil`
  alanlar sonraki genel ayar değişikliklerini izler; aktif oturumun çözülmüş
  ayarları ise oturum boyunca sabittir. Her kısayol ayrı önizlenebilir.
- `SwitcherShortcut` ve `WindowListFilter` decoder'ları eski JSON'da eksik
  alanlara varsayılan verir. Kimlik, tuşlar, filtreler ve eski `releaseToChoose`
  korunur. Yeni encoder eski alanı da yazar; eski sürüm arama modunu açık tutma
  olarak görür. Eski tek kısayol tercihi ilk açılışta kalıcı kimliğe taşınır.
- Açık panelde farklı kısayol yeni oturum/kapsam/görünüm başlatır; aynı kısayol
  gezinir. Carbon/yerel olay tekilleştirmesi kısayol kimliğini de karşılaştırır.
  İleri/geri Carbon kayıtları birlikte başarılı değilse ikisi de kaldırılır;
  görünüm değişiklikleri fiziksel kısayolları gereksiz yeniden kaydetmez.
- Arama durumu metinden ayrıdır: son harfi silmek veya arama boşken tuşları
  bırakmak pencereye geçmez. Bırakınca arama modu boş sorguyla da açılır.
- Panel içindeki eylemler kaydedilebilir, kaldırılabilir ve sıfırlanabilir.
  Çakışan veya gezinme/vazgeçme tuşlarını bozan atamalar reddedilir. Tab,
  Shift+Tab, oklar ve Escape temel gezinme/çıkış yolları olarak korunur. Tek
  başına harfler arama sırasında komut yerine metin olur. Seçim tuşu, arama
  sırasında da ulaşılabilir olması için Enter/işlev tuşu veya değiştiricili bir
  tuş olmalıdır; metin olarak işlenecek yalın boşluk/harf/geri silme reddedilir.
- Eylemler açma kısayolunun basılı değiştiricileri çıkarıldıktan sonra eşlenir.
  Önceki davranış korunur: örneğin ⌥ ile açılan oturumda ⌥+⌘W, ⌘W eylemine
  gider; ⌘ ile açılan oturumda basılı ⌘ tekrar bir eylem değiştiricisi sayılmaz.
  Böyle bir oturumda kullanılacak eylemler ⌘ gerektirmeyen tuşlarla atanabilir.
- Kaydedici kilidi atomik olarak tek kayıtçıya verilir; SwiftUI henüz diğer
  düğmeleri devre dışı çizmeden gelen ikinci kayıt isteği de reddedilir. Modül
  durdurulunca kilit ve yerel dinleyiciler bırakılır. Global geçiş kapalıyken
  ayarlar yine düzenlenebilir. Düzenleme hataları kayıt durumundan ayrıdır.
- Eşzamanlı pencere yenilemeleri tek taramayı bekler. Eski oturum çağrısı iptal
  edildiğinde yeni oturum taramaya katılabilir; kapatılan modülün geç sonucu
  yayımlanmaz ve tarama sırasında yapılan seçim korunur.

Çalıştırılan kontroller:

- `swift test`: 1.150 vaka, 4 isteğe bağlı sistem testi atlama, 0 hata. Bu aşama
  8 sunum/kayıt geçişi testi, 6 eylem eşleme testi ve 5 uygulama durum/yenileme/
  kayıtçı kabul testi ekledi. Derleyici uyarısı yok.
- `scripts/audit-window-switcher.sh --skip-build`: TR/EN toplam 308 kontrol
  geçti. Önceki 24 panel varyantına preset kapsam/stil/tema değişimi, üç bırakma
  yolu, boş aramada geri silme, eski/yeni eylem tuşu yönlendirmesi, düzenleme
  hatasından dönüş ve kayıtçı kilidi eklendi. Yönlendirme **örnek katalog ve
  görüntü sağlayıcısıyla** çalışır; gerçek AX/ScreenCaptureKit kabulü değildir.
- Kısayol seçenekleri 520/760 pt, tam ayar formu 760/1000 pt genişlikte TR/EN
  açıldı. Altı native seçenek menüsü, ekran görüntüleri ve ölçülebilen AX
  öğelerinde yatay taşma kontrol edildi. İngilizce yüzde biçimi `80%`, Türkçe
  `%80` olarak doğrulandı. Camın WindowServer bileşimi bu görüntü alma yöntemiyle
  doğrulanamaz; okunabilir yapısal form kaydı açık görünümde ayrıca alındı.
- Denetim uygulaması, oturumlar arasında yerel AppKit girişi için kendi normal
  penceresini tutar. Bu kurulum üretimdeki nonactivating HUD'nin veya fiziksel
  klavye tesliminin kanıtı değildir. Kurulu uygulamanın tercihleri değiştirilmez.
- `scripts/check-localizations.sh`: 4102 anahtar, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı; kısayol kaydedicisinde 0 eksik Türkçe çeviri.
- Yerel çıktılar `.build/switcher-stage2-{full-tests,bundle,runtime,localizations}.log`,
  `.build/switcher-stage2-release-build.log` ve `.build/switcher-audit/{tr,en}/`
  altındadır. Debug imza doğrulaması ve `swift build -c release --product MacPocket`
  geçti. Sürüm/build numarası değiştirilmedi; sürüm etiketi veya Release oluşturulmadı.

## Üçüncü aşamada uygulananlar ve doğrulama

- `WindowListFilter` artık beş uygulama kapsamı, üç masaüstü görünürlük kapsamı,
  üç kategori için göster/gizle/sona taşı, tam ekran görünürlüğü ve uygulama
  gruplaması saklar. Eski altı boolean alan yeni decoder'da aynı davranışa
  taşınır; encoder eski alanları da yazar. Eski sürüme dönüşte yeni “sona taşı”
  göster olarak, ileri kapsamlar tüm uygulamalar/masaüstleri olarak okunabilir;
  eski sürüm yeni semantiği aynen korumaz. Bilinmeyen yeni enum metni varsa eski
  alan/default kullanılır. Tercih dosyası biçimi ve kısayol kimlikleri korunur.
- Filtre, arama ve istisnalar önce uygulanır; istenen sıralama ardından kategori
  önceliğiyle kararlı iki kümeye bölünür. Birden çok kategoriye uyan öğe bir kez
  görünür. Gruplama en son her çalışan uygulama örneğinin ilk uygun penceresini
  tutar; ayrı süreçler birleştirilmez. Arama başka bir kardeş pencereyi ortaya
  çıkarabilir. Gruplama uygulama içi native sekme desteği anlamına gelmez.
- İmleç altındaki uygulama, açılışta alınan CoreGraphics konumu ve WindowServer
  ön/arka sırasıyla bulunur. Gizli/küçültülmüş, başka Space çıkarımlı ve
  görünürlüğü bilinmeyen kayıtlar imleç isabeti sayılmaz. Uygulama kapsamı arama
  veya istisna yüzünden arkadaki uygulamaya kaymaz. Soğuk açılışta ilk taze
  katalogla bir kez çözülür; sonraki fare hareketi/katalog sırası hedefi değiştirmez.
  “İmleç altındaki pencereler” aynı noktayı içeren görünür, örtüşen pencereleri
  kapsar. Kapsam açılışında öndeki uygulama kimliği yenilemede rastgele değiştirilmez.
- Görünürlük kesin Space kimliği değildir. Görünür olmayan masaüstü filtresi
  ekrandaki WindowServer kayıtlarını çıkarır; AX/WindowServer ile konumu
  bilinmeyenler her iki kapsamda tutulur. Başlık ve ekran kaydı izin sınırlamaları
  devam eder. Ekranı bilinmeyen kayıtlar da tutulur. Hiçbir ekranla kesişmeyen bir
  AX çerçevesine önce rastgele ekran atanabiliyordu; bu artık `nil` kalır.
- `WindowFocusObservation` ortak bir kaynak sahipliği kullanır: HUD ve Tools
  iki istemci olsa da öndeki uygulama için bir AX gözlemci ve odak gözlemine ait tek NSWorkspace
  abonelik çifti vardır. Son istemci durunca kaynaklar ve bellek içi gözlem
  geçmişi bırakılır. Periyodik AX odak taraması eklenmez. Bildirimler ana
  run loop'ta teslim edilir; pencere okuması seri bir actor'de, 50 ms AX mesaj
  zaman aşımıyla yapılır. Hızlı istekler birleşir; eski süreç/oturum sonucu
  yayımlanmaz. Kaynak API sözleşmesi: Apple
  [AXObserverCreate](https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate),
  [AXObserverAddNotification](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification).
- Odak zamanları PID + uygulama başlangıç zamanı + pencere kimliğiyle tutulur;
  AX hash, WindowServer kimliği yokken yardımcı eşleşmedir. Geçmiş 4096 pencere
  kaydıyla sınırlı, yalnız bellektedir. Süreç sonlanınca ilgili kayıtlar silinir.
  Bir uygulamanın aktivasyonu artık bütün kardeş pencerelere aynı yeni zaman
  vermez; aktivasyon geçmişi yalnız penceresiz uygulama satırına yedektir.
  İzin yokluğu, bildirim desteklemeyen uygulamalar, gözlem başlamadan önceki
  geçmiş ve birleştirilen hızlı geçişler için eksiksiz MRU iddiası yoktur;
  katalogdaki öndeki pencere gözlemi ve WindowServer sırası yedek olmaya devam eder.
- Kimlik kontrolündeki ayrı hata düzeltildi: eksik iki başlangıç zamanı (`nil`)
  artık aynı süreç kanıtı sayılmaz. Canlı salt okuma kontrolünde 23 düzenli
  uygulamanın yalnız 20'sinde AppKit `launchDate` vardı (Finder, Docker Desktop
  ve Chrome'da eksikti); çekirdeğin `proc_pidinfo(PROC_PIDTBSDINFO)` başlangıç
  zamanı 23'ünde de okunabildi. Katalog, gözlem ve işlem/yakalama doğrulaması
  öncelikle aynı çekirdek saatini kullanır, okunamıyorsa AppKit'e döner.
  İki kaynağın da kimlik veremediği hedef doğrulanmaz. Bu kontrol gerçek
  pencere odaklama/eylem kabulü değildir. Süreç kimliği çıktısı
  `.build/switcher-stage3-process-identity.log` içindedir.
- Filtreler tek bir küçük menü yerine açılabilir native ayar grubundadır.
  Seçeneklerin sonuçları ve konumu bilinmeyen pencerelerin korunması TR/EN
  açıklanır; seçili değerler AppKit erişilebilirlik özniteliklerinden okunur.

Çalıştırılan kontroller:

- `swift test`: 1.169 vaka, 4 isteğe bağlı sistem testi atlama, 0 hata.
  Bu aşama 9 filtre/ekran geometri testi, 7 odak geçmişi/kimlik testi ve
  3 uygulama kapsam/gezinme/kaynak sahipliği testi ekledi.
- `scripts/audit-window-switcher.sh --skip-build`: TR/EN toplam 342 kontrol.
  Filtre kontrolleri 520/760 pt genişlikte, yedi native menüde seçili değerler,
  ölçülebilen öğelerde yatay taşma; aktif olmayan uygulama kapsamı, gruplanmış
  panelde arama/gezinme ve birden çok odak gözlem istemcisinin temiz kapanışı
  kontrol edildi. Filtre görüntüleri iki dilde incelendi.
- Kaynak sahipliği kontrolü denetim uygulaması öndeyken, kendi PID'si gözlemden
  çıkarılarak yapıldı; dış uygulamaya AX gözlemcisi bağlanmadı. Bu sonuç gerçek
  odak bildirimi, fiziksel kısayol veya tam Space kabulü değildir. Raporda
  `realFocusNotificationsVerified=false` ayrıca belirtilir. Önceki cam/AX ölçüm
  sınırlamaları geçerlidir.
- `scripts/check-localizations.sh`: 4112 anahtar, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı; kısayol kaydedicisinde 0 eksik Türkçe çeviri.
- Yerel çıktılar `.build/switcher-stage3-{full-tests,bundle,runtime,localizations}.log`,
  `.build/switcher-stage3-release-build.log` ve `.build/switcher-audit/{tr,en}/`.
  Debug paket/imza ve Release derlemesi başarılı; sürüm/build numarası
  değiştirilmedi.

## Dördüncü aşama: Space üyeliği ve sıralama

- `WindowSpaceProvider`, SkyLight'ı çalışma anında yükler. Yalnız
  `CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces` ve
  `CGSCopySpacesForWindows` kullanır; uygulama/pencere/Space taşıyan veya etkinleştiren
  bir özel API çağrısı eklenmez. Özel framework sabit linklenmez. Bu destek
  macOS'un belgelenmiş bir sözleşmesi değildir; sembol/veri alınamazsa eski
  görünürlük çıkarımı ve MRU sırası çalışmaya devam eder.
- `SpaceTopology` her ekranın geçerli Space'ini ve Mission Control listesini
  çözer. Birden çok ekranda aynı anda görünür Space'ler ve ortak `Main` topolojisi
  desteklenir. Tekrarlanan ortak kimlikler bir kez numaralanır; görünürlük
  birleşimle belirlenir. Masaüstü numarası mevcut topoloji sırasıdır, kalıcı
  kullanıcı adı/kimliği değildir. Kaynak API imza referansları:
  [CGSSpace.h](https://github.com/NUIKit/CGSInternal/blob/master/CGSSpace.h) ve
  [AltTab v11.10.1 SkyLight tanımları](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/macos/api-wrappers/SkyLight.framework.swift).
  Bunlar araştırma girdileridir; upstream uygulama kodu ürüne kopyalanmadı.
- Pencere üyeliği her benzersiz WindowServer kimliği için alınır. Seri actor,
  sorgular arasında kontrol edilen 250 ms bütçe ve iptal kontrolü kullanır;
  bir WindowServer çağrısı için sert zaman aşımı garantisi değildir. Başarısız,
  boş ve bilinmeyen kimlik içeren sonuçlar ayrılır. Topoloji okuma başı/sonu
  değişmişse karma sonuç yayımlanmaz, sonraki olağan katalog yenilemesi tekrar dener.
- Katalog çıktısına `WindowSpaceMembership` ve metadata kullanılabilirlik/kısmi
  durumları eklenir. Bilinen üyelik küçültülmüş/gizli pencerelerde ekranda görünme
  çıkarımından önce gelir. Bilgi yoksa eski davranış korunur. Tam ekran Space'inde
  bulunmak, yardımcı pencerenin kendisinin de tam ekran olduğu anlamına gelmez;
  pencere tam ekran filtresi hâlâ okunan AX durumuna dayanır.
- Genel ve kısayola özgü `Masaüstü sırası` eklendi. Aynı Space'teki pencereler
  MRU ile sıralanır. Üyeliği tam çözülemeyenler sonda MRU ile kalır. Kategori
  bazlı sona taşıma ve uygulama gruplaması daha sonra uygulanır. Kartların
  erişilebilir durum metni ve Tools durum hücresinin yardımı masaüstü adını içerir.
  Görsel Space rozeti seçenekleri sonraki görünüm aşamasındadır.
- İstemciye yeni bir TCC istemi, global tuş kaydı veya izin atlatma eklenmez.
  Çalışma anındaki Space verisi mevcut katalog taramalarında alınır. Panel açıkken
  Space/ekran değişimi bildirimleriyle yenileme ve çoklu ekran yeniden bağlama
  senaryoları ayrıca tamamlanacak/kabul edilecek.

Doğrulama:

- `swift test`: toplam 1.183 vaka, 4 isteğe bağlı sistem testi atlama, 0 hata.
  Yeni 13 çekirdek test; çoklu/ortak ekran topolojisi, 64 bit kimlikler, gizli/
  küçültülmüş/sticky pencereler, bilinmeyen üyelik, Space sırası, eksik API,
  değişen topoloji, bütçe, bozuk sonuçlar ve belirsiz geometri eşleşmesini kapsar. Bir uygulama testi yeni
  katalog metadata'sının filtre/sıralama ve genel ayar ayrımını doğrular.
- Native denetim TR/EN toplam 370 kontrol: Space sırasının gerçek panelde Tab
  gezinmesini belirlemesi, yerelleştirilmiş erişilebilir durum ve yeni filtre
  sonucu fixture verisiyle doğrulandı. Bunlar fiziksel klavye/VoiceOver kabulü değildir.
- Ek olarak üretim `WindowCatalog` ve `WindowSpaceProvider` ile **kendi AppKit
  penceresinde** gerçek WindowServer okuması yapıldı: normal üyelik, küçültürken
  aynı üyeliğin korunması, tam ekranda yeni Space kimliği/type 4, çıkınca özgün
  kimlik ve topolojiye dönülmesi, geçici Space'in kaldırılması. Native tam ekran
  giriş/çıkış tamamlanma bildirimleri beklenir; giriş bitmeden çıkış isteme yarışı
  denetimde düzeltildi. Bu, başka uygulamayı farklı Space'ten odaklama kabulü değildir.
- Fixture klavye denetimi fareyle seçim/dış tık kapatmayı ve işletim sisteminin
  anlık foreground uygulamasını kapsam dışı bırakır. Test kısayol oturumu için
  kendi `NSRunningApplication.current` bağlamı enjekte edilir; üretim varsayılanı
  NSWorkspace kalır. Yerel AppKit tuş teslimi hâlâ gerçek nonactivating panelden
  geçer; denetim gerekirse kendi panelinin key odağını yeniden kurar ve native
  sunum işlemlerinin bir run loop turunu tamamlamasını bekler. Bu, odak koruma
  veya fiziksel tuş teslimi kanıtı değildir. `syntheticWindowFocusControlled=true`
  ve odak yenileme sayısı rapordadır. Denetimdeki düz zemin tercihi de yeni kısayol
  oturumlarında korunur; camın `cacheDisplay` sınırlamaları görsel kanıt yerine kullanılmaz. `hoverInputVerified=false`, `externalClickDismissalVerified=false` ve
  `externalSpaceFocusVerified=false` raporda açıktır.
- Terminaldeki ayrı sekme prototipi, kendi uygulamasını AX üzerinden okurken
  `notImplemented` döndürdü (`AXIsProcessTrusted=false`). Bu sonuç başka uygulamada
  native sekme desteğini ne doğrular ne çürütür. Native sekme gruplaması henüz
  uygulanmış sayılmaz; tarayıcı sekmeleri veya benzer başlıklar eşdeğer kabul edilmez.
  AppKit'in kendi sekme modeli:
  [NSWindowTabGroup](https://developer.apple.com/documentation/appkit/nswindowtabgroup).
- `scripts/check-localizations.sh`: 4118 anahtar, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı; kısayol kaydedicisinde 0 eksik Türkçe çeviri.
- Debug paket/imza ve Release derlemesi kontrol edildi; sürüm 0.1.5 ve build 8
  korundu. Yerel çıktılar `.build/switcher-stage4-{full-tests,bundle,runtime,localizations}.log`,
  `.build/switcher-stage4-release-build.log`; rapor ve görüntüler
  `.build/switcher-audit/{tr,en}/`. Ön prototip girdileri/çıktıları
  `.build/research/alttab-2026-11-06/` altında, ürün kaynaklarından ayrıdır.

## Beşinci aşama: ortam yenileme ve yerel pencere sekmeleri

- Panel, Space değişimini `NSWorkspace.notificationCenter`, ekran değişimini
  `NSApplication.didChangeScreenParametersNotification` üzerinden izler.
  Ortam hemen geçersiz kılınır; 180 ms birleştirme sonrasında tek taze katalog
  taraması yapılır. Arama ve hâlâ uygun olan seçim korunur; bekleyen Tab/Shift+Tab
  adımları bir kez uygulanır. Hazırlık sırasında Option bırakılırsa eski Space'in
  önbelleğinden odaklama yapılmaz; yeni sonuç beklenir. Panel kapalıyken yeni AX
  taraması başlatılmaz, sonraki açılış eski ortamın hızlı seçimini kullanamaz.
- Kaldırılan ekran kimliği ana/kalan ekrana düşer, panel yeniden yerleştirilir;
  eski koordinatlardaki tam boy önizleme hemen gizlenir. Fiziksel monitör çıkarma,
  ekran ölçeği ve karma çoklu ekran yerleşimleri hâlâ canlı kabul gerektirir.
- Geciken prewarm görevi artık saklanır ve modül/ortam değişiminde iptal edilir.
  Eski model taraması yenisini ezemez. `WindowCatalog` da tarama kimliğini kontrol
  eder; Space okumasında bekleyen eski bir tarama, yeni pencerenin eylem handle'ını
  geri alamaz. Odak geçmişi son gözlenen tarih korunarak birleştirilir.
- `WindowTabAccessibility` AX pencere kökünün doğrudan altındaki `AXTabGroup`
  ve `AXTabButton` öğelerini sınırlı bütçeyle okur. Grubun tek seçili kontrolü,
  benzersiz kontrol kimlikleri ve aynı süreç kimliği gerekir. Başlık ve sekme
  numarası kimlik yerine kullanılmaz. AX referansları Core actor'ünden çıkmaz.
- AX grubu tek başına yerel pencere sekmesinin kanıtı sayılmaz. Aynı PID ve
  **tam WindowServer çerçevesinde**, seçili kökün dolu Space üyeliği ve kalan
  sekme sayısı kadar başarılı **boş üyelikli fiziksel yüzey** birlikte gerekir.
  Aynı konumdaki birden çok sekme grubunun toplamı doğrulanır. Eksik/çelişkili
  yüzey, okunamayan Space verisi veya bilinmeyen süreç başlangıcı varsa normal
  katalog kayıtları korunur. Bu muhafazakâr destek bütün uygulamalarda sekme
  algılama garantisi değildir; uygulama içi/browser sayfa sekmeleri taranmaz.
- Kart kimliği süreç başlangıcı + grup + gerçek AX kontrol kimliğine dayanır.
  Yalnız seçili sekme doğrulanmış WindowServer kimliği ve pencere eylemleri alır.
  Arka plan sekmesine başlıktan veya sıradan yüzey kimliği atanmaz; yeni görüntü
  yakalanmaz. Daha önce kendi kimliğiyle yakalanmış görüntü varsa `Son görüntü`
  olarak kalabilir; yoksa `Henüz sekme görüntüsü yok` gösterilir. Sekme numarası
  üç stilde ve erişilebilir durum metninde bulunur. Arka plan sekmesinde pencere
  kapat/küçült/tam ekran eylemleri desteklenmiş sayılmaz.
- Odaklama, aynı süreç/grup içindeki gerçek düğmeyi güncel kimlik ve başlıkla
  yeniden doğrular; AXPress sonrası seçili değeri ve grubun AXWindow kökünü
  bekler, sonra o kökü öne getirmeyi dener. Yer değiştirmiş kontrol kimliği
  takip edilir; kaldırılmış/yeniden oluşturulmuş veya başlığı değişmiş eski
  kontrol aynı sıradaki başka sekmeye yönlendirilmez. Başarısızlık kullanıcıya
  normal pencere hatası olarak döner.
- `separateTabs` eski kısayol JSON'unda varsayılan kapalıdır. Gruplama uygun
  seçili sekmeyi korur; arama yalnız arka plan sekmesini bulmuşsa o sonuç
  seçilebilir. Ayrı sekmeler, uygulama gruplaması ve Space/kategori filtreleri
  birlikte çalışır. Tools ayrıntı API'si sekme kayıtlarını ayrı listeler.
- Bu aşama yalnız güncel taramada okunabilen native sekme gruplarını kapsar.
  Başka Space'te AX kökü okunamayan sekme grubunu kalıcı keşfetme/izleme,
  bütün üçüncü taraf uygulamalarda kimlik devamlılığı ve sekme kapatma
  davranışları ayrıca ele alınacak. Hiçbir bilinmeyen yüzeye görüntü bağlanmaz.

Doğrulama:

- `swift test`: **1.202 vaka**, 4 isteğe bağlı sistem testi atlama, 0 hata
  (Core 803, App 22, AI 22, SSH Swift Testing 355). Yeni 16 çekirdek sekme testi,
  bir ortam seçimi testi ve iki uygulama iptal/prewarm testi eklendi. Sekme
  testleri yinelenen/boş başlıklar, yeniden sıralama/yeniden oluşturma, çelişkili
  gruplar, üst üste gruplar, süreç ayrımı, eksik üyelik, arama/filtreleme,
  önizleme kimliği ve eski ayar geçişini kapsar.
- Native TR/EN **440 kontrol** (dil başına 220) geçti. Ortam bildirimleriyle
  yenileme birleştirme, sorgu/seçim/bekleyen adımlar, geç taramayı reddetme,
  hazırlıkta bırakma, kapalı panel önbelleği, geçersiz ekran kimliğine düşme ve
  kaynak temizliği örnek katalogla sınandı. Ekran testi fiziksel ekran sökme değildir.
- Üretim katalog/Space sağlayıcısı, kendi tam ekran penceremizin gerçek
  NSWorkspace Space bildirimleriyle açık paneli güncelledi. Ayrı bir test,
  kendi yeni penceresinin handle'ını eski taramanın silemediğini doğruladı.
- Kendi iki AppKit penceresi gerçekten sekmelendi; **aynı başlıklı iki sekme**
  üzerinde NSAccessibility düğmesine basmak doğru sekmeyi seçti. AppKit seçimi
  fiziksel yüzey işleminden önce bildirdiği için denetim WindowServer üyeliğinin
  de yer değiştirmesini bekler. Grup/kontrol kart kimlikleri seçimden sonra
  korundu. Üç stilde yerelleştirilmiş sıra, grup/ayrı gösterim ve ekran görüntüsü
  kontrol edildi. Bunlar kendi süreç içindeki NSAccessibility ve üretim
  projeksiyonunun kanıtıdır; uzaktaki `AXUIElement` adaptörünün kabulü değildir.
- Üretim `com.doancan.MacPocket` kimliğinde, AppState/modüller başlamadan yapılan
  salt okunur preflight AX ve Ekran Kaydı izinlerini **false** bildirdi. İzin
  istenmedi veya değiştirilmedi. Bu nedenle dış uygulamada sekme odağı,
  gerçek ScreenCaptureKit, Space odağı ve fiziksel global kısayol kabulü bekliyor.
- `scripts/check-localizations.sh`: **4124 anahtar**, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı; kaydedicide 9 anahtar ve 0 eksik Türkçe çeviri.
- Debug paket/imza doğrulaması ve `swift build -c release --product MacPocket` geçti.
  Sürüm **0.1.5 / build 8** korundu. Yerel çıktılar
  `.build/switcher-stage5-{tests,full-tests,bundle,runtime,localizations}.log`,
  `.build/switcher-stage5-release-build.log`, `.build/switcher-stage5-permissions.json`
  ve `.build/switcher-audit/{tr,en}/report.json` / `native-tabs-*.png`.

## Altıncı aşama: gözlenen oluşturulma sırası ve yaşam döngüsü

- `WindowLifecycleService` tek paylaşılan WindowServer aboneliğini HUD ve Tools
  arasında sahiplik belirteçleriyle paylaşır. İsteğe bağlı semboller yalnız ilk
  gözlem başlatıldığında yüklenir: `CGSMainConnectionID`,
  `SLSRegisterConnectionNotifyProc`, `SLSRemoveConnectionNotifyProc`,
  `SLSRequestNotificationsForWindows`. AppKit'in olay dağıtım yönü değiştirilmez;
  hedef uygulama/pencere bu katmanda taşınmaz veya etkinleştirilmez.
- `811` oluşturma, `804` fiziksel yok edilmedir. Callback yalnız tam dört baytlık,
  sıfır olmayan kimliği kopyalar. Farklı bağlantı, bozuk uzunluk ve Space/
  görünürlük olayları reddedilir. Kilitli giriş sıralaması tarih değişikliklerinden
  bağımsız gözlem sırası sağlar; bir olay patlaması için tek bekleyen main-queue
  bildirimi vardır. AX veya AppKit callback içinde çağrılmaz.
- Başlangıç kataloğundaki normal fiziksel pencereler bütün izleme listesiyle
  aboneliği başlatır; yapay bir ürün penceresi açılmaz. Yeni oluşturulan yüzeyin
  PID/katmanı, yalnız ilgili WindowServer kimlikleri sorgulanarak çözülür.
  Canlı regular süreç ve süreç başlangıcı doğrulanınca tarihe sahip olabilir ve
  sonraki katalogdan önce yok edilmesini kaçırmamak için hemen izlemeye alınır.
  Gerçek oluşturma olayı geometri işleminden önce gelir; sıfır çerçeve bu
  katmanda reddedilmez. Kullanıcıya gösterilecek normal pencere kabulü yine
  AX/WindowServer kataloğunun ayrı geometrik/anlamsal kurallarına bağlıdır.
  Bu yol panel kapalıyken AX taraması başlatmaz. Kendi panelimiz ve yardımcı
  yüzeyler geçiş panelini yenilemez.
- `CGWindowListCreateDescriptionFromArray`, `NSNumber` nesnelerinden oluşan bir
  NSArray beklemez; CGWindowID değerlerini callbacksiz CFArray içinde alır.
  Ek canlı testte bulunan dönüşüm hatası bu gerçek ABI ile düzeltildi. Ayrı kendi
  pencere deneyinde kutulu dizi sıfır, ham kimlik dizisi doğru tek sonucu verdi.
  Girdi/çıktı `.build/research/alttab-2026-11-06/window-description-probe.*` altında.
- İstek listesi eklemeli değil **yerine geçer**. Yeni kimlikler önceki canlı
  izlemelerle birleştirilir; tek Space/AX taramasında kaybolan pencereler hemen
  bırakılmaz. Yok edilme ve ölmüş/yeniden kullanılmış süreçler listeden çıkarılır.
  8192 izleme sınırı veya API hatasında bu isteğe bağlı yetenek kapanır ve normal
  katalog/MRU davranışı kalır; sessizce izleme kaybedip tarihi kesin göstermez.
- Gözlem defteri 8192 öğeyle sınırlıdır. Başlangıç gözlemi yalnız sahip kimliğini
  tutar, oluşturulma tarihi üretmez. Gerçek oluşturma olayında tarih/sıra,
  pencere ID + PID + süreç başlangıcına bağlanır. Sahip değişirse önceki tarih
  aktarılmaz. Sahibi çözülemeden kaybolan eski bir yüzeyin kimliği yeniden
  oluşturulursa eski tarih devralınmaz. Sıralama aynı gözlem oturumunun sıra
  numarasını kullanır; duvar saati geri gitse de ters dönmez.
- Genel/kısayola özgü **Oluşturulma sırası** eskiden yeniye sıralar; gözlemden
  önce açık olan ve tarihi alınamayan pencereler sonda MRU ile kalır. Ayarlardaki
  açıklama bu sınırı söyler. Doğrulanmış aktif native sekmenin tarihi o kontrol
  kimliğinde korunabilir; bilinmeyen arka plan sekmesine kökün tarihi kopyalanmaz.
- Katalog başı ve sonundaki yaşam döngüsü sürümleri karşılaştırılır. Tarama
  sürerken oluşturulan/yok edilen veya geçmişi tahliye edilen fiziksel kimlik,
  eski sonuçtan yayımlanmaz. Eylemden önce aynı sürüm tekrar doğrulanır. Böylece
  gecikmiş Space okuması yok edilmiş pencerenin handle'ını geri getiremez.
  API desteği kaybolursa bir sonraki yeni katalog normal yola döner.
- Model bilinen yok edilmiş fiziksel kartı, ona bağlı native grup kayıtlarını ve
  görüntü kimliklerini hemen bırakır. Açık HUD yeni kapsama, bekleyen seçimleri
  koruyan yenileme yoluyla geçer; Tools tablosu görünürken yenilenir. Kapalı HUD
  yalnız önbelleğini geçersiz kılar. Belirsiz arka plan sekmesi düğmeleri yine
  eylem anında güncel AX kimliğiyle doğrulanır.
- Son sahip ayrılınca callback kayıtları ve tam pencere izleme listesi kaldırılır.
  Yeni gözlem yeni bir oturumdur; durdurulmuş aralıktaki pencerelere tarih atanmaz.
  Özel C API, unregister sonrasında önceden girmiş callback'lerin bittiğini
  belgelemiyor. Bu yüzden her kayıt neslinin **pasif, geçmişi/handler'ı temizlenmiş
  küçük context nesnesi** süreç sonuna kadar tutulur; eski callback yeni nesle
  yazamaz. Aktif callback/abonelik/task kalmasıyla aynı şey değildir. Kaldırma
  hatasında yeniden kayıt denenmez; mevcut katalog yolu kullanılmaya devam eder.
- `804` kullanıcı kapatmasının kanıtı değildir: bellekte tutulan kapalı NSWindow
  fiziksel CG listesinde kalabilir; olay ancak nesne bırakılınca gelir. Sırf
  gizlendiği/Space'ten çıktığı için silme yapılmaz. Bütün üçüncü taraf hayalet
  pencere durumlarının çözüldüğü iddia edilmez. Önceki bağımsız araştırma ve
  API kaynakları `.build/research/alttab-2026-11-06/lifecycle-findings.md` içindedir;
  upstream uygulama kodu ürüne kopyalanmadı. API bildirimleri ve olay numaraları
  için kaynaklar: [SkyLight tanımları](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/macos/api-wrappers/SkyLight.framework.swift),
  [WindowServer olay yönlendirmesi](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/windowserver/WsEventRouting.swift)
  ve [CGS bildirim başlığı](https://github.com/NUIKit/CGSInternal/blob/master/CGSEvent.h).
  Bunların sözleşme iddiaları ile yukarıdaki yerel çalışma anı ölçümleri ayrı tutulur.

Doğrulama:

- `swift test`: **1.229 vaka**, 4 isteğe bağlı sistem testi atlama, 0 hata;
  derleyici uyarısı yok (Core 828, App 24, AI 22, SSH Swift Testing 355).
  Bu aşama 25 çekirdek ve 2 uygulama testi ekledi: bozuk/hizasız payload,
  bilinmeyen başlangıç geçmişi, PID/başlangıç değişimi, oluştur/yok et/kimlik
  tekrar kullanımı, saat değişimi, tarih tahliyesi, çok iş parçacıklı callback
  girişi, bildirim birleştirme, eski nesil callback, kısmi kayıt/abonelik/kaldırma
  hatası, ortak sahiplik, tam liste gönderme, limitte fallback, geç bildirim,
  filtre/sıralama/ayar kalıcılığı ve native sekmenin kendi tarihini koruması.
- Native TR/EN **494 kontrol** (dil başına 247) geçti. Yeni 54 kontrol, üretim
  `WindowLifecycleService` ve `WindowCatalog` ile ayrı **kendi test sürecimizin**
  gerçek WindowServer olaylarını kullanır. Mevcut pencereye tarih uydurmama,
  iki yeni pencerenin sırası ve native panelde Tab gezinmesi, açık panelimizin
  kendini gereksiz yenilememesi, yok edilmiş handle'ın odaklamadan önce reddi,
  Space okumasında bekleyen eski taramanın onu geri getirememesi, ortak sahiplik,
  durdurma/yeniden başlatma ve yardımcı sürecin temiz çıkışı doğrulandı.
- Katalog taraması yapılmadan, otomatik yeni-yüzey yolunun **gerçekten** iki
  pencereyi çözüp izlediği Debug tanısı ile kontrol edilir; başka bir taramanın
  tesadüfen aynı sonucu üretmesi başarı sayılmaz. Gerçek arka plan native
  sekmesi ve uygulaması gizliyken oluşturulan pencere için oluşturma **ve** yok
  edilme aynı yoldan doğrulandı. Eylem/kimlikler yalnız sahip olunan sürece aittir.
- Canlı denetim iki hata buldu: CoreGraphics'e kutulu sayı dizisi gönderme ve
  gerçek oluşturma anında henüz sıfır olan çerçeveyi reddetme. İkisi düzeltildi.
  Test sürecinin NSWorkspace listesine girmesi ve uygulamasının gizlenmesi de
  AppKit işlem tamamlanması beklenerek ölçülür; test dosyasının ilk yazılması
  bu durumların kanıtı sayılmaz. `birthResolutionTrace` ve `extraResolutionTrace`
  yalnız ilgili kendi fixture kimliklerinin gerçek ilk meta verisini kaydeder.
- Kapatılıp bellekte tutulan kendi NSWindow'umuzun CG listesinde kaldığı ve henüz
  yok edilme olayı vermediği tekrar doğrulandı. Referans bırakılınca olay geldi.
  Kullanıcı kapatmasının bütün uygulamalarda çözülmüş olduğu sonucu çıkarılmaz.
- `scripts/check-localizations.sh`: **4126 anahtar**, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı; kaydedicide 9 anahtar ve 0 eksik Türkçe çeviri.
- Debug paket/imza ve `swift build -c release --product MacPocket` geçti.
  Salt okunur üretim kimliği preflight'ında AX/Ekran Kaydı yine **false**;
  AppState başlatılmadı ve izin istenmedi. Buradaki WindowServer kabulü
  başka uygulamalarda AX/SCK, fiziksel kısayol veya VoiceOver kabulü değildir.
- Sürüm **0.1.5 / build 8** korundu. Yerel çıktılar
  `.build/switcher-stage6-{full-tests,bundle,runtime,localizations}.log`,
  `.build/switcher-stage6-release-build.log`, `.build/switcher-stage6-permissions.json`;
  rapor/görüntüler `.build/switcher-audit/{tr,en}/`, `creation-order.png`,
  `lifecycle-*/state.json`. Odaklı Debug denetimi `--audit-switcher <path>` ile
  birlikte `--only-lifecycle` kabul eder; onun ayrı çıktısı
  `.build/switcher-audit/lifecycle-only/report.json` altındadır.

## Yedinci aşama: sekme grubunu Space dışında yeniden keşfetme

- `TabAccessibility<IO>` keşif, kimlik, grup belleği ve eylem doğrulamasını tek
  yerde tutar. Üretimde `AXWindowTabIO` aynı AXUIElement API'lerini kullanır;
  AX referansları `WindowCatalog` actor'ünden çıkmaz. Debug'da aynı mantığı
  kendi süreç içi NSAccessibility nesneleriyle kullanan ayrı taşıma vardır.
  Bu ayırma TCC erişimi sağlamaz ve uzaktaki AX yolunun canlı kabulü değildir.
- Yalnız güncel `WindowTabProjectionResolver` fiziksel doğrulamasından geçen
  gruplar hatırlanır. İlk kez görülen bir uygulama içi NSTabView/tarayıcı şeridi
  sırf AXTabGroup olduğu için kalıcı keşif kaynağına dönüşmez. Grup kaydı süreç
  PID'si **ve** kernel başlangıcıyla bağlıdır; eski sürecin verisi yeniden
  kullanılmış PID'ye aktarılmaz. Kapsamlı olmayan bir PID/uygulama sorgusu,
  kapsam dışındaki diğer canlı uygulamaların kayıtlarını silmez.
- Katalog, AXWindows listesindeki pencerelerin yanına daha önce doğrulanmış
  grubun **şimdiki AXWindow kökünü** ekleyebilir. Grup/root rolü, süreç,
  özel pencere kimliği ve güncel WindowServer'da aynı PID'ye ait fiziksel kayıt
  gerekir. Yalnız tutulmuş AX nesnesinin varlığı yeterli değildir. Geometriyle
  sekme kökü tahmin edilmez; özel pencere kimliği alınamıyorsa native sekme yolu
  uygulanmaz, sıradan katalog/geometri yedeği ayrı devam eder.
- Başlık, seçili kontrol, düğmeler ve pencere durumu her taramada yeniden okunur.
  AXChildren ağacı alınamazken kayıtlı **grup başvurusu** hâlâ okunabiliyorsa o
  grup üzerinden tekrar denenir. Okuma başarısızsa eski sekme listesi, başlık
  veya seçim yayımlanmaz. Bilinen geçersiz grup bırakılır; geçici okunamayan
  grup sınırlı bellekte bir sonraki olağan taramayı bekleyebilir.
- Grup kökü kontrollerin okunmasından önce **ve sonra** aynı pencereyle
  karşılaştırılır; seçili kontrolün değeri tekrar okunur. Sekme değişiminin
  eski kökle yeni listeyi eşleştirebildiği yarış bu kontrollerle reddedilir.
  Yalnız gerçek düğme kimliği takip edilir. Kaydedilmiş düğme, sıradaki başka
  düğmeye veya aynı başlıklı yeni sekmeye yönlendirilmez; güncel başlık da
  eylem anında doğrulanır. İzin yoksa native sekme odağı uygulamayı
  etkinleştirmeden reddedilir.
- Grup belleği en son doğrulanan **128 grup / 2048 kontrol** ile sınırlıdır.
  Sınırlı token tablosunda tahliye edilen kimlikler, ancak tutulan aynı gerçek
  nesneyle eşitlik sağlanırsa geri bağlanır. Grup başvuruları süreç bitişi,
  bilinen geçersizleşme, izin kaybı veya kapasite tahliyesinde bırakılır.
  Keşifte uygulama başına 200 ms ek kurtarma bütçesi, mevcut 80 pencere ve
  toplam katalog süresi/öğe sınırları korunur. Bütçe sınırlı taramalarda başlangıç
  döner; yavaş bir grubun diğerlerini sürekli engellememesi amaçlanır. AX çağrıları
  arasında denetlenen bütçeler sert zaman aşımı garantisi değildir.
- Yeniden bulunan kök, normal AX satırıyla aynı güncel metadata/eylem yolundan
  geçer. Tam/boş Space üyeliği, fiziksel yüzey sayısı ve aynı çerçeve kanıtı
  her projeksiyonda tekrar gerekir. Okunamayan Space üyeliğine eski Space ataması
  yapıştırılmaz; arka plan sekmelerine görüntü kimliği tahmin edilmez.
- İzin açıklaması, Ekran Kaydı'nın diğer Space'lerdeki **bazı** pencereler için
  gerektiğini söyler. Okunabilen kayıtlı AX grubunun başlıkları için Ekran Kaydı
  gerekmez; gerçek küçük resim/tam boy yakalama hâlâ bu izni gerektirir.

Doğrulama:

- `swift test`: **1.247 vaka**, 4 isteğe bağlı sistem testi atlama, 0 hata ve
  0 derleyici uyarısı (Core 846, App 24, AI 22, SSH Swift Testing 355).
  Yeni 18 çekirdek test; kanıtsız grubu hatırlamama, eksik AX listesi/ağacı,
  güncel başlık/seçim, önce/sonra kök değişimi, süreç yeniden kullanımı, sorgu
  kapsamı, geçici/kalıcı AX hatası, eksik fiziksel yüzey, yabancı süreç/düğme,
  çelişkili kök, süre/öğe/grup/kontrol sınırı, izin kaybı, yeniden sıralama,
  kaldırılan/yeniden adlandırılan kontrol ve eylem sonrası seçim değerini kapsar.
- Native TR/EN **524 kontrol** (dil başına 262) geçti; yeni 30 kontrol eklendi.
  Kendi iki NSWindow'umuz gerçekten sekmelendi. Ayrı bir kendi penceremiz tam
  ekrana girip yeni Space oluşturdu; eski sekme grubu gerçekten görünmeyen
  Space'te kaldı. Katalog girdisi kasıtlı boş AXWindows listesiyle verilirken
  **ortak üretim keşif mantığı**, tutulan gerçek NSAccessibility grup nesnesinden
  kökü/sekme listesini yeniden okudu; kart kimlikleri ve gerçek Space filtresi
  korundu. Space dışında değiştirilen başlık eski veriden gelmedi.
- Tam ekran giriş/çıkış tamamlanma bildirimleri ve WindowServer topolojisi
  beklendi; özgün Space geri geldi, geçici Space kaldırıldı. Dönüşte kayıtlı
  gerçek düğmeye basmak doğru pencereyi seçti; pencere kökü AX listesi olmadan
  yeniden takip edildi. Kapatılan sekmenin yerine **aynı başlıklı** yenisi
  eklendiğinde eski eylem, taşımanın press metoduna bile ulaşmadan reddedildi.
  Native görüntü `native-tabs-space-roundtrip.png` olarak kaydedildi.
- Bu native kanıt **kendi süreç içi formal NSAccessibility taşımasına** aittir;
  `listedAXWindowsIntentionallyOmitted=true`, `externalAXTransportVerified=false`
  ve `otherSpaceFocusVerified=false` rapordadır. Uzaktaki AXUIElement yolunda
  gerçekten listeden düşme/yeniden okuma, başka Space'ten odaklama ve üçüncü
  taraf uygulamalar ayrıca gerçek izinle kabul edilecek. Kapatılıp fiziksel
  yüzeyi bellekte tutulan bütün üçüncü taraf pencere durumları çözülmüş sayılmaz.
- `scripts/check-localizations.sh`: **4126 anahtar**, 0 eksik İngilizce çeviri,
  0 biçim uyuşmazlığı; kaydedicide 9 anahtar ve 0 eksik Türkçe çeviri.
  Debug paket/imza ve `swift build -c release --product MacPocket` geçti.
  Üretim kimliği preflight'ında AX/Ekran Kaydı yine **false**, AppState başlamadı
  ve izin istenmedi. Sürüm 0.1.5 / build 8
  korundu; Release veya sürüm etiketi oluşturulmadı.
- Yerel çıktılar `.build/switcher-stage7-{tests,full-tests,bundle,runtime,localizations}.log`,
  `.build/switcher-stage7-release-build.log`, `.build/switcher-stage7-permissions.json`
  ve `.build/switcher-audit/{tr,en}/report.json` altındadır. Odaklı Debug denetimi
  `--audit-switcher <path> --only-tabs` kabul eder; ayrı kanıtı
  `.build/switcher-audit/tabs-only/report.json` içindedir.

## Sekizinci aşama: görünüm, ekran, gecikme ve animasyon tercihleri

Uygulananlar:

- Genel ayarlar ve dokuz profil için dört başlık modu, üç kısaltma yönü,
  durum simgeleri, masaüstü numaraları, hover eylemleri ve küçük resim
  görünürlüğü. Yeni alanlar eski JSON kayıtlarını bozmaz; `nil` geneli izler,
  `false` ve `0` açık tercih olarak korunur. Bilinmeyen enum değerleri güvenli
  varsayılana döner; gecikme sonlu 0–900 ms aralığına alınır.
- Küçük resimler kapalıysa bu stil simgelere döner ve küçük resim kuyruğu
  çalışmaz. Tam boy önizleme ayrı kalır. Görsel ad tercihi ve kısaltma,
  yardım/erişilebilirlikteki tam uygulama ve pencere adını değiştirmez.
  Durum glyph'i gizlendiğinde birleşik durum açıklaması korunur. Space
  üyeliği bilinmiyorsa `?`, birden fazla biliniyorsa `+` gösterilir; ham
  Space ID'leri veya tahmini masaüstü numarası çizilmez.
- Panelin ekranı oturum başında seçilir: fare, öndeki uygulamanın ilk uygun
  ön plan pencere çerçevesi veya `CGMainDisplayID()` ile ana menü ekranı.
  Öndeki pencere belirlenemiyorsa fare, o da belirlenemiyorsa kalan ilk
  ekran kullanılır. Ekran filtresi aynı oturum ekranına bağlanır. Aktif
  pencere seçimi AX odak kabulü değil, WindowServer çerçeve çıkarımıdır.
- Basılı tutarak açılışta ayarlanabilir gecikme; hızlı seçme bırakıldığında
  odaklama panel gecikmesini beklemez. Açık tut/ara modlarında bırakma,
  bekleyen paneli hemen gösterir; arama tuşları gecikme sırasında başka
  uygulamaya gönderilmez. Varsayılan gecikme 110 ms'dir.
- Açılış 90 ms, kapanış 90 ms, seçim 160 ms ve önizleme girişi 120 ms ayrı
  açılır/kapatılır. Eski varsayılanlar korunur; yeni kapanış ve önizleme
  giriş animasyonları varsayılan kapalıdır. Sistem/uygulama Hareketi Azalt
  tercihi tümünü geçersiz kılar. Görsel animasyon odaklamayı bekletmez.
- Native testte doğrudan `resignKey()` çağrısının AppKit anahtar pencere
  kaydını tutarsız bırakıp yeniden açılan panelin Tab almamasına yol açtığı
  görüldü. Etkileşimli panel artık hemen `orderOut` ile bırakılır; kapanış
  yalnız kendi görüntüsünü gösteren, klavye/fare almayan geçici panelde
  yapılır. Yeni oturum/durdurma bu görüntüyü ve eski kapanış görevini kaldırır.
- Eski odaklama görevi yeni oturumda/modül durduğunda iptal edilir.
  Katalog, AX eylemi ve model sonucu iptali denetler; geciken başarı veya
  hata yeni oturumun hata metnini silemez/değiştiremez. Çoktan gerçekleşen
  işletim sistemi eylemi geri alınmış sayılmaz.
- Ayarlar mevcut grouped Form düzeninde üç açılır ayrıntı grubundadır.
  Küçük kartlarda sekme etiketi `1/2` biçimindedir; tam anlam durum/yardım
  metninde korunur. Sabit boyutlu simge kartları da en az 84×92 pt'dir;
  küçük resim kartları en az 160×124 pt'dir. Bu, küçük ölçekte iki satırlı
  ad ve eylemler için yer korur.

Doğrulama:

- Yeni 13 Core testi: varsayılanlar, tüm alanların false/zero dahil JSON
  gidiş dönüşü, eski/bilinmeyen kayıtlar, genel ayarı izleme, bozuk/aşırı
  gecikme, sanal ekran seçimleri/fallback, Space rozetleri, bağımsız büyük
  önizleme, Reduce Motion ve en küçük kart. Bir App testi, geç kalan odak
  başarısı ve hatasının iptal sonrası yeni hata durumunu koruduğunu denetler.
- `swift test`: **1.261 vaka**, 4 isteğe bağlı sistem testi atlama, 0 hata
  ve 0 derleyici uyarısı (Core 859, App 25, AI 22, SSH Swift Testing 355).
- Tam native TR/EN denetimi **690 kontrol** (dil başına 345) ile geçti.
  İngilizce/açık ve Türkçe/koyu 520 pt formlar ile küçük kartların ekran
  görüntüleri incelendi. Ölçülen yatay taşma yok; bu ölçüm tam erişilebilirlik
  kabulü değildir.
- Odaklı native denetimde **82 kontrol** geçti: üç stil × dört başlık modu,
  0,6 ölçek ve uzun adlar, görüntü yakalamama, gizli glyph'lerle durumun
  korunması, yeniden açılma + tek yerel Tab, observer çoğalmaması, gecikme,
  üç bırakma modu, iptal, tam boy görüntü girişi, temiz durdurma; 520/760 pt
  formlar, sekiz gerçek anahtar ve gecikme adımlayıcısının bağlı değeri
  değiştirmesi. Ekran görüntülerinde küçük kartlar ve Türkçe form incelendi.
- Aynı profilin değişmeyen ayarlarla tekrar açılması bir sonraki karta geçer;
  aynı ID'nin ayarları değiştirilmişse yeni görünümle oturum açılır. Tam
  native denetim, ilk uygulamadaki gezinme regresyonunu yakaladı; iki durum
  için ayrı kontrol eklendi/korundu.
- Kanıt kendi fixture katalog/görüntülerimiz ve yerel AppKit kontrolleridir.
  Ayar menülerindeki her seçimin ve profil ayrıntılarının fiziksel klavye/
  VoiceOver kabulü yapılmadı; enum kalıcılık/çözümleme model testleriyle
  doğrulandı. Gerçek AX/SCK, fiziksel HID, çoklu ekran, Sticky Keys ve
  trackpad kabulü bu aşamayla tamamlanmış sayılmaz.
- Çıktılar `.build/switcher-stage8-{bundle,full-tests,runtime,localizations}.log`,
  `.build/switcher-stage8-release-build.log`,
  `.build/switcher-audit/appearance-only/report.json` ve tam TR/EN raporlarıdır.
  Odaklı Debug modu `--audit-switcher <path> --only-appearance` kabul eder.
- `scripts/check-localizations.sh`: **4156 anahtar**, 0 eksik İngilizce
  çeviri, 0 biçim uyuşmazlığı; kaydedicide 9 anahtar, 0 eksik Türkçe çeviri.
  Debug paket/imza ve `swift build -c release --product MacPocket` geçti.
  Son Release derlemesi 130,69 saniyede tamamlandı; bu uygulama gecikmesi
  veya çalışma zamanı performans ölçümü değildir. Üretim preflight kaydı
  `.build/switcher-stage8-permissions.json`: AX/SCK true, AppState başlamadı.
  Sürüm **0.1.5 / build 8** korundu; etiket veya GitHub Release oluşturulmadı.

## Dokuzuncu aşama: gerçek uzaktaki AX ve ScreenCaptureKit kabulü

Önceki aşama ilerlemeydi. Üretim imzasında AX/Ekran Kaydı izinleri açık
görüldüğünden, sentetik katalog/görüntü yerine ayrı bir AppKit süreciyle gerçek
taşıma test edildi. Bu aşama bütün üçüncü taraf uygulamaların veya fiziksel
tuşların kabul edildiği anlamına gelmez.

Uygulanan düzeltmeler:

- Küçültülmüş pencerenin geri açılması asenkrondur; AX geri açma isteği kabul
  edilse de `AXRaise` kısa süre geçici hata verebiliyordu. Yalnız `.cannotComplete`
  ve `.failure` için en fazla 12 yükseltme denemesi, arada 40 ms bekleme
  eklendi. Her denemede süreç başlangıcı/PID ve görev iptali denetlenir;
  desteklenmeyen veya eskimiş hedef yeniden denenmez. AX çağrı süreleri ayrıca
  eklenir; 440 ms kesin toplam süre garantisi değildir.
- `NSRunningApplication.hide()` canlı test uygulamasını gizleyemediğinde,
  kimliği yeniden doğrulanmış hedefin standart `AXHidden` niteliği yedek yol
  olarak kullanılır. Gizli uygulamaya dönüşte `activate()` reddi artık yanlış
  biçimde “eskimiş pencere” sayılmaz; geçerli süreçte AX gizliliği kaldırma ve
  öne getirme denenir. Gerçek gizleme, geri dönme ve doğru hedef doğrulandı.
  API başvurusu: [Apple AXHidden](https://developer.apple.com/documentation/applicationservices/kaxhiddenattribute).
- Kapatılıp bellekte tutulan NSWindow'un fiziksel WindowServer yüzeyi
  yaşayabiliyor. Eksiksiz AX listesinde olmayan, ekran dışında kalmış ve
  **görünür bir Space'e** atanmış salt WindowServer satırı, “başka Space'te
  açık pencere” diye yeniden eklenmez. Gerçek AX pencereleri, gizli/küçültülmüş
  hedefler, görünmeyen Space'ler ve bilinmeyen/kısmi metadata korunur.
  Son satır çıkarıldığında uygulamanın penceresiz kaydı üretilir; aynı
  NSWindow yeniden açıldığında güncel AX kaydı yeniden kabul edilir.
- Kapatma animasyonu ilk liste yenilemesinden uzun sürebilir. Model, kapanan
  hedef salt WindowServer satırına dönmüşse 200/400/800 ms beklemelerle en fazla
  üç ek salt okunur yenileme yapar; AX eylemini tekrarlamaz, eylem kilidini
  bekletmez. Panel kapanışı/modül durması bekleyen işi iptal eder. AX penceresi
  açık kalmış iptal edilmiş kapatma bu yeniden denemeyi başlatmaz.
- Her iki denetim betiği eski `report.json` dosyasını açılıştan önce kaldırır;
  başarısız yeni çalıştırma eski başarılı raporla geçemez. Ayrı hedef yalnız
  test pencerelerinin AX alt ağaçlarını kaydeder; uygulama/sistem menüleri
  tanı envanterine alınmaz.

Canlı kanıt:

- [Dış süreç denetimi](../scripts/audit-window-switcher-external.sh) üretim
  bundle kimliğinde, AppState/modüller/global kısayollar/izin isteme başlamadan
  çalışır. [Ayrı hedef](../scripts/fixtures/WindowSwitcherFixture.swift) kendi
  pencerelerini üretir; katalog ve eylemler PID + uygulama yolu + süreç
  başlangıcıyla sınırlıdır. Kullanıcı tercihleri değiştirilmez.
- **47 kontrol** geçti. Aynı başlıklı ve başlangıçta aynı çerçeveli A/B
  pencereleri farklı kimliklerle bulundu; SCK kırmızı/yeşil görüntüleri doğru
  hedeften yakaladı. İçerik maviye dönünce yeni yakalama değişti; üretim canlı
  küçük resim kuyruğu sonraki kırmızı değişimi de yeniledi. Piksel bütçesi,
  kuyruk durdurma ve oturum sonrasına yayın yapmama denetlendi. Önbellek
  bilerek korunur; durdurma bütün önbellek görüntülerini silme iddiası değildir.
- Gerçek AX odak gözlemcisi iki farklı odağı kaydetti; MRU doğru sıralandı.
  Aynı başlıklı A/B hedefleri, küçült/geri getir, gizle/göster, gerçek
  görüntülerle HUD/tam boy önizleme ve HUD seçimini odaklama geçti.
- Gerçek `AXRadioButton` / `AXTabButton` düğmeleri keşfedildi, arka plan
  sekmesine basmak gerçekten B'yi seçti ve yeni başlık yeniden okundu.
  Başka bir kendi penceremiz AX ile tam ekrana alındı. AXWindows'ta yalnız
  bu yeni Space'in penceresi listelenirken, eski gruptaki iki sekme ortak
  üretim mantığıyla **gerçek kayıtlı AXUIElement başvurularından** tekrar
  okundu; görünmeyen Space üyeliği ve kimlikler korundu. Bu turda liste
  kasıtlı boşaltılmadı, AX taşıması taklit edilmedi.
- `windowDidEnterFullScreen` / `windowDidExitFullScreen` tamamlanmaları ve
  WindowServer topolojisi beklenerek özgün Space'lerin geri geldiği doğrulandı;
  stil bayrağının erken değişmesi yeterli sayılmadı. Kapatılan gerçek pencere
  700 ms sonra da fiziksel yüzeyini korurken katalog/eylem kaydı çıkarıldı.
  Model de kapanış animasyonu sonrasında satırı çıkardı. Son pencerenin
  kapatılması ve aynı tutulmuş pencerenin tekrar açılması ayrıca geçti.
- Yeni üç App testi; gecikmeli kapatmanın eylem kilidini tutmadan listeden
  çıkarılması, durdurmanın ek katalog okumasını kesmesi ve AX penceresini
  koruyan iptal edilmiş kapatmanın gereksiz ek okuma üretmemesini kapsar.
  `swift test`: **1.264 vaka** (Core 859, App 28, AI 22, SSH 355), 4 isteğe
  bağlı sistem testi atlama, 0 hata ve 0 derleyici uyarısı. Önceki TR/EN
  native denetimi de **690 kontrolde** geçti. Yerelleştirme: **4156 anahtar**,
  0 eksik çeviri ve 0 biçim uyuşmazlığı; kaydedicide 9 anahtar, 0 eksik Türkçe.
- Debug paket/imza ve Release derlemesi geçti; son Release 109,35 saniyede
  tamamlandı. Son üretim preflight'ında da AX/SCK true, AppState başlamadı.
  Kaynak, rapor ve imzalı executable SHA-256 kayıtları
  `.build/switcher-stage9-evidence.json` dosyasındadır.
- Kaynak [WindowExternalRuntimeAudit.swift](../Sources/MacPocketApp/Diagnostics/WindowSwitcher/WindowExternalRuntimeAudit.swift),
  kanıt `.build/switcher-external-audit/run/report.json`; yalnız kendi
  görüntülerimiz `external-{A-red,B-green,A-blue,HUD}.png` dosyalarındadır.
  Diğer çıktılar `.build/switcher-stage9-{bundle,external,app-tests,full-tests,runtime,localizations}.log`,
  `.build/switcher-stage9-release-build.log` ve `.build/switcher-stage9-permissions.json`.

Kapsam sınırı: başka Space'ten odaklama, gerçek üçüncü taraf uygulama farkları,
görünmeyen Space'te kapatılmış yüzeylerin bütün anlamsal durumları, gerçek izin
geri alma, fiziksel Option/Tab, VoiceOver/Sticky Keys, çoklu ekran ve trackpad
kabulü tamamlanmadı. Tam CPU/bellek/gecikme ölçümü yapılmadı. Özellikle eksik AX
veya Space bilgisi kapalı pencere sonucuna zorlanmaz. Sürüm 0.1.5 / build 8
korundu; sürüm etiketi veya GitHub Release oluşturulmadı.

## Onuncu aşama: özgün Space'e odak ve iki bağlı ekran

Kaynak değişikliği:

- Arka plan yerel sekmesi seçilmeden önce güncel grubun AXWindow kökü alınır.
  Önce bu kökün özgün Space'i görünür yapılır, sonra sekme seçilir. Sekmeye
  doğrudan basmak, daha önce Space atanmamış fiziksel yüzeyini tam ekran
  penceresinin Space'ine taşıyabiliyordu. Yalnız hedefin görünmesi yeterli
  kabul edilmez; özgün üyelik de korunmalıdır.
- `WindowSpecificActivation` isteğe bağlı `_SLPSSetFrontProcessWithOptions`
  sembolünü çalışma anında bulur. Çağrıdan önce canlı WindowServer kaydının
  pencere/PID eşleşmesi, eylem akışında süreç başlangıcı ve iptal denetlenir.
  Çağrının başarılı dönmesi tek başına odak/Space başarısı sayılmaz.
- Soğuk katalogda standart AXWindows/AXChildren/focused/main listeleri
  hedefi içermeyebilir. `WindowRemoteAXLookup` yalnız açık odak isteğinde,
  katalog aktöründe, 250 ms ve 8192 aday sınırıyla isteğe bağlı Cocoa
  remote-token ABI'sini dener. Her adayın IPC zaman aşımı 20 ms'dir; süre
  dolarken başlamış tek IPC bu bütçeyi aşabilir. PID, tam pencere kimliği ve
  AXWindow rolü gerekir; başlık eşleştirme, arka plan taraması ve girdi
  gönderimi yoktur. Yüksek/seyrek AX kimlikleri veya farklı AX sağlayıcıları
  çözülemeyebilir; bu durumda odak isteği açıkça başarısız olur.
- WindowServer kimliği bilinen gerçek pencereye odak için AX izni gerekir;
  yalnız uygulamanın etkinleşmesi pencere odağı başarısı sayılmaz. Bu izin
  dalı statik olarak düzeltildi; canlı izin geri alma testi yapılmadı.
- Çapraz Space denemesinde hedefli sentetik mouse-down çağrısı başarı dönse
  de odağı taşımadı. Bu deneme üründen çıkarıldı; üretim odağı mouse-down/up
  üretmez. Kullanılan ABI'ler için [AltTab AX kaynağı](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/AXUIElement.swift)
  ve [SkyLight sarmalayıcısı](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/SkyLight.framework.swift)
  araştırıldı; bu kaynak okuması canlı MacPocket kabulünün yerine kullanılmadı.

Canlı kabul ve sınırları:

- Kendi ayrı AppKit sürecimizde **69 kontrol** geçti. Önceki 47 kontrole,
  çapraz Space sekme seçimi, iki bağlı ekranda panel/filtre ve önbelleksiz
  sıradan pencereye odak kontrolleri eklendi. Soğuk katalog hedefi başlangıçta
  AX başvurusuz ve diğer Space'teydi; sonunda tam pencere kimliği odağa geldi,
  özgün masaüstü görünür oldu ve pencerenin Space üyeliği korundu. İçerikte
  mouse olayı ve pencerenin konum/boyutunda değişiklik olmadı.
- Gerçek bağlı ekran kimlikleri 3 ve 1 üzerinde test pencereleri ayrı ekranlara
  yerleştirildi. Fare ve ana menü politikası ekran 3'ü, öndeki pencere politikası
  ekran 1'i seçti. Panelin gerçek ekranı, fiziksel ekrandaki HUD yüzeyi ve
  gösterilen pencere kimliklerinin aynı ekranı kullanması doğrulandı. İmleç
  programatik konumlandırılıp geri alındı; fiziksel kullanıcı girdisi veya
  ekran sökme/takma testi değildir.
- Yeni üç Core testi; arka plan sekmesini seçmeden güncel fiziksel grup kökünü
  çözme, kaldırılmış düğmeyi reddetme ve farklı PID'nin kökünü reddetme geçti.
  `swift test`: **1.267 vaka** (Core 862, App 28, AI 22, SSH 355), 4 isteğe
  bağlı atlama, 0 hata ve 0 derleyici uyarısı. Yerelleştirme **4156 anahtar**,
  0 eksik/biçim uyuşmazlığı; kaydedicide 9 anahtar ve 0 eksik Türkçe.
- Bir ara dış süreç koşusu, derlemeler sürerken yerel sekme adımında `expired`
  ile erken durdu; nedeni kesinleştirilmedi. Sonraki iki tam koşuda da 69 kontrol geçti.
  Önceki başarısız rapor başarılı kabul edilmedi. Bu kayıt kesintisiz/ölçülmüş
  güvenilirlik veya üçüncü taraf uygulamalarda tam kapsam iddiası değildir.
- TR/EN native denetimi **690 kontrol** (dil başına 345) ile geçti. Debug
  paket ve imza doğrulandı; Release derlemesi **107,69 saniyede** tamamlandı.
  Son üretim preflight'ında AX/SCK true, AppState başlamamıştı.
- Raporlar `.build/switcher-stage10-*` ve kaynak/rapor/executable SHA-256
  özeti `.build/switcher-stage10-evidence.json` içindedir. Sürüm **0.1.5 / build 8**
  korundu. Üçüncü taraf uygulamalar, fiziksel Option/Tab, VoiceOver/Sticky Keys,
  trackpad, ekran hotplug ve CPU/bellek/gecikme kabulü hâlâ ayrıdır.

## On birinci aşama: koşullu uygulama istisnaları

Uygulanan davranış:

- Tek istisna editörü eski iki listeyi ve yeni kuralları birlikte yönetir.
  Uygulama yolu ve tam bundle kimliği mevcut kesin eşleşmesini korur; önek
  ayrıca seçilir. Önek ham `hasPrefix` anlamındadır: `com.example.` gibi bir
  değer uygulama ailesini kapsar. Boş hedef hiçbir uygulamayı eşleştirmez.
- Her kuralın birbirinden bağımsız iki sonucu vardır. Liste görünürlüğü:
  göster / her zaman gizle / açık penceresi yokken gizle / başlık metni geçince
  gizle. Global kısayollar: etkin bırak / uygulama öndeyken kapat / yalnız
  odaktaki pencere tam ekrandayken kapat. Birden fazla eşleşen kural OR ile
  birleşir; kural devre dışı bırakılabilir veya kaldırılabilir.
- Başlık eşlemesi literal, büyük/küçük harfe duyarlı ve “herhangi biri”
  anlamındadır; boş satırlar atlanır, regex yoktur. CRLF/CR/Unicode satır
  ayraçları girişte ayrılır. Küçültülmüş/gizli fiziksel pencere ve WindowServer
  kimliği olmayan doğrulanmış yerel sekme “penceresiz uygulama” sayılmaz.
- Bundle kimliği katalogda NSRunningApplication'dan alınır ve yerel sekme
  kartlarına taşınır; her filtrelemede diskten bundle okunmaz. Kurallar arama,
  kategori, gruplama ve sekme birleştirmeden önce uygulanır. MacPocket'ta
  istisnalar “öndeki uygulama” profili dahil bütün profillerde geçerlidir;
  AltTab'ın bu profilde genel gizleme kuralını aşma davranışı kopyalanmadı.
- Okumak kayıt göçü/yazma yapmaz. İlk açık düzenleme `switcher.exceptions.v1`
  JSON kaydını yazar; eski tam yol/daima gizle ve tam bundle/daima kapat alt
  kümesi eski anahtarlara da yazılır. Yeni koşullar eski sürümlere genişletilerek
  aktarılmaz. Bozuk, bilinmeyen türde veya gelecekteki enum içeren veri
  korunur, eski basit alt küme kullanılır ve editörde kurtarma mesajı gösterilir.
  Hızlı “Bu Uygulamayı Hariç Tut” işlemi de aynı depoyu kullanır ve okunamayan
  kaydın üzerine yazmaz. Sınırlar: 128 kural, 32 başlık metni/kural, 512
  karakter/metin, 1024 karakter/uygulama hedefi.
- Kısayol kapatma açılışta ve tercih değişince yeniden değerlendirilir;
  uygulama aktivasyonu bekleme hatası giderildi. Yalnız eşleşen tam ekran
  kuralı ve açık global kısayollar varken 250 ms aralıkla odaktaki AX pencere
  okunur. AX mesajları ana aktörden uzakta, 30 ms zaman aşımıyla; PID ve süreç
  başlangıcı okuma öncesi/sonrası doğrulanır. Başka Space'teki veya arka
  plandaki tam ekran kardeş pencere kısayolları kapatmaz. İzin/durum bilinmezse
  kısayollar etkin kalır. Kural/app değişimi, kayıt modu ve modül durması
  işi iptal eder; geç sonuç eski askıya alma durumunu geri getiremez.
- Öndeki uygulama/Space değişimi üretim bildirimleriyle yeniden okunur.
  Testte normal C penceresi açıkça odağa alınmadan tam ekrana geçirilmişti;
  tam ekran koşulu testi gerçek odak başlangıcıyla düzeltildi. AX setter'ın
  `.cannotComplete`/`.failure` sonucu istenen tam ekran geçişini başlatmış
  olabilir: üretim eylemi 2 saniyelik bütçeyle salt durum okuması yapar,
  ikinci toggle göndermez. Başka hata türleri başarı sayılmaz. Bu yeni hata
  dalı zorla enjekte edilmiş AX hatasıyla ayrıca kabul edilmiş değildir.

Doğrulama kapsamı:

- Çekirdek testleri hedef türleri/önek, mevcut kayıtların göçsüz okunması,
  bağımsız politikalar, gizli/küçültülmüş pencere/arka plan sekmesi ayrımı,
  literal Türkçe başlık eşlemesi, filtre/gruplama sırası, JSON geri dönüşü,
  bozuk/future/tür dışı veri koruması ve sınırları kapsar. App testleri tablo
  ve oturum filtresinin anında değişmesini, hızlı hariç tutmayı, başlangıç/
  tercih düzenlemesini, aynı uygulamada normal/tam ekran/bilinmeyen durum,
  kural kaldırma, ön uygulama değişimi ve durdurma sırasında geç sonuçları kapsar.
- Native editör testleri iki genişlikte etkinleştir/devre dışı bırak,
  düzenleme sheet'i, Vazgeç ile kayıtsız kapanış, boş hedefte doğrulama ve
  geçerli kuralın gerçek Kaydet düğmesiyle bir kez yazılmasını denetler.
  Türkçe/İngilizce ad-hoc denetim tercihleri ayrı suite'tedir; global
  kısayollar ve trackpad kaydı başlatılmaz. Native ağaç/çerçeve incelemesi
  VoiceOver veya fiziksel klavye kabulü değildir.
- Üretim kimliğindeki ayrı uygulama denetiminde bundle metadata'sı ve
  yeniden adlandırılmış gerçek arka plan sekmesine başlık kuralı doğrulandı.
  C normalden tam ekrana geçince politika askıya alındı, Desktop sekmesine
  ve soğuk E penceresine dönünce açıldı; C'ye dönünce yeniden kapandı.
  Ayrı uygulamanın son penceresi kapandığında koşullu penceresiz gizleme ve
  yeniden açıldığında tekrar görünme ayrıca denetlenir. Bu sürücü Carbon
  tuşlarını kaydetmez; gerçek tuşun hedef uygulamaya teslimi ayrıca kabul
  edilecektir. Kendi editör/listelerimizin gerçek SCK görüntüleri de üretim
  imzası altında alınır; kullanıcı pencerelerinin görüntüsü kaydedilmez.
- Son `swift test`: **1.287 vaka** (Core 874, App 36, AI 22, SSH 355),
  4 isteğe bağlı atlama, 0 hata ve 0 derleyici uyarısı. Yerelleştirme **4192
  anahtar**, 0 eksik İngilizce/biçim uyuşmazlığı; kaydedicide 9 anahtar ve
  0 eksik Türkçe. Editörde genel “Kaydet” anahtarının İngilizce “Record”
  karşılığı yerine bağlama özel “İstisnayı Kaydet / Save Exception” kullanılır.
- İlk 480 pt sheet'in alt seçenekleri kaydırma gerektiriyordu. Başlık metni
  ve açıklaması aynı satır grubuna alındı, ilk yükseklik 600 pt'ye çıkarıldı.
  Uzun tam ekran seçim etiketi kısaltıldı; odaktaki pencere koşulu açıklamada
  korunur. İstisnaların birbirini geçersiz kılmadığı arayüzde de belirtilir.
- Ara native koşusunda Kaydet çağrısından hemen sonra yapılan kontrol,
  ertelenmiş SwiftUI eylemini henüz görmedi. Denetim düğmeye tekrar basmadan
  gerçek kayıt sonucunu ve sheet kapanışını sınırlı bekler. Önceki başarısız
  native raporlar `.build/switcher-stage11-native-before-save-wait-{tr,en}.json`
  dosyalarında korunur; başarılı kabul olarak kullanılmaz.
- Son dış süreç denetimi **109 kontrol** ile geçti: 81 ayrı AppKit süreç/
  pencere kontrolü ve 28 kendi editör kontrolü (dördü gerçek SCK görüntüsü).
  TR/EN denetimi **738 kontrol** (dil başına 369) ile geçti. Liste ve sheet
  yatay taşma sezgisi kontrol edildi; Türkçe gerçek SCK görüntüsü ve İngilizce
  native render görsel olarak incelendi. Bu ölçüm tam ekran okuyucu/kontrast
  veya fiziksel tuş teslimi kabulü değildir.
  Son üretim preflight'ında AX/SCK true ve AppState başlamamıştı.
- Kaynaklar: `SwitcherExceptions.swift`, `SwitcherForegroundWindow.swift`,
  `SwitcherExceptionsEditor.swift` ve ilgili model/controller entegrasyonu.
  Debug paket/imza ve son Release derlemesi geçti (**111,39 saniye**).
  SHA-256 kaynak, immutable rapor, test logları, kendi SCK görüntüleri ve
  imzalı executable özeti `.build/switcher-stage11-evidence.json` içindedir.
  Çıktılar `.build/switcher-stage11-{full-tests,bundle,external,runtime,localizations,release-build}.log`
  ve `.build/switcher-stage11-{external,tr,en}-report.json` dosyalarındadır.
  Sürüm **0.1.5 / build 8** korunur; tam AltTab eşdeğerliği iddiası yoktur.

## On ikinci aşama: ok ve Vim gezinmesi

- Davranış bölümüne bağımsız “Ok tuşlarıyla gezin” ve “Vim tuşlarıyla gezin”
  seçenekleri eklendi. Eski kurulumlarda oklar açık, Vim kapalı kalır; tercih
  okumak kayıt yazmaz. Tercihler globaldir ve panel açılırken oturuma alınır;
  açık panelde sonradan değişmez. Tab/Shift+Tab ve Escape korunur.
- `SwitcherPanelInput` eylem/gezinme önceliğini tek saf çözümleyicide toplar.
  h/l yatay, j/k dikey gezer; / boş arama moduna geçirir. Aramada h/j/k/l ve
  / metindir; büyük/Shift'li H/J/K/L de aramaya yazılır. `/` bazı düzenlerde
  Shift gerektirdiği için mantıksal karakterine göre tanınır. Açma sırasında
  basılı değiştiriciler tüketilir, fazladan değiştiriciler yön hareketi yapmaz.
- Vim karakterleri fiziksel ABD klavye konumlarına sabitlenmez. Özel eylem
  atamaları gezinmeden önce uygulanır ve değiştirilmez; oklar özel eyleme de
  atanabilir. Çakışan eylemler, mevcut klavye düzeninde normal/Shift karakter
  çözümüyle ayarlarda açıklanır. Arama sırasında çıplak harf eylemleri yine
  yazıya bırakılır. Tab ve Escape'in gezinme/vazgeçme güvencesi korunur.
- Dikey hareketin düz pencere sayısına göre mod alınması, eksik son satırda
  yanlış satıra geçebiliyordu. Yeni satır geometrisi hedef satırın en yakın
  mevcut sütununa gider; satırlar arasında döner. Liste hazırlanırken yönler
  sayısal sütun uzaklığına çevrilmez, sıra korunarak yeni liste ve yeni sütun
  sayısı üzerinde uygulanır. Seçim hesaplanmadan önce yeni yerleşim hesaplanır.
- `WindowSwitcherModel.cycle` uzaklığı mod aldıktan sonra işler; `Int.min` ve
  `Int.max` tanı girdilerinin taşma üretmesi engellendi. Satır geometrisinin
  boş, tek satır/sütun ve aşırı sayısal girdileri de sınanır.
- Yeni 14 Core testi varsayılanlar, bağımsız tercihler, yönler, mantıksal
  karakterler, Shift gerektiren /, arama/özel eylem önceliği, değiştiriciler,
  Enter alias'ı, çakışma adları, eksik satır ve sıralı bekleyen girdi kapsamını
  denetler. Bir App testi aşırı adım/boş liste seçim aritmetiğini kapsar.
- Native denetim, üç gerçek panel stilinde yerel NSEvent gönderir; doğrulanmış
  katalog ve ekran görüntüsü yerine bu bölümde sahipli sahte satırlar kullanır.
  Dört Vim yönü, oklar, eksik satır, mantıksal karakter, /, sorguda h/j/k/l,
  Escape sonrası boş arama modu, Shift'li harf, açma Option'ı basılıyken gezinme,
  aramada bırakınca seçmeme, oturum tercihi, özel harf/ok eylemi ve listeyi
  beklerken karışık yön sırası denetlenir. 520/760 pt native tercih düğmeleri,
  kalıcı bool değişimi, çakışma açıklaması ve yatay taşma sezgisi ayrıca ölçülür.
- İlk yerel denetim, 110 ms açılış gecikmesini beklemeden panel istemişti;
  bu iki yanlış başlangıç koşulu düzeltildi. Denetim gerçek panel görünürlüğü
  ve hazırlık durumunu bekler. `--only-navigation` yalnız bu bölümü çalıştırır:
  `scripts/audit-window-switcher.sh --skip-build --only-navigation`.
- Son `swift test`: **1.302 vaka** (Core 888, App 37, AI 22, SSH 355),
  4 isteğe bağlı atlama, 0 hata ve 0 derleyici uyarısı. Yerelleştirme **4197
  anahtar**, 0 eksik İngilizce ve 0 biçim uyuşmazlığı; kaydedicide 9 anahtar
  ve 0 eksik Türkçe.
- Önceki istisna denetiminin Kaydet testi, sheet'i kapanan parent contentView'ını
  yeniden kullanıyordu; bir İngilizce tam koşuda eylem çağrısı görülmedi.
  Test artık bağımsız yeni bir NSWindow/NSHostingView üzerinde aynı üretim
  formunun bir kez kaydetmesini doğrular; düğmeye tekrar basmaz. Önceki
  raporlar `.build/switcher-stage12-before-fresh-save-window-{tr,en}.json`
  dosyalarında korunur. Bu değişiklik test penceresinin yaşam döngüsüdür;
  üretim istisna kuralları değiştirilmedi.
- Debug paket/imza ve son Release derlemesi geçti; Release **115,92 saniye**
  sürdü. Kaynaklar doğrulama boyunca sabit tutuldu; önceki eşzamanlı düzenleme
  sırasında eski Core modülü/yeni App çağrısı karışan Release koşusu başarılı
  sayılmadı. Son testler Shift gerektiren / davranışını da içerir.
- Son native TR/EN denetimi **864 kontrol** (dil başına 432; 63 yeni gezinme
  kontrolü) ve dış süreç/gerçek pencere denetimi **109 kontrolde** geçti.
  Native ayarların Türkçe/İngilizce render'ı incelendi; oklar kapalı/Vim açık
  durum ve özel eylem açıklaması görüntüde doğrulandı. Üretim preflight'ında
  AX/SCK true, AppState başlamamıştı. Kaynak/rapor/log/executable SHA-256 özeti
  `.build/switcher-stage12-evidence.json`, değişmez rapor kopyaları
  `.build/switcher-stage12-{external,tr,en}-report.json` ve kendi ayar
  görüntülerimiz `.build/switcher-stage12-images/` içindedir.
- Kapsam: yerel AppKit olayları ve native kontroller; gerçek HID Option/Tab,
  gerçek Dvorak/Türkçe klavye kurulumu ve üçüncü taraf pencereye tuş teslimi
  kabulü değildir. Global harf kısayolu/tuş kaydı, yeni bağımlılık, sürüm etiketi
  veya GitHub Release oluşturulmadı. Sürüm **0.1.5 / build 8** korundu.

## On üçüncü aşama: imlecin pencereyi takip etmesi — 7 Kasım 2026

- Davranış bölümünde üç bağımsız seçim vardır: kapalı (eski kurulumlarda da
  varsayılan), her başarılı geçişte, yalnız imleç hedef pencereden farklı
  ekrandaysa. Global tercih panel açılırken yakalanır; panel kapanırken
  kaybolmaz ve modelin sonraki tercih okumasıyla değiştirilmez. Tools tablo
  odağı da aynı model üzerinden o andaki tercihi kullanır.
- Katalogdaki eski çerçeve veya arka plan sekmesinin olmayan fiziksel kimliği
  kullanılmaz. `WindowCatalog.focusDestination` önce süreç başlangıcını ve
  eylem kaydını doğrular, öndeki uygulamanın gerçek AXFocusedWindow / AXWindow
  kökünü okur. Normal hedefte tam WindowServer kimliği, sekmede seçili düğmenin
  güncel grup kökü eşleşmelidir. Çerçeve yalnız bu PID/ID'nin gerçek görünür
  WindowServer satırından gelir. Penceresiz uygulama açıldığında aynı uygulamanın
  yeni gerçek odaktaki penceresi okunabilir; bu özel yeniden açma yolu bu
  aşamada ayrı canlı kabul edilmiş değildir. Kimlik yoksa tahmin yapılmaz.
- Taşımadan hemen önce öndeki süreç/başlangıcı, görünür fiziksel pencere ve aynı
  katmandaki sıra yeniden kontrol edilir. Ekranlar `CGDisplayBounds`, imleç
  `CGEvent.location`, pencere `CGWindowList` koordinatlarıyla aynı uzayda
  hesaplanır; Cocoa Y dönüşümü karıştırılmaz. Kısmen ekran dışındaki pencerede
  görünür bölümün ortası seçilir. Negatif/üst ekran koordinatları, ekranlar
  arası pencere, boş/sıfır/sonlu olmayan geometri ve aynalanmış ekran belirsizliği
  saf geometri testlerindedir.
- İmleç konumu ve CoreGraphics hareket/sürükleme/tıklama/kaydırma/keydown
  sayaçları istek başında alınır. Yeni giriş, basılı fare düğmesi veya konum
  değişimi otomatik taşımayı keser; kullanıcı imleci aynı noktaya geri getirse
  bile sayaç farkı korunur. Sürekli event tap, harf kaydı, sentetik tıklama veya
  mouse-up gönderilmez. Kapalı seçenekte imleç ve ek odak geometrisi okunmaz.
- Eylem başarısızsa, görev iptal edilmişse, model durmuşsa veya daha yeni odak
  isteği başlamışsa eski sonuç imleci taşıyamaz ve yeni hata durumunu ezemez.
  WindowServer henüz hazır değilse en fazla sekiz salt okuma/25 ms bekleme
  turu vardır; başarılı taşıma tekrar edilmez. API reddi ya da bilinmeyen
  geometri başarılı pencere odağını hataya çevirmez. Bu, bütün bağımsız katalog
  örnekleri arasında genel bir odak yarışı çözümü iddiası değildir.
- İlk canlı koşuda aynı ekrandaki “her geçişte” kontrolü taşımayı görmedi;
  nedeni kesinleştirilmedi. Sahipli pencere sırası, hedef/öndeki PID, sayaçlar
  ve nokta için tek kayıtlı DEBUG tanısı eklendi. Ardından gerçek taşıma geçti.
  Hazır-değil ile kullanıcı girişinden vazgeçme ayrıca ayrıldı; birim testinde
  iki hazır-değil yanıtından sonra yalnız bir başarılı taşıma doğrulandı.
- Sekiz yeni Core testi geometri/tercih/giriş denetimini, on yeni App testi
  varsayılan kapalı maliyeti, taze hedef, hata/iptal, eski istek, durdurma,
  sınırlı metadata tekrarı, hazır-değil tekrarı, API reddi ve tercih yakalamasını
  kapsar. Native radyo düğmelerinde üç seçenek 520/760 pt'de gerçekten seçilip
  kaydedilir; denetleyici yakalanmış tercihi kapandıktan sonra modele iletir.
- Ayrı AppKit fixture'da gerçek iki bağlı ekran: farklı ekrana geçişte imleç
  hedefin ortasına geldi; kapalıyken ve aynı ekran koşulunda yerinde kaldı;
  her geçişte aynı ekranda da taşındı. Küçültülmüş hedef geri getirildiğinde ve
  başka Space'teki arka plan sekmesi seçildiğinde doğru fiziksel pencereye
  taşındı. Yanlış arka plan kardeş pencere odak hedefi olarak kabul edilmedi.
  İçerikte tıklama olmadı. Deneme sonunda özgün imleç konumu geri yüklendi;
  gerçek cihazla elle hareket/tıklama kabulü yerine bu programatik warp ve
  giriş-sayacı testleri kullanılmış değildir.
- Türkçe tam koşuda önceki Space/lifecycle fixture'larında başlangıç yarışı
  görüldü, İngilizce temizdi. Space fixture'ı artık üyelik gerçekten görünür
  olana kadar referans değer almaz. Lifecycle producer Windows menüsünden
  çıkarılır, bırakılan pencerenin weak başvurusu her AppKit turundan sonra
  yayımlanır; nesnenin gerçekten bırakılması ve fiziksel yüzeyin yok olması
  WindowServer yok etme olayı kabulünden ayrı beklenir. Önceki raporlar
  `.build/switcher-stage13-before-readiness-{tr,en}.json` içindedir. Sonraki iki
  dilde bu kontroller de geçti; ürünün bütün üçüncü taraf yaşam döngüleri
  tamamlanmış sayılmaz.
- Kapsam: kendi iki ekranımız, kendi ayrı AppKit pencerelerimiz, yerel native
  tercihler ve sahte taşıyıcıyla giriş/iptal testleri. Fiziksel klavye/fare,
  VoiceOver, hotplug ve farklı üçüncü taraf uygulamalar ayrıca kabul edilecek.
  Sürüm **0.1.5 / build 8** korundu; yeni sürüm etiketi veya GitHub Release yok.
- Son `swift test`: **1.320 vaka** (Core 896, App 47, AI 22, SSH 355),
  4 isteğe bağlı atlama, 0 test hatası ve 0 derleyici uyarısı. Yerelleştirme
  **4201 anahtar**, 0 eksik İngilizce ve 0 biçim uyuşmazlığı; kaydedicide
  9 anahtar ve 0 eksik Türkçe. Türkçe/İngilizce native denetim **900 kontrol**
  (dil başına 450), dış süreç denetimi **121 kontrol** ile geçti. İki dilde
  dar ayar görünümü görsel olarak incelendi. Debug paket/imza ve Release
  derlemesi geçti; son Release **99,60 saniye** sürdü. Üretim preflight'ında
  AX/SCK true ve AppState başlamamıştı.
- Kaynak/rapor/log/executable SHA-256 özeti
  `.build/switcher-stage13-evidence.json`, sabit rapor kopyaları
  `.build/switcher-stage13-{external,tr,en}-report.json`, ayar görüntüleri
  `.build/switcher-stage13-images/` içindedir. Son loglar
  `.build/switcher-stage13-{full-tests,bundle,external,runtime,localizations,release-build}.log`
  dosyalarında korunur. Bu sayılar tam AltTab eşdeğerliği anlamına gelmez.

## On dördüncü aşama: trackpad yönü, haptik ve hareket sahipliği — 7 Kasım 2026

- Trackpad bölümüne yatay/dikey yön ve seçim değiştiğinde isteğe bağlı haptik
  eklendi. Eski `switcher.gestureFingers` 3/4 kayıtları korunur; varsayılan
  hareket kapalı, eski etkin tercihte yön yatay ve yeni haptik kapalıdır.
  Okuma yeni kayıt yazmaz. Native radyo grupları ve toggle, TR/EN açıklamalar,
  desteklenmeyen API durumunda kapalı kontroller kullanılır. Sistem Space/
  Mission Control hareketleri bastırılmaz; aynı hareketin sistem ayarındaki
  çakışması kullanıcıya açıklanır.
- Yatay hareket pencereler, dikey hareket mevcut kart satırları arasında gezinir.
  Eksik satır ve satır sonu mevcut ok/Vim geometrisini kullanır. İlk eşik,
  değiştirici basılmasa da öndeki pencereden sonraki/önceki MRU hedefi seçer;
  yalnız paneli açıp aynı ön pencereyi tekrar seçme sorunu düzeltildi. Panel
  ipucu parmakları kaldırarak seçmeyi açıklar. Bekleyen adımlar taze listeye
  sırasıyla uygulanır. Seçim ancak son parmak ayrılınca onaylanır; kullanıcı
  arama başlattıysa klavye bırakma davranışıyla aynı biçimde panel açık kalır.
  Yazılmakta olan sorgu parmak bırakmayla erken onaylanmaz.
- Önceki adapter null temas tamponunu boş kareden ayırmıyor ve gerçek son
  parmak kalkışını kaçırabiliyordu. `TrackpadContactDecoder` sıfır teması `[]`,
  okunamayan kareyi `nil` olarak ayırır. Multitouch ABI'sinde make-touch 3,
  touching 4, break-touch 5'tir; eski 4/5 filtresi ayrılan parmağı sayıyordu.
  Yeni filtre 3/4'tür. 96 bayt stride, path kimliği 16, state 20, XY 32/36
  senkron ve hizasız güvenli okuma ile kopyalanır; ham bellek ana kuyruğa
  gönderilmez. 0–10 temas sınırı ve bilinmeyen state reddi vardır. Bu özel
  ABI'nin bu macOS/cihaz birleşiminde donanım kabulü yapılmış değildir.
- Saf `SwitcherGestureTracker` cihaz ve temas kimliğiyle çalışır. Yapılandırma
  sonrası önce bütün parmakların kalkması gerekir; hareket ortasında açılan
  tercihler aniden panel açmaz. İki trackpad'in temasları birleşmez. Parmağın
  yerine yenisi gelirse, fazla parmak eklenirse, eksik parmak yeniden katılırsa,
  baskın çapraz hareket veya geçersiz/sonlu olmayan koordinat varsa hareket
  iptal edilir. Kısmi kalkış gezinmeyi dondurur, kalan parmağın konumu yüzünden
  seçim sıçramaz. Eşik artığı ve yön değiştirme korunur; tek karedeki adımlar
  sınırlı tek olayda aktarılır, sınırsız `while` döngüsü yoktur.
- Callback aktarımında tek kilit tanıyıcıyı ve ana kuyruğa ekleme sırasını korur.
  Yapılandırma nesli, stop/ayar değişikliğinden önce kuyruğa alınmış olayları
  düşürür. `MTDeviceCreateList` sonucu cihazlar kayıttayken tutulur ve unregister/
  stop sonrasında bırakılır. Eksik sembol özelliği kullanılamaz yapar.
- Denetleyici hareketin açtığı panel oturumunu sahiplenir. Bir klavye panelinin
  üzerinden başlayan hareket o paneli gezemez veya bırakınca seçemez. Escape
  aynı basılı hareketin sonraki kareleriyle paneli yeniden açtırmaz. İptal,
  ayar değişikliği, kaydedici, modül durdurma ve öndeki uygulama istisnasında
  hareket seçimi onaylanmaz. Global geçiş kapalıyken/kaydedici açıkken/istisna
  eşleşiyorken cihaz kaydı durdurulur; eski callback yolunun bu koşulları
  atlaması giderildi. Yalnız kendi hareketinin seçim değişiminde AppKit
  `.alignment` haptik isteği verilir; klavye/hover için yeni haptik eklenmez.
- 12 yeni Core testi varsayılan/uyumluluk, iki eksen/3–4 parmak, eşik artığı,
  ters yön, kısmi kalkış, temas değişimi, iki cihaz, çapraz eksen, geçersiz veri
  ve sınırlı büyük hareketi kapsar. Altı App testi null/boş tampon farkı,
  make/touch/break durumları, hizasız okuma, bilinmeyen ABI, sıralı aktarım ve
  stop/yeniden yapılandırma sonrası kuyruğun iptalini denetler.
- Native denetimde kopyalanmış temas değerleri üretimdeki relay üzerinden gerçek
  üç panel stilini sürer; 3 ve 4 parmak, yatay pencere/dikey satır/ters yön,
  öndeki pencereyi atlama, son parmakla tek odak, aramadayken bırakınca açık
  kalma, Escape, klavye paneli sahipliği,
  haptik isteği sayısı, kapalı haptikle gezinme, geçersiz kare, global kapatma,
  kaydedici, uygulama istisnası ve kaynak bırakma denetlenir. Haptik performer
  sayıcıdır; katalog yalnız sahipli sahte satırları bilir. Bu bölüm gerçek
  cihaz callback'i, hissedilen titreşim veya dış uygulama odağı kanıtı değildir.
- İlk dar native koşuda kapalı radyo durumları yalnız formal
  `NSAccessibilityProtocol` ile okunmuş ve beş informal SwiftUI radyo sarmalayıcısı
  kaçırılmıştı. Kontrol başarısız sayıldı; önceki raporlar
  `.build/switcher-stage14-before-enabled-inspection-{tr,en}.json` içinde korunur.
  Denetim artık informal etkinlik getter’ı / `AXEnabled` yolunu da okur, hem etkin hem kapalı
  altı kontrolü ayrı doğrular ve depolama güncellemesinden sonra render'ı bekler.
- Araştırma: AltTab v11.10.1 [trackpad adapter'ı](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/events/TrackpadEvents.swift)
  ve [tetik çekirdeği](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/events/GestureTriggerKernel.swift)
  davranış için incelendi; güncel AltTab NSEvent/tap yolu ile bu projenin mevcut
  isteğe bağlı MultitouchSupport yolu aynı adapter değildir. ABI durumları
  [touchdevice başlığı](https://github.com/asmagill/hs._asm.undocumented.touchdevice/blob/master/MultitouchSupport.h)
  ve [twongseng başlığı](https://github.com/mkalten/twongseng/blob/master/multitouch.h)
  ile karşılaştırıldı. Haptik API [Apple NSHapticFeedbackManager](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager)
  sözleşmesidir. Referanslar `.build/research/alttab-2026-11-07/` içindedir;
  upstream uygulama kodu ürüne kopyalanmadı. Kaynak incelemesi, temas-fixture
  denetimi ve fiziksel donanım kabulü ayrı tutulur.
- Son `swift test`: **1.338 vaka** (Core 908, App 53, AI 22, SSH 355),
  4 isteğe bağlı atlama, 0 test hatası ve 0 derleyici uyarısı. Yerelleştirme
  **4207 anahtar**, 0 eksik İngilizce ve 0 biçim uyuşmazlığı; kaydedicide
  9 anahtar ve 0 eksik Türkçe. Son TR/EN native koşusu **1.066 kontrol**
  (dil başına 533; 83 hareket kontrolü), ayrı süreç denetimi **121 kontrol**
  ile geçti. Dar Türkçe/İngilizce ayar render'ları görsel olarak incelendi.
- Debug paket/imza ve son Release derlemesi geçti; Release **108,92 saniye**
  sürdü. Kaynak SHA-256 değerleri son doğrulama boyunca sabit kaldı. Önceki
  530 kontrol/dil ve Release koşusu başarılıydı; son arama-tutma düzeltmesi
  sonrasında tam test/native/Release tekrarlandı. Önceki sonuçlar
  `.build/switcher-stage14-before-search-retention-*` dosyalarında ayrıdır.
  Üretim preflight'ında AX/SCK true ve AppState başlamamıştı.
- Kanıt özeti `.build/switcher-stage14-evidence.json`, sabit rapor kopyaları
  `.build/switcher-stage14-{external,tr,en}-report.json`, sekiz ayar görüntüsü
  `.build/switcher-stage14-images/` içindedir. Loglar
  `.build/switcher-stage14-{full-tests,bundle,gesture,runtime,external,localizations,release-build}.log`
  dosyalarındadır. `gesture` logu arama-tutma düzeltmesinden önceki dar 80
  kontrol/dil koşusudur; güncel kapsam tam `runtime` raporundadır.
  Sürüm **0.1.5 / build 8** korundu; tam AltTab eşdeğerliği, fiziksel trackpad
  veya hissedilen haptik kabulü iddiası yoktur.

## On beşinci aşama: uygulama Dock rozetleri — 7 Kasım 2026

- Üç kart stiline Dock bildirim rozeti eklendi. Genel varsayılan açık;
  her kısayolda açık/kapalı/geneli izle seçilebilir. Eski kısayollarda yeni
  optional alan nil kalır, JSON kimlik/filtre/diğer görünüm seçenekleri korunur.
  Tercih panel açılırken alınır; kapalı kısayolda Dock okuma işçisi başlatılmaz.
  Durum simgesi ve Space rozeti bağımsız kalır.
- Rozet uygulamanın Dock etiketidir. Aynı uygulamanın iki penceresi veya sekmesi
  aynı etiketi paylaşır; pencereye özel okunmamış sayısı uydurulmaz. Sayı, `!`,
  `0`, yazı ve birleşik emoji desteklenir. Uzun etiket görselde ilk üç grapheme
  ve üç noktayla kısalır; tam metin yardım ve ana kartın erişilebilirlik
  değerindedir. Çocuk rozet ayrı VoiceOver öğesi değildir. Boş/yalnız boşluk,
  kontrol/bidi yönlendirme karakteri ve 256 UTF-16 birimini aşan veri reddedilir;
  ZWJ/ZWNJ birleşimleri korunur. İlk birim koşusu birleşik emoji reddini buldu;
  kontrol filtresi bu iki anlamlı birleştiriciyi koruyacak biçimde düzeltildi.
- `DockApplicationBadgeReader` actor'ü AX okumalarını ana iş parçacığından
  ayırır. Yalnız mevcut panelde istenen uygulamalar alınır; aynı uygulamanın
  çok penceresi isteği çoğaltmaz. Kimlik pozitif PID, bilinen süreç başlangıcı
  ve yerel `.app` URL'sidir. Başlangıçta ve okumadan sonra gerçek çalışan
  uygulama kimliği doğrulanır. Dock öğeleri uygulama adına/bundle önekine göre
  eşlenmez; standart dosya yolu ve actor içinde çözülen symlink yolu eşleşir.
  Farklı kurulumların aynı adı birbirine rozet taşımaz.
- Dock her turda tekrar bulunur; birden çok çalışan Dock kimliği varsa tahmin
  yapılmaz. Uygulama/Dock AX nesnesi kalıcı tutulmaz;
  işlem sonunda Dock PID/başlangıcı yeniden doğrulanır. Yalnız
  `AXApplicationDockItem` + çalışan uygulama öğeleri değerlendirilir;
  `AXStatusLabel` yalnız istenmiş tam URL'lerde okunur. Başka uygulamaların
  rozet etiketleri okunmaz. Aynı URL'ye ait çelişkili Dock etiketleri (birinin
  boş olması dahil) belirsiz sayılır. Dock eylemi, tıklama, Notification Center
  veritabanı, bildirim izni isteme veya Dock tercihi yazma yoktur.
- AX mesajları 25 ms timeout kullanır; her çağrı arasında 250 ms tur bütçesi,
  en fazla 32 kök/512 Dock öğesi/256 hedef ve iptal kontrolü vardır. Bunlar
  çağrı arası bütçe/mesaj timeout'udur; işletim sistemi IPC'si için katı toplam
  gerçek-zaman garantisi değildir. Bir öğenin metadata hatası o öğeyi atlar.
  İzin/root/list/bütçe hatası veya etiketi olmayan tam sonuç eski rozeti siler;
  bilinmeyen durum sıfır bildirim gibi sunulmaz.
- Yalnız görünür HUD bir işçiyle, turdan sonra bir saniye bekleyerek yeniler.
  Kapalı panelde/prewarm'da okuma yoktur. Oturum ve işçi nesilleri eski yanıtı
  düşürür; güncel listeden çıkan veya istenmemiş uygulama sonucu kabul edilmez.
  Panel/modül/model durdurulunca önbellek temizlenir; Dock hatası pencere
  seçimini veya hata durumunu değiştirmez.
- 12 Core testi etiket/veri sınırı, Unicode/emoji, uygulama kimliği ve URL,
  süreç yeniden kullanımı, çelişkili öğeler, boş sonuç, eski tercih uyumu,
  bağımsız kısayol tercihi ve iptal edilmiş gerçek okuyucu girişini kapsar.
  Sekiz App testi ortak uygulama başına tek istek, kimliksiz hedef, eski oturum,
  kapatılmış panel, kaldırılmış hedef, boş sonuçla silme, yanlış süreç yanıtı
  ve iki işçinin birleşmesini denetler.
- Native denetim gerçek 520/760 pt ayar toggle'ını değiştirip kaydeder. Üç
  stil × açık/koyu tema, minimum %60 ölçek, sayı/metin/uzun etiket/0,
  aynı uygulama pencereleri, tam erişilebilir açıklama, boş sonuç, oturum
  tercihi, kapalı preset'te okuma yapmama ve kaynak bırakma denetlenir.
  Sağlayıcı sahipli sahte rozetlerdir; bu bölüm gerçek Dock taşıması değildir.
  Dar simge ve küçük resim görünümleri görsel olarak incelendi. Rozet beyaz
  yazı/sabit kırmızı çiftinin hesaplanmış kontrastı 6,57:1'dir; bütün arayüzün
  kontrast veya gerçek ekran okuyucu kabulü olarak kullanılmaz.
- Referans: AltTab v11.10.1
  [uygulama rozet yenilemesi](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/switcher/state/Applications.swift)
  ve [BadgeBar açıklaması](https://github.com/ahmetrende/BadgeBar#how-it-works).
  AltTab'ın bir saniyelik panel-içi AX/URL eşlemesi araştırıldı; upstream kodu
  ürüne kopyalanmadı. Araştırma girdileri
  `.build/research/alttab-2026-11-07/badges/` içindedir.
- İlk gerçek dış koşuda yeni yedi Dock kontrolü geçti; eski HUD odak/Space/
  ekran kontrollerinden 14'ü başarısızdı. Rapor/log
  `.build/switcher-stage15-first-external-{report.json,log}` olarak korunur.
  Bunun rozet okumasından kaynaklandığı kanıtlanmadı. Üretim odak kodu
  değiştirilmeden eklenen dört açık/kapalı karşılaştırma ve tam dış koşu
  132 kontrolde geçti. Odak/PID, kendi AppKit key/main durumu, hata ve katalog
  kimliği artık rapordadır. İlk hatanın nedeni kesinleşmiş/çözülmüş sayılmaz;
  tekrar üretim ve gerçek HID kabulü açık kalır. Son denetim gerçek `7` rozeti
  iki pencerede görünürken odak geçişini de ayrıca denetler.
- Kullanıcı yönlendirmesiyle kurulu AltTab 11.7.1, ARM64 dilimi ayrılarak
  REA/Ghidra'da doğrudan çözümlendi. `0x1001ebf14` gövdesi, öne getirmeden
  sonra ek bir key-window olayı gönderildiğini gösterdi. MacPocket bu adımı
  atlıyordu. Doğrulanmış PID/pencere için 256 sıfırlanmış baytlık kayda tek
  hedefli down olayı eklendi; up çifti veya global imleç hareketi yoktur.
  Nokta içerik/yeniden boyutlandırma kenarlarından uzakta `(300000,300000)`.
  Bu özel ABI'nin kanıtı ve sınırları
  [REA araştırma ekinde](research/2026-11-06-alttab-free-pro.md#kurulu-uygulamada-doğrudan-rea-incelemesi--7-kasım-2026)
  ve `.build/research/alttab-2026-11-07/rea/` içindedir.
- Düzeltmeden sonra üç ABI testi, kısa gerçek odak koşusunda **67 kontrol**
  ve tam dış koşuda **134 kontrol** geçti. Gerçek `7` Dock etiketi iki pencereye
  geldi; açık/kapalı dört odak, Space, küçültülmüş hedef, imleç ve içerikte
  tıklama/istenmeyen geometri değişimi kontrolleri de geçti. Başarısız önceki
  koşular korunur. Bu sonuç bütün üçüncü taraf/HID güvenilirliği veya tam AltTab
  eşdeğerliği değildir.
- Rozet aşamasının tam testleri **1.358 vaka / 4 isteğe bağlı atlama**, native
  TR/EN **1.190 kontrol**, yerelleştirme **4210 / 0 eksik** ve Release
  **117,96 saniye** ile key-window düzeltmesinden önce geçti. Düzeltmeden sonra
  imzalı Debug paket, üç hedefli ABI testi, 134 gerçek pencere kontrolü ve tam
  **1.361 vaka** (Core 923, App 61, AI 22, SSH 355; 4 isteğe bağlı atlama,
  0 test hatası/derleyici uyarısı) geçti. Son kaynakla yerelleştirme yeniden
  **4210 / 0 eksik / 0 biçim uyuşmazlığı**, Release derlemesi **108,84 saniye**
  ile tamamlandı. Kaynaklar önceki 134 kontrol koşusuyla aynıdır. Native
  TR/EN 1.190 kontrolünün düzeltme öncesindeki kapsamı ayrı korunur.
  Son kanıt `.build/switcher-stage15-key-fix-evidence.json`, gerçek son rapor
  `.build/switcher-stage15-key-fix-external-report.json` içindedir.
  Sürüm **0.1.5 / build 8** korundu.

## On altıncı aşama — mevcut ayar aktarımına erişim ve veri bütünlüğü

Genel **Ayarlar > Gelişmiş** aktarımı zaten `switcher.*` anahtarlarını kapsıyordu;
ilk araştırmada bu karşılık atlanmıştı. Pencere geçişi ayarlarına bu bölümü açan
bir düğme eklendi. Açıklama, aktarımın diğer MacPocket ayarlarını da içerdiğini
ve içe aktarmanın mevcut ayarları değiştirdiğini belirtir. Genel sıfırlama ve
yeniden başlatma akışı kullanılır; ikinci bir aktarım biçimi oluşturulmadı.

- İçe aktarma bütün dosyayı doğrulamadan tercihlere dokunmaz. Önceki akış,
  çözülemeyen değerleri sessizce atıp eski ayarları temizleyebiliyordu. Geçersiz
  Data/Date sarmalları, null/iç içe bozuk değerler ve boolean/kesirli sürüm
  başlıkları artık dosyanın reddedilmesine neden olur. Dosya okuma 8 MiB ile
  sınırlıdır. Dışa aktarma da aynı sınırı korur; biçim sürümü hâlâ 1'dir.
- Modern kısayol, eylem ve istisna kayıtları çözülüp doğrulanır. Eksik/tekrarlı
  kısayol kimlikleri, sınırı aşan profiller ve varsayılanlarla birleştirilince
  çakışan eylemler reddedilir. Geçerli Data baytları yeniden kodlanmaz; diğer
  eski/gelecek tercihler için kapsamlı bir scalar izin listesi uygulanmaz.
- Tek persistent-domain güncellemesi, uygulama içindeki temizle-sonra-yaz
  ara durumunu kaldırır; bu, süreçler arası kalıcı işlem garantisi değildir.
  İlgisiz anahtarlar ve dil tercihi korunur. İçe aktarılan kapalı global kısayol
  ilk açılış geçişi tarafından yeniden etkinleştirilmez.
- 12 yeni bütünlük testi ve mevcut 15 tercih testi birlikte geçti. Yalnız
  sahipli geçici dosya ve izole UserDefaults alanları kullanıldı; kullanıcının
  gerçek ayarları içe aktarılmadı veya sıfırlanmadı.
- TR/EN native denetimi **11'er kontrol / 22 toplam / 0 hata**: gerçek düğmenin
  basılması, açma eyleminden önce Gelişmiş sekmesinin seçilmesi, devre dışı düğme,
  520/760 genişlikte taşma ve sahipli dosyada gerçek yaz/oku/aktar akışı geçti.
  Açma eylemi sayaçla yakalandı; gerçek Settings sahnesi ve NSSavePanel/
  NSOpenPanel kullanılmadı. Bunlar dosya seçici veya tüm ayarlar ekranı kabulü
  sayılmaz. 520 genişlikte TR/EN görüntüleri ayrıca gözle incelendi.
- Native raporlar `.build/switcher-stage16-{tr,en}-report.json`, koşu günlükleri
  `.build/switcher-stage16-{tests,runtime,localizations}.log` içindedir.
  Yerelleştirme **4215 anahtar / 0 eksik / 0 biçim uyuşmazlığı** ile geçti.
  Uygulama sürümü **0.1.5 / build 8** korundu.
- Son tam koşu **1.373 vaka** (Core 935, App 61, AI 22, SSH 355), dört isteğe
  bağlı atlama ve sıfır test hatasıyla tamamlandı. Günlükte Contacts/CoreData
  hizmet bağlantısı tanıları vardır; test başarısızlığı veya derleyici uyarısı
  değildir. Önceki 134 gerçek pencere kontrolü odak düzeltmesine aittir;
  ayar aktarımı değişikliğinden sonra yeniden çalıştırılmış sayılmaz.
- Son Release derlemesi **124.76 saniye** ile geçti. Kaynak SHA ve günlük
  özetleri `.build/switcher-stage16-evidence.json` dosyasındadır; imzalı Debug
  paketinin sıkı imza kontrolü ve `git diff --check` temizdir.

## On yedinci aşama — çalışan uygulamaya bağlı CLI

Paketin kendi executable'ı istemci olarak kullanılabilir; ayrıca geliştirme
aracında `macpocket-probe switcher …` aynı bağlantıyı kullanır:

```sh
app="/Applications/MacPocket.app/Contents/MacOS/MacPocket"
"$app" --switcher list
"$app" --switcher list --detailed
"$app" --switcher focus '<list çıktısındaki id>'
"$app" --switcher focus --mru 2
"$app" --switcher show 1
"$app" --switcher hide
"$app" --switcher status
```

Geliştirme paketi için ilk satırdaki yol `.build/MacPocket.app/Contents/MacOS/MacPocket`
olarak değiştirilebilir. Bu geliştirmede `/Applications` paketine kurulum yapılmadı.

- `list`, mevcut kart/tablo aramasından ve kısayol filtrelerinden bağımsız gerçek
  pencereleri, aynı kataloğun MRU sırasıyla döndürür; penceresiz uygulamalar
  listelenmez. `id`, sayısal `windowID`, başlık ve **1'den başlayan** MRU indeksi
  vardır. Yerel sekmelerin opak `id` değeri korunur.
- `--detailed`, PID/uygulama/bundle, durumlar, ekran, bilinen/bilinmeyen Space
  kimlikleri ve sıraları, odak tarihi, gözlenen oluşturma sırası, yerel sekme
  bilgisi ve sonlu `[x, y, genişlik, yükseklik]` geometrisini CoreGraphics'in
  sol üst başlangıçlı global koordinatlarında ekler. Bilinmeyen değerler
  uydurulmaz. Raporun izin,
  kısmi katalog ve Space metadata kapsamı ayrıca döner. Erişilebilirlik yokken
  sınırlı liste alınabilir; odaklama açık izin hatası verir ve izin istemez.
- `focus`, taze katalogdaki opak ID veya sayısal pencere kimliğini kullanır.
  `--mru` güncel listedeki **1 tabanlı** sırayı kullanır; çağrılar arasında sıra
  değişebildiğinden belirli hedef için `id` tercih edilir. Hedef yoksa başka
  pencereye düşülmez. Açık seçim oturumu iptal edilip mevcut odak yolu çağrılır.
- `show [1…9]`, kayıtlı profilin kart panelini açar. Profil numarası da **1
  tabanlıdır**; kayıtlı olmayan profil, kapalı modül veya tuş kaydı sırasında
  hata döner. Aynı profilin tekrarlanan `show` çağrısı seçimi ilerletmez.
  `opening` isteğin kabul edildiğini belirtir, içerik taramasının bittiğini
  garanti etmez. `hide` seçim yapmadan kapatır; `status.panelVisible` gerçek
  AppKit panelinin o anki görünürlüğüdür. Bu komutlar global kısayol ayarını
  değiştirmez ve modülü kendiliğinden etkinleştirmez.
- Çıktı sürüm 1 JSON'dur. Başarıda çıkış **0**, sunucunun bildirdiği hatada **2**,
  argüman/bağlantı/yanıt hatasında **1** döner. `errorCode` makine için sabittir,
  `message` yerelleştirilebilir. Her yanıtta istek UUID'si doğrulanır.
- Kullanıcı/oturum kapsamındaki CFMessagePort, arka plan seri kuyruğunda çalışır;
  ana aktör asenkron pencere işlerini sürdürebilir. Ağ portu, dosya soketi veya
  shell komutu açılmaz. İstek 4 KiB, yanıt 4 MiB sınırındadır; büyük çıktı sessizce
  kesilmez, hata döner. Son tarih denetimi ve iptal geç kalmış odağı önler.
  Zaman aşımı yine de gerçekleşmiş bir eylemi geri alamaz; sonuç doğrulanamadı
  mesajı döner, otomatik tekrar yapılmaz. Uygulama açık değilse açık hata verilir.
  Aynı oturumdaki yerel süreçler bu arayüze bağlanabilir; uygulama adına ayrıca
  yetkilendirme sınırı sunulmaz.
- Eski `macpocket-probe windows/focus/thumbnail` doğrudan geliştirme komutları
  korunur. Yeni `switcher` komutları çalışan uygulamanın izin ve oturumunu
  kullanır. AltTab'ın wire biçimi veya sıfır tabanlı profil sözleşmesi kopyalanmadı.
  İncelenen referans [AltTab CLI kaynağı](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/events/CliEvents.swift),
  kullanılan API [Apple CFMessagePortSetDispatchQueue](https://developer.apple.com/documentation/corefoundation/cfmessageportsetdispatchqueue(_:_:))
  belgesindedir; ürün kaynaklarına upstream kodu alınmadı.

17 hedefli test (10 Core, 7 App) geçti. Yerel native denetimde **16 TR + 16 EN**
kontrol geçti: gerçek Mach iletişimi, gerçek kart paneli aç/kapat/görünürlük,
tekrarlanan show, açıkken düzenlenen profilin yeniden uygulanması, profil reddi,
modül kapatma ve ayrı süreçte paket executable'ı
doğrulandı. Bu koşuda odak hedefi **sahte katalogdur**; üçüncü taraf pencereye
odak kabulü veya fiziksel klavye testi değildir. Önceki 134 sahipli gerçek
pencere kontrolü mevcut odak yolunun önceki kaydıdır, yeni CLI üzerinden
çalıştırılmış sayılmaz. Kullanıcı ayarları değiştirilmedi; izole audit paketi,
geçici UserDefaults alanı ve sahipli fixture kullanıldı.

Raporlar `.build/switcher-stage17-{tr,en}-report.json`, günlükler
`.build/switcher-stage17-{tests,runtime,bundle,localizations}.log` içindedir.
Yerelleştirme **4224 anahtar / 0 eksik / 0 biçim uyuşmazlığı** ile geçti;
sürüm **0.1.5 / build 8** korundu.

Ara native koşuda yalnız denetimin alt süreç bekleyicisi takıldı: sahipli çocuk
süreç artık görünmezken `Process.waitUntilExit` dönmedi. Örnek yığın
`.build/switcher-stage17-hung-audit.sample.txt` içinde korundu. Sahipli denetim
süreci durdurulup uygulamanın mevcut continuation/sonlandırma handler tabanlı
`BoundedProcess` çalıştırıcısı kullanıldı; son 32 kontrol bundan sonra geçti.
Bu kayıt üretim CLI veya üçüncü taraf pencere odağı hatası olarak sunulmaz.

Son kaynakla tam test koşusu **1.390 vaka** (Core 945, App 68, AI 22, SSH 355),
dört isteğe bağlı atlama ve sıfır test hatasıyla tamamlandı. Sıkı paket imza
kontrolü, yerelleştirme ve `git diff --check` geçti. Kaynak SHA'ları ve son
kanıt özeti `.build/switcher-stage17-evidence.json` dosyasındadır.
Son Release derlemesi **111.06 saniye** ile tamamlandı.

## On sekizinci aşama — açma ve basılı tutma değiştiricilerini ayırma

Kısayol profilindeki **Basılı tutulan tuşlar** bölümünde, açma birleşimindeki
⌃/⌥/⌘ tuşlarından hangilerinin bırakma davranışını yöneteceği seçilir.
Örneğin açma birleşimi **⌃⌥Tab**, tutulan küme **yalnız ⌥** olduğunda, ⌃ hâlâ
basılı olsa da ⌥ bırakılınca seçilir. ⌃ bırakılıp ⌥ tutulmaya devam ederse
panel açık kalır; ⌥Tab ileri, ⌥Shift+Tab geri gezinir. Bu, herhangi bir normal
harfi basılı tutma veya değiştiricisiz global kısayol desteği değildir.

- `SwitcherShortcut.holdModifiers` isteğe bağlıdır. Alan yoksa **Açma kısayolunu
  izle** uygulanır; önceki tüm açma değiştiricilerinin bırakılmasını bekleyen
  davranış korunur. Açık küme gelecekte açma birleşimine yeni tuş eklenirse
  kimliğini korur. Birden fazla tutulan değiştirici seçilirse hepsinin
  bırakılması beklenir. İleri/geri Shift kuralı değişmedi.
- Seçenekler yalnız boş olmayan alt kümelerdir. Açma birleşimi dışındaki veya
  bilinmeyen değiştiriciler reddedilir. Açma kısayolu yeniden kaydedildiğinde
  artık mevcut olmayan tutma kümesi varsayılana döner. Profil başına mevcut
  seç/açık tut/ara bırakma tercihi kullanılır; oturum ipucu gerçek tutulan
  kümeyi gösterir. Kayıt sırasında bu ayarlar kilitlidir.
- Kalıcılık ve genel ayar aktarımı alanı korur; alanı içermeyen eski JSON
  kayıtları çalışır. Bozuk tutma kümesi içe aktarma doğrulamasından geçmez ve
  mevcut tercihlere dokunulmaz. Arşiv ve uygulama sürümü değiştirilmedi.
- Yeni bir global klavye dinleyicisi eklenmedi. Carbon aynı açma birleşimini
  kaydeder; tutma kümesi oturumdaki yerel tuşlar ve mevcut değiştirici
  zamanlayıcısıyla izlenir. ⌘Tab hâlâ doğrulamada reddedilir.
- Yedi yeni Core testi; eski alan yokluğu, tüm geçerli/geçersiz alt kümeler,
  saklama/JSON, açma tuşu düzenleme, eylem önceliği ve aktarımda bütünlüğü kapsar.
  Mevcut ilgili testlerle hedefli koşu **41 test / 0 hata** ile geçti.
- Native TR/EN **43'er / 86 kontrol / 0 hata**: üç gerçek AppKit kart stili,
  ileri/geri yerel tuşlar, açmaya ait ek değiştiricinin bırakılması, tutulan
  değiştiricinin diğer tuş hâlâ basılıyken bırakılması, tek seçim, eski davranış,
  gecikmeli/soğuk katalogda hızlı bırakma, arama/açık tut ve Escape denetlendi.
  Katalog ve odak hedefi sahte fixture'dır; fiziksel klavye/global Carbon
  teslimi veya üçüncü taraf pencere odağı kabulü değildir.
- Gerçek ayar kontrolü 520/760 pt'de açıldı; native radyo seçimi, varsayılana
  dönüş ve açık bölümde kayıt kilidi denetlendi. SwiftUI'nin sanal AX disclosure
  düğümüne in-process press durum değiştirmediğinden, sahibi olduğumuz pencereye
  AppKit fare olayları gönderildi. Gruplu Form'un iki genişlikte değişen kenar
  boşluğu görüntüden ölçülerek test tıklamaları düzeltildi. Bu, VoiceOver kabulü
  veya ürünün disclosure davranışında saptanmış bir hata olarak sunulmaz.
  Türkçe/İngilizce geniş ve dar görüntüler gözle incelendi; ayrı ölçülen
  taşma kontrolü sanal AX düğümlerinin tüm geometrisini kapsamaz.
- Önceki CLI native denetimi de **16 TR + 16 EN / 32 kontrol / 0 hata** ile
  yeniden geçti. Tam son koşu **1.397 vaka** (Core 952, App 68, AI 22, SSH 355),
  dört isteğe bağlı atlama ve sıfır test hatasıyla tamamlandı.
  Yerelleştirme **4231 anahtar / 0 eksik / 0 biçim uyuşmazlığı** ile geçti.

Native raporlar `.build/switcher-stage18-{tr,en}-report.json`, CLI regresyonu
`.build/switcher-stage18-cli-{tr,en}-report.json`, son kaynak SHA'ları ve kanıt
özeti `.build/switcher-stage18-evidence.json` içindedir. Uygulama sürümü
**0.1.5 / build 8** korundu. Tam AltTab eşdeğerliği iddiası yoktur.
Son Release derlemesi **123.34 saniye** ile geçti; sıkı paket imza
kontrolü ve `git diff --check` temizdir.

## On dokuzuncu aşama — gerçek CLI odağı ve gizli uygulama yarışı

Paket içindeki gerçek `--switcher` istemcisi, ayrı süreçten üretim
CFMessagePort dinleyicisine ve `SwitcherCommandService` yoluna bağlandı.
Katalog PID ve kanonik uygulama yolu ile ayrı, sahibi olduğumuz AppKit
fixture'ına sınırlandı; pencere bilgisi ve odağı gerçek AX/WindowServer'dan
geldi. Normal modelin odak/yaşam döngüsü gözlem kiraları açıldı; global
kısayol kaydı, normal AppState veya kullanıcı tercihleri başlatılmadı.

- Güncel imzalı paketin **doğrudan shell** preflight'ı AX/SCK izinlerini false,
  **Launch Services** ile başlatılan aynı paketin preflight'ı true gördü.
  Bu makinede çalıştırma bağlamları farklı sonuç verdi; hiçbir izin istemi veya
  TCC değişikliği yapılmadı. Dosyalar `.build/switcher-stage19-{permissions,ls-permissions}.json`
  içinde ayrıdır. Gerçek denetim sunucusu Launch Services üzerinden açıldı.
- İlk CLI koşusu 28 kontrolde kapalı hedefin hata sınıflaması nedeniyle kaldı:
  model gözlem kiraları açılmadan çalıştırılmıştı; hedef artık görünmezken
  CLI `focus-failed` döndürdü, diğer pencereye geçmedi. Son kurulum normal
  model kiralarını kullanır; hedefin sahibinin kaydından ve WindowServer'dan
  kalktığı ayrıca beklenir. İlk rapor/log korunur.
- İkinci koşu gerçek bir üretim hatasını gösterdi. Gizli uygulamadan B
  penceresine geçişte CLI `focused` döndü ve AX odak kimliği B oldu, ancak
  öndeki süreç önceki uygulama olarak kaldı. Sonraki hide kontrolü de bu
  yanlış başlangıç durumundan etkilendi. Önceki API kabulü/AXRaise başarısı
  gerçek ön plan odağını doğrulamıyordu.
- `WindowCatalog.focus` somut pencerelerde artık başarı/MRU kaydından önce
  gerçek hedefi doğrular: doğru öndeki süreç, AX odak kimliği, yaşayan hedef
  ve WindowServer'da görünür fiziksel pencere. Native sekmeler seçili fiziksel
  pencere üzerinden çözülür. CG kimliği olmayan AX pencereler için tam AX
  nesne eşitliği ve öndeki süreç kontrolü kodda vardır; bu özel fallback'in
  canlı kabulü bu koşunun kapsamı değildir. Penceresiz uygulamayı yeniden
  açma yolu önceki istek kabulü davranışını korur.
- Kontrol sınırlıdır: en fazla 24 örnek ve örnekler arasında 25 ms; AX mesaj
  süreleri ayrıca geçerlidir, dolayısıyla bu bir 600 ms toplam süre garantisi
  değildir. Başlangıçta gizli olan uygulamada odak gelmezse yalnız bir kez,
  taze hedef/başlatılma kimliği ve iptal kontrolleriyle etkinleştirme, hedefli
  key olayı ve raise tekrarlanır. Pencere içine tıklama veya imleç taşıma
  eklenmedi. Doğrulanamayan sonuç hata döner; MRU'ya başarı yazılmaz.
- Son CLI koşusu **36 kontrol / 0 hata**: aynı başlıklı iki pencereyi ID ile
  ayırma, sade/ayrıntılı liste, sayısal/opak ID ve MRU 2, küçültülmüş hedef,
  dört gizle/geri aç çevrimi, key/main/ön plan eşleşmesi, gerçek panel,
  tekrarlanan show, seçili diğer kartı seçmeden hide, açık panelden açık hedefe
  focus, bulunmayan/eski ID ve geçersiz profil/indeks, geometri/içerik tıklaması
  koruması ve tüm model/controller kiralarının kapanması geçti. Gizli uygulama
  çevrimlerinin her birinde son gerçek durum doğrulandı; iç retry dalının
  kaç kez kullanıldığına ilişkin ayrı sayaç tutulmadı.
- Aynı son kaynakla tam dış koşu **134 kontrol / 0 hata** ile geçti; gerçek
  yakalama, Space/sekme/ekran, rozet ve imleç kapsamları önceki koşuyla aynı
  denetim yolundan yeniden çalıştırıldı. Toplam 170 kontrol farklı kapsamları
  içerir; hepsi tek bir fiziksel klavye kabulü gibi yorumlanmamalıdır.
- Tam testler **1.397 vaka** (Core 952, App 68, AI 22, SSH 355), dört isteğe
  bağlı atlama ve sıfır test hatasıyla geçti. Yerelleştirme **4231 / 0 eksik /
  0 biçim uyuşmazlığı**. Sahipli AppKit kabulü üçüncü taraf uygulama, gerçek
  HID, VoiceOver veya genel AltTab eşdeğerliği sayılmaz.

İlk/ikinci ara koşular `.build/switcher-stage19-{first,second}-external-report.json`,
son CLI `.build/switcher-stage19-cli-real-report.json`, tam dış koşu
`.build/switcher-stage19-full-external-report.json` içindedir. Son kaynak SHA,
günlük ve kapsam özeti `.build/switcher-stage19-evidence.json` dosyasındadır.
Sürüm **0.1.5 / build 8** korundu. Release derlemesi **113.14 saniye** ile
geçti; sıkı paket imzası ve `git diff --check` temizdir.

## Yirminci aşama — giriş engeli tanısı ve klavye oturumunu devralma

Saf ⌘Tab araştırmasında olay filtresi oluşturulmasına rağmen hiç callback
gelmediği görüldü. Bu sonuç desteklenmediği anlamına gelmez: bu Mac'te
`IsSecureEventInputEnabled()` true, geçerli konsol kullanıcısının
`kCGSSessionSecureInputPID` değeri **751 / Google Chrome** olarak okundu.
Güvenli giriş açıkken üretilmiş tuşlardan genel klavye desteği sonucu çıkarılmaz.
AltTab'ın kaynakta kullandığı Carbon kaydı ve yerel sembolik kısayol 1/2'yi
kapatma yolu ayrıca incelendi. Yerel kısayol değişikliği uygulama kapanınca
kalıcı olabildiği için geri yükleme güvencesi olmadan ürüne eklenmedi.
**Saf ⌘Tab hâlâ reddedilir; bu aşama onun kabulü değildir.**

- `SecureKeyboardInputStatus` yalnız güvenli giriş durumunu ve mevcut konsol
  kullanıcısının sahip PID'sini okur. Parola/AX alanları okunmaz; güvenli giriş
  kapatılmaz. Bozuk, başka kullanıcıya ait veya çelişkili sahip kaydı bir
  uygulamaya atanmaz. Pencere Geçişi sayfası açıkken durum saniyede bir
  yenilenir; görünümün görevi iptal edildiğinde yenileme biter. Uyarı TR/EN'dir.
- Kontrollü ⌘Tab denemesi artık bu engeli ilk adımda bildirir ve böyle bir
  durumda tuş üretmez. Önceki denemenin kendi Command durumunu temizleme
  seçeneği ayrıdır. `nativeSettingsChanged` ve fiziksel girdi kabulü ayrı tutulur.
- Gerçek bir oturum hatası giderildi: ayarlardan/CLI'den açılan mevcut panelde
  aynı profilin kısayoluna basınca yalnız geziniliyor, basılı tuş sahipliği
  alınmıyordu. Artık klavye aynı paneli devralır, bir adım ilerler ve profilin
  seç/açık tut/ara bırakma davranışını uygular. Tarama sürerken hızlı bırakma
  taze sonuç üzerindeki sıraya alınmış adımı bir kez seçer.
- Trackpad'den klavyeye devralmada profilin özgün bırakma davranışı geri gelir;
  eski hareketin geç gelen iptal/bırakması klavye panelini kapatmaz veya seçmez.
  Oturumun profil/çözümlenmiş görünümü değişmişse yeni ayarlar yeni oturumla
  uygulanır; eski kapsam üzerinde devam edilmez.
- Salt okunur tanı için **5 Core testi** geçti. Gerçek yerel AppKit panellerinde
  TR/EN basılı tuş denetimi **55 × 2**, hareket denetimi **95 × 2**, toplam
  **300 kontrol / 0 hata** geçti. Bunlar yerel AppKit girdi teslimi ve sahte
  katalog/temas verisi kullanır; gerçek HID, fiziksel trackpad, haptik veya
  üçüncü taraf odak kabulü değildir.
- Tam testler **1.402 vaka** (Core 957, App 68, AI 22, SSH 355), dört isteğe
  bağlı atlama ve sıfır test hatasıyla geçti. Yerelleştirme **4234 / 0 eksik /
  0 biçim uyuşmazlığı**; debug paket derlemesi ve sıkı imza doğrulaması geçti.

Kanıtlar `.build/switcher-stage20-hold-{tr,en}-report.json`,
`.build/switcher-stage20-gesture-{tr,en}-report.json`,
`.build/switcher-stage20-secure-input-live.json` ve ilgili günlüklerdedir.
Kaynak SHA ve kapsam özeti `.build/switcher-stage20-evidence.json` dosyasındadır.
Canlı durum kaydı üretimde kullanılan aynı Core okuyucusuyla alındı.
Bu aşama için release kabulü ayrıca bildirilmedikçe önceki aşamanın release
sonucu güncel kaynak üzerinde yeniden koşulmuş sayılmaz. Sürüm/build değiştirilmedi.

## Yirmi birinci aşama — gerçek uygulamalarda bağlı sayfa odağı

Gerçek üçüncü taraf kabulü, üretim imzalı debug bundle'ın erken AppKit girişinde
ve ayrı paket CLI sürecinden yapıldı. Başlangıçta Ghostty çalışıyor olmasına
rağmen görünür pencere yüzeyi yoktu; pencere açılmadı ve native kapsam mevcut
**iTerm2** penceresiyle sınandı. Electron kapsamı mevcut **Visual Studio Code**
pencereleridir. Uygulama tercihleri ve belge içerikleri değiştirilmedi.

- İlk gerçek geçişte VS Code öne geldiği hâlde CLI `focus-failed` döndü.
  Hedef `1091` için gerçek odak `8132 / AXSheet`, onun `AXParent` değeri ise
  `1091 / AXWindow` idi. İkinci VS Code penceresi `1092`, kendi ayrı sayfası
  `8131` ile aynı durumu taşıyordu. Bu, doğru pencereye bağlı iletişim
  sayfasının farklı WindowServer kimliği nedeniyle yanlış başarısız sayılmasıydı.
- `WindowFocusOwner` yalnız AXWindow veya AXSheet'ten başlayan, aynı PID'deki
  üst öğe zincirini okur. En fazla sekiz öğe, 100 ms bütçe ve öğe başına 20 ms
  AX zaman aşımı vardır; çevrim, uygulama kökü, okunamayan rol/kimlik ve iptal
  doğrulamayı durdurur. Başlık/geometri benzerliği sahiplik kanıtı sayılmaz.
  Hedef ile bulunan sahibin kimliği ayrıca eşleşmelidir.
- Odak doğrulaması sayfanın gerçek sahibini denetler. Katalogdaki aktif kart ve
  odak gözlemindeki MRU da sahibi izler. İmleç için dönen geometri ise gerçekten
  odaklı sayfanın WindowServer yüzeyidir. Sayfa kapatılmaz veya onaylanmaz.
- Ayrı paket CLI → CFMessagePort → gerçek model → PID/URL kapsamlı gerçek
  katalog zincirinde **29 kontrol / 0 hata** geçti. iTerm2, iki VS Code penceresi,
  sayfa/sahip kimlikleri, kardeş pencerenin odak hedefi olamaması, tek aktif kart,
  gerçek MRU 2, kayıp ID, geometri koruması, kira temizliği ve önceki pencereye
  dönüş denetlendi. Kabul okuyucusu üretim sahip çözücüsünü yeniden kullanmaz;
  gerçek AXSheet'in doğrudan AXParent kimliğini bağımsız okur.
- Sahipli ayrı AppKit uygulamasıyla tam dış denetim **134 kontrol / 0 hata**
  verdi; mevcut Space/sekme, küçültme/gizleme, MRU, yakalama ve imleç yolları
  bu odak değişikliğiyle yeniden geçti. **7 yeni sahiplik testi**, ilgili
  odak/imleç testleriyle birlikte 22 seçili testte sıfır hata verdi.
- Tam test koşusu **1.409 vaka** (Core 964, App 68, AI 22, SSH 355), dört
  isteğe bağlı atlama ve sıfır test hatasıyla geçti. Yerelleştirme
  **4234 / 0 eksik / 0 biçim uyuşmazlığı**.
- Release `MacPocket` ürünü **115,78 saniyede** derlendi; debug paketinin sıkı
  imza doğrulaması ve denetim betiğinin gerçek çağrısı geçti. Release paket
  yayımlanmadı; uygulama sürümü veya build numarası değiştirilmedi.

Gerçek uygulama kabulü yalnız mevcut görünür pencerelerde odak içindir:
ekran görüntüsü veya belge metni kaydedilmez; global kısayol kaydedilmez.
Fiziksel HID, VoiceOver/Sticky Keys, farklı uygulamalar veya genel AltTab
eşdeğerliği bu sonuçtan çıkarılamaz. Tekrar çalıştırma:
`scripts/audit-window-switcher-external.sh --skip-build --only-existing-focus`
(görünür iTerm2 ve VS Code pencereleri gerekir).

Gerçek uygulama raporu `.build/switcher-stage21-existing-focus/report.json`,
ara başarısız kayıtlar `.build/switcher-stage21-{first,second,third,fourth,fifth}-existing-report.json`,
tam sahipli dış rapor `.build/switcher-stage21-full-external-report.json`
dosyalarındadır. Önceki uygulama ve pencereye dönüldüğü gerçek AX kimliğiyle
doğrulandı. Kaynak SHA, kapsam ve kapı sonuçları
`.build/switcher-stage21-evidence.json` dosyasındadır. Sürüm **0.1.5 / build 8** korundu.

## Yirmi ikinci aşama — gerçek Settings ve dosya seçicileriyle aktarım

Ayar aktarımının dosya seçicisi kabulü tamamlandı. Gerçek üretim bileşeni
`SwitcherSettingsTransferLink`, `openOverride` kullanılmadan gerçek SwiftUI
Settings sahnesini Gelişmiş bölümünde açtı. Türkçe ve İngilizce ayrı denetim
bundle'larında **29 × 2 = 58 kontrol / 0 hata** geçti; her dilde yedi gerçek
dosya seçicisi açıldı. Normal kullanıcının tercih alanı yerine denetim
bundle'ının tercih alanı ve `.build` içindeki kendi dosyaları kullanıldı.

- Üretimde NSSavePanel/NSOpenPanel artık `beginSheetModal` ile kendi Settings
  penceresine bağlanır. Uygulama çapında iç içe `runModal` döngüsü yoktur.
  Bekleyen seçici varken dışa/içe aktar düğmeleri kilitlenir; görünüm kapanınca
  seçici iptal edilir. Tamamlanma yalnız hâlâ aynı panelin sahibi olan görünümde
  uygulanır. Pencere bağlantısı zayıf NSView referansıyla tutulur.
- Açma seçicisi tek JSON dosyası kabul eder; dizin seçmez. İptal ayar uygulamaz.
  Seçici açılamazsa TR/EN hata metni gösterilir. Aktarım sonuçlarının tam metni
  açık erişilebilirlik etiketiyle de verilir; görsel TR/EN sonuçlar incelendi.
- Gerçek dosyadan dokuz profil; üç stil/bırakma davranışı, özel basılı tutma
  kümesi, eylemler, koşullu istisnalar ve kapalı global kısayol kayıpsız döndü.
  Modelin izleme aralığı da gerçek içe aktarma sonrası güncellendi.
- Dışa/içe aktarmada iptal, bozuk profil verisinin tüm mevcut yönetilen ayarları
  koruması ve yerelleştirilmiş nedenin gösterilmesi denetlendi. Dosya seçilmişken
  Settings kapatıldığında içe aktarılmadığı; tekrar açıldığında yeni seçicinin
  kilitlenmediği de geçti. Dosya seçicilerinin Settings'e bağlılığı gerçek
  `sheetParent` pencere kimliğiyle doğrulandı.
- Denetimde dosya konumu/ismi panel **açılmadan önce** hazırlanır; bu alanlar
  macOS 27 SDK'sında yalnız yapılandırma evresinde değiştirilebilir. Sonraki
  gerçek dosya seçimi ve düğme eylemleri, mevcut AX izni olan üretim imzalı
  yardımcı süreçten yalnız denetim penceresinin bağlı AX alt ağacına uygulanır.
  Bu yardımcı normal AppState'i veya modülleri başlatmaz; izin istemez.
- Yardımcı 18 AX işlemi kaydetti. Kapanan sayfalardaki 12 düğme eyleminin AX
  dönüşü `cannotComplete` oldu; tıklama tekrarlanmadı. Başarı, API dönüşünden
  değil bağımsız panel URL'si, dosya içeriği, gerçek tercih/model durumu ve
  görünen sonuç metninden doğrulandı. Fiziksel tuş/fare kabulü iddiası yoktur.

İlk sürücü denemeleri yapılandırma evresi ve uzak dosya paneline girdi yöneltme
sınırlarını ortaya çıkardı; başarısız örnekler başarılı kabul gibi kaydedilmedi.
Yerel UI metin okuyucusunun boş etiket sonuçları görsel kayıtla ayrıldı;
mesajların erişilebilirlik etiketi ve gerçek sonucu ayrıca kontrol edildi.
Denetim kaynakları DEBUG kapsamındadır; tercih/dosya I/O üretim yoludur.

Raporlar `.build/switcher-stage22-transfer-{tr,en}-report.json`, kontrolcü kaydı
`.build/switcher-stage22-controller-report.json`, görseller
`.build/switcher-stage22-transfer-{tr,en}-{valid,invalid}.png` dosyalarındadır.
Tekrar koşu: `scripts/audit-window-switcher.sh --skip-build --only-transfer`.
Tam testler **1.409 vaka**, dört isteğe bağlı atlama ve sıfır hatayla geçti.
Yerelleştirme **4235 / 0 eksik / 0 biçim uyuşmazlığı**. Release `MacPocket`
ürünü **111,66 saniyede** derlendi; debug paketinin sıkı imzası doğrulandı.
Kaynak SHA ve kapsam özeti `.build/switcher-stage22-evidence.json` içindedir.
Sürüm **0.1.5 / build 8** korundu.

> Tarihsel düzeltme: 23–25. aşamalarda güvenli girişin ⌘Tab için engel
> sayılması yanlış bir genellemeydi. 26. aşamada Carbon ile event tap ayrıldı;
> eski kayıtlar o zamanki davranışın tarihsel kanıtıdır.

## Yirmi üçüncü aşama — ⌘Tab sahipliği ve bağımsız geri yükleme

Saf ⌘Tab artık tercih doğrulamasında kabul edilir. Üretim denetleyicisi ileri
ve Shift ile geri Carbon kısayolunu çift olarak kaydeder; ikisinden biri
başarısızsa başarılı yarıyı da kaldırır ve macOS kısayol durumunu değiştirmez.
İki kayıt da başarılıysa aynı imzalı executable ayrı, yetkisiz bir yardımcı
süreç olarak `--switcher-native-key-guard` ile başlatılır. Bu giriş AppState,
normal modüller ve dil/tercih geçişlerinden önce çalışır.

Yardımcı süreç yalnız SkyLight sembolik kısayol **1 ve 2** için özgün açık/
kapalı durumunu okur. Hazır mesajı ebeveyne ulaştıktan sonra edinme komutu
verilir; ikisini kapatma ve geri okuma başarılı olmadan edinme onaylanmaz.
Kısmi hatada iki özgün değer de geri yazılır. Sistem tercih dosyası, root,
kalıcı daemon veya genel tuş izleme kullanılmaz. SkyLight özel API'dir;
dosya backend testleri bu API'nin gerçek devralma kabulünü kanıtlamaz.

UI iş parçacığı saniyede bir kalp atışı gönderir. Yardımcı süreç dört saniye
atış alamazsa, boru kapanırsa, protokol bozulursa veya Güvenli Klavye Girişi
açılırsa özgün durumu geri yükleyip kapanır. Güvenli giriş yardımcıda yaklaşık
100 ms aralıkla kontrol edilir. Normal kapatma geri yükleme onayını bekler;
modül/global kısayol kapatma, istisna ve tuş kaydı önce bu sahipliği bırakır.
Çocuğun beklenmedik kapanışında ebeveyn de geri yüklemeyi dener. Geri yükleme
başarısızsa süreç bitmiş olsa bile yeni sahipliğe izin verilmez; geçici hata
kalkınca tekrar denenebilir. Eski sonlanma callback'i yeni sahibin durumunu
geri yazamaz. UI'da beklenmedik hata için yerelleştirilmiş **Yeniden Dene**
eylemi vardır; hatalı yardımcı sürekli yeniden başlatılmaz.

Yardımcı kaybolduğunda kuyruktaki eski kısayol teslimi reddedilir. Açık ve
⌘ basılı tutulan oturum, UI tekrar çalıştığında tuş bırakma veya Enter ile
eski hedefe odaklanamaz. Varsayılan Option+Tab ve manuel açılan panelin
davranışı korunur. ⌘ basılıyken varsayılan ⌘W/⌘S eylemlerinin yalnız basılı
tutulan değiştirici çıkarıldığı için kaybolması da düzeltildi; özel çıplak
tuş eylemi önceliklidir ve aramada çıplak harfler metin kalır.

Doğrulama kapsamı:

- Altı saf işlem testi dört özgün durum, kısmi setter hatası, başarısız geri
  okuma, eksik durum bilgisi ve yalnız 1/2 numaralarının değiştirilmesini kapsar.
  Basılı ⌘ eylemleri/arama önceliği için bir ek test vardır.
- `scripts/audit-switcher-native-keys.sh --skip-build`: **34 kontrol geçti**.
  Gerçek üretim lease'i, gerçek ayrı süreçler ve aynı boru protokolü kullanılır;
  setter'lar yalnız UUID'li kendi geçici JSON dosyasına bağlıdır. Normal stop,
  kalp atışı, UI durması, çocuğun öldürülmesi, ebeveynin `_exit` ile temizlenmeden
  çökmesi, boru kapanması, örnek güvenli giriş ve geçici geri yükleme hatası
  kapsanır. Gerçek sistem durumu öncesi/sonrası aynıydı. Bu sonuç gerçek macOS
  setter kabulü değildir.
- Aynı script'in iki **salt okunur gerçek backend** denemesi hazır durumunu
  `R0` olarak okudu: edinme komutu gönderilmeden `Q` için 0, geçersiz protokol
  için 65 çıkışı alındı. WindowServer'a devralma yazısı istenmedi.
- `scripts/audit-window-switcher.sh --skip-build --only-hold`: TR **76**,
  EN **76** kontrol geçti. Yerel AppKit ⌘Tab/⌘ShiftTab, üç bırakma modu,
  basılı ⌘ ile eylem/arama ve sahiplik kaybında seçmeden iptal kapsanır.
  Bunlar gerçek global ⌘Tab veya fiziksel HID teslimi değildir.
- Tam `swift test`: Core **971** (4 isteğe bağlı atlama), App **68**,
  AI **22**, SSH **355**; toplam **1.416**, 0 hata. Son panel sahipliği
  korumasından sonra ilgili **68 App testi** ayrıca yeniden geçti.
- Yerelleştirme: **4.237 anahtar, 0 eksik İngilizce, 0 biçim uyuşmazlığı**;
  kaydedicide 9 anahtar ve 0 eksik Türkçe. İmzalı Debug paketinin strict
  codesign kontrolü geçti. `swift build -c release --product MacPocket`
  **128,89 saniyede başarılı**. Sürüm **0.1.5 / build 8** korundu.

Kanıtlar `.build/switcher-stage23-*` ve script'in
`.build/switcher-native-key{,-readonly}-report.json` dosyalarındadır. Son
gerçek durum okumasında Chrome **PID 751** Güvenli Klavye Girişi sahibiydi.
Güvenli giriş kapatılmadı; bu koşulda gerçek sistem ⌘Tab devralması ve HID
kabulü yapılmadı. Tam AltTab eşdeğerliği iddiası yoktur.

## Yirmi dördüncü aşama — kayıt hataları ve sahip bırakma temizliği

`WindowSwitcherHotkeyController.configure` içindeki üretim kayıt politikası
doğrudan sınandı. Carbon kayıt/kaldırma, güvenli giriş sorgusu ve yardımcı
sahipliğini edinme çağrıları `SwitcherHotkeyRegistration.system` içinde aynı
OS çağrılarına bağlanır. Testler bu sınırı değiştirir; gerçek denetleyiciyi ve
kendi UserDefaults alanını kullanır. Bu testler gerçek global Carbon teslimi
veya WindowServer setter kabulü değildir.

Dokuz yeni uygulama testi şu yolları kapsar:

1. Güvenli girişte yalnız ⌘Tab atlanır, Option ileri/geri çifti kalır.
2. İleri veya geri Carbon kaydının ayrı ayrı hata vermesinde başarılı yarı
   kaldırılır; macOS sahipliği hiç edinilmez.
3. İki Carbon kaydı edinmeden önce tamamlanır; kaydedici ve modül kapanması
   geri yüklemeyi Carbon kaldırmasından önce yapar.
4. Yardımcı edinme hatası iki kaydı da geri alır; açık yeniden deneme toparlar.
5. Beklenmedik yardımcı kaybı otomatik yeniden başlatma döngüsü oluşturmaz.
6. Güvenli giriş açılması geri yükler; kapanması diğer kısayolları koruyarak
   yeniden edinmeye izin verir.
7. Geri yüklenemeyen eski sahip varken yeni sahip edinilmez; eski sahip
   bırakılabildiğinde açık yeniden deneme çalışır.
8. Global kapatma izleyiciyi durdurur, önce geri yükleyip sonra kayıtları kaldırır.
9. Öndeki uygulama istisnası aynı sırayla bırakır; istisna kaldırılınca yeniden kaydeder.

Süreç sahibi `stop()` çağrılmadan bırakıldığında okuma borusu açık kalabiliyordu:
son Process'i tutan çakışma koruması, Pipe nesnesini de tutuyordu. `deinit`
artık ebeveyne ait iki boru ucunu da kapatır. Gerçek süreç denetimi boru
nesnelerini tutarak kapandıktan sonra boş okuma/yazmanın reddedildiğini ve
çocuğun EOF ile özgün durumu geri yüklediğini doğrular. Tekrar kullanılabilen
sayısal descriptor kimliğine dayanmaz.

Güncel doğrulama:

- `swift test`: Core **971** (4 isteğe bağlı atlama), App **77**, AI **22**,
  SSH **355**; toplam **1.425**, 0 hata. Yeni dokuz kayıt testi de geçti.
- `scripts/audit-switcher-native-keys.sh --skip-build`: **35 gerçek süreç/
  dosya backend kontrolü** ve edinme komutu içermeyen **iki salt okunur gerçek
  backend kontrolü**, 0 hata. Gerçek sistem setter'ı ve fiziksel HID denenmedi.
- TR/EN `--only-hold`: **76 + 76** kontrol, 0 hata. Rapordaki
  `globalCommandTabExercised: false`, yerel AppKit Command olaylarının gerçek
  global ⌘Tab tesliminden ayrı olduğunu açıkça belirtir.
- Yerelleştirme: **4.237 anahtar, 0 eksik İngilizce, 0 biçim uyuşmazlığı**;
  kaydedicide 9 anahtar ve 0 eksik Türkçe. Debug paketinin strict codesign
  kontrolü geçti. Release ürün derlemesi **118,43 saniyede başarılı**.
  Sürüm **0.1.5 / build 8** korundu.

Son Carbon sorgusu güvenli girişin açık olduğunu; süreç denetimi sahibinin
Chrome **PID 751** olduğunu tekrar gösterdi. Güvenli giriş değiştirilmedi.
Gerçek ⌘Tab devralması/HID kabulü hâlâ açıktır. Kanıtlar
`.build/switcher-stage24-*` dosyalarındadır.

## Yirmi beşinci aşama — ölçülen liste hesaplama maliyeti

Seçim, küçük resim, rozet ve görünüm güncellemeleri aynı `filtered` sonucunu
tekrar istiyordu. Önceki getter her okumada filtreleme, sıralama ve gruplamayı
yeniden çalıştırıyordu. `WindowSwitcherModel` artık tek sonuç dizisini saklar;
katalog, tablo/oturum araması, profil filtresi/sırası, öndeki süreç, ekran,
imleç bağlamı ve istisnalar değişince geçersizleştirir. Etkin varsayılan sıra
ve locale kimliği okumada kontrol edilir. Seçim ve görüntü güncellemeleri aynı
sonucu yeniden kullanır. Saklanan değer AX nesnesi veya görüntü içermez.

Modelin sıralama tercihi, kendisine verilen `defaults` yerine doğrudan
`UserDefaults.standard` üzerinden okunuyordu. Bu da düzeltildi; üretimde
varsayılan alan aynıdır, ayrı modellerin ayar alanları birbirine karışmaz.
Beş yeni davranış testi ayrı tercih alanlarını ve dışarıdan sıra değişmesini,
tablo/oturum aramasını, öndeki uygulama/ekran/imleç değişimini, yerinde profil
düzenlemesini/gruplamayı, istisna yenilemesini ve katalogdan kaldırılan
pencereleri kapsar. Testler önbelleğin özel uygulama ayrıntısını doğrulamaz;
görünen sonucun güncel kalmasını denetler.

### Tekrarlı liste okuması ölçümü

`--only-performance`, **300 öğeli sentetik modelde**, başlığa göre sıralama
ve ortadaki seçimle çalışır.
Her örnek 100 liste ve 100 seçili öğe okumasıdır; önce/sonra onar örnek alınır.
Sonuç checksum'ı iki koşuda da **315000**'dır.

| Debug / Mac Studio ölçümü | Önce | Sonra |
|---|---:|---:|
| 200 okuma medyanı | 129,19 ms | 5,89 ms |
| 200 okuma örnek p95'i | 130,60 ms | 8,25 ms |

Bu koşulda medyan iş yükü yaklaşık **22 kat daha kısa**, maliyet yaklaşık
**%95,4 daha düşük**. Bunlar sentetik model ve Debug ölçümleridir; tüm
uygulamanın, gerçek HID'nin, Release sürümünün veya pil tüketiminin aynı
oranda iyileştiği anlamına gelmez.

### Gerçek katalog ve panel ölçümü

`scripts/audit-window-switcher-external.sh --skip-build --only-performance`
üretim imza kimliği, gerçek AX/SCK ve ayrı sahipli AppKit uygulamasıyla **15
kontrolde geçti**. Genel katalog yalnız okunur; kullanıcı pencere başlıkları
rapora kaydedilmez. Altı genel taramanın her birinde **33 katalog kaydı** ve
`partial: false` görüldü. Bu sayı iki sahipli test penceresini ve penceresiz
uygulama kayıtlarını da içerebilir. İlk tarama **364,53 ms**, sonraki beşi
**76,70–178,22 ms** sürdü; bu taramalar için bir hızlanma iddiası yoktur.

Yalnız iki sahipli pencerenin AX katalog taraması medyanı **17,21 ms** idi.
Panel sekiz kez açıldı; ilk model oturumunda panel görünürlük bayrağı yaklaşık
**21,76 ms**, yeni seçili küçük resim yaklaşık **250,94 ms** içinde görüldü.
Sonraki yedi açılışın medyanları panel için **13,11 ms**, katalog hazırlığı
için **34,70 ms**, yeni seçili küçük resim için **67,92 ms** idi. İlk oturumun
model görüntü önbelleği boştur; işletim sisteminin SCK servisinin soğuk olduğu
iddia edilmez. İlk temel koşuda yeni görüntünün yaklaşık 834 ms sürmesi de
SCK başlangıç maliyetinin değişebildiğini gösterir; bu fark önbellek
optimizasyonuna atfedilmez.

Ölçümde açılış gecikmesi **0 ms**, açılış/kapanış animasyonu kapalı ve opak
erişilebilirlik zemini zorlanmıştır. Panel değeri `isVisible` gözlemidir;
ilk fiziksel ekran karesi değildir. Süreler 5 ms aralıklı gözlem ve AppKit
zamanlamasını içerir. `thumbnailAvailableAfterPreparationMs`, katalog
hazırlandıktan sonraki görüntü kontrolüdür. Global kısayol kaydı, fiziksel tuş
teslimi veya kullanıcı penceresine odak/eylem yapılmaz. Panel kapalıyken yeni
yakalama başlamadığı ve durdurmada kaynakların bırakıldığı da kontrol edilir.

Güncel kontroller:

- Tam testler: Core **971** (4 isteğe bağlı atlama), App **82**, AI **22**,
  SSH **355**; toplam **1.430**, 0 hata.
- Yerel gezinme: TR **63**, EN **63**; basılı tutma/bırakma: TR **76**,
  EN **76**; toplam **278** native panel kontrolü, 0 hata.
- Yerelleştirme: **4.237 anahtar, 0 eksik İngilizce, 0 biçim uyuşmazlığı**;
  kaydedicide 9 anahtar ve 0 eksik Türkçe. Debug strict codesign geçti.
  Release ürün derlemesi **115,28 saniyede başarılı**.
  Sürüm **0.1.5 / build 8** korundu.

Önce/sonra ham ölçümler `.build/switcher-stage25-{baseline,after}-report.json`,
test ve derleme kayıtları `.build/switcher-stage25-*` içindedir. Bu aşama gerçek
⌘Tab, VoiceOver, fiziksel trackpad veya pil kabulünü tamamlamaz.

## Fiziksel klavye kabulünün durumu — 7 Kasım 2026

Debug derlemesine `--only-manual-keyboard` modu eklendi. Aynı oturumdaki gerçek
Carbon ileri/geri callback'lerini, değiştirici bırakma olayını, yeni başarılı
odak isteğini ve ayrı uygulamanın AX odaklı pencere kimliğini birlikte bekler.
Çalıştırma: `./scripts/audit-window-switcher-external.sh --skip-build --only-manual-keyboard`.
Kullanıcının fiziksel klavye katılımı henüz gerçekleşmedi; bu kabul geçmedi.

`--only-manual-keyboard-cancel` ile iptal temizliği doğrulandı: test süreçleri
çıktı, ilk sistem kısayol durumu geri yüklendi ve AltTab yeniden açıldı.
Ham rapor fiziksel kabulü doğru biçimde `false` tutar. Rehber ekran görüntüsü
bu çalışmada elde edilemedi; rehberin görsel kabulü yapılmış sayılmaz.
Güncel Debug derleme/imza kontrolü geçti. Yerelleştirme kontrolü: 4240 anahtar,
0 eksik İngilizce çeviri, 0 biçim uyuşmazlığı. Önceki tam test ve Release
sonuçları aşağıda kendi aşamalarının kanıtı olarak korunur.

## Yirmi altıncı aşama — gerçek ⌘Tab devralması ve güvenli giriş düzeltmesi

Önceki event tap denemesinin güvenli giriş altında callback almaması,
Carbon tabanlı kısayol kaydına da genellenmişti. Bunun sonucunda çalışan bir
kayıt yolu kod tarafından gereksiz yere engelleniyordu. Bu koşul hem
denetleyiciden hem yardımcı süreçten kaldırıldı. Güvenli giriş açılması artık
kayıtları sökmez veya yardımcıyı kapatmaz; UI durumu bilgi olarak gösterir ve
parola alanından çıkılmasını istemez. Güvenli giriş hiçbir aşamada kapatılmaz.

[Apple TN2150](https://developer.apple.com/library/archive/technotes/tn2150/_index.html)
olay yakalama yöntemleri ile güvenli giriş etkileşimini açıklar; buradan tüm
kısayol API'leri için aynı sonuç çıkarılmamalıdır. AltTab'ın eski deney notuna
ait arama sonucu Carbon'un güvenli girişte çalıştığını belirtti; doğrudan
dosya URL'leri 404 verdiğinden bu sonuç güncel sürüm kod kanıtı sayılmadı.
Aşağıdaki gerçek macOS durum testleri kendi başına ayrı kanıttır.

### Gerçek Carbon / WindowServer kabulü

`scripts/audit-window-switcher-external.sh --skip-build --only-system-command-tab`
**21 kontrolde geçti**. Önce çakışan kurulu AltTab **11.7.1** normal şekilde
kapatıldı; ayarlarına müdahale edilmedi. macOS'un ileri/geri iki kısayolunun
açık olduğu doğrulandı. Üretim `SwitcherHotkeyRegistration.system`, gerçek
Carbon kayıtları, üretim denetleyicisi ve gerçek yardımcı executable kullanıldı:

- Gerçek ⌘Tab ve ⌘ShiftTab kayıtları başarılı oldu.
- Yardımcı, gerçek WindowServer durumunu açık/açık → kapalı/kapalı yaptı.
- Kaydediciye giriş açık/açık durumunu geri getirdi; çıkış yeniden devraldı.
- Yalnız teste ait gerçek yardımcı süreç sonlandırıldı. Ebeveynin geri
  yüklemesi ve sağlık izleyicisinin Carbon kayıtlarını kaldırması geçti.
- Yardımcı kendiliğinden tekrar tekrar başlatılmadı; açık yeniden deneme
  gerçek macOS durumunu yeniden devraldı.
- Modül durdurma özgün açık/açık durumunu geri getirdi ve kaynakları bıraktı.
- Eski yardımcıların tamamı çıktıktan sonra AltTab yeniden açıldı. Başlangıç
  ve son WindowServer durumu aynı kapalı/kapalı değerleriydi; AltTab yeniden
  kendi kısayolunu devraldı. Eski PID **44031**, yeniden açılan PID **3893**.

Test boyunca Chrome **PID 751** güvenli girişi açık tutuyordu ve bu durum
değişmedi. Event tap, üretilmiş tuş veya kullanıcı penceresine test eylemi
kullanılmadı. Sahipli test uygulaması kapandı ve başlangıçtaki uygulama geri
getirildi. Bu sonuç **kayıt, gerçek durum geçişi ve geri yükleme** kabulüdür;
fiziksel tuş teslimi kabulü değildir.

### Üretilmiş girişin sınırı

Önce `--only-carbon-hotkey` ile yalnız ⌃⌥⌘F12 ve Shift'li karşılığı kaydedildi.
Kayıtlar başarılıydı; işaretlenmiş `CGEvent.post` olaylarından Carbon pressed/
released callback'i alınmadı. Güvenli giriş, sistem kısayol durumu ve başlangıç
uygulaması korundu; üretilmiş değiştiriciler bırakıldı. Bu negatif deneme
`.build/switcher-stage26-carbon-initial-report.json` içindedir. Sonuç fiziksel
Carbon tuşunun çalışmadığı veya nedeninin Chrome olduğu anlamına gelmez;
bu ortamda sentetik uçtan uca kabul yapılamadığını gösterir. Fiziksel ⌘Tab /
⌘ShiftTab / bırakınca seçme kabulü kullanıcı klavyesiyle ayrıca yapılmalıdır.

### Kısayolu arayüzden seçme

Tuş kaydı sırasında macOS'un ⌘Tab'ı yeniden etkin olduğundan bu birleşimin
kaydediciye ulaşması güvenilir değildir. Kısayol satırına native **Hazır
kısayollar** menüsü eklendi: ⌥Tab ve ⌘Tab. Profil kimliği, filtre, görünüm ve
bırakma davranışı korunur; yeni birleşimde bulunmayan açık basılı tutma kümesi
varsayılana döner. Aynı dönüşüm normal tuş kaydında da kullanılır. Çakışmalar
mevcut doğrulayıcı üzerinden bildirilir; kayıt sırasında menü devre dışıdır.

İlk simgeli menü native AX ağacında “aşağı git / go down” olarak görünüyordu.
Görünür yerelleştirilmiş metinli native menüye çevrildi; TR/EN ve 520/760
genişlikte doğru ad ve taşma kontrolü geçti. Bileşen görüntüleri incelendi.
Bu kontrol menü açıp seçim yapmanın fiziksel veya VoiceOver kabulü değildir.

Güncel doğrulama:

- Tam testler: Core **972** (4 isteğe bağlı atlama), App **82**, AI **22**,
  SSH **355**; toplam **1.431**, 0 hata. Yeni test profil ayarlarının ve geçerli
  basılı tutma kümesinin hazır seçimde korunmasını doğrular.
- Dosya backend'li gerçek süreç kontrolleri **34**, salt okunur gerçek backend
  kontrolleri **2**: geçti. Önceki 35. kontrol, artık yanlış kabul edilen
  “güvenli girişte kapat” davranışına aitti ve kaldırıldı.
- TR/EN basılı tutma ve menü adı kontrolleri **78 + 78**, 0 hata.
- Yerelleştirme **4.237 anahtar, 0 eksik İngilizce, 0 biçim uyuşmazlığı**;
  kaydedicide 9 anahtar, 0 eksik Türkçe. Debug strict codesign geçti.
  Release ürün derlemesi **114,98 saniyede başarılı**.
  Sürüm **0.1.5 / build 8** korundu.

Kanıtlar `.build/switcher-stage26-*` içindedir. Bu aşama tam AltTab eşdeğerliği
veya fiziksel klavye/trackpad kabulü iddiası değildir.

## Yirmi sekizinci aşama — geç gelen önizlemeler

Üç görüntü yarışı düzeltildi: liste yenilenirken kapanan pencerenin bekleyen
yakalama sonucu önbelleğe geri yazılabiliyordu; seçili büyük önizleme yakalanırken
Ekran Kaydı izni kaldırıldığında sonuç yine gösterilebiliyordu; Tools görünümü
durdurulduktan sonra ayrıntı önizlemesi geri gelebiliyordu. Sonuçlar uygulanmadan
önce pencerenin varlığı, geçerli oturum, iptal ve izin yeniden denetlenir.
Ayrıntı önizlemesinin geç gelen hataları da durdurulmuş görünümü değiştirmez.

Üç kontrollü gecikme testi önce üç hatayı yeniden üretti. Düzeltmeden sonra
**85 App testi, 0 hata** ile geçti. Debug paket derlemesi ve strict imza kontrolü
geçti; yerelleştirme **4240 anahtar, 0 eksik İngilizce, 0 biçim uyuşmazlığı**.
Kanıtlar `.build/switcher-stage28-*` içindedir. Bu sonuçlar model yarışlarının
kabulüdür; fiziksel klavye veya trackpad kabulü değildir. Sürüm/build değişmedi.

## Yirmi dokuzuncu aşama — trackpad yeniden bağlanması ve uyku

Önceki adaptör cihaz listesini yalnız ayar uygulanırken alıyordu. Bluetooth
trackpad sonradan bağlandığında veya uyku sonrası bağlantısı yenilendiğinde
eski liste kullanılabiliyordu. `TrackpadHardwareObservation`, gerçek IOKit
eşleşme/sonlanma bildirimlerini ana run loop'ta izler; iterator'lar boşaltılarak
yeniden kurulur. Bildirimler 150 ms birleştirilir; periyodik cihaz taraması yoktur.
Liste değişince eski callback'ler kaldırılır ve güncel cihazlara bağlanılır.
Uyku öncesinde aktif hareket iptal edilir, cihazlar durdurulur; uyanış güncel
listeyi zorunlu olarak yeniden bağlar. Özellik kapatılınca port, run loop kaynağı,
iki iterator, uyku/uyanma abonelikleri ve bekleyen zamanlayıcı bırakılır.

Bağlantı kaybı parmak bırakma kabul edilmez. UI'ya teslim edilen hareket kimliği
ayrı tutulur; bitiş callback'i kuyruğa girmiş olsa bile donanım değişimi eski
teslimleri geçersizleştirip `cancelled` verir. Yeni temaslar tüm parmaklar
kalkmadan gezinmeye başlayamaz; bu durum yanlış pencereye geçişi önler.

`MACPOCKET_TEST_TRACKPAD=1 swift test --filter MacPocketAppTests`: **90 test,
0 hata**. Bu makinede I/O Registry'de Bluetooth `AppleMultitouchDevice` bulundu;
gerçek MultitouchSupport cihaz listesiyle 3 ve 4 parmak ayarında adaptör
başlatma/durdurma testi geçti. IOKit abonelikleri gerçekten kuruldu ve temizlendi.
Uyku/uyanma test bildirimleri yalnız test sürecine gönderildi; bilgisayar uyutulmadı.
Hareket/iptal yarışları kontrollü temas verisi kullanır. Fiziksel kaydırma,
bağlantıyı kesip yeniden kurma ve haptik hissi bu kontrollerin kabulü değildir.

İmzalı Debug derlemesi ve yerelleştirme **4240 / 0 eksik / 0 biçim uyuşmazlığı**
ile geçti. Release ürün derlemesi **112,29 saniyede başarılı** oldu. Kanıtlar
`.build/switcher-stage29-*` içindedir. Sürüm **0.1.5 / build 8** korundu.

## Sıradaki geliştirmeler

1. REA ile eklenen key-window olayının daha fazla üçüncü taraf uygulamada ve
   gerçek HID ile kabulü. iTerm2 ve iki VS Code penceresinde CLI odağı 21.
   aşamada geçti. Son sahipli dış koşu 134 kontrolde temizdir.
   Üçüncü taraf uygulama farkları ve görünmeyen Space'te kapatılmış fakat
   fiziksel yüzeyi tutulan pencerelerin anlamsal yaşam döngüsü. Kendi ayrı
   AppKit sürecimizde çapraz Space odak ve iki bağlı ekran kabulü onuncu
   aşamada geçti; hotplug ve farklı AX sağlayıcıları ayrıca denenmelidir.
2. CLI'nin ek üçüncü taraf pencerelerde kabulü; iTerm2/VS Code görünür pencere
   kapsamı tamamlandı. Gerçek Settings ve dosya seçicisi kabulü 22. aşamada
   TR/EN tamamlandı.
   Trackpad hotplug/uyanma kodu 29. aşamada eklendi; fiziksel yeniden bağlama,
   gerçek uyku/uyanma ve haptik kabulü ayrıca açık.
3. Saf ⌘Tab'ın fiziksel ileri/geri/bırakma tuş teslimi kabulü yapılacak.
   Gerçek Carbon kaydı ve WindowServer devralması/geri yüklemesi 26. aşamada
   geçti; güvenli giriş artık bunun için engel sayılmaz. Basılı tutulacak değiştirici kümesi
   artık açma birleşiminden bağımsızdır. AltTab'ın basılı tutma kaydedicisi
   normal harf tuşlarını reddeder; harf basılı tutma eşdeğerlik gereksinimi
   değildir. Değiştiricisiz açmanın gerekliliği ve macOS sınırları ayrıca
   incelenecek. Eski olay filtresi denemesi üretim Carbon yolunun kabulü değildir.
4. Gerçek izinli pencere, Space/ekran, fiziksel kısayol, trackpad ve performans
   kabulü. Araştırmadaki tam matris bu aşamanın sonunda yeniden denetlenecek.

## Bekleyen canlı kabul

Sekizinci aşamadaki üretim kimliği preflight'ında Erişilebilirlik ve Ekran Kaydı
izinleri **true** görüldü; önceki aşamalardaki false kayıtları tarihseldir.
Bu salt okunur kontrol AppState'i başlatmadı ve izin istemedi; izin verilmiş
olması davranışın kabul edildiği anlamına gelmez. Dokuzuncu aşamada kendi ayrı
uygulamamızla gerçek görüntü/odak/sekme ve AX eylemi kabulü yapıldı; diğer Space'e
odak geçişi onuncu aşamada kendi AppKit sürecimizde geçti. Fiziksel
⌘W/⌘M/Option-Tab tuş teslimi ayrıca kabul edilecek. Bağlı Bluetooth trackpad ile
adaptörün başlatılması/durdurulması 29. aşamada geçti; fiziksel hareket ve haptik
ayrıca denenmelidir. Bu belge tam AltTab eşdeğerliği iddiası değildir.

6 Kasım'daki ilk araştırma yalnız belge değişikliği yapmıştı; yukarıdaki ilk
uygulama aşaması ondan sonra gerçekleştirildi. Araştırma bulguları tarihsel
kaynak durumu olarak korunur. Tam AltTab eşdeğerliği tamamlanmış değildir.
