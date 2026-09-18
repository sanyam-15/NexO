# Android rollout (Phase 6)

## Environment
- OS: Arch Linux
- IDE: Android Studio
- SDK root: `/home/diego/Android/Sdk`
- Verified with `flutter doctor` (Android toolchain OK, licenses accepted)

## Android config applied
- `namespace` + `applicationId`: `com.chere3.nexo`
- `minSdk`: max(flutter.minSdkVersion, 24)
- `targetSdk`: flutter targetSdkVersion
- Build types:
  - debug/profile signed with debug key
  - release uses `android/key.properties` if present; fallback debug signing for local builds

## App naming variants
- Main: `Nexo`
- Debug: `Nexo (Debug)`
- Profile: `Nexo (Profile)`

## Release signing
1. Copy `android/key.properties.example` -> `android/key.properties`
2. Fill keystore values
3. Build release artifacts:
   - APK: `flutter build apk --release`
   - AAB: `flutter build appbundle --release`

## Android QA checklist executed
- Emulator boot + ADB connectivity: ✅
- App build/install pipeline (`assembleDebug`/install): ✅
- Core navigation open (Home/Add/Analytics tabs): ✅
- Forms and local DB startup path: ✅

## Pending manual checks (device)
- Physical Android device QA (USB + real hardware perf)
- Play Store listing/signing upload dry-run

## Permissions/platform review
Current app does not request dangerous runtime permissions in AndroidManifest.
- No storage/media runtime permission requested
- Locale/timezone behavior uses system defaults
- SQLite local persistence works under app sandbox

## Troubleshooting on Hyprland
For emulator white-screen issues, launch with X11 backend:

```bash
QT_QPA_PLATFORM=xcb SDL_VIDEODRIVER=x11 _JAVA_AWT_WM_NONREPARENTING=1 android-studio
```

Or run emulator directly with software-safe options:

```bash
emulator -avd Pixel_8_API_36 -gpu host -no-snapshot-load
```
