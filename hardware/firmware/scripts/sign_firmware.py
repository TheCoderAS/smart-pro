#!/usr/bin/env python3
"""
Sign a Unisync extension image.

The signature is produced here, offline, with the firmware key -- never on
a master. A compromised master therefore cannot forge firmware; it can only
relay a signature someone with the key already produced.

Usage:
    ./sign_firmware.py extension_stm32.ino.bin --key <32 hex chars> [--sec 1]

Prints the values to paste into the upload form, and writes <name>.sig.
"""
import argparse, hashlib, hmac, sys, pathlib

ap = argparse.ArgumentParser()
ap.add_argument("image")
ap.add_argument("--key", required=True, help="firmware key, 32 hex chars")
ap.add_argument("--sec", type=int, default=0,
                help="security version; raise it to lock out older builds")
a = ap.parse_args()

key = bytes.fromhex(a.key)
if len(key) != 16:
    sys.exit("key must be exactly 32 hex characters (16 bytes)")
if not 0 <= a.sec <= 255:
    sys.exit("security version must be 0..255")

img = pathlib.Path(a.image).read_bytes()

magic = img.find(b"UNISYNC1")
if magic < 0:
    sys.exit("no Unisync descriptor in this image -- wrong file, or the "
             "descriptor was optimised out")
dev_type = img[magic + 8]
ver = (img[magic + 10], img[magic + 11], img[magic + 12])

sig = hmac.new(key, img, hashlib.sha256).digest()
pathlib.Path(a.image + ".sig").write_bytes(sig)

print(f"image      : {a.image}")
print(f"size       : {len(img)} bytes")
print(f"type       : {dev_type}")
print(f"version    : {ver[0]}.{ver[1]}.{ver[2]}")
print(f"security   : {a.sec}")
print(f"signature  : {sig.hex()}")
print()
print("Upload with:")
print(f'  curl -F "firmware=@{a.image}" \\')
print(f'       -F "sig={sig.hex()}" -F "sec={a.sec}" \\')
print(f'       -H "X-Auth: $TOKEN" \\')
print(f'       "http://192.168.4.1/api/fw/upload?mesh=1"')
