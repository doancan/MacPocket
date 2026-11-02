# Gece modu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ekran Parlaklığı zaman çizelgesine "Güneşe göre" modu: konumdan gün doğumu/batımı, akşam parlaklık düşüşü + renk ısıtma (macOS Night Shift ya da MacPocket gamma), isteğe bağlı istisnalar.

**Architecture:** Saf hesaplar (güneş, Kelvin→RGB, gece eğrisi) `MacPocketCore`'da test edilir. `DisplayBrightnessService` gamma'yı tek noktada birleştirir (orijinal × renk × parlaklık). Yeni `NightModeService` (App) konumu, Night Shift'i ve istisnaları yönetir, her dakika (geçişte 15 sn) hedef parlaklık/sıcaklığı hesaplayıp servise uygular.

**Tech Stack:** Swift 6, SwiftUI/AppKit, CoreLocation, CoreGraphics gamma, özel CoreBrightness (`CBBlueLightClient`), XCTest.

**Spec:** `docs/superpowers/specs/2026-11-02-night-mode-design.md`

## Global Constraints

- macOS 14+; hardened runtime; sandbox yok; Developer ID imzalı.
- Kullanıcıya görünen her metin yerelleştirilebilir (TR kaynak, EN `Resources/en.lproj/Localizable.strings`); `rawValue` gösterilmez, `localizedTitle` kullanılır; `scripts/check-localizations.sh` 0 eksik.
- Sürüm/build numarasına, etiketlere, Release'e dokunulmaz (AGENTS.md).
- Varsayılanlar: gece parlaklığı 0.6, gece sıcaklığı 3400 K, gündüz 6500 K (= katsayı 1,1,1), gün batımı geçişi 60 dk (batıştan 30 dk önce → 30 dk sonra), gün doğumu 30 dk; seçilebilir geçiş 20 / 60 / 120 dk.
- İstisnalar varsayılan kapalı. f.lux eşdeğerliği iddia edilmez.
- Spec'teki "Okuyucu kontrolünden sonra verilen kararlar" 1–6 bağlayıcıdır: gece parlaklığı ekranın temel seviyesine göreli; renk yalnız güneş modunda; elle değişiklik yalnız parlaklığı geçiş bitene kadar bekletir; Night Shift'i MacPocket sürer ve önceki durumu diske yazar; istisnalar ikisini de ~2 sn'de kaldırır; gamma geri okuma uyuşmazsa ekran kartında not.
- Çıkışta/çökme kurtarmada gamma ve Night Shift önceki durumuna döner.

## Review Focus

- Konum izni reddedildi / henüz sorulmadı → sayfada nedeni ve şehir seçimi görünür, çizelge şehirle çalışır (Task 5 testi: konum yoksa `NightModeService.status == .needsLocation`).
- Elle parlaklık değişikliği gece modunda → bir sonraki geçiş noktasına kadar beklenir, renk ısıtma sürer (Task 6 testi).
- Yazılımsal karartılmış ekranda renk ısıtma → ikisi birlikte kalır, biri diğerini ezmez (Task 3 testi: compose sırası).
- Night Shift seçiliyken yöntem değiştirme ya da çıkış → kullanıcının önceki Night Shift durumu (etkin + güç + mod) geri yüklenir (Task 4 testi, sahte istemciyle).
- Kutup günü/gecesi ve gece yarısını geçen geçişler → değerler sıçramaz (Task 1–2 testleri).

---

### Task 1: Güneş hesabı (Core)

**Files:**
- Create: `Sources/MacPocketCore/SolarSchedule.swift`
- Test: `Tests/MacPocketCoreTests/NightModeTests.swift`

**Interfaces:**
- Produces: `public struct Coordinate: Codable, Equatable, Sendable { latitude: Double; longitude: Double }`;
  `public enum SolarDay: Equatable, Sendable { case normal(sunrise: Date, sunset: Date), alwaysDay, alwaysNight }`;
  `public enum SolarCalculator { static func day(containing date: Date, at: Coordinate, timeZone: TimeZone) -> SolarDay }` (NOAA formülü, resmi zenit 90.833°).

- [ ] **Step 1: Failing tests** — `testIstanbulSummerSolstice`: 2026-06-21, (41.0082, 28.9784), Europe/Istanbul → gün doğumu 05:32, batımı 20:39 (±2 dk). `testIstanbulWinterSolstice`: 2026-12-21 → 08:21 / 16:41 (±2 dk). `testTromsoPolarNightAndMidnightSun`: (69.6492, 18.9553) 2026-12-21 → `.alwaysNight`, 2026-06-21 → `.alwaysDay`.
- [ ] **Step 2:** `swift test --filter NightModeTests` → derleme hatası (tip yok).
- [ ] **Step 3:** `SolarCalculator.day` uygula.
- [ ] **Step 4:** Testler geçer.
- [ ] **Step 5:** Commit `feat: sunrise and sunset from a coordinate`.

### Task 2: Renk sıcaklığı ve gece eğrisi (Core)

**Files:**
- Modify: `Sources/MacPocketCore/SolarSchedule.swift`
- Modify: `Sources/MacPocketCore/DisplayControl.swift` (`BrightnessSchedule`)
- Test: `Tests/MacPocketCoreTests/NightModeTests.swift`

**Interfaces:**
- Produces: `public enum ColorTemperature { static func channelFactors(kelvin: Double) -> (red: Double, green: Double, blue: Double) }` (Tanner Helland, 6500 K ve üstü = (1,1,1), en düşük 1900 K'ye kırpılır, her katsayı 0…1).
- Produces: `public struct NightSettings: Codable, Equatable, Sendable` — `nightLevel = 0.6`, `nightKelvin = 3400.0`, `transitionMinutes = 60`, `dimBrightness = true`, `warmColor = true`, `colorMethod: ColorMethod = .macPocket`, `baseLevels: [String: Double] = [:]` (`enum ColorMethod: String, Codable, CaseIterable { case macPocket, nightShift }`), `location: Coordinate?`, `locationName: String?`, `pausedUntil: Date?`, `excludedApps: [String] = []`, `pauseForFullScreenVideo = false`.
- Produces: `public struct NightTarget: Equatable, Sendable { night: Double /*0 gündüz…1 gece*/; level: Double; kelvin: Double }`;
  `public enum NightCurve { static func target(at date: Date, day: SolarDay, settings: NightSettings) -> NightTarget }` — gün batımı geçişi `[sunset − T/2, sunset + T/2]`, gün doğumu geçişi `[sunrise − 15 dk, sunrise + 15 dk]` (30 dk sabit), smoothstep; `level` = temel seviyeye uygulanacak çarpan `1 − night·(1 − nightLevel)`, `kelvin = 6500 − night·(6500 − nightKelvin)`.
- Produces: `BrightnessSchedule.source: Source?` (`enum Source: String, Codable { case manual, solar }`, nil = manual) ve `BrightnessSchedule.night: NightSettings?` (eski kayıtlar çözülsün diye opsiyonel).

- [ ] **Step 1: Failing tests** — `testDaylightIsNeutral`: `channelFactors(6500) == (1,1,1)`. `testWarmCutsBlueMost`: 3400 K'de `red == 1`, `blue < green < 1`. `testCurveMidTransitionIsHalfway`: sunset 18:00, T=60, 18:00'de `night == 0.5`, `level == 0.8` (çarpan; nightLevel 0.6). `testCurveBeforeAndAfter`: 17:29 → night 0; 18:31 → 1; gün doğumundan 16 dk sonra → 0. `testPolarDays`: `.alwaysNight` → night 1, `.alwaysDay` → night 0. `testOldScheduleDecodes`: `{"enabled":true,"points":[...]}` JSON'u `source == nil`, `night == nil` ile çözülür.
- [ ] **Step 2:** Çalıştır → fail.
- [ ] **Step 3:** Uygula.
- [ ] **Step 4:** Geçer.
- [ ] **Step 5:** Commit `feat: color temperature and the night curve`.

### Task 3: Gamma'yı tek noktada birleştir (App)

**Files:**
- Modify: `Sources/MacPocketApp/DisplayBrightnessService.swift` (`applySoftware`, `GammaTable`, `restoreSoftwareDimming`)
- Modify: `Sources/MacPocketCore/DisplayControl.swift` (saf birleştirme)
- Test: `Tests/MacPocketCoreTests/NightModeTests.swift`

**Interfaces:**
- Produces (Core): `public enum GammaComposer { static func compose(_ channel: [Float], factor: Float, scale: Float) -> [Float] }` = her değer × factor × scale.
- Produces (App): `DisplayBrightnessService.setWarmth(_ factors: (red: Double, green: Double, blue: Double))` — tüm yönetilen ekranlara uygulanır; (1,1,1) ve parlaklık tam iken orijinal tablo geri konur. Gamma her zaman `original × warmth × softwareScale` olarak tek fonksiyonda (`applyGamma(_ id:)`) yazılır; donanım (DDC) ekranlarda `softwareScale = 1`.

- [ ] **Step 1: Failing test** — `testComposeAppliesWarmthThenBrightness`: `compose([1, 0.5], factor: 0.5, scale: 0.8) == [0.4, 0.2]`.
- [ ] **Step 2:** fail. **Step 3:** uygula (`applySoftware` → `applyGamma`, `originalGamma` ilk değişiklikte yakalanır, `restoreSoftwareDimming` sıcaklığı da sıfırlar). **Step 4:** tüm testler geçer.
- [ ] **Step 5:** Commit `refactor: compose software dimming and warmth in one gamma write`.

### Task 4: Night Shift istemcisi (App)

**Files:**
- Create: `Sources/MacPocketApp/NightShiftClient.swift`
- Test: `Tests/MacPocketCoreTests/NightModeTests.swift` (protokol Core'da)

**Interfaces:**
- Produces (Core): `public protocol NightShiftControlling: AnyObject { var isAvailable: Bool { get }; func snapshot() -> NightShiftState?; func apply(enabled: Bool, strength: Double); func restore(_ state: NightShiftState) }`, `public struct NightShiftState: Codable, Equatable, Sendable { enabled: Bool; strength: Double; mode: Int }`; `public final class NightShiftSession { init(client:); func activate(strength:); func deactivate() }` — ilk `activate`'te `snapshot()` alınır, `deactivate` onu geri yükler, ikinci `deactivate` hiçbir şey yapmaz.
- Produces (App): `final class NightShiftClient: NightShiftControlling` — `dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness")`, `CBBlueLightClient`; `setEnabled:`, `setStrength:commit:`, `setMode:`, `getBlueLightStatus:`, `getStrength:`. Sınıf ya da seçici yoksa `isAvailable == false`. Strength: Kelvin'den `(6500 − kelvin) / (6500 − 1900)` kırpılmış 0…1.

- [ ] **Step 1: Failing test** — `testSessionRestoresPreviousNightShift`: sahte istemci `{enabled:false, strength:0.3, mode:1}`; `activate(0.7)` → sahte `enabled true, strength 0.7`; `deactivate()` → `restore` önceki durumla bir kez çağrılır.
- [ ] **Step 2–4:** fail → uygula → geçer. Canlı: `NightShiftClient().isAvailable` bu Mac'te `true` olduğunu bir kez yazdır (hata ayıklama yolu, Task 6).
- [ ] **Step 5:** Commit `feat: drive macOS Night Shift and restore it afterwards`.

### Task 5: Konum (App + paket ayarları)

**Files:**
- Create: `Sources/MacPocketApp/NightLocationProvider.swift`
- Create: `Sources/MacPocketCore/CityCatalog.swift` (küçük gömülü liste: Türkiye'nin 81 il merkezi + 40 büyük dünya şehri, ad + koordinat)
- Modify: `Resources/Info.plist` (`NSLocationUsageDescription`, `NSLocationWhenInUseUsageDescription`), `Resources/MacPocketRelease.entitlements` ve `Resources/MacPocket.entitlements` (`com.apple.security.personal-information.location`)
- Test: `Tests/MacPocketCoreTests/NightModeTests.swift`

**Interfaces:**
- Produces: `@MainActor final class NightLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate` — `@Published authorization: CLAuthorizationStatus`, `func request()` (kCLLocationAccuracyReduced; tek sefer `requestLocation`), `var onLocation: (Coordinate, String?) -> Void` (ad `CLGeocoder` ile şehir, başarısızsa nil). Günde en fazla bir kez yeniler.
- Produces: `public enum CityCatalog { static let all: [City] }`, `public struct City: Identifiable, Hashable, Sendable { name: String; coordinate: Coordinate }`.
- Kullanım açıklaması metni (TR): "MacPocket, gece modunda gün doğumu ve gün batımı saatlerini hesaplamak için yaklaşık konumunu kullanır; konum bu Mac’ten çıkmaz."

- [ ] **Step 1: Failing test** — `testCityCatalogHasIstanbulAndUniqueNames`: "İstanbul" var, adlar benzersiz, tüm enlemler −90…90.
- [ ] **Step 2–4:** fail → uygula → geçer; `plutil -lint` Info.plist ve entitlements temiz.
- [ ] **Step 5:** Commit `feat: location for the night schedule, with a city fallback`.

### Task 6: NightModeService (App)

**Files:**
- Create: `Sources/MacPocketApp/NightModeService.swift`
- Modify: `Sources/MacPocketApp/DisplayBrightnessService.swift` (`applySchedule` → güneş modunda NightModeService'e bırak), `Sources/MacPocketApp/PocketStatusItemController.swift` (servisi başlat; sağ tık menüsüne "Gece modunu 1 saat kapat" / "Gece modunu yeniden aç")
- Test: `Tests/MacPocketCoreTests/NightModeTests.swift` (karar mantığı Core'da)

**Interfaces:**
- Produces (Core): `public enum NightPause { static func isPaused(now: Date, settings: NightSettings, frontmostBundleID: String?, fullScreenVideo: Bool) -> Bool }`.
- Produces (App): `@MainActor final class NightModeService: ObservableObject { static let shared; enum Status { case off, needsLocation, active(NightTarget), paused(until: Date?) }; @Published private(set) var status; func start(); func pauseForAnHour(); func resume(); var debugNow: Date? }`.
  Temel seviye: `NightSettings.baseLevels: [String: Double]` (ekran anahtarı → gündüz seviyesi); gündüz elle değişiklik temeli günceller; uygulanan = temel × `NightTarget.level`.
  Night Shift önceki durumu `MacPocket.night.nightShiftSnapshot` anahtarında saklanır; `start()` bir kayıt bulursa (çökme) önce onu geri yükler.
  Gamma geri okuma: `setWarmth` sonrası `GammaTable.read` ile karşılaştır, uyuşmayan ekranlar `@Published warmthUnsupported: Set<CGDirectDisplayID>`.
  Değerlendirme: her 60 sn, geçiş içindeyken 15 sn; ön uygulama değişince (`NSWorkspace.didActivateApplicationNotification`) hemen. Parlaklık `DisplayBrightnessService.setLevel(_:for:fromSchedule: true)` ile (elle değişiklik `overrideUntil`'i bugünkü gibi kurar → parlaklık beklenir, renk sürer). Renk: `colorMethod == .macPocket` → `setWarmth`, `.nightShift` → `NightShiftSession`; yöntem değişince eskisi geri alınır. Duraklatmada her ikisi nötre geçer. Tam ekran video: öndeki uygulamanın ekranı kaplayan penceresi (CGWindowList, layer 0) ve aynı pid'in `PreventUserIdleDisplaySleep` assertion'ı.
  Hata ayıklama: `defaults write com.doancan.MacPocket MacPocket.night.debugNow -string "2026-11-02T18:00:00+03:00"` varsa `debugNow` olarak kullanılır (yalnız DEBUG ve release'te de okunur ama arayüzde gösterilmez).

- [ ] **Step 1: Failing tests** — `testPauseUntilFutureDate`, `testExcludedFrontmostAppPauses`, `testFullScreenVideoOnlyWhenOptedIn` (`pauseForFullScreenVideo == false` iken `fullScreenVideo: true` → false).
- [ ] **Step 2–4:** fail → uygula → geçer.
- [ ] **Step 5:** Commit `feat: night mode follows the sun with optional pauses`.

### Task 7: Arayüz ve yerelleştirme

**Files:**
- Modify: `Sources/MacPocketApp/DisplayBrightnessView.swift` (`BrightnessScheduleCard`)
- Modify: `Resources/en.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `NightModeService.shared` (status, pause/resume), `NightSettings`, `CityCatalog`, `NightLocationProvider`.
- Kart: başlık "Zaman çizelgesi" + anahtar; altında segment "Elle saatler / Güneşe göre". Güneşe göre: konum satırı (şehir adı + "Konumu kullan" / şehir menüsü; izin reddedildiyse uyarı + Sistem Ayarları düğmesi), bugünün gün doğumu/batımı, "Parlaklığı düşür" anahtarı + gece parlaklığı kaydırıcısı (mevcut `BrightnessFillSlider` dili), "Rengi ısıt" anahtarı + gece sıcaklığı kaydırıcısı (1900–6500 K, gösterim K), "Renk yöntemi" (MacPocket / macOS Night Shift — Night Shift yoksa devre dışı ve açıklama), "Geçiş süresi" menüsü (20 dk / 1 saat / 2 saat), istisnalar bölümü ("Bir saatliğine kapat" düğmesi, "Tam ekran video oynarken kapat" anahtarı, "Bu uygulamalar öndeyken kapat" listesi + Ekle/Sil). Grafik güneş modunda 24 saatlik eğriyi `NightCurve` ile çizer.
- Tüm yeni metinlerin İngilizce karşılıkları.

- [ ] **Step 1:** Uygula; `swift build` temiz (yeni uyarı yok).
- [ ] **Step 2:** `scripts/check-localizations.sh` → 0 eksik.
- [ ] **Step 3:** Commit `feat: night mode controls on the brightness page`.

### Task 8: Canlı kabul ve belgeler

- [ ] **Step 1:** `MACPOCKET_SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh release`, `.build/MacPocket.app` başlat.
- [ ] **Step 2:** `debugNow` = gün batımı ortası → iki harici ekranda parlaklık ~%80 ve sıcak renk (ekran görüntüsü); gece → %60 ve 3400 K; gündüz → nötr.
- [ ] **Step 3:** Night Shift yöntemi: önce kullanıcının Night Shift durumunu kaydet, gece moduna gir, çık/yöntem değiştir → önceki durum geri gelir.
- [ ] **Step 4:** Uygulamadan çık → renkler nötr.
- [ ] **Step 5:** Konum izni verilmeden şehir seçimiyle çalışma.
- [ ] **Step 6:** `docs/NATIVE_MACOS.md`'ye kısa "Gece modu" bölümü: neyin statik, neyin canlı doğrulandığı ayrı ayrı. `swift test` tamamı + l10n 0 eksik. Commit `docs: night mode acceptance notes`.
