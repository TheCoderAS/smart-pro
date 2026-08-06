#!/usr/bin/env python3
"""
Provision one extension board.

Writes 64 bytes of NVS: identity, the firmware verification key, and a
per-device bus key derived from the root key. Run once per board on the
production jig, before or after flashing.

Usage:
    ./provision.py --uid <8 hex> --type 1 --rev 1 \
                   --root <32 hex> --fw <32 hex> [--out prov.bin]

The UID is the STM32 device UID the board reports; read it from the master
log line "[EXT] 0x01 type=..." or over SWD.
"""
import argparse, hashlib, hmac, pathlib, sys

ap = argparse.ArgumentParser()
ap.add_argument("--uid",  required=True, help="device UID, 8 hex chars")
ap.add_argument("--type", type=int, required=True)
ap.add_argument("--rev",  type=int, default=1)
ap.add_argument("--root", required=True, help="root key, 32 hex chars")
ap.add_argument("--fw",   required=True, help="firmware key, 32 hex chars")
ap.add_argument("--out",  default="prov.bin")
a = ap.parse_args()

uid  = bytes.fromhex(a.uid)
root = bytes.fromhex(a.root)
fwk  = bytes.fromhex(a.fw)
if len(uid) != 4:  sys.exit("uid must be 8 hex characters")
if len(root) != 16 or len(fwk) != 16:
    sys.exit("keys must be 32 hex characters each")
if not 1 <= a.type <= 254: sys.exit("type must be 1..254")

# Same derivation the master performs, so the two agree without a database.
dev_key = hmac.new(root, uid, hashlib.sha256).digest()[:16]

b = bytearray(b"\xFF" * 64)
b[8]  = a.type
b[9]  = a.rev
b[11] = 0                      # security version floor starts at 0
b[32:48] = fwk
b[48:64] = dev_key

pathlib.Path(a.out).write_bytes(b)
print(f"uid        : {a.uid}")
print(f"type / rev : {a.type} / {a.rev}")
print(f"dev_key    : {dev_key.hex()}  (derived, not stored anywhere else)")
print(f"written    : {a.out} ({len(b)} bytes)")
print()
print("Flash it with:")
print(f'  ocd "program {a.out} 0x08007000 verify reset exit"')
