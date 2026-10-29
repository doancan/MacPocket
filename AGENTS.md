# MacPocket çalışma kuralları

- Kullanıcı açıkça istemedikçe sürüm numarasını/build numarasını değiştirme, sürüm etiketi veya GitHub Release oluşturma. Geliştirme ve derleme mevcut sürüm üzerinde devam eder.
- Kullanıcı AI Dosyaları / AI Clutter aracını kapsamdan çıkardı; yeniden ekleme.
- AltTab/iStat/CleanMyMac referanslarıyla tam eşdeğerlik iddiasını yalnız özellik bazlı kanıt ve gerçek kabul testi destekliyorsa kullan. Statik inceleme, uygulanan kod ve canlı doğrulamayı ayrı kaydet.
- Bu geliştirme makinesi pilsiz Mac Studio’dur. MacBook şarj sınırı/durdurma ve pil donanım desteğini burada doğrulanmış sayma.
- Pencere geçişinin asıl deneyimi Windows Alt+Tab gibi animasyonlu önizleme kartlarıdır: Alt basılıyken Tab/Shift+Tab ile seç, Alt bırakıldığında öne getir. Tablo yalnız Tools içindeki ayar/ayrıntı görünümüdür.
- Arayüz Türkçe (kaynak dil) ve İngilizce yerelleştirilir. Kullanıcıya görünen her metin yerelleştirilebilir olmalı: SwiftUI literal’leri, `LocalizedStringKey` alan bileşen parametreleri, String gereken yerde `String(localized:)` (Core dahil). Ham değerler (`rawValue`) gösterilmez; `localizedTitle` kullan. İngilizce karşılıklar `Resources/en.lproj/Localizable.strings` (çoğullar `Localizable.stringsdict`) içindedir; `scripts/check-localizations.sh` 0 eksikle geçmeden iş bitmiş sayılmaz.
