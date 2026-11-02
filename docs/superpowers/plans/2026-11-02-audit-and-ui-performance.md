# Denetim ve arayüz performansı Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boştaki uygulama CPU'sunu düşürmek (gereksiz ana iş parçacığı yoklamasını kaldırarak) ve mevcut özellikleri gerçek akışla doğrulayıp denetim tablosuna işlemek.

**Architecture:** Arka plan zamanlayıcıları yalnızca gerçekten iş olduğunda çalışır. "İş var mı" kararı Core'da saf, test edilebilir özelliklerdir; servisler (App katmanı) bu kararı zamanlayıcıyı kurmak/durdurmak için kullanır. Davranış değişmez, yalnızca gereksiz yoklama kalkar.

**Tech Stack:** Swift 6 / SwiftUI, XCTest (mevcut `Tests/MacPocketCoreTests`), SwiftPM.

**Spec:** `docs/superpowers/specs/2026-11-02-audit-and-ui-performance-design.md`

## Global Constraints

- Sürüm/build numarası, etiket ve GitHub Release değiştirilmez (AGENTS.md).
- Kullanıcıya görünen her metin yerelleştirilir; `scripts/check-localizations.sh` 0 eksikle geçmeli.
- Yeni bağımlılık eklenmez.
- Commit mesajlarında AI/Claude imzası yok; `Claude-Session` satırı hariç tutulur (kullanıcı talimatı önceliklidir). Commit yalnızca kullanıcı isterse atılır; bu plandaki "commit" adımları kullanıcı onayına bağlıdır.
- Pilsiz Mac Studio: pil/şarj davranışı doğrulanmış sayılmaz.

## Review Focus

- Mikser: ayarlı (nötr olmayan) uygulama varken sayfa kapalıysa tap'ler çalışmaya devam etmeli (polling durmamalı).
- Mikser: ayar tekrar nötr olunca ve sayfa kapalıyken polling durmalı, açık tap'ler bırakılmalı.
- Dondurucu: özellik kapalıyken dondurulmuş uygulama kalmamalı (thaw hâlâ çalışmalı).
- Dondurucu: kural yokken veya özellik kapalıyken `evaluate()` hiçbir sinyal göndermemeli.
- Çıkışta (`thawAll`, `stopAll`) zamanlayıcı durmuş olmalı, çift başlatma ikinci zamanlayıcı kurmamalı.

---

### Task 1: Core — "yoklama gerekli mi" kararları

**Files:**
- Modify: `Sources/MacPocketCore/VolumeMixer.swift`, `Sources/MacPocketCore/AppFreezer.swift`
- Test: `Tests/MacPocketCoreTests/VolumeMixerTests.swift`, `Tests/MacPocketCoreTests/AppFreezerTests.swift`

**Interfaces:**
- Produces: `VolumeMixerSettings.hasActiveEntries: Bool` (en az bir giriş `!isNeutral`); `AppFreezerSettings.hasWork: Bool` (`enabled && !rules.isEmpty`).

- [ ] **Step 1: Başarısız testleri yaz**
  - `VolumeMixerTests.testHasActiveEntries`: boş ayar → `false`; `entries["a"] = .init(volume: 1)` → `false`; `.init(volume: 0.5)` → `true`; `.init(muted: true)` → `true`; yalnız nötr + bir ayarlı → `true`.
  - `AppFreezerTests.testHasWork`: varsayılan → `false`; `enabled = true`, kural yok → `false`; `enabled = true` + bir kural → `true`; `enabled = false` + kural → `false`.
- [ ] **Step 2: Çalıştır, derleme hatasıyla başarısız olduğunu gör:** `swift test --filter "VolumeMixerTests|AppFreezerTests"`
- [ ] **Step 3: İki hesaplanan özelliği ekle** (imzalar yukarıda; tek satırlık gövdeler).
- [ ] **Step 4: Aynı komutla geçtiğini doğrula** (0 hata).
- [ ] **Step 5: Commit (kullanıcı isterse)** `feat: expose whether mixer/freezer polling has work`

### Task 2: Ses mikseri — yalnızca gerektiğinde yokla

**Files:**
- Modify: `Sources/MacPocketApp/VolumeMixerView.swift` (`VolumeMixerService`, `VolumeMixerView`)

**Interfaces:**
- Consumes: `VolumeMixerSettings.hasActiveEntries`.
- Produces: `VolumeMixerService.setViewVisible(_ visible: Bool)`; `private func updatePolling()` zamanlayıcıyı `viewVisible || settings.hasActiveEntries` koşuluna göre kurar/durdurur.

- [ ] **Step 1:** `start()` artık `refresh()` çağırıp `updatePolling()` çalıştırır; zamanlayıcı yalnızca koşul doğruyken vardır (zaten varsa ikinci kurulmaz, koşul yanlışsa `invalidate` + `nil`). `settings.didSet` sonunda `updatePolling()` de çağrılır.
- [ ] **Step 2:** `VolumeMixerView`: `.onAppear { service.setViewVisible(true) }`, `.onDisappear { service.setViewVisible(false) }`. `setViewVisible(true)` ayrıca `refresh()` çağırır (mevcut `onAppear` davranışı korunur).
- [ ] **Step 3:** Çıkış yolu `stopAll()` zamanlayıcıyı da durdurmaz (uygulama kapanırken zaten biter); davranış değişmez.
- [ ] **Step 4: Doğrula:** `swift build` temiz; `swift test` geçer.
- [ ] **Step 5: Commit (kullanıcı isterse)** `perf: poll the audio mixer only when visible or in use`

### Task 3: Uygulama dondurucu — işi yoksa yoklama

**Files:**
- Modify: `Sources/MacPocketApp/AppFreezerService.swift`

**Interfaces:**
- Consumes: `AppFreezerSettings.hasWork`.
- Produces: `evaluate()` içinde, `!settings.hasWork && frozen.isEmpty` ise erken dönüş (hiçbir uygulama listesi taranmaz). `frozen` doluyken (özellik kapatıldıysa) mevcut davranışla thaw edilir.

- [ ] **Step 1:** `evaluate()` başına guard ekle. Gözlemciler ve 15 sn zamanlayıcı yerinde kalır (ucuz hale geldi).
- [ ] **Step 2: Doğrula:** `swift test` (`AppFreezerTests` karar mantığını zaten kapsar) geçer.
- [ ] **Step 3: Commit (kullanıcı isterse)** `perf: skip app scan when the freezer has nothing to do`

### Task 4: Güç Merkezi yoklama maliyetini ölç

**Files:**
- Modify (yalnızca ölçüm sonucu gerektiriyorsa): `Sources/MacPocketApp/PowerCenterModel.swift`

- [ ] **Step 1:** Güç Merkezi açıkken 30 sn `sample MacPocket 30` al; `PowerInspector.overview`/`refreshEnergy` altındaki ana iş parçacığı payını kaydet.
- [ ] **Step 2:** Pay toplamın %10'unu aşıyorsa okuma çağrısını arka plana taşı ve yeniden ölç; aşmıyorsa değişiklik yapma ve sonucu spec'e yaz.

### Task 5: Önce/sonra ölçümü ve regresyon

- [ ] **Step 1 (önce — Task 2'den önce yapılır):** `make app`, uygulamayı aç, hiçbir sayfa açık değilken 60 sn boyunca 5 sn aralıkla `ps -o %cpu=` ortalamasını kaydet.
- [ ] **Step 2 (sonra):** Aynı derleme/yöntemle ölç. Beklenen: ortalama belirgin düşer; düşmezse `sample` ile yeni sıcak noktayı bul, kapanmış sayma.
- [ ] **Step 3:** `swift test`, `scripts/check-localizations.sh` (0 eksik), `swift build -c release --product MacPocket` hepsi geçer.
- [ ] **Step 4:** Mikser regresyonu: nötr olmayan bir uygulama ayarla, sayfayı kapat, tap'in çalışmaya devam ettiğini sistem sesinde doğrula (bu makinede ses çıkışı gerekir; yoksa "doğrulanamadı" olarak yaz).

### Task 6: Özellik denetimi (arayüzden)

**Files:**
- Create: `docs/FEATURE_AUDIT.md`

- [ ] **Step 1:** Spec'teki özellik listesinin her biri için gerçek akışı çalıştır (mutlu yol + boş/geçersiz girdi + Türkçe karakter). Tabloya durum yaz: çalışıyor / hata (kısa tanım) / bu makinede doğrulanamaz.
- [ ] **Step 2:** Her "hata" için önce başarısız test, sonra düzeltme, sonra tabloyu güncelle. Büyük çıkan hata ayrı task/plana ayrılır, bu planda gizlice büyütülmez.
