# Değişiklik Günlüğü

## Yayımlanmamış

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
