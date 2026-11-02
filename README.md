# MacPocket

Proje deposu: [doancan/MacPocket](https://github.com/doancan/MacPocket).

MacPocket; CPU/RAM/disk izleme ve MacBook odaklı gelişmiş güç yönetimini, temizlik ve uygulama bakımını,
Tools altında pencere geçişini ve Mac'i uyanık tutmayı bir araya getiren
native macOS projesidir.

- [Ürün kapsamı ve geliştirme sırası](docs/PRODUCT.md)
- [MacBook güç yönetimi: izleme, şarj, profiller ve otomasyon](docs/POWER_MANAGEMENT.md)
- [Özelleştirme, seçenekler ve ayar profilleri](docs/CUSTOMIZATION.md)
- [Sistem Merkezi, Görev Yöneticisi ve canlı doğrulama](docs/SYSTEM_CENTER.md)
- [CleanMyMac My Tools eşlemesi](docs/CLEANMYMAC_TOOLS.md)
- [İlk referans incelemesi ve teknik bulgular](docs/research/2026-10-28-initial.md)

Mevcut sürüm **0.1.0**. Genel Bakış, Sistem İzleme, Güç Merkezi, Temizlik,
Disk Analizi, Uygulamalar ve Tools ana bölümleridir. Görev Yöneticisi ve sekiz
sistem raporu Tools altında açılır. Native kenar/araç çubukları, Liquid Glass,
menü çubuğu hızlı bakışı, Ayarlar, tema ve oturum açılışında başlatma desteği vardır.

Dosya taraması, klasör boyutları, büyük/eski dosya filtreleri, SHA-256 ile
aynı içerikli dosyalar ve onaylı Çöp işlemleri çalışır. Uygulama envanteri,
bundle kimliğiyle ilişkili dosya kaldırma planı ve Homebrew güncelleme/kaldırma
kanalı eklendi. Pencere Geçişi, macOS erişim durumuna göre uygulama veya pencere
listesi sunar. Güç geçmişi yerel kaydedilir. **68 çekirdek testi geçti.**
[Derleme ve canlı doğrulama](docs/NATIVE_BUILD.md) · [Native macOS davranışları](docs/NATIVE_MACOS.md).

Geliştirme devam ediyor; sürüm numarası yalnız kullanıcı isteğiyle değiştirilir.
Homebrew dışındaki güncelleme kanalları, gelişmiş güç otomasyonları ve MacBook
şarj sınırı/durdurma henüz tamamlanmadı. Tam AltTab eşdeğerliği iddia edilmez;
özel Spaces davranışları ve bütün görünüm seçenekleri henüz eşlenmedi.

Menü çubuğu birleşik grup veya ayrı CPU/RAM/disk/pil/güç göstergeleri, sıralama,
birim, etiket, yazı boyutu ve mini gösterge seçenekleri sunar. Pencere Geçişi
Alt+Tab kısayol kaydı, animasyonlu kart şeridi, filtre/hariç tutma, AX pencere
eylemleri ve izinli seçili pencere önizlemesi içerir. macOS araçlarına 11 gerçek
sorgu, uygulama kalıntısı aday taraması, yerel Vision benzer görsel karşılaştırması
ve süre sınırı olan ekran temizleme eklendi. AI Dosyaları kullanıcı isteğiyle kaldırıldı.
[Alt+Tab kart geçişi](docs/WINDOW_SWITCHER.md) · [Devam eden geliştirme ve kabul kapsamı](docs/CONTINUED_DEVELOPMENT.md).

## Native uygulama

```sh
make build
make test
make probe
make app           # Debugger erişimi olan geliştirme uygulaması
make app-release   # Optimize uygulama, debugger entitlement olmadan
swift run macpocket-probe processes
swift run macpocket-probe diagnostic swap
```

Derlenen uygulama `.build/MacPocket.app` içindedir.
Tasarım kaynağı `Design/macpocket-system-center.html` içindedir; HTML önizleme örnek veri kullanır.
[Etkileşimli tasarımı aç](https://p.superdesign.dev/draft/dd6d81b7-5129-4332-966b-ae40c5b265f0).

## Hazırlanan araçlar

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

## Kullanım

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

## Yeniden kurulum

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
