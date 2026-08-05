# Unisync — Operations Guide

**Version 1.0 — FROZEN**
Applies to: bootloader v2.0, extension firmware v4.7+, master firmware v11.9.2+

Do not change the addresses in Part 6. Everything else is adjustable.

---

## Part 0 — Set these once

Paste into your terminal at the start of every session. Nothing else in this
guide will work without them.

```bash
BOARDS=~/.arduino15/packages/STMicroelectronics/hardware/stm32/2.12.0/boards.txt

ocd() {
  ~/.arduino15/packages/STMicroelectronics/tools/xpack-openocd/0.12.0-6/bin/openocd \
    -f interface/stlink.cfg -f target/stm32g0x.cfg -c "$1"
}
```

A function, not a variable. In zsh an unquoted variable is passed as one
argument instead of being split into separate options, so `$OCD $CFG ...`
fails with `Can't find interface/stlink.cfg -f target/stm32g0x.cfg`.

Check the ST-Link is connected and the board is powered:

```bash
ocd "init; exit"
```

You want to see `Cortex-M0+ r0p1 processor detected`.
If you see `Error: open failed`, the ST-Link is unplugged.
If you see `Target voltage: 0.0`, the board has no power.

---

## Part 1 — The one setting that changes between builds

Both the bootloader and the extension are built for the same chip, but they
live at different places in memory. One line in a settings file tells the
compiler which. You must set it correctly **before** each build.

| Building | Set to |
|---|---|
| Bootloader | `0x0` |
| Extension application | `0x1000` |

Set it to `0x0`:

```bash
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x0/' $BOARDS
```

Set it to `0x1000`:

```bash
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x1000/' $BOARDS
```

Check which one is active:

```bash
grep GenG0.build.flash_offset $BOARDS
```

**After changing this you must fully close and reopen the Arduino IDE.**
The IDE reads the file once at startup. If you skip this, it silently builds
with the old value and the board will not run.

---

## Part 2 — Arduino IDE settings

Identical for the bootloader and the extension:

| Setting | Value |
|---|---|
| Board | Generic STM32G0 series → Generic G030F6Px |
| U(S)ART support | **Disabled** |
| Optimize | Smallest (-Os) with LTO |
| C Runtime Library | Newlib Nano |
| Upload method | any — you will flash from the terminal |

`U(S)ART support: Disabled` saves about 6 KB. The firmware talks to the
RS-485 bus directly and does not use the Arduino serial library. If you
switch this to Enabled the extension will no longer fit.

For the master (ESP32) there is one extra setting:

| Setting | Value |
|---|---|
| Partition Scheme | **Minimal SPIFFS (1.9MB APP with OTA / 190KB SPIFFS)** |

Without a partition scheme that includes SPIFFS, the master prints
`[FW] filesystem mount FAILED` at boot and cannot store firmware images.

To produce a `.bin` file: **Sketch → Export Compiled Binary**.
The file appears in a `build` folder inside the sketch folder.

---

## Part 3 — Preparing a brand new board

Three steps, in this order. Do them once per physical board.

### Step 1 — Write the board's identity

This tells the board what kind of device it is. Without it the board will
refuse every update, by design.

```bash
python3 -c "b=bytearray(b'\xFF'*32); b[8]=0x01; b[9]=0x01; open('/tmp/prov.bin','wb').write(b)"
ocd "program /tmp/prov.bin 0x08006000 verify reset exit"
```

- `b[8]` is the **device type**. `0x01` = 2-relay switch. Change this number
  for a different product; images built for one type are refused by all others.
- `b[9]` is the **board revision**. Bump it when you change the PCB.

This survives everything — factory reset, unpairing, firmware updates.
You never repeat it unless you replace the chip.

### Step 2 — Flash the bootloader

```bash
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x0/' $BOARDS
```

Restart the IDE. Open the bootloader sketch. Export Compiled Binary. Then:

```bash
ocd "program /home/sams/smart-pro/hardware/firmware/ext_bootloader/build/STMicroelectronics.stm32.GenG0/ext_bootloader.ino.bin 0x08000000 verify reset exit"
```

You should see `** Verified OK **`.
The bootloader must be under 4096 bytes — the IDE prints the size after
compiling. It is normally around 2400.

### Step 3 — Flash the extension application

```bash
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x1000/' $BOARDS
```

Restart the IDE. Open the extension sketch. Export Compiled Binary. Then:

```bash
ocd "program /home/sams/smart-pro/hardware/firmware/extension_stm32/build/STMicroelectronics.stm32.GenG0/extension_stm32.ino.bin 0x08001000 verify reset exit"
```

The extension must be under 10240 bytes.

### Step 4 — Confirm it worked

Watch the master's serial output. Within about a minute you should see:

```
[EXT] 0x01 type=1 rev=1 fw=v1.0.0
[ONLINE] Switch
```

That one line proves the identity write, the bootloader, and the
application are all correct. If you do not see it, go to Part 7.

---

## Part 4 — Releasing a new extension firmware

This is the normal day-to-day flow. **No cables, no ST-Link.**

### Step 1 — Set the version number

Open the extension sketch. Near the top:

```c
#define FW_VER_MAJOR   1
#define FW_VER_MINOR   0
#define FW_VER_PATCH   0
```

Increase one of them. The rule the master follows is simple: it only
installs a version that is **higher** than what a board is already running.
Equal or lower is ignored. If you forget to increase it, nothing happens
and nothing breaks.

```c
#define FW_TARGET_TYPE 0x01
```

This must match `b[8]` from the identity write. Leave it at `0x01` unless
you are building for a different product.

### Step 2 — Build

Make sure the setting is `0x1000` (Part 1), restart the IDE if you changed
it, then **Sketch → Export Compiled Binary**.

Confirm the version marker made it into the file:

```bash
strings /home/sams/smart-pro/hardware/firmware/extension_stm32/build/STMicroelectronics.stm32.GenG0/extension_stm32.ino.bin | grep UNISYNC1
```

If this prints nothing, stop. The master will reject the upload. See Part 7.

### Step 3 — Upload through the web page

1. Connect to the master's WiFi network
2. Open `http://192.168.4.1`
3. Go to **Settings → Extension firmware**
4. Tap the box, choose your `.bin`
5. Leave **Share with all masters in the mesh** ticked
6. Tap **Add to firmware library**

The page confirms the type and version it read from the file.

### Step 4 — Wait

Every master checks its switches every 30 seconds and updates any that are
running an older version, one at a time. A single switch takes about 5
seconds. Nothing to click.

The **Extensions** card on the same page shows each switch, its version,
and whether an update is queued. It refreshes every 15 seconds.

---

## Part 5 — Things you can safely change

All in the master sketch, near the top.

| Setting | Default | Meaning |
|---|---|---|
| `RECONCILE_MS` | `30000` | How often (ms) a master looks for switches to update |
| `OTA_MAX_FAILS` | `3` | Attempts before a switch is marked failed and left alone |
| `OTA_BACKOFF_MS` | `120000` | Wait (ms) after a failed attempt before retrying |
| `EXT_OTA_CHUNK_SIZE` | `32` | Bytes per packet on the RS-485 wire |
| `FW_MAX_TYPES` | `8` | How many device types one master can store firmware for |

If you change `EXT_OTA_CHUNK_SIZE`, you must also change `OTA_CHUNK_SIZE`
in the extension sketch to the same number, and reflash both. Larger is
faster but less tolerant of a noisy bus. Do not exceed 32.

In the extension sketch:

| Setting | Default | Meaning |
|---|---|---|
| `FW_VER_MAJOR/MINOR/PATCH` | `1.0.0` | Version of this build |
| `FW_TARGET_TYPE` | `0x01` | Which device type this build is for |
| `ORPHAN_TIMEOUT_MS` | `30000` | How long (ms) without contact before a switch unpairs itself |

---

## Part 6 — Do not change these

These are shared between the bootloader and the extension. The bootloader
cannot be updated remotely — if these ever disagree, every board needs a
cable to recover.

| Name | Value |
|---|---|
| Bootloader location | `0x08000000` |
| Running firmware location | `0x08001000` |
| Update staging location | `0x08003800` |
| Settings location | `0x08006000` |
| Settings size | 32 bytes |
| Device type position | byte 8 |
| Board revision position | byte 9 |

If you ever must change one, change it in the bootloader **and** the
extension **and** reflash both over a cable, on every board.

---

## Part 7 — When something is wrong

### Reading the green light on the extension

The light flashes at startup, before the switch begins working normally.

| What you see | What it means | What to do |
|---|---|---|
| One long flash | Normal start | Nothing |
| Three quick flashes | Installing an update | Wait, it restarts itself |
| Five quick flashes | Update refused, kept the old firmware | See below |
| Flashing forever, fast | No working firmware | Redo Part 3 |
| Slow breathing | Running, not paired yet | Pair it from the app |
| Slower breathing | Running and paired | Nothing |

**Five flashes** means the update was rejected on purpose. Causes, in order
of likelihood: the identity write in Part 3 Step 1 was never done; the image
was built for a different device type; the image arrived damaged. The switch
keeps working on its old firmware.

### Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `not a Unisync extension image` on upload | Version marker missing from the file | Part 7, next section |
| `[FW] filesystem mount FAILED` at master boot | Wrong Partition Scheme | Part 2, reflash master |
| Switch never appears in the list | Wrong build setting, or identity not written | Part 1, then Part 3 |
| Update never starts | Version not increased | Part 4 Step 1 |
| `update failed 3x` in the web page | Switch not responding | Power cycle the switch; it retries |
| Board dead after flashing bootloader | Built with `0x1000` instead of `0x0` | Part 1, reflash bootloader |
| Board dead after flashing application | Built with `0x0` instead of `0x1000` | Part 1, reflash application |

### If the version marker is missing

Run the check in Part 4 Step 2. If `UNISYNC1` does not appear, the compiler
removed it. Confirm this block is present and unmodified in the extension
sketch:

```c
__attribute__((used, section(".rodata.fwdesc")))
static const uint8_t FW_DESC[16] = { ... };
```

### Recovering any board

A cable always works, whatever state the board is in. Erase and redo Part 3:

```bash
ocd "init; reset halt; stm32g0x mass_erase 0; reset; exit"
```

This erases everything including the identity write, so start again from
Part 3 Step 1.

### Reading a board's settings without changing them

```bash
ocd "init; reset halt; mdb 0x08006000 32; exit"
```

Byte 0 is `A5` if paired to a master, `FF` if not.
Byte 8 is the device type. If it reads `FF`, the identity was never written.

---

## Part 8 — Quick reference

```bash
# session setup
BOARDS=~/.arduino15/packages/STMicroelectronics/hardware/stm32/2.12.0/boards.txt
ocd() {
  ~/.arduino15/packages/STMicroelectronics/tools/xpack-openocd/0.12.0-6/bin/openocd \
    -f interface/stlink.cfg -f target/stm32g0x.cfg -c "$1"
}

# switch build target (restart the IDE after either)
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x0/'    $BOARDS   # bootloader
sed -i 's/^GenG0.build.flash_offset=.*$/GenG0.build.flash_offset=0x1000/' $BOARDS   # application
grep GenG0.build.flash_offset $BOARDS

# new board, once
python3 -c "b=bytearray(b'\xFF'*32); b[8]=0x01; b[9]=0x01; open('/tmp/prov.bin','wb').write(b)"
ocd "program /tmp/prov.bin 0x08006000 verify reset exit"
ocd "program .../ext_bootloader.ino.bin  0x08000000 verify reset exit"
ocd "program .../extension_stm32.ino.bin 0x08001000 verify reset exit"

# inspect / recover
ocd "init; reset halt; mdb 0x08006000 32; exit"
ocd "init; reset halt; stm32g0x mass_erase 0; reset; exit"
```

Everyday releases need none of the above — bump the version, export the
binary, upload it on the Settings page.
