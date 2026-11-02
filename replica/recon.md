# Recon: mole.fit → MacPocket kazanımları

Kaynak yalnız herkese açık sayfa (https://mole.fit/). Hesap, kaynak kodu, ağ çağrısı kullanılmadı.
Ekran görüntüsü alınmadı (`screens/` boş): bu tek sayfalık bir pazarlama metni okumasıdır.
Tüm "clone" durumları **statik kod incelemesine** dayanır; canlı doğrulama yapılmadı.

## 1. Kapsam
- Uygulama/platform: macOS yardımcı programı (Mole Mac uygulaması, macOS 14+).
- Dilim: sayfadaki tüm işlevler. Gezegen/marka adları, karakterler, şiirler, ikonlar alınmaz; işlevler MacPocket'ın kendi Türkçe adlarıyla yapılır.
- Kullanıcı: MacPocket'ın kendisi. İlke: benzer olan MacPocket modülü **genişletilir**, sıfırdan yazılmaz.

## 2. Kaynaklar
| kaynak | ne verdi |
| --- | --- |
| https://mole.fit/ (Five Tools, Menu Bar & Utilities, CLI, Pricing, Positioning) | işlev listesi, güvenlik ilkeleri, fiyat/konumlandırma |

Yardım merkezi, changelog ve video bu turda okunmadı; ayrıntı eksik kalan satırlar "tahmin" sayılır.

## 3. Mevcut MacPocket ile eşleme (modül → Mole alanı)
| Mole alanı | MacPocket'taki karşılığı | Karar |
| --- | --- | --- |
| Clean | CleanupView + CleanupTargets (14 hedef) | Genişlet: hedef ekle, Sistem Verisi + "Ayrı Yönet" |
| Software: güncelleme | ApplicationsView + Homebrew cask | Genişlet: kanal ekle |
| Software: başlangıç öğeleri | LoginItemController (yalnız kendi kaydı) | Yeni servis: LaunchAgents okuma |
| Software: kaldırma | ApplicationLeftovers + UninstallPlan | Genişlet: kategori, makbuz, Dock |
| Optimize | SystemMaintenanceTools (11 salt okunur rapor) | Genişlet: ilk mutasyonlu görevler |
| Analyze | SpaceLens (treemap) | Büyük ölçüde hazır; bağlam menüsünü doğrula |
| Status | SystemMonitor, Fan/Temp, Overview, TaskManager | Genişlet: sağlık puanı, 60 sn bento, pin |
| Menü çubuğu HUD | MenuBarModules/Renderer | Genişlet: kompakt mod, sağ tık, (ops.) koşucu |
| Araçlar: ekranı açık tut, ekran temizleme | SleepController, ScreenCleaningController | Genişlet: renk + giriş kilidi |
| Gizlilik Kontrolü | — | **Yeni** |
| WiFi Düşük Gecikme | — | **Yeni** |
| Proje artıkları / yükleyici süpürme (CLI) | CleanupTargets (DerivedData vb.) | Genişlet, uygulama içine al |

## 4. Ekranlar (hedef, mevcut sekmelerle)
| ID | ekran | nasıl ulaşılır | amaç | durum |
| --- | --- | --- | --- | --- |
| S01 | Temizlik | ana sekme | hedef tara/seç/Çöp'e taşı | var, genişler |
| S02 | Temizlik › Sistem Verisi | Temizlik içinde | snapshot, yükleyici, sistem cache | yeni alt sayfa |
| S03 | Uygulamalar › Güncellemeler | Uygulamalar | kanal bazlı güncelleme | var, genişler |
| S04 | Uygulamalar › Başlangıç Öğeleri | Uygulamalar | 3 sınıf öğe yönetimi | yeni |
| S05 | Uygulamalar › Kaldırma | Uygulamalar | plan + kalıntı | var, genişler |
| S06 | Bakım (Optimize) | Tools | görünür bakım geçişi | var (rapor), mutasyon yeni |
| S07 | Disk Analizi | ana sekme | treemap | var |
| S08 | Sistem İzleme / Genel Bakış | ana sekme | bento + sağlık puanı | var, genişler |
| S09 | Görev Yöneticisi | Tools | süreç listesi + sabitle | var, genişler |
| S10 | Menü çubuğu HUD + hızlı menü | menü çubuğu | canlı bakış | var, genişler |
| S11 | Gizlilik Kontrolü | Tools + Ayarlar › Menü Çubuğu | kamera/mikrofon canlı durumu | yeni |
| S12 | Ekran Temizleme | Tools | düz renk, kilit | var, genişler |
| S13 | WiFi Düşük Gecikme | Tools + Ağ kartı | AWDL geçici kapatma | yeni |

Her ekran için durumlar kaydedilecek: boş, yükleniyor, dolu, hata, izin yok, yönetici gerekir.

## 5. Akışlar
- F01 Kullanıcı temizler: S01 tara → seç → önizleme/onay → Çöp'e taşı. (kural: "kullanımda" öğe uyarılır; "Ayrı Yönet" toplama girmez)
- F02 Kullanıcı yükleyici/proje artığı süpürür: S01 filtre → seç → onay.
- F03 Uygulamayı kaldırır: S05 uygulama seç → kalıntı planı → onay.
- F04 Başlangıç öğesini kapatır: S04 sınıf gör → doğrudan olanı kapat; Ayarlar yönetimli olana yönlendir.
- F05 Bakım çalıştırır: S06 görev seç → (yönetici) onay → sonuç.
- F06 Mikrofon/kamera açılır: S11 → bildirim → "bu uygulama için bildirme".
- F07 Düşük gecikmeyi aç/kapat: S13 → yönetici onayı → uyku/çıkış/ağ değişiminde otomatik geri al.
Tıklama sayısı hedefi: F01 en fazla 4.

## 6. Çıkarılan veri modeli
- CleanupTarget (var): + `managedSeparately: Bool` (tahmin; "Ayrı Yönet" grubu için). güven: orta
- StartupItem (yeni): label, plist yolu, sınıf (direct | systemManaged | readOnly), etkin. güven: orta
- MaintenanceTask (yeni): id, ad, yönetici gerekir, macOS sürüm koşulu, son sonuç. güven: orta
- PrivacyUsageEvent (yeni): cihaz (camera|mic), uygulama adı (yalnız mic), başlangıç. güven: orta
- HealthScore (yeni, türetilmiş): bileşen puanları + toplam. güven: düşük (formül Mole'da belirtilmemiş)

## 7. Kapsam dışı / atlanan
AI Cleanup & Care (kullanıcı kararı), lisans/ödeme, Windows sürümü, Touch ID sudo (sistem dosyası düzenler), marka adları/karakter/şiir/ikon.
Doğrulanamayanlar: fan yazma, AWDL kontrolü ve yönetici işlemleri bu ortamda gerçek davranışla doğrulanmadı; MacBook'a özgü hiçbir şey bu Mac Studio'da doğrulanmış sayılmaz.

## 8. Büyüklük: **L**
Zor üç parça: (1) ayrıcalıklı işlemler (yönetici yardımcısı: bakım, AWDL, fan, yazı tipi önbelleği); (2) kamera/mikrofon canlı algılama (CoreAudio + CoreMediaIO) ve izin/bildirim akışı; (3) çok kanallı güncelleme (Sparkle/App Store/GitHub) ve başlangıç öğesi sınıflandırması.
Hızlı kazanımlar (M altı): Sistem Verisi listesi, proje artığı/yükleyici süpürme, sağlık puanı, süreç sabitleme, ekran temizleme renk/kilit, kompakt HUD, Gizlilik Kontrolü.

## 9. Ekran görüntüsü bulguları (eklendi)
Kaynak: `replica/screens/mole-*.png` (yalnız referans, ürüne girmez). İlk okuma metin tabanlıydı; görseller şunları ekledi:
- Özellikler bölümü Güneş Sistemi temasıyla sunuluyor; **gezegen/ay adları ve görselleri alınmaz.** İşlevler nötr adlarla kalır.
- Temizlik: öğe başına temizle/atla/**koru**; özet ekranı "N GB bulundu · M öğe · K kategori" + "Sonuçları incele".
- Yazılım: "Hızlı kaldırma" anahtarı; boyutlar silmeden önce görünür.
- Optimize: tüm çalıştırma için **tek yönetici yetkisi**; güvensiz/uygulanamaz görev **gerekçeyle atlanır**; sonuç ne çalıştığını ve neden atlandığını gösterir.
- Analiz: sistem klasörleri yalnız görüntüleme; Çöp'ten **geri koyma**; yalnız Çöp'teki öğe kalıcı silmede sorar.
- Durum: sağlık kartı (puan + çip/RAM/macOS/çalışma süresi etiketleri), CPU/GPU/bellek/pil/disk/ağ/fan kartları, süreç tablosu (MEM, %CPU, PWR, PID, "…" menüsü), fan Otomatik/Soğut/Maks, eşleşmiş cihaz pilleri, süreç için sade dille açıklama.
- Menü çubuğu paneli: aynı kartların küçük hali + **Gizlilik satırı** (kamera ve mikrofon simgeleri, "Kullanımda değil"), Uyanık/Ekran kısayolları, temizlik geçmişi toplamları.
Matris güncellendi: +14 satır.
