# Kaldırma planı — 9 Kasım 2026

SwiftUI/AppKit ve mevcut Pocket boşluk, kart, simge ve mesaj bileşenleri kullanıldı. Başlıkta uygulama kimliği, gövdede süreç durumu ve seçim grupları, sabit alt bölümde seçim sonucu ve kaldırma eylemi yer alır.

- Uygulama, önbellek/günlükler ve kullanıcı verileri ayrı gruplardır. Kullanıcı verileri varsayılan olarak seçilmez. Grup başlığı yalnız o grubun seçimini değiştirir.
- Uzun dosya yolları orta noktadan kısaltılır; tam yol ipucunda, ilgili konum ayrı Finder düğmesindedir.
- Süreç listesi açılabilir ayrıntıdır. Kapatma hatasında ayrıntı açılır ve görünüm hataya kayar. Zorla kapatma, ayrı onay gerektiren ikinci bir eylemdir.
- İçerik tek alanda kayar; başlık ve seçili öğe özeti/eylemler sabit kalır. Boş seçim, süreç denetimi ve işlem sırasında eylem durumları ayrıdır. Hata planı kapatmaz.
- Yerel onay kutuları, açıklamalı simge düğmeleri, metinli durumlar, iptal klavye kısayolu ve Türkçe/İngilizce çeviriler kullanılır.

Canlı görüntüler: `.build/uninstall-improvements/ui-tr/{plan,review}.png` ve `ui-en/{plan,review}.png`. Bunlar yalnız denetimin oluşturduğu uygulamaya aittir. Süreç/dosya kabul sınırları: [APPLICATION_UNINSTALL.md](../docs/APPLICATION_UNINSTALL.md).

Doğrulama: Türkçe/açık ve İngilizce/koyu görünümde 23’er canlı kontrol geçti; 4.418 yerelleştirme anahtarında eksik İngilizce karşılık ve biçim uyuşmazlığı yok. Ekran görüntüleri denetim penceresinin etkin olmayan sistem renklerini de içerir.
