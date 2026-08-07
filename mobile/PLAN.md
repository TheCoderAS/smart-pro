# Unisync mobile app — build plan (v1)

_Plan for the Unisync Flutter app targeting Android and iOS, informed by
`web/docs/UNISYNC_API_REFERENCE_v1.md` (v1.0, master firmware v11.13.2)
and `web/docs/UNISYNC_OPERATIONS_GUIDE_v1.md` (v2.0)._

**Scope:** the complete production app. Every feature the API surfaces
is in scope: login, live control, extension management, mesh
administration, firmware updates, and BLE password recovery. Nothing
is deferred.

---

## 1. Product properties the app must respect

These are not features; they are invariants that shape every layer of
the app. Ignore any of them and the app breaks in the field.

- **The device is local-only.** All HTTP and WebSocket traffic goes to
  `http://192.168.4.1` (port 80 for REST, port 81 for WebSocket).
  There is no cloud path. The phone must be joined to the device's
  Wi-Fi before any endpoint is reachable.
- **One password does two jobs.** The same string joins the Wi-Fi and
  authenticates the API. There is no separate account, no email,
  no OAuth.
- **Tokens do not expire and survive reboots** — verified
  arithmetically, not stored server-side. Only a password change
  revokes them.
- **A token issued by any master in a mesh is accepted by every
  master in that mesh.** The app must not care which master it is
  currently talking to.
- **Roaming is silent.** The IP stays `192.168.4.1` even as the phone
  hops between masters. State can jump between messages because a
  different master answered. Treat every WebSocket message as an
  authoritative full snapshot; never merge incrementally.
- **Password change is a special dance.** The reply arrives before the
  Wi-Fi restarts (~400 ms later). The app must wait for the reply,
  then expect the Wi-Fi to drop, then rejoin with the new password,
  then re-log-in.
- **Extension firmware is signed offline.** The signature is produced
  with a firmware key the app does not hold. The CDN doesn't need to
  be trusted. The app is only a transport for the signed manifest.
- **Master firmware is verified by secure boot, not by the master
  itself.** A master OTA can return 200, reboot, and come back on the
  old version. Confirmation comes from `GET /api/info` after reboot,
  not from the upload response.
- **`cred_stale: true` on a peer means "surface as remove & re-add"** —
  the master cannot self-heal.
- **Recovery is BLE-only** — the API is behind the Wi-Fi the user
  cannot join. Recovery must therefore be reachable from a logged-out
  app, on the login screen, not in settings.

---

## 2. Target platforms

| Concern | Target | Notes |
| --- | --- | --- |
| Flutter | **Stable channel, latest release** at build start (currently 3.24+; adopt 3.27+ / 4.x when it lands) | Track a single channel; upgrade in a scheduled sprint, not ad-hoc. |
| Dart SDK | **3.6+** minimum | Enables strict null-safety, patterns, records. |
| Android `minSdk` | **24** (Android 7.0) | Covers >99% of active devices; needed for BLE and Wi-Fi Network Suggestions. |
| Android `compileSdk` / `targetSdk` | **latest stable** (35+; bump each Google deadline) | Google requires target within one API of latest for Play Store updates. |
| Android Gradle Plugin | **latest 8.x** | Java 17 required (bundled by newer AS). |
| iOS deployment target | **iOS 14.0** | Required for the modern Bluetooth central APIs used by `flutter_blue_plus`, and for `NEHotspotConfiguration` deprecation-free flows. |
| iOS Xcode | **latest stable** | Match App Store submission requirement. |
| Locales | English at launch; architected for later Hindi / Kannada | Every user-visible string via `flutter_localizations` + ARB from day one. |
| Dark mode | Required | Follow system by default; explicit toggle in settings. |

---

## 3. Package matrix

Every choice below is on a maintained release channel as of 2026-Q3.
Deprecated / abandoned alternatives are named explicitly so we don't
accidentally drift to them.

| Concern | Chosen | Rationale | Rejected |
| --- | --- | --- | --- |
| **HTTP client** | `dio` | Interceptors for `X-Auth`, per-request timeouts, download progress for firmware, first-class `CancelToken`. | `http` alone (thin, no interceptor story). |
| **WebSocket** | `web_socket_channel` + a tiny hand-rolled reconnect wrapper | Official Flutter team, no runtime baggage. Auto-reconnect logic is small enough that a dependency isn't worth the coupling. | `web_socket_client` (fine but a third dep for ~40 lines of code). |
| **BLE** | `flutter_blue_plus` | Actively maintained (fork after `flutter_blue` went abandoned), supports Android 12 runtime permissions, supports iOS Core Bluetooth including background modes. | `flutter_blue` (abandoned), `flutter_reactive_ble` (still active but slower release cadence). |
| **Wi-Fi network joining** | `wifi_iot` | Only cross-platform option that wraps Android `WifiNetworkSuggestion` **and** iOS `NEHotspotConfiguration`. Actively maintained. | `flutter_wifi_connect` (Android-only), rolling our own platform channels (avoidable YAGNI). |
| **Wi-Fi scanning** (for onboarding a new master) | `wifi_scan` | Only current option; Android 13+ requires `NEARBY_WIFI_DEVICES` permission which this wraps. | `wifi_iot`'s scan API on iOS is not exposed. iOS cannot scan third-party Wi-Fi anyway — we scan on Android and fall back to a manual SSID entry on iOS. |
| **Secure storage** (token, remembered device passwords) | `flutter_secure_storage` | Keychain on iOS, EncryptedSharedPreferences on Android. Actively maintained. | `flutter_storage` (unrelated), plain `shared_preferences` (not encrypted). |
| **Preferences** (theme, last-connected device UID) | `shared_preferences` | Official, current, tiny. | `hive` (abandoned; use `hive_ce` if we ever need embedded storage, but not for prefs). |
| **State management** | `flutter_riverpod` (v2.x, code-gen with `riverpod_generator`) | Compile-time safety, testable, no `BuildContext` gymnastics, works with `AsyncNotifier` for the request/response patterns dominant in this app. | `provider` (superseded by Riverpod), `get`/`getx` (dubious code quality, discouraged), Bloc (viable but heavier and boilerplate-heavier than Riverpod for this app's shape). |
| **Routing** | `go_router` (v14+) | Declarative, deep-link friendly, official Flutter team package, plays nicely with Riverpod via `riverpod_annotation`. | `auto_route` (viable, code-gen heavy), `Navigator 2.0` raw (unnecessary). |
| **Cryptography** (HMAC-SHA256 for BLE) | `crypto` | Official Dart team package, tiny, sync API sufficient for 8-byte challenge. | `cryptography` package (more elaborate but overkill here). |
| **Hex codec** (recovery-key parsing) | `convert` | Official Dart team. | Custom parser (there's no reason). |
| **QR scanning** (for scanning the device UID/recovery-key card during onboarding) | `mobile_scanner` | Uses ML Kit / AVFoundation; actively maintained; supports Flutter 3.24+. | `qr_code_scanner` (abandoned), `qr_flutter` (encoder only, not scanner). |
| **Permissions** | `permission_handler` | Standard, actively maintained, handles Android 12/13 runtime BLE + `NEARBY_WIFI_DEVICES` permission split correctly. | Rolling per-permission ad-hoc code. |
| **Logging** | `logger` package + a thin `Logger` port that swallows PII on release builds | Simple, structured console output during dev; no telemetry ever leaves the device. | `logging` (core, less ergonomic), any hosted-log SaaS (device is LAN-only and users won't opt in). |
| **App icons / splash** | `flutter_launcher_icons`, `flutter_native_splash` | Standard, actively maintained. | Manual per-platform asset generation. |
| **Serialisation** | `freezed` + `json_serializable` | Immutable data classes + generated `fromJson`/`toJson`; matches the API's plain JSON. | Hand-written models (repetitive, error-prone). |
| **DI / service locator** | Riverpod providers | Riverpod already does DI; no separate container needed. | `get_it` (unnecessary layer on top of Riverpod). |
| **Testing** | `flutter_test` + `mocktail` + `patrol` (for integration on real device / emulator) | `mocktail` is null-safety-native; `patrol` handles native permission dialogs which our BLE and Wi-Fi flows will trigger. | `mockito` (still works but requires build_runner-gen mocks). |
| **CI runtime** | `subosito/flutter-action@v2` on GitHub Actions | Ubuntu for Android AAB/APK, macOS for iOS IPA. Actively maintained. | Fastlane on its own (heavier), Bitrise (external SaaS). |

**Explicitly rejected as deprecated / abandoned:**
`flutter_blue`, `qr_code_scanner`, `hive` (superseded by `hive_ce`),
`provider` (superseded by Riverpod for greenfield), `getx`, `mockito`
(superseded by `mocktail` for null-safety-native tests).

---

## 4. Repo layout

```
mobile/
├── android/                          # generated by flutter create, edited for network config + permissions
├── ios/                              # generated by flutter create, edited for ATS + BLE + hotspot config
├── lib/
│   ├── main.dart                     # entrypoint, ProviderScope, MaterialApp.router
│   ├── app/
│   │   ├── router.dart               # go_router configuration
│   │   ├── theme.dart                # Material 3 light + dark
│   │   └── l10n/                     # ARB files, generated Dart
│   ├── core/
│   │   ├── api/
│   │   │   ├── dio_client.dart       # Dio setup, X-Auth interceptor, retry, 401/423/429 handling
│   │   │   ├── endpoints.dart        # every path from §5 of the API doc
│   │   │   └── failure.dart          # sealed hierarchy: Network, Auth, Locked, RateLimited, Server
│   │   ├── ws/
│   │   │   ├── state_socket.dart     # single-writer wrapper, auto-reconnect, snapshot replay
│   │   │   └── state_dto.dart        # full snapshot type, freezed
│   │   ├── ble/
│   │   │   ├── recovery_service.dart # scan → connect → challenge → HMAC → response → result
│   │   │   └── uuids.dart            # service + three char UUIDs from API §8
│   │   ├── wifi/
│   │   │   ├── join.dart             # wraps wifi_iot: suggest + register + await connected
│   │   │   └── scan.dart             # Android scan; iOS returns UnsupportedError
│   │   ├── crypto/hmac.dart          # HMAC-SHA256 truncated to 8 bytes helper
│   │   ├── storage/
│   │   │   ├── secure_store.dart     # token per master UID; remembered passwords
│   │   │   └── prefs.dart            # theme, last-used device UID
│   │   ├── errors/error_dispatcher.dart  # 401 → re-auth flow, 423 → lockout screen, 429 → back-off
│   │   └── logging/log.dart
│   ├── features/
│   │   ├── auth/                     # login, password change, forgot-password entrypoint
│   │   ├── recovery/                 # BLE recovery flow, logged-out
│   │   ├── onboarding/               # first-time commissioning of a factory-fresh master
│   │   ├── dashboard/                # live switch grid, room grouping
│   │   ├── switches/                 # rename, reorder, killall
│   │   ├── extensions/               # list, pending-pair prompts, assign / reject / replace / rename / remove
│   │   ├── mesh/                     # status, create, invite, join, leave, rename, mesh-password change
│   │   ├── firmware/                 # library, upload from CDN with progress, extension + master OTA
│   │   ├── audit/                    # /api/audit viewer
│   │   └── settings/                 # theme, sign out (local), sign out all (password change)
│   └── shared/
│       ├── widgets/                  # reusable buttons, cards, empty states
│       └── models/                   # shared freezed types
├── test/                             # unit + widget tests
├── integration_test/                 # patrol scenarios
├── assets/
│   ├── icon/                         # source PNGs for flutter_launcher_icons
│   └── splash/                       # source PNGs for flutter_native_splash
├── pubspec.yaml
├── analysis_options.yaml             # includes flutter_lints + stricter rules
└── README.md
```

**Feature-first inside `features/`, plumbing in `core/`.** Every feature
owns its screen widgets, its Riverpod providers, and any feature-only
DTOs. Cross-feature contracts live under `shared/`.

---

## 5. Architecture

**Three layers**, wired by Riverpod, code-gen wherever possible:

1. **Data** — `dio_client`, `state_socket`, `recovery_service`,
   platform Wi-Fi / BLE wrappers. Pure transport, no domain vocabulary.
2. **Repository / notifier** — `AsyncNotifier`s that map raw responses
   to domain models, own retry / auth-refresh policy, and expose
   `AsyncValue<T>` streams the UI can watch.
3. **Presentation** — `ConsumerWidget` / `HookConsumerWidget`
   subscribing to notifier providers, no direct HTTP.

**Single source of truth for live state:** one `StateSocketNotifier`
(a Riverpod `Notifier`) holds the full snapshot the WebSocket delivered.
Every dashboard widget reads a `Selector`-style slice of it. Commands
(POST `/api/relay`, etc.) are optimistic — flip local state, wait for
the next snapshot, roll back on failure.

**Auth flow:**
- On app start, read the stored token for the last-used device UID.
- Call `GET /api/info` with `X-Auth: <token>`. If 200 and
  `auth: true`, we're logged in.
- On any 401, redirect to the password prompt; retry the original
  request once with the new token; if that succeeds, resume normal
  operation.
- After `/api/password` returns 200: show "reconnecting…" UI, tear
  down the socket, kick off Wi-Fi rejoin with the new password, then
  re-login.

**Failure hierarchy:**
```dart
sealed class ApiFailure {}
class UnreachableFailure extends ApiFailure {}   // no route to 192.168.4.1
class Unauthorized      extends ApiFailure {}   // 401
class LockedOut         extends ApiFailure { final Duration retryAfter; }  // 423
class RateLimited       extends ApiFailure { final Duration retryAfter; }  // 429
class ServerFailure     extends ApiFailure { final int status; final String body; }
class NotOnDeviceWifi   extends ApiFailure {}   // detected via wifi_iot ssid check
```

The Dio interceptor turns raw exceptions into this hierarchy so the UI
layer only ever pattern-matches on `ApiFailure`.

---

## 6. Complete feature inventory

### 6.1 Onboarding
- **Factory-fresh master commissioning.** Phone joins the AP with
  the label password → `GET /api/info` returns `auth: false` → prompt
  user to set the owner password → `POST /api/password` → login →
  proceed to dashboard.
- **Add existing master to app.** Scan the QR / enter the UID and
  password from the label → join AP → login → save token.
- **Add master to an existing mesh** (via the physical master already
  in the mesh). `POST /api/mesh/invite` on the joined master
  produces a `mac`/`pin` pair, the new master calls
  `POST /api/mesh/join` with those.

### 6.2 Login
- Password field, "sign in" button.
- "Forgot password" link — goes to BLE recovery.
- Handle 401 (wrong password), 423 (lockout with countdown), 429
  (back-off with retry timer).

### 6.3 BLE recovery (§8)
- Reachable from the login screen while logged out.
- Prompt user to bring the phone close to the device.
- Scan for advertising name `U{UID}` — user selects theirs.
- Connect → read challenge (8 bytes) → prompt for recovery key
  (32 hex, on the card) → compute `HMAC-SHA256(key, challenge)`
  truncated to 8 bytes → write → read/notify result → new password
  is returned as ASCII.
- On success, offer to auto-join the AP with the new password.
- Silence = failure; 15 s timeout, warn user, allow retry.
- Show "5 failures locks the service for 15 minutes" after 3
  failures.

### 6.4 Dashboard
- Live switch grid, powered by the WebSocket snapshot.
- Group by extension slot / rename ("Living Room / Kitchen").
- Tap toggles via `POST /api/relay id=... state=...`.
- Long-press → rename, reorder.
- Header: master name, mesh badge if `mesh: true`, reconnecting
  indicator when socket is down.
- "Kill all" affordance in overflow menu — `POST /api/relay/killall`
  with confirm dialog.
- Empty-state guidance when no extensions are provisioned yet.

### 6.5 Switches (management)
- Rename individual switches: `POST /api/switch/rename id, name`.
- Reorder: drag handles, commit via
  `POST /api/switch/reorder plain=<comma-separated>`.

### 6.6 Extensions
- List extensions from `GET /api/extensions`: name, slot, online
  status, firmware, stuck flag, available update badge.
- Pending-pair prompt: when a new extension advertises, the master
  surfaces it; the app assigns via `POST /api/assign uid, name`.
- Reject: `POST /api/reject uid`.
- Replace an existing extension into a slot:
  `POST /api/replace uid, slot, name`.
- Rename in place: `POST /api/rename slot, name`.
- Remove: `POST /api/remove slot` with a "this cannot be undone"
  dialog.

### 6.7 Mesh
- Status page from `GET /api/mesh/status`: mesh name, peer count,
  firmware, syncing flag, peer list with per-peer name/fw.
- **`cred_stale: true` on any peer** → prominent action tile "This
  master missed a password change and cannot self-heal. Remove and
  re-add." Links to the remove flow.
- **Create mesh** (standalone → mesh, first master):
  `POST /api/mesh/create name`.
- **Invite from an existing mesh master**:
  `POST /api/mesh/invite` → shows `mac` + `pin` to enter on the
  joining master.
- **Join** on the joining master:
  `POST /api/mesh/join mac, pin`.
- **Leave**: `POST /api/mesh/leave` with a strong-confirm.
- **Rename**: `POST /api/mesh/rename name`.
- **Change mesh password**: `POST /api/mesh/passwd old, pass, name`
  — piggy-backs the special reconnection dance from §6 of the API
  doc.
- **Relay a switch on another mesh peer**:
  `POST /api/mesh/relay peer_uid, sw_id, ch` (used implicitly when
  the dashboard shows peer switches).
- **Mesh config** command:
  `POST /api/mesh/config cmd, target_uid, …` (advanced admin;
  behind "Advanced" affordance).

### 6.8 Master rename
- `POST /api/master/rename name` — accessible from settings and from
  the master's card on the mesh page.

### 6.9 Firmware
- **Manifest fetch.** A per-device-type manifest URL is baked into
  the app config (or fetched from a top-level `firmware.json`).
  The manifest shape from API §7 is:
  ```json
  { "type": 1, "version": "1.2.1", "sec": 0, "size": 9456,
    "sig": "4d6da99f…", "url": "https://cdn/…/ext_t1_1.2.1.bin" }
  ```
- **Show what's available vs installed** per extension type; poll
  `GET /api/fw/list` and per-extension `avail` field.
- **Upload flow** for extensions:
  1. Download the `.bin` from the manifest URL (progress bar,
     cancellable).
  2. Verify local file size matches `size`.
  3. Multipart-POST to `/api/fw/upload?mesh=1` with fields
     `firmware=<bin>`, `sig=<sig>`, `sec=<sec>` and header
     `X-Auth: $TOKEN`.
  4. Show "queued" — the master updates matching switches within
     30 s each, one at a time.
  5. Poll `/api/extensions` and reflect the `fw` field until all
     matching extensions report the new version.
- **Master OTA** via `POST /api/ota/master` multipart. After 200,
  show "rebooting"; poll `GET /api/info` and warn if `fw` still
  shows the old version — the image was rejected by secure boot.
- Surface upload errors: `missing signature`, `not a Unisync
  extension image`, `image not in signed library`, `signature
  INVALID` — each with a plain-English explanation.
- **Never** call `/api/ota/image` — that's master-to-master.

### 6.10 Audit
- `GET /api/audit` viewer. Just a scrollable list of log entries
  with timestamps. Read-only.

### 6.11 Settings
- Theme (system / light / dark).
- Change password (`POST /api/password` with the reconnect dance).
- Sign out (local): discard token.
- Sign out all devices (equivalent to a password change, per API §2).
- Remove this master from the app: clears stored token + preferences.
- About: app version, master firmware version.

### 6.12 Multi-master support
- The app supports having multiple masters saved (e.g. house + office,
  each a separate mesh).
- Master switcher on the top bar; each entry is a `(UID, name, mesh
  name)` triple with its own stored token.
- When a user opens a master the app tries to join its Wi-Fi if
  not already connected. iOS's `NEHotspotConfiguration` handles the
  system prompt.

---

## 7. Build sequence

Not "phases with go/no-go gates" — just a rational ordering. Each block
lands as its own PR; the app builds and runs after each.

1. **Bootstrap.** `flutter create --org in.unisync --project-name
   unisync mobile`. Analysis options. `pubspec.yaml` with the package
   matrix from §3. Riverpod scope, empty router, splash / launcher
   icons.
2. **Config, permissions, network security.** Android manifest,
   `NetworkSecurityConfig.xml` allowing cleartext to `192.168.4.1`,
   iOS `Info.plist` with ATS `NSAllowsLocalNetworking` +
   `NSLocalNetworkUsageDescription` + BLE + Wi-Fi info-purpose
   strings (see §8).
3. **Core plumbing.** Dio client with `X-Auth` interceptor, failure
   hierarchy, secure token store keyed by master UID, `logger`.
4. **Wi-Fi join / scan wrappers.** Cross-platform `join(ssid,
   password)` and Android-only `scan()`; a "not on device Wi-Fi"
   guard used by every screen behind the login wall.
5. **Auth.** `POST /api/login`, token persistence, session bootstrap
   via `GET /api/info`, 401/423/429 handling, sign out.
6. **State socket.** `web_socket_channel` subscription with reconnect,
   snapshot type, connectivity indicator.
7. **Dashboard.** Reads state socket, renders switch grid, sends
   `POST /api/relay` on tap.
8. **Switch management.** Rename + reorder + killall.
9. **Extensions.** Full CRUD (assign, reject, replace, rename,
   remove, pending prompts).
10. **Mesh.** Status, create, invite, join, leave, rename,
    mesh-password change (reconnect dance), `cred_stale` action tile,
    advanced mesh config.
11. **Firmware.** Manifest fetch, cancellable download, extension OTA
    upload, master OTA upload with post-reboot confirmation, list +
    poll.
12. **BLE recovery.** Scan by `U{UID}`, challenge / HMAC / response /
    result flow, auto-join with new password on success, lockout
    warning after 3 failures.
13. **Onboarding.** Factory-fresh commissioning; QR-scan a device
    card; add-master flow; add-master-to-mesh flow.
14. **Audit viewer.**
15. **Settings, multi-master switcher, About.**
16. **Localisation scaffolding.** Extract every user-visible string
    to ARB; English first.
17. **Accessibility pass.** Semantics labels, contrast against
    Material 3 palette, dynamic type, keyboard/switch-access on
    Android, VoiceOver on iOS.
18. **Release prep.** Signing configs, ProGuard/R8 rules if any
    package needs them (BLE plugin usually does), iOS entitlements,
    App Store / Play Console metadata, screenshots.

---

## 8. Platform-specific configuration

### Android (`android/`)

- `minSdk 24`, `compileSdk 35+`, `targetSdk 35+`, Kotlin 2.x, Java 17.
- `AndroidManifest.xml` permissions:
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
  <uses-permission android:name="android.permission.CHANGE_WIFI_STATE"/>
  <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
  <!-- Android 13+ Wi-Fi scan without location -->
  <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
      android:usesPermissionFlags="neverForLocation" tools:targetApi="33"/>
  <!-- BLE, Android 12+ split -->
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
      android:usesPermissionFlags="neverForLocation" tools:targetApi="31"/>
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"
      tools:targetApi="31"/>
  <!-- Legacy BLE on Android <12 requires location -->
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
      android:maxSdkVersion="30"/>
  ```
- `network_security_config.xml` (referenced from `<application
  android:networkSecurityConfig="…">`):
  ```xml
  <network-security-config>
    <domain-config cleartextTrafficPermitted="true">
      <domain includeSubdomains="false">192.168.4.1</domain>
    </domain-config>
    <base-config cleartextTrafficPermitted="false"/>
  </network-security-config>
  ```
  Cleartext to `192.168.4.1` only — everything else (the CDN) must
  be HTTPS.

### iOS (`ios/Runner/Info.plist`)

- Deployment target 14.0.
- ATS exception:
  ```xml
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
  ```
- Purpose strings (any missing string causes a Store rejection):
  ```
  NSLocalNetworkUsageDescription  = "Unisync connects to your switches on your home Wi-Fi."
  NSBonjourServices               = (leave empty unless we advertise; we don't)
  NSBluetoothAlwaysUsageDescription   = "Unisync uses Bluetooth to recover a lost password from a nearby switch."
  NSBluetoothPeripheralUsageDescription = same
  NSLocationWhenInUseUsageDescription = "" (we do not use location; do not include)
  ```
- Wi-Fi joining requires the `Access WiFi Information` and
  `Hotspot Configuration` entitlements — enabled in Xcode's
  Signing & Capabilities. Both are automatic-provisioning eligible.
- BLE background modes: **not** enabled (recovery is user-initiated
  and foreground; enabling background modes triggers stricter Store
  review with no user benefit).

---

## 9. Testing strategy

- **Unit tests** for:
  - HMAC-SHA256 truncation helper (fixed vectors from RFC + spot-check
    against `openssl dgst`).
  - Failure-hierarchy mapping in the Dio interceptor.
  - State-socket snapshot deserialization (freezed round-trip).
  - Password-change reconnect state machine.
- **Widget tests** for:
  - Login form (401 shows inline error, 423 shows countdown, 429 shows
    back-off timer).
  - Dashboard cell (optimistic toggle, rollback on failure).
  - `cred_stale` action tile.
  - Firmware upload progress + error surfaces.
- **Integration tests (Patrol)** for:
  - End-to-end login with a mocked device (a Dart HTTP server that
    replays canned responses).
  - Reconnect after simulated Wi-Fi drop.
  - BLE recovery flow with mocked GATT (via `flutter_blue_plus`'s
    testable transport if available; otherwise a physical device
    smoke script).
- **Contract tests** against the ops-guide sample outputs, so any
  master-firmware change that shifts a JSON shape breaks CI before
  it breaks users.

---

## 10. CI/CD

Extend the current `.github/workflows/` (which already carries
`web-ci.yml`) with:

- `mobile-ci.yml`
  - Triggers: PR + push to `main`, filtered to `mobile/**` +
    the workflow file.
  - Concurrency group `mobile-ci-${{ github.ref }}` with
    `cancel-in-progress: true`.
  - Jobs, on `ubuntu-latest`:
    1. `flutter analyze` (fails on any warning).
    2. `flutter test --coverage`.
    3. `flutter build apk --release` (produces universal APK for
       download from the workflow artefacts).
    4. `flutter build appbundle --release` for Play submissions.
  - iOS job on `macos-latest`:
    1. `flutter build ios --release --no-codesign` (no signing on
       CI — signing is a release-time job).
- `mobile-release.yml`
  - Manual `workflow_dispatch` with inputs for version, changelog.
  - On tag push `mobile-vX.Y.Z`, signs and uploads the AAB to Play
    Console internal track, and the IPA to TestFlight via Fastlane.
  - Secrets: Play service account JSON, App Store Connect API key.

**Caching:** `subosito/flutter-action@v2` handles the SDK cache;
Gradle + CocoaPods cached via `actions/cache` on `~/.gradle/caches`
and `mobile/ios/Pods` respectively.

---

## 11. Security posture

- Token stored only in `flutter_secure_storage`. Never logged.
- Recovery key is never persisted; user re-enters it on each recovery
  attempt.
- CDN images downloaded over HTTPS; signature verification happens on
  the master. The app does not need — and does not have — the
  firmware key.
- Cleartext HTTP is scoped to `192.168.4.1` on Android and to local
  networking on iOS. Any accidental non-local HTTP call fails.
- No third-party analytics, no crash reporting SaaS. If we want crash
  reports later, add Sentry with **opt-in** consent and a hard opt-out
  in Settings.
- BLE recovery UUIDs are hardcoded from the API doc — a single source
  of truth. Any change to those UUIDs is a device firmware change and
  a coordinated app release.

---

## 12. Release readiness checklist

- [ ] All 18 build blocks in §7 landed, each with tests.
- [ ] Every user-visible string in the ARB, no `Text('…')` literals
      outside test/scaffold files (enforced by a lint rule).
- [ ] Every screen has a semantics label and passes contrast check
      in dark + light.
- [ ] `flutter analyze` clean, `flutter test` clean, integration
      suite green.
- [ ] Manual smoke on: latest iPhone SE, iPhone 15 Pro Max, one
      Pixel, one Samsung, one budget Android in the target market
      (Redmi 12 or equivalent).
- [ ] Manual smoke of the password-change reconnect flow on real
      hardware.
- [ ] Manual smoke of the BLE recovery flow on a real master (the
      only way to confirm the challenge-response works end to end).
- [ ] Extension OTA verified against a real master with a signed test
      image.
- [ ] Master OTA verified with both a good image and a deliberately
      bad one to confirm the "reboot came back on old firmware"
      detection.
- [ ] Cleartext-HTTP guard verified: an accidental request to
      `example.com` HTTP fails on both platforms.
- [ ] Play Store data-safety form completed; App Store privacy
      nutrition label completed; both truthfully state "no data
      collected".
- [ ] Screenshots + store listing copy in English (+ Hindi if we
      ship it in v1).

---

## 13. Open technical questions for the team

1. **First-boot commissioning UX.** API §1 says "the password on the
   card joins the Wi-Fi and logs in", but ops guide §A2 says the
   Wi-Fi password (on the label) and the owner password (set later)
   are distinct on a factory-fresh device. Which one should the app
   assume is on the retail card for the end user? The plan above
   supports both by reading `auth` from `/api/info` and prompting
   accordingly — please confirm this matches the intended retail
   packaging.
2. **Firmware manifest hosting.** Where does the app fetch the
   per-extension-type manifest from? A single top-level
   `https://cdn.unisync.in/firmware/index.json`? Baked-in URLs per
   type? This ships in the app config.
3. **QR-code contents on the device card.** For onboarding: are we
   printing a URL, a JSON blob, or a compact `unisync://<uid>?p=<pw>`
   scheme? The onboarding UX assumes the latter.
4. **Home-screen widgets** (Android home-widget / iOS WidgetKit) —
   out of scope for the first release per this plan. Confirm.
5. **Voice-assistant integration** (Alexa / Google Home / HomeKit) —
   out of scope. HomeKit in particular would require MFi
   certification for the device, not just app work. Confirm.
6. **Multiple homes / multiple meshes** — the plan supports this via
   the master switcher. Confirm the retail scenario (one household ↔
   one mesh vs many meshes per user) so we don't over-engineer.

---

_Document owner: engineering. Update this file when the plan shifts;
each change is a PR reviewed like code._
