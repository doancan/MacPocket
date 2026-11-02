# Mimari: mole.fit kazanımları → MacPocket

Girdi: `replica/recon.md`, `replica/features.csv`. Bu proje native macOS (Swift 6, SwiftPM, macOS 14+) olduğundan
skill'in web varsayılanları (Next.js, Postgres, Stripe...) **uygulanmaz**; mevcut yapı korunur. Veritabanı/SQL yok:
`schema.sql` yerine aşağıdaki Swift tipleri ve kalıcılık kuralları vardır. "API" yerine servis sınırları ve XPC komut listesi vardır.

Karar (kullanıcı): yetkili işlemler **yapılacak**, eksiksiz, yüksek kalitede. "macOS özellikleri" = native entegrasyonlar
(SMAppService, XPC, CoreAudio/CoreMediaIO, UserNotifications, Liquid Glass) olarak yorumlandı; farklıysa söyle.

## 1. Yığın (değişmiyor)
| katman | seçim | neden |
| --- | --- | --- |
| dil/derleme | Swift 6 + SwiftPM | mevcut; tek `Package.swift` |
| mantık | `MacPocketCore` (UI'sız, test edilebilir) | mevcut katman kuralı |
| arayüz | SwiftUI + AppKit köprüsü, Liquid Glass | mevcut `PocketDesign` |
| kalıcılık | `UserDefaults` (ayar), uygulama klasöründe JSON (geçmiş) | mevcut `AppPreferences`/`PowerHistory`; DB gerekmez |
| süreç çalıştırma | `BoundedProcess` | süre sınırı + iptal zaten çözülmüş |
| yetkili işlem | **yeni hedef `MacPocketHelper`** + XPC | bkz. 2 |
| yerelleştirme | `String(localized:)` + `Localizable.strings` | `scripts/check-localizations.sh` 0 eksik şart |
| test | `MacPocketCoreTests` (44 dosya) | mevcut stil |

Yeni üçüncü taraf bağımlılık yok.

## 2. Yetkili yardımcı (en kritik karar)
**Bulgu:** bu Mac'te geçerli kod imzalama kimliği yok (`security find-identity` → 0). `SMAppService.daemon` ve
XPC istemci doğrulaması gerçek Developer ID/Apple Development imzası ister; ad-hoc imzada onay ve doğrulama güvenilmez.

Bu yüzden tek arayüz, iki arka uç:

```swift
// Core: yetkili işlemin tek giriş noktası (UI bunu bilir, arka ucu bilmez)
protocol PrivilegedExecuting: Sendable {
    func run(_ command: PrivilegedCommand) async throws -> PrivilegedResult
    var availability: PrivilegedAvailability { get }   // .ready | .needsApproval | .unsigned | .unsupported(reason)
}
```
| arka uç | ne zaman | davranış |
| --- | --- | --- |
| `HelperDaemonExecutor` | imzalı derleme (Developer ID) | `SMAppService.daemon` LaunchDaemon + `NSXPCConnection`; Ayarlar'da bir kez onay → oturum başına tekrar sorma yok |
| `AdminPromptExecutor` | imzasız/ad-hoc (bugünkü durum) | işlem başına macOS yönetici penceresi (`AuthorizationExecuteWithPrivileges` yerine `osascript ... with administrator privileges` çağrısı, sabit komut listesinden) |

"Oturumda tek yetkilendirme" (features.csv) yalnız `HelperDaemonExecutor` ile sağlanır; `AdminPromptExecutor`'da her işlemde sorar ve bunu arayüzde dürüstçe yazar.

**Güvenlik kuralları (pazarlık dışı):**
- Yardımcı **keyfi komut çalıştırmaz.** `PrivilegedCommand` kapalı bir `enum`; her durumun sabit yolu ve doğrulanmış parametreleri vardır. Örnek durumlar: `.deleteLocalSnapshot(date)`, `.setAWDL(enabled)`, `.flushDNS`, `.rebuildFontCache`, `.runPeriodic`, `.setFan(rpm)`.
- Parametreler yardımcıda yeniden doğrulanır (tarih biçimi, aralıklar); UI'ya güvenilmez.
- Daemon yalnız kendi imza gereksinimini (`setCodeSigningRequirement`) sağlayan istemciyi kabul eder.
- Her işlem log'lanır (komut adı + sonuç; kullanıcı yolu/kişisel veri yok).
- Geri alınamayan her işlem önce önizleme + açık onay ister (dry-run kuralı).

## 3. Yeni/genişleyen Core modülleri (Sources/MacPocketCore)
| dosya | durum | sorumluluk | feature satırları |
| --- | --- | --- | --- |
| `PrivilegedCommand.swift` | yeni | komut enum + doğrulama | yetki, WiFi, bakım |
| `PrivilegedExecutor.swift` | yeni | protokol + AdminPrompt arka ucu | aynı |
| `Sources/MacPocketHelper/` | yeni hedef | daemon + XPC dinleyici | imzalı derleme |
| `CleanupTargets.swift` | genişler | + hedefler (tarayıcı/bulut/iletişim/tasarım önbelleği, proje artıkları, yükleyici süpürme), `managedSeparately` | Temizlik |
| `SystemDataCleanup.swift` | yeni | snapshot silme, `Install macOS*.app` listesi, sistem cache | Sistem Verisi |
| `InUseDetector.swift` | yeni | açık dosya tutan süreç → "kullanımda" | Güvenlik |
| `StartupItems.swift` | yeni | LaunchAgents/Daemons + `SMAppService` okuma, 3 sınıf | Başlangıç öğeleri |
| `ApplicationServices.swift` | genişler | kanal protokolü: Homebrew (var), Sparkle appcast, GitHub Releases, App Store | Güncellemeler |
| `ApplicationLeftovers.swift` | genişler | 15+ kategori, `pkgutil` makbuzu, Dock girdisi | Kaldırma |
| `MaintenanceTasks.swift` | yeni | görev kataloğu + destek durumu (macOS sürümü/donanım) | Optimize |
| `HealthScore.swift` | yeni | saf fonksiyon: ölçümler → puan + bileşen açıklaması | Durum |
| `PrivacyMonitor.swift` | yeni | mikrofon/kamera canlı kullanım | Gizlilik |
| `WiFiLowLatency.swift` | yeni | AWDL aç/kapat + geri alma tetikleyicileri | Araçlar |
| `FanControl.swift` | yeni (araştırma spike'ı sonrası) | fan hedef devri yazma | Durum |

Bağımlılık yönü: View → Model → Core servis → `PrivilegedExecuting`/`BoundedProcess`. Çekirdek mantık saf kalır; I/O sınırda.

## 4. Veri tipleri ("şema")
```swift
enum StartupClass: Sendable { case direct, systemManaged, readOnly }
struct StartupItem: Identifiable, Sendable { let id: String; let label: String; let plistURL: URL?; let kind: StartupClass; let isEnabled: Bool }
struct MaintenanceTask: Identifiable, Sendable { let id: MaintenanceTaskID; let needsAdmin: Bool; let support: SupportState }
enum SupportState: Sendable { case supported, unsupported(reason: String) }   // gerekçe zorunlu (CLAUDE: donanım desteği gösterilir)
struct PrivacyUsage: Sendable { enum Device { case microphone, camera }; let device: Device; let appName: String?; let startedAt: Date }
struct HealthScore: Sendable { let total: Int; let parts: [Part] }   // Part: ad, 0-100, ağırlık, neden
```
Kalıcı: `ignoredPrivacyApps: [String]` (bundle id), `wifiLowLatencyWasOn: Bool` (çökme sonrası geri alma için), `pinnedProcessNames: [String]`, bakım son sonuçları (JSON).
Tüm zamanlar `Date` (UTC), gösterimde yerel saat dilimi.

## 5. Servis sınırları ("rotalar", akışlara göre)
| akış | çağrı | yetki | not |
| --- | --- | --- | --- |
| F01/F02 | `CleanupScanner.scan(targets)` → `CleanupPlan`; `execute(plan)` | kullanıcı | `managedSeparately` toplama girmez; `InUseDetector` uyarır |
| F01 | `SystemDataCleanup.snapshots()` / `.delete(date)` | yönetici (`.deleteLocalSnapshot`) | önce liste + onay |
| F03 | `UninstallPlanner.plan(app)` genişler | kullanıcı (+ Çöp) | makbuz/Dock kategorileri |
| F04 | `StartupItems.list()`, `.setEnabled(item)` | `.direct` kullanıcı; `.systemManaged` Ayarlar'a yönlendirir | `.readOnly` asla değiştirilmez |
| F05 | `MaintenanceTasks.run(ids)` | görev başına | görev başı sonuç + kısmi hata |
| F06 | `PrivacyMonitor.events` (AsyncStream) | yok (izin gerekmez) | bildirim `UNUserNotificationCenter` |
| F07 | `WiFiLowLatency.setEnabled(_)` | `.setAWDL` | geri alma: uyku, çıkış, ağ değişimi, çökme sonrası açılışta |
| Durum | `HealthScore.compute(snapshot)` | yok | saf, test edilebilir |

## 6. Isırabilecek noktalar
- **AWDL:** kapatmak AirDrop/Handoff/Sidecar'ı etkiler. Her çıkış yolunda (uyku, `NSApplication.willTerminate`, `NWPathMonitor` değişimi, bir sonraki açılışta kalıcı bayrakla) geri alınmazsa kullanıcı AirDrop'suz kalır. En yüksek risk.
- **Kamera/mikrofon:** CoreMediaIO ve CoreAudio özellikleri uygulama adını vermez; mikrofon için `kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyIsRunningInput` (macOS 14.2+) ile süreç→uygulama eşlemesi **doğrulanmalı**. Kamera adı verilmez (Mole da vermiyor).
- **Fan yazma:** Apple Silicon'da SMC yazması kısıtlı olabilir; bu Mac Studio'da gerçekten mümkün mü **kanıtlanmadı** → önce spike (yalnız okuma/izin testi), sonuç yoksa özellik `unsupported(reason)` olarak gösterilir, hiç yazılmaz.
- **Idempotans/yarış:** silmeden hemen önce `lstat` kimliği yeniden doğrulama (`CleanupTargets` zaten yapıyor) tüm yeni silme yollarında korunur. Yardımcı çağrıları idempotent olmalı (`awdl0 down` iki kez zararsız).
- **macOS sürümüne göre destek:** `periodic` yalnız eski macOS'ta etkili; font cache komutları sürümle değişir. `SupportState` ile gerekçeli gizle.
- **Güncelleme kanalı yanlış-pozitif:** Sparkle appcast'te sürüm karşılaştırması bozuk olabilir; yalnız güvenilir `CFBundleShortVersionString` karşılaştırması, belirsizse "bilinmiyor".
- **Türkçe/Unicode:** yollar ve uygulama adları NFC/NFD farklı olabilir; karşılaştırmada normalize et.
- **Yerelleştirme:** her yeni metin `String(localized:)`; `rawValue` gösterme; en.lproj eşleşmesi.

## 7. Yapım sırası
**Hazırlık (M0):** `PrivilegedCommand` + `AdminPromptExecutor` + testleri; `HelperDaemonExecutor` iskeleti ancak imza kimliği gelince etkinleşir (kimlik yokken test edilemez; bunu raporla).

| kilometre taşı | ekranlar | içerik |
| --- | --- | --- |
| **M1 dikey dilim** | S11 | Gizlilik Kontrolü uçtan uca (yetki gerekmez; yeni modülün sınırlarını kanıtlar) |
| **M2 must** | S01, S02, S04, S06 | `InUseDetector`, temizlik hedefi genişletme, `managedSeparately`, Sistem Verisi liste, Quick Look bakımı, StartupItems okuma, kompakt HUD, Ekran Temizleme renk/kilit |
| **M3 yetkili** | S02, S06, S13 | snapshot silme, WiFi Düşük Gecikme (+geri alma), font/DNS/periodic bakım |
| **M4 should** | S03, S05, S08, S09 | güncelleme kanalları, kaldırma kategorileri, `HealthScore`, bento 60 sn, süreç sabitleme |
| **M5 could** | S08, S10 | fan yazma (spike sonucuna bağlı), koşucu animasyonu, Parallels, SQLite vacuum |

Her kilometre taşında: `make test`, `scripts/check-localizations.sh`, `make build`, gerçek uygulamada uçtan uca deneme, `features.csv` `clone` sütununu güncelleme. AGENTS.md gereği sürüm/build numarası değişmez, etiket/Release yok.

## 8. Uygulama notları (M1 sırasında bulundu)
- `PowerSettings.swift` zaten `NSAppleScript ... with administrator privileges` ile yönetici çalıştırıcı içeriyor. M3'te `AdminPromptExecutor` sıfırdan yazılmaz; bu kod `PrivilegedExecuting` arkasına taşınır/genişletilir.
- `scripts/build-app.sh` imzalama kimliği yokken sessizce çıkış kodu 1 veriyor (`grep` boş sonuç + pipefail). Çözüm bekliyor; geçici: `MACPOCKET_SIGN_IDENTITY=- ./scripts/build-app.sh`.
