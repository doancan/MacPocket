# Feature catalog

What each module does today, the permission it needs, and its known limits. The
source of truth for behavior is the code and its tests; this page is the map.

## Monitoring and power

| Module | Description | Needs |
| --- | --- | --- |
| Overview | Device summary, storage, applications, power, quick settings | – |
| System monitor | CPU per interval, memory (physical, wired, compressed), disk, network, thermal state, uptime | – |
| Sensors and fans | Hottest-sensor trend; fan profiles with automatic hand-back to macOS | Helper (root, one-time install) |
| Power center | Power source, battery health and details, power schedule | – |
| Menu bar | Combined or separate CPU, GPU, RAM, disk, network (ping, Wi-Fi, VPN), power and sensor items; drag-and-drop editor, per-module thresholds | – |
| Menu bar organizer | Collapse other apps' icons into a hidden group | Accessibility |
| Weather | Temperature and forecast panel in the menu bar | – |
| Keep awake | Prevent sleep manually or conditionally (power source, apps, schedule) | – |

## Network

All network tools live on one page with tabs.

| Tool | Description | Needs |
| --- | --- | --- |
| Connection diagnosis | Measures modem, internet and DNS separately and states where the problem is; optional outage notifications and history | – |
| Network traffic | Per-app upload and download, helper processes grouped under their app | – |
| Wi-Fi analysis | Signal, noise, BSSID, channel congestion, channel suggestion | Location (macOS requirement for SSIDs) |
| Local network | Device discovery with manufacturer lookup from offline databases | Local Network; Helper for MAC discovery |
| Speed test | Download and upload measurement | – |
| Port manager | Listening ports and owning processes | – |
| Hosts file | Edit `/etc/hosts` | Administrator approval on save |
| Internet control | Per-app rules for new connections by signed app identity | Network Extension approval |
| SSH manager | Lossless `ssh_config` editing, connection and ProxyJump tests, keys, known hosts, backups, quick-connect shortcut, import of hosts and keys from another Mac (local folder or iCloud Drive) | Automation (for the chosen terminal) |

## Disk and files

| Tool | Description | Needs |
| --- | --- | --- |
| Disk analysis | Size breakdown including the "System Data" bucket; items classified Safe / Review / Manual with the exact command shown before deletion | Full Disk Access for protected areas |
| Cleanup | Large and old files, duplicate files (SHA-256), similar images (Vision feature prints) | Full Disk Access |
| Applications | Installed apps, complete uninstall with leftover discovery, update sources | – |
| Disk health | SSD wear, data written and temperature from NVMe SMART | – |
| USB eject manager | Safe eject with the processes holding the volume | – |
| Cable impact map | Shows which disks, open files, network sessions and displays depend on a USB/Thunderbolt device before it is unplugged | – |

## Productivity

| Tool | Description | Needs |
| --- | --- | --- |
| Window switcher | Alt+Tab-style switcher with live previews, per-shortcut filters, appearance and release behavior, window actions, CLI control | Accessibility, Screen Recording |
| Window layout | Snap the focused window to halves, quarters and thirds by shortcut | Accessibility |
| Clipboard history | Searchable history with preview | – |
| Command bar | Global search over pages and tools | – |
| Quick actions | Common Finder and system actions in one place | Automation |
| Close protection | Require a hold or a double press before ⌘Q or ⌘W reaches the app | Accessibility |
| App freezer | Suspend and resume processes | – |
| Dock previews, file shelf | Window previews on the Dock; drag-and-drop shelf | Accessibility, Screen Recording |

## Display, audio and devices

| Tool | Description | Needs |
| --- | --- | --- |
| Display settings | Hidden HiDPI modes, refresh rate, mirroring; brightness control | – |
| Screenshot and recording | Region, window and scrolling capture; screen recording with optional microphone | Screen Recording, Microphone |
| Grab from screen | Read on-screen text, decode QR codes, pick colors as HEX, RGB, HSL or SwiftUI | Screen Recording |
| Audio output and mixer | Output selection; per-app volume | Audio capture |
| Mouse | Button remapping and scroll tuning | Accessibility |
| Bluetooth batteries | Battery levels, including Logitech HID++ devices | Input Monitoring (Logitech only) |
| Night mode | Sunrise/sunset schedule | Location |

## Utilities

Offline helpers in Tools: case converter (14 formats, Turkish and English casing
rules), JSON format and minify, Base64 and URL encoding, JWT inspection, SHA-256 and
SHA-512, UUID v4, secure password and token generator, Unix time, line diff, and
QR / Wi-Fi QR with PNG export.

## AI usage tracking

Tracks session and weekly quotas for Claude, Codex/ChatGPT and Grok accounts, with
several accounts per provider, menu bar indicators, a floating panel and threshold
alerts. MacPocket reads sign-ins that the provider CLIs already created (Keychain or
their credential files) and sends the token only to that provider's usage endpoint.
Each Claude profile uses its own configuration directory. See
[Security and privacy](../architecture/security-and-privacy.md).

## Known limits

- Fan control, battery charge limiting and battery hardware behavior are developed
  and verified on a desktop Mac; they are not validated on MacBook hardware.
- Advanced power automation is incomplete.
- Internet control needs the user to approve the system extension; enforcement on
  a clean install has not been signed off end to end.
- Physical keyboard and trackpad acceptance of the window switcher (haptics,
  gestures) depends on attached hardware and is checked manually.
- Saving the hosts file requires administrator approval from macOS.
