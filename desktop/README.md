# NST Tunnel — Desktop

Modern Flutter desktop client (Windows & macOS) for NST Tunnel.

> This is the UI shell with a polished Material 3 interface. The native
> tunnel/core engine integration is planned — the app currently simulates
> the connection lifecycle so the interface can be built and reviewed.

## Build
```bash
cd desktop
flutter create --platforms=windows,macos .
flutter pub get
flutter build windows --release   # or: flutter build macos --release
```
