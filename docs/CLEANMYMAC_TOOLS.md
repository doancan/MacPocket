# CleanMyMac My Tools → MacPocket Tools

Durum: **0.3.0** native Tools kataloğunda macOS’a özel ek araçlar, altı kategori, arama ve
kalıcı favoriler vardır. Dosya, uygulama ve Homebrew servisleri aşağıda belirtilen
kapsamda çalışır. Bakım Görevleri yalnız salt okunur raporları açar. Giriş/arka plan
öğeleri macOS ayarına yönlendirir. Hazır olmayan servisler kartlarda belirtilir.
Kullanıcı CCleaner adını CleanMyMac olarak düzeltti ve My Tools bölümünü istedi.

Referans, Mac Studio'da kurulu **CleanMyMac 5.7.2 Setapp** sürümüdür.
My Tools kataloğu üstten alta canlı arayüzde kontrol edildi; 21 araç yerel
localization kaynakları ve [resmi My Tools listesiyle](https://macpaw.com/support/cleanmymac/knowledgebase/my-tools)
eşleştirildi. Algoritma, sonuç doğruluğu ve sistem üzerinde işlem yürütme
her araç için ayrıca doğrulanacaktır. Her satırın uygulama durumu hazır olan kapsamı ayrıca belirtir.

## Araç eşlemesi

AI Clutter kullanıcı isteğiyle kapsam dışındadır. Diğer satırlar istenen ürün kapsamına dahildir. "Yerel servis" MacPocket içinde
geliştirilecek işlevi; "ek entegrasyon" ayrıca hesap, tarayıcı bileşeni veya
tespit motoru gerektiren işlevi belirtir.

| Referans | MacPocket karşılığı | Hedef işlev | Uygulama durumu |
| --- | --- | --- | --- |
| AI Clutter | — | — | Kullanıcının 29 Ekim isteğiyle kapsamdan ve arayüzden kaldırıldı |
| App Leftovers | Uygulama Kalıntıları | Kaldırılmış uygulamaların ilişkili öğelerini bulma | Dahil; yerel servis planlandı |
| App Updater | Uygulama Güncelleme | Kanal bazlı sürüm kontrolü/güncelleme | Homebrew yerel katalog kontrolü ve ayrı onayla cask upgrade; diğer kanallar bekliyor |
| Application Permissions | Uygulama İzinleri | İzin durumlarını inceleme ve izin yönetimine erişim | Dahil; sistem desteği doğrulanacak |
| Background Items | Arka Plan Öğeleri | Arka plan görevlerini inceleme/yönetme | macOS Giriş Öğeleri / arka plan ayarına yönlendirme |
| Browser Care | Tarayıcı Bakımı | Chrome sekmelerini kaynak kullanımıyla inceleme | Dahil; tarayıcı entegrasyonu gerekli |
| Downloads | İndirilenler | İndirilmiş dosyaları inceleme/ayıklama | Çalışıyor: seçilen Downloads kapsamını tarama ve onaylı Çöp |
| Duplicate Finder | Yinelenen Dosyalar | İçerik eşleşmesiyle kopyaları bulma | Çalışıyor: taramada tutulan dosyalar arasında SHA-256 eşleşmesi |
| Email Cleanup | E-posta Temizliği | Hesap üzerinden e-posta düzenleme | Dahil; hesap entegrasyonu gerekli |
| Large and Old Files | Büyük ve Eski Dosyalar | Boyut/yaş filtreleriyle alan analizi | Çalışıyor: boyut/yaş filtreleri ve onaylı Çöp |
| Login Items | Giriş Öğeleri | Oturum açılışındaki öğeleri inceleme/yönetme | macOS Giriş Öğeleri ayarına yönlendirme; MacPocket kaydı kendi Ayarlarında |
| Mail Attachments | Mail Ekleri | Yerel e-posta eklerini inceleme | Dahil; erişim ve ilişkilendirme doğrulanacak |
| Maintenance Tasks | Bakım Görevleri | Desteklenen bakım işlerini tek yerde toplama | Sekiz salt okunur rapor; bakım mutasyonları bekliyor |
| Malware Finder | Zararlı Yazılım Taraması | Bulgu üreten tarama ve inceleme | Dahil; tespit motoru/veri kaynağı gerekli |
| Privacy Items | Gizlilik İzleri | Seçilen etkinlik/tarayıcı izlerini inceleme | Dahil; kaynak bazlı servis geliştirilecek |
| Screen Cleaning Mode | Ekran Temizleme Modu | Girişi geçici kilitleyip fiziksel temizliği kolaylaştırma | Dahil; giriş/izin entegrasyonu gerekli |
| Similar Images | Benzer Görseller | Benzerlik adaylarını karşılaştırmalı inceleme | Dahil; görsel analiz servisi gerekli |
| System Junk | Sistem Gereksiz Dosyaları | Cache/log ve diğer adayları kategorileme | Çalışıyor: kullanıcı cache/log klasörü taraması ve seçili Çöp; otomatik güvenli silme iddiası yok |
| Time Machine Snapshot | Time Machine Anlık Görüntüleri | Yerel snapshot'ları inceleme ve seçili bakım | Dahil; Time Machine/destek kontrolü gerekli |
| Trash Bins | Çöp Kutuları | Erişilebilen çöp konumlarını inceleme | Seçilen kullanıcının Çöp klasörünü inceleme; kalıcı boşaltma yapılmaz |
| Uninstaller | Tam Uygulama Kaldırma | App bundle ve ilişkili öğeler için kaldırma planı | Çalışıyor: app + exact bundleID ilişkili dosya planı; seçili Çöp / Homebrew cask uninstall |

## Mac Studio'da canlı gözlenen bakım alt listesi

Yerel 5.7.2 arayüzünde Maintenance Tasks şu beş öğeyi gösterdi:

- Flush DNS Cache.
- Free Up Purgeable Space.
- Reindex Spotlight.
- Repair Disk Permissions.
- Speed Up Mail.

Hiçbir görev seçilmedi; Run düğmesi devre dışıydı. Bakım yürütülmedi ve dosya
silinmedi. Görünür görev adı, o görevin başarıyla çalıştığı anlamına gelmez.

[Resmi bakım açıklaması](https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks)
cihaz/sürüm koşullarını ayrıca belirtir: RAM boşaltma Intel ile, periodic
scripts macOS 13 ve öncesiyle, snapshot işlemi Time Machine kurulumu ile
sınırlıdır. Paket kaynaklarında bütün adlar bulunsa da MacPocket etkin araç
listesini cihazdan belirlemelidir.

## Ortak Tools deneyimi

Aranabilir kartlar, favoriler, kategori filtreleri, özelleştirilebilir sıra ve
doğrudan işleme giriş ortak davranıştır. Araç kartı açıklama, destek/yetki
durumu, son tarama/çalışma zamanı ve sonuç geçmişini gösterebilir.
Kaldırma/güncelleme gibi işlevler kendi ana modülleriyle aynı servisleri kullanır.

Salt okunur tarama/rapor ile veri veya sistem ayarı değiştiren işlem ayrı
eylemlerdir. Kaldırma ve temizlik planında ilişkili, paylaşılan ve erişilemeyen
öğeler ayrılır. Ek entegrasyonu bulunmayan bir kart tamamlanmış işlev gibi
sunulmaz. Malware tespiti yalnız dosya adı veya şüpheli metin eşleşmesine
indirgenmez.

MacPocket'a eklenen Pencere Geçişi, Mac'i Uyanık Tut, Görev Yöneticisi ve Sistem Raporları bu 21 aracın yanındadır.
[Sistem İzleme/Sistem Araçları ve Görev Yöneticisi](SYSTEM_CENTER.md) kullanıcının
ek istediği sistem merkezidir; CleanMyMac'te canlı görülmüş araçlar olarak
sunulmaz.

Kaynak: [statik paket/kimlik notları](research/cleanmymac-static-notes.md).
