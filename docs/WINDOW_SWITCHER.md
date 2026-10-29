# Alt+Tab pencere geçişi

Hedef: AltTab’ın (alt-tab.app/features, alt-tab.app/pricing) vaat ettiği Windows
tarzı “canlı küçük resimlerle pencere geçişi”. MacPocket AltTab kodunu kopyalamaz;
AppKit, Carbon hotkey, Erişilebilirlik (AX), CGWindowList ve ScreenCaptureKit ile
bağımsız uygulanır. Tools → Pencere Geçişi ayar ve ayrıntı ekranıdır.

## Özellik eşlemesi (29 Ekim 2026)

| AltTab | MacPocket | Durum |
|---|---|---|
| Canlı küçük resimler | CGWindowID ile birebir yakalama; panel açıkken ~1 sn’de bir yenilenir | Uygulandı; görüntü Ekran Kaydı izniyle canlı doğrulanacak |
| Her pencere, her Space ve ekran | AX (geçerli Space) + CGWindowList (tüm Space’ler) birleşimi; “Diğer masaüstü”, “Ekran N” rozetleri | Uygulandı; probe ile gerçek sistemde doğrulandı |
| Küçültülmüş ve gizli pencereler | Rozetli; kısayol başına göster/gizle | Uygulandı |
| Seçmeden önce tam boy önizleme | Seçili pencere kendi konumunda, tıklamayı geçiren panelde | Uygulandı |
| Açık/koyu görünüm | Panel sistem görünümünü izler; saydamlığı azalt → düz zemin | Uygulandı |
| Üzerine gelince kapat/küçült/tam ekran | Kart düğmeleri; klavye ⌘W ⌘M ⌘F ⌘H ⌘Q | Uygulandı |
| Stiller | Küçük resim / uygulama simgesi / başlık listesi | Uygulandı, canlı görüldü |
| Yazarak arama | Panel açıkken yazmak süzer (çok terimli, harf/aksan duyarsız); ⌫, esc | Uygulandı, canlı görüldü |
| Otomatik boyut | Pencere sayısına göre küçülen ızgara, boyut kaydırıcısı | Uygulandı, canlı görüldü |
| 9 kısayol, her biri kendi filtresiyle | Kaydedici; uygulama/masaüstü/ekran filtreleri, bırakınca seç | Uygulandı |
| Anında veya açık tut | Kısayol başına “Bırakınca seç”; arama varken panel açık kalır | Uygulandı |
| İstisnalar | Geçişte gösterme + “öndeyken kısayolu kapat” (VM/uzak masaüstü) | Uygulandı |
| Trackpad hareketleri | 3/4 parmak yatay kaydırma (özel MultitouchSupport, isteğe bağlı) | Uygulandı; trackpad’siz bu Mac’te doğrulanmadı |
| Komut satırı | `macpocket-probe windows`, `focus <windowID>`, `thumbnail` | Uygulandı, doğrulandı |
| Erişilebilir | VoiceOver etiketleri, seçim duyurusu, kart eylemleri | Uygulandı |
| Pil dostu | Canlı yenileme yalnız panel açıkken; boşta ~%2 CPU | Ölçüldü |
| 21 dil | — | Kapsam dışı (uygulama Türkçe) |

## Teknik notlar

- Pencere kimliği AX ↔ WindowServer eşlemesiyle (`_AXUIElementGetWindow`, çalışma
  anında aranır; yoksa çerçeve eşleşmesi) bulunur. Aynı başlıklı pencereler artık
  karışmaz.
- Diğer Space’teki pencereler WindowServer başlığı gerektirir (Ekran Kaydı). İzin
  yokken başlıksız ekran dışı pencereler tahmin edilmez.
- Diğer Space’e geçiş: uygulama etkinleştirilir (macOS Space değiştirir), pencere
  AX’te görünür olunca kimliğiyle öne getirilir.
- Katalog uygulama değişimlerinde arka planda tazelenir; panel önbellekle anında
  açılır, ardından taze liste gelir.
- İzinler imza kimliğine bağlıdır. `scripts/build-app.sh` geçerli bir Developer ID /
  Apple Development sertifikası varsa onu kullanır; ad-hoc imzada her derlemede
  izinler sıfırlanır.

## Bekleyen canlı kabul

Erişilebilirlik ve Ekran Kaydı izinleri kullanıcı tarafından verilmelidir. Bu
izinlerle küçük resimlerin canlı yenilenmesi, tam boy önizleme, diğer Space’e
geçiş ve ⌘W/⌘M eylemleri ayrıca kabul edilecek. Trackpad hareketi trackpad’li
bir Mac’te denenmelidir. Bu belge tam AltTab eşdeğerliği iddiası değildir.
