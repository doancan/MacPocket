<p align="center">
  <img src="Design/logo.png" width="128" height="128" alt="MacPocket simgesi">
</p>

<h1 align="center">MacPocket</h1>

<p align="center">
  <b>Mac’ini izle, bakımını yap, ayarlarını keşfet — hepsi tek bir native uygulamada.</b><br>
  Sistem izleme · güç yönetimi · temizlik · 50’den fazla araç
</p>

<p align="center">
  <a href="https://github.com/doancan/MacPocket/releases/latest"><img alt="Sürüm" src="https://img.shields.io/github/v/release/doancan/MacPocket?label=s%C3%BCr%C3%BCm"></a>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-27%2B-black?logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange?logo=swift">
  <img alt="Testler" src="https://img.shields.io/badge/testler-1467-brightgreen">
  <img alt="Diller" src="https://img.shields.io/badge/dil-T%C3%BCrk%C3%A7e%20%C2%B7%20English-lightgrey">
</p>

<p align="center">
  <a href="https://github.com/doancan/MacPocket/releases/latest"><b>İndir</b></a> ·
  <a href="#öne-çıkanlar">Öne çıkanlar</a> ·
  <a href="#araçlar">Araçlar</a> ·
  <a href="#derleme">Derleme</a> ·
  <a href="CHANGELOG.md">Değişiklikler</a> ·
  <a href="docs/PRODUCT.md">Yol haritası</a>
</p>

---

## Öne çıkanlar

- **SSH Yöneticisi** — kayıpsız config düzenleme, bağlantı/ProxyJump testleri, Terminal/iTerm2/Ghostty, anahtarlar, known_hosts, yedekler ve global kısayollu hızlı bağlantı. SSHConfigManager kaynakları yerel paketlerle bu projeye taşındı; [aktarım ve doğrulama notları](docs/SSH_INTEGRATION.md).
- **AI kullanım takibi** — Claude, Codex/ChatGPT ve Grok için çoklu hesap kotaları, menü çubuğu göstergeleri, yüzen panel ve kota uyarıları; [kapsam ve doğrulama](docs/AI_USAGE.md).
- **Pratik Araçlar** — ayrı çalışma alanında 14 biçimli Case Converter, JSON, Base64, URL, JWT, hash, UUID, parola, Unix zamanı, metin karşılaştırma ve QR/Wi-Fi QR; çevrimdışı, arama ve favorilerle.
- **Canlı sistem izleme** — CPU, RAM, disk, ağ ve sensörler; en sıcak sensörün trendi ve menü çubuğunda istediğin göstergeler.
- **Uygulama başına ağ trafiği** — hangi uygulamanın şu an ne kadar indirip yüklediği, yardımcı süreçler uygulamada toplanmış halde.
- **Wi-Fi analizi** — sinyal, gürültü, BSSID, çevredeki ağların kanal yoğunluğu ve modem için kanal önerisi.
- **Kablo etki haritası** — kabloyu çekmeden önce bağlı diskleri, açık dosyaları, TCP/SSH oturumlarını ve ekran/ses etkilerini gör; otomatik bağlantılar ile elle eşleştirmeler ayrı gösterilir. [Kapsam ve doğrulama](docs/CABLE_IMPACT.md).
- **Disk sağlığı** — SSD’nin kendi bildirdiği yıpranma, yazılan veri ve sıcaklık (NVMe SMART), yönetici izni gerekmeden.
- **Temizlik ve uygulama bakımı** — büyük/eski ve aynı içerikli dosyalar, uygulama kalıntıları, Homebrew güncelleme/kaldırma.
- **Alt+Tab pencere geçişi** — animasyonlu önizleme kartları; dokuz kısayol için bağımsız filtre, görünüm ve bırakma davranışı; özelleştirilebilir pencere eylemleri.
- **Gizli ayarlar** — Dock, Finder, ekran görüntüsü ve performans ayarlarını Terminal’e girmeden değiştir.
- **Ekran Süresi** — hangi uygulamada ne kadar zaman geçirdiğin; boşta ve kilitli süre sayılmaz, veriler bu Mac’te kalır.
- **Esnek menü çubuğu** — CPU, GPU, RAM, disk, ağ ve sensörler; sürükle-bırak düzenleyici ve eşik renkleri.
- **Menü çubuğu düzenleyici** — diğer uygulamaların simgelerini gizli grupta topla, ok düğmesiyle göster ve aranabilir listeden aç.
- **Bağımsız güncelleme merkezi** — Sparkle, isteğe bağlı App Store ve uygulamaya bağlanan herkese açık GitHub kaynaklarından sürüm denetimi; kurulum üreticinin akışında devam eder.
- **İnternet kontrolü** — imzalı uygulama kimliğine göre yeni bağlantılar için kurallar ve Network Extension uzantısı. Gerçek engellemenin sistem onayı ve canlı kabulü bekliyor; [kapsam, imzalama ve doğrulama](docs/PRODUCT_EXPANSION.md).
- **Otomatik güncelleme** — imzalı güncellemeler uygulama içinden.
- **İki dil** — arayüzün tamamı Türkçe ve İngilizce.

## İndirme

İmzalı ve notarize edilmiş paket [GitHub Releases](https://github.com/doancan/MacPocket/releases/latest)
sayfasındadır: `MacPocket-0.1.6-macOS-arm64.dmg` dosyasını aç, kurulum penceresinde **MacPocket** ikonunu
**Applications / Uygulamalar** klasörüne sürükle. Kopyalama bitince uygulamayı Uygulamalar’dan açıp disk görüntüsünü çıkarabilirsin.
Türkçe/İngilizce yönergeler kurulum penceresindedir. ZIP paketi de alternatif indirme ve otomatik güncellemeler için sunulur.
Apple Silicon ve macOS 27 gerekir. 0.1.3’ten itibaren yeni sürümler uygulama içinden (Sparkle) kurulur.
Depo özel olduğunda indirme GitHub erişimi gerektirir. Mevcut özel depo için anonim Sparkle adresi 404 döndüğünden uygulama içi güncelleme yerine Release sayfasından indirerek kurulum kullanılmalıdır.

## Araçlar

| | Grup | Araçlar |
| :-: | --- | --- |
| 🖥️ | **Sistem ve ağ** | Görev Yöneticisi · Ağ Trafiği · Wi-Fi Analizi · Ağ Hız Testi · Port Yöneticisi · Hosts Dosyası · USB ve Thunderbolt · Sistem Raporları · Destek Raporu · Gizli Ayarlar · Bakım · Başlangıç Öğeleri · macOS Araçları |
| 💽 | **Disk ve dosyalar** | Disk Sağlığı · USB Çıkarma Yöneticisi · Disk Analizi · büyük/eski dosyalar · aynı içerikli dosyalar (SHA-256) · Benzer Görseller · Uygulama Kalıntıları |
| 🪟 | **Ekran** | Ekran Ayarları (gizli HiDPI modları, yenileme hızı, yansıtma) · Ekran Parlaklığı · Ekran Görüntüsü · Ekran Kaydı · Ekrandan Al · Ekran Temizleme |
| ⚡ | **Üretkenlik** | Ekran Süresi · Pencere Geçişi · Pencere Yerleşimi · Masa Düzenleri · Pano Geçmişi · Metin Kısaltmaları · Makrolar · Hızlı İşlemler · Odak Oturumu · Kapatma Koruması · Uygulama Dondurucu · Mac’i Uyanık Tut |
| 🎧 | **Ses ve aygıtlar** | Ses Çıkışı · Ses Mikseri · Fare Kaydırma · Bluetooth Pilleri (Logitech HID++ dahil) |
| 🧰 | **Pratik Araçlar** | Case Converter (14 biçim, Türkçe/İngilizce, canlı önizleme) · JSON düzenleme/küçültme · Base64 ve URL kodlama · JWT inceleme · SHA-256/SHA-512 · UUID v4 · güvenli parola/token · Unix zamanı · satır karşılaştırma · QR/Wi-Fi QR ve PNG |
| 🔒 | **Gizlilik ve güvenlik** | Gizlilik Kontrolü (mikrofon/kamera bildirimi) · Sistem Güvenliği (SIP, Gatekeeper) |

Ana bölümler: Genel Bakış, Sistem İzleme, Güç Merkezi, Temizlik, Disk Analizi, Uygulamalar, Araçlar ve Pratik Araçlar.
Menü çubuğu birleşik grup veya ayrı CPU, GPU, RAM, disk, ağ (ping, Wi-Fi, VPN), güç ve sensör göstergeleri
sunar; Ayarlar’daki canlı düzenleyicide sürükle-bırak sıralanır, görünüm ve eşik renkleri modül başına ayarlanır.

## Durum

| | |
| --- | --- |
| Sürüm | **0.1.6** |
| Testler | 1.467 uygulama testi; 4 gerçek disk/sistem testi ve 1 bağlı trackpad testi isteğe bağlıdır. SSHConfigKit: 384, AIUsageKit: 420 test (3 isteğe bağlı atlama). |
| Yerelleştirme | Türkçe (kaynak) ve İngilizce, eksik anahtar yok |
| Belgeler | [Native macOS davranışları](docs/NATIVE_MACOS.md) · [Derleme ve canlı doğrulama](docs/NATIVE_BUILD.md) · [Alt+Tab kart geçişi](docs/WINDOW_SWITCHER.md) · [Devam eden geliştirme](docs/CONTINUED_DEVELOPMENT.md) |
| Yeni araçlar | [Menü çubuğu, bağımsız güncellemeler ve internet kontrolü](docs/PRODUCT_EXPANSION.md) |

<details>
<summary><b>Bilinen sınırlar</b></summary>

- Geliştirme pilsiz bir Mac Studio’da yapılır; MacBook şarj sınırı/durdurma ve pil donanımı burada doğrulanmış sayılmaz.
- Gelişmiş güç otomasyonları henüz tamamlanmadı.
- Tam AltTab, iStat veya CleanMyMac eşdeğerliği iddia edilmez; fiziksel klavye/trackpad, haptik ve üçüncü taraf uygulama kapsamındaki açık kontroller [pencere geçişi belgesindedir](docs/WINDOW_SWITCHER.md#bekleyen-canlı-kabul).
- Hosts dosyasını kaydetmek macOS yönetici onayı ister.
- AI Dosyaları aracı kullanıcı isteğiyle kaldırıldı.

</details>

<details>
<summary><b>Diğer belgeler</b></summary>

- [Ürün kapsamı ve geliştirme sırası](docs/PRODUCT.md)
- [MacBook güç yönetimi: izleme, şarj, profiller ve otomasyon](docs/POWER_MANAGEMENT.md)
- [Özelleştirme, seçenekler ve ayar profilleri](docs/CUSTOMIZATION.md)
- [Sistem Merkezi, Görev Yöneticisi ve canlı doğrulama](docs/SYSTEM_CENTER.md)
- [CleanMyMac My Tools eşlemesi](docs/CLEANMYMAC_TOOLS.md)
- [İlk referans incelemesi ve teknik bulgular](docs/research/2026-10-28-initial.md)

</details>

## Derleme

```sh
make build
make test
make probe
make app           # Debugger erişimi olan geliştirme uygulaması
make app-release   # Optimize uygulama, debugger entitlement olmadan
make dmg           # Optimize uygulama ve sürükle-bırak DMG kurulum penceresi
swift run macpocket-probe processes
swift run macpocket-probe diagnostic swap
```

Derlenen uygulama `.build/MacPocket.app` içindedir.
Çalışan uygulamanın pencere geçişine terminalden erişmek için
`.build/MacPocket.app/Contents/MacOS/MacPocket --switcher list --detailed` kullanılabilir.
ID/MRU ile odaklama ve panel aç/kapat komutları [pencere geçişi belgesindedir](docs/WINDOW_SWITCHER.md#on-yedinci-aşama--çalışan-uygulamaya-bağlı-cli).
Tasarım kaynağı `Design/macpocket-system-center.html` içindedir; HTML önizleme örnek veri kullanır.
[Etkileşimli tasarımı aç](https://p.superdesign.dev/draft/dd6d81b7-5129-4332-966b-ae40c5b265f0).

## Geliştirici araçları

Tersine mühendislik ve hata ayıklama ortamı (REA, LLDB, Frida, Ghidra, Rizin) proje betikleriyle kurulur.

<details>
<summary><b>Kurulum ve kullanım ayrıntıları</b></summary>

### Hazırlanan araçlar

| Araç | Kullanım |
| --- | --- |
| REA 6.8.0 | Komut satırı, Codex MCP bağlantısı ve REA skill |
| Xcode LLDB ve LLDB DAP | Native breakpoint, değişken okuma ve çağrı gözlemi |
| Frida 17.23.2 | REA üzerinden çalışma zamanında fonksiyon hook |
| Ghidra 12.1.4 | ARM64 decompiler ile native kod analizi |
| OpenJDK 25 | Ghidra çalışma ortamı |
| Rizin 0.9.1 | Binary bilgisi ve statik inceleme |
| Node.js 26.12.1 | REA çalışma ortamı; Node Inspector da dahildir |

REA 6.8.0 için Ghidra 12.1.4 sabitlenmiştir. Homebrew'daki Ghidra 12.2
bu REA sürümü tarafından kabul edilmez. Kurulum betiği resmi Ghidra
arşivini indirir, yayımlanan SHA-256 değerini kontrol eder ve gerekirse
Mac'in mimarisine uygun decompiler'ı derler.

### Kullanım

Proje kökünde:

```sh
make check    # Sürümler, Codex bağlantısı, skill ve Ghidra kontrolü
make smoke    # Küçük yerel örnek üzerinde LLDB, Frida, Rizin ve Ghidra testi
make debug    # Örneği etkileşimli LLDB ile aç
```

`make debug` içinde:

```text
breakpoint set --name macpocket_add
run
frame variable left right
continue
quit
```

REA komutlarını proje ortamıyla çalıştırmak için:

```sh
./scripts/rea.sh --help
./scripts/rea.sh inspect /uygulamanin/tam/yolu --provider ghidra
./scripts/rea.sh decompile /programin/tam/yolu fonksiyon_adi --provider ghidra
```

Örnek kaynaklar `tools/` altında, derleme çıktıları ve test raporları
Git'e dahil edilmeyen `.build/` altındadır. Referans paketleri, çıkarılan
binary'ler, analiz snapshot'ları ve tam REA kanıtları `.build/research/`
altında saklanır.

### Yeniden kurulum

[Homebrew](https://brew.sh) ve Xcode/Command Line Tools kurulu bir Mac'te:

```sh
make setup
make smoke
```

Kurulum REA'yı global olarak yükler; Codex'in kullanıcı yapılandırmasına MCP
kaydını ve `~/.agents/skills/reverse-engineer-anything` dizinine skill'i ekler.
Mevcut Codex yapılandırması REA tarafından yedeklenir. Kurulumdan sonra
yeni araçların yüklenmesi için Codex'i yeniden başlatın.

Ghidra varsayılan olarak
`~/.local/share/macpocket/toolchains/ghidra_12.1.4_PUBLIC` altına kurulur.
Farklı konum için `MACPOCKET_GHIDRA_HOME` kullanılabilir.
Java ve Ghidra yollarını proje betikleri hazırlar; shell profilini değiştirmek
gerekmez. Projeye özel MCP/skill kopyası oluşturulmaz.

REA'nın GDB ve kalıcı Rizin debugger oturumları Linux gerektirir. macOS'ta
debugging için LLDB ve Frida kullanılır; Rizin statik inceleme için hazırdır.
Bu Mac'te Rizin 0.9.1 örnek Mach-O dosyasının temel bilgilerini döndürürken
`Incomplete buffer read` tanıları da üretiyor. Smoke testi bu araç için
yalnızca temel binary bilgisini doğrular; tanılar `.build/rizin-rea.json`
içinde saklanır. Native decompilation Ghidra ile ayrıca doğrulanır.

Kaynaklar: [REA kurulumu](https://github.com/morluto/rea/blob/main/docs/installation.md),
[REA debugger desteği](https://github.com/morluto/rea/blob/main/docs/reverse-engineering-tools.md),
[Ghidra 12.1.4](https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.1.4_build),
[Codex MCP yapılandırması](https://developers.openai.com/learn/docs-mcp).

</details>
