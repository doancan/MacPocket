# Ekran görüntüsü aracı — 1. aşama tasarımı

Tarih: 3 Kasım 2026 · Durum: onaylandı (sohbette, 3 Kasım 2026)

## Amaç

Kullanıcı CleanShot X'i (Setapp, 5.0.2) ⇧⌘3/⇧⌘4/⇧⌘5 ile kullanıyor ve aşağı yukarı aynı özelliklerin MacPocket'te
olmasını istiyor. Özellik listesi CleanShot'ın resmî sayfalarından ve uygulamanın kullanıcı gözüyle davranışından
çıkarıldı; CleanShot'ın kodu incelenmedi (lisansı tersine mühendisliği yasaklıyor), uygulama tamamen bizim kodumuz.
Tam eşdeğerlik iddiası yok (AGENTS.md).

## Aşamalar (kullanıcı onaylı sıra)

1. **Bu belge:** çekim + çekim sonrası önizleme + ayarlar + geçmiş + dört düzenleme aracı.
2. Tam düzenleyici (şekiller, numaralı adım, spot ışığı, kırpma, arka plan aracı).
3. Sabitleme, kayan sayfa çekimi, zamanlayıcı, masaüstü simgelerini gizleme.
4. Ekran kaydı geliştirmeleri (alan/pencere, GIF, tıklama/tuş gösterimi, kamera).

Bulut ve video stüdyosu kapsam dışı.

## 1. aşama hedefleri

- **Çekim modları:** alan, pencere, tam ekran (imlecin ekranı), önceki alan. "Hepsi bir arada" (⇧⌘5) alan seçimini
  açar ve altta mod çubuğu gösterir (Alan / Pencere / Tam ekran / Önceki alan).
- **Alan seçimi:** çekim anında ekranlar dondurulur (önce tüm ekranların görüntüsü alınır, seçim bu görüntü üstünde
  yapılır). Artı imleç, imleç yanında büyüteç (piksel ızgarası) ve piksel cinsinden boyut etiketi. Esc iptal.
  Boşluk tuşu pencere moduna geçer: imlecin altındaki pencere vurgulanır, tıklayınca o pencere çekilir.
- **Pencere çekimi:** pencerenin kendisi, gölgesiyle ve saydam arka planla (PNG/HEIC'te saydam; JPG'de beyaz).
- **Çekim sonrası:** ekranın sol altında küçük önizleme kartı. Üzerine gelince Kopyala, Kaydet, Düzenle, Kapat.
  Sürükle-bırak ile başka uygulamaya dosya olarak verilir; sürükleyince kart kapanır (ayar). Birden çok çekim üst
  üste dizilir. İsteğe bağlı otomatik kapanma (kapalı / 5 / 10 / 30 sn).
- **Otomatik işlemler (ayar):** panoya kopyala (varsayılan açık), klasöre kaydet (varsayılan açık), önizleme göster
  (varsayılan açık).
- **Kayıt:** klasör (varsayılan Masaüstü), biçim JPG / PNG / HEIC (varsayılan PNG; kullanıcı CleanShot'ta JPG
  kullanıyor, ayardan seçer), JPG kalitesi, dosya adı "Ekran Resmi 2026-11-03 08.43.12" (dil tablosundan),
  aynı ad varsa sona sayı.
- **Kısayollar:** ⇧⌘3 tam ekran, ⇧⌘4 alan, ⇧⌘5 hepsi bir arada; pencere ve önceki alan için boş (kullanıcı atar).
  macOS'un kendi kısayolları açıksa ya da başka uygulama (CleanShot) tuttuysa kayıt başarısız olur; sayfada uyarı ve
  Sistem Ayarları → Klavye Kısayolları düğmesi.
- **Geçmiş:** son 200 çekim / 30 gün; dosyası silinenler düşer. Araçlar → Ekran Görüntüsü sayfasında küçük
  resimlerle: aç, düzenle, kopyala, Finder'da göster, listeden kaldır.
- **Düzenleyici (ilk dört araç):** ok, vurgulayıcı (yarı saydam dikdörtgen), pikselleştirme (alan), metin. Renk ve
  kalınlık seçimi, geri al/yinele, Kopyala, Kaydet (üzerine), Farklı Kaydet. Çizimler katman olarak tutulur, dışa
  aktarırken görüntüye işlenir.
- Arayüz Türkçe + İngilizce; Ekran Kaydı izni yoksa nedeni ve izin düğmesi gösterilir.

## Anti-hedefler

- Çekimde MacPocket'in kendi seçim katmanının ya da önizleme kartının görüntüye girmesi.
- Retina ekranda bulanık/yarı çözünürlüklü çıktı (çıktı her zaman ekranın yerel piksel çözünürlüğünde).
- Kısayol çakışmasında sessizce çalışmamak.

## Builder kararları (benim)

- Çekim ScreenCaptureKit (`SCScreenshotManager`) ile; alan çekimi dondurulmuş tam ekran görüntüsünden kırpılır.
- Koordinat, dosya adı, biçim kodlama, geçmiş ve düzenleme katmanlarının işlenmesi Core'da, birim testli.
- Yeni araç sayfası "Ekran Görüntüsü" (Araçlar, Üretkenlik).
