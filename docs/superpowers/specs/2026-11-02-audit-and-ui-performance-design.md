# Adım 1: Mevcut durum denetimi ve arayüz performansı

Durum: taslak, kullanıcı incelemesi bekliyor. Kapsam, Güç Merkezi genişletmesinin (fan, CPU, profiller)
1. adımıdır; sonraki adımlar ayrı spec alır.

## Amaç

Güç Merkezi ve mevcut özelliklerin gerçek çalışmasını doğrulamak, hataları düzeltmek ve arayüzü hızlandırmak.
Sahte veya çalışmayan hiçbir şey gösterilmez: bu makinede (pilsiz Mac Studio) doğrulanamayan kontrol
gizlenir veya nedeniyle devre dışı gösterilir.

## Başlangıç ölçümleri (2026-11-02, debug derleme, Mac Studio)

| Kontrol | Sonuç |
| --- | --- |
| `swift test` | 431 test, 0 hata, 3 atlandı |
| `scripts/check-localizations.sh` | 2347 anahtar, 0 eksik |
| `pmset -g assertions/therm/custom/sched` | her biri ~0 sn; yoklama maliyeti değil |
| Boştaki uygulama CPU'su | %5–15 (yüksek) |
| Fan okuması (`macpocket-probe system`) | `fans` alanı dönüyor; sensör erişimi çalışıyor |

## Bulgu 1: Arka plan zamanlayıcıları ana iş parçacığını meşgul ediyor

`sample` profilinde ana iş parçacığı zamanının büyük kısmı iki zamanlayıcıda:

- `VolumeMixerService.refresh()` (`VolumeMixerView.swift:159`): 3 sn'de bir, ana iş parçacığında
  `audioApps()` (süreç listesi filtreleme ve özellik okuma). Mikser sayfası kapalıyken de çalışıyor.
- `AppFreezerService.evaluate()` (`AppFreezerService.swift:53`): 15 sn'de bir, ana iş parçacığında.

Tasarım: ağır okumayı ana iş parçacığı dışına al (arka plan actor'ü), sonucu yalnızca değişince
yayınla; mikser tap'leri gerekmedikçe ve sayfa görünmüyorsa yoklamayı seyrelt/durdur. Davranış korunur
(ses uygulamalarının tap'leri ayarlarla senkron kalır), yalnızca iş nerede ve ne sıklıkla yapıldığı değişir.

## Bulgu 2: Güç Merkezi yoklaması

`PowerCenterModel.run()` her 2 sn'de ana aktörde `PowerInspector.overview()` (IOKit) çağırıyor.
Maliyeti ölçülmedi; ölçüm planda ilk görev. Ölçüm yük gösterirse okuma arka plana taşınır.
Sayfa görünmüyorken yoklama zaten durduruluyor (`run()` iptali).

## Denetim kapsamı (henüz yapılmadı)

Her özellik gerçek akışla açılır, mutlu yol ve kenar durumlar denenir, sonuç `docs/` altındaki
denetim tablosuna "çalışıyor / hata / bu makinede doğrulanamaz" olarak işlenir:
Güç Merkezi sekmeleri, pencere geçişi, pano, snippet, makro, depolama/temizlik, uygulama dondurma,
ses mikseri, parlaklık, menü çubuğu modülleri, ekran temizleme/kayıt/yakalama, odak oturumu,
başlangıç öğeleri, port yöneticisi. Hata bulunan her özellik için önce başarısız test, sonra düzeltme.

## Kapsam dışı

Fan yazımı, CPU yönetimi ve yeni arayüz bileşenleri sonraki adımlardır. Yeni bağımlılık eklenmez.

## Doğrulama (bitti sayılma ölçütü)

Boşta CPU'nun önce/sonra aynı `ps`/`sample` yöntemiyle ölçülmesi; tüm testler, lokalizasyon
kontrolü ve release derlemesinin geçmesi; denetim tablosundaki her satırın somut kanıtla doldurulması.
