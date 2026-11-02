# Gece modu: konuma göre otomatik karartma ve renk ısıtma — tasarım

Tarih: 2 Kasım 2026 · Durum: onaylandı (2 Kasım 2026)

## Amaç ve neden

Kullanıcı, f.lux'taki gibi ekranın akşamları **kendiliğinden ve yavaş yavaş** kararmasını ve renginin ısınmasını istiyor.
Saatleri elle girmek istemiyor: MacPocket bulunduğu yerin gün doğumu/gün batımını kendisi bulmalı, mevsimle kayan
saatleri kendiliğinden takip etmeli. macOS'un kendi Night Shift modu varken onu da kullanabilmeli; kim neyi isterse
onu seçebilmeli. İstisnalar (geçici kapatma, belirli uygulamalar, tam ekran video) **isteğe bağlı** olmalı.

f.lux ile tam eşdeğerlik iddia edilmez (AGENTS.md). Hedef, yukarıdaki üç özelliktir.

## Hedefler

1. **Güneşe göre çizelge.** Konumdan gün doğumu ve gün batımı hesaplanır (cihaz üzerinde, ağ gerekmez). Akşam gün
   batımına doğru, sabah gün doğumuna doğru yumuşak geçiş olur.
2. **Parlaklık + renk birlikte.** Harici ekranların parlaklığı düşer ve ekran rengi sıcak tona döner. İkisi ayrı ayrı
   açılıp kapatılabilir.
3. **Renk için iki yöntem, kullanıcı seçer:**
   - **macOS Night Shift:** MacPocket, Night Shift'i gece açar, gündüz kapatır ve sıcaklık gücünü ayarlar.
   - **MacPocket renk ısıtması:** ekranın renk tablosunu (gamma) MacPocket değiştirir; f.lux gibi.
4. **İsteğe bağlı istisnalar:** "Bir saatliğine kapat", "Seçilen uygulamalar öndeyken kapat", "Tam ekran video
   oynarken kapat". Hepsi varsayılan olarak kapalı; açan kullanır.
5. Arayüz Türkçe + İngilizce; mevcut Ekran Parlaklığı sayfasının tasarım diliyle uyumlu.

## Hedef olmayanlar

- f.lux'un diğer özellikleri (Darkroom/ters renk, uyku saatine göre "yatma modu", Hue ampul kontrolü, film modu
  ön ayarları, geriye sayan alarm) bu işin kapsamında değil.
- Dahili ekranın parlaklığı: mevcut araçta olduğu gibi dahili ekran macOS'a bırakılır. (Bu Mac'te dahili ekran yok;
  dahili ekran davranışı burada doğrulanamaz.)
- Ağdan gün doğumu verisi çekmek yok; hesap yerel.

## Anti-hedefler (çalışsa bile başarısızlık sayılır)

- Geçişlerin göze batması: parlaklık/renk adım adım "zıplamamalı".
- Renk ısıtmasının mevcut yazılımsal karartmayla çakışıp birini ezmesi ya da çıkışta/çökmede ekranı sarı/karanlık
  bırakması.
- Night Shift seçiliyken kullanıcının kendi Night Shift ayarlarını kalıcı olarak bozmak (MacPocket kapatılınca veya
  yöntem değiştirilince önceki Night Shift durumu geri gelmeli).
- Konum izni verilmediğinde özelliğin sessizce çalışmaması: kullanıcı nedenini görmeli ve şehir seçerek devam edebilmeli.

## Kısıtlar

- macOS 14+ (Package.swift), sandbox yok, hardened runtime açık, Developer ID ile imzalı ve notarize.
- Konum için hardened runtime'da `com.apple.security.personal-information.location` entitlement'ı ve Info.plist'te
  konum kullanım açıklaması gerekir (her ikisi de şu an yok).
- Night Shift'in herkese açık API'si yok; özel `CoreBrightness` çerçevesindeki `CBBlueLightClient` ile kontrol edilir.
  Çalışma anında bulunamazsa Night Shift seçeneği devre dışı görünür ve nedeni yazılır (BrightnessIndicator'daki
  OSDManager yaklaşımıyla aynı ilke).
- Yazılımsal karartma zaten gamma tablosunu ölçekliyor (`DisplayBrightnessService.applySoftware`, `originalGamma`).
  Renk ısıtması aynı tabloyu kullanır; ikisi **tek bir yerde birleştirilerek** uygulanmalı (önce orijinal tablo,
  sonra renk katsayıları, sonra parlaklık ölçeği).
- Çıkışta `restoreSoftwareDimming()` hem karartmayı hem ısıtmayı geri almalı; çökme kurtarma da aynı.
- Geliştirme makinesi pilsiz, harici iki ekranlı (MateView, LG HDR 4K), macOS 27. Kabul testi bu iki ekranda yapılır;
  dizüstü/dahili ekran davranışı doğrulanmış sayılmaz.

## Kullanıcının kararları

- Saat kaynağı: konuma göre otomatik (gün doğumu/batımı).
- Hem parlaklık düşsün hem renk ısınsın.
- Renk için macOS Night Shift ile MacPocket'in kendi ısıtması arasında seçim olsun.
- İstisnalar seçimlik olsun.

## Benim kararlarım (kullanıcı söylemedi; kontrol edilmeli)

- **Mevcut "Zaman çizelgesi" kalır** ve bir mod seçimi kazanır: "Elle saatler" (bugünkü noktalar) / "Güneşe göre".
  Güneşe göre modda gece parlaklığı ve gece renk sıcaklığı tek birer kaydırıcıdır; noktalar gizlenir.
- **Varsayılanlar:** gece parlaklığı %60, gece renk sıcaklığı 3400 K (gündüz 6500 K = değişiklik yok), geçiş süresi
  gün batımında 60 dk (batıştan 30 dk önce başlayıp 30 dk sonra biter), gün doğumunda 30 dk. Geçiş süresi
  seçilebilir: 20 dk / 60 dk / 2 saat.
- **Konum:** Konum Servisleri'nden bir kez alınır, yaklaşık konum (şehir hassasiyeti) yeterli; koordinat diskte
  saklanır ve günde en fazla bir kez yenilenir. İzin yoksa listeden şehir seçilir (ya da enlem/boylam girilir).
- **Hesap:** NOAA güneş konumu formülü, Core'da saf Swift; kutup gününde/gecesinde (güneş doğmaz/batmaz) gece ya da
  gündüz değeri sabit uygulanır.
- **Seçilen uygulamalar** listesi bundle ID ile tutulur; uygulama öne geldiğinde 1 sn içinde normale döner, ayrıldığında
  geçişle geri gelir.
- **Tam ekran video** algısı: öndeki uygulamanın tam ekran penceresi var ve ekran uykusu engelleniyor (IOPM
  assertion `PreventUserIdleDisplaySleep`) ise.
- **"Bir saatliğine kapat"** Ekran Parlaklığı sayfasında ve menü çubuğu sağ tık menüsünde (son commit'teki hızlı menü)
  bulunur; yerine "Yeniden aç" yazar.
- **Elle parlaklık değişikliği** (tuşlar/kaydırıcı) bugünkü gibi bir sonraki geçişe kadar çizelgeyi bekletir.
- Renk ısıtması **her harici ekrana** uygulanır; "hangi ekran" seçimi parlaklık tuşlarına özeldir, gece moduna değil.
- Night Shift seçiliyken MacPocket parlaklığı yine kendisi düşürür; yalnız renk işini Night Shift'e bırakır.

## Okuyucu kontrolünden sonra verilen kararlar (benim kararım)

1. **Gece parlaklığı göreli.** Gündüz değeri her ekranın kullanıcının bıraktığı kendi seviyesidir (temel seviye);
   gece = temel × gece oranı (varsayılan 0.6). Gün doğumu temel seviyeye döner, %100'e zorlamaz. Temel seviye ekran
   başına saklanır; gündüz elle yapılan değişiklik temeli günceller.
2. **Renk ısıtma yalnız "Güneşe göre" modunda.** "Elle saatler" modu bugünkü gibi yalnız parlaklık. Ayrı ana anahtar
   yok: çizelge anahtarı + "Rengi ısıt" anahtarı yeterli.
3. **Elle değişiklik (gece/geçişte)** yalnız parlaklığı, içinde bulunulan ya da sıradaki geçiş bitene kadar bekletir;
   renk ısıtma sürer. Odak oturumu (`scheduleHeld`) da yalnız parlaklığı bekletir.
4. **Night Shift'i MacPocket sürer:** kendi güneş zaman çizelgesiyle açar/kapatır ve gücünü geçiş boyunca kademeli
   değiştirir. Etkinleştirmeden önceki Night Shift durumu diske yazılır; çıkış, yöntem değişikliği ve bir sonraki
   açılıştaki çökme kurtarma bu kayıttan geri yükler.
5. **İstisnalar ikisini de kaldırır** (parlaklık + renk). Renk ve yazılımsal parlaklık ~2 sn'de yumuşakça nötre döner;
   DDC parlaklığı tek yazımla temele döner. İstisna bitince yine ~2 sn'de gece değerine döner.
6. **Gamma tutmayan ekran** (ör. HDR açıkken): yazdıktan sonra tablo geri okunur; uyuşmuyorsa o ekranın kartında
   "Bu ekranda renk ısıtma uygulanamıyor (HDR açık olabilir)" notu gösterilir; Night Shift yöntemi önerilir. Otomatik
   yöntem değişimi yok.

## Builder'a bırakılanlar

- Dosya/tip yerleşimi (Core'da güneş hesabı ve renk sıcaklığı → RGB katsayısı; App'te servisler), arayüz yerleşimi
  ayrıntıları (mevcut sayfa dili korunarak), test kapsamı.
- Kelvin → RGB dönüşümünün formülü (ör. Tanner Helland yaklaşımı) ve geçiş eğrisi (doğrusal ya da yumuşatılmış).

## Kabul

- Birim testleri: güneş hesabı (bilinen şehir/tarih için ±2 dk), kutup durumları, Kelvin → katsayı, geçiş eğrisi,
  gamma birleştirme sırası.
- Canlı kontrol (bu Mac, iki harici ekran): saati değiştirmeden "şimdiyi" simüle eden bir hata ayıklama yolu ile
  gece/gündüz değerlerinin uygulanması, Night Shift aç/kapa ve önceki durumun geri gelmesi, çıkışta renklerin
  geri dönmesi, izin yokken şehir seçimiyle çalışma.
- `scripts/check-localizations.sh` 0 eksik.
