# AltTab ücretsiz / Pro araştırması ve MacPocket karşılaştırması

## Hızlı sonuç — 7 Kasım 2026

**Ücretsiz:** pencere bazlı Option+Tab geçişi, canlı küçük resimler ve tam boy
önizleme, aynı uygulamanın pencereleri, Space/ekran kapsamları, gizli ve
küçültülmüş pencereler, açık/koyu görünüm ve trackpad hareketleri.
Gelişmiş filtre, eylem, sıralama, istisna ve kontrol ayarlarının ayrıntılı
envanteri aşağıdadır; kaynak incelemesinden çıkarılanlar ayrıca işaretlidir.

**Pro'nun dört grubu:** yazarak arama (bırakınca aramaya geçme dahil), simge ve
başlık listesi stilleri, otomatik küçük resim boyutu, toplam dokuz açma
kısayoluna kadar bağımsız profiller. Pro ve Lifetime aynı işlevleri açar;
gelecekteki ana sürüm güncellemeleri Lifetime'a dahildir.
[Resmi fiyat ve özellik ayrımı](https://alt-tab.app/pricing) bu kontrolde de
Pro için 9,99 USD, Lifetime için 24,99 USD gösteriyor.

**MacPocket'in güncel durumu:** bu dört Pro grubunun karşılığı kaynakta var.
Animasyonlu kartlar, profil bazlı görünüm/filtre/sıralama, eylem tuşları,
istisnalar, imleç takibi, hareket/haptik tercihleri, ayar aktarımı ve CLI de
uygulandı. Aşağıdaki ilk araştırma tablolarındaki eski eksik sütunu güncel
durum olarak okunmamalı; doğrulama kayıtları [geliştirme belgesindedir](../WINDOW_SWITCHER.md).
Saf Command+Tab için Carbon kayıt ve bağımsız geri yükleme yardımcısı artık
uygulandı. 26. aşamada **gerçek Carbon kayıtları ve WindowServer devralması/
geri yüklemesi 21 kontrolde geçti**; Chrome güvenli girişi açık kaldı. Önceki
güvenli giriş engeli yanlış genellemeydi ve kaldırıldı. Arayüzdeki hazır
kısayol menüsünden ⌘Tab seçilebilir. Fiziksel trackpad/haptik, HID ve üçüncü
taraflarda tüm özelliklerin kabulü tamamlanmadı.

**Somut REA bulgusu:** kurulu 11.7.1'in ARM64 makine kodunda, pencereyi öne
getirmenin ardından hedef pencereye klavye odağı veren ek olay kaydı bulundu.
MacPocket'in odak yoluna eklendi; statik bulgu ve kendi ayrı AppKit
pencerelerimizdeki gerçek odak kabulü aşağıda ayrı kaydedildi.

**Kısayol kapsamı düzeltmesi:** AltTab'ın basılı tutma kaydedicisi normal harf
tuşlarını kabul etmiyor; yalnız değiştirici tuş istiyor
(`CustomRecorderControlTestable.isShortcutAcceptable`,
`modifiersOnlyButContainsKeycode`). Normal harf basılı tutma desteği AltTab
eşdeğerliği için bir gereksinim değildir.
[Sabitlenmiş kaynak](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/kit/CustomRecorderControlTestable.swift).

Araştırma tarihi: **6 Kasım 2026**. Amaç, AltTab'ın kullanıcıya sunulan ücretsiz ve
Pro özelliklerini MacPocket'ın mevcut pencere geçişiyle eşlemek ve geliştirme
işlerini belirlemek. Bu çalışma uygulama kodunu değiştirmez ve tam eşdeğerlik
veya canlı kabul sonucu bildirmez.

Bu rapor uygulama öncesi araştırma kaydıdır. Aynı gün başlayan geliştirmelerin
güncel durumu ve doğrulama sonuçları [pencere geçişi belgesinde](../WINDOW_SWITCHER.md)
tutulur; aşağıdaki eksiklerin bir bölümü ilk aşamada giderildi.

## Yeniden kontrol ve güncel çalışma ağacı

Resmi özellik, fiyatlandırma, FAQ ve `releases/latest` uç noktası yeniden
kontrol edildi: son sürüm hâlâ `v11.10.1`; Pro 9,99 USD, Lifetime 24,99 USD.
REA ile kurulu paketin `Info.plist` kimliği yeniden okundu: `11.7.1`,
`com.lwouis.alt-tab-macos`; yeni kanıt
`ev_f2fd674d8407fb93b5fce704339f8c03cf8e839d8206ceaaa827ea161eab4fba`.
Tam metadata kanıtı `.build/research/alttab-2026-11-06/rea-plist-recheck.json`
dosyasındadır. Executable SHA-256 önceki araştırmayla aynı. İlk metadata oturumunda REA sağlayıcıları
universal Mach-O'yu doğrudan çözümleyemedi. 7 Kasım'daki ARM64 dilim incelemesi
bu statik engeli aştı; aşağıdaki yeni REA bölümü ayrıdır. Metadata incelemesi
uygulamayı başlatmadı.

Aşağıdaki ayrıntılı tablolardaki **MacPocket karşılıkları ilk araştırma anına
aittir**. Güncel kaynak okumasında animasyonlu kartlar, dokuz bağımsız profil,
bırakınca arama, özelleştirilebilir eylem tuşları, gelişmiş kapsamlar, kategori
sona taşıma, uygulama gruplama, Space sırası ve desteklenen yerel sekmeler için
kod artık var. Yedinci aşamanın kayıtlı test/native sonuçları
[geliştirme belgesindedir](../WINDOW_SWITCHER.md); bunlar üçüncü taraf uygulama
ve gerçek HID kabulü yerine geçmez. Başlık/kısaltma, rozet, ekran ve animasyon
tercihleri sekizinci aşamada uygulandı; model ve kendi native fixture doğrulaması
aynı belgede ayrı kaydedildi. Fiziksel trackpad/haptik kabulü hâlâ açık; saf ⌘Tab reddediliyor.
Dokuzuncu aşamada kendi ayrı AppKit sürecimizle gerçek AXUIElement/SCK taşıması,
canlı piksel yenileme, MRU, sekme keşif/seçim ve Space dışında kayıtlı AX grubunu
yeniden okuma kabulü yapıldı. Kapsam ve kalan gerçek kabul işleri yine geliştirme
belgesindedir; bu raporun aşağıdaki tarihsel karşılık sütunlarını geriye dönük
canlı kabul kaydına dönüştürmez.

Onuncu aşamada aynı ayrı AppKit sürecimizde özgün Space üyeliğini koruyan
sekme/soğuk sıradan pencere odağı ve iki gerçek bağlı ekranda panel/filtre
kontrolleri geçti. Özel AX/WindowServer API sınırları ve başarısız ara deneme
[geliştirme kaydında](../WINDOW_SWITCHER.md) ayrıdır; üçüncü taraf ve fiziksel
kısayol kabulü tamamlanmış sayılmaz.

On birinci aşamada koşullu istisna motoru ve tek editör eklendi. Tam yol/tam
bundle/önek, penceresizken ve başlık metnine göre gizleme, yalnız odaktaki
pencere tam ekrandayken kısayol kapatma ile eski kayıt uyumu geliştirme
belgesinde kaydedildi. Aşağıdaki ilk araştırma tabloları tarihsel kalır.

On ikinci aşamada bağımsız ok/Vim gezinme tercihleri, / ile arama ve özel
eylem önceliği eklendi. Eksik satırda dikey hareket ve katalog yüklenirken
yön sırası düzeltildi. Kod, test ve yerel AppKit kabulü geliştirme belgesinde
ayrıdır; bu kayıt fiziksel klavye veya tam AltTab eşdeğerliği sayılmaz.

7 Kasım'daki on üçüncü aşamada imlecin odağı izlemesi eklendi: kapalı, her
geçişte veya imleç farklı ekrandayken. Taze hedef kimliği, kullanıcı girişi/
iptal koruması ve iki gerçek ekranda kendi pencerelerimizle kabul geliştirme
belgesindedir; bu ilk araştırmanın tarihsel karşılık sütunlarını değiştirmez.

On dördüncü aşamada yatay/dikey trackpad seçimi, isteğe bağlı haptik ve hareket
sahipliği eklendi; son parmakla seçme, temas/cihaz kimliği ve eski callback
iptali düzeltildi. Native paneller kopyalanmış temas verileriyle denetlendi;
fiziksel trackpad ve titreşim kabulü ayrıca açık. Ayrıntılar geliştirme belgesindedir.

On beşinci aşamada uygulamaya ait Dock rozeti, global/kısayol seçeneği ve
panel-içi yenileme eklendi. Aynı uygulamanın pencereleri etiketi paylaşır;
uzun metin erişilebilir açıklamada korunur. Kod, native fixture ve gerçek
Dock taşıması kabulü geliştirme belgesinde ayrı tutulur. Tarihsel envanter
aşağıda ilk araştırma anını göstermeye devam eder.

On altıncı aşamada ilk araştırmanın bir eksikliği düzeltildi: uygulamanın genel
ayar aktarımı zaten `switcher.*` tercihlerini kapsıyordu. Yeni bir dosya biçimi
yerine bu bölüme pencere geçişi ayarlarından erişim eklendi; bozuk dosyanın mevcut
ayarları silmesi ve kapalı global kısayolun ilk açılışta etkinleşmesi önlendi.
Genel aktarım diğer MacPocket ayarlarını da içerir. Dosya seçici kabulü ile
sahipli dosya/tercih ve native düğme kontrollerinin sınırları geliştirme
belgesinde ayrıdır. Resmi özellik ve fiyat sayfaları 7 Kasım'da yeniden
okundu; aşağıdaki ücretsiz/Pro ayrımı ve fiyatlar değişmedi.

On yedinci aşamada çalışan MacPocket'a bağlanan CLI eklendi: sade/ayrıntılı
liste, ID veya MRU sırasıyla odaklama, profil seçerek panel açma, seçmeden
kapatma ve görünürlük sorgusu. MacPocket'ın kendi JSON protokolü kullanılır;
AltTab komut satırı biçimiyle birebir uyum iddiası yoktur. Aynı katalog ve odak
yolu kullanılır. Yerel iletişim, gerçek panel, ayrı CLI süreci ve sahte katalog
doğrulamasının sınırları geliştirme belgesinde ayrıdır.

On sekizinci aşamada açma birleşimi ile basılı tutulacak değiştirici kümesi
ayrıldı. Örneğin ⌃⌥Tab ile açıp yalnız ⌥ bırakılınca seçme uygulanabilir;
varsayılan eski davranışı izler. Tercih, kalıcılık/aktarım ve yerel native
panel denetimi geliştirme belgesinde kayıtlıdır. Bu, saf ⌘Tab desteği veya
iki bağımsız tuş kaydedicisinin tam eşleniği değildir; basılı tutulacak küme
açma birleşimindeki ⌃/⌥/⌘ tuşlarından seçilir.

On dokuzuncu aşamada CLI'nin ayrı süreçteki gerçek AppKit pencerelerine
odaklanması denetlendi. Gizli uygulamada API kabulünün gerçek ön plan geçişini
garanti etmediği görüldü; somut pencere odağına pozitif doğrulama ve bu yarış
için tek yeniden etkinleştirme eklendi. 36 gerçek CLI ve 134 genel dış denetim
kontrolü geçti. Bu, önceki sahte katalog CLI testlerinden ayrı kanıttır;
üçüncü taraf uygulamalar ve fiziksel HID kabulü açık kalır.

Yirminci aşamada manuel/trackpad panelinden klavyeye oturum devralma hatası
giderildi. Güvenli Klavye Girişi için salt okunur sahip tanısı ve TR/EN uyarı
eklendi. Mevcut Chrome kaynaklı güvenli giriş, ⌘Tab olay filtresi denemesini
engelliyor; saf ⌘Tab hâlâ desteklenmiş sayılmaz. Yerel panel ve sahte katalog/
temas denetimleri ile fiziksel kabul sınırı geliştirme belgesindedir.

Yirmi birinci aşamada iTerm2 ve iki gerçek VS Code penceresinde paket CLI
üzerinden odak/MRU kabulü yapıldı. VS Code'daki bağlı AXSheet'in farklı fiziksel
pencere kimliğinin yanlış odak hatası sayılması giderildi: aynı süreçteki gerçek
AXParent sahipliği denetlenir; başka pencerenin sayfası kabul edilmez. 29 gerçek
uygulama ve 134 sahipli dış kontrol geçti. Bu kapsam tüm uygulamalar veya
fiziksel HID eşdeğerliği değildir.

Yirmi ikinci aşamada ayar aktarımının gerçek Settings sahnesi ve gerçek
NSSavePanel/NSOpenPanel kabulü TR/EN tamamlandı. Üretim seçicileri Settings'e
bağlı, uygulamayı bloklamayan sayfalardır; görünüm kapanınca bekleyen işlem
iptal olur. 58 kontrolde dokuz profil, eylem/istisnalar, iptal/bozuk dosya,
seçili dosyayla pencereyi kapatma ve yeniden açma geçti. Kendi dosya/tercih
alanı, AX ile denetlenen gerçek arayüz ve fiziksel girdi sınırı geliştirme
belgesinde ayrı tutulur.

## Kurulu uygulamada doğrudan REA incelemesi — 7 Kasım 2026

- Kurulu AltTab **11.7.1** universal executable'ının ARM64 dilimi `lipo` ile
  ayrı araştırma dosyasına çıkarıldı; orijinal paket değiştirilmedi.
  Önceki universal hedef engeli bu incelemede aşıldı. REA 6.7.0 / Ghidra
  12.1.4 ARM64 Mach-O'yu açıp makine kodunu çözümledi. Bu, ilk metadata
  incelemesinden farklı olarak işlev gövdelerinin statik tersine mühendisliğidir.
- `0x1000a6948` gövdesinde `_GetProcessForPID` →
  `__SLPSSetFrontProcessWithOptions(..., windowID, 0x200)` → `0x1001ebf14`
  sırası görüldü. `0x1000a5b80` ve `0x1000a63c8` yollarında da aynı ek
  key-window adımı bulunur. Yalnız öne getirme çağrısı klavye odağını garanti
  etmez; MacPocket'ın önceki `WindowSpecificActivation` yolu bu ek adımı
  içermiyordu.
- `0x1001ebf14`, 256 sıfırlanmış bayt içinde 248 baytlık kayıt oluşturup
  `SLPSPostEventRecordTo` çağırıyor. Gözlenen alanlar: uzunluk `0x04=0xf8`,
  olay tipi `0x08=1`, nokta `0x20=(300000,300000)`, bayrak `0x3a=0x10`,
  hedef pencere kimliği `0x3c`. Tek down kaydı var; up çifti yok. Bu yol
  global imleç taşıması veya pencere içeriğine normal tıklama değildir;
  özel WindowServer ABI'sidir ve OS uyumluluğu ayrıca önemlidir.
- Bu kayıt, MacPocket'ın doğrulanmış PID/pencere kimliğiyle çalışan mevcut
  öne getirme yoluna eklendi. ABI kaydı için üç test ve kendi ayrı AppKit
  uygulamamızda gerçek odak denetimi kullanılır. Statik AltTab decompilation'ı
  canlı AltTab davranışı veya tam özellik eşdeğerliği sayılmaz.
- Orijinal executable SHA-256:
  `1e7ff8555e072efbe25caafce60a8e41b0580002ea7aa41a9c032f22820a2d1a`;
  ARM64 dilim SHA-256:
  `d84c3732dac48efc839bd4305a14003c745cc8f23c9f863bba3861dca1f0a7e1`.
  REA Evidence paketi `.build/research/alttab-2026-11-07/rea/rea-evidence.json`,
  snapshot `analysis-snapshot.json` dosyasındadır (12 kayıt). Başlıca kayıtlar:
  `ev_eb9ad42553153edd90d96b842e717a7c2d77cb36b3518cd64007171681fca3f2`
  (olay gövdesi),
  `ev_ef2bcbc6f3d92d6ca9ec55c239531c50895d26b1d81d667ef5429a3a9df90c23`
  (öne getirme sırası). Ghidra pseudocode tür/çağrı prototipleri özgün kaynak
  değildir; gövde ve API sembolleri üzerinde çıkarımdır. Kanıt dışa aktarıldı
  ve REA hedefi kapatıldı.

## Sürümler ve kanıt sınırı

| İnceleme | Kimlik | Kanıt türü |
|---|---|---|
| Resmi son yayımlanan AltTab | `v11.10.1`, 23 Ekim 2026; commit `c500294bdb01186011a5c64a412b04cef9931bef` | GitHub release API ve sabitlenmiş kaynak dosyaları |
| Bu Mac'te kurulu AltTab | `/Applications/AltTab.app`, `com.lwouis.alt-tab-macos`, sürüm/build `11.7.1` | REA `inspect_plist` ve `inspect_macho` |
| MacPocket | Araştırma anındaki çalışma ağacı | Core/App kaynakları ve mevcut testlerin okunması |
| Canlı AltTab arayüzü | Doğrulanamadı | REA kararlı süreç kimliği kuramadı; aşağıdaki sınıra bakın |
| Canlı MacPocket kabulü | Bu araştırmada yapılmadı | Önceki notlar tarihsel kanıttır; güncel kabul yerine geçmez |

[Resmi son sürüm](https://github.com/lwouis/alt-tab-macos/releases/tag/v11.10.1)
ile kurulu sürüm farklıdır. Aşağıdaki ayrıntılı ayarlar `v11.10.1` kaynak
incelemesidir; hepsinin kurulu `11.7.1` binary'sinde bulunduğu iddia edilmez.
29 Ekim tarihli araştırmadaki kurulu sürüm kaydı bugünkü paket kimliği yerine
kullanılmamalıdır.

REA executable SHA-256:
`1e7ff8555e072efbe25caafce60a8e41b0580002ea7aa41a9c032f22820a2d1a`.
Universal binary iki mimari dilimi içerir; incelenen dilim `arm64`.

- Plist Evidence: `ev_c5bf53ee885ae9a04761cba48b8769818934f5ed7a8039e859dc0e882bd5e614`.
- Mach-O Evidence: `ev_d102c17b56950d6357e7cbbb422359689a037680c8c708b7917f4e5d561b625d`.
- Özet görünüm: `ev_a903c602412aed14a2a9b0a8abe4e7425dad5912817d3c29a4b395e0bfbd0eb1`.
- Yerel tam kanıt: `.build/research/alttab-2026-11-06/rea-evidence.json`.
- İncelenen upstream dosyalar ve SHA kayıtları aynı dizinin `reference/` ve
  `source-manifest.json` öğelerindedir; araştırma girdileridir, ürüne katılmadılar.

`observe_native_ui(pid:1797, window_id:220, accessibility:true, screenshot:false)`
çağrısı `process-identity-unavailable` ile reddedildi: süreç başlangıç zamanı
alınamadığından PID yeniden kullanım kontrolü yapılamadı. Ekran görüntüsü veya
AX ağacı alınmadı. Bu, AltTab'ın çalışmadığı veya kullanıcı izninin kesinlikle
eksik olduğu anlamına gelmez. Başka süreç başlatılmadı, kurulu uygulamanın
ayarları ve lisansı değiştirilmedi. REA oturumu kanıt dışa aktarımından sonra
kapatıldı. Mach-O import/export envanteri stripped semboller nedeniyle tam
kapsam garantisi vermez; bu envanter davranış kanıtı olarak kullanılmadı.

## Ücretsiz ve Pro ayrımı

Resmi fiyatlandırma dört Pro grubu gösteriyor. `ProFeature.swift` ve
`PreferenceDefinition.swift` bu ayrımı kaynakta doğruluyor; aramaya geçerek
tuşları bırakma davranışı da arama grubunun Pro parçası.

| Özellik | Ücretsiz | Pro / Pro Lifetime | MacPocket kaynak durumu |
|---|---|---|---|
| Pencere bazlı geçiş ve küçük resim stili | Evet | Evet | Var; gerçek yakalama izin ve kabul gerektirir |
| Aynı uygulama, farklı Space/ekran, gizli/küçültülmüş pencereler | Evet | Evet | Var; Space üyeliği ve bazı durumlar kısmi |
| Tam boy önizleme, açık/koyu, trackpad | Evet | Evet | Kaynakta var; donanım ve canlı kabul ayrı |
| Panelde uygulama/pencere adıyla arama | Hayır | Evet | Var |
| Uygulama simgeleri ve başlık listesi stilleri | Hayır | Evet | İkisi de var |
| Pencere sayısına göre otomatik küçük resim boyutu | Hayır | Evet | Var |
| Ek açma kısayolları, toplam en fazla 9 | Bir açma kısayolu | Evet | En fazla 9, her birinde filtre var |
| Tuşları bırakınca aramaya geç | Hayır | Evet | Ayrı mod yok; mevcut arama doluyken panel açık kalıyor |

Kaynaklar: [fiyatlandırma](https://alt-tab.app/pricing),
[ProFeature.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/pro/ProFeature.swift),
[PreferenceDefinition.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/PreferenceDefinition.swift).

6 Kasım 2026'da görünen fiyatlar: **Pro 9,99 USD** tek ödeme ve mevcut ana sürüm
güncellemeleri; **Pro Lifetime 24,99 USD** tek ödeme ve gelecekteki ana sürümler.
Kişisel lisans üç Mac aktivasyonu kapsıyor. Takım Lifetime lisansı Mac başına
24,99 USD; 2–1000 koltuk, ortak anahtar, cihaz yönetimi ve şirket/VAT faturası
sunuluyor. Deneme 14 gün, iade aralığı 30 gün; deneme sonunda ücretsiz geçiş
çalışmaya devam ediyor. Bölgesel para birimi ve son tutar ödeme ekranında
belirleniyor. [Resmi fiyat ve lisans kapsamı](https://alt-tab.app/pricing).

Pro ve Lifetime arasında geçiş özelliği farkı belirtilmiyor; güncelleme hakkı
farklı. AltTab'ın ödeme, lisans aktivasyonu, deneme ve hesap yönetimi kendi
dağıtım modelidir; MacPocket pencere geçişine eklenmesi gereken işlevler değildir.

## Ayrıntılı işlev envanteri

**Var** yalnız uygulama kodunun mevcut olduğunu, **kısmi** davranış veya seçenek
eksiklerini anlatır. Hiçbiri bu oturumda canlı doğrulandı anlamına gelmez.
Ücretsiz olduğu resmi tabloda tek tek yazılmayan gelişmiş ayarlar aşağıda
**Pro dışı / kaynak** diye belirtilmiştir: incelenen Pro kapıları bu seçenekleri
kapsamıyor; deneme sonrası binary üzerinde ayrıca denenmediler.

### Temel geçiş, klavye ve fare

| AltTab işlevi | Paket | MacPocket karşılığı / açık iş |
|---|---|---|
| Option+Tab ile ileri, Shift ile geri; bırakınca odakla | Ücretsiz | Var: Carbon ileri/geri kayıt, modifier bırakma ve yedek izleme |
| Tuşları bırakınca paneli açık tut | Ücretsiz | Kısayol başına `releaseToChoose=false` var |
| Command+Tab dahil açma kombinasyonunu değiştirme | Ücretsiz | Kısmi: saf Command+Tab açıkça reddediliyor; değiştiricisiz kısayol yok |
| Basılı tutulan tuş ve sonraki pencere tuşunu ayrı kaydetme | Pro dışı / kaynak | Tek `keyCode + modifiers` modeli; iki ayrı kaydedici yok |
| Panel açıkken seç, geri git, iptal et, ara kısayollarını kaydetme | Arama Pro; diğerleri Pro dışı / kaynak | Enter/Escape/Tab/ok ve yazarak arama var; eylem tuşları sabit |
| Pencere kapat, küçült/geri al, tam ekran, uygulamadan çık, gizle/göster | Temel eylemler ücretsiz | Backend eylemleri var; gizleme var, ayrı gösterme komutu yok; kısayollar sabit |
| Kart üzerine gelince kapat/küçült/tam ekran düğmeleri | Ücretsiz | Yalnız kapat düğmesi var; başlık stilinde o da yok |
| Oklarla ve Vim tuşlarıyla gezinmeyi ayrı etkinleştirme | Pro dışı / kaynak | Oklar var; Vim seçeneği ve okları kapatma yok |
| Fare üzerine gelince seçme | Pro dışı / kaynak | Var; başlangıçtaki fare konumunun yanlış seçim yapması engelleniyor |
| İmlecin odağı takip etmesi: asla / daima / ekran değişince | Pro dışı / kaynak | Karşılık bulunmadı |

Kaynaklar: [resmi özellikler](https://alt-tab.app/features),
[ShortcutEditor.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/tabs/controls/ShortcutEditor.swift),
[ShortcutsWhenActiveSheet.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/tabs/controls/ShortcutsWhenActiveSheet.swift),
[AdditionalControlsSheet.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/tabs/controls/AdditionalControlsSheet.swift).

MacPocket kanıtı: [hotkey controller](../../Sources/MacPocketApp/WindowSwitcherHotkeyController.swift),
[kısayol modeli](../../Sources/MacPocketCore/SwitcherConfiguration.swift),
[kart görünümü](../../Sources/MacPocketApp/WindowSwitcherOverlayView.swift).
AltTab eylem listesinde zorla kapatma bulunmadı; normal çıkışla karıştırılmamalı.

### Filtreler, gruplama ve sıralama

| AltTab işlevi | Paket | MacPocket karşılığı / açık iş |
|---|---|---|
| Tüm uygulamalar / aktif / aktif olmayan / imleç altındaki pencereler / imleç altındaki uygulama | Pro dışı / kaynak | Tüm veya öndeki uygulama var; diğer üç kapsam yok |
| Tüm / görünür / görünür olmayan Space'ler | Pro dışı / kaynak | Tüm veya geçerli Space var; kesin Space kimliği/üyeliği modeli yok |
| Tüm ekranlar veya paneli gösteren ekran | Pro dışı / kaynak | Tüm veya fare ekranı var; ekranı bilinmeyen kayıt filtrede kalıyor |
| Küçültülmüş, gizli ve penceresizleri göster / gizle / sona taşı | Pro dışı / kaynak | Göster/gizle var; kategori bazında sona taşı yok |
| Tam ekran pencereleri göster / gizle | Pro dışı / kaynak | Tam ekran eylemi var; görünürlük filtresi yok |
| Uygulama başına bir pencere / tüm pencereler | Pro dışı / kaynak | Ayrı gruplama seçeneği yok |
| Desteklenen sekmeleri tek pencere / ayrı pencere göster | Pro dışı / kaynak | Açık sekme modeli ve ayarı yok; her tarayıcı sekmesi desteği varsayılmaz |
| Son odaklanan / son oluşturulan / alfabetik / Space sırası | Pro dışı / kaynak | Son kullanılan, uygulama ve başlık sırası var; oluşturulma ve Space sırası yok |
| Kısayol başına bağımsız filtre, sıralama ve gruplama | Ek kısayollar Pro | Filtreler bağımsız; sıralama global, gruplama yok |

Kaynak: [ShortcutEditor.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/tabs/controls/ShortcutEditor.swift).
Değerlerin anlamı: [MacroPreferences.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/MacroPreferences.swift).
MacPocket: [WindowListFilter ve WindowFiltering](../../Sources/MacPocketCore/WindowListFilter.swift),
[kısayol ayarları](../../Sources/MacPocketApp/WindowSwitcherSettingsForm.swift).

MacPocket MRU kaydı uygulama aktivasyonu, snapshot'taki öndeki pencere ve kendi
odak işlemlerinden oluşuyor. Her pencere odak değişikliğini izleyen AX observer
bulunmadığından eksiksiz pencere MRU geçmişi kabul edilmemeli.

### Görünüm, yakalama ve animasyon

| AltTab işlevi | Paket | MacPocket karşılığı / açık iş |
|---|---|---|
| Küçük resimler / uygulama simgeleri / başlıklar | Son iki stil Pro | Üçü de var |
| Küçük / orta / büyük / otomatik boyut | Otomatik Pro | Manuel 0,6–1,4 ölçek ve otomatik ızgara var |
| Sistem / açık / koyu tema | Pro dışı / kaynak | Sistem görünümü var; geçiş için ayrı tema seçimi yok |
| Bırakınca odakla / açık tut / ara | Arama modu Pro | İlk ikisi var; açık arama metni bırakınca seçmeyi engelliyor |
| Seçili pencerenin kendi konumunda tam boy önizlemesi | Ücretsiz | Ayrı, tıklamayı geçiren görüntü paneli var; varsayılan kapalı |
| Kısayol başına stil, boyut, tema, bırakma davranışı, önizleme | Pro değerler ayrıca kapılı | Yalnız bırakma davranışı bağımsız; görünüm/önizleme global |
| Paneli aktif / fare / menü çubuğu ekranında göster | Pro dışı / kaynak | Fare ekranına göre konumlandırma var; üçlü seçim yok |
| Pencere başlığı / uygulama adı / ikisi | Pro dışı / kaynak | Sabit kart düzeni; üçlü başlık seçeneği yok |
| Başlığı baştan / ortadan / sondan kısalt | Pro dışı / kaynak | Ayrı tercih yok |
| Durum simgesi, Space numarası, trafik ışıkları ve küçük resmi gizleme | Pro dışı / kaynak | En fazla bir durum glyph'i; ayrı görünürlük ayarları ve Space numarası yok |
| Dock uygulama bildirim rozetini kartta gösterme; sayı/metin için erişilebilir açıklama | Pro dışı / kaynak | Bu araştırmada karşılığı bulunmadı; Space rozetiyle aynı özellik değil |
| Açılma gecikmesi 0–900 ms, panel çıkış ve önizleme giriş animasyonu | Pro dışı / kaynak | 110 ms sabit gecikme, 90 ms panel açılışı; ayrı animasyon ayarları yok |
| Arka planda pencere yakalamayı aç/kapat | Pro dışı / kaynak | Aynı seçenek yok; canlı thumbnail yenileme panel açıkken çalışıyor |

Kaynaklar: [AppearanceTab.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/tabs/appearance/AppearanceTab.swift),
[CustomizeStyleSheet.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/tabs/appearance/CustomizeStyleSheet.swift),
[AnimationsSheet.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/tabs/appearance/AnimationsSheet.swift),
[Preferences.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/Preferences.swift).
Bildirim rozeti ve durumların ayrı çizimi:
[TileView.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/switcher/main-window/TileView.swift),
[StatusIconsView.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/switcher/main-window/StatusIconsView.swift).

MacPocket'ta seçim/liste değişimi açıkça anlık uygulanmış; kayan seçim çerçevesi
yok ([OverlayView](../../Sources/MacPocketApp/WindowSwitcherOverlayView.swift)).
Bu, AGENTS.md'deki animasyonlu kart deneyimi hedefinin açık işidir.

Canlı küçük resimler varsayılan **kapalı**. Açıkken ilk 48 uygun pencere yakalanır,
küçültülmüşler atlanır, her yakalama turundan sonra 1100 ms beklenir; gerçek tur
aralığı yakalama süresini de içerir
([Model](../../Sources/MacPocketApp/WindowSwitcherModel.swift)).
Seçili pencere ilk 48 dışında ise önceliklendirme onu bu kümeye eklemiyor.
Bu nedenle tüm kartların her zaman canlı olduğu söylenemez.

AltTab kaynakta odaklanan pencereyi arka planda önbelleğe alıyor, küçültmeden
geri dönme animasyonu sırasında yakalamayı erteliyor ve kısmi görüntüleri sınırlı
tekrar denemeyle ele alıyor. Bunlar MacPocket için yakalama sağlamlığı işleri;
tek bir ekran görüntüsü testiyle eşdeğerlik kurulamaz.
[WindowThumbnails.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/switcher/state/WindowThumbnails.swift).

### İstisnalar, trackpad, erişilebilirlik ve sistem işlevleri

| AltTab işlevi | Paket | MacPocket karşılığı / açık iş |
|---|---|---|
| Uygulamayı listeden çıkar; açık penceresi yokken çıkar | Pro dışı / kaynak | Uygulama yolu istisnası var; koşullu kural yok |
| Başlıkta belirli metin geçen pencereleri çıkar | Pro dışı / kaynak | Yok; AltTab eşlemesi literal `contains`, regex değil |
| Öndeki uygulamada kısayolu daima / yalnız tam ekranda kapat | Pro dışı / kaynak | Daima kapatma var; tam ekran koşulu yok |
| İstisna için bundle ID öneki kullanma | Pro dışı / kaynak | Listeleme istisnası tam uygulama yolu; aynı kapsam değil |
| Üç/dört parmak yatay/dikey hareket | Ücretsiz; yön ayrıntısı kaynak | Yatay üç/dört parmak var; dikey seçenek yok |
| Trackpad haptik geri bildirimi | Pro dışı / kaynak | Karşılık bulunmadı; donanım kabulü gerekir |
| VoiceOver, Sticky Keys, azaltılmış saydamlık | Ücretsiz vaat | Etiket/duyuru var; gerçek VoiceOver/Sticky Keys kabulü yok; özel düz zemin dalı görünümde bulunmadı |
| CLI: liste, ayrıntılı liste, ID/MRU ile odak, panel aç/kapat | Pro dışı / kaynak | Probe `windows`, `focus`, `thumbnail` var; aynı CLI sözleşmesi yok |
| Başlangıçta açılma, menü simgesi, dil | Pro dışı / kaynak | Uygulama genelindeki karşılıklar ayrı; switcher özgü menü simgesi seçenekleri eşlenmedi |
| Ayarları dışa/içe aktar, sıfırla ve yeniden başlat | Pro dışı / kaynak | Düzeltme: genel ayar aktarımı ilk inceleme sırasında da `switcher.*` anahtarlarını kapsıyordu; bu karşılık ilk araştırmada atlandı. Erişim ve veri bütünlüğü iyileştirmeleri 16. aşamada kaydedildi. |
| Ayarlar içinde arama ve ilgili seçeneğe yönlendirme | Pro dışı / kaynak | AltTab ayar araması kaynakta var; MacPocket araç aramasıyla aynı davranış değil |
| Manuel/kontrol et/otomatik kur güncelleme ve çökme raporu politikası | Pro dışı / kaynak | Uygulama genelindeki güncelleme ayrı; aynı politika seçenekleri eşlenmedi |

Kaynaklar: [ExceptionMatcher.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/switcher/state/ExceptionMatcher.swift),
[MacroPreferences.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/MacroPreferences.swift),
[AdditionalControlsSheet.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/tabs/controls/AdditionalControlsSheet.swift),
[CliEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/events/CliEvents.swift),
[GeneralTab.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/tabs/GeneralTab.swift),
[SettingsSearch.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/preferences/settings-window/SettingsSearch.swift).

AltTab'ın resmi destek kapsamı macOS 12+, Intel/Apple Silicon ve 21 dil.
MacPocket'ın mevcut macOS 27+/Apple Silicon hedefi ve Türkçe/İngilizce kapsamı
korunur; bunlar pencere geçişi eşdeğerliğiyle aynı konu değildir.
[Resmi özellikler](https://alt-tab.app/features).

Erişilebilirlik pencere bilgisi/odak için, Ekran Kaydı küçük resimler için
gerekiyor. Stage Manager küçük resimleri bozabilir veya küçültebilir; simge ve
başlık stilleri alternatif. Bunlar resmi FAQ beyanlarıdır, bu makinede kabul
edilmedi. [FAQ](https://alt-tab.app/faq).

Kaynak GPL-3.0; resmi FAQ, ücretli lisansın dağıtılan imzalı/notarize binary için
olduğunu söylüyor. MacPocket mevcut bağımsız AppKit/AX/ScreenCaptureKit
uygulamasını geliştirebilir; bu araştırmada upstream kodu ürün kaynaklarına
taşınmadı. [Lisans](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/LICENCE.md),
[FAQ](https://alt-tab.app/faq).

“İzleme yok” ifadesi “hiç ağ bağlantısı yok” diye yorumlanmamalı: gizlilik
politikası yerel kullanım sayaçları, güncelleme kontrolleri, isteğe bağlı çökme
raporları ve Pro lisans doğrulamasını ayrı anlatıyor. Lisans aktive edildikten
sonra çevrimdışı kullanım destekleniyor; başarısız periyodik kontrol uygulamayı
kilitlemiyor. [Gizlilik](https://alt-tab.app/privacy), [FAQ](https://alt-tab.app/faq).
Pil/CPU ve gecikme vaatleri bu araştırmada ölçülmedi; pilsiz Mac Studio'da
MacBook pil kabulü yapılamaz.

## MacPocket geliştirme sırası

1. **Kart deneyimini tamamla.** Alt basılıyken Tab/Shift+Tab seçimini animasyonla
   görünür kıl; Reduce Motion davranışını koru. İlk 48 dışındaki seçili karta
   görüntü sağla; küçültülmüş/önbellek durumunu açıkça göster. Canlı görüntü
   varsayılanını, maliyetini ölçerek değerlendir. Hover küçült/tam ekran ekle.
2. **Kısayol modelini genişlet.** Filtrenin yanına bağımsız stil, boyut, tema,
   önizleme, sıralama ve bırakınca arama ekle. Eylem tuşlarını özelleştir.
   Command+Tab desteğini macOS ile birlikte gerçek kabul ederek ele al.
3. **Kapsamı tamamla.** Tam ekran filtresi, sona taşı kategorileri, aktif olmayan
   ve imleç altı kapsamları, uygulama/sekme gruplama; pencere odak gözlemiyle MRU.
   Space kimliği ve görünürlük çıkarımını ayrı modelle; özel API ihtiyacını
   kullanılan uygulama yoluyla birlikte açıkça belgele.
4. **Ayrıntılı tercihler.** Başlık/kısaltma/rozet, ekran konumu, gecikme ve
   animasyon ayarları; başlık bazlı ve tam ekran koşullu istisnalar; Vim,
   imleç takibi, dikey hareket/haptik; ayar aktarımı ve CLI sözleşmesi.
5. **Gerçek kabul ve ölçüm.** Aşağıdaki senaryoları ayrı sonuç kayıtlarıyla
   bitir. Ücretsiz/Pro kapsamını ürün içinde bölmek bu araştırmanın gereği değil.

Bu sıralama teknik değerlendirmedir; AltTab'ın performansının MacPocket'ta
elde edildiği veya her platform sınırlamasının aşıldığı sonucu değildir.

## Kabul matrisi

| Senaryo | Kabul ölçütü | Bu araştırma |
|---|---|---|
| Üç fixture pencereyle Option+Tab / Shift+Tab | Basılıyken odak değişmez; bırakınca seçili pencere gelir; seri tuşlar kaybolmaz | Çalıştırılmadı |
| Hızlı tek basış, Escape, dış tıklama | Doğru önceki pencere / iptal; panel ve kısayol takılı kalmaz | Çalıştırılmadı |
| Aynı uygulamada aynı başlıklı pencereler | ID+PID ile doğru görüntü/odak; her odak değişimi doğru MRU | Çalıştırılmadı |
| İki ekran, iki Space, tam ekran, gizli ve küçültülmüş hedef | Filtre sonucu ve öne getirme her durum için ayrı doğrulanır | Çalıştırılmadı |
| Hareketli içerik, 49+ pencere, hızlı arama/seçim | Seçili kart daima doğru; eski görüntü başka karta taşınmaz; gecikme ölçülür | Çalıştırılmadı |
| İzin verilmemiş / verilmiş / sonradan kaldırılmış | Gerçek kapsam açık; yanlış küçük resim veya sahte başarı yok | Çalıştırılmadı |
| Fixture kapat/küçült/geri al/tam ekran/gizle/çık | Doğru hedef; kayıt diyaloğu ve kapanan pencere yarışları güvenli | Çalıştırılmadı |
| Üç stil, TR/EN, açık/koyu, Reduce Motion/Transparency, VoiceOver/Sticky Keys | Erişilebilir odak, anlaşılır durum ve yerelleştirme | Canlı çalıştırılmadı |
| Dokuz kısayol, çakışma, istisna, yeniden başlatma | Tercihler bağımsız ve kalıcı; çakışmalar açıkça bildirilir | Çalıştırılmadı |
| Fiziksel trackpad | Üç/dört parmak; yatay/dikey; bırakma ve haptik ayrı kabul | Donanım kabulü yok |
| Panel açık/kapalı performansı | Aynı fixture ile CPU, bellek, yakalama ve seçim gecikmesi kayıtları | Ölçülmedi |

Mevcut saf model testleri filtre, arama, seçim, kısayol doğrulama/kalıcılık ve
ızgarayı kapsıyor: [WindowCatalogTests.swift](../../Tests/MacPocketCoreTests/WindowCatalogTests.swift).
İlk araştırma sırasında yeniden çalıştırılmadılar; sonraki uygulama/test sonuçları
geliştirme belgesindedir. Saf testler gerçek HID, AX, Space ve yakalama
kabulünü kanıtlamazlar. İlk araştırmadaki değişiklik yalnız belgelerdi. Yerel belge bağlantıları
ve `git diff --check` geçti. `scripts/check-localizations.sh`: 4076 anahtar,
0 eksik İngilizce çeviri, 0 biçim uyuşmazlığı; kısayol kaydedicisinde 9 anahtar,
0 eksik Türkçe çeviri ve 0 biçim uyuşmazlığı.
