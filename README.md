# NST Tunnel

Android + desktop VPN/proxy client based on [v2rayNG](https://github.com/2dust/v2rayNG) / Xray, with a Happ-style dark UI.

[![API](https://img.shields.io/badge/API-24%2B-yellow.svg?style=flat)](https://developer.android.com/about/versions/lollipop)
[![Latest](https://img.shields.io/github/v/release/Kirillka645/nst-tunnel)](https://github.com/Kirillka645/nst-tunnel/releases/latest)

## Download

**One universal Android APK** (arm64 + armeabi-v7a + x86 + x86_64):

→ [Latest release](https://github.com/Kirillka645/nst-tunnel/releases/latest) → `NSTTunnel_*.apk`

Also: Windows `.zip` and macOS `.dmg` desktop builds.

## Project layout

```
nst-tunnel/
├── V2rayNG/                 # Android app (Gradle / Kotlin)
│   └── app/                 # UI, VPN service, Xray core AAR
├── desktop/                 # Flutter desktop client (sing-box engine)
├── AndroidLibXrayLite/      # submodule — Xray mobile lib source
├── hev-socks5-tunnel/       # submodule — TUN helper
├── .github/workflows/       # CI: single APK + desktop release
├── compile-hevtun.sh
└── README.md
```

| Path | What |
|------|------|
| `V2rayNG/` | Main Android project — open this folder in Android Studio |
| `desktop/` | Flutter Windows/macOS client |
| `fastlane/` | Store metadata |

## Features

- Large **circular** connect button (Happ-style)
- **Ping** and **Update subscription** on the home screen
- Server cards with delay/type chips
- Deep indigo dark theme
- Single universal APK (no ABI matrix)

## Build Android

```bash
# submodules + hevtun + libv2ray.aar as in CI, then:
cd V2rayNG
./gradlew :app:assemblePlaystoreRelease
# → app/build/outputs/apk/playstore/release/NSTTunnel_<version>.apk
```

F-Droid flavor (optional): `./gradlew :app:assembleFdroidRelease`

## Geoip / Geosite

- Files live under `Android/data/com.nstkir.nsttunnel/files/assets`
- Enhanced lists: [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)

## License

GPL-3.0 — derived from v2rayNG; must stay GPL-compatible.
