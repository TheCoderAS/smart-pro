# Unisync mobile app

Flutter app for Android + iOS. Controls Unisync masters and extensions
over the device's own Wi-Fi (`192.168.4.1`) — local-first, no cloud.

See [PLAN.md](PLAN.md) for the full build plan, and
`../web/docs/UNISYNC_API_REFERENCE_v1.md` for the device API.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run          # with a device/emulator attached
```

Layout follows PLAN.md §4: features under `lib/features/`, transport
and platform plumbing under `lib/core/`, app-level wiring (router,
theme, l10n) under `lib/app/`.
