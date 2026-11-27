# Changelog

All notable changes to MacPocket are documented in this file. Each release lists only the
sections that apply, in this order: Features, Improved, Changed, Fixed, Removed, Security.

## Unreleased

### Features
- **SSH Manager:** Import hosts and keys from another Mac in one step. Choose a copied `~/.ssh` folder or a config file (local or in iCloud Drive); a review sheet lists new hosts, keys and warnings before anything changes. `Include`d hosts are merged into the config, keys are copied with owner-only permissions, and an existing file is never overwritten.

### Improved
- **SSH Manager:** A config that lives in iCloud Drive and has not been downloaded yet is downloaded and explained instead of being offered as a new empty file.
- **SSH Manager:** Banner and toolbar buttons keep their natural width, so labels no longer get squeezed on narrow windows.

### Security
- **SSH Manager:** Hosts warn when a private key can be read by other users (ssh refuses such keys) and offer a one-click permission fix, and when a private key sits in a cloud-synced folder.

### Fixed
- **Language:** The first launch follows the macOS language order instead of always opening in Turkish, and a system language that is neither English nor Turkish falls back to English.
- **Installer:** The disk image window shows its whole artwork again on macOS 27, the icon labels no longer collide with the card edges, and the instructions lead in English with Turkish below.

## 1.0.0 — November 27, 2026

First public release. MacPocket is now open source under the MIT License.

### Features
- **Project:** Source code, contribution guide, security policy and architecture documentation are public.

### Improved
- **Network Speed:** The test no longer ties up worker threads for its whole duration.

### Changed
- **Main window:** The window opens at a size that shows the Overview in four columns without resizing.
- **Weather:** Forecasts come only from public providers: Visual Crossing, MET Norway and Open-Meteo without a key, and WeatherAPI.com, Pirate Weather, OpenWeather and Tomorrow.io with your own free API key. A saved selection of the removed source falls back to Visual Crossing.

### Fixed
- **Fan control:** If the temperature sensor stays unreadable for five seconds, the fans go back to macOS instead of running unsupervised.
- **Fan control:** A fan release that fails is retried every second instead of being forgotten, and a failed first request no longer leaves the diagnostic unlock set.
- **Port Manager:** A hanging `lsof` now times out after 15 seconds instead of blocking the page.
- **Commands:** Many commands timing out at once no longer delay each other, and a command that leaves a background child behind returns its output at once.
- **Cleanup:** When an administrator removal times out or is cancelled, the result lists what was actually removed instead of reporting everything as failed.

### Removed
- **Weather:** The previous third-party weather connection.

### Security
- **AI Usage:** Codex sign-in files that are named pipes or larger than 256 KiB are refused, and a sign-in command that ignores a termination request is killed after two seconds.
- **Fan helper:** A fault is logged when the helper can identify its client only by name.
- **Cleanup:** Removal with administrator rights refuses system folders, the home folder and its Library on its own, not only behind the earlier checks.

## 0.5.1 — November 23, 2026

### Changed
- **Release:** All 0.5.0 changes (the Liquid Glass setting, the Leftovers tab in Apps, consistent page layout, fan and network helper fixes) ship for the first time in this release. See the 0.5.0 changes below.

### Fixed
- **Overview:** Row names were shown twice in Overview › Quick Settings.
- **Command Bar:** The Command Bar ignored Return and Esc coming from the Accessibility Keyboard, Switch Control, or scripts. It now runs the selected command and closes the panel.

## 0.5.0 — November 23, 2026

### Features
- **Liquid Glass:** A new setting at Settings › Appearance › Material. When on, tabs, search fields, buttons, and floating panels are drawn with Liquid Glass; when off, MacPocket's own controls use opaque, flat surfaces.
- **SSH Manager:** The SSH Manager follows the Liquid Glass setting too.
- **Connection Diagnostics:** The first tab of Network Management. The modem, the internet (1.1.1.1), and DNS are measured separately, the faulty link along the connection path is flagged, and the recommended action is stated. Ping runs only when the button is pressed. `macpocket-probe connection`.
- **Internet outages:** While MacPocket is open, disconnections are recorded (drops shorter than 5 seconds are not counted). Optional notifications are available when the connection drops and when it returns.
- **Sidebar search:** Search across all pages, tools, and network tabs that ignores Turkish diacritics, available with ⌥⌘F.
- **Last open page:** A "Last open page" option under Settings › General › Page to open at launch. The tool and network tab are remembered as well.
- **Shortcuts and Spotlight:** "Open MacPocket Page" and "Diagnose Connection" actions.
- **Help menu:** MacPocket Help, Changelog, and Report a Problem replace the empty "Help isn't available" item.
- **Network Management:** Network Traffic, Wi-Fi Analysis, Local Network, Network Speed Test, Port Manager, Hosts File, and Internet Control appear in the sidebar as a single page with tabs. Only the selected tab's tool runs.
- **Stats Bar:** In the grouped layout, each module can stay in the group or also get its own menu bar item (Layout in module settings, right-click in the list).
- **Fan control:** When the app updates, the helper restarts itself and manual fan speeds are re-sent.

### Improved
- **Fan control:** The card distinguishes "reading", "unreadable", and "no fan" states, requests give up after 10 seconds, and "Reinstall Helper" is offered if the registration is corrupted.
- **Accessibility:** Icon-only buttons and menus have VoiceOver names, and rows selected by clicking have keyboard and VoiceOver actions. Hosts row checkboxes are read with the row name. Cleanup category checkboxes and Local Network device rows are now native buttons, focusable with the keyboard and selectable with Space/Return and VoiceOver.
- **Accessibility:** The running app's accessibility tree was scanned across 54 pages, and no unnamed interactive elements owned by the app remain.
- **Connection Diagnostics:** The ping result is evaluated using the median of three replies instead of the average, and DNS is measured twice. A single delayed reply no longer makes a fast connection look "slow".
- **Menu Bar Editor and SSH:** The plain text fields match the search fields on other pages.
- **Page layout:** Secondary buttons no longer look like primary ones. There is a single switch size, with switches on the trailing edge of settings rows, and icon boxes use one size per role. Settings forms align under the title, and the Internet Control, Cable Impact Map, and Menu Bar Editor cards span the page width.
- **Overview:** Tiles use a module-colored highlight instead of a growing hover effect. Quick Actions and Screenshot use the same style.
- **SSH Manager:** The SSH Manager uses the same icon box as other pages.

### Changed
- **Page layout:** Every page now follows the same order: title, summary, full-width section tabs, content (including Disk Analysis, Network, Apps, Tools, and Disk X-Ray).
- **Appearance:** New installs start with monochrome icons.
- **Apps:** App Leftovers is now the third tab of the Apps page (also reachable from search and the Command Bar).
- **Apps:** Apps that ship with macOS and cannot be deleted are no longer listed. Apple apps installed from the App Store or downloaded separately (Xcode, Compressor, and others) can now be uninstalled, and the lock applies only to apps actually protected by System Integrity Protection.
- **Liquid Glass:** The sidebar, toolbar, and menus are always drawn with glass by macOS.
- **Tools:** Practical Tools were removed from the sidebar and open within Tools, with a new icon.
- **Translations:** 391 unused English translations left over from removed features were deleted.

### Fixed
- **Fan control:** The app crashed when the helper service was unreachable.
- **MAC scan:** The app crashed when the helper was unreachable during a MAC scan.
- **Port Manager:** Process numbers for multi-port processes rendered as a vertical stack of characters.
- **Display Brightness:** Cards overflowed the page in a narrow window.
- **Interface:** "Save" buttons appeared as "Record" in English.
- **Interface:** Interface APIs deprecated in macOS 27 were updated.
- **Apps:** When macOS denies removal during app uninstall (App Management, bundles containing root-owned files), the bundles are now permanently deleted with an administrator password. Trash mode explains what to do, and the app waits 15 seconds for heavy apps to quit.
- **Disk X-Ray:** The page started a new full-disk scan each time it was revisited and left the previous one running in the background, which froze the app after a few visits. Results are now preserved and the last scan time is shown.

### Removed
- **Tools:** Update Center and Workspaces were removed. Saved layouts and repository links are deleted at launch, and unused translations were cleaned up.
- **Tools:** Screen Time, Macros, Text Shortcuts, Focus Session, macOS Tools, Support Report, and Privacy Check were removed, along with background services and the Focus module in the menu bar. Saved data is left untouched, and changes left behind by a crashed focus session are reverted once.
- **Sidebar:** The logo and tagline were removed from the sidebar.
- **Power Center:** The Energy Settings and Power Reports buttons were removed from the header. They remain in the Settings tab and under Tools › System Reports.
- **Stats Bar:** The 1×/1.5×/2× selector in the preview was removed.

## 0.4.0 — November 19, 2026

### Features
- **Menu bar icons:** A new "Icon and value" style.
- **Menu bar popover:** The Summary tab (health score, CPU/memory/disk/network tiles, recent events) is the default first tab.
- **Menu bar popover:** The Clipboard tab, shown when clipboard history is on, supports search, a type filter, click to paste into the frontmost app, and pinning.
- **Menu bar popover:** The Health tab answers "Why is my Mac slow?" with sustained load, memory pressure, swap, heat, and a filling disk, each with a one-click fix.
- **Menu bar popover:** The Events tab lists sleep/wake, network drops, heating, memory pressure, and disk mount/eject.
- **Menu bar popover:** The Launcher tab holds favorite apps, folders, files, and links.
- **Menu bar popover:** The Disk tab estimates when the disk will fill based on the last week's trend. Process lists offer Quit, Force Quit, and Show in Finder from the right-click menu.

### Improved
- **Menu bar icons:** Drawings snap to the display's pixel grid (sharp on non-Retina displays as well). Values use the menu bar clock's typeface, and small text is at least 10 pt.
- **Menu bar icons:** Warning and accent colors tint only the value and the graph, while the icon and label keep the menu bar's color. The attention dot does not change the item's width. Grouped icons were redrawn.
- **Menu bar popover:** Content switches instantly. Tabs show a bold icon and name side by side, and the selected tab is highlighted in the accent color. The tab bar scrolls when it does not fit.
- **Menu bar popover:** In light and dark appearance, it uses a clean background and cards like macOS Settings, independent of the window behind it. Text uses only macOS type styles (minimum 10 pt).
- **Performance:** The main window's last page is no longer drawn in the background while the window is closed, and the process list no longer re-reads process paths on every measurement. The running-apps list updates only when an app launches or quits, and temperature sensors are read at most every 5 seconds.
- **Performance:** The menu bar uses 0.5% CPU instead of 2.0% with the window closed, and 1.4% instead of 3.1% with the popover open (development build, median measurement).

### Changed
- **Menu bar popover:** The popover is a fixed-size window that does not jump when tabs change.
- **Menu bar popover:** New installs start with Summary, CPU, Memory, Network, and (if clipboard history is on) Clipboard. Existing selections are preserved.

### Fixed
- **Cleanup:** The page's ring animation kept running when the page was empty and used 25% CPU (now 0.5%).
- **Clipboard:** Click-to-paste did not reach the target app.
- **Clipboard:** Saved history was deleted when the clock was set back by a few seconds.

### Removed
- **Menu bar popover:** The "Advanced" switch was removed. Every tab shows full detail.

## 0.3.0 — November 14, 2026

### Features
- **Disk X-Ray:** A new tool that breaks down "System Data" item by item. It measures Xcode, simulator runtimes and devices, package managers, developer toolchains, AI models (including Ollama), logs, temporary files, Docker, virtual machines, iOS backups, the Android SDK, app caches, project build folders, and unexplained large folders (including the owning app). Each item is classified as Safe, Review, or Manual.
- **Disk X-Ray:** Before deleting, the exact operations are shown and can be copied. "Free X GB" makes the least worrying selection. History, trends, growth alerts, and "deleted and came back" items are kept on this Mac.
- **Disk X-Ray:** "Shrink instead of delete" uses transparent APFS compression (verified, atomic swap). Verified archiving and restore are also included.
- **Disk X-Ray:** Small and medium widgets, a menu bar item, Shortcuts actions (get size, clean safe items), optional external-disk projects, closing simulators on quit, and navigating to the page from a notification.
- **Disk X-Ray:** Optional daily scan, low-space alert, weekly summary, and weekly safe automatic cleanup. `macpocket-probe system-data [--json | free <GB> | clean [--apply]]`.
- **Keep Awake:** A "Turn the display off when idle, keep the Mac awake" setting (1–30 min), and "7 days (longest)" in the duration list for conditional keep-awake.
- **Apps:** A single "Remove Completely" button with a single confirmation permanently deletes the app and all associated files found (including user data). The plan is re-scanned after the app quits, and files written during quit are deleted too. A single administrator password is requested for system files and root-owned items.
- **Apps:** The uninstall plan now also finds Group Containers, Application Scripts, cookies, ByHost preferences, LaunchAgents, helpers/services under /Library, and Application Support folders matching the app name.

### Improved
- **Disk X-Ray:** "Shrink" now works file by file, preserving hard links within the folder and verifying every copy. It needs free space only equal to the largest file, refuses if a build tool (cargo, xcodebuild, and so on) is running in the folder, and estimates the savings beforehand from a real sample. A 188 GB Rust `target` folder shrank to 63.8 GB.

### Changed
- **Deletion:** Cleanup, Space Lens, File Tools, App Leftovers, and Uninstall now permanently delete items by default, and space is freed immediately. A "Deletion mode" menu on each screen lets you choose moving to the Trash instead. The Trash is still emptied with a separate confirmation.

### Security
- **Full Disk Access:** On the Cleanup, Disk Analysis, Uninstall, and Leftovers screens, a warning card appears when the permission is missing. It opens System Settings and a drag-and-drop card, and suggests restarting after the permission is granted. The explanation in the setup wizard describes these uses.

## 0.2.0 — November 11, 2026

### Features
- **Stats Bar:** A page with a live preview (light/dark menu bar, 1×–2× zoom), a module list sorted by dragging, and separate options for each module. Options include a style gallery with real drawings, chart type (bar/line/area) and width, font size, label position and alignment, fixed accent color, and an independently ordered threshold editor.
- **Stats Bar:** New styles: horizontal bar and ring, and three bars and a live chart for the grouped icon.
- **Clock:** A new module with world clocks (city list in the popover).
- **Menu bar values:** CPU load average, swap usage, and power consumption (W).
- **Appearance:** Seventeen color themes selectable from a menu in Settings › Appearance (MacPocket, Midnight, Tokyo, Ocean, Mint, Forest, Nord, Solarized, Gruvbox, Sunset, Cherry, Coffee, Sand, Rose, Purple, Dracula, Graphite: surfaces and accent colors). Each theme's contrast is verified by a test.

### Improved
- **Stats Bar:** The popover is now opaque, takes theme colors, and follows the system's light/dark appearance.
- **Stats Bar:** Stacked label/value and two-line values are vertically centered and aligned to the same edge.
- **SSH Manager:** The icon was redrawn.

### Changed
- **Stats Bar:** Menu bar settings moved from Settings to the main window.

### Fixed
- **Weather:** The location name was written twice ("Ankara Ankara, Türkiye").
- **Stats Bar:** The warning threshold could exceed the critical threshold.
- **Stats Bar:** The grouped popover also showed disabled modules as tabs.
- **Settings:** Popup menu pickers were unreadable in the accent color.
- **Navigation:** The ⌘ shortcut cycle crashed when more than 9 pages were added.
- **Stats Bar:** A menu bar list row toggled the module on and off instead of selecting it under VoiceOver/accessibility.

## 0.1.7 — November 11, 2026

### Features
- **Keep Awake:** A new menu bar module that shows a full cup and remaining time when on. Preset durations, keeping the display on, and automation status are in the panel.
- **Focus:** A new menu bar module that shows remaining time and progress. Duration selection, start/end, today's time and streak are in the panel.
- **Bluetooth batteries:** A new menu bar module that shows the accessory whose battery will run out first, colored by threshold.
- **Brightness and night mode:** A new menu bar module that shows main display brightness, with a slider for each external display, night mode status, sunrise/sunset, and pausing. All four new modules are enabled from Settings › Menu Bar and appear as their own item in every layout.
- **Weather:** The hour card opens a separate details page. When the source provides them, it shows precipitation probability/amount/intensity, feels-like temperature, humidity, wind/gust/direction, pressure, cloud cover, visibility, UV, and dew point. The 1/3/6/12-hour precipitation periods are preserved, and missing fields are not filled with zeros.
- **Weather:** The panel has a large temperature/condition display, a compact humidity-wind-pressure row, a scrollable hourly forecast, and daily temperature bars on a shared scale. Location and source settings moved to a separate view, and the selected source and refresh remain at the bottom. Separate states were added for an empty location, loading, errors, a missing key, and the absence of a detailed forecast.
- **Weather:** From 11 free-access options, the ones you want can be added to the source basket, and the menu bar queries only the selected source. Visual Crossing, MET Norway, and Open-Meteo need no key, and ECMWF IFS/AIFS Single, GFS, and ICON are separate model options.
- **Weather:** WeatherAPI.com, Pirate Weather, OpenWeather's free current-weather/5-day forecast endpoints, and Tomorrow.io work with a personal API key. Provider-specific caching, persistent selection, quota/access errors, and coverage links were added, and existing users' iStat connection is preserved until the first selection change.
- **Uninstall:** The uninstall plan shows the app, caches/logs, and user data in separate groups. Group selection, Show in Finder, and a persistent selection summary were added, and user data is not selected by default.

### Improved
- **Alt+Tab panel:** The closing fade was handed off to the window server, and the panel is no longer redrawn while closing. With 24 windows and the close animation on, the panel closes in 5–7 ms instead of 383–443 ms.
- **Alt+Tab panel:** The selection animation slides only a single frame, and card contents change without animation. Cards are recomputed only when their own inputs change.
- **UI updates:** The Power, Cleanup, Apps, Local Network, Weather, Screen Time, and Audio Mixer screens and the main model moved to Observation, so screens refresh only when a value they read changes. Power overview cards are limited to their own data, and when the app language is pinned, localized strings are read from a cache.
- **AI quota view:** Session and weekly percentages are larger and side by side, and model-specific limits are shown at full width. The repeated account percentage was removed, and low/full quota warnings and explicit reset times were added. The menu panel shows more accounts at once, and text and bar contrast was strengthened in the light theme.
- **Clipboard history:** JSON generation and atomic disk writes moved to a serial background queue. Changes arriving during a write are merged into the latest state, and the completion of an older write does not mark newer changes as saved.
- **Clipboard history:** The last save is preserved on quit, and deleting, or turning off on-disk storage, completes after the pending write. A late error response cannot invalidate a successful retry, and the on-disk storage preference is applied even when clipboard capture is off.
- **Clipboard history:** No save is scheduled unless content changes, and the quit/module-stop call does not rewrite the archive. History that has not yet loaded is not saved with an empty in-memory state.
- **Clipboard history:** Real changes are stored with the existing delayed save, and a failed save can be retried. When on-disk storage is turned back on, in-memory history and images are saved, and deleting everything does not recreate an empty archive.
- **Clipboard search:** The tool page and quick panel query a shared in-memory index, prepared as history changes, off the UI thread. A 120 ms debounce while typing and cancellation of the stale request were added, and while a search is pending, the previous result is not pasted with Enter or the shortcut.
- **Clipboard search:** Turkish letter conversion, source app, type filter, and pinned-first ordering are preserved. A new entry prepares only the changed search document, and an empty search shows the list without waiting.
- **Screen Time:** Cards and charts share the same day/hour summary. The same app durations are no longer summed repeatedly for day totals, active day count, average, and scale, and the comparison with the previous day uses the same live record snapshot.
- **Clipboard list:** To build the title for long text, the code advances to the first non-empty line instead of splitting the entire text into lines. Leading blank lines, Unicode line endings, whitespace trimming, and the 200-character preview are preserved, and the invisible remainder of long log text is not re-split while the title is prepared.
- **App Leftovers:** Matching looks up the candidate's full name and the app identifiers at dot/hyphen boundaries in a set, instead of walking all installed apps for each candidate. Case, helper-app boundaries, and the same-vendor warning are preserved, and different apps with the same prefix are not hidden.
- **USB Eject:** The page refreshes through Disk Arbitration change notifications instead of running `diskutil` every three seconds. Attach/detach, partition, and mount point/name changes are coalesced with a short delay.
- **USB Eject:** Listeners are removed when the page closes, and if a notification session cannot be created, the previous scan serves as a fallback. A change arriving during a refresh is not lost, and the old selection of a re-attached disk is not preserved.
- **Fan panel:** On the app side, temperature is read only for temperature-dependent profiles and off the UI thread. Unnecessary sensor scanning was removed for the automatic/fixed profile.
- **Fan panel:** When the hidden panel returns to the automatic profile, the fans are released to the system and the loop stops, while the manual profile's heartbeat continues. A pending temperature or target response does not reapply the old profile.
- **GPU measurement:** Only the performance statistics, model, and core count are read, instead of copying the entire driver property table on each read. The GPU list and values are re-queried on every measurement, and the busiest-GPU selection is preserved.
- **Menu bar history:** When the system and menu bar history fill up, append/trim is published as a single update. Each measurement produces one publish instead of two, and the buffer limit is not shown to subscribers as exceeded.
- **Weather:** Instead of a per-second UI poll, a single wait is scheduled for the time the button becomes usable again. A source/time change or the view closing cancels the old wait, and manual retry and API quota limits are preserved.
- **Process scanning:** Automatic process reads stop when Task Manager is hidden, minimized, or fully covered, and the list refreshes immediately when the window returns. Unnecessary process scanning was removed at main window launch and on pages that do not use process data. The open menu bar process panel and explicitly requested report/port reads continue to work.
- **Live charts:** Small charts are drawn on a single Canvas instead of creating a separate chart element per sample. Smooth curves, colored fill, the negative Wi-Fi scale, and the automatic upper bound are preserved. Invalid values are excluded from drawing, and sensor and menu bar refresh intervals are unchanged.
- **Menu bar panel:** Native animations are preserved for the first open/close and for size changes. Clicking another MacPocket icon switches the open panel's content and the icon it is attached to, rather than closing and reopening the panel. The Reduce Motion preference is respected, and closing with an outside click and Escape is preserved.
- **Weather:** Working previous/next buttons replaced the visual arrows in the hourly forecast. Clicking an hour card shows the date/time and Celsius temperature provided by the source, and the details can be dismissed. At scroll limits the buttons are disabled, and the Reduce Motion preference is preserved.
- **Uninstall:** After the uninstall confirmation, a normal quit is requested first. Files are not moved until the app and the helper processes inside the bundle have quit. Processes that do not quit require a separate force-quit confirmation, and on error the plan stays open. Scope and verification are documented separately.

### Changed
- **Menu bar settings:** Keep Awake buttons moved from the Power and Fan panel, and night mode items from the right-click menu, into the new modules, giving a single place for these settings.
- **Distribution:** Because the repository is private, downloading requires GitHub access. Since the anonymous Sparkle update URL is not reachable, this release must be downloaded from the Release page and installed manually.

### Fixed
- **Menu bar panel:** The open request was lost when clicking between the weather, AI, and other icons. A selection arriving during a real close is retained, on rapid switching the last target opens, and clicking the same icon again closes the panel.

### Removed
- **Bluetooth batteries:** The separate menu bar icon was removed. If it was previously on, the new module is enabled once automatically.

### Security
- **Weather:** API keys are stored in the Keychain.

## 0.1.6 — November 7, 2026

### Features
- **Alt+Tab window switching:** Animated preview cards, selection with Tab/Shift+Tab while Alt is held, and bringing the window to the front when Alt is released.
- **Alt+Tab window switching:** Independent filter/view/release settings for nine shortcuts and customizable window actions were developed. Acceptance coverage for physical keyboard/trackpad and all Space/full-screen combinations is tracked separately, and full AltTab parity is not claimed.
- **Cable Impact Map:** For the selected USB/Thunderbolt device, it shows connected disks, open files, TCP/SSH sessions matching the local address, and display/audio effects together. Hardware evidence and user matches are kept separate, and the tool is read-only. Scope and acceptance limits are documented separately.
- **Menu Bar Editor:** Apps can be collected into a hidden group and hidden or shown with an arrow button. It includes a searchable list and opening an icon. The macOS 27 private visibility interface is checked at runtime, and the compatibility limit with system panels is explained in the tool.
- **Update center:** An independent update center with Sparkle for apps outside Homebrew, optional App Store, and public GitHub release sources linked to the app. Checks are started manually, and installation continues in the publisher's flow.
- **Internet Control (experimental):** Allow/block rules by signed app identity, a connection list, and a Network Extension. The filter is off at launch, and using it requires macOS extension/network filter approval. Rules apply to new connections, and acceptance of actual blocking is not yet complete. Scope and verification are documented separately.

### Changed
- **Distribution:** Because the repository is private, downloading requires GitHub access. Since the anonymous Sparkle update URL is not reachable, this release must be downloaded from the Release page and installed manually.

## 0.1.5 — November 6, 2026

### Features
- **DMG installer:** The installer window has MacPocket's own icon, drag-and-drop installation into the Applications folder, a Retina background, and Turkish/English instructions. The existing ZIP and Sparkle flow is preserved for automatic updates.
- **SSH Manager:** A single workspace for SSH config editing, connection and ProxyJump tests, connecting with Terminal/iTerm2/Ghostty, key and known_hosts management, backups, and quick connect with a global shortcut. A Turkish/English interface and preference/backup import from existing SSH managers were added.
- **AI usage tracking:** Quotas of Claude, Codex/ChatGPT, and Grok accounts can be monitored separately from the menu bar, the usage screen, and a small floating panel. For Claude there are separate profiles, profile folder discovery, sign-in through an explicit user action, account management, quota alerts, and a per-account refresh cooldown policy.
- **Command Bar, File Shelf, and Dock Previews:** Quick access to tools and content, collecting and transferring files/text/images, and window previews from the Dock.
- **Screenshot and mouse tools:** Scrolling screenshots, captures pinned to the screen, and per-app mouse button assignments.

### Improved
- **Modules:** Enabling and disabling modules individually and releasing the resources of disabled modules were improved.
- **Audio and updates:** Per-app audio routing, channel-based update sources, and conditional keep-awake were improved.
- **Tools:** Card alignment in tabs was tidied.
- **Alt+Tab:** The panel opens without taking app focus. Quick selection, delayed panel display, and switching to the selected window on Alt release were improved.

### Removed
- **Tools:** Duplicate tool cards for functions available in the sidebar or system settings were removed.

### Security
- **DMG installer:** The DMG download is signed and notarized by Apple.
- **Permissions:** Showing which features use each permission was improved.

## 0.1.4 — November 5, 2026

### Features
- **Case Converter:** 14 text/code formats, Turkish/English İ/ı rules, live preview with a 300 ms debounce, line-by-line batch conversion, acronym/number splitting, and Latin letter simplification. All formats can be compared, copied individually or in bulk, and the selected result can be used as input. Text statistics are shown. Processing is local, there is a 64 KiB input limit, and cancelled or stale results are guarded against.
- **Practical Tools:** A separate offline workspace in the left menu with JSON editing/minification, standard/URL-safe Base64, URL parameter encoding, JWT content and time inspection, SHA-256/SHA-512, bulk UUID v4, secure passwords/tokens, Unix seconds/milliseconds conversion, line diff, and text/Wi-Fi QR generation.
- **Practical Tools:** Includes search, persistent favorites, examples, temporary tool drafts, error/progress states, copying, and text/PNG export. JSON preserves large numbers and key order, and JWT signatures are not verified.
- **Weather:** The menu bar shows temperature and a condition icon, with a feels-like temperature option and hourly and five-day forecast panels. Users can search for a city/district and select their location, and the selection is preserved when the app is reopened. The location can be changed from the panel or from Menu Bar settings.
- **Weather:** Includes hourly automatic refresh and keeping the last successful data on connection errors.
- **USB Eject Manager:** Lists external physical disks and their partitions, with safe single/bulk eject, processes and open files using the disk, and switching to Finder and to the app. Internal/startup disks are protected, and a re-attached disk does not inherit the old selection.
- **Local Network:** Lists devices by name, vendor (built-in MACLookup and IEEE registries), type, IP/MAC, and latency. Multiple networks can be scanned together (Wi-Fi, Ethernet, manually added VLAN ranges). The detail panel offers a network map, live ping, port scan, risk warnings, Wake-on-LAN, and new device notification.
- **Local Network:** A normal network scan automatically completes MAC lookup on all selected subnets through the installed helper service, with no separate button or per-scan password. Direct lookup is limited to 32 concurrent pings and also adds devices not visible in a normal scan.
- **Power Scheduling:** Recurring wake/power-on and sleep/shutdown times, and one-time events.

### Improved
- **Tool interfaces:** An inventory of screens and routing was made for 57 catalog entries. In a narrow window, header actions move to the next line, and short settings screens are scrollable.
- **Tool interfaces:** Loading, refreshing, empty, and error states were separated in USB/Thunderbolt, disk health, Bluetooth, network traffic, and startup items. Screen recording shows preparing/saving stages, and success is reported when the file is complete.
- **Tool performance:** Totals for Network Traffic groups are computed in a single pass. Reset no longer launches an extra `nettop`, and pending stale results do not leak into the new session.
- **Tool performance:** When no external disk is present, the USB eject list makes one `diskutil` query instead of three. Weather waits directly for the hourly refresh time instead of a per-minute check loop, and the timer does not start if no location is selected.
- **Local Network:** MAC information on other subnets uses SNMP target IP–interface matching, with an explanation for interface MACs that cannot be matched and a priority for direct ARP results and the interface/address filter.

### Fixed
- **Tool interfaces:** Search focus and keyboard access to the network map were fixed. Audio output errors are now visible.
- **Local Network:** During MAC lookup, results are not written for a network that was removed. The temporary route is cleaned up only if it was added successfully, and devices found only through Bonjour are also listed.
- **Local Network:** The helper's service identifier, file path, and XPC name in the wizard are preserved, and a normal scan does not trigger reinstallation/approval.

## 0.1.3 — November 4, 2026

### Features
- **Updates:** Automatic updates via Sparkle, with a "Check for Updates…" menu and automatic checking and downloading in Settings.
- **Screen Time:** Per-app daily and hourly time and 7- and 30-day charts. Idle, locked, and sleep time are not counted.
- **Setup wizard:** A welcome on first launch, live permission status, and a drag-and-drop card for System Settings.
- **GPU:** A module showing GPU usage, processor, and memory in the menu bar, with a detail panel.
- **Network:** Ping, Wi-Fi signal, VPN lock, and an offline warning for the Network module.
- **Menu bar views:** CPU core bars, pie, and disk read/write, with sensor selection for temperature.

### Improved
- **Menu bar editor:** Drag-and-drop ordering in the live preview, add/disable from the shelf, and click to configure.
- **Threshold colors:** The value turns orange at the warning threshold and red at critical (%, °C, ms, dBm).
- **Maintenance:** Revamped with 8 tasks, administrator tasks with a single password, and live status and last-run information.

### Fixed
- **Build:** All compiler warnings in the release build were cleared.
- **Setup wizard:** When macOS restarts the app after a permission is granted, the setup wizard resumes where it left off.

### Security
- **Updates:** Updates are signed.

## 0.1.2 — November 3, 2026

### Features
- **Wi-Fi Analysis:** Signal, noise, BSSID, channel congestion of nearby networks, and a channel recommendation for the modem.
- **Network Traffic:** Shows live which app downloads and uploads how much.
- **Disk Health:** SSD wear, data written, and temperature (NVMe SMART).
- **USB and Thunderbolt:** Connected devices, link speed, and power, with a slow-cable warning.
- **Hosts File:** Redirect or block domains and toggle groups with one click.
- **Screenshot:** Region, window, and full-screen capture, preview cards, history, and annotation.
- **Display Settings:** Hidden HiDPI modes, refresh rate, main display, and mirroring.
- **Bluetooth Batteries:** Device batteries including Logitech, and a low-battery notification.
- **Fan control:** Fan control and a fan card in Power Center.
- **Menu bar:** Hottest sensor and Bluetooth battery indicators.
- **Settings:** A performance group in hidden Settings with animations, App Nap, and Dock settings.
- **Displays:** Volume and mute keys for monitor speakers (DDC).
- **Cleanup:** Profiles and category selection in the scan.
- **Energy:** A new Energy page.

### Improved
- **Cleanup:** A new scan animation.

### Changed
- **Platform:** macOS 27 became the baseline.

### Fixed
- **Bluetooth:** Devices connected with a charging cable stay in the list.
