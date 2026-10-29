# iStat görünüm seçenekleri — 29 Ekim 2026

Referans: yerel `/Applications/Setapp/iStat Menus.app`, sürüm 7.50 / 2394.
Bu çalışma mevcut REA CPU/RAM statik kanıtlarını yeniden kullanır:
`ev_d3f6ae9978c45c47b84758fe6a510b63ec21d30ff9109ca5e888eb2ef819154f`.
Yeni örnekleme algoritması veya tam özellik eşitliği iddiası yoktur.

## Kaynak gözlemi

`Contents/Resources/en.lproj/Localizable.strings`, `plutil -convert json -o -`
ile salt okunur çözümlendi. Şu anahtarlar bulundu:

- `Combined.Combined`
- `Disks.Combined`, `Disks.Separate`, `Disks.Show Labels`
- `Memory.Show Labels`, `Memory.Size`, `Memory.Percentage`, `Memory.Size & Percentage`
- `Memory.Free`, `Memory.Wired`, `Memory.Compressed`, `Memory.Memory Pressure`
- `Setup.Select Menu Bar Style`

Bunlar paketlenmiş seçenek adlarıdır; çalışma zamanı düzeni veya formülleri
kanıtlamaz. Ham boş RAM, kullanılabilir bellek yerine geçirilmedi.

## Bağımsız MacPocket uygulaması

Menü çubuğu ayarları gerçek sistem örneklerini kullanır. Birleşik grup/ayrı
NSStatusItem, CPU/RAM/disk/pil/güç seçimi ve sırası, metin/mini gösterge,
etiket/simge, aralık, yazı boyutu, ondalık, birim, RAM alanı ve yüzdesi,
disk seçimi ve boş alan/doluluk yüzdesi eklendi. Bunlar MacPocket tasarım
kararlarıdır; iStat kaynak kodu veya birebir algoritma kopyası değildir.

Pilsiz cihazda pil göstergesi oluşturulmaz. RAM seçenekleri fiziksel toplam,
ham boş sayfa, wired ve sıkıştırıcının fiziksel alanıdır. Bellek baskısı veya
uygulama belleği taklidi üretilmez. Bağlı olmayan seçili disk — gösterir.

Tam iStat kapsamı (sensörler/fanlar, ağ grafikleri, GPU, tüm CPU çekirdekleri,
uyarılar ve ayrıntılı pil telemetrisi) bu değişiklikle tamamlanmış sayılmaz.
