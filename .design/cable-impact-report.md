# Kablo Etki Haritası — 7 Kasım 2026

SwiftUI/AppKit, mevcut Pocket başlık/kart/mesaj/boşluk bileşenleri. Asıl iş kabloyu çıkarmadan önce olası etkileri değerlendirmek.

- Üstte aygıt seçimi, okuma zamanı ve kaynak türlerinin kısa özeti; altta kaynak, ilişki kanıtı, sonuç ve okunabilen açık işler sıralanır.
- Donanım ağacı bağlantısı ile kullanıcının eklediği ilişki metin ve simgeyle ayrılır. Belirsiz bağlantılar ayrı, açılır bir eşleştirme alanındadır.
- Yenile, iptal, yüklenme, boş envanter, eşleşmeyen kaynak, kısmi hata ve donanım değişmesi durumları vardır. Kaldırma/disk ayırma eylemi eklenmedi; mevcut USB Çıkarma ekranına geçilir.
- Dar içerikte başlık eylemi alt satıra geçer. Uzun metinler sarılır; içerik kaydırılabilir. Native Picker, Toggle, Button ve DisclosureGroup kontrolleri kullanıldı.
- Teknik PID değerleri yerel binlik ayıracı eklenmeden gösterilir. Kaynak ve kullanım zamanları ayrıdır; sayfa sürekli ölçüm yapıyormuş gibi sunulmaz.

Doğrulama: iki dil/iki görünümde 700 ve 1060 pt içerik, native erişilebilirlik ağaçları ve yalnız sahip olunan test penceresinin görüntüleri. İşlevsel model kontrolleri ile gerçek loopback oturumu ayrı kaydedildi. Görsel incelemede yatay kırpılma görülmedi. Tam VoiceOver, fiziksel klavye ve fiziksel dock kabulü yapılmadı.

İşlev kapsamı ve kanıtlar: [Kablo Etki Haritası](../docs/CABLE_IMPACT.md).
