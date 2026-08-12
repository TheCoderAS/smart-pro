# Unisync — Operations Guide

**Version 2.0 — FROZEN**
Applies to: bootloader v4.0, extension v1.2.0+, master v11.11.3+
Supersedes guide v1.3, which predates key provisioning and firmware signing.

Part A is the master. Part B is the extension. Part C is day-to-day
releases. They are independent; read the part you need.

---

## Part 0 — Once per session

```bash
BOARDS=~/.arduino15/packages/STMicroelectronics/hardware/stm32/2.12.0/boards.txt

ocd() {
  ~/.arduino15/packages/STMicroelectronics/tools/xpack-openocd/0.12.0-6/bin/openocd \
    -f interface/stlink.cfg -f target/stm32g0x.cfg -c "$1"
}
```

A function, not a variable. In zsh an unquoted variable is passed as one
argument, and OpenOCD fails with `Can't find interface/stlink.cfg -f ...`.

Check the programmer and power:

```bash
ocd "init; exit"
```

Expect `Cortex-M0+ r0p1 processor detected`. `open failed` means the
ST-Link is unplugged; `Target voltage: 0.0` means the board has no power.

---

## Part 0b — Your keys

Generate **once for the whole product line** and never lose them. Losing
the firmware key means you can never sign an update for any unit already
in the field.

```bash
python3 -c "import os;print('root',os.urandom(16).hex());print('fw  ',os.urandom(16).hex())"
```

- **root key** — every master holds it. Each extension gets
  `HMAC(root_key, its_uid)`, so the master derives any device's key from
  its UID and needs no database.
- **fw key** — signs firmware images. Stays on your build machine and on
  each device for verification. Never on a CDN or in the app.

---

# PART A — MASTER

## A1. Build settings

| Setting | Value |
|---|---|
| Board | ESP32C6 Dev Module (or your board's entry) |
| Partition Scheme | **Minimal SPIFFS (1.9MB APP with OTA / 190KB SPIFFS)** |

Without a partition scheme that includes SPIFFS the master prints
`[FW] filesystem mount FAILED` and cannot store firmware.

## A2. First flash

Normal Arduino upload over USB. On first boot it prints, **once**:

```
[AUTH] WiFi password for this master: 30e4b5610a83
[AUTH] no owner password set -- API open until one is set
[SEC] no root key -- extensions cannot pair until provisioned
```

**Record that Wi-Fi password on the device label.** It is never printed
again. It applies to the standalone access point; a master in a mesh
keeps the shared mesh password.

**There are two separate passwords and they are not related:**

| | Set by | Used for | Where it lives |
|---|---|---|---|
| Wi-Fi password | generated on first boot | joining the access point | device label |
| Owner password | chosen at commissioning | logging in to the API | NVS, salted hash |

`/api/password` sets the **owner** password and accepts any string of 8
characters or more. It does not check the Wi-Fi password, because you
already proved you know that by being on the network.

Ownership is therefore gated by physical access to the label. That is the
usual model for this class of device, but it has one consequence worth
knowing: **whoever sets the owner password first, owns the device.** If a
master is left powered and unclaimed on a network someone else can join,
they can claim it. Commission each master immediately after flashing.

## A3. Commission

Between flashing and setting a password the API is fully open. That is
deliberate — a factory-fresh unit must be reachable — but do not leave a
master unattended in that state.

```bash
M=192.168.4.1
curl -X POST "http://$M/api/provision" -d "root=<ROOT>" -d "fw=<FW>"
curl -X POST "http://$M/api/password"  -d "password=YourOwnerPassword"

TOKEN=$(curl -s -X POST "http://$M/api/login" -d "password=YourOwnerPassword" \
        | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
echo "$TOKEN"
```

Use the **same** root and fw keys on every master.

Confirm the API closed — this must return **401**:

```bash
curl -i -X POST "http://$M/api/relay" -d "id=ext0_1&state=1"
```

And that a token works — this must return **200**:

```bash
curl -i -X POST "http://$M/api/relay" -H "X-Auth: $TOKEN" -d "id=ext0_1&state=1"
```

## A4. Releasing a new master build

Flash **one** master over USB. The rest copy it from whichever neighbour
has the newest version and keep retrying until they all match.

1. Raise `MASTER_FW_VERSION` in the sketch
2. Flash one master
3. Watch the others:

```
[MFW] peer v11.11.4 rssi=-38, we run v11.11.3 -- pulling
[MFW] joined peer, gateway 192.168.4.1
[MFW] downloading 1377920 bytes
[MFW] mesh radio reinitialised
[MFW] access point restored: My House
[MFW] image applied -- restarting
```

and on the source: `[MFW] serving 1377920 bytes to 192.168.4.2`.

A master only pulls a version **higher** than its own, so forgetting to
bump is harmless.

**During a pull** the master drops its Wi-Fi for 30–60 s, so phones
connected to it disconnect and reconnect after the restart. Its switches
keep working throughout. Masters far from the one you flashed still
update: the version spreads neighbour by neighbour, so a master only
needs a good link to *some* already-updated master.

**Master images are not signature-checked in firmware.** They rely on
ESP32 secure boot, which refuses a bad image at the *next boot* rather
than at upload. A master update can therefore appear to succeed and then
silently not take effect.

## A5. Master tunables

| Setting | Default | Meaning |
|---|---|---|
| `MASTER_FW_VERSION` | `"11.11.3"` | this build's version |
| `MASTER_SYNC_MS` | `60000` | how often to look for a newer neighbour |
| `MASTER_PULL_BACKOFF` | `300000` | wait after a failed download |
| `MASTER_PULL_JITTER` | `20000` | random wait so masters do not all pull at once |
| `MASTER_PEER_COOLDOWN` | `600000` | avoid a neighbour that failed us |
| `MAX_MESH_MASTERS` | `16` | masters per mesh, ~700 bytes each |
| `MAX_EXTENSIONS` | `5` | switches per master |
| `RECONCILE_MS` | `30000` | how often to check switches for updates |
| `OTA_MAX_FAILS` | `3` | attempts per image before giving up |
| `OTA_BACKOFF_MS` | `120000` | wait between failed attempts |

A new firmware version resets the failure counter, so three failures
against one bad image do not lock a switch out of future updates.

---

# PART B — EXTENSION

## B1. Build settings

| Setting | Value |
|---|---|
| Board | Generic STM32G0 series → Generic G030F6Px |
| U(S)ART support | **Disabled** |
| Optimize | Smallest (-Os) with LTO |
| C Runtime Library | Newlib Nano |

`U(S)ART support: Disabled` saves about 6 KB. The firmware drives the
RS-485 bus with direct register access and does not use the Arduino
serial library. Set it to Enabled and the image no longer fits.

## B2. The one setting that changes between builds

| Building | Flash offset |
|---|---|
| Bootloader | `0x0` |
| Application | `0x1000` |

```bash
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x0/'    $BOARDS
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x1000/' $BOARDS
grep GenG0.build.flash_offset $BOARDS
```

**Close and reopen the Arduino IDE after changing it.** The IDE reads the
file once at startup. Skip this and it silently builds with the old
value; the board flashes, verifies, and does not run.

Produce a `.bin` with **Sketch → Export Compiled Binary**.

## B3. Preparing a new board

Three steps, in this order, once per physical board.

### Step 1 — Identity and keys

```bash
python3 shared/provision.py --uid <UID> --type 1 --rev 1 \
        --root <ROOT> --fw <FW> --out /tmp/prov.bin

ocd "program /tmp/prov.bin 0x08007000 verify reset exit"
```

- `--uid` is the STM32 device UID, 8 hex characters. **Read it over SWD
  before provisioning** — the master cannot tell you, because a board has
  to be provisioned before it can pair and be logged:

  ```bash
  ocd "init; reset halt; dump_image /tmp/uid.bin 0x1FFF7598 4; exit"
  python3 -c "import struct;print('%08X'%struct.unpack('<I',open('/tmp/uid.bin','rb').read())[0])"
  ```

  This works on a completely blank board; no firmware needs to be flashed
  first. `0x1FFF7598` is the third word of the chip's 96-bit unique ID,
  which is exactly what the firmware reads at run time.

  Use `dump_image`, not `mdw`. `mdw` prints through OpenOCD's command
  console and the output is frequently lost when `exit` runs, leaving you
  with a halt message and no value.

  On a production jig, read the UID and build the blob in one step:

  ```bash
  ocd "init; reset halt; dump_image /tmp/uid.bin 0x1FFF7598 4; exit" >/dev/null 2>&1
  UID=$(python3 -c "import struct;print('%08X'%struct.unpack('<I',open('/tmp/uid.bin','rb').read())[0])")
  echo "board UID: $UID"
  python3 shared/provision.py --uid $UID --type 1 --rev 1 \
          --root <ROOT> --fw <FW> --out /tmp/prov.bin
  ```
- `--type` is the device type. `1` = 2-relay switch. Images built for one
  type are refused by every other type.
- `--rev` is the board revision.

Provision **first**. A board with no identity fails closed and blinks
five times, which looks like a fault.

### Step 2 — Bootloader

Offset `0x0`, then:

```bash
ocd "program .../ext_bootloader.ino.bin 0x08000000 verify reset exit"
```

Must be under **4096** bytes.

### Step 3 — Application

Offset `0x1000`, then:

```bash
ocd "program .../extension_stm32.ino.bin 0x08001000 verify reset exit"
```

Must be under **12288** bytes.

### Step 4 — Confirm

On the master:

```
[SEC] Auth OK 20353838
[EXT] 0x01 type=1 rev=1 fw=v1.2.0
```

`Auth OK` proves the identity write, the derived key, and the bootloader
handover all work. `Auth FAIL` means the master's root key and the one
passed to `provision.py` differ.

## B4. Extension tunables

| Setting | Default | Meaning |
|---|---|---|
| `FW_VER_MAJOR/MINOR/PATCH` | `1.2.0` | this build's version |
| `FW_TARGET_TYPE` | `0x01` | device type this build is for |
| `ORPHAN_TIMEOUT_MS` | `30000` | time without contact before unpairing |

---

# PART C — RELEASING EXTENSION FIRMWARE

No cables. One upload reaches every matching switch on every master.

## C1. Version and build

Raise `FW_VER_PATCH`. A switch only installs a version **higher** than it
is running, so forgetting is harmless.

Build at offset `0x1000`, export the binary, then confirm the descriptor
survived the compiler:

```bash
strings .../extension_stm32.ino.bin | grep UNISYNC1
```

Nothing printed means the descriptor was optimised out and the master
will reject the upload. Check `FW_DESC` is present and marked
`__attribute__((used)) const volatile`.

## C2. Sign

```bash
python3 shared/sign_firmware.py .../extension_stm32.ino.bin \
        --key <FW> --sec 0
```

It prints the type and version read from the image, and the signature.

**`--sec` is the security version**, separate from the firmware version.
Each device stores a floor and refuses anything below it. Leave it at `0`
until you ship a build that must never be reinstallable — a security fix —
then raise it. **Raising it is permanent for every device that installs
that build**; older images will never install on those units again, and
only SWD can recover them.

## C3. Upload

```bash
curl -F "firmware=@.../extension_stm32.ino.bin" \
     -F "sig=<SIGNATURE>" -F "sec=0" \
     -H "X-Auth: $TOKEN" \
     "http://192.168.4.1/api/fw/upload?mesh=1"
```

`?mesh=1` also offers the image to every peer master.

**The web UI cannot upload extension firmware** — it does not send the
signature, and the master will answer `missing signature`. Use the API.

## C4. What happens next

Each master checks its switches every 30 s and updates any running an
older version, one at a time. About 5 s per switch.

```
[FW] stored type=1 v1.2.1 9456 bytes crc=0x833BD696
[FW] updating ext 0x01 type=1 v1.2.0 -> v1.2.1
[EXT-OTA] BEGIN ok
[EXT-OTA] 320/9456 bytes
...
[EXT-OTA] END ok -- extension rebooting
[EXT] 0x01 type=1 rev=1 fw=v1.2.1
```

The absence of `[SEC] Challenge sent` afterwards confirms pairing
survived the update.

An occasional `CHUNK n retry 1` is normal; the transfer recovers.

---

# PART D — WHEN SOMETHING IS WRONG

## D1. The extension's green light

| What you see | Meaning | Action |
|---|---|---|
| One long flash | normal start | none |
| Three quick flashes | installing an update | wait, it restarts itself |
| Five quick flashes | update refused, old firmware kept | see D2 |
| Fast flashing forever | no working firmware | redo Part B3 |
| Slow breathing | running, not paired | pair it |
| Slower breathing | running and paired | none |

## D2. OTA refusal codes

Shown as `[EXT-OTA] ACK error: 0xNN`.

| Code | Meaning |
|---|---|
| `0xFE` | malformed request |
| `0xFD` | board never provisioned — Part B3 Step 1 |
| `0xFC` | image built for a different device type |
| `0xFB` | image too large or zero length |
| `0xFA` | security version below the device's floor |
| `0xF9` | signature invalid or missing |

## D3. Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `missing signature` on upload | used the UI, or omitted `-F sig=` | Part C3 |
| `signature INVALID, image rejected` | wrong fw key, or image edited after signing | re-sign |
| `[SEC] Auth FAIL` | master root key ≠ provisioning root key | re-provision |
| `[SEC] no root key provisioned` | master not commissioned | Part A3 |
| Switch never appears | wrong build offset, or not provisioned | Part B2, then B3 |
| Update never starts | version not raised | Part C1 |
| `update failed 3x` | switch not responding | power cycle it |
| `[FW] filesystem mount FAILED` | wrong Partition Scheme | Part A1 |
| Board dead after bootloader flash | built at `0x1000` not `0x0` | Part B2 |
| Board dead after app flash | built at `0x0` not `0x1000` | Part B2 |
| UI shows login and never loads | no session | sign in with the owner password |
| Master never updates from a peer | older than 11.9.4 | flash it once over USB |

## D4. Inspecting a board

```bash
ocd "init; reset halt; mdb 0x08007000 64; exit"
```

| Byte | Meaning |
|---|---|
| 0 | `A5` paired, `5A` standalone, `FF` new |
| 1 | bus address |
| 8 | device type — `FF` means never provisioned |
| 9 | board revision |
| 11 | security version floor |
| 32–47 | firmware key |
| 48–63 | device key |

## D5. Recovering a board

A cable always works. This erases everything including the identity, so
start again from Part B3 Step 1.

```bash
ocd "init; reset halt; stm32g0x mass_erase 0; reset; exit"
```

---

# PART E — DO NOT CHANGE

Shared between the bootloader and the extension. The bootloader cannot be
updated remotely; if these disagree, every board needs a cable.

| Item | Value |
|---|---|
| Bootloader | `0x08000000`, 4 KB |
| Slot A, running firmware | `0x08001000`, 12 KB |
| Slot B, update staging | `0x08004000`, 12 KB |
| Settings (NVS) | `0x08007000`, 4 KB |
| Settings size | 64 bytes |
| Device type | byte 8 |
| Board revision | byte 9 |
| Security floor | byte 11 |
| Firmware key | bytes 32–47 |
| Device key | bytes 48–63 |

Sized in whole 2 KB erase pages: 2 + 6 + 6 + 2 = 16 pages = 32 KB. A slot
that is not a page multiple would corrupt its neighbour during a copy.

---

# PART F — PRODUCTION

Order matters. The last step is irreversible.

1. Provision identity and keys (B3.1)
2. Flash bootloader (B3.2)
3. Flash application (B3.3)
4. Functional test: pairing, both relays, both touch inputs
5. One full OTA cycle, to prove the bootloader copy works on this board
6. **Then** burn the protection fuses

| Fuse | Reversible | Purpose |
|---|---|---|
| STM32 WRP on bootloader pages | yes | bootloader cannot be replaced |
| STM32 RDP level 2 | **no** | firmware and keys unreadable |
| ESP32 secure boot v2 | **no** | only signed images boot |
| ESP32 flash encryption | **no** | root key unreadable |

**RDP level 2 blocks your own recovery.** A board with the wrong
`hw_type`, a bad bootloader or a marginal flash page becomes scrap, and
no returned unit can ever be analysed. Steps 4 and 5 exist to catch that
before the fuse is burned. Confirm your STM32G030 variant supports RDP 2;
some offer level 1 only.

**Flash encryption is not optional.** The root key is identical on every
master, so extracting it from one unencrypted unit yields every
extension's key in the field.

---

# PART G — QUICK REFERENCE

```bash
# session
BOARDS=~/.arduino15/packages/STMicroelectronics/hardware/stm32/2.12.0/boards.txt
ocd() { ~/.arduino15/packages/STMicroelectronics/tools/xpack-openocd/0.12.0-6/bin/openocd \
        -f interface/stlink.cfg -f target/stm32g0x.cfg -c "$1"; }

# build target -- restart the IDE after either
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x0/'    $BOARDS
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x1000/' $BOARDS

# new extension
python3 shared/provision.py --uid <UID> --type 1 --rev 1 --root <ROOT> --fw <FW> --out /tmp/prov.bin
ocd "program /tmp/prov.bin                 0x08007000 verify reset exit"
ocd "program .../ext_bootloader.ino.bin    0x08000000 verify reset exit"
ocd "program .../extension_stm32.ino.bin   0x08001000 verify reset exit"

# new master
#   flash over USB, record the printed WiFi password, then:
curl -X POST "http://192.168.4.1/api/provision" -d "root=<ROOT>" -d "fw=<FW>"
curl -X POST "http://192.168.4.1/api/password"  -d "password=<OWNER>"

# release extension firmware
python3 shared/sign_firmware.py <BIN> --key <FW> --sec 0
curl -F "firmware=@<BIN>" -F "sig=<SIG>" -F "sec=0" \
     -H "X-Auth: $TOKEN" "http://192.168.4.1/api/fw/upload?mesh=1"

# release master firmware
#   raise MASTER_FW_VERSION, flash ONE master over USB, the rest follow

# inspect / recover
ocd "init; reset halt; mdb 0x08007000 64; exit"
ocd "init; reset halt; stm32g0x mass_erase 0; reset; exit"
```
