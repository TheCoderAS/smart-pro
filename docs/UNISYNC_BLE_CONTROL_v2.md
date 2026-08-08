# Unisync — BLE Contract for the App

**Version 2 — firmware v11.16.0.** Supersedes v1.

Nine commands, full state, recovery. Read §3 and §7 before writing code —
they are where the design differs from what you would assume.

---

## 1. Two transports, one model

| | Wi-Fi | BLE |
|---|---|---|
| Control, state, config | yes | yes |
| Firmware **transfer** | yes | **no** |
| Firmware **information** | yes | yes |
| Recovery | no | yes |

BLE exists so a phone that needs its Wi-Fi for internet can still control
switches. Everything except firmware transfer works on either.

**One token works on both transports and on every master in a mesh.** Log
in once. Switching transport or roaming needs no re-authentication.

---

## 2. Service and characteristics

Service `556e6973-796e-6320-5265-636f76657231`

| Purpose | UUID | Type |
|---|---|---|
| Recovery challenge | `…32` | read |
| Recovery response | `…33` | write |
| Recovery result | `…34` | read, notify |
| Control request | `…35` | write |
| Control response | `…36` | notify |
| State push | `…37` | notify |

Advertising name is `U{UID}`, matching the model number on the device.

### Manufacturer data

| Byte | Meaning |
|---|---|
| 0–1 | company id `FF FF`, little endian |
| 2 | format version, `0x01` |
| 3–4 | **mesh id**, big endian, `0000` = standalone |
| 5 | flags: bit0 in a mesh, bit1 provisioned, bit2 client connected |

**Filter scans on manufacturer data, never on name.** Names are
per-device, so name filtering needs every UID known in advance. The mesh
id is what distinguishes your house from the neighbour's — store it at
pairing and ignore masters advertising a different one.

---

## 3. Framing — the part that bit us

Every message, both directions, may be chunked:

```
[0] chunk index
[1] chunk total
[2..] payload, max 160 bytes
```

**Requests: both framings are accepted.** A payload starting with `{` is
treated as one unframed JSON message. Anything else is parsed as a chunked
frame. Send whichever is convenient; unframed is simpler for anything
under ~180 bytes.

**Responses and state pushes are always chunked.** Reassemble in order,
parse when `index == total - 1`. A full `exts` reply can reach 13 chunks.
Request limit is 512 bytes assembled.

---

## 4. Commands

Write JSON to `…35`; the reply arrives on `…36`.

### login
```json
{ "c": "login", "p": "<password>" }
```
```json
{ "token": "518e625b45fcd138cd9e06dc802384a6", "mesh": true }
```
The password is the one that joins the Wi-Fi: the card password
standalone, the mesh password in a mesh. `mesh` tells you which applied.

Every other command needs `"t": "<token>"`.

### relay
```json
{ "t": "…", "c": "relay", "id": "ext0_1", "s": true }
```
```json
{ "ok": true }
```
`id` **must** carry the channel suffix — `ext<slot>_<ch>` or
`master_<ch>`. There is no separate `ch` field on this transport.

### killall
```json
{ "t": "…", "c": "killall" }
```
Turns everything off in **one** call. Do not loop `relay` commands for
this — ten separate commands means ten state pushes and it feels broken.
There is no all-on equivalent by design.

### exts
```json
{ "t": "…", "c": "exts" }
```
```json
{ "extensions": [ {
  "slot": 0, "addr": 1, "online": true, "type": 1, "rev": 1,
  "name": "Slot 1", "sw1": "Living Room", "sw2": "Kitchen",
  "fw": "1.2.5", "fails": 0, "stuck": false, "avail": "1.2.6"
} ] }
```
Identical shape to `GET /api/extensions`. `avail` appears only when the
**master's own library** holds something newer — see §7. `stuck` means
three failed attempts and the master has stopped trying.

### reorder
```json
{ "t": "…", "c": "reorder", "order": "ext0_1,ext0_2,master_1" }
```
Comma-separated switch ids, same as the HTTP endpoint.

### audit
```json
{ "t": "…", "c": "audit" }
```
```json
{ "events": [ { "t": 3812, "what": "login ok" } ] }
```
`t` is seconds since the master booted, not wall-clock — masters have no
RTC. Render as relative time.

### fwlist
```json
{ "t": "…", "c": "fwlist" }
```
```json
{ "fs": true, "master": "11.16.0",
  "images": [ { "type": 1, "ver": "1.2.6", "size": 9456 } ] }
```
What is **already staged on this master**, plus its own version. See §7.

### mesh
```json
{ "t": "…", "c": "mesh" }
```
```json
{ "active": true, "mesh_name": "My House",
  "fw": "11.16.0", "peer_count": 2 }
```

### state
```json
{ "t": "…", "c": "state" }
```
Returns the same document the state characteristic pushes. Use it once on
connect; after that rely on the push.

### Errors
```json
{ "err": "login required" }
{ "err": "bad password" }
{ "err": "unknown command" }
{ "err": "empty order" }
```
A malformed or unparseable request produces **no reply at all**. Use a
timeout, not an error handler.

---

## 5. State push

Subscribe to `…37`. The master pushes the full state document whenever
anything changes — a relay toggled at the wall, an extension going
offline, an update completing.

**Treat every push as a complete snapshot, not a delta.**

Pushes are rate limited to one per 150 ms. The limit **defers**, it never
drops — a change during the window is sent as soon as the window ends.

Expected latency:

| Origin | Time to reach the app |
|---|---|
| App toggles a relay | ~15–30 ms to act, ≤150 ms for state |
| Physical wall switch | up to ~350 ms — 200 ms poll + 150 ms push |

The 200 ms is how often the master polls each extension. A physical press
cannot surface faster than that.

---

## 6. Roaming

Every master in a mesh advertises the same mesh id, and a token issued by
one is accepted by all. **Hopping is the app's job** — the firmware cannot
move a client.

1. Keep scanning while connected
2. Track RSSI per master
3. If another is stronger by **≥10 dB sustained ~5 s**, reconnect there
4. Re-subscribe to `…37`. **Do not re-authenticate.**

The margin and the delay matter — without hysteresis the app oscillates
between two masters in the middle of a house.

Prefer a master with flag bit 2 clear; one already serving a client may
refuse a second connection.

**A login prompt while the user walks between rooms means something is
wrong.** The token is already valid everywhere.

---

## 7. Firmware updates over BLE

The app downloads images over the internet and caches them. BLE shows
what is running and what is staged. **Transfer requires Wi-Fi.**

**The master does not know what the app has cached.** Its `avail` field
compares an extension's running version against its **own** library only.
An image you downloaded but have not uploaded is invisible to it.

So the app decides:

| Question | Source |
|---|---|
| What is running? | `exts` → `fw`, `mesh` → `fw` |
| What do I have cached? | your own store |
| What is already on the master? | `fwlist` → `images` |
| Is an update available? | **your manifest vs `fw`** — not `avail` |
| Is an upload still needed? | your cache vs `fwlist` |

Flow:

1. Fetch the CDN manifest over the internet, cache the image
2. Over BLE, read `exts` and `fwlist`
3. If your cached version beats `fw` and is not already in `fwlist`,
   show "update available"
4. When the user accepts, prompt: **switch to the master's Wi-Fi**
5. Upload over HTTP with `sig` and `sec` from the manifest
6. Back on BLE, poll `exts` to watch `fw` change

Do not show "up to date" based on `avail` — you will hide an update you
have already downloaded.

Changelog comes from your CDN manifest. The master stores none.

---

## 8. Recovery

Must work while **logged out** — the user reaching for it cannot join the
Wi-Fi. Put it on the login screen, not in settings.

1. Read `…32` — 8-byte challenge, new every connection
2. Ask for the recovery key from the card, 32 hex characters
3. Write `HMAC-SHA256(key, challenge)` truncated to 8 bytes to `…33`
4. Read or await notify on `…34` — the new password as ASCII

A wrong key produces **silence**, not an error. Five failures lock the
service for 15 minutes.

Standalone recovery returns the card password. Mesh recovery generates a
new mesh password and pushes it to every master — one master recovers the
whole house.

---

## 9. What BLE cannot do

Prompt the user to join the master's Wi-Fi for:

- firmware transfer, master or extension
- mesh create, join, leave
- password change
- key provisioning
- switch renaming and assignment

---

## 10. Checklist

- Filter on manufacturer data; store the mesh id at pairing
- Accept both request framings; always reassemble responses
- One token, both transports, every master — never re-authenticate on a hop
- Use `killall`, never a loop
- Treat state pushes as full snapshots
- Determine "update available" from your own manifest, not `avail`
- Time out silent requests
- Keep recovery reachable while logged out
- `audit` timestamps are uptime, not wall-clock
