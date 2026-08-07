# Release runbook

## Versioning

Bump `version:` in `pubspec.yaml` (`x.y.z+build`). The build number
must increase monotonically for both stores.

## Android

1. One-time: generate the upload keystore and KEEP IT SAFE — losing it
   forfeits the Play listing identity:

   ```bash
   keytool -genkey -v -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Create `android/key.properties` (gitignored):

   ```properties
   storeFile=../upload-keystore.jks
   storePassword=…
   keyAlias=upload
   keyPassword=…
   ```

3. Build: `flutter build appbundle --release`. Without
   `key.properties` the build silently signs with the debug key —
   fine for CI artifacts, never uploadable to Play.

4. First upload: confirm the final `applicationId` in
   `android/app/build.gradle.kts` BEFORE uploading; it cannot change
   after publication.

## iOS

1. Xcode → Runner target → Signing & Capabilities: select the team;
   enable **Access WiFi Information** and **Hotspot Configuration**
   capabilities (both auto-provisioning eligible).
2. `flutter build ipa --release`, upload via Transporter or
   `xcrun altool`.
3. Purpose strings already in Info.plist: local network, Bluetooth
   (recovery), camera (QR). Do not add location — the app doesn't use
   it, and BLE permissions are declared `neverForLocation`.

## Store forms

Both stores: declare **no data collected** — the app talks only to
the user's own device on their LAN plus an anonymous firmware CDN
fetch. No analytics, no crash SaaS, no accounts.

## Pre-flight checklist (per release)

- [ ] `flutter analyze` clean, `flutter test` green, CI green.
- [ ] Manual smoke of the password-change reconnect dance on real
      hardware (both /api/password and /api/mesh/passwd paths).
- [ ] BLE recovery end-to-end against a real master.
- [ ] Extension OTA with a real signed image; master OTA with a good
      AND a deliberately bad image (verify the app reports the
      old-version-after-reboot case).
- [ ] Cleartext guard: an http:// request to any host other than
      192.168.4.1 fails on both platforms.
- [ ] VoiceOver / TalkBack pass on login, dashboard, recovery.
- [ ] The six PLAN.md §13 open questions are either answered or
      consciously deferred.
