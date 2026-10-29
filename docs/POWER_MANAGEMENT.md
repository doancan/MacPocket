# MacBook güç yönetimi

Durum: ürün gereksinimi ve uygulama planı. 28 Ekim 2026'da kullanıcının
"özellikle MacBook'lar için çok gelişmiş izleme ve yönetim" isteğiyle genişletildi.
Bu belge tamamlanmış özellikleri değil, geliştirilecek kapsamı tanımlar.

Güç yönetimi MacPocket'ta ayrı ve öncelikli bir ana modüldür. MacBook Air ve
MacBook Pro için model/macOS bazında destek belirlenir. Masaüstü Mac'lerde
uygun enerji, termal durum ve uyku işlevleri sunulur; olmayan pil verisi sıfır
kapasiteli bir pil gibi gösterilmez.

## Ayrıntılı izleme

| Alan | Hedeflenen bilgi |
| --- | --- |
| Canlı pil | Yüzde, güç kaynağı, şarj oluyor/beklemede/deşarj oluyor durumu ve son okuma zamanı |
| Kapasite ve sağlık | Bildirilen sağlık durumu, döngü, tasarım ve tam dolum kapasitesi; kaynak ve birimler uygunsa sağlık/aşınma oranı |
| Elektriksel veriler | Kaynak sağlıyorsa akım, voltaj, sıcaklık ve pil şarj/deşarj gücü |
| Adaptör ve bağlantı | Bildirilen adaptör gücü ve mevcut bağlantı bilgisi; kapasite ile gerçek anlık tüketim ayrı gösterilir |
| Kalan süre | Yüke bağlı pil ömrü ve hedefe şarj süresi tahmini; yetersiz veri ve değişen yük belirtilir |
| Sistem enerjisi | Erişilebilen CPU/GPU/sistem enerji verileri ve termal baskı; ölçüm kapsamı açık gösterilir |
| Uygulama etkisi | Elde edilebilen süreç enerji/aktivite göstergeleriyle tüketim sıralaması ve kullanım bağlamı |
| Uyku analizi | Uyku/uyanma olaylarıyla eşlenen pil kaybı, süre ve tekrarlayan tüketim eğilimleri |
| Geçmiş | Saatlik/günlük grafikler, 24 saat/7 gün/30 gün görünümleri, şarj oturumları ve sağlık eğilimi |

Her değer ölçülen, sistem tarafından bildirilen veya hesaplanan/tahmini olarak
işaretlenir. Örneğin adaptörün bildirdiği watt değeri gerçek priz tüketimi olarak
sunulmaz; uygulama CPU yüzdesinden uygulamanın watt tüketimi türetilmez.
Okunamayan sensörler, birimi bilinmeyen alanlar ve artık güncel olmayan örnekler
açık durum taşır. Termal baskı seviyesi ile ölçülmüş sıcaklık farklı verilerdir.

Uyku kaybı raporu için uyku öncesi ve sonrası geçerli örnekler ve sistem olayları
eşlenir. Yeniden başlatma veya eksik kayıt, kesintisiz uyku olarak varsayılmaz.
Geçmiş yerelde tutulur; saklama süresi, silme ve dışa aktarma kullanıcıya sunulur.
Adaptör seri numarası gibi tanımlayıcılar kullanıcı raporuna varsayılan olarak eklenmez.

## Aktif yönetim

| Kontrol | Hedef davranış |
| --- | --- |
| Şarj limiti | Doğrulanmış backend'in desteklediği aralıkta kullanıcı hedefi; istenen ve gözlenen durum ayrı |
| Şarj durdur/başlat | Desteklenen cihazda adaptörle çalışmayı koruyarak şarjı durdurma ve yeniden başlatma |
| Tek seferlik tam şarj | Seyahat öncesi tam şarj isteği ve ardından önceki politikaya dönüş; bitiş zamanı garanti edilmez |
| Güç modu | Pil ve adaptör için ayrı düşük/otomatik/yüksek güç seçimi; modelin desteklediği seçenekler |
| Profiller | Masa Başı, Mobil, Performans ve Seyahat; kullanıcı tarafından düzenlenebilir ayarlar |
| Uyku yönetimi | Süreli veya manuel durdurulana kadar uyanık tutma; ekranı açık tutma ayrı seçenek |
| Bildirimler | Düşük pil, hedefe ulaşma, beklenmeyen deşarj ve doğrulanmış termal olay bildirimleri |

Şarjı durdurma, adaptörü devre dışı bırakarak pili zorla boşaltmaktan ayrı tutulur.
Kontrolün başarısı geri okunan durumla doğrulanır. İşletim sistemi isteği kabul
etse bile uygulanma henüz doğrulanmadıysa sonuç "istek gönderildi" olarak kalır.

Apple'ın kendi Charge Limit özelliği Apple Silicon ve macOS 26.4+ üzerinde
80–100 aralığı sunar; bu, uygulamamızın aynı ayarı doğrudan değiştirebileceğini
kanıtlamaz. Uygulama içi backend'in desteklediği aralık ayrıca keşfedilir ve test
edilir. Sistemin zaman zaman tam şarj yapması da hesaba katılır.
[Apple Charge Limit](https://support.apple.com/en-us/102338)

Güç modlarının model desteği değişir ve pil/adaptör için ayrı ayarlanabilir.
MacPocket kullanılabilir seçenekleri cihazdan doğrular.
[Apple Power Modes](https://support.apple.com/en-us/101613)

## Profiller ve otomasyon

Hazır profiller düzenlenebilir; kullanıcı kendi profillerini oluşturabilir,
çoğaltabilir, adlandırabilir ve dışa aktarabilir. Pil ve adaptör için ayrı
tercihler, desteklenen şarj hedefleri, eşikler, zaman pencereleri, kural
öncelikleri, manuel geçersiz kılma süreleri ve bildirimler özelleştirilebilir.

Güç ekranındaki kartlar, menü çubuğundaki göstergeler, grafik aralığı, gösterilen
birimler ve geçmiş saklama süresi seçilebilir. Örnekleme sıklığı ayarı uygulamanın
enerji tüketimiyle birlikte değerlendirilir; düşük güçte arka plan örneklemesi
ayrı tercih taşır. Tüm görünüm ve veri ayarları aynı veri kaynağına bağlanır.

Bir profili içe aktarmak onu çalıştırmaz. Farklı MacBook'tan gelen bir profilin
uygulanabilen, desteklenmeyen ve yetki gerektiren alanları önizlemede ayrılır.
Profil düzenlemesi ile etkinleştirme farklı işlemlerdir. Ortak davranışlar
[özelleştirme belgesinde](CUSTOMIZATION.md) tanımlanır.

Kullanıcı bir kuralı etkinleştirirken tetikleyiciyi, koşulları ve uygulanacak
işlemi birlikte görür. Hedef örnekler:

- Adaptör takıldığında Masa Başı profilini ve desteklenen şarj hedefini kullan.
- Pilde çalışırken belirlenen eşikte düşük güç profiline geç.
- Kullanıcının seçtiği zaman penceresinde Seyahat tam şarj isteğini etkinleştir.
- Uyanık tutma oturumu için süre sonunda veya seçilen pil eşiğinde oturumu bitir.
- Desteklenen, güncel termal durum verisinde kullanıcı tarafından seçilmiş
  tasarruf profilini öner veya kural etkinse uygula.

Kuralların önceliği ve çakışmaları tek yerde çözülür. Manuel seçim, belirlenmiş
geçersiz kılma süresi boyunca otomasyonu bastırır. Şarj/yüzde ve sıcaklık
eşiklerinde histerezis ve bekleme süreleri kullanılır; sürekli aç/kapa döngüsü
oluşturulmaz. Apple'ın pil yönetimiyle çakışan talepler ayrıca değerlendirilir.

İşlem günlüğü tetikleyici, seçilen kural, önceki/istenen/gözlenen durum ve sonucu
saklar. Destek veya gerekli yetki kaybolduğunda ilgili kural işlem yapamaz ve
sebebi gösterilir. Kullanıcı otomasyonu durdurabilir ve MacPocket'ın değiştirdiği
doğrulanmış ayarları önceki durumuna döndürebilir; sistemin sonradan yaptığı
başka değişiklikler körlemesine üzerine yazılmaz.

Tools → Mac'i Uyanık Tut ve güç merkezi ortak `SleepController` oturumunu
gösterir. Süre, manuel durdurma ve uygulama kapanışı aynı yaşam döngüsünden
yönetilir. Uygulamanın oluşturduğu assertion'lar sonlandırıldığında bırakılır.

## Destek ve teknik sınırlar

| Durum | Uygulama davranışı |
| --- | --- |
| Public okuma API'si mevcut | İzleme ve değişiklik bildirimleri kullanılır |
| Sistem ayarı mevcut, uygulama içi yazma doğrulanmamış | Mevcut durum ve sistem ayarına erişim sunulur; doğrudan kontrol tamamlandı sayılmaz |
| Model/sürüm bazında test edilmiş kontrol backend'i | Sadece doğrulanmış işlemler ve değer aralığı etkinleştirilir |
| Yetki/helper gerekiyor | İlgili işlem için dar kapsamlı kontrol servisi ve açık yetki durumu kullanılır |
| Pil yok veya özellik desteklenmiyor | Gerekçeli desteklenmiyor durumu gösterilir |

Pil/adaptör okuması için IOPowerSources, termal ve düşük güç durumları için
ProcessInfo bildirimleri temel alınır. Geçmiş kaydı ve arayüz güncellemesi arka
planda seyreltilir; izleyicinin kendi enerji maliyeti gerçek donanımda ölçülür.
[IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h),
[Power notifications](https://developer.apple.com/documentation/xcode/responding-to-power-notifications)

Public SDK incelemesinde doğrudan şarj limiti/durdurma setter'ı doğrulanmadı.
Özel API veya SMC yolu, root erişimi var diye otomatik desteklenmiş sayılmaz.
Önceki [teknik inceleme](research/2026-10-28-initial.md) bu sınırları kaydeder.
MacBook için şarj yönetimi ürün kapsamındadır; backend araştırması ve donanım
testi tamamlanmadan çalışıyor olarak işaretlenmez.

## Kabul ölçütleri ve geliştirme önceliği

1. Gerçek MacBook'ta pil/adaptör okuması; olmayan, izin gerektiren ve eski
   veriler için doğru durumlar; CPU/RAM/disk izleme ile düşük maliyetli örnekleme.
2. Sağlık ve geçmiş, şarj/uyku oturumu raporları, menü çubuğunda hızlı durum.
3. Şarj backend'inin erken doğrulanması; test edilen model/macOS ve desteklenen
   işlemlerin matrisi. Bu araştırma sonraki aşamalara bırakılmaz.
4. Desteklenen aktif kontroller, profiller ve çakışma çözümü; her işlemde geri okuma.
5. Otomasyon, bildirim ve geri dönüş testleri; uyku/uyanma, yeniden başlatma,
   adaptör değişimi, pil eşiği, helper bağlantı kaybı ve uygulama kapanışı.

Mevcut geliştirme Mac'inde pil bulunmuyor. Saf hesaplamalar, politika motoru ve
masaüstünde geçerli uyku/enerji işlevleri burada test edilebilir. Şarj kontrolü
ve pil sağlığı davranışlarının gerçek donanım kabulü MacBook üzerinde yapılır.
