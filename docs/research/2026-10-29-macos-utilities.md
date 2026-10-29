# macOS Tools: sorgu kapsamı ve doğrulama

29 Ekim 2026. Bu iş, MacPocket'a yeni servis ekler; referans uygulama binary'sinden
bir algoritma çıkarıldığı iddia edilmez. Kaynaklar bu Mac'teki Apple man sayfaları
ve araçların salt okunur çıktılarıdır. Sürüm numarası değiştirilmedi.

MacUtilitiesView, MacUtilityService üzerinden 11 sabit sorgu sunar:

| Araç | Kaynak |
| --- | --- |
| Time Machine yerel görüntüleri | tmutil listlocalsnapshots / |
| Kullanıcı oturum işleri | launchctl list |
| Kullanıcı TCP dinleme soketleri | lsof -nP -a -u UID -iTCP -sTCP:LISTEN |
| Başlangıç birimi bilgisi | diskutil info / |
| Disk / bölüm haritası | diskutil list |
| Spotlight etkinlik durumu | mdutil -s / |
| DNS çözümleyicileri | scutil --dns |
| IPv4 / IPv6 yolları | netstat -rn |
| İşletim sistemi güncelleme geçmişi | softwareupdate --history |
| Sistem Bütünlüğü Koruması | csrutil status |
| Gatekeeper değerlendirmesi | spctl --status |

`man launchctl`, list komutunun PID / son çıkış kodu / görev kimliği verdiğini
belirtir. `man lsof`, -a seçeneğinin tüm filtreleri AND ile birleştirdiğini
belirtir; böylece kullanıcı kapsamı ve TCP LISTEN kapsamı birbirini genişletmez.
Kullanıcı metni komutlara verilmez, shell çalıştırılmaz. İşlemler 8 saniye ve
256 KiB ile sınırlıdır; kısmi sonuç ve alınamayan çıkış kodu açıkça korunur.
İptal yalnız MacPocket'ın başlattığı sorgu sürecini durdurur.

Native görünümde kategori/arama, ayrı Sorgula, iptal, çıktı araması, kopyalama ve
metin dışa aktarma vardır. Gizlilik ve Güvenlik ile Yazılım Güncelleme düğmeleri
macOS Ayarları'nı açar; izin veya sistem tercihi otomatik değiştirilmez.

Bu Mac Studio'da 11 sorgunun tamamı çıkış kodu 0 ile, her biri 0,15 saniyeden
kısa sürede tamamlandı. Yalnız komut, çıkış, süre ve byte sayısı içeren kanıt
`.build/mac-utilities-live-check.json` altında tutulur; ham ağ/oturum çıktıları
depoya eklenmez. Ayrıntılı gözlemler:

- tmutil sorgusu başarıyla döndü; yerel Time Machine görüntüsü listesi boştu.
- mdutil başlangıç biriminde indekslemenin etkin olduğunu bildirdi.
- spctl değerlendirmelerin etkin olduğunu bildirdi.
- csrutil Sistem Bütünlüğü Koruması'nın etkin olduğunu bildirdi.

Bunlar yalnız sorgu anının sonuçlarıdır. SMART desteği, her aygıtın veya her
MacBook modelinin sağlık durumunun okunduğu anlamına gelmez. Güvenlik sorguları
bir malware taraması değildir. Görüntü silme, indeks yenileme, güvenlik
ayarlarını değiştirme veya yazılım güncelleme kurulumu yapılmadı. Güncelleme
geçmişi, yeni güncelleme araması değildir; çevrimiçi kontrol macOS Ayarları'na
bırakılır. Diğer kullanıcıların soketleri ve tüm sistem launchd domain'leri bu
sorguların kapsamına dahil değildir.
