# Sistem Merkezi ve Görev Yöneticisi

Kullanıcı, terminalden görülebilen sistem durumlarının ve araçlarının arayüzde
sunulmasını; Windows Görev Yöneticisi'ne yakın, yoğun teknik bir görev yöneticisi
istedi. Tasarım doğrudan Codex tarafından hazırlanmıştır.

## Görev Yöneticisi

- Uygulama/arka plan/sistem filtreleri; ad, kullanıcı ve PID araması.
- Sıralanabilir CPU, RSS bellek, kullanıcı, durum, PID ve süreç adı sütunları.
- İş parçacığı sütunu; üst süreç ve başlangıç zamanı ayrıntı panelinde.
- PID, başlangıç zamanı, kullanıcı ve executable kimliğine bağlı seçim.
- Ayrı normal sonlandırma ve zorla sonlandırma; sinyal gönderilmesi ve gözlenen
  çıkış farklı sonuçlar olarak gösterilir.
- Korunan veya erişilemeyen süreçler için açık durum.
- CPU/RAM/disk/termal özetleri, ayrıntı paneli, sütun ve yenileme seçenekleri.
- Henüz toplanmayan süreç bazlı disk/ağ verileri desteklenmiyor olarak gösterilir.

CPU yüzdesi bir mantıksal çekirdeğe göre ölçülür ve %100'ü aşabilir. İlk örnek
henüz interval üretmez. RSS paylaşılan sayfaları içerebilir; süreç RSS toplamı
Activity Monitor sistem bellek kullanımı olarak sunulmaz.

## Sistem İzleme / Sistem Araçları

| Alan | Kullanıcıya sunulacak görünüm | Çekirdek durumu |
| --- | --- | --- |
| CPU/RAM | Interval CPU, fiziksel RAM, wired, compressor ve ham boş sayfalar | Canlı native okuma mevcut |
| Bellek baskısı/swap | Ayrı göstergeler ve ham tanı çıktısı | Sabit salt okunur komutlar mevcut |
| Uyku engelleri | Uykuyu engelleyen assertion'lar, kaynak süreçler | Salt okunur tanı mevcut |
| Güç/termal | Güç kaynağı, düşük güç ve termal durum; desteklenen ayarlar | Canlı okuma ve tanı mevcut |
| Diskler/APFS | Mount, kapasite, boş alan ve paylaşım semantiği | Volume okuma ve dosya sistemi raporu mevcut |
| Ağ | Arayüz sayaçları, hata ve aktarım durumları | Sabit salt okunur rapor mevcut |
| Açık dosya/port | Seçilen süreç kaynakları; büyük sonuçta kısmi rapor | Bounded lsof tanısı; kapsam/limit açık gösterilir |
| Başlangıç/arka plan | Login item, launch agent/daemon envanteri ve desteklenen yönetim | CleanMyMac Tools kapsamı; uygulama bekliyor |
| Bakım işlemleri | DNS, indeks ve doğrulanmış bakım işlemlerinin destek/etki bilgisi | Referans arayüzü doğrulandı; MacPocket yürütücüsü bekliyor |

Salt okunur tanılar ile sistemi değiştiren bakım işlemleri farklı eylemlerdir.
Raporda ölçüm zamanı, kapsam, çıkış/durum, erişilemeyen öğeler ve veri sınırları
yer alır. Ham çıktı isteğe bağlı açılır; arama, kopyalama ve dışa aktarma sunulur.

## Mevcut native uygulama ve çekirdek

Swift package: `MacPocket` masaüstü uygulaması, `MacPocketCore` kütüphanesi ve
`macpocket-probe` doğrulama aracı. Arayüz SwiftUI; büyük süreç listesi için
sütunları yeniden boyutlandırılabilen, sanallaştırılmış AppKit NSTableView kullanılır.
Kaynaklar `Sources/` altında, testler `Tests/` altındadır.

```sh
make build
make test
swift run macpocket-probe system
swift run macpocket-probe processes
swift run macpocket-probe diagnostic memoryPressure
swift run macpocket-probe diagnostic powerAssertions
```

Native süreç okuması libproc ile yapılır. Sonlandırma seçilen kimliği yeniden
doğrular; PID 0/1, kendi süreç/ataları, başka kullanıcı ve sistem süreçleri
engellenir. Darwin'in PID temelli sinyalinde son doğrulama ile sinyal gönderimi
arasındaki çok küçük yarış atomik olarak ortadan kaldırılamaz.

## Tasarım durumu

[Codex tasarımı](https://p.superdesign.dev/draft/dd6d81b7-5129-4332-966b-ae40c5b265f0)
ve [tasarım alanı](https://superdesign.dev/teams/b3995d4c-a0ba-46be-8074-0145d4c08323/projects/6f2e88f1-1f89-4293-8b78-a858c182b936).

Kaynak: `Design/macpocket-system-center.html`. Bu etkileşimli HTML tasarımı
örnek veri kullanır ve gerçek süreçlere sinyal göndermez. Native çekirdek canlı
veriyle ayrıca doğrulanmıştır. Kullanıcı onayından sonra tasarım native
uygulamaya aktarıldı ve gerçek çekirdek verilerine bağlandı.

Arama/filtre, süreç seçimi, sonlandırma diyaloğu, Sistem Araçları görünümü ve
23 Tools kartı tarayıcıda denendi. Filtre dışına çıkan seçim temizlenir; yeni
bir sürece işlem yapmak için açık seçim gerekir. Native arayüzde de aynı
kimlik ve seçim kuralları uygulanır. Tools araması, kategoriler ve kalıcı favoriler
çalışır. Uyanık tutma gerçek IOPM assertion kullanır; diğer araçların hazır olmayan
işlevleri devre dışıdır.

## Mac Studio doğrulaması

28 Ekim 2026, macOS 27.0.1, `Mac16,9`, 16 mantıksal CPU, 64 GiB fiziksel RAM.
Pil mevcut değil; güç kaynağı AC. Bu bilgi pil desteği olmayan masaüstü durumunu
doğrular. MacBook'ta pil/şarj kontrolü kabulü ayrıca yapılacaktır.

- Sistem ve süreç snapshot'ları canlı olarak alındı.
- Bellek baskısı, swap, güç assertion'ları, güç ayarları, termal, disk ve ağ
  raporları çalıştırıldı.
- Büyük açık dosya çıktısı 256 KiB sınıra ulaştı; kısmi sonuç durumu ayrıca ele alındı.
- 27 çekirdek testi geçti. SIGTERM ve SIGKILL yalnız oluşturulan test süreçlerinde denendi.
- Native Görev Yöneticisi üzerinden sahip olunan sleep fixture (PID 60241) seçildi,
  normal sonlandırma onaylandı; uygulama çıkışı gözledi ve seçim temizlendi.
- Native Sistem Araçları üzerinden swap raporu alındı: çıkış kodu 0, gerçek sistem çıktısı.
- Tools üzerinden uyanık tutma başlatıldı. pmset, MacPocket PID 58643 için
  PreventUserIdleSystemSleep kaydını gösterdi. Durdurulunca yalnız bu kayıt kalktı;
  diğer uygulamaların assertion kayıtları korundu.
- Güç Merkezi pil bulunmayan Mac Studio durumunu doğru gösterdi.
- Testteki Foundation bekleme kilidi, doğrudan sahip olunan posix_spawn/waitpid
  fixture ve süre sınırlarıyla giderildi.

Tam çıktılar ve geliştirme logları `.build/macpocket-*` ve
`.build/process-fixture-*` altında tutulur; Git'e eklenmez.
