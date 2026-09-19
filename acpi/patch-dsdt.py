#!/usr/bin/env python3
"""Patch the Yoga Slim 7 Carbon 14ACN6 DSDT for the ACPI table upgrade.

Renames the _HID of \\_SB.I2CA.SPK1 ("CLSA0102") to XHID, so the SSDT from
cs35l41-spk1.asl can give the device a new _HID. The replacement has the same
length, so no AML package lengths change. The OEM revision is bumped (the
kernel only upgrades a table to a newer revision) and the checksum is fixed.

Usage: patch-dsdt.py <input DSDT.aml> <output DSDT.aml>
"""
import struct
import sys

ORIG = b"\x08_HID\x0dCLSA0102\x00"
PATCHED = b"\x08XHID\x0dCLSA0102\x00"


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    data = bytearray(open(sys.argv[1], "rb").read())

    if data[:4] != b"DSDT" or struct.unpack_from("<I", data, 4)[0] != len(data):
        sys.exit("error: input is not a complete DSDT table")

    if data.count(PATCHED) == 1 and data.count(ORIG) == 0:
        # Already patched (the override is active and we read it back)
        print("DSDT is already patched, reusing it")
    elif data.count(ORIG) == 1:
        i = data.find(ORIG)
        data[i + 1:i + 5] = b"XHID"
        rev = struct.unpack_from("<I", data, 24)[0]
        struct.pack_into("<I", data, 24, rev + 1)
        print(f"patched SPK1 _HID -> XHID, OEM revision {rev} -> {rev + 1}")
    else:
        sys.exit("error: CLSA0102 _HID not found exactly once; "
                 "this is not the expected BIOS")

    data[9] = 0
    data[9] = (-sum(data)) & 0xFF
    open(sys.argv[2], "wb").write(data)


if __name__ == "__main__":
    main()
