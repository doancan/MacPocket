# Uygulama kaldırma — kapsam ve doğrulama

## Tamamen Kaldır

Uygulamalar'daki **Tamamen Kaldır…** düğmesi hiçbir şey seçtirmeden uygulamayı ve bulunan her ilişkili öğeyi (kullanıcı verileri dahil) kalıcı siler. Tek onay istenir; onaydan sonra uygulama normal çıkış isteğiyle kapatılır, plan yeniden taranır (kapanırken yazılan dosyalar kaçmaz) ve sırayla kullanıcı öğeleri, /Library öğeleri ve en son uygulama paketi silinir. İlk hatada kalan öğelere dokunulmaz. /Library öğeleri ve root sahipli dosyalar için tek bir sistem parolası istenir; launchd işleri silinmeden önce durdurulur. Plan penceresinde ayrıca ayrıntılı seçim ve "Silme biçimi" (kalıcı / Çöp) kalır.

Eşleşme kuralları: tam bundle kimliği ve `kimlik.` ile başlayan aileler (Caches, Logs, Preferences, ByHost, Containers, Group Containers, Application Scripts, Cookies, HTTPStorages, WebKit, LaunchAgents; /Library altında LaunchDaemons, PrivilegedHelperTools, Application Support, Preferences, Caches) ve uygulama adıyla birebir aynı adlı Application Support/Caches/Logs klasörleri (en az 4 karakter). Yalnız üretici öneki (`com.vendor`) paylaşan klasörler çıkarılmaz.

## Plan

Kaldırma planı uygulama paketini, önbellek/günlükleri ve kullanıcı verilerini ayrı gösterir. Başlangıçta yalnız uygulama paketi seçilir. Tercihler, uygulama verileri ve kapsayıcılar açıkça seçilmelidir. Grup seçimi yalnız kendi grubunu etkiler; Finder düğmesi dosyayı açığa çıkarır.

## Kapatma ve kaldırma

Onaydan sonra ana uygulamaya AppKit üzerinden normal çıkış isteği gönderilir. Kaydetme/iptal penceresine uygulamanın kendisi karar verir. Ana uygulama çıkmadan yardımcı süreçlere sinyal gönderilmez. Paket içinde yürütülebilir dosyası doğrulanan yardımcılar daha sonra normal kapatma sinyali alır. Kapanmayı reddetme veya süre aşımı dosya taşımayı başlatmaz; plan hata ve kalan süreçlerle açık kalır.

Zorla kapatma yalnız normal denemeden sonra ayrı onayla sunulur. Onay, görünen süreçlerin PID ve başlangıç kimliklerine bağlanır; liste değişirse yeniden inceleme gerekir. Beklemeyi durdurma sonraki adımları iptal eder, daha önce gönderilen çıkış isteğini geri alamaz.

Kaldırma servisi arayüzden bağımsız olarak da çalışan süreçleri kontrol eder. Çıkış sırasında kaydedilmiş tercih dosyalarının kimlikleri yeniden okunur; yalnız eski planda açıkça seçilen yollar taşınır. Sonradan bulunan veri otomatik seçilmez. Her taşıma öncesinde tekrar süreç kontrolü yapılır; uygulama paketi en son taşınır. Hata kısmi sonuçları saklar ve kalan işlemleri durdurur.

## Sınırlar

- Süreç sahipliği seçilen uygulama paketinin gerçek dosya yolu ile doğrulanır. Benzer ad, bundle-ID öneki veya üst süreç ilişkisi tek başına yeterli değildir. Aynı bundle-ID ile başka konumda çalışan kopya kapatılmaz.
- Uygulamanın bundle kimliğiyle adlandırılmış LaunchAgent/Daemon, ayrıcalıklı yardımcı ve App Group klasörleri plana girer; başka kimlikli paylaşılan servisler ve üretici ortak klasörleri girmez. Homebrew seçiliyse paketin kendi kaldırma yönergelerini çalıştırır; bu yönergeler ayrıca servis durdurabilir ve uygulamayı Çöp’e taşımayabilir.
- Süreç/PID ve dosya kimliği kontrolleri aradaki yarış penceresini daraltır; macOS süreç başlatma ve dosya taşıma işlemlerini tek atomik işlem olarak sunmaz. Tam kapsamlı yardımcı temizliği iddia edilmez.
- Kaldırma sonrası yeniden denemede uygulama paketi değişmiş veya kaybolmuşsa güncel envanterden yeni plan açılmalıdır. Kısmi dosya taşımaları otomatik geri alınmaz.

## Doğrulama — 9 Kasım 2026

- **Kod ve birim testleri:** paket sınırı/simgesel bağlantı, değişmiş kimlik, normal çıkış sırası, reddedilen çıkış, ayrı zorla kapatma onayı, yeni süreç kimliği, iptal, arka uç koruması, kaydedilmiş tercih dosyası ve taşıma arasında yeniden başlama için 12 yeni test. Tam kök test çalışması: 1.479 test, 0 hata, 5 donanım/sistem koşullu atlama.
- **Canlı test:** Türkçe ve İngilizce çalıştırmalarda 23’er kontrol geçti (toplam 46). Denetimin oluşturduğu AppKit uygulaması ve paket içindeki C yardımcı süreci kullanılır. Normal çıkış, çıkışı reddetme ve SIGTERM’i reddeden yardımcı senaryoları gerçek süreçlerle çalıştırılır. Aynı kimlikli diğer kopyanın çalışmaya devam etmesi ve çıkışta yazılan tercihin güncel içeriğiyle taşınması doğrulanır. Dosyalar yalnız denetime ait geçici alandan yine denetime ait hedefe taşınır; kullanıcının uygulamaları kapatılmaz, gerçek Çöp kullanılmaz.
- **Arayüz:** Türkçe/açık ve İngilizce/koyu görünümde normal plan ve kapanmama durumunun yerel pencere görüntüleri alınır. Gerçek bir kullanıcı belgesinin kaydetme penceresi, yönetici yetkili kullanıcı uygulaması ve her Homebrew paketinin kaldırma yönergesi kabul edilmiş sayılmaz.

Tekrarlama: `scripts/audit-uninstall.sh` (Debug paket ve ekran kaydı izni gerekir). Raporlar ve görüntüler `.build/uninstall-improvements/ui-{tr,en}/` altında tutulur. İngilizce çeviri kapısı: `scripts/check-localizations.sh`.
