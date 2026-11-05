# SSH Yöneticisi aktarımı

SSHConfigManager'ın SSH özellikleri MacPocket'a gömülüdür. Ana sol menüde tek **SSH Yöneticisi** girişi bulunur; Sunucular, SSH Anahtarları, Bilinen Sunucular, Yedekler ve SSH Ayarları sayfanın içindedir. Kaynak uygulamanın orijinal ikonu kullanılır.

## Bağımsız kaynak ve paketleme

- `Sources/MacPocketSSH`: SwiftUI ekranları, modeller, terminal başlatıcıları, hızlı bağlantı paneli ve MacPocket yaşam döngüsü bağlantısı.
- `Packages/SSHConfigKit`: parser, config/known_hosts depoları, atomik yazma, dosya izleme, anahtar yönetimi, SSH süreçleri ve testleri. Yerel Swift paketi; başka proje klasörüne bağlantı yoktur.
- `Packages/KeyboardShortcuts`: 2.4.0 kaynakları, çevirileri ve MIT lisansı. Yerel Swift paketi.
- `Resources/SSHManagerIcon.icns`: orijinal uygulamanın ikonunun bağımsız kopyası.
- Kısayol kaydedicisinin dokuz metni için paket içinde Türkçe çeviri de sağlanır ve denetlenir. Türkçe kaynak metinleri `String(localized:defaultValue:)` ile, İngilizce karşılıkları ana uygulamanın `Resources/en.lproj/Localizable.strings` tablosuyla sunulur. SSH anahtarları `SSH.` önekiyle ayrılır. Paket kaynakları da yerelleştirme kontrolüne dahildir.
- `scripts/build-app.sh`, kısayol kaydedicisinin `KeyboardShortcuts_KeyboardShortcuts.bundle` paketini uygulamanın Resources dizinine kopyalar. SSH paketleri çalıştırılabilir dosyaya bağlanır. Mevcut Sparkle framework'ü uygulama içinde paketlenir.

SSHConfigManager kaynak klasörü derleme veya çalışma sırasında kullanılmaz. SwiftPM önbellekleri ve önceki derleme çıktıları kaynak kodun yerine geçmez. MacPocket'ın önceden var olan Sparkle bağımlılığı korunur.

## Özellik eşlemesi

| Özellik | Uygulama | Doğrulama |
| --- | --- | --- |
| Host ekleme, düzenleme, çoğaltma, silme; grup yönetimi | HostList, AppModel, ConfigDocument | HostCommands, HostEditorModel, AppModel, HostGroup testleri |
| Yorumlar/girintiler/tekrarlı seçenekler; Include ve Match korunması | SSHConfigKit/Config ve Resolve | Round-trip, IncludeResolver, ConfigResolver testleri; canlı geçici dosya kaydı |
| Kaydetmeden diff ve `ssh -G` doğrulaması | SaveFlowModel, SaveSheet, ConfigStore | SaveFlowModel/ConfigStore testleri; gerçek `ssh -G` ve kayıt |
| Çakışma algılama, dosya izleme, atomik yazma | ConfigStore, SafeFileWriter, FileWatcher | Hata, yarış, dış değişiklik ve iptal testleri |
| Etkin ayarlar ve kaynakları | EffectiveSettings, EffectiveConfigCache | Etkin ayar ve önbellek testleri; gerçek `ssh -G` |
| ProxyJump zinciri ve zincir testi | ProxyChainModel/View | ProxyChainModel ve bağlantı testi modelleri |
| Tekli/toplu bağlantı testleri ve hata sınıflandırma | ConnectionTestsModel, ConnectionTester | Eşzamanlılık/iptal/sınıflandırma testleri; gerçek loopback SSH hata sonucu |
| Terminal, iTerm2 ve Ghostty; güvenli komut oluşturma | TerminalLaunchers, Connector, SSHCommandBuilder | TerminalLaunching/SSHCommandBuilder testleri |
| Bulanık arama, favoriler, son bağlantılar, bağlantı önizlemesi | QuickConnectModel, HostMemory | QuickConnectModel/HostMemory/FuzzyMatcher testleri; canlı arama/favori kontrolü |
| Global kısayol ve hızlı bağlantı paneli | SSHRuntime, QuickConnectPanel | Kaynak/derleme; özgün KeyboardShortcuts uygulaması korunur |
| Menü çubuğundan hızlı bağlantı | PocketMenuBarView → SSHQuickConnectView | Kaynak/derleme; ana popover'ın terminal simgesinden erişim |
| Komut çubuğundan bölümlere ve hızlı bağlantıya erişim | CommandBarService | Kaynak/derleme |
| known_hosts araması, hash eşleştirme, kontrollü silme; değişmiş host anahtarı akışı | KnownHostsModel/Store, HostKeyRemoval | HostMatcher, KnownHostsStore/Model, HostKeyRemoval testleri |
| Anahtar tarama, SHA256 parmak izi, parola/agent/kullanım bilgisi | KeysModel, KeyScanner/Inspector/Usage | KeysModel ve SSHConfigKit anahtar testleri; canlı anahtar üretimi ve kullanım listesi |
| Ed25519/RSA4096 üretme, host'a atama, agent, yükleme, parola değiştirme, çöp kutusu | KeyManager, KeySheets, KeyTools | Geçici dosyalarda gerçek ssh-keygen; yan etkileri enjekte edilen model testleri |
| Config/known_hosts yedek karşılaştırma ve geri yükleme | BackupsModel/View, BackupManager | BackupsModel ve BackupManager testleri; canlı config geri yükleme taslağı |
| Dosya yolları, yedek sayısı, terminal ve global kısayol ayarları | SettingsView, AppSettings | AppModel ve ayar testleri; canlı ayar ekranı |
| Çıkışta kaydedilmemiş değişiklik koruması | SSHRuntime.prepareToTerminate → PocketAppDelegate | Kaynak/derleme; kayıt/engellenmiş taslak altyapısı testleri |

Uygulama genelindeki tema, Dock görünürlüğü, girişte başlatma, dil ve Sparkle güncellemeleri MacPocket'ın mevcut ayarlarına aittir; ayrı bir SSHConfigManager uygulama kimliği/güncelleme kanalı başlatılmaz.

## Mevcut verilerin taşınması

- Gerçek `~/.ssh/config`, `known_hosts` ve anahtarlar yerinde kullanılır; kaynak proje silinince bu dosyalar silinmez.
- Standalone uygulamanın `tr.com.mess.SSHConfigManager` tercih alanından config/known_hosts yolları, terminal, yedek sayısı, favoriler ve son bağlantılar bir kez kopyalanır. MacPocket'ta önceden ayarlanmış değerler ezilmez.
- Önceki global kısayol, MacPocket'ın `KeyboardShortcuts_MacPocket.SSH.quickConnect` anahtarına taşınır; mevcut MacPocket kısayolu korunur.
- Eski yedekler `~/Library/Application Support/MacPocket/SSH/Backups` altına kopyalanır. Kaynak yedekler korunur. Aynı adlı farklı yedekler sıra numarasıyla saklanır. Hatalı aktarım yeniden denenebilir.
- SSH'ye özgü tercihler `com.doancan.MacPocket.SSH` alanında tutulur.

## Çalıştırılabilir kontroller

```sh
swift test --filter MacPocketSSHTests
swift test --package-path Packages/SSHConfigKit
scripts/check-localizations.sh
scripts/build-app.sh debug
```

DEBUG uygulamasında `--ssh-fixture <geçici-home>` ile gerçek SSH dosyalarına, agent'a ve keychain'e dokunmadan beş sayfa açılabilir. `--audit-ssh <rapor.json>` normal düzenleyici, kayıt, yedek, `ssh -G`, geçici anahtar üretimi ve 960/1280 pt sayfa kontrollerini çalıştırır. Gerçek ağ kontrolü yalnızca loopback adresindedir; terminal başlatma fixture'da enjekte edilir. Fixture modu üretim derlemesine dahil değildir.

## Kaydedilen kanıt

5 Kasım 2026, Mac Studio, macOS 27; sürüm **0.1.4**, build **7** korundu.

- Uygulama/modeller: 355 test geçti. Parser/SSH altyapısı: 384 test geçti.
- MacPocket genel testleri: 739 test, 0 hata; mevcut 4 isteğe bağlı gerçek donanım/sistem testi atlandı. Ayrıca 355 SSH model testi aynı koşuda geçti.
- Canlı fixture: Türkçe ve İngilizce için beş bölüm × iki genişlik; her dilde 58 kontrol geçti. Proje dışına kopyalanan imzalı uygulamada sekme sınırları, tablonun son sütununa yatay kaydırma ve hızlı bağlantı paneli/arama odağı da doğrulandı. Raporlar `.build/ssh-port/detached-tr.json` ve `detached-en.json`.
- Yerelleştirme: 4.002 anahtar; 0 eksik çeviri, 0 biçim uyuşmazlığı, 0 kullanılmayan çeviri.
- Kaynaklar proje dışında bağımsız bir geçici klasöre kopyalanıp boş derleme diziniyle başarıyla derlendi. `Package.swift` SSH bağımlılıkları yalnızca `Packages/SSHConfigKit` ve `Packages/KeyboardShortcuts` yerel yollarıdır.
- Görsel kanıt: `.build/ssh-port/detached-tr-*.png` ve `detached-en-*.png`: her bölüm için 960/1280 pt; ayrıca hızlı bağlantı paneli. Dar pencerede sekme çubuğunun eski genişliğe takılması düzeltildi; beş sekmenin tamamının gerçek AX çerçeveleri pencere sınırları içinde ölçüldü.
- Debug paketleme ve Release derlemesi başarılı; derin/sıkı kod imzası doğrulandı. Nihai gereksinim kontrolü `.build/ssh-port/completion-verification.json` içinde kaydedildi.
- Paket bağımlılıkları ve ikon hash’i `.build/ssh-port/package-verification.json` içinde kaydedildi. Kaynak proje yoluna veya paket dışındaki bir SSH kütüphanesine dinamik bağlantı yoktur; sistem dışındaki Sparkle framework’ü uygulamada bulunur. Kısayol paketinin Türkçe kaynakları ve lisansı da paketlendi.

Uzak bir gerçek sunucuya oturum açıldığı, gerçek kullanıcı anahtarının agent/keychain'e eklendiği veya bir sunucuya yüklendiği iddia edilmez. Terminal uygulamalarının dış otomasyon kabulü, kurulu terminal ve macOS Otomasyon iznine bağlıdır; bu entegrasyonda başlatma ve hata/fallback yolları test doubles ile doğrulanmıştır. Görsel/AX kontrolleri tam VoiceOver kabulü yerine geçmez.
