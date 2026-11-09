# Değişiklik Günlüğü

## Yayımlanmamış

- **Küçük canlı grafikler:** örnek başına ayrı grafik öğeleri oluşturan yapı tek Canvas çizimine taşındı. Yumuşak eğri, renkli alan, negatif Wi-Fi ölçeği ve otomatik üst sınır korunur. Geçersiz değerler çizime katılmaz; sensör ve menü çubuğu yenileme aralıkları değişmez.

- **Animasyonlu menü çubuğu geçişi:** ilk açılış/kapanış ve boyut değişimlerinde yerel animasyonlar korunur. Başka bir MacPocket simgesine tıklamak açık panelin içeriğini ve bağlı olduğu simgeyi değiştirir; paneli kapatıp yeniden açmaz. Hareketi azalt tercihi uygulanır; dışarı tıklama ve Escape ile kapatma korunur.

- **Menü çubuğu panel geçişi:** hava durumu, AI ve diğer simgeler arasında tıklarken açılma isteğinin kaybolması düzeltildi. Gerçek bir kapanış sırasında gelen seçim saklanır; hızlı geçişte son hedef açılır, aynı simgeye tekrar tıklama paneli kapatır.

- **Saatlik hava ayrıntıları:** saat kartı ayrı bir ayrıntı sayfası açar. Kaynak sağlıyorsa yağış olasılığı/miktarı/şiddeti, hissedilen sıcaklık, nem, rüzgâr/hamle/yön, basınç, bulut örtüsü, görüş, UV ve çiy noktası gösterilir. Yağışın 1/3/6/12 saatlik dönemi korunur; eksik alanlar sıfırla doldurulmaz.

- **Saatlik tahmin tıklamaları:** görsel ok yerine çalışan ileri/geri düğmeleri eklendi. Saat kartları tıklandığında kaynağın sunduğu tarih/saat ve Celsius sıcaklığı gösterilir; ayrıntı kapatılabilir. Kaydırma sınırlarında düğmeler devre dışı kalır; hareketi azalt tercihi korunur.

- **Hava durumu paneli:** büyük sıcaklık/koşul görünümü, kompakt nem-rüzgâr-basınç satırı, kaydırılabilir saatlik tahmin ve ortak ölçekli günlük sıcaklık çubukları. Konum ve kaynak ayarları ayrı görünüme alındı; seçili kaynak ve yenileme altta kaldı. Boş konum, yükleme, hata, anahtar eksikliği ve ayrıntılı tahmin bulunmaması için ayrı durumlar eklendi.

- **Hava durumu kaynak sepeti:** 11 ücretsiz erişim seçeneğinden istenenler sepete eklenebilir; menü çubuğu yalnız seçili kaynağı sorgular. Visual Crossing, MET Norway ve Open-Meteo anahtarsız; ECMWF IFS/AIFS Single, GFS ve ICON ayrı model seçenekleridir. WeatherAPI.com, Pirate Weather, OpenWeather’ın ücretsiz mevcut hava/5 günlük tahmin uçları ve Tomorrow.io kişisel API anahtarıyla çalışır. Anahtarlar Anahtar Zinciri’nde tutulur. Sağlayıcıya özel önbellek, kalıcı seçim, kota/erişim hataları ve kapsam bağlantıları eklendi; mevcut kullanıcıların iStat bağlantısı ilk seçim değişikliğine kadar korunur.

- **Kaldırma planı:** uygulama, önbellek/günlükler ve kullanıcı verileri ayrı gruplarda gösterilir. Grup seçimi, Finder’da gösterme ve sabit seçim özeti eklendi; kullanıcı verileri başlangıçta seçilmez.
- **Çalışan uygulamalar:** kaldırma onayından sonra önce normal çıkış istenir. Uygulama ve paket içindeki yardımcı süreçler kapanmadan dosyalar taşınmaz. Kapanmayan süreçler için ayrı zorla kapatma onayı gerekir; hatada plan açık kalır. [Kapsam ve doğrulama](docs/APPLICATION_UNINSTALL.md).

## 0.1.6 — 7 Kasım 2026

- **Alt+Tab pencere geçişi:** animasyonlu önizleme kartları, Alt basılıyken Tab/Shift+Tab ile seçim ve Alt bırakıldığında pencereyi öne getirme. Dokuz kısayol için bağımsız filtre/görünüm/bırakma ayarları ve özelleştirilebilir pencere eylemleri geliştirildi. Fiziksel klavye/trackpad ve tüm Space/tam ekran kombinasyonları için kabul kapsamı ayrıca izleniyor; tam AltTab eşdeğerliği iddia edilmiyor.

- **Kablo Etki Haritası:** seçilen USB/Thunderbolt aygıtının bağlı disklerini, açık dosyalarını, yerel adresle eşleşen TCP/SSH oturumlarını ve ekran/ses etkilerini birlikte gösterir. Donanım kanıtı ile kullanıcı eşleştirmeleri ayrıdır; araç salt okunurdur. [Kapsam ve kabul sınırları](docs/CABLE_IMPACT.md).

- **Menü çubuğu düzenleyici:** uygulamaları gizli grupta toplama, ok düğmesiyle gizleme/gösterme, aranabilir liste ve simgeyi açma. macOS 27 özel görünürlük arayüzü çalışma anında denetlenir; sistem panelleriyle uyum sınırı araçta açıklanır.
- **Bağımsız güncelleme merkezi:** Homebrew dışındaki uygulamalar için Sparkle, isteğe bağlı App Store ve uygulamaya bağlanan herkese açık GitHub sürüm kaynakları. Denetim elle başlatılır; kurulum üreticinin akışında devam eder.
- **İnternet kontrolü — deneysel:** imzalı uygulama kimliğiyle izin/engel kuralları, bağlantı listesi ve Network Extension uzantısı. Filtre başlangıçta kapalıdır; kullanım macOS uzantı/ağ filtresi onayı gerektirir. Kurallar yeni bağlantılar içindir; gerçek engelleme kabulü henüz tamamlanmadı. [Kapsam ve doğrulama](docs/PRODUCT_EXPANSION.md).

- **Doğrulama:** 1.467 testte 0 hata, donanıma bağlı 5 isteğe bağlı atlama. Türkçe/İngilizce kontrolünde eksik çeviri yok. Kablo Etki Haritası için 32 canlı kontrol geçti; fiziksel kablo çıkarma testi yapılmadı.

- **Dağıtım notu:** depo özel olduğu için indirme GitHub erişimi gerektirir. Anonim Sparkle güncelleme adresi erişilebilir olmadığından bu sürüm Release sayfasından indirilerek kurulmalıdır.

## 0.1.5 — 6 Kasım 2026

- **DMG kurulum penceresi:** MacPocket’ın kendi simgesi, Uygulamalar klasörüne sürükle-bırak kurulumu, Retina arka planı ve Türkçe/İngilizce yönergeler. İmzalı ve Apple tarafından notarize edilmiş DMG indirmesi; otomatik güncellemeler için mevcut ZIP ve Sparkle akışı korunur.
- **SSH Yöneticisi:** Tek çalışma alanında SSH config düzenleme, bağlantı ve ProxyJump testleri, Terminal/iTerm2/Ghostty ile bağlantı, anahtar ve known_hosts yönetimi, yedekler ve global kısayollu hızlı bağlantı. Türkçe/İngilizce arayüz ve mevcut SSH yöneticisinden tercih/yedek aktarımı eklendi.
- **AI kullanım takibi:** Claude, Codex/ChatGPT ve Grok hesaplarının kotaları ayrı ayrı menü çubuğu, kullanım ekranı ve küçük yüzen panelden izlenebilir. Claude için ayrı profiller, profil klasörü keşfi, açık kullanıcı eylemiyle giriş, hesap yönetimi, kota uyarıları ve hesap başına yenileme bekleme politikası bulunur.
- **Komut Çubuğu, Dosya Rafı ve Dock Önizlemeleri:** Araçlara ve içeriklere hızlı erişim, dosya/metin/görselleri toplama ve aktarma, Dock üzerinden pencere önizlemeleri eklendi.
- **Ekran görüntüsü ve fare araçları:** Kaydırmalı ekran görüntüsü, ekrana sabitlenen çekimler ve uygulamaya özel fare tuşu atamaları eklendi.
- **Modül ve izin yönetimi:** Modülleri ayrı açma/kapatma, kapalı modüllerin kaynaklarını bırakma ve izinlerin hangi özellikler tarafından kullanıldığını gösterme geliştirildi. Uygulama başına ses yönlendirmesi, kanal bazlı güncelleme kaynakları ve koşullu uyanık tutma iyileştirildi.
- **Araçlar ve pencere geçişi:** Yan menüde veya sistem ayarlarında bulunan işlevlerin yinelenen araç kartları kaldırıldı; sekmelerdeki kart hizaları düzenlendi. Alt+Tab seçiminde panel uygulama odağını almadan açılır; hızlı seçim, gecikmeli panel gösterimi ve Alt bırakılınca seçilen pencereye geçiş iyileştirildi.

## 0.1.4 — 5 Kasım 2026

- **Case Converter:** 14 metin/kod biçimi; Türkçe/İngilizce İ/ı kuralları, 300 ms beklemeli canlı önizleme, satır satır toplu dönüşüm, kısaltma/sayı ayrıştırma ve Latin harflerini sadeleştirme. Tüm biçimleri karşılaştırma, tek tek/toplu kopyalama, seçilen sonucu girdi yapma ve metin istatistikleri. İşlem yereldir; 64 KiB girdi sınırı ve iptal/eski sonuç koruması bulunur.
- **Pratik Araçlar:** Sol menüde ayrı bir çevrimdışı çalışma alanı. JSON düzenleme/küçültme, standart/URL uyumlu Base64, URL parametre kodlama, JWT içerik ve zaman inceleme, SHA-256/SHA-512, toplu UUID v4, güvenli parola/token, Unix saniye/milisaniye dönüşümü, satır farkı ve metin/Wi-Fi QR üretimi. Arama, kalıcı favoriler, örnekler, geçici araç taslakları, hata/ilerleme, kopyalama ve metin/PNG dışa aktarma bulunur. Girdi/sonuçlar otomatik diske yazılmaz; geçici pano çıktısı geçmişe arşivlenmez. JSON büyük sayıları ve anahtar sırasını korur; JWT imza doğrulaması yapılmaz.

- **Araç arayüzleri:** 57 katalog girişinin ekran/yönlendirme envanteri çıkarıldı. Dar pencerede başlık eylemleri alt satıra geçer; kısa ayar ekranları kaydırılabilir. USB/Thunderbolt, disk sağlığı, Bluetooth, ağ trafiği ve başlangıç öğelerinde yüklenme/yenileme/boş/hata durumları ayrıldı. Arama odağı ve ağ haritasının klavye erişimi düzeltildi. Ses çıkışı hataları görünür; ekran kaydında hazırlama/kaydetme aşamaları gösterilir ve başarı dosya tamamlanınca bildirilir. Araç bazındaki doğrulama kapsamı `.design/tool-ui-report.md` içindedir.

- **Araç performansı:** Ağ trafiği gruplarının toplamları tek geçişte hesaplanır; sıfırlama artık ek `nettop` başlatmaz ve bekleyen eski sonuçlar yeni oturuma karışmaz. Harici disk yokken USB çıkarma listesi üç yerine tek `diskutil` sorgusu yapar. Hava durumu, dakikalık kontrol döngüsü yerine doğrudan saatlik yenileme zamanını bekler; konum seçilmediyse zamanlayıcı başlatmaz.

- **Menü çubuğunda hava durumu:** Sıcaklık ve koşul simgesi, hissedilen sıcaklık seçeneği, saatlik ve beş günlük tahmin paneli eklendi. Kullanıcı şehir/ilçe arayıp konumunu seçebilir; seçim uygulama yeniden açıldığında korunur. Konum değişikliği panelden veya Menü Çubuğu ayarlarından yapılabilir. Saatlik otomatik yenileme ve bağlantı hatasında son başarılı veriyi koruma bulunur.

- ⏏️ **USB Çıkarma Yöneticisi**: harici fiziksel diskleri ve bölümlerini listeleme, tekli/toplu güvenli çıkarma, diski kullanan süreçler ve açık dosyalar, Finder ve uygulamaya geçiş. Dahili/başlangıç diskleri korunur; yeniden takılan disk eski seçimi devralmaz.
- 🌐 **Yerel Ağ**: cihazları ad, üretici (yerleşik MACLookup ve IEEE kayıtları), tür, IP/MAC ve gecikmeyle listele; birden fazla ağı birlikte tarama (Wi-Fi, Ethernet, elle eklenen VLAN aralıkları), ağ haritası, ayrıntı panelinde canlı ping, port taraması ve risk uyarıları, Wake-on-LAN, yeni cihaz bildirimi
- ⏰ **Güç Zamanlaması**: tekrarlayan uyanma/açılma ve uyku/kapanma saatleri, tek seferlik olaylar
- Yerel Ağ düzeltmeleri: MAC araması sırasında kaldırılan ağın sonucuna yazılmaz; geçici rota yalnız başarıyla eklendiyse temizlenir; yalnız Bonjour ile bulunan cihazlar da listelenir.
- Diğer alt ağlarda MAC bilgisi: SNMP hedef IP–arayüz eşleştirmesi; eşleştirilemeyen arayüz MAC’leri için açıklama; doğrudan ARP sonucunun önceliği ve arayüz/adres filtresi.
- Helper’ın sihirbazdaki servis kimliği, dosya yolu ve XPC adı korunur; normal tarama yeniden kurulum/onay başlatmaz.
- Normal ağ taraması, kurulu yardımcı servis üzerinden tüm seçili alt ağlarda MAC aramasını otomatik tamamlar; ayrı düğme veya tarama başına parola gerekmez. Doğrudan arama 32 eşzamanlı ping ile sınırlıdır ve normal taramada görünmeyen cihazları da ekler.

## 0.1.3 — 4 Kasım 2026

### ✨ Yeni
- **Otomatik güncelleme** — Sparkle ile; “Güncellemeleri Denetle…” menüsü, Ayarlar’da otomatik denetim ve indirme, imzalı güncellemeler
- **Ekran Süresi** — uygulama başına günlük ve saatlik süre, 7 ve 30 günlük grafik; boşta, kilitli ve uykuda sayılmaz
- **Kurulum sihirbazı** — ilk açılışta karşılama, izinlerin canlı durumu ve Sistem Ayarları’na sürükle-bırak kartı
- **GPU modülü** — menü çubuğunda GPU kullanımı, işleyici ve bellek; ayrıntı paneli

### 🚀 İyileştirmeler
- Menü çubuğu düzenleyici: canlı önizlemede sürükle-bırak sıralama, raftan ekle/kapat, tıkla-ayarla
- Eşik renkleri: değer uyarı eşiğinde turuncu, kritikte kırmızı (%, °C, ms, dBm)
- Ağ modülüne ping, Wi-Fi sinyali, VPN kilidi ve çevrimdışı uyarısı
- Yeni görünümler: CPU çekirdek çubukları, pasta, disk okuma/yazma; sıcaklık için sensör seçimi
- Bakım yenilendi: 8 görev, yönetici görevleri tek parolayla, canlı durum ve son çalıştırma bilgisi

### 🛠 Düzeltmeler
- Release derlemesindeki tüm derleyici uyarıları temizlendi
- İzin verilince macOS uygulamayı yeniden başlattığında kurulum sihirbazı kaldığı yerden sürüyor

## 0.1.2 — 3 Kasım 2026

### ✨ Yeni araçlar
- **Wi-Fi Analizi** — sinyal, gürültü, BSSID, çevredeki ağların kanal yoğunluğu ve modem için kanal önerisi
- **Ağ Trafiği** — hangi uygulamanın ne kadar indirip yüklediği, canlı
- **Disk Sağlığı** — SSD yıpranması, yazılan veri ve sıcaklık (NVMe SMART)
- **USB ve Thunderbolt** — takılı aygıtlar, bağlantı hızı ve güç; yavaş kablo uyarısı
- **Hosts Dosyası** — alan adlarını yönlendir veya engelle, grupları tek tıkla aç/kapat
- **Ekran Görüntüsü** — alan, pencere ve tam ekran yakalama, önizleme kartları, geçmiş ve işaretleme
- **Ekran Ayarları** — gizli HiDPI modları, yenileme hızı, ana ekran ve yansıtma
- **Bluetooth Pilleri** — Logitech dahil aygıt pilleri ve düşük pil bildirimi

### 🚀 İyileştirmeler
- Fan kontrolü ve Güç Merkezi’nde fan kartı
- Menü çubuğuna en sıcak sensör ve Bluetooth pil göstergeleri
- Gizli Ayarlar’a performans grubu: animasyonlar, App Nap ve Dock ayarları
- Monitör hoparlörleri için ses ve sessiz tuşları (DDC)
- Temizlik taramasında profiller ve kategori seçimi, yeni tarama animasyonu
- macOS 27 temel sürüm oldu; yeni Enerji sayfası

### 🛠 Düzeltmeler
- Şarj kablosuyla bağlı Bluetooth aygıtları listede kalıyor
