# Disk Röntgeni

Durum: ilk sürüm, Mac Studio (macOS 27.2.1, pilsiz) üzerinde geliştirildi ve doğrulandı. Referans yok: işlev,
kamuya açık özellik tarifine bakılarak ve bu Mac'teki gerçek konumlar ölçülerek bağımsız yazıldı.

## Ne yapar

“Sistem Verisi” olarak görünen alanın içini açar. Her kalem gerçek boyutuyla (`st_blocks`, sabit bağlar bir kez),
açıklaması, geri gelme maliyeti (yeniden oluşur / yeniden indirilir / bir daha gerekmez / geri gelmez) ve rozetiyle
(**Güvenli**, **İncele**, **Elle**) listelenir.

| Grup | Kaynak |
| --- | --- |
| Xcode, Simülatörler | Sabit konumlar; `xcrun simctl runtime list -j` ve `simctl list devices -j` |
| Paket yöneticileri, araç zincirleri | Sabit konumlar (brew, npm, pnpm, yarn, pip/uv, CocoaPods, Gradle, Cargo, Go, Maven, Bun/Deno, nvm, rustup, pyenv, conda, editör eklentileri) |
| Yapay zekâ | Hugging Face, LM Studio, PyTorch, Claude VM paketleri, Chrome yerel modeli, kodlama oturum kayıtları; `ollama list` (model başına satır, `ollama rm`) |
| Günlükler, geçici dosyalar, Çöp | `~/Library/Logs`, sistem tanılama raporları, kullanıcı geçici klasöründe 3 günden eski dosyalar |
| Time Machine | `tmutil listlocalsnapshots /` (boyut bildirilmez; `tmutil deletelocalsnapshots <tarih>`, yönetici) |
| Docker | `docker system df`; derleme önbelleği, imajlar, konteynerler, birimler ayrı satır ve ayrı `prune` komutu |
| Sanal makineler, iOS yedekleri, Android | Parallels, Fusion, VirtualBox, UTM, Tart (elle); yedek başına aygıt adı ve tarih; AVD ve SDK bileşenleri |
| Projeler | `Developer`, `Projects`, `Code`, `dev`, `Desktop`, `Documents` altında `node_modules`, `.build`, `Pods`, `target`, `.next`… Boşta kalma süresi projenin kendi dosyalarından, kilit dosyaları ve `npm install` sayılmadan |
| Diğer büyük klasörler | Başka hiçbir satırın açıklamadığı büyük klasörler; sahibi paket kimliğinden (“X’e ait” / “Y tarafından bırakıldı, artık kurulu değil”) |

Bilinçli olarak dışarıda: Masaüstü, Belgeler, İndirilenler, Fotoğraflar, Müzik, Filmler, iCloud Drive (Depolama
ayarları bunları Sistem Verisi saymaz; iCloud'un soğuk önbellekte dakikalar sürebilen ölçümü de riskli).
Proje klasörleri kullanıcının işidir; yalnız içindeki derleme klasörleri raporlanır.

## Silme güvenliği

- Her silme mevcut `FileTrashService` ve `AdministratorRemover` üzerinden geçer: kanonik yol, sembolik bağ reddi, korumalı
  kökler, kimlik doğrulaması ve tek yönetici istemi.
- Onay, ayrı bir pencere değil sayfanın içinde, alt kenarda açılan bir paneldir (seçili satırlar görünür kalır); çalışacak her işlemi birebir gösterir (`rm -rf -- '…'`, `xcrun simctl runtime delete <id>`), geri
  gelmek için internet isteyen toplamı ve yönetici gerektiren işlem sayısını söyler; **Planı Kopyala** ile panoya alınır.
- Elle (manual) kalemler onay listesine hiç giremez. Sahibi uygulaması açık olan kalem atlanır.
- Komutlar kabuk olmadan, argüman dizisiyle çalışır; yönetici sürümü `osascript` ile, argümanlar kaçışlı.

## Geçmiş ve otomasyon

Geçmiş `~/Library/Application Support/MacPocket/system-data-history.json` dosyasındadır (6 ay, yalnız boyut ve yol).
“Neyin değiştiğini hatırla” kapatılırsa dosya silinir. Otomasyon (hepsi kapalı başlar): günlük tarama, düşük alan uyarısı
(aşağı inerken bir kez), olağandışı büyüme (son 14 taramanın ortancasından ≥%50 ve ≥2 GB), haftalık özet (>2 GB), haftalık
otomatik temizlik (yalnız Güvenli, parola istemeyen, sahibi kapalı kalemler; izlenen taramada çalışmaz).

## Sil yerine küçült (şeffaf sıkıştırma)

Yalnızca okunan klasörler (proje derleme çıktıları, araç zincirleri, Xcode arşivleri, SDK bileşenleri) için. Dosyalar macOS'un
kendi dosyalarını sakladığı gibi, şeffaf APFS sıkıştırmasıyla yerinde saklanır: hiçbir şey silinmez ve hiçbir yol değişmez.

Dosya dosya, yerinde çalışır; bu yüzden klasörün tamamı için değil, yalnızca en büyük dosyanın bir sıkıştırılmış kopyası kadar
boş alan gerekir. Her dosya yanına gizli bir geçici dosya olarak `ditto --hfsCompression --noclone` ile yazılır. (`--noclone`
şarttır: onsuz ditto APFS'te dosyaları klonlar ve hiçbir şey sıkıştırılmaz. macOS'un kendi dosyalarındaki gibi LZVN kullanılır.)
Kopya orijinalle boyut, izin, tarih ve içerik açısından karşılaştırılır (128 MB'a kadar bayt bayt, büyükler beş pencereden);
orijinal bu sırada değişmediyse `rename` ile yerine konur. Klasör içindeki sabit bağlar korunur: bir dosyanın bütün adları aynı
sıkıştırılmış kopyaya yeniden bağlanır (Rust `target/debug/deps` içinde dosyaların çoğu sabit bağlıdır; bu yüzden eski sürüm
bu klasörü reddederdi). Dışarıyla paylaşılan sabit bağlar ve APFS klonları (`ATTR_CMNEXT_CLONE_REFCNT` > 1), 64 KB'tan küçükler,
10 dakikadan yeni değişenler, zaten sıkıştırılmışlar ve %10'dan az kazandıranlar olduğu gibi bırakılır. Klasörde `cargo`,
`rustc`, `swift-build`, `xcodebuild`, `gradle`, `node` gibi bir derleme aracı çalışıyorsa (`BuildActivity`, çalışma dizini
projenin içindeyse) hiçbir şeye dokunmadan reddedilir. Bir kopya doğrulanamazsa tüm işlem durur ve orijinal olduğu gibi kalır;
iptalde her dosya ya bütündür ya sıkıştırılmıştır. Çökmüş bir koşudan kalan geçici dosyalar bir sonraki koşuda temizlenir.

“Tahmin” gerçek dosyalardan örnek alıp geçici klasörde sıkıştırarak kazancı önceden söyler; klasöre dokunmaz.

Gerçek ölçümler (bu Mac, Rust `target` klasörü): `target/release` 4,83 GB → 2,15 GB (2,68 GB kazanç, 15 sn, 9 619 dosyanın SHA-1'i
önce/sonra birebir aynı, geride geçici dosya yok). 188 GB'lık `target` için tahmin: ~183 GB uygun, ~142 GB kazanç.

## Sil yerine arşivle

Küçültme uygun olmayan tek klasörler için ikinci yol: klasör yanındaki `.MacPocket Archives` içine zip olarak alınır, `unzip -t`
ile doğrulanır, paketlenirken değişmediği kontrol edilir ve ancak sonra kaldırılır. “Arşivler” listesinden geri yüklenir.

## Diğer

- **Harici disklerdeki projeler** (Projeler sekmesinde, kapalı başlar): yalnız takılı, yazılabilir, yerel diskler; Time
  Machine, ağ, salt okunur ve dahili diskler asla taranmaz.
- **Mac kapanırken simülatörleri kapat** (Otomasyon sekmesinde, açık başlar): `willPowerOff` bildiriminde `simctl shutdown all`.
- **Menü çubuğu öğesi** (Otomasyon sekmesinde, kapalı başlar): simge, Sistem Verisi boyutu veya boş alan; son taramanın değeri,
  kendiliğinden tarama yapmaz. Uygulamanın ana menü çubuğu yapılandırmasından bağımsız kendi `NSStatusItem`'ıdır.
- **Widget** (küçük ve orta, `MacPocketWidget` uzantısı): son taramanın Sistem Verisi, güvenle boşaltılabilir ve boş alan
  değerleri. Korumalı alanda çalışır ve yalnızca uygulamanın tarama sonrası yazdığı
  `~/Library/Application Support/MacPocket/system-data-summary.json` dosyasını okuyabilir (tek dosyalık okuma istisnası);
  sağlama profili gerekmez. `scripts/embed-widget.sh` `build-app.sh` içinden uzantıyı derleyip imzalar; başarısız olursa
  uygulama widget'sız paketlenir. Widget kendisi hiçbir şey ölçmez; boş durumda “Henüz tarama yok” gösterir.
- **Bildirimler** tıklanınca ilgili sekmede Disk Röntgeni açılır.
- **Shortcuts eylemleri:** “Sistem Verisi Boyutunu Al” ve “Güvenli Sistem Verisini Temizle” (`SystemDataIntents.swift`).
  SwiftPM Xcode'un App Intents meta veri adımını çalıştırmadığı için `scripts/build-app.sh` derlemenin ürettiği sabit değer
  dosyalarından `appintentsmetadataprocessor` ile `Metadata.appintents` üretir ve pakete koyar.
- **Betik:** `swift build --product macpocket-probe` ile üretilen `macpocket-probe system-data …` (uygulama paketine konmadı).
- **Yönetici parolası:** `tmutil deletelocalsnapshots` önce kullanıcı olarak denenir (bu macOS'ta parolasız çalışır); parola
  yalnızca bu başarısız olursa istenir.

## Kullanım deneyimi

Ölçülen ve doğrulanan (kanıt: `--audit-system-data` denetimi, 43 kontrol, gerçek ekran pikselleri, birim testleri):

- **Hız hissi:** gerçek Mac'te ilk öğe 0,01 sn'de ekranda; tarama 16 sn sürer ve bu sürede belirli ilerleme çubuğu, “Aşama 2/5”, taranan dosya sayısı ve o an ölçülen yer görünür; sonuçlar akarak dolar. Dört art arda taramada bellek artışı ~5 MB (sızıntı yok).
- **Tek dokunuş:** “Güvenlileri Temizle…” yalnızca Güvenli, parola istemeyen, sahibi kapalı kalemleri seçip onayı açar; “İncele” kalemleri asla teklif edilmez.
- **Güvenli varsayılan:** kalıcı silmede Return **iptal eder**, silmek tıklama veya ⌘⌫ ister (gerçek tuş olaylarıyla sınandı); Çöp'e taşımada Return onaylar.
- **Klavye:** ⌘F arama, ⌘R yeniden tara, ⌘. durdur; satırın metnine tıklamak seçer.
- **Erişilebilirlik:** gerçek erişilebilirlik ağacında 55 denetimin hepsinin adı var; satır eylemleri (ayrıntı, Finder, gizle, küçült, arşivle) hiç gizlenmez, yalnızca soluk durur; Hareketi Azalt'a uyulur.
- **Kontrast:** rozet ve ikincil metin renkleri iki temada WCAG AA (4,5:1) için ölçüldü ve testli: rozetler 7,2–9,4:1 (sistem renkleriyle 2,1–3,0:1 idi), ikincil metin 5,96:1 açık, 6,98:1 koyu (sistemin `.secondary` rengi açıkta 3,95:1).
- **Pencere genişliği:** 760, 1000 ve 1400 noktada hiçbir denetim pencerenin dışına taşmaz; kartlar genişliğe göre 3/2/1 sütuna iner (sonsuz/NaN genişlikte çökme düzeltildi ve testli).
- **Arama:** Türkçe harfler düz harflerle bulunur (“kayit” → “kayıt”, “ISTANBUL” → “İstanbul”), kelime sırası önemsizdir.
- **Dürüstlük:** okunamayan yerler sayıyla bildirilir; silmeden sonra boş alan yeniden taramadan güncellenir; sayfa son durumunu (sekme, sıralama, açık gruplar) hatırlar.
- **İngilizce:** paketlenmiş uygulama İngilizce çalıştırıldı, 43 kontrol geçti, çoğullar doğru.

Kanıtlanamayan (elle yapılacaklar için bkz. SYSTEM_DATA_UX_CHECKLIST.md): gerçek kullanıcılarla kullanılabilirlik testi, VoiceOver ile elle okuma (ağaç NSAccessibility üzerinden okundu, VoiceOver duyulmadı), dar ekranlarda dokunmatik kullanım ve altı aydan uzun geçmişin etkisi. “En iyi deneyim” öznel bir iddiadır; burada yalnızca ölçülebilen kısımları garanti edilmiştir.

## Doğrulama (AGENTS.md ayrımıyla)

**Uygulanan kod:** Core `SystemData/` (model, katalog, ayrıştırıcılar, tarayıcı, keşif, harici diskler, planlayıcı, silme,
arşivleyici, geçmiş, otomasyon, döküm, simülatör kapatma) ve uygulama görünümü, modeli ve otomasyon servisi.

**Testler:** Swift Testing ile Core'da yüzü aşkın test. Gerçek geçici dosyalarla silme ve arşivleme (sembolik bağ, izin,
yaş filtresi, meşgul uygulama, doğrulama hatası, paketlerken değişim, sabit bağ); sahte ev ve sistem köküyle tarama yalıtımı;
gerçek süreç hattı: `docker`/`ollama` yerine geçen betiklerle gerçek `BoundedProcess` ve tam argüman doğrulaması; iOS yedeği
fixture'ı; **gerçek `simctl` ile** geçici simülatör oluşturup komut yoluyla silme, açıp `shutdownAll` ile kapatma.

**Canlı (bu Mac):** `macpocket-probe system-data` gerçek diskte 47 kalem buldu; en büyük 14 kalemin boyutu `du -skx` ile
eşleşti. DEBUG `--audit-system-data <klasör>` sahte ev klasöründe arayüzü baştan sona çalıştırır (tara, seç, onay, sil,
arşivle, geri yükle, geçmiş; 23 kontrol) ve ekran görüntüsü alır.

**Gerçek araçlarla (bu Mac):**
- `tmutil`: gerçek yerel anlık görüntü oluşturuldu, tarayıcı buldu, komut yoluyla parolasız silindi, kayboldu.
- Docker Desktop açıldı; gerçek `docker system df` çıktısı ayrıştırıldı ve tarayıcının satırları (images 1,945 GB, volumes
  1,47 GB) çıktıyla eşleşti. Hiçbir şey budanmadı. Ardından uygulama kapatıldı.
- `simctl`: geçici aygıt oluşturma/silme, simülatör açma ve `shutdownAll`.

**Kaynaktan doğrulanan (araç kurulu değil):** Ollama `list` biçimi resmî `cmd.go` ve `format/bytes.go` kaynağından
alındı (dört boşluk dolgusu, ondalık birimler, bulut modellerde boyut `-`) ve testlere sabitlendi. Ollama ≥10 birimlerde
tam sayıya yuvarlar; model boyutları bu yüzden yaklaşıktır.

**Widget ve menü çubuğu:** widget görünümü ve sağlayıcısı testli ve PNG'ye çizildi; paket derlemesi imzalı uzantıyı içeriyor ve
derin doğrulamadan geçiyor; kurulu MacPocket ile çakışmayan geçici bir kimlikle kaydedilince `pluginkit` uzantıyı
`com.apple.widgetkit-extension` noktasında listeledi (sonra kayıt silindi). Menü çubuğu öğesi gerçek `NSStatusItem` ile testli.

**Doğrulanmadı / yok:**
- Yönetici parolası penceresi (osascript, parola gerektirir; komut ve kaçışlama testli, pencere denenmedi) ve
  parolasız silinemeyen bir anlık görüntü.
- Gerçek Ollama (kurulu değil), gerçek iOS yedeği (yok).
- Shortcuts uygulamasında eylemlerin görünmesi ve widget'ın masaüstü/Bildirim Merkezi galerisinde çizilmesi: uygulama
  kurulmadığı için görülmedi (meta veri, kayıt, görünüm ve mantık testli).
- MacBook/OLED'e özgü hiçbir şey.
