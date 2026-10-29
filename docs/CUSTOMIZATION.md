# Özelleştirme ve seçenekler

Durum: ürün gereksinimi. Kullanıcı, MacPocket genelinde bol seçenek ve kapsamlı
özelleştirme istedi. Aşağıdaki ayarlar tüm modüller geliştirilirken dikkate alınır.

## Özelleştirilebilir alanlar

| Alan | Seçenekler |
| --- | --- |
| Genel görünüm | Sistem/açık/koyu tema, vurgu ve grafik renkleri, kompakt/rahat yoğunluk, okunabilir metin boyutu ve hareket tercihi |
| Ana ekran | Kart seçimi ve sırası, favori modüller, başlangıç sayfası, sabitlenmiş hızlı işlemler |
| Menü çubuğu | Birleşik/ayrı göstergeler, sıra, ikon/değer/grafik sunumu, birimler, ondalık hassasiyet ve gösterilecek ölçümler |
| CPU/RAM/disk | Gösterilecek çekirdek/volume/ölçümler, grafik türü ve aralığı, ölçek, renkler, yenileme sıklığı ve geçmiş saklama süresi |
| Sistem İzleme | Memory pressure/swap/termal/güç/ağ göstergeleri, tanı kartları, sıralama, yenileme ve rapor saklama tercihleri |
| Görev Yöneticisi | Süreç sütunları, arama/filtreleme, CPU/RAM sıralaması, uygulama/süreç kapsamı ve sonlandırma eylemine hızlı erişim |
| Tools / CleanMyMac referansı | Araç favorileri, kategori filtreleri, kart sırası, doğrudan erişim ve araç bazında sonuç geçmişi |
| Güç yönetimi | Kullanıcı profilleri, pil/adaptör tercihleri, desteklenen şarj hedefleri, eşikler, otomasyon kuralları ve öncelikleri |
| Window Switcher | Global kısayollar, ileri/geri gezinme, kapsam/sıralama filtreleri, gizli/küçültülmüş pencere tercihleri, thumbnail boyutu ve sunumu |
| Uyanık tutma | Hazır ve özel süreler, varsayılan oturum türü, ekranı açık tutma, pil/adaptör koşulları, bitiş bildirimi ve hızlı erişim |
| Temizlik | Tarama kategorileri, dahil/hariç dizinler, korunacak uygulama ve öğeler, sonuç filtreleri, yaş/boyut eşikleri |
| Disk analizi | Volume ve klasör kapsamı, dosya türü/boyut filtreleri, sıralama, gösterim birimleri ve eşik bildirimleri |
| Uygulama kaldırma | İlişkili dosya kategorileri, korunacak veri tercihleri, uygulama istisnaları ve kaldırma planı görünümü |
| Güncellemeler | Kontrol sıklığı, uygulama/kanal tercihleri, sürüm atlama, bildirim veya desteklenen güncelleme davranışı |
| Bildirimler | Modül bazında aç/kapat, eşik, tekrar aralığı, sessiz saatler ve bildirim türleri |
| Kısayollar | Uygulama içi/global atamalar, çakışma bildirimi, favori işlemlere hızlı erişim ve modül bazında sıfırlama |

Donanım veya macOS desteği gerektiren tercihler kullanılabilirlik durumuyla
birlikte sunulur. Bir ayarın kullanıcı tarafından seçilebilir olması, cihazın
desteklemediği bir işlemi mümkün kılmaz.

## Ayarların düzenlenmesi

- Ayar adı, açıklaması ve ilgili modül üzerinden arama.
- Sık kullanılan tercihler için hızlı ayarlar; modül içinde gelişmiş seçenekler.
- Açıklayıcı varsayılanlar, hazır profiller ve değişikliklerin anlaşılır önizlemesi.
- Kullanıcının varsayılandan değiştirdiği alanları görebilmesi.
- Tek ayar, modül, profil veya tüm uygulama düzeyinde varsayılanlara dönüş.
- Aynı tercihin ana ekran, Tools ve menü çubuğunda tutarlı davranması.
- Görünüm ve gösterim değişikliklerinin mümkün olduğunda anında önizlenmesi.

Görünüm ayarı değiştirmek sistem güç ayarı uygulamaz. Profili düzenlemek,
etkinleştirmek ve bir otomasyonu çalıştırmak ayrı eylemlerdir. Kaldırma/temizlik
tercihleri değiştiğinde dosya planı yeniden üretilir; eski seçime göre işlem
yapılmaz. Paylaşılan dosya sahipliği ve izin denetimleri tüm tercihlerde korunur.
Görev Yöneticisi tercihleri, süreç kimliği ve sonlandırma yetkisi denetimlerini
kaldırmaz. Salt okunur tanı aracı ile sistemi değiştiren bakım işlemi araç
kartında farklı eylem olarak gösterilir.

Tools kapsamı [CleanMyMac Tools](CLEANMYMAC_TOOLS.md) ve
[Sistem Merkezi](SYSTEM_CENTER.md) belgelerindeki işlevlerle eşleşir.

## Profiller ve taşınabilirlik

Hazır profillerden türetme, yeni profil oluşturma, kopyalama, adlandırma ve silme
desteklenir. Uygulama görünüm profili, güç profili ve modüle özgü tercihler
amaçlarına göre gruplanır; aynı güç denetimi farklı profillerden çakışırsa ortak
politika motoru önceliği çözer.

Ayarlar sürümlü bir formatta yerelde saklanır. Kullanıcı ayarlarını dışa
aktarabilir, seçtiği bölümleri içe aktarabilir ve öncesinde mevcut ayarların
yedeğini alabilir. İçe aktarma önizlemesinde değişecek, desteklenmeyen ve bu
cihazda yeniden seçilmesi gereken alanlar gösterilir.

Global tercihler ve cihaza özgü alanlar ayrılır. Örneğin farklı bir MacBook'ın
pil kontrol desteği, volume kimliği veya klasör yolu bu Mac'te varsayılmaz.
Sistem izinleri ve kimlik bilgileri ayar dosyasıyla taşınmaz. İçe aktarılan
otomasyonlar kullanıcı etkinleştirene kadar çalışmaz.

Uygulama ayarlarını sıfırlama, sistemde önceden değiştirilmiş güç ayarlarını
körlemesine geri yazmaz. Güç ayarlarının geri alınması kendi doğrulanmış durum
ve işlem geçmişi üzerinden ayrıca yönetilir.

## Uygulama temeli ve kabul ölçütleri

Ortak `SettingsStore` ve `ProfileStore`, modüllerin ayarlarını tek kaynaktan
sağlar. Ayar şeması sürümlenir; modüller kendi seçeneklerini ve destek
koşullarını tanımlar. Cihaz durumu, arayüz önizlemesi ve etkin kontrol durumu
birbirinden ayrılır.

Geliştirmede doğrulanacak davranışlar:

1. Yeniden açılışta tercihlerin korunması ve eski sürümden ayar geçişi.
2. Geçersiz veya kısmen desteklenen içe aktarmada anlaşılır sonuç ve mevcut
   ayarların tutarlı kalması.
3. Birim, tema, kart sırası ve profil değişikliklerinin ilgili yüzeylere yansıması.
4. Kısayol/otomasyon çakışmalarının belirlenmesi ve elle verilen kararın önceliği.
5. Ayar sıfırlama/yedekten geri dönme; bu işlemlerin aktif güç veya dosya
   işlemlerini beklenmedik biçimde tetiklememesi.
6. Özelleştirilmiş yenileme, geçmiş ve bildirim tercihlerinin MacPocket'ın kendi
   enerji tüketimi üzerindeki etkisinin ölçülmesi.
