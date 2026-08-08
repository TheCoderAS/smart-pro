# Unisync mobile — BLE Control build plan

_Plan for adding BLE as a second control transport, per
`docs/UNISYNC_BLE_CONTROL_v1.md` (firmware v11.15.0). Supplements
`mobile/PLAN.md`; nothing there is invalidated._

**Scope:** the complete BLE control path — discovery, pairing to a
mesh, connect, authenticated JSON command/response, live state push,
and RSSI-based roaming — plus the transport abstraction that lets the
existing UI run unchanged over either Wi-Fi or BLE. Recovery already
exists and merely shares the service (§7). Firmware OTA and all
configuration stay on Wi-Fi by design.

---

## 1. Why this is worth the work

Today the app can only control switches while joined to the master's
Wi-Fi AP, which has no internet. A user on home Wi-Fi must leave their
network to control a switch and rejoin after. BLE removes that: the
phone keeps its own network and talks to the **nearest master** over
Bluetooth.

The firmware was designed to make this cheap for the app:

- The **state document is byte-identical** across WebSocket and BLE.
- The **token is identical** across HTTP and BLE, and valid on every
  master in the mesh.

So the app's state handling and auth do **not** need to know which
transport is live. That is the design pivot this plan builds around.

---

## 2. Invariants (from the BLE spec)

- **Filter scans by manufacturer data, never by name.** Names are
  per-device (`U{UID}`); the mesh id in the manufacturer data is what
  identifies "my system".
- **Manufacturer data (6 bytes):** `[0..1]` company id `FF FF` LE,
  `[2]` format `0x01`, `[3..4]` mesh id **big-endian** (`0000` =
  standalone), `[5]` flags (bit0 in-mesh, bit1 provisioned, bit2 a
  client is already connected).
- **Mesh id is stable** across renames, password changes, reboots, and
  identical on every master in a mesh. Store it at pairing; afterwards
  only connect to masters advertising that id.
- **Roaming is the app's job.** Hop when another master is **≥10 dB
  stronger, sustained ~5 s**. Hysteresis is mandatory or the app
  oscillates mid-house. **Never re-authenticate on a hop** — the token
  is already valid on the new master. Prefer masters with flag bit 2
  clear.
- **Every message is chunked:** `[0] index, [1] total, [2..] payload`,
  ≤160 payload bytes/chunk; reassemble in order, parse at
  `index == total-1`. A single-chunk message starts `00 01`. Do not
  assume the larger MTU the master requests is granted.
- **Silent failure.** A malformed/unknown request gets **no reply** —
  use a timeout, never an error handler.
- **Every state push is a full snapshot**, not a delta (same as the WS).
- **BLE cannot do:** firmware upload, mesh create/join/leave,
  provisioning, password change, switch rename/reorder/assign, audit.
  Prompt the user to join Wi-Fi for these.

---

## 3. Architecture — the transport abstraction

The heart of the change. Introduce a `ControlTransport` interface that
both paths implement, and select the active one by reachability.

```dart
abstract interface class ControlTransport {
  TransportKind get kind;              // wifi | ble
  bool get isReady;

  Future<LoginResult> login(String password);
  Future<void> setRelay({required String id, required bool on, int? ch});
  Future<void> killAll();
  Future<List<ExtensionInfo>> extensions();
  Future<MeshStatus> meshStatus();
  Future<StateSnapshot> fetchState();

  /// Full snapshots, transport-agnostic. The dashboard already treats
  /// these as authoritative replacements (API §4).
  Stream<StateSnapshot> get stateStream;
}
```

- **`HttpTransport`** — thin wrapper over the existing Dio repos +
  `stateSocketProvider`. Almost no new code; it adapts what's already
  built to the interface.
- **`BleTransport`** — new; everything in §4–§8 feeds it.

**Selection** (`activeTransportProvider`): prefer Wi-Fi when
`WifiService.masterReachable()` succeeds (the LAN path is faster and
unlocks the config-only features); otherwise use BLE if a paired master
is in range. The existing `SwitchRepository`, session, and state
providers are re-pointed at `activeTransportProvider` so **no UI
changes** are needed for control.

`tokenProvider` stays exactly as is — the token is shared, so switching
transport mid-session needs no re-login (matches the firmware's whole
premise).

**Why an interface, not a flag:** the two transports have genuinely
different plumbing (HTTP status codes vs silent-timeout, `ch` param vs
channel-suffixed id, WS vs GATT notify). An interface keeps that
divergence in two small adapters instead of scattering `if (ble)` across
the app.

---

## 4. Framing codec — `core/ble/ble_framing.dart`

Pure Dart, the most testable piece.

- `List<List<int>> encode(List<int> payload)` → chunks of
  `[index, total, ...≤160 bytes]`.
- A `ChunkReassembler` that accepts chunks, validates order, and yields
  a complete payload at `index == total-1`; resets/raises on
  out-of-order or index/total mismatch.
- JSON helpers: `encodeCommand(Map)` → UTF-8 → chunks;
  `String? decodePayload(List<int>)`.

**Tests:** single-chunk `00 01` round-trip, multi-chunk split at 160,
reassembly in order, rejection of out-of-order/duplicate/oversized,
a >MTU state document round-trip. All hardware-free.

---

## 5. Advertising parser — `core/ble/advert.dart`

Pure Dart.

- `MasterAdvert? parseManufacturerData(Uint8List)` → `{ meshId (int,
  big-endian), inMesh, provisioned, clientConnected }`, or null if the
  company id / format byte don't match (so foreign beacons are ignored).
- `MasterBeacon` = advert + `deviceId` + `rssi` + `name`, produced from
  a scan result.

**Tests:** correct mesh-id endianness, each flag bit, standalone
`0000`, rejection of non-Unisync manufacturer data. Hardware-free.

---

## 6. Mesh-id store + pairing — `core/storage/*`

- Extend the saved-master record with its **mesh id** (and standalone
  flag). Captured at first pairing (onboarding, or first BLE connect).
- Scans then filter to beacons whose mesh id matches a saved master —
  "ignore the neighbour's system".
- A standalone master (`meshId == 0`) pairs to that specific device id.

---

## 7. BLE control client — `core/ble/ble_control_client.dart`

Built on `flutter_reactive_ble` (already a dependency, already
permission-gated by `ensureBlePermissions`). One client bound to one
connected master:

- Connect (reuse the recovery service UUID `…31`); request a larger MTU
  but tolerate refusal (framing handles it).
- Subscribe to **control response `…36`** and **state push `…37`**; feed
  both through their own `ChunkReassembler`.
- `Future<Map> request(Map command, {timeout})`: chunk-write to
  **request `…35`**, await the next reassembled response, **time out**
  on silence (spec: no reply on error). Map `{"err": …}` bodies to a
  typed `BleCommandError`.
- Expose `stateStream` from the `…37` reassembler as `StateSnapshot`.
- Command builders match the spec exactly: `login {c,p}`,
  `relay {t,c,id,s}` (id already carries the channel suffix, **no `ch`**),
  `killall {t,c}`, `exts {t,c}`, `mesh {t,c}`, `state {t,c}`.

**Tests:** command JSON shape per spec, response parsing, timeout on
silence, `{"err"}` → typed error. The GATT layer is mocked behind a thin
seam so these stay hardware-free; a real round-trip is a device smoke
test.

---

## 8. Roaming controller — `core/ble/roaming.dart`

Pure decision logic, fully unit-testable; the radio calls are injected.

- While connected, keep a **background scan** running; maintain a
  rolling RSSI per beacon of the same mesh id.
- A `RoamPolicy.shouldHop(current, candidate, history)` that returns a
  target only when the candidate is **≥10 dB stronger for ~5 s
  sustained** (time-windowed, not instantaneous), preferring beacons
  with **flag bit 2 clear**.
- On hop: disconnect, connect to the target, **re-subscribe** `…36`/`…37`,
  and **reuse the existing token** (no login). Surface nothing to the
  user — hopping must be invisible.

**Tests:** no hop under 10 dB; no hop on a brief spike (< the dwell
window); hop when sustained; tie-break toward the unoccupied master;
no oscillation across a synthetic walk. Pure logic → fully covered
without hardware.

---

## 9. Fallback UX — Wi-Fi-only features

When the active transport is BLE and the user taps a Wi-Fi-only action
(OTA, mesh create/join/leave, password change, switch rename/reorder/
assign, audit), show a **"Join the switch's Wi-Fi to do this"** sheet
with a one-tap route into the existing Add-a-switch/join flow, instead
of failing. A small `requiresWifi` guard on those actions, driven by
`activeTransportProvider.kind`.

---

## 10. Build sequence

Each block is its own PR; the app builds and tests stay green after
each. Blocks 1–5 are pure Dart and land with full unit coverage before
any device work.

1. **Framing codec** (§4) + tests.
2. **Advertising parser** (§5) + tests.
3. **Mesh-id store & pairing capture** (§6) + tests.
4. **Roaming policy** (§8, pure logic) + tests.
5. **Transport interface + `HttpTransport`** (§3) — adapt existing
   repos/state behind `ControlTransport`; re-point providers; no UI
   change; existing tests still green.
6. **BLE control client** (§7) — connect, framed request/response,
   state-push stream; mocked-GATT tests.
7. **`BleTransport`** implementing `ControlTransport` over the client;
   `activeTransportProvider` reachability selection.
8. **Roaming controller** wiring (§8) — background scan + hop execution.
9. **Fallback UX** (§9) for Wi-Fi-only features.
10. **Onboarding/pairing** — capture mesh id; BLE-first "add a switch"
    path when Wi-Fi isn't desired.
11. **Dashboard polish** — a transport indicator (Wi-Fi vs BLE) in the
    header status pill, so the user can see how they're connected.

---

## 11. Testing strategy

The high-value logic is pure Dart and tested without hardware: framing,
manufacturer-data parsing, roaming hysteresis, command JSON, response/
error mapping, transport selection. The GATT boundary is mocked behind
a seam.

**Requires hardware (documented in `RELEASE.md`):** a real BLE
connect + login + relay round-trip; state push from a wall-switch
toggle; a two-master roam with the ≥10 dB/5 s policy; the silent-
timeout path; and that a token issued by master A is accepted by B
after a hop (no login prompt).

---

## 12. Risks / decisions

- **iOS background scanning** is restricted; continuous roam-scanning
  works foreground. Backgrounded control is a later question (would need
  state-restoration + background BLE modes, which the plan currently
  avoids per PLAN.md §8). BLE control is a foreground feature for now.
- **Battery:** continuous scan-while-connected costs power. Use
  low-latency scan only while the control screen is foregrounded; drop
  to a slower cadence or stop when backgrounded.
- **Transport thrash:** if both Wi-Fi and BLE are available, prefer
  Wi-Fi and don't flip-flop — pick on screen entry, re-evaluate only on
  a connectivity change, not per command.
- **Reused recovery UUIDs:** the control service is the same `…31`
  service recovery already uses; the client must not disturb the
  logged-out recovery flow. Keep them as separate connections/sessions.

---

## 13. Open questions for the team

1. **MTU floor:** the spec says don't assume the requested MTU is
   granted. Is there a guaranteed minimum (23?) we should size the
   160-byte chunk assumption against, or can chunk size adapt to the
   negotiated MTU?
2. **Scan cadence vs battery:** acceptable background behaviour — stop
   scanning entirely when backgrounded, or a slow keep-alive?
3. **Standalone roaming:** roaming is mesh-only (shared id). Confirm a
   standalone master never participates in hop logic.
4. **Transport preference override:** should the user be able to force
   BLE even when Wi-Fi is reachable (e.g. to stay on home internet),
   or is "Wi-Fi when present" always right?

---

_Document owner: engineering. Update this file when the plan shifts;
each change is a PR reviewed like code._
