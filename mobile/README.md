# Unisync mobile app

Flutter app for Unisync masters (Android + iOS). The full build plan —
architecture, package matrix, feature inventory, and platform
configuration — lives in [`PLAN.md`](PLAN.md).

## Getting started

```sh
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generated sources are not committed
flutter run
```

## Checks

```sh
flutter analyze
flutter test
```

CI (`.github/workflows/mobile-ci.yml`) runs analyze + test on every PR
touching `mobile/**`, then builds a release APK/AAB and an unsigned iOS
build.
