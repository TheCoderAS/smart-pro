# Unisync — API Reference

**Version 1.0** — master firmware v11.13.2
For the Flutter client. Every example is a working `curl` you can run today.

The master is an access point at **`192.168.4.1`**. There is no internet
path to it; the phone must be joined to the device's Wi-Fi. All responses
are JSON. There is no HTML the client needs.

---

## 1. The credential model

**One password does two jobs**: it joins the Wi-Fi *and* logs in to the
API. There is no separate account.

| Mode | Password |
|---|---|
| Standalone | the device password, on the card in the box |
| In a mesh | the mesh password, shared by every master |

A master in a mesh ignores its own device password entirely. Leaving the
mesh restores it.

**Implication for the app:** if the user can reach `192.168.4.1` at all,
they already know the password. Logging in is a formality, not a second
factor — but it is still required, because the token is what authorises
every subsequent call.

---

## 2. Authentication

### Log in

```bash
curl -X POST "http://192.168.4.1/api/login" -d "password=a1b2c3d4e5f6"
```

```json
{ "token": "3f2a...c81d", "mesh": true }
```

`token` is 32 hex characters. `mesh` tells you which password was
accepted, which is useful for the UI wording.

### Use the token

Send it as a header on every subsequent request:

```bash
curl "http://192.168.4.1/api/extensions" -H "X-Auth: $TOKEN"
```

A query parameter `?t=<token>` also works, and is required for the
WebSocket, which cannot send headers.

### Properties you can rely on

- **No expiry.** A token stays valid until the password changes.
- **Survives reboots.** Tokens are not stored on the master; they are
  verified arithmetically.
- **Works on every master in a mesh.** A token issued by master A is
  accepted by master B. This matters more than it sounds — see §3.
- **Revocation is a password change**, which invalidates every token
  everywhere at once.

### Log out

```bash
curl -X POST "http://192.168.4.1/api/logout"
```

Does nothing server side. Discard the token locally. Present it in the UI
as "sign out"; present a password change as "sign out all devices".

### Failures

| Code | Meaning | What the app should do |
|---|---|---|
| 401 | no or invalid token | prompt for the password, retry once |
| 423 | locked out, 5 wrong passwords | show remaining time, ~5 minutes |
| 429 | rate limited, 40 requests / 10 s | back off, retry |

---

## 3. Roaming — read this before designing the network layer

Every master in a mesh serves **the same SSID and the same IP**,
`192.168.4.1`. As the user moves through the house the phone silently
re-associates to whichever master is strongest. **The app is not told, and
the IP does not change.**

You cannot detect this from the socket. What you can rely on:

- The token still works — it is validated by any master in the mesh.
- The state you receive may jump, because you are now talking to a
  different master with different local switches.
- A WebSocket will drop and reconnect on re-association.

So: reconnect the WebSocket automatically, treat every state push as
authoritative and complete rather than incremental, and never cache
"which master am I talking to".

---

## 4. Live state — WebSocket

```
ws://192.168.4.1:81/ws?t=<token>
```

Port **81**, not 80. The token must be in the query string; a WebSocket
handshake cannot carry the `X-Auth` header. Without a valid token the
master closes the connection immediately.

Pushes a full state document on connect and on every change. Top-level
fields include `master_name`, `uptime`, `boot_complete`, `scan_active`,
plus the switch and peer arrays.

Treat every message as a complete replacement of local state.

---

## 5. Endpoints

`OPEN` needs nothing. `TOKEN` needs `X-Auth`.

### Device

| Method | Path | Auth | Parameters |
|---|---|---|---|
| GET | `/api/info` | OPEN | — |
| POST | `/api/login` | OPEN | `password` |
| POST | `/api/logout` | OPEN | — |
| POST | `/api/password` | TOKEN | `password` |
| POST | `/api/master/rename` | TOKEN | `name` |
| GET | `/api/audit` | TOKEN | — |
| POST | `/api/scan` | TOKEN | — |

`/api/info` is deliberately open — call it before login to learn the
firmware version and confirm the device is reachable.

```bash
curl "http://192.168.4.1/api/info"
```

```json
{ "uptime": 3812, "free_heap": 184320, "uid": "C5F77720",
  "fw": "11.13.2", "auth": true }
```

### Switches

| Method | Path | Auth | Parameters |
|---|---|---|---|
| POST | `/api/relay` | TOKEN | `id`, `state`, `ch` |
| POST | `/api/relay/killall` | TOKEN | — |
| POST | `/api/switch/rename` | TOKEN | `id`, `name` |
| POST | `/api/switch/reorder` | TOKEN | `plain` |

```bash
curl -X POST "http://192.168.4.1/api/relay" -H "X-Auth: $TOKEN" \
     -d "id=ext0_1" -d "state=1"
```

### Extensions

| Method | Path | Auth | Parameters |
|---|---|---|---|
| GET | `/api/extensions` | TOKEN | — |
| POST | `/api/assign` | TOKEN | `uid`, `name` |
| POST | `/api/reject` | TOKEN | `uid` |
| POST | `/api/replace` | TOKEN | `uid`, `slot`, `name` |
| POST | `/api/rename` | TOKEN | `slot`, `name` |
| POST | `/api/remove` | TOKEN | `slot` |

```json
{ "extensions": [
  { "slot": 0, "addr": 1, "online": true, "type": 1, "rev": 1,
    "fw": "1.2.0", "name": "Slot 1", "sw1": "Living Room",
    "sw2": "Kitchen", "fails": 0, "stuck": false, "avail": "1.2.1" }
]}
```

`avail` appears only when a newer image is waiting; `stuck` means three
failed attempts and the master has given up.

### Mesh

| Method | Path | Auth | Parameters |
|---|---|---|---|
| GET | `/api/mesh/status` | TOKEN | — |
| POST | `/api/mesh/create` | TOKEN | `name` |
| POST | `/api/mesh/invite` | TOKEN | — |
| POST | `/api/mesh/join` | TOKEN | `mac`, `pin` |
| POST | `/api/mesh/leave` | TOKEN | — |
| POST | `/api/mesh/rename` | TOKEN | `name` |
| POST | `/api/mesh/passwd` | TOKEN | `old`, `pass`, `name` |
| POST | `/api/mesh/relay` | TOKEN | `peer_uid`, `sw_id`, `ch` |
| POST | `/api/mesh/config` | TOKEN | `cmd`, `target_uid`, … |

```json
{ "active": true, "mesh_name": "My House", "peer_count": 2,
  "fw": "11.13.2", "syncing": false, "cred_stale": false,
  "peers": [ { "name": "Bro Room", "fw": "11.13.2" } ] }
```

`cred_stale: true` means this master missed a password change while
offline. It cannot self-heal — surface it as **"remove and re-add this
master"**.

### Firmware

| Method | Path | Auth | Parameters |
|---|---|---|---|
| GET | `/api/fw/list` | TOKEN | — |
| POST | `/api/fw/upload` | TOKEN | multipart + `sig`, `sec`, `mesh` |
| POST | `/api/ota/master` | TOKEN | multipart |
| POST | `/api/ota/extension` | TOKEN | multipart + `addr` |
| GET | `/api/ota/image` | mesh key | `k` |
| POST | `/api/provision` | OPEN until set | `root`, `fw` |

`/api/ota/image` is master-to-master only; the app never calls it.

---

## 6. Changing the password

This is the one call with unusual mechanics.

```bash
curl -X POST "http://192.168.4.1/api/password" -H "X-Auth: $TOKEN" \
     -d "password=newpassword123"
```

```json
{ "ok": true, "scope": "mesh", "note": "reconnect with the new password" }
```

**The reply is sent first, then the Wi-Fi restarts about 400 ms later.**
That ordering is deliberate: the app gets a definite answer instead of
inferring success from a dropped socket.

What the app must do:

1. Send the request and **wait for the reply**
2. On `200`, show "password changed, reconnecting…"
3. Expect the Wi-Fi to drop
4. Rejoin with the **new** password
5. Log in again — the old token is dead

`scope` is `"mesh"` or `"device"`; use it to tell the user whether they
just changed the password for one master or the whole house.

Minimum 8 characters. In a mesh, every master takes the change.

---

## 7. Firmware updates

**Extension images must be signed.** The signature is produced offline
with the firmware key; neither the master nor the app can generate it. The
CDN therefore does not need to be trusted — a tampered image is rejected.

Serve a manifest alongside each image:

```json
{ "type": 1, "version": "1.2.1", "sec": 0, "size": 9456,
  "sig": "4d6da99f…", "url": "https://cdn/…/ext_t1_1.2.1.bin" }
```

The app downloads both and relays them unchanged:

```bash
curl -F "firmware=@ext_t1_1.2.1.bin" \
     -F "sig=4d6da99f…" -F "sec=0" \
     -H "X-Auth: $TOKEN" \
     "http://192.168.4.1/api/fw/upload?mesh=1"
```

`?mesh=1` also offers the image to peer masters. After that it is
automatic: each master updates matching switches within 30 seconds, one at
a time, roughly 5 seconds each. Poll `/api/extensions` and watch `fw`.

**Master images are different.** They are not signature-checked in
firmware; authenticity comes from secure boot at the next boot. So a
master update can return `200`, reboot, and come back on the **old**
version if the image was bad. Always confirm with `/api/info` after the
reboot rather than trusting the upload response.

Masters also update each other over the mesh, so the app normally only
needs to push to one.

### Upload errors

| Response | Cause |
|---|---|
| `{"error":"missing signature"}` | no `sig` field |
| `{"error":"not a Unisync extension image"}` | wrong file |
| `{"error":"image not in signed library"}` | forced push of an unsigned image |
| 500, log shows `signature INVALID` | wrong key or altered image |

---

## 8. BLE recovery

Used when the password is lost. The API cannot help — it is behind the
Wi-Fi the user cannot join — so this is BLE only, and it must be reachable
from a **logged-out** app. Put it on the login screen, not in settings.

Advertised name is the model number printed on the device, `U{UID}`,
for example `UC5F77720`.

| Purpose | UUID |
|---|---|
| Service | `556e6973-796e-6320-5265-636f76657231` |
| Challenge (read) | `556e6973-796e-6320-5265-636f76657232` |
| Response (write) | `556e6973-796e-6320-5265-636f76657233` |
| Result (read/notify) | `556e6973-796e-6320-5265-636f76657234` |

Flow:

1. Scan for `U{UID}`, connect
2. **Read** the challenge — 8 bytes, new on every connection
3. Ask the user for the recovery key from the card, 32 hex characters
4. **Write** `HMAC-SHA256(recovery_key, challenge)` truncated to 8 bytes
5. **Read or await notify** on Result — the new password, as ASCII

```dart
// step 4
final mac = Hmac(sha256, hexToBytes(recoveryKey)).convert(challenge).bytes;
await responseChar.write(mac.sublist(0, 8));
```

Standalone recovery returns the password printed on the card. Mesh
recovery generates a new mesh password and pushes it to every master, so
**one master recovers the whole house**.

A wrong key produces **no response at all** — silence is the failure
signal, so use a timeout. Five failures lock the service for 15 minutes.

BLE permissions are required on both platforms, and iOS needs a usage
description in `Info.plist`.

---

## 9. Client checklist

- Store the token in secure storage; there is no expiry to manage
- Reconnect the WebSocket automatically and treat state as full snapshots
- Never cache which master you are talking to
- On 401, prompt for the password once and retry
- On 429, back off
- After a password change: expect the drop, rejoin, re-login
- Confirm master updates via `/api/info`, not the upload response
- Surface `cred_stale` as an action the user must take
- Recovery must work while logged out
