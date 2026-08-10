# Unisync Firmware — Changelog for the App

**Current: master v11.19.0**, extension v1.2.0, bootloader v4.0.
Everything below is app-visible. Ordered newest first; §"Action required"
at the end lists what the app must change.

---

## v11.19.0 — Activity log coverage

**21 events are now recorded**, up from 10, and the same set on Wi-Fi and
BLE so the log no longer depends on how you were connected.

Added: renames (switch, extension, master, mesh), reorder, add / reject /
replace a switch, firmware updates, mesh join, mesh password change.

**Individual relay toggles are deliberately not logged.** The ring holds
24 entries; normal switch use would evict every sign-in and configuration
event within a minute. If you want switch history, build it in the app
from the state pushes you already receive — you get real timestamps and
unlimited depth that way.

Event strings are now written for display: *"Signed in"*, *"Turned all
switches off"*, *"Recovered the password over Bluetooth"*. Render them
as-is; do not map or reformat them.

---

## v11.18.1 — Activity log response size

The audit response was built in a fixed 2 KB buffer and **silently
dropped entries** when it overflowed — the app received a short list with
no error. Now built on the heap with overflow detection.

If you saw fewer events than expected before this build, that was why.

---

## v11.18.0 — Renames over BLE

Three commands that did not exist. "Master unreachable" on rename was the
app calling something that was never implemented.

```json
{ "t":"…", "c":"rename_ext",    "slot":0, "name":"Bedroom" }
{ "t":"…", "c":"rename_sw",     "id":"ext0_1", "name":"Reading Light" }
{ "t":"…", "c":"rename_master", "name":"Hall" }
```

All reply `{"ok":true}` or `{"err":"…"}`, persist to NVS, and push state.

---

## v11.17.1 — Connection policy

- **Authenticated clients are never disconnected.** A phone left idle is
  normal.
- **One unproven client at a time.** A second anonymous connection is
  refused immediately, so a squatter cannot lock the owner out.
- **Unauthenticated clients are dropped after 15 s.** Log in promptly
  after connecting.
- Up to **3 concurrent connections**, so two phones can both use BLE.

Practical effect: connect, then `login` within 15 seconds or you will be
disconnected.

---

## v11.17.0 — Advertising continues while connected

Previously a single connection stopped advertising entirely, making the
master invisible to every other phone. It now keeps advertising while
slots remain free — required for roaming to work at all.

---

## v11.16.0 — Reorder, activity log, firmware info over BLE

New commands: `reorder`, `audit`, `fwlist`.

`exts` now returns the same fields as `GET /api/extensions`: added
`name`, `sw1`, `sw2`, `rev`, `fails`, `stuck`, `avail`.

**`avail` reflects only what is already staged on that master.** An image
the app has downloaded but not yet uploaded is invisible to it. Decide
"update available" by comparing your own manifest against `fw`, and use
`fwlist` to see whether an upload is still needed.

---

## v11.15.3 — State pushes were being dropped

Rate limiting **discarded** a state push that arrived within the window
instead of deferring it. The app then showed stale state until some later
change happened to fall outside a window.

This was the cause of "sometimes not realtime". Now deferred, floor
150 ms, never dropped.

---

## v11.15.2 — BLE writes were being discarded

`getValue()` was read through a type conversion that returned an empty
buffer, so every request the app sent was thrown away. Nothing in the log
said so.

Also: connection interval reduced to 15–30 ms, and chunk pacing cut from
12 ms to 4 ms and applied only to multi-chunk replies.

If BLE control never worked before this build, this is why.

---

## v11.15.1 — Request framing accepts both forms

A payload starting with `{` is treated as one unframed JSON message.
Anything else is parsed as `[index][total][payload]`.

Previously unframed JSON was misread as a chunk header and silently
discarded. Send whichever suits you; unframed is simpler under ~180 bytes.

Full logging was added through the BLE path — every write, parse failure,
command, token check and relay result now appears on serial.

---

## v11.15.0 — Discovery data for roaming

Advertising now carries 6 bytes of manufacturer data:

| Byte | Meaning |
|---|---|
| 0–1 | company id `FF FF`, little endian |
| 2 | format version `0x01` |
| 3–4 | **mesh id**, big endian, `0000` = standalone |
| 5 | flags: bit0 in a mesh, bit1 provisioned, bit2 client connected |

**Filter scans on manufacturer data, not the device name.** Names are
per-device (`U{UID}`), so name filtering needs every UID known in
advance. The mesh id is identical across a mesh and stable through
renames, password changes and reboots — store it at pairing and ignore
masters advertising a different one.

---

## v11.14.1 — Advertising fixed

The advertising packet was 32 bytes against a 31-byte limit, so nothing
was advertised at all and the master was undiscoverable. The service UUID
moved to the scan response.

---

## v11.14.0 — Web UI removed, BLE control added

The served pages are gone. The app is the only client; all 32 endpoints
return JSON.

BLE became a full control transport, not just recovery. Firmware
**transfer** stays on Wi-Fi.

---

## v11.13.x — BLE recovery

Recovery service for a lost password. Must be reachable while **logged
out** — put it on the login screen, not in settings.

---

## v11.12.0 — One credential, roaming sessions

**One password per mode.** Standalone: the card password joins the Wi-Fi
*and* logs in. In a mesh: the mesh password does both. There is no
separate account password.

**Tokens are stateless and never expire.** A token issued by one master
is accepted by every master in the mesh, over either transport. Survives
reboots. Revoked only by changing the password.

**Never re-authenticate on a roam or a transport switch.** A login prompt
while the user walks between rooms means something is wrong.

**Password change replies before the Wi-Fi restarts** (~400 ms), so you
get a definite answer. Sequence: await the reply → expect the drop →
rejoin with the new password → log in again.

---

# Action required in the app

| # | Change | Why |
|---|---|---|
| 1 | Filter scans on manufacturer data, store the mesh id | names are per-device |
| 2 | `login` within 15 s of connecting | unproven clients are dropped |
| 3 | Never re-authenticate on roam or transport switch | the token is already valid |
| 4 | Use `killall`, never a loop of `relay` | ten commands means ten state pushes |
| 5 | "Update available" from your own manifest, not `avail` | the master cannot see your cache |
| 6 | Treat state pushes as full snapshots | they are not deltas |
| 7 | Render audit strings as-is | already written for display |
| 8 | Time out silent requests | malformed requests get no reply |
| 9 | Keep recovery reachable while logged out | its users have no credentials |
| 10 | Expect ~350 ms for physical switch presses | 200 ms poll + 150 ms push |

---

# Known limits

| Limit | Value |
|---|---|
| Activity log | 24 entries, RAM only, cleared on reboot |
| Activity timestamps | seconds since boot, not wall-clock — no RTC |
| Extensions per master | 5 |
| Masters per mesh | 16 |
| Concurrent BLE clients | 3 |
| BLE request size | 512 bytes assembled |
| Firmware transfer over BLE | not supported, by design |

---

# Not yet done

- **BLE login sends the password in clear** and has no lockout. Challenge
  –response is designed but not built. Do not treat BLE as a private
  channel yet.
- Wi-Fi-only: firmware transfer, mesh create/join/leave, password change,
  provisioning, switch assignment.
