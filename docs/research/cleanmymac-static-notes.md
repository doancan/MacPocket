# CleanMyMac 5.7.2 — My Tools statik incelemesi

28 Ekim 2026. Bu kayıt kurulu Setapp uygulamasının paket metadata ve İngilizce
localization kaynakları ile resmi MacPaw belgelerini inceler. Canlı arayüz
doğrulaması ana agent tarafından ayrıca yapılır. Uygulama veya bakım işi bu
incelemede çalıştırılmadı; kurulu uygulamada değişiklik yapılmadı.

## Kimlik

- Konum: `/Applications/Setapp/CleanMyMac.app`.
- Bundle: `com.macpaw.CleanMyMac-setapp`.
- Sürüm: `5.7.2`; build: `50702.0.2610141002`.
- Executable: `CleanMyMac_5_Setapp`.
- Kaynak: `Contents/Info.plist`.
- `SMPrivilegedExecutables` içinde `com.macpaw.CleanMyMac-setapp.Agent` kaydı var.
  Bu, her aracın admin yetkisi istediğini veya o agent'ın bu anda çalıştığını
  kanıtlamaz.

[Resmi sürüm kaydı](https://macpaw.com/cleanmymac/whats-new), 5.7.2'yi
15 Ekim 2026 tarihine bağlar. Browser Care bu sürümde, Screen Cleaning Mode
5.7.1'de ve My Tools 5.5.0'da duyurulmuştur.

## My Tools kataloğu

MacPaw'ın [22 Ekim 2026 tarihli My Tools belgesindeki](https://macpaw.com/support/cleanmymac/knowledgebase/my-tools)
21 araç aşağıdadır. Bu liste kullanıcı kapsamının karşılaştırılacağı referanstır;
her aracın bu Mac'te çalıştırıldığı anlamına gelmez.

| Grup | Referans araçları |
| --- | --- |
| Uygulama | App Leftovers, App Updater, Uninstaller |
| Performans | Background Items, Login Items, Maintenance Tasks, Time Machine Snapshot |
| Alan ve dosya | AI Clutter, Downloads, Duplicate Finder, Large and Old Files, Similar Images |
| Temizlik | Mail Attachments, System Junk, Trash Bins |
| Koruma | Application Permissions, Malware Finder, Privacy Items |
| Bağımsız araçlar | Browser Care, Email Cleanup, Screen Cleaning Mode |

Aynı belge favoriye alınan araçları ilk bölümde, kalanları başka bölümde
gösterdiğini açıklar. Araç araması ve doğrudan araca erişim My Tools'un temel
etkileşimleridir.

## Yerel kaynaklarda doğrulanan My Tools yapısı

Kaynak kökü: `Contents/Frameworks/`.
Her framework için localization dosyası
`<Ad>.framework/Versions/A/Resources/en.lproj/Localizable.strings` konumundadır.
Dosyalar `plutil -convert json -o -` ile salt okunur çözümlendi; binary/text
strings dosyalarında sabit satır numarası yerine tam key kaydedilir.

| Framework | Anahtarlar / metadata | Statik sonuç |
| --- | --- | --- |
| ToolboxModule | `module_name`, `intro_search_placeholder`, `tools_section_header_favorites`, `tools_section_header_others`, `favorite_save`, `favorite_saved` | My Tools başlığı, arama, favoriler/diğer araçlar ve kaydetme durumları mevcut |
| ToolboxModule | `browser_care_card_title`, `browser_care_card_open`, `browser_care_carousel_install` | Browser Care kartı ve Chrome extension kurulum/erişim metinleri mevcut |
| ApplicationsModule | `custom_flow_updateApps_title`, `custom_flow_uninstaller_title`, `custom_flow_leftovers_title` | Updater, Uninstaller ve leftovers adları mevcut |
| PerformanceModule | `custom_flow_backgroundItemsManagement_title`, `custom_flow_loginItemsManagement_title`, `custom_flow_maintenanceTasks_title`, `custom_flow_timeMachineSnapshot_title` | Performans araçlarının adları mevcut |
| JunkCleanupModule | `custom_flow_aiClutter_title`, `custom_flow_mailAttachments_title`, `custom_flow_systemJunk_title`, `custom_flow_trashBin_title` | Temizlik kartları ve AI clutter adları mevcut |
| OrganizeModule | `custom_flow_duplicateFinder_title`, `custom_flow_downloads_title`, `custom_flow_laof_title`, `custom_flow_similarImages_title` | Dosya düzenleme araçlarının adları mevcut |
| ProtectionModule | `custom_flow_applicationPermissions_title`, `custom_flow_malwareFinder_title`, `custom_flow_privacyItems_title` | Koruma araçlarının adları mevcut |
| EmailCleanupModule | `email_cleanup_module_name`, `email_cleanup_card_title`, `email_cleanup_card_scan_cta` | Email Cleanup kartı ve scan eylemi mevcut |
| ScreenCleaningMode | `my_tools_card_title`, `settings_accessibility_description` | Screen Cleaning Mode kartı ve giriş kilidi için Accessibility açıklaması mevcut |

`ToolboxModule` Info.plist bundle kimliği `com.macpaw.CleanMyMac.ToolboxModule`;
`PerformanceModule` için `com.macpaw.CleanMyMac.PerformanceModule`;
`ScreenCleaningMode` için `com.macpaw.CleanMyMac.ScreenCleaningMode`.

Temel localization dosyası SHA-256 değerleri:

- ToolboxModule: `69edc46e071a3edec6258bcfafefea2204b69d493ec211908c524b82c0aa8caf`.
- PerformanceModule: `0528420c4a0bcc78c0010f7703538e7132cc1a63ef0632980b0dba7b25a2a9c2`.
- ScreenCleaningMode: `12719a43bb83c1070f962716bb4fb8e31bf0963ce31bd4df9e6a808d7b6e9b71`.

## Bakım görevleri ve Mac Studio sınırları

PerformanceModule içinde şu title key'leri bulunur:
`free_up_ram_title`, `flush_dns_cache_title`, `free_up_purgeable_space_title`,
`reindex_spotlight_title`, `repair_disk_permissions_title`,
`periodic_scripts_title`, `speed_up_mail_title`, `thin_local_snapshots_title`.
`custom_flow_maintenanceTasks_search_keywords` bunları arama terimleriyle eşler.

[Resmi bakım belgesine](https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks)
göre RAM boşaltma Intel Mac'lerle, periodic scripts macOS 13 ve öncesiyle,
Time Machine snapshot işlemi ise Time Machine kurulumu bulunan cihazlarla
sınırlıdır. Dolayısıyla kaynakta bir task title bulunması Apple Silicon Mac
Studio/macOS 27 üzerinde kullanılabilirlik kanıtı değildir.

DNS cache temizleme, Spotlight ve Mail indeksleme, purgeable alan ve snapshot
bakımı sistem veya kullanıcı verisini değiştiren operasyonlardır. Salt okunur
terminal tanılarıyla aynı yürütme sınıfına konmamalıdır. Statik metinler bunların
komutunu, kullanılan backend'i, başarı durumunu veya tam etki alanını kanıtlamaz.

## MacPocket için çıkarım

Tools kataloğu; arama, favoriler, kategori, destek/yetki durumu ve işlem geçmişi
ile ortak giriş yüzeyi olabilir. Uygulama kaldırma/güncelleme gibi zaten başka
modüllerde bulunan işlevler aynı servislere yönlenir.

Kullanıcının ek istediği terminal tabanlı sistem gözlemleri (memory pressure,
swap, sleep assertions, ağ ve açık dosyalar) ayrı Sistem İzleme/Sistem Araçları
kataloğudur. Bunlar CleanMyMac My Tools içinde gözlenmiş kartlar olarak
sunulmamalıdır. Görev Yöneticisi de kullanıcının ek gereksinimidir.

Email Cleanup hesap bağlantısı; Browser Care tarayıcı extension'ı; malware
tespiti ise ayrı motor/veri kaynağı gerektiren kapsamlar olarak değerlendirilir.
Yalnız kartları çoğaltmak bu özelliklerin implementasyonu sayılmaz.

## Açık doğrulamalar

- Canlı My Tools listesi ile yukarıdaki katalog arasındaki cihaz/sürüm farkları.
- Arama, favori ve karta girişin canlı akışı.
- Bakım görevlerinin bu Mac'teki görünürlük ve çalışabilirlik durumları.
- İlgili işi gerçekten çalıştırmadan etkisi, tamamlanması veya geri dönüşü
  hakkında sonuç verilmemesi.
