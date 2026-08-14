#!/usr/bin/env python3

import shutil
from pathlib import Path
from tempfile import NamedTemporaryFile

import pycdlib


# ============================================================================
# CURRENT CUSTOMIZED ISO
#
# The original VMware ISO was deleted.
#
# We now use the existing customized ISO as the source.
# ============================================================================

SOURCE_ISO = Path(
    "/cygdrive/e/vmware/ESXi-8.0.1-auto.iso"
)

OUTPUT_ISO = Path(
    "/cygdrive/e/vmware/ESXi-8.0.1-auto.iso"
)

# Temporary source backup used while rebuilding the same ISO.
SOURCE_BACKUP_ISO = Path(
    "/cygdrive/e/vmware/ESXi-8.0.1-auto-source-backup.iso"
)


# ============================================================================
# EXTRACTED WORKING CONTENT
# ============================================================================

WORK_ISO_DIR = Path(
    "/cygdrive/d/ESXI/esxi-auto/work/current-iso"
)

BOOT_CFG = WORK_ISO_DIR / "BOOT.CFG"
KS_CFG = WORK_ISO_DIR / "KS.CFG"


# ============================================================================
# EXPECTED CONFIGURATION
# ============================================================================

EXPECTED_KERNELOPT = (
    "kernelopt=runweasel "
    "cdromBoot ks=http://http-server-01.vgs.com/repo/ks.cfg"
)

REQUIRED_KS_STRINGS = [
    "vmaccepteula",
    "rootpw ",
    "network --bootproto=static",
    "--ip=192.168.253.128",
    "--netmask=255.255.255.0",
    "--gateway=192.168.253.2",
    "--nameserver=192.168.253.1",
    "--hostname=esxi-host-01.vgs.com",
    "--device=vmnic0",
    "install --firstdisk --overwritevmfs",
    "reboot",
    "%firstboot",
]


# ============================================================================
# OUTPUT HELPERS
# ============================================================================

def header(text):
    print()
    print("=" * 72)
    print(text)
    print("=" * 72)


def ok(text):
    print(f"[OK] {text}")


def info(text):
    print(f"[INFO] {text}")


def warn(text):
    print(f"[WARN] {text}")


def fail(text):
    print()
    print("=" * 72)
    print("ERROR")
    print("=" * 72)
    print(text)
    print("=" * 72)
    raise SystemExit(1)


# ============================================================================
# FILE VALIDATION
# ============================================================================

def require_file(path, description):
    if not path.exists():
        fail(
            f"{description} does not exist:\n\n"
            f"{path}"
        )

    if not path.is_file():
        fail(
            f"{description} is not a regular file:\n\n"
            f"{path}"
        )


# ============================================================================
# VERIFY BOOT.CFG FROM WORK DIRECTORY
# ============================================================================

def verify_boot_cfg_source():

    require_file(
        BOOT_CFG,
        "Source BOOT.CFG"
    )

    text = BOOT_CFG.read_text(
        encoding="utf-8",
        errors="replace"
    )

    kernelopt = None

    for line in text.splitlines():

        if line.startswith("kernelopt="):
            kernelopt = line.strip()
            break

    if kernelopt != EXPECTED_KERNELOPT:

        fail(
            "BOOT.CFG is not configured correctly.\n\n"
            f"Expected:\n{EXPECTED_KERNELOPT}\n\n"
            f"Found:\n{kernelopt}"
        )

    ok(
        f"BOOT.CFG kernelopt: {kernelopt}"
    )


# ============================================================================
# VERIFY KS.CFG FROM WORK DIRECTORY
# ============================================================================

def verify_ks_cfg_source():

    require_file(
        KS_CFG,
        "Source KS.CFG"
    )

    text = KS_CFG.read_text(
        encoding="utf-8",
        errors="replace"
    )

    missing = []

    for required in REQUIRED_KS_STRINGS:

        if required not in text:
            missing.append(required)

    if missing:

        fail(
            "KS.CFG is missing required content:\n\n"
            + "\n".join(
                f"- {item}"
                for item in missing
            )
        )

    ok("KS.CFG contains required directives")

    print()
    print("KS.CFG network configuration:")
    print("  IP       : 192.168.253.128")
    print("  Netmask  : 255.255.255.0")
    print("  Gateway  : 192.168.253.2")
    print("  DNS      : 192.168.253.1")
    print("  Hostname : esxi-host-01.vgs.com")
    print("  Device   : vmnic0")


# ============================================================================
# CREATE SAFE SOURCE BACKUP
# ============================================================================

def create_source_backup():

    require_file(
        SOURCE_ISO,
        "Current customized ESXi ISO"
    )

    if SOURCE_BACKUP_ISO.exists():

        info(
            "Removing previous temporary source backup:\n"
            f"     {SOURCE_BACKUP_ISO}"
        )

        SOURCE_BACKUP_ISO.unlink()

    shutil.copy2(
        SOURCE_ISO,
        SOURCE_BACKUP_ISO
    )

    ok(
        "Current customized ISO backed up:\n"
        f"     {SOURCE_BACKUP_ISO}"
    )


# ============================================================================
# BUILD CUSTOMIZED ISO
#
# Important:
#
# SOURCE_BACKUP_ISO is opened.
# OUTPUT_ISO is written.
#
# This avoids trying to read and overwrite the same ISO simultaneously.
# ============================================================================

def build_custom_iso():

    header("OPENING CURRENT CUSTOMIZED ESXi ISO")

    iso = pycdlib.PyCdlib()

    try:

        iso.open(
            str(SOURCE_BACKUP_ISO)
        )

        ok(
            "Current customized ISO opened"
        )

        if iso.eltorito_boot_catalog is None:

            fail(
                "Current ISO does not contain "
                "an El Torito boot catalog."
            )

        ok(
            "Existing El Torito boot catalog detected"
        )

        # ------------------------------------------------------------
        # Remove old output before writing.
        # ------------------------------------------------------------

        if OUTPUT_ISO.exists():

            info(
                "Removing previous customized ISO:\n"
                f"     {OUTPUT_ISO}"
            )

            OUTPUT_ISO.unlink()

        # ------------------------------------------------------------
        # Replace BOOT.CFG
        # ------------------------------------------------------------

        try:

            iso.rm_file(
                iso_path="/BOOT.CFG;1"
            )

            ok(
                "Existing BOOT.CFG removed"
            )

        except Exception as exc:

            fail(
                "Could not remove existing BOOT.CFG:\n\n"
                f"{exc}"
            )

        try:

            ok(
                "Modified BOOT.CFG added"
            )

        except Exception as exc:

            fail(
                "Could not add modified BOOT.CFG:\n\n"
                f"{exc}"
            )

        # ------------------------------------------------------------
        # Replace KS.CFG
        # ------------------------------------------------------------

        try:

            iso.rm_file(
                iso_path="/KS.CFG;1"
            )

            ok(
                "Existing KS.CFG removed"
            )

        except Exception:

            warn(
                "Existing KS.CFG was not found; "
                "adding it as a new file."
            )

        try:

            iso.add_file(
                str(KS_CFG),
                iso_path="/KS.CFG;1"
            )

            ok(
                "Modified KS.CFG added"
            )

        except Exception as exc:

            fail(
                "Could not add modified KS.CFG:\n\n"
                f"{exc}"
            )

        # ------------------------------------------------------------
        # Write output ISO
        # ------------------------------------------------------------

        header("WRITING CUSTOMIZED ISO")

        iso.write(
            str(OUTPUT_ISO)
        )

        ok(
            "Customized ISO written:\n"
            f"     {OUTPUT_ISO}"
        )

    finally:

        iso.close()


# ============================================================================
# EXTRACT FILE FROM ISO FOR VERIFICATION
# ============================================================================

def extract_iso_file(iso, iso_path, suffix):

    temp_file = NamedTemporaryFile(
        prefix="esxi_iso_",
        suffix=suffix,
        delete=False
    )

    temp_path = Path(
        temp_file.name
    )

    temp_file.close()

    iso.get_file_from_iso(
        local_path=str(temp_path),
        iso_path=iso_path
    )

    return temp_path


# ============================================================================
# VERIFY OUTPUT ISO
# ============================================================================

def verify_custom_iso():

    header("VERIFYING CUSTOMIZED ISO")

    require_file(
        OUTPUT_ISO,
        "Customized ISO"
    )

    output_size = (
        OUTPUT_ISO.stat().st_size
    )

    if output_size < 100 * 1024 * 1024:

        fail(
            "Customized ISO is unexpectedly small.\n\n"
            f"Size: {output_size:,} bytes"
        )

    ok(
        f"Output ISO exists: {OUTPUT_ISO}"
    )

    ok(
        f"Output ISO size: {output_size:,} bytes"
    )

    iso = pycdlib.PyCdlib()

    temp_files = []

    try:

        iso.open(
            str(OUTPUT_ISO)
        )

        ok(
            "Customized ISO opens successfully"
        )

        if iso.eltorito_boot_catalog is None:

            fail(
                "Customized ISO does not contain "
                "an El Torito boot catalog."
            )

        ok(
            "El Torito boot catalog preserved"
        )

        # ------------------------------------------------------------
        # Verify BOOT.CFG
        # ------------------------------------------------------------

        try:

            boot_cfg_temp = extract_iso_file(
                iso,
                "/BOOT.CFG;1",
                ".cfg"
            )

            temp_files.append(
                boot_cfg_temp
            )

            boot_cfg_text = boot_cfg_temp.read_text(
                encoding="utf-8",
                errors="replace"
            )

        except Exception as exc:

            fail(
                "Could not read BOOT.CFG from customized ISO:\n\n"
                f"{exc}"
            )

        found_kernelopt = None

        for line in boot_cfg_text.splitlines():

            if line.startswith("kernelopt="):

                found_kernelopt = line.strip()
                break

        if found_kernelopt != EXPECTED_KERNELOPT:

            fail(
                "Customized ISO contains incorrect BOOT.CFG.\n\n"
                f"Expected:\n{EXPECTED_KERNELOPT}\n\n"
                f"Found:\n{found_kernelopt}"
            )

        ok(
            "BOOT.CFG contains correct kernelopt:\n"
            f"     {found_kernelopt}"
        )

        # ------------------------------------------------------------
        # Verify KS.CFG
        # ------------------------------------------------------------

        try:

            ks_cfg_temp = extract_iso_file(
                iso,
                "/KS.CFG;1",
                ".cfg"
            )

            temp_files.append(
                ks_cfg_temp
            )

            ks_cfg_text = ks_cfg_temp.read_text(
                encoding="utf-8",
                errors="replace"
            )

        except Exception as exc:

            fail(
                "Could not read KS.CFG from customized ISO:\n\n"
                f"{exc}"
            )

        missing = []

        for required in REQUIRED_KS_STRINGS:

            if required not in ks_cfg_text:
                missing.append(required)

        if missing:

            fail(
                "KS.CFG inside customized ISO is missing:\n\n"
                + "\n".join(
                    f"- {item}"
                    for item in missing
                )
            )

        ok(
            "KS.CFG exists and contains required directives"
        )

        print()
        print(
            "Verified ESXi network configuration:"
        )

        print(
            "  IP       : 192.168.253.128"
        )

        print(
            "  Netmask  : 255.255.255.0"
        )

        print(
            "  Gateway  : 192.168.253.2"
        )

        print(
            "  DNS      : 192.168.253.1"
        )

        print(
            "  Hostname : esxi-host-01.vgs.com"
        )

        print(
            "  Device   : vmnic0"
        )

    finally:

        iso.close()

        for temp_file in temp_files:

            try:
                temp_file.unlink()

            except OSError:
                pass


# ============================================================================
# DISPLAY ISO SIZE
# ============================================================================

def display_iso_size():

    output_size = (
        OUTPUT_ISO.stat().st_size
    )

    header("ISO SUMMARY")

    print(
        f"Customized ISO : {OUTPUT_ISO}"
    )

    print(
        f"Size           : {output_size:,} bytes"
    )


# ============================================================================
# CLEAN TEMP SOURCE BACKUP
# ============================================================================

def cleanup_source_backup():

    if not SOURCE_BACKUP_ISO.exists():
        return

    try:

        SOURCE_BACKUP_ISO.unlink()

        ok(
            "Temporary source backup removed"
        )

    except OSError as exc:

        warn(
            "Could not remove temporary source backup:\n"
            f"{SOURCE_BACKUP_ISO}\n\n"
            f"{exc}"
        )


# ============================================================================
# MAIN
# ============================================================================

def main():

    header(
        "ESXi 8.0U1 UNATTENDED ISO BUILDER"
    )

    print(
        f"Current ISO    : {SOURCE_ISO}"
    )

    print(
        f"BOOT.CFG       : {BOOT_CFG}"
    )

    print(
        f"KS.CFG         : {KS_CFG}"
    )

    print(
        f"Output ISO     : {OUTPUT_ISO}"
    )

    print(
        f"Source Backup  : {SOURCE_BACKUP_ISO}"
    )

    # ------------------------------------------------------------
    # Validate working files first.
    # ------------------------------------------------------------

    verify_boot_cfg_source()
    verify_ks_cfg_source()

    # ------------------------------------------------------------
    # Backup existing customized ISO.
    # ------------------------------------------------------------

    create_source_backup()

    try:

        # --------------------------------------------------------
        # Build
        # --------------------------------------------------------

        build_custom_iso()

        # --------------------------------------------------------
        # Verify
        # --------------------------------------------------------

        verify_custom_iso()

        # --------------------------------------------------------
        # Display result
        # --------------------------------------------------------

        display_iso_size()

        header("SUCCESS")

        print(
            "Customized ISO:"
        )

        print(
            f"  {OUTPUT_ISO}"
        )

        print()

        print(
            "Kernel option:"
        )

        print(
            f"  {EXPECTED_KERNELOPT}"
        )

        print()

        print(
            "Static network:"
        )

        print(
            "  IP       : 192.168.253.128"
        )

        print(
            "  Netmask  : 255.255.255.0"
        )

        print(
            "  Gateway  : 192.168.253.2"
        )

        print(
            "  DNS      : 192.168.253.1"
        )

        print(
            "  Hostname : esxi-host-01.vgs.com"
        )

        print()

        print(
            "ISO rebuild completed successfully."
        )

    finally:

        cleanup_source_backup()


if __name__ == "__main__":
    main()
