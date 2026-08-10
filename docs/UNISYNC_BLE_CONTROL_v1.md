# Unisync — BLE Control: what changed and how to use it
**For the Flutter client. Firmware v11.15.0.**

Supplements the API reference; nothing there is invalidated.

---

## Why this exists

A phone joined to the master's Wi-Fi has no internet unless it also has
cellular. A user on home Wi-Fi for internet would otherwise have to leave
that network to control their switches, and rejoin afterwards.

BLE is the second way in. The phone stays on whatever network it likes and
talks to the **nearest master** over BLE.

**BLE carries control and recovery only.** Firmware upload stays on Wi-Fi
— 1.4 MB over BLE is hours, and the Wi-Fi path already works.

---

## Discovery

Every master advertises continuously, whether or not a client is
connected, so the app can always find the nearest one.

**Advertising packet**

| Field | Value |
|---|---|
| Name | `U{UID}`, e.g. `UC5F77720` — matches the model on the device |
| Manufacturer data | 6 bytes, below |

**Manufacturer data**

| Byte | Meaning |
|---|---|
| 0–1 | company id, `FF FF` little endian |
| 2 | format version, currently `0x01` |
| 3–4 | **mesh id**, big endian. `0000` = standalone |
| 5 | flags |

**Flags**

| Bit | Meaning |
|---|---|
| 0 | in a mesh |
| 1 | provisioned with product keys |
| 2 | a client is already connected |

**Scan response** carries the service UUID
`556e6973-796e-6320-5265-636f76657231`.

Filter on the manufacturer data, not the name — names are per-device, so
filtering by name would need every UID known in advance.

### Mesh id

Derived from the mesh's internal key. It is:

- **identical on every master in a mesh**
- **stable** across renames, password changes and reboots
- **`0000`** on a standalone master

Store it when the user first pairs. Afterwards, connect only to masters
advertising that id — that is what stops the app latching onto a
neighbour's system.

---

## Roaming

**The firmware cannot move a client.** Hopping is the app's job, and the
firmware provides what you need to do it: every master advertises the same
mesh id, and a token issued by one is accepted by all.

Suggested behaviour:

1. Scan continuously in the background while connected
2. Track RSSI per master
3. If another master is stronger by **≥ 10 dB sustained for ~5 s**,
   disconnect and reconnect there
4. Re-subscribe to notifications; **do not re-authenticate**

The 10 dB margin and the delay matter. Without hysteresis the app will
oscillate between two masters at the midpoint of a house.

**No re-login on hop.** Tokens are stateless and validated arithmetically
from the shared credential, so master B accepts a token issued by master
A. This is the single most important property for the user experience —
they should never see a login prompt while walking around.

Prefer a master whose flag bit 2 is clear; one already serving a client
may refuse a second connection.

---

## Protocol

One service, `556e6973-796e-6320-5265-636f76657231`.

| Characteristic | UUID suffix | Type |
|---|---|---|
| Recovery challenge | `…32` | read |
| Recovery response | `…33` | write |
| Recovery result | `…34` | read, notify |
| **Control request** | `…35` | write |
| **Control response** | `…36` | notify |
| **State push** | `…37` | notify |

### Framing

Every message, both directions, is chunked:

```
[0] chunk index
[1] chunk total
[2..] payload
```

Reassemble in order; parse when `index == total - 1`. Payload is at most
160 bytes per chunk. A single-chunk request starts `00 01`.

Chunking is required because a state document exceeds the MTU. The master
requests a larger data length on connect, but the phone may refuse, so do
not assume it.

### Commands

Write JSON to the request characteristic; the reply arrives on the
response characteristic.

**Log in**
```json
{ "c": "login", "p": "<password>" }
```
```json
{ "token": "3f2a…c81d", "mesh": true }
```

The password is the same one that joins the Wi-Fi: the card password
standalone, the mesh password in a mesh. The token returned is the
**same token the HTTP API issues** — usable over either transport, on
every master.

**Switch a relay**
```json
{ "t": "<token>", "c": "relay", "id": "ext0_1", "s": true }
```
```json
{ "ok": true }
```
`id` must carry the channel suffix: `ext<slot>_<ch>` or `master_<ch>`.
Unlike the HTTP endpoint there is no separate `ch` parameter.

**All off**
```json
{ "t": "<token>", "c": "killall" }
```

**Extensions**
```json
{ "t": "<token>", "c": "exts" }
```
```json
{ "extensions": [ { "slot":0, "addr":1, "online":true,
                    "type":1, "fw":"1.2.5" } ] }
```

**Mesh status**
```json
{ "t": "<token>", "c": "mesh" }
```
```json
{ "active": true, "mesh_name": "My House",
  "fw": "11.15.0", "peer_count": 2 }
```

**Full state**
```json
{ "t": "<token>", "c": "state" }
```
Returns the same document the WebSocket pushes.

### Errors

```json
{ "err": "login required" }
{ "err": "bad password" }
{ "err": "unknown command" }
```

An unknown or malformed request produces **no reply at all**. Use a
timeout, not an error handler.

---

## State push

Subscribe to `…37`. The master pushes the same JSON the WebSocket sends,
whenever anything changes — a relay toggled from a wall switch, an
extension going offline, an update completing.

Same chunking. **Treat every push as a complete snapshot**, not a delta.

This is what makes the two transports interchangeable: the app's state
handling does not need to know which one is in use.

---

## Recovery

Unchanged, but note it now shares the service with control.

The recovery flow must work while **logged out** — the user reaching for
it cannot join the Wi-Fi. Put it on the login screen.

1. Read the challenge from `…32` — 8 bytes, new every connection
2. Ask for the recovery key from the card, 32 hex characters
3. Write `HMAC-SHA256(key, challenge)` truncated to 8 bytes to `…33`
4. Read or await notify on `…34` — the new password as ASCII

A wrong key produces **silence**, not an error. Five failures lock the
service for 15 minutes.

Standalone recovery restores the card password. Mesh recovery generates a
new mesh password and pushes it to every master — **one master recovers
the whole house**.

---

## What BLE cannot do

Fall back to Wi-Fi for these:

- firmware upload, master or extension
- mesh create, join, leave
- provisioning
- password change
- switch renaming, reordering, assignment
- audit log

If the app needs one of these while on BLE, prompt the user to join the
master's Wi-Fi.

---

## Checklist

- Filter scans by manufacturer data, never by device name
- Store the mesh id at pairing; ignore masters advertising a different one
- Require ≥ 10 dB and ~5 s before hopping
- Never re-authenticate on a hop — the token is already valid
- Prefer masters with flag bit 2 clear
- Reassemble chunks in order; treat state pushes as full snapshots
- Time out silent requests
- Keep recovery reachable while logged out
- Route OTA and configuration over Wi-Fi
