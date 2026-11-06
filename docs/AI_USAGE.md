# AI abonelik kotaları

MacPocket menüsü → **AI Kotaları…** ile doğrudan, veya Ayarlar → Menü Çubuğu → **AI Kotaları** → **Hesapları ve Kota Ayarlarını Aç** üzerinden hesap eklenir. Hesap eklendiğinde AI menü öğesi açılır. Claude, Codex/ChatGPT ve Grok CLI desteklenir. Bu araç API harcama raporu değildir; AI Dosyaları / AI Clutter ile ilişkisi yoktur.

## Claude klasörünü bulma

**Hesap Ekle → Claude → Mevcut hesabı kullan** içinde profiller otomatik aranır. **Claude Klasörlerini Bul** ile yeniden tara ve bulunan klasöre tıkla. Varsayılan Claude Code oturumu klasör aramadan seçilebilir. `~/.claude-work` gibi bir yolu yapıştırabilir veya **Klasör Seç…** ile gizli klasörleri de gösteren pencereden seçebilirsin. Anahtar Zinciri kaydını elle seçme seçeneği **Gelişmiş** altında bulunur.

Arama; `~/.claude`, ana klasördeki `.claude*` profil adayları, `.claude-profiles` altındaki adaylar, `CLAUDE_CONFIG_DIR`, önceden eklenen profiller ve MacPocket profil klasörleriyle sınırlıdır. Tüm disk veya proje klasörleri taranmaz. Yalnız dosya/klasör adlarına bakılır; klasör bulma işlemi oturum anahtarını okumaz. Bulunan klasörün geçerli bir hesaba giriş yaptığı doğrulanmış sayılmaz.

## Çoklu Claude hesabı

1. **Hesap Ekle** ile sağlayıcı olarak Claude’u seç, “Kişisel” veya “İş” gibi bir ad ver.
2. **Yeni hesaba giriş yap** seçeneğine geç ve **Ekle ve Giriş Yap** düğmesine bas.
3. Terminal’de Claude Code’un `claude auth login` akışını tamamla. Claude Code önceden kurulu olmalıdır. Giriş açılamazsa hesap satırındaki **Profile Giriş Yap** ile tekrar dene.
4. Diğer hesabı aynı şekilde ekle. Her profil ayrı `CLAUDE_CONFIG_DIR` kullanır; mevcut varsayılan Claude Code oturumu değiştirilmez.

Profil klasörleri `~/Library/Application Support/MacPocket/AIUsage/ClaudeProfiles/<UUID>` altında oluşturulur. CLI, bu klasörün kendi oturumunu macOS Anahtar Zinciri’nde yönetir. MacPocket yalnız ilgili profilin bilinen ad alanını veya kendi `.credentials.json` dosyasını okur; başka bir hesabın kaydına kendiliğinden geçmez. Mevcut bir profil klasörü veya belirli bir Anahtar Zinciri kaydı da açıkça seçilebilir. CLI adlandırması değişirse mevcut profil ekleme ekranında ilgili kayıt seçilmelidir.

Claude Code’un hesap izolasyonu belgesi: [Log in with multiple accounts](https://code.claude.com/docs/en/authentication#log-in-with-multiple-accounts).

## Codex / ChatGPT ve Grok

Her hesap için CLI’ın kendi ayrı oturum dosyasını seç. **Geçerli CLI oturumunu kullan** mevcut `CODEX_HOME` / `GROK_HOME` veya varsayılan `.codex` / `.grok` klasörünü seçer. Birden fazla hesap aynı değişen dosyaya bağlanmamalı; her hesap ayrı CLI oturumu kullanmalıdır. MacPocket bu dosyalardaki oturumları yenilemez, kurulum yapmaz veya ücretli model isteği göndermez. Yeniden giriş ilgili CLI’dan yapılır.

## Gösterim ve davranış

- En fazla 32 hesap; “Menüde” işaretli ilk üç hesabın sağlayıcı simgesi ve yüzdesi menü çubuğunda, diğerlerinin sayısı `+N` olarak görünür. Aynı sağlayıcıdan birden fazla hesap varsa kısa hesap adı da gösterilir. Tüm etkin hesaplar ayrıntı panelindedir.
- Kalan/kullanılan yüzde veya yalnız simge seçilebilir. Başlık yüzdesi sağlayıcının en yüksek kullanım oranına sahip limitidir; oturum/haftalık/model/aylık limitler ayrıntıda ayrı gösterilir.
- Her hesap için son veri, istek zamanı, sağlayıcı bekleme süresi ve bildirim dönemi bağımsızdır. Manuel yenileme de sağlayıcının asgari aralığına ve HTTP 429 bekleme süresine uyar.
- Varsayılan yenileme 5 dakika; seçenekler 5–60 dakika. Menü öğesi ve yüzen panel kapalıysa sorgu ve zamanlayıcı çalışmaz. Hesabın kendi anahtarı da o hesabı duraklatır.
- İsteğe bağlı yüzen panel yatay/dikey kullanılabilir. Yüzen panel, menü öğesinden bağımsız açılabilir.
- Bildirimler varsayılan kapalıdır; açıkça etkinleştirildiğinde macOS izni istenir. Eşikler kullanılan kota yüzdesine uygulanır; her hesap/limit/dönem için yinelenmez.
- Bağlantı hatası, giriş ihtiyacı ve istek sınırı ayrı belirtilir; varsa son başarılı değer korunur. Takibi kaldırmak CLI oturumunu veya profil klasörünü silmez.

## Veri ve bağımlılıklar

Oturum anahtarları ayarlara veya kota önbelleğine kopyalanmaz. Ayarlar hesap adı ve kaynak konumunu; yerel önbellek kota verisini ve bildirim durumunu içerir. Tanılama özeti hesap adlarını, dosya yollarını ve token’ları içermez. İstekler yalnız üç sabit HTTPS kota adresine gider; yönlendirme, çerez ve kalıcı HTTP önbelleği kapalıdır. Otomatik token yenileme ve ücretli CLI istemi kullanılmaz.

Kota adresleri sağlayıcıların belgelenmemiş uç noktalarıdır; değişiklikler erişimi bozabilir. Gerçek sonuçlar aboneliğe ve CLI oturum biçimine bağlıdır. Grok CLI kotası Grok web kotasından farklı olabilir.

MIT lisanslı üçüncü taraf UsageCore uyarlaması `Packages/AIUsageKit` içinde yerel olarak bulunur. Kaynak/revizyon bilgisi `UPSTREAM.json`, telif ve izin metni `LICENSE` içindedir; lisans uygulamada `Licenses/AIUsageKit.txt` olarak paketlenir. Harici bir uygulama veya araştırma klasörüne çalışma zamanı bağımlılığı yoktur. Bu paketin kullanılmayan bağımsız güncelleyicisi çıkarılmıştır; MacPocket kendi Sparkle güncelleme akışını kullanır.

## Kota odaklı görünüm

AI Kotaları penceresi **Genel Bakış**, **Hesaplar** ve **Ayarlar** olarak ayrılır. Genel Bakış her hesabın oturum ve haftalık limitlerini aynı satırda gösterir. Hesaplar sekmesinde hesap adı, takip anahtarı, menüde gösterim ve oturum kaynağı yönetilir. Genel gösterim/yenileme/bildirim tercihleri Ayarlar’dadır.

Yüzen panel 96 pt genişliğinde cam şerittir; hesap adları, sağlayıcı simgeleri ve oturum/haftalık için ayrı küçük göstergeler içerir. Yön düğmesi yatay düzene geçirir. Tutamaçla sürüklenebilir; ayar düğmesi hesap penceresini açar, kapat düğmesi yalnız yüzen paneli kapatır. Kısaltmalar Türkçe O (Oturum), H (Haftalık), A (Aylık), M (Model); İngilizce S, W, M, M’dir. Tam limit adı, kalan/kullanılan gösterim biçimi, sıfırlanma ve son veri zamanı hesap üzerinde bekletince görünür. Son başarılı değerler güncel değilse durum simgesi ve açıklaması korunur.
