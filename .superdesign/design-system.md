# MacPocket — Windows Task Manager density on macOS

Product: native macOS system utility for a power user. Primary canvas target is
the Task Manager and connected System Tools. The user explicitly selected a
Windows Task Manager-like, information-dense technical interface. Turkish UI.
The actual app will be SwiftUI/AppKit; this HTML is a design prototype.

The style-library high-contrast reference informs legibility and fine dividers.
The user's technical desktop requirement overrides its marketing layout,
oversized typography and decorative treatments.

## Foundations

- Background #17191e; sidebar #121419; panels #1e2128; raised surface #272b33.
- Primary text #f1f3f5, secondary #adb4c1, muted #788291; lines #343a46.
- Selected/accent #65a7ff; CPU #65a7ff; memory #c49aff; disk #73d3a6;
  network #f3bf71; danger #f57878; success #73d3a6.
- Typography: system-ui/-apple-system, matching SF Pro/Segoe UI character.
  Monospace ui-monospace/SF Mono for PIDs and numeric tabular data.
- Body/table text 12–13px, labels 11–12px, title 22px. No oversized headings.
- 4px spacing grid; table rows 31px; controls 30–32px; corners 5–8px.
- Small line icons. No decorative imagery, logos, gradients, or motion effects.
- Compact title bar with macOS window controls; no browser chrome.
- Visible focus state, keyboard navigation, readable contrast and selected row.

## Shell and layout

1440×960 desktop reference. A 190px sidebar, flexible main pane, optional 270px
process inspector. Sidebar: Genel Bakış; Görev Yöneticisi (active); Performans;
Güç Merkezi; Sistem Araçları; Temizlik; Uygulamalar; Tools; Ayarlar. Product title
is plain text MacPocket, no invented logo. Hardware subtitle is Mac Studio.

## Task Manager

Header Görev Yöneticisi, status Son güncelleme, 1 sn/2 sn/5 sn refresh selector,
pause and refresh. Compact four-part CPU/RAM/disk/network summary with small
time-series graphs; show a tiny Örnek veri label on this prototype.

Tabs Süreçler, Performans, Başlangıç, Ayrıntılar. Main Süreçler view is a dense
sortable table, never a card grid. Columns: process, PID, user, state, CPU%,
RSS memory, threads, disk read/write and network. Values unavailable for an
adapter must be —, not simulated zero. CPU is per logical core and may exceed
100%. Include CPU-normalization choice in settings. Use restrained heat tint
in CPU/memory cells, contextual actions and a selected browser row.

Toolbar search, Tümü/Uygulamalar/Arka plan/Sistem filters, column selection.
Selected process inspector: executable path, PID/parent, user, startup time,
threads, memory and permission state. Normal Sonlandır and red Zorla Sonlandır
are distinct. System processes carry a Korunuyor state. A confirmation dialog
uses selected name/PID, cancellation and action; no silent force escalation.
After signaling, show İstek gönderildi until process exit is observed.

## System Tools

The sidebar entry switches to a compact diagnostic table with categories:
memory pressure/swap, sleep blockers, power settings/thermal state, mounted
volumes/APFS, network interfaces/connections, open files/ports and background
items. Master/detail with readable result summary, raw output disclosure,
timestamps, copy/export, refresh and pin. Show read-only diagnostics separately
from system-changing maintenance tools, with effect and availability states.

## Broader context

Tools includes the 21 CleanMyMac My Tools equivalents (independent MacPocket
features), Window Switcher, and Keep Awake. Favorites and search are central.
Power Center supports MacBooks with real hardware capability checks; this
Mac Studio has no internal battery, so show Pil bulunmuyor rather than 0%.
Settings: columns, order, units, compactness, refresh, thresholds, profiles,
shortcuts, graph ranges, imports/exports and default reset.

Prototype interactions should let the user sort/search/select processes,
switch System Tools, open process details and a confirmation dialog, change
refresh and open column options. All prototype data is illustrative; no OS
action or actual process termination is performed by the design.
