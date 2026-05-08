# NST Tunnel — Desktop

Cross-platform (Windows / macOS / Linux) Flutter Desktop client for the same Xray-based VPN profiles the [NST Tunnel Android app](../V2rayNG) uses.

The Android and Desktop clients share:

- The same brand identity (Material 3 palette, brand orange #f97910, success green tertiary, warm-monochrome surfaces)
- Compatible profile import — paste a `vmess://`, `vless://`, `trojan://` or `ss://` link and it works on either platform
- The same Xray config schema (we generate identical JSON)

## Architecture

```
desktop/
├── assets/icons/                    Vector assets (logo, etc.)
├── lib/
│   ├── theme/
│   │   └── app_theme.dart           Material 3 colour scheme — mirrors
│   │                                Android res/values/colors.xml
│   ├── data/
│   │   ├── profile.dart             Profile model (VMess/VLESS/Trojan/SS/SOCKS/custom)
│   │   ├── profile_repository.dart  ChangeNotifier-based store, persisted via SharedPreferences
│   │   └── parsers/
│   │       └── uri_parser.dart      vmess:// / vless:// / trojan:// / ss:// share-link parser
│   ├── service/
│   │   ├── config_builder.dart      Profile → Xray-core JSON
│   │   └── xray_service.dart        Sidecar manager: download, run, stop, log buffer
│   └── ui/
│       ├── home_screen.dart         Single-screen MVP layout
│       ├── widgets/                 ServerCard, ConnectionFab, EmptyState
│       └── dialogs/                 Import URI sheet, install-xray progress
└── pubspec.yaml
```

### Sidecar binary

We **do not bundle Xray-core** with the installer because of binary-size & licence considerations. On first run the app downloads the latest stable build directly from the [official XTLS/Xray-core GitHub releases](https://github.com/XTLS/Xray-core/releases) (~10–20 MB) and stores it under the per-user app data directory (`%LocalAppData%\NSTTunnel\bin\xray.exe` on Windows).

This is the same approach used by `v2rayN`, `Nekoray`, and other widely-used desktop Xray clients.

## Running locally

### Windows one-time prerequisites

Flutter for Windows uses NTFS symlinks while wiring up native plugins, which
requires **Developer Mode** to be enabled. This is a one-line click and
unrelated to NST Tunnel itself, but the build will refuse to start until it
is on:

1. Open `Settings → System → For developers`
2. Toggle **Developer Mode** to **On**
3. Confirm the prompt — no reboot needed.

### Run

```bash
cd desktop
flutter pub get
flutter run -d windows         # or  -d macos / -d linux
```

## Building a release

```bash
flutter build windows --release          # Windows .exe + dependencies in build\windows\x64\runner\Release
flutter build macos   --release          # .app bundle
flutter build linux   --release
```

The Windows build requires Visual Studio Build Tools 2022 with the "Desktop development with C++" workload.

## What's included in v1

- ✅ Material 3 theme with light/dark mode (system-driven)
- ✅ Server list + import via share URI (single or batch)
- ✅ Active server selection
- ✅ Connect / Disconnect via local Xray-core sidecar
- ✅ Local SOCKS5 (port 10808) and HTTP (port 10809) inbounds — point your apps at these
- ✅ Auto-installer for the Xray binary
- ✅ Persistent storage of servers across launches

## What's planned next

- System-proxy auto-toggle on Windows (registry-level)
- TUN mode (transparent traffic capture) via wintun driver
- QR code scanner & generator
- Real-time stats overlay
- Subscription auto-update
- Routing rule editor

## License

GPL-3.0, same as the parent project.
