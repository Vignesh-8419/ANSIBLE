#!/usr/bin/env python3

import shutil
from pathlib import Path
import pycdlib

ISO = Path("/cygdrive/e/vmware/ESXi-8.0.1-auto.iso")
BACKUP = Path("/cygdrive/e/vmware/ESXi-8.0.1-auto-before-uefi-fix.iso")

WORK_BOOT_CFG = Path(
    "/cygdrive/d/ESXI/esxi-auto/work/current-iso/EFI/BOOT/BOOT.CFG"
)

EXPECTED = (
    "kernelopt=runweasel cdromBoot "
    "ip=192.168.253.128 "
    "netmask=255.255.255.0 "
    "gateway=192.168.253.2 "
    "nameserver=192.168.253.1 "
    "netdevice=vmnic0 "
    "ks=http://192.168.253.136/repo/ks.cfg"
)


def fail(msg):
    print()
    print("=" * 72)
    print("ERROR")
    print("=" * 72)
    print(msg)
    print("=" * 72)
    raise SystemExit(1)


def ok(msg):
    print(f"[OK] {msg}")


if not ISO.is_file():
    fail(f"ISO not found:\n{ISO}")

if not WORK_BOOT_CFG.is_file():
    fail(f"Working EFI BOOT.CFG not found:\n{WORK_BOOT_CFG}")


text = WORK_BOOT_CFG.read_text(
    encoding="utf-8",
    errors="replace",
)

kernelopt = None

for line in text.splitlines():
    if line.startswith("kernelopt="):
        kernelopt = line.strip()
        break

if kernelopt != EXPECTED:
    fail(
        "Working EFI/BOOT/BOOT.CFG has the wrong kernelopt.\n\n"
        f"Expected:\n{EXPECTED}\n\n"
        f"Found:\n{kernelopt}"
    )

print("=" * 72)
print("ESXi UEFI BOOT.CFG ISO UPDATE")
print("=" * 72)
print(f"ISO        : {ISO}")
print(f"BOOT.CFG   : {WORK_BOOT_CFG}")
print()
print(f"kernelopt  : {kernelopt}")

# ----------------------------------------------------------------------
# Backup current ISO. Never modify the only copy without a backup.
# ----------------------------------------------------------------------

if BACKUP.exists():
    BACKUP.unlink()

shutil.copy2(ISO, BACKUP)

ok(f"ISO backup created:\n     {BACKUP}")

# ----------------------------------------------------------------------
# Open ISO
# ----------------------------------------------------------------------

iso = pycdlib.PyCdlib()

try:
    iso.open(str(BACKUP))

    ok("ISO opened successfully")

    if iso.eltorito_boot_catalog is None:
        fail("ISO does not contain an El Torito boot catalog.")

    ok("El Torito boot catalog preserved")

    # ------------------------------------------------------------------
    # IMPORTANT:
    # This is the actual UEFI path in your ESXi ISO.
    # ------------------------------------------------------------------

    uefi_path = "/EFI/BOOT/BOOT.CFG;1"

    try:
        iso.rm_file(iso_path=uefi_path)
        ok("Existing EFI/BOOT/BOOT.CFG removed")
    except Exception as exc:
        fail(
            "Could not remove existing EFI/BOOT/BOOT.CFG:\n"
            f"{exc}"
        )

    iso.add_file(
        str(WORK_BOOT_CFG),
        iso_path=uefi_path,
    )

    ok("Modified EFI/BOOT/BOOT.CFG added")

    # --------------------------------------------------------------
    # Write back to the original customized ISO path.
    # --------------------------------------------------------------

    if ISO.exists():
        ISO.unlink()

    iso.write(str(ISO))

    ok(f"Updated ISO written:\n     {ISO}")

finally:
    iso.close()

# ----------------------------------------------------------------------
# Verify the resulting ISO
# ----------------------------------------------------------------------

verify = pycdlib.PyCdlib()

try:
    verify.open(str(ISO))

    ok("Updated ISO opens successfully")

    temp_file = Path(
        "/tmp/esxi_uefi_bootcfg_verify.cfg"
    )

    try:
        verify.get_file_from_iso(
            local_path=str(temp_file),
            iso_path="/EFI/BOOT/BOOT.CFG;1",
        )

        verify_text = temp_file.read_text(
            encoding="utf-8",
            errors="replace",
        )

    finally:
        if temp_file.exists():
            temp_file.unlink()

    found = None

    for line in verify_text.splitlines():
        if line.startswith("kernelopt="):
            found = line.strip()
            break

    if found != EXPECTED:
        fail(
            "Updated ISO still contains an incorrect UEFI BOOT.CFG.\n\n"
            f"Expected:\n{EXPECTED}\n\n"
            f"Found:\n{found}"
        )

    ok("EFI/BOOT/BOOT.CFG contains the correct kernelopt")

finally:
    verify.close()

print()
print("=" * 72)
print("SUCCESS")
print("=" * 72)
print("UEFI BOOT.CFG has been updated inside the ISO.")
print()
print(f"ISO:")
print(f"  {ISO}")
print()
print("Kickstart:")
print("  http://192.168.253.136/repo/ks.cfg")
print()
print("kernelopt:")
print(f"  {EXPECTED}")
print("=" * 72)
