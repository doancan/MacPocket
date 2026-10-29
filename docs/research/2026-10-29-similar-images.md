# Benzer Görseller — yerel Vision servisi

29 Ekim 2026. Bu iş Apple'ın public Vision / ImageIO API'larıyla yeni bir
MacPocket servisi geliştirir; CleanMyMac algoritmasının kopyalandığı iddia edilmez.
Sürüm numarası değiştirilmedi.

Kaynaklar:

- [VNGenerateImageFeaturePrintRequest](https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest)
- [VNFeaturePrintObservation.computeDistance](https://developer.apple.com/documentation/vision/vnfeatureprintobservation/computedistance(_:to:))
- [Apple'ın görsel benzerlik örneği](https://developer.apple.com/documentation/vision/analyzing-image-similarity-with-feature-print)

İstek revision 2 ve scaleFit ile üretilir; tüm adaylar aynı revision kullanır.
Apple daha küçük feature-print mesafesinin daha fazla benzerlik belirttiğini
söyler. 0,3 / 0,6 / 0,9 uygulamanın deneysel inceleme eşikleridir; evrensel
kalite sınırı, eşit içerik kanıtı veya benzerlik yüzdesi olarak sunulmaz.

Kullanıcı klasör seçer; tarama başlamadan görseller okunmaz. FileScanner'a
opsiyonel allowedExtensions filtresi eklendi. Varsayılan nil eski taramaların
kapsamını korur; görsel filtresi retention ve byte toplamından önce uygulanır.
Böylece büyük video/arşiv dosyaları görselleri sonuç listesinden çıkaramaz.
Symlink izlenmez, hard link tek sayılır; gizli içerikler atlanır.

JPEG/PNG/HEIC/HEIF/TIFF/WebP/BMP/GIF desteklenir; çok kareli dosyada yalnız ilk
kare incelenir. Özgün dosya değişiklik kimliği önce/sonra doğrulanır. ImageIO
önce boyut metadata'sını okur, dosya 64 MiB veya 100 MP üzerindeyse atlar.
Analiz için EXIF yönü uygulanmış en çok 1.536 piksel küçük resim üretilir.
Galeri küçük resimleri en çok 310 piksel, sırayla çözümlenir; yüzlerce decoder
aynı anda başlatılmaz. Dosya yüklenmez, yerel Vision dışında servis çağrılmaz.

Tarama en çok 100 bin klasör girdisi, metadata için 20 saniye, tüm iş için
varsayılan 60 saniye ve kullanıcı seçimine göre en büyük 100/250/500 desteklenen
resimle sınırlıdır. En çok 1.000 çift eşleşmesi tutulur. Vision iptal isteği alır;
süre ve Task iptali işlem adımları arasında denetlenir. Bu bir dış süreç hard
kill zaman garantisi değildir. Desteklenmeyen/bozuk/okunamayan dosya ve sınıra
ulaşılması kısmi kapsam olarak gösterilir.

Her grup bir referans resim ve o referansla doğrudan eşik altında kalan resimleri
sunar. A≈B, B≈C ilişkisinden A≈C sonucu çıkarılmaz. Bir resim birden çok grupta
bulunabilir; farklı adayların birbirlerine benzemesi garanti edilmez. Galeride
ham mesafe, küçük resim ve Finder'da gösterme vardır. Benzer fotoğraf silme veya
otomatik fazla-kopya seçme eylemi yoktur; eşit içerik için ayrı Yinelenenler
aracının SHA-256 servisi kullanılır.

Doğrulama: sahip olunan 256×192 piksel PNG test resmi CoreGraphics ile üretildi;
aynı içerikli ayrı dosyaların Vision mesafesi 0 çıktı. 5 test geçti: görüntüye
özel retention, sınırlı thumbnail / değişen dosya reddi, gerçek Vision eşleşmesi
ve görüntü sayısı sınırı, bozuk resmin açık atlanması, önceden iptal edilmiş iş.
Kullanıcının resimleri okunmadı, hiçbir görsel silinmedi. Native UI kabulü ana
agent tarafından ayrıca yapılacaktır.
