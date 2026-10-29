# MacPocket ürün kapsamı

28 Ekim 2026 tarihinde kullanıcı tarafından belirlenen kapsam.
Hedef, aşağıdaki işlevleri tek bir native macOS uygulamasında birleştirmektir.
Bu belge gereksinimleri tanımlar; özelliklerin tamamlanmış olduğunu ifade etmez.

## Ürün genelinde kapsamlı özelleştirme

Kullanıcının isteği doğrultusunda tüm modüller ayrıntılı seçenekler sunar.
Görünüm, menü çubuğu, veri/grafik sunumu, kısayollar, bildirimler, güç profilleri,
otomasyon ve bakım tercihleri ayrı ayrı özelleştirilebilir.

Aranabilir ayarlar, hazır profiller, profil oluşturma/kopyalama, modül bazında
varsayılana dönme ve ayarları dışa/içe aktarma ortak kapsamın parçasıdır.
Sık kullanılan seçenekler hızlı erişimde, ayrıntılı tercihler ilgili modülün
gelişmiş ayarlarında yer alır. Donanımın desteklemediği seçenekler gerekçesiyle
gösterilir. Ayrıntılar [özelleştirme belgesindedir](CUSTOMIZATION.md).

## Sistem izleme — iStat referansı

| Alan | Kapsam |
| --- | --- |
| CPU | Toplam ve çekirdek bazında kullanım, user/system/idle ayrımı, geçmiş grafiği |
| RAM | Kullanım bileşenleri, bellek baskısı, compressed memory ve swap |
| Disk | Volume kapasitesi, kullanılan/boş alan, mevcut sürücü istatistiklerine göre okuma/yazma aktivitesi |
| Power management | MacBook odaklı gelişmiş pil sağlığı/enerji izleme, geçmiş, şarj yönetimi, güç profilleri ve otomasyon |

iStat referansından seçilen alanlar CPU, RAM, disk ve power management'tır.
Her ölçümün birimi, örnekleme aralığı ve destek durumu açık olmalıdır.
Henüz oluşmamış ilk CPU örneği veya okunamayan değer sıfır kullanım gibi gösterilmez.

## MacBook odaklı gelişmiş güç yönetimi

Güç yönetimi, MacPocket'ın ana modüllerinden biridir. Kullanıcı özellikle
MacBook'lar için kapsamlı izleme ve aktif yönetim istediğini netleştirdi.

- Pil yüzdesi, şarj/deşarj hızı, kalan süre tahmini ve adaptör bilgisi.
- Pil sağlığı, döngü sayısı, tasarım/tam dolum kapasitesi ve aşınma eğilimi.
- Donanımın sağladığı enerji/sıcaklık verileri, termal durum ve tüketim analizi.
- Saatlik/günlük geçmiş; uyku sırasında pil kaybı ve şarj oturumu raporları.
- Şarj yüzdesi sınırı, şarjı durdurma/başlatma ve tek seferlik tam şarj hedefi.
- Pil ve adaptör için ayrı güç profilleri; desteklenen düşük/otomatik/yüksek güç modları.
- Adaptör, pil seviyesi, saat ve doğrulanmış termal olaylara bağlı kullanıcı kuralları.
- Tools'taki Mac'i Uyanık Tut ile ortak uyku yönetimi ve durum gösterimi.

Ayrıntılı gereksinimler, destek durumları ve kabul ölçütleri
[Power Management belgesindedir](POWER_MANAGEMENT.md).

İzleme, uyku engelleme, sistem güç ayarları ve donanıma şarj komutu gönderme
ayrı yeteneklerdir. Kontrol desteği cihaz modeli, macOS sürümü ve kullanılabilir
backend ile belirlenir. Pil bulunmayan cihazda şarj denetimleri desteklenmiyor
durumunu gösterir. Şarjı durdurma, adaptörden çalışmaya devam ederken pili şarj
etmeyi durdurmak olarak tanımlanır; zorla deşarj ayrı bir özelliktir.

Bu geliştirme Mac'inde pil bulunmuyor. Şarj sınırının uygulanması, manuel
durdurma, yeniden başlatma ve uyku/uyanma sonrası davranış MacBook üzerinde
doğrulanmalıdır. Apple'ın yerleşik şarj limiti ve uygulama içi kontrolün
erişilebilirliği için [teknik bulgulara](research/2026-10-28-initial.md) bakın.

## Tools

### CleanMyMac My Tools kataloğu

Kullanıcı önceki CCleaner adını **CleanMyMac** olarak düzeltti. Güncel bakım ve
Tools referansı, bu Mac Studio'da kurulu CleanMyMac 5.7.2 Setapp sürümüdür.
My Tools içindeki 21 araç canlı arayüzde ve yerel kaynaklarla eşleştirildi.

MacPocket Tools; aranabilir araç kartları, favoriler, kategori filtreleri,
özelleştirilebilir sıra ve ilgili işleme doğrudan giriş sunar. Uygulama
kaldırma/güncelleme gibi işlevler kendi modülleriyle ortak servislere bağlanır.
21 aracın Türkçe karşılığı, hedefi ve yerel servis/ek entegrasyon ayrımı
[CleanMyMac Tools belgesinde](CLEANMYMAC_TOOLS.md) yer alır.

Katalog doğrulaması, araçların algoritmalarının MacPocket'ta hazır olduğu
anlamına gelmez. Browser Care, Email Cleanup ve Malware Finder kapsamda ayrı
entegrasyon veya motor gerektiren işlevlerdir.

### Window Switcher / AltTab

Pencere geçişi **Tools** bölümünde yer alır.

- Uygulama yerine açık pencere bazında listeleme.
- Son odaklanan pencereye göre sıralama ve ileri/geri klavye gezinmesi.
- Pencere başlığı ve uygulama ikonu; destek ve izin durumuna göre thumbnail.
- Seçilen pencereyi öne getirme; küçültülmüş pencereyi geri açma.
- Kısayol ayarı, seçimi iptal etme ve izin durumlarının anlaşılır gösterimi.
- Farklı Space, tam ekran, gizli uygulama ve kapanmış pencere durumlarının ayrı testi.

Pencere geçişi için Accessibility, thumbnail için Screen Recording yetenekleri
ayrı ele alınır. AltTab ile aynı Space kapsamı, özel sistem API'leri ve canlı
doğrulama gerektiren bir araştırma konusudur.

### Mac'i Uyanık Tut

Mac'in otomatik uykuya geçmesini geçici olarak engelleyen araç **Tools**
bölümünde yer alır.

- Tek hareketle başlatma ve durdurma.
- Belirlenen süre boyunca veya kullanıcı durdurana kadar açık tutma.
- Ekranı da açık tutmayı ayrı bir seçenek olarak sunma.
- Etkin durumu ve varsa kalan süreyi Tools ve menü çubuğunda gösterme.
- Süre dolduğunda, kullanıcı durdurduğunda veya uygulama kapandığında uyku
  engelini kaldırma.

Bu araç, güç yönetimindeki uyku kontrolüyle ortak `SleepController` kullanır.
Tools ve güç yönetimi aynı etkin oturumu ve kalan süreyi gösterir.
Doğrulama; süre bitimi, manuel durdurma, ekran seçeneği ve uygulama kapanışında
uyku engelinin serbest bırakılmasını kapsar.

## Sistem merkezi ve Görev Yöneticisi

Kullanıcı, terminalde erişilebilen ayrıntılı gözlemleri ve sistem araçlarını
arayüzden kullanmak; Windows Görev Yöneticisi benzeri süreç izleme ve uygulama
sonlandırma istedi. Sistem merkezi bu ek kapsamı karşılar.

- **Sistem İzleme:** CPU/RAM/disk yanında memory pressure, swap, termal durum,
  güç/uyku engelleri, ağ ve erişilebilen süreç bilgileri.
- **Sistem Araçları:** salt okunur tanı raporları, destek/izin durumu ve sonuç
  geçmişi; sistemi değiştiren bakım araçlarından ayrı yürütme.
- **Görev Yöneticisi:** arama/sıralama/filtreleme, süreç ayrıntıları, normal
  sonlandırma ve açıkça seçilen zorla sonlandırma; PID ve süreç kimliği doğrulaması.

Ayrıntılı izleme, işlem ve doğrulama kapsamı
[Sistem Merkezi belgesindedir](SYSTEM_CENTER.md). Mac Studio üzerinde geçerli
işlevler burada canlı doğrulanır; MacBook pil kontrollerinin donanım kabulü
MacBook'a kurulumdan sonra yapılır.

## Temizlik, disk analizi ve uygulama bakımı — CleanMyMac referansı

| Alan | Kapsam |
| --- | --- |
| Temizlik | Önbellek, geçici dosya ve log adaylarını kategorileri ve boyutlarıyla tarama; seçilen öğeler için uygulanabilir temizlik planı |
| Disk izleme ve analiz | Kapasite eğilimi, klasör/dosya alan kullanımı ve büyük dosyalar; sistem izleme ile ortak disk veri kaynağı |
| Tam uygulama kaldırma | App bundle, ilişkili destek/tercih/cache dosyaları, login item ve helper adayları; kaldırılabilen, paylaşılan ve erişilemeyen öğeler için sonuç |
| Uygulama güncelleme | Kurulu uygulamaların sürüm ve kurulum kanalını belirleme; desteklenen kanallarda güncelleme bulma ve uygulama |

Tarama ile dosya değiştirme ayrı işlemlerdir. Kaldırma planı uygulamanın bundle
kimliğini ve ilişkili öğenin sahiplik kanıtını kullanır. Ortak App Group veya
üretici klasörleri başka uygulamaları etkileyebileceği için ayrı değerlendirilir.
Disk boyutu hesabında APFS paylaşımlı alan, hard link, erişim hataları ve iptal
durumu hesaba katılır.

Güncelleme kanalları Homebrew, Sparkle, App Store, Setapp/üretici ve bilinmeyen
olarak ayrılır. Her uygulama için tek bir evrensel güncelleme yöntemi varsayılmaz.
CleanMyMac App Updater referans alınır; her kurulum kanalı için MacPocket'ın
güncelleme sağlayıcısı ayrıca uygulanır ve doğrulanır. Önceki CCleaner paket
incelemesi tarihsel kayıttır ve güncel referans olarak kullanılmaz.

## Geliştirme temeli

Önerilen uygulama: Swift + SwiftUI/AppKit. Okuma servisleri ve sistem üzerinde
değişiklik yapan servisler ayrı arayüzlerle geliştirilir.

| Modül | Sorumluluk |
| --- | --- |
| SystemMetrics | CPU/RAM örnekleme ve zaman serisi |
| ProcessMonitor | Süreç envanteri, kaynak kullanımı ve doğrulanmış süreç sonlandırma |
| SystemDiagnostics | Sınırlandırılmış salt okunur sistem tanıları ve raporları |
| StorageMonitor | Volume kapasitesi ve disk I/O; tarama modülleriyle ortak kimlikler |
| PowerTelemetry / BatteryHealth | Pil, adaptör, enerji ve termal telemetri; sağlık göstergeleri |
| ChargingController / PowerModeController | Donanım ve macOS desteğine göre ayrı şarj/güç kontrolleri |
| PowerPolicyEngine / PowerHistoryStore | Profiller, çakışma çözümü, otomasyon ve yerel geçmiş |
| SleepController | Tools ve güç yönetimi için ortak uyanık tutma oturumu, süre ve ekran seçeneği |
| WindowSwitcher | Pencere keşfi, MRU, kısayol, odaklama ve thumbnail |
| CleanupPlanner / CleanupExecutor | Tarama sonucundan plan üretme ve seçilmiş planı uygulama |
| ApplicationInventory / UninstallPlanner | Uygulama kimliği, ilişkili dosya adayları ve kaldırma planı |
| UpdateCoordinator | Kanal bazlı güncelleme sağlayıcıları ve sonuçları |
| SettingsStore / ProfileStore | Ortak ayarlar, modül/cihaz tercihleri, sürümlü profiller ve içe/dışa aktarma |

Geliştirme sırası:

1. CPU/RAM/disk/power okuma, süreç/sistem tanıları, uygulama envanteri, ortak ayar/profil altyapısı ve gerçek verilerle native uygulama temeli.
2. MacBook güç merkezi: sağlık/geçmiş, profiller ve uyku yönetimi; şarj backend'i için erken donanım doğrulaması.
3. Desteklenen MacBook'ta aktif şarj/güç kontrolleri ve otomasyonun uçtan uca testi.
4. Görev Yöneticisi ve Sistem Merkezi; Tools içindeki pencere geçişi, CleanMyMac araç kataloğu ve ortak Mac'i Uyanık Tut erişimi.
5. Temizlik, alan analizi ve tam kaldırma planları; ardından seçilen planların uygulanması.
6. Kanal bazlı uygulama güncelleme.

Bu sıra, şarj kontrolü dahil kapsamın tamamını korur. Desteklenmeyen özellikler
uygulanmış gibi gösterilmez; her aşamada gerçek donanım ve izin durumları denenir.

## Native kalite hedefi

Apple macOS deneyimi; Liquid Glass destekli gezinme, native menüler/toolbar,
klavye kullanımı, Ayarlar, oturum açılışında başlatma ve pencere/menü çubuğu
yaşam döngüsü ürün gereksinimidir. Mevcut temel ve doğrulama durumu
[NATIVE_MACOS.md](NATIVE_MACOS.md) içindedir. Tüm modüller bu standarda göre
tamamlanacaktır; hazır olmayan işlevler kullanılabilir gibi gösterilmez.
