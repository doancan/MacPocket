# AltTab davranış eşlemesi — 29 Ekim 2026

## Kanıt ve kapsam

Kurulu `/Applications/AltTab.app` paketinin Info.plist verisi REA ile yeniden
okundu. Bundle `com.lwouis.alt-tab-macos`, sürüm/build `11.10.1`, kaynak lisansı
GPL-3.0 olarak gözlendi. Evidence:
`ev_dfa3f9cda41cec06854936959b51f79904fbd717ceffd16edda2ecc1cc59826f`.
Bu resource incelemesinin executable kimliği yoktur; çalışırken davranış
kanıtı veya binary eşdeğerlik iddiası değildir.

Önceki aynı sürüm kaynak incelemesi tekrar kullanıldı; odaklı ek inceleme:
[KeyboardEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/v11.10.1/src/events/KeyboardEvents.swift).
Carbon hotkey ile modifier bırakma/giriş gözlemi ayrıdır. macOS 26 Escape
davranışı için AltTab'ın özel event-tap yolu vardır. MacPocket bu kaynak kodunu
kopyalamaz; public AppKit/Carbon/AX/ScreenCaptureKit ile bağımsız implementasyon
kullanır. AltTab paketine ya da ayarlarına müdahale edilmedi.

## Eklenen MacPocket davranışları

- Kalıcı seçenekler: gizli/küçültülmüş/penceresiz uygulamalar; tek uygulama
  kapsamı; son kullanılan/uygulama/başlık sırası; uygulama yolu kara listesi.
- Son kullanılan sırası MacPocket'ın gözlediği uygulama etkinleştirmelerinden,
  kendi odak eylemlerinden ve liste yenilenirken öndeki AX penceresinden oluşur.
  Geçmiş oturumların ya da gözlenmemiş bütün odak değişikliklerinin MRU kaydı
  olduğu iddia edilmez. Pencere kimlikleri PID/başlangıç/AX hash üzerinden stabildir.
- Varsayılanı kapalı global kısayol: Control+Option+Space, Option+Tab veya
  Control+Tab; Shift ile ters yön. Diğer uygulamayla çakışma açık hata verir;
  mevcut AltTab kısayolu zorla ele geçirilmez.
- Global kısayol ayrı native panel açar. Tekrar basma, Tab/oklarla gezinme,
  Enter ile etkinleştirme, Escape ile iptal ve tercihe göre değiştirici tuşların
  bırakılmasıyla seçim vardır. Genel klavye kaydı veya global event tap yoktur.
- Seçili pencere için küçültme/geri alma, destekliyorsa tam ekran, uygulama
  gizleme ve ayrı onayla pencere kapatma. Kapatma planı hedef kimliğini sabitler.
  Her mutasyonda PID ve uygulama başlangıcı yeniden kontrol edilir; AX
  desteklemiyorsa işlem sunulmaz/başarısızlık açık gösterilir.
- ScreenCaptureKit ile seçili pencerenin isteğe bağlı önizlemesi. Ekran Kaydı
  izni yokken listeleme görüntü yakalama veya izin isteme başlatmaz. Kullanıcı
  ayrı düğmeyle izin isteyip ayrı düğmeyle önizleme alır. PNG yalnız bellekte
  tutulur, diske yazılmaz. Aynı PID/başlıklı birden fazla SCWindow bulunursa
  yanlış pencere göstermemek için sonuç reddedilir.
- Listeleme 8 saniye/200 öğeyle sınırlı; kısmi sonuç işaretlenir. AX ve capture
  çağrılarının erişim başarısızlıkları uydurma pencere/thumbnail ile doldurulmaz.

## Doğrulama ve açık sınırlar

Dört yeni çekirdek testi görünürlük/blacklist bileşimini, uygulama/arama kapsamını,
gözlenen MRU sırasını ve bilinmeyen kimliklerde mutasyon reddini doğrular.
`.build/switcher-tests.log`: dört test başarılı. Tam uygulama derlemesi başarılı.

Kısayolun gerçek sistem kaydı/panel davranışı ve izin durumlarının native
arayüz kabulü ana çalışma tarafından yapılmalıdır. Kullanıcının gerçek
pencereleri kapatılmadı, küçültülmedi, tam ekrana geçirilmedi; Erişilebilirlik
ve Ekran Kaydı izinleri bu geliştirme sırasında otomatik verilmedi. İzinli AX
ve capture davranışı henüz bu makinede doğrulanmış kabul edilmez.

Tam AltTab eşdeğerliği **tamamlandı denemez**: private WindowServer/Space
entegrasyonuna dayanan bütün-Space kontrolü, görünmeyen/aynı başlıklı her
pencerenin birebir thumbnail eşlemesi, per-window eksiksiz MRU geçmişi, tüm
AltTab görünüm temaları ve gelişmiş tetikleme kombinasyonları henüz eşlenmedi.
Public API kapsamı macOS'un Space/tam ekran politikasına tabidir.

Apple: [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager).
