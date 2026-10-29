# Native geliştirme sürümü — 0.3.0

28 Ekim 2026: kullanıcının onayladığı Codex tasarımı native uygulamaya aktarıldı.

## Çalışan bölümler

- Genel Bakış: cihaz özeti, depolama, uygulamalar, güç ve günlük araçlara erişim.
- Sistem İzleme: CPU interval grafiği, fiziksel/ham boş/wired/sıkıştırılmış bellek,
  disk kapasitesi, termal durum ve çalışma süresi.
- Tools → Görev Yöneticisi: süreç listesi, filtre/sıralama, sütun tercihleri,
  PID/başlangıç/UID/yürütülebilir kimliğiyle normal ve zorla sonlandırma.
- Tools → Sistem Raporları: sekiz izinli salt okunur rapor; iptal, kısmi sonuç,
  arama, kopyalama ve dışa aktarma.
- Temizlik ve Disk Analizi: seçilmiş klasörde metadata taraması, üst klasör
  boyutları, boyut/yaş/arama filtreleri, SHA-256 içerik eşleşmesi ve seçili
  öğeleri ayrı onayla Çöp’e taşıma. Symlink takip edilmez, hard link tek sayılır.
  Tarama 45 saniye/200 bin öğeyle sınırlıdır; en büyük 8 bin dosya tutulur.
  Sınıra/erişim engeline ulaşıldığı ve kopya incelemesinin kapsamı açık gösterilir.
- Uygulamalar: standart ve kullanıcı tarafından eklenen konumlarda envanter;
  bundle kimliğine tam eşleşen kullanıcı Library öğeleri için kaldırma planı.
  Kullanıcı verileri başlangıçta seçili değildir. Apple/sistem/MacPocket korunur.
  Shared vendor/App Group ve bilinmeyen helper öğeleri otomatik eklenmez.
- Homebrew: yerel katalogdan güncelleme bulma ve ayrı onayla cask upgrade.
  Homebrew uygulaması kaldırılırken paket kaydını bozmamak için cask uninstall
  kullanılır; --zap kullanılmaz. Uygulamanın kendisi Çöp’e gitmeyebilir ve
  onay metni bunu açıklar. Seçili ilişkili dosyalar Çöp’e gider.
- Pencere Geçişi: açık uygulamalar, arama ve öne getirme. Erişilebilirlik izni
  verilirse gerçek pencere başlığı/minimize durumu ve AX raise kullanılır.
  İzin yokken yalnız uygulama geçişi yapılır. Liste 8 saniye/200 öğeyle sınırlıdır.
- Güç: gerçek kaynak/düşük güç/termal durum, süreli ve ekran tercihiyle uyanık
  tutma; dakika örnekleri ve uyku/uyanma olaylarının yerel geçmişi (en çok 20.160 kayıt).
- Tools: 25 kompakt kart, altı kategori, arama ve kalıcı favoriler. Giriş ve
  arka plan öğeleri macOS’un ilgili sistem ayarını açar.

## Henüz tamamlanmayan ürün kapsamı

MacBook şarj sınırı, şarj durdurma, sağlık ayrıntıları ve güç otomasyonları;
Homebrew dışındaki güncelleme sağlayıcıları; global pencere geçiş kısayolu ve
pencere küçük resimleri; malware, e-posta/tarayıcı bakımı,
Time Machine mutasyonları ve bütün sistem girişini
kilitleme servisleri geliştirme kapsamındadır. Hazır olmayan kartlar çalışıyor
olarak sunulmaz. Süreç başına ağ/disk aktarım hızı henüz ölçülmez.

Bu Mac’te pil yoktur. MacBook pil/şarj kontrolünün donanım kabulü ayrıca gerekir.
Erişilebilirlik izni kullanıcı tarafından verilmelidir; otomatik verilmez.

## Derleme

Xcode/Command Line Tools ve Swift 6 gerekir. macOS 14 ve üzeri hedeflenir.

```sh
make test
make app
make app-release
```

Uygulama `.build/MacPocket.app` olarak üretilir. Bu Mac'te optimize sürüm
`/Users/Dogancan/Applications/MacPocket.app` konumuna kuruldu ve oradan açıldı.
Apple Silicon aktarım paketi `.build/MacPocket-0.3.0-arm64.zip` içindedir. Debug sürümü LLDB için
get-task-allow entitlement içerir; release sürümü içermez. Release uygulaması
ad-hoc imzalıdır; Apple Developer imzası ve notarization bu aşamada yapılmadı.
Hazırlanan arm64 paket Apple Silicon Mac içindir. Intel hedefi ayrıca derlenir.

## Doğrulama

Mac Studio Mac16,9 / macOS 27.0.1 / 16 mantıksal CPU / 64 GiB RAM üzerinde:

- Derleme ve uygulama paket imza kontrolü başarılı.
- 49 XCTest testi geçti; süreç kimliği/koruma, SIGTERM/SIGKILL, tanı sınırları,
  iptal ve uyanık tutma assertion yaşam döngüsü doğrulandı.
- Native arayüzden sahip olunan test süreci sonlandırıldı, çıkış gözlendi.
- Native swap raporu gerçek çıktıyla ve çıkış kodu 0 ile tamamlandı.
- Native uyanık tutma başlatılıp durduruldu; pmset ile MacPocket'ın kendi
  assertion kaydının oluşup kalktığı doğrulandı.

Test çıktıları ve ekran görüntüleri `.build/` altında yerel olarak tutulur.
Referans uygulamalar veya kullanıcının dosyaları sonlandırma/temizlik testine
konu edilmedi.

## 0.3.0 canlı kontrol — 29 Ekim 2026

- Yeni Genel Bakış 119 uygulama ve gerçek Mac Studio metrikleriyle açıldı.
- Görev Yöneticisi Tools kartından açıldı; sol menüde ana bölüm yapılmadı.
- Önceden sistem raporlarında ekran dışına kayan kenar çubuğu düzeltildi:
  gezinme yayıncısı canlı metriklerden ayrıldı, split view pencere alanıyla
  sınırlandı, kenar çubuğu/alt durum yüksekliği sabitlendi. Sayfa geçişleri
  arayüzden kontrol edildi; Genel Bakış, Tools ve rapor görüntüleri aynı
  2880 × 1800 piksel boyutunda kaldı. Seçili Tools satırına fareyle yeniden
  tıklamak araç listesine döndürür. Önce/sonra görüntüleri .build altında saklandı.
- Sahip olunan örnekte 4 tekil dosya / 388 KiB bulundu. Hard link ikinci kez
  sayılmadı; aynı boyutlu farklı içerik elendi, 2 dosyalı gerçek kopya grubu bulundu.
  Fazla test kopyası onay sonrası Çöp’e taşındı; asıl dosyalar korundu.
- Yalnız oluşturulan örnek uygulama klasörü envantere eklendi, kaldırma planı
  incelendi ve örnek bundle onay sonrası Çöp’e taşındı. Gerçek uygulama kaldırılmadı.
- Yerel Homebrew kataloğunda iki güncelleme görüntülendi. Güncelleme onayı açılıp
  iptal edildi; gerçek cask upgrade/uninstall kabul testi bu Mac’te yürütülmedi.
- Güç Merkezi’nde uyanık tutma başlatıldı; pmset MacPocket’ın assertion’ını
  gösterdi. Durdurulduktan sonra bu kayıt kalktı. Yerel dakika kayıtları görüldü.
- Pencere Geçişi açık uygulamaları ve eksik Erişilebilirlik iznini doğru gösterdi.
  AX pencere geçişi izin verilmediği için bu Mac’te kabul testinden geçmedi.

[0.2.0 platform temeli ve kısayollar](NATIVE_MACOS.md).

## Mevcut sürüm üzerinde devam eden geliştirme

29 Ekim devamı: [güncel kapsam ve kabul kayıtları](CONTINUED_DEVELOPMENT.md).
Bu belgedeki 0.3.0 başlangıç kaydı tarihsel kabul kapsamıdır.
