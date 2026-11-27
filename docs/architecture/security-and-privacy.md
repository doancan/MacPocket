# Security and privacy

MacPocket works locally. It has no account system and no analytics. Network access
is limited to the features listed below.

## Network access

| Feature | Destination | Data sent |
| --- | --- | --- |
| Updates | GitHub Releases (`appcast.xml`) via Sparkle | Standard update check; system profiling is disabled |
| Connection diagnostics, speed test | Public resolvers and test endpoints | Probe traffic only |
| Weather (menu bar) | The forecast provider the user picks: Visual Crossing, MET Norway or Open-Meteo without a key, or WeatherAPI.com, Pirate Weather, OpenWeather or Tomorrow.io with the user's own free API key | Coordinates of the selected city; the user's key goes only to that provider |
| AI usage tracking | Provider usage endpoints (Claude, OpenAI/Codex, xAI/Grok) | The user's own access token, sent to that provider only |
| Application update sources | GitHub releases of apps the user opts to track | Public API requests |

Nothing else leaves the Mac. Clipboard history, window titles, file listings and
network device names stay on the machine.

## Permissions

MacPocket asks for a permission only when a feature needs it. Usage strings are in
`Resources/Info.plist` (and localized in `Resources/*.lproj/InfoPlist.strings`).

| Permission | Used for |
| --- | --- |
| Accessibility | Window switcher, window layout, menu bar editor, mouse buttons |
| Screen Recording | Window thumbnails, screenshots, screen recording |
| Full Disk Access | Disk analysis and cleanup of protected locations |
| Input Monitoring | Reading battery levels of Logitech devices over HID++ |
| Microphone | Optional audio in screen recordings |
| Audio capture | Per-app volume mixer (audio is not stored) |
| Location | Sunrise and sunset for night mode (stays on the Mac) |
| Local Network | Discovering devices in the Local Network tool |
| Automation (Apple Events) | Quick actions via Finder and System Events; opening SSH sessions in the chosen terminal |

Release entitlements are in `Resources/MacPocketRelease.entitlements`. The debug
build adds debugger access (`get-task-allow`); release builds do not.

## Privileged helper

The helper runs as root and exposes a narrow XPC interface. Rules:

- The helper validates the caller's code signature and each request's arguments.
- It never executes arbitrary commands; each privileged operation is a typed method.
- Fan control has a watchdog: if the app stops sending heartbeats, or the machine
  gets hot, the helper hands control back to macOS.
- New privileged features must validate their own input and add tests.

## Credentials

- AI usage tracking reads existing Claude Code, Codex and Grok sign-ins from the
  macOS Keychain or the tools' own credential files. MacPocket does not create
  accounts or copy tokens elsewhere.
- Tokens are held in memory for the request and are never logged.
- Release signing material (Developer ID certificate, notarization and Sparkle
  keys) exists only as CI secrets.

## Destructive operations

Cleanup, uninstall and file removal show exactly what will be deleted and require
confirmation. Items are classified (safe, review, manual) and anything that cannot
be regenerated is called out. Deletion goes through `FileRemoval` so every path is
checked against protected locations first.

## Reporting a vulnerability

See [SECURITY.md](../../SECURITY.md).
