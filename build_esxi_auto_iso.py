#!/usr/bin/env python3

import shutil
from pathlib import Path
from tempfile import NamedTemporaryFile

import pycdlib


# ============================================================================
# CONFIGURATION
# ============================================================================

SOURCE_ISO = Path(
    "/cygdrive/e/vmware/ESXi-8.0.1-auto.iso"
)

OUTPUT_ISO = Path(
    "/cygdrive/e/vmware/ESXi-8.0.1-auto.iso"
)

SOURCE_BACKUP_ISO = Path(
    "/cygdrive/e/vmware/ESXi-8.0.1-auto-source-backup.iso"
)

WORK_ISO_DIR = Path(
    "/cygdrive/d/ESXI/esxi-auto/work/current-iso"
)

BOOT_CFG = WORK_ISO_DIR / "BOOT.CFG"


# ============================================================================
# HTTP KICKSTART
# ============================================================================

KS_URL = (
    "http://192.168.253.136/repo/ks.cfg"
)

EXPECTED_KERNELOPT = (
    "kernelopt=runweasel "
    "cdromBoot "
    "ip=192.168.253.128 "
    "netmask=255.255.255.0 "
    "gateway=192.168.253.2 "
    "nameserver=192.168.253.1 "
    "netdevice=vmnic0 "
    f"ks={KS_URL}"
)


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
# VERIFY HTTP KICKSTART
# ============================================================================

def verify_http_kickstart():
    """
    Verify that the HTTP KS.CFG is reachable.

    Uses curl because the user has already confirmed curl is available
    in the Cygwin environment.
    """

    import subprocess

    info(
        "Checking HTTP kickstart URL:\n"
        f"     {KS_URL}"
    )

    try:
        result = subprocess.run(
            [
                "curl",
                "-fsS",
                KS_URL,
            ],
            capture_output=True,
            text=True,
            timeout=20,
        )

    except FileNotFoundError:
        fail(
            "curl was not found.\n\n"
            "Install/use curl in Cygwin."
        )

    except subprocess.TimeoutExpired:
        fail(
            "HTTP kickstart request timed out:\n\n"
            f"{KS_URL}"
        )

    if result.returncode != 0:
        fail(
            "HTTP kickstart could not be downloaded.\n\n"
            f"URL:\n{KS_URL}\n\n"
            f"curl stderr:\n{result.stderr}"
        )

    ks_text = result.stdout

    required = [
        "vmaccepteula",
        "rootpw",
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

    missing = [
        item
        for item in required
        if item not in ks_text
    ]

    if missing:
        fail(
            "HTTP KS.CFG is reachable but is missing required "
            "configuration:\n\n"
            + "\n".join(
                f"- {item}"
                for item in missing
            )
        )

    ok("HTTP KS.CFG is reachable and valid")

    print()
    print("HTTP KS.CFG configuration:")
    print("  URL      :", KS_URL)
    print("  IP       : 192.168.253.128")
    print("  Netmask  : 255.255.255.0")
    print("  Gateway  : 192.168.253.2")
    print("  DNS      : 192.168.253.1")
    print("  Hostname : esxi-host-01.vgs.com")
    print("  Device   : vmnic0")


# ============================================================================
# VERIFY BOOT.CFG SOURCE
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
            f"Expected:\n"
            f"{EXPECTED_KERNELOPT}\n\n"
            f"Found:\n"
            f"{kernelopt}"
        )

    ok(
        f"BOOT.CFG kernelopt:\n"
        f"     {kernelopt}"
    )


# ============================================================================
# CREATE SOURCE BACKUP
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
# BUILD ISO
#
# The ISO already contains all ESXi files and the boot catalog.
#
# We only replace BOOT.CFG.
#
# KS.CFG is NOT added to the ISO because it is now served over HTTP.
# ============================================================================

def build_custom_iso():

    header(
        "OPENING CURRENT CUSTOMIZED ESXi ISO"
    )

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
        # Remove old output.
        # ------------------------------------------------------------

        if OUTPUT_ISO.exists():

            info(
                "Removing previous customized ISO:\n"
                f"     {OUTPUT_ISO}"
            )

            OUTPUT_ISO.unlink()

        # ------------------------------------------------------------
        # Replace BOOT.CFG.
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

            iso.add_file(
                str(BOOT_CFG),
                iso_path="/BOOT.CFG;1"
            )

            ok(
                "Modified BOOT.CFG added"
            )

        except Exception as exc:

            fail(
                "Could not add modified BOOT.CFG:\n\n"
                f"{exc}"
            )

        # ------------------------------------------------------------
        # Write output ISO.
        # ------------------------------------------------------------

        header(
            "WRITING CUSTOMIZED ISO"
        )

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
# EXTRACT FILE FOR VERIFICATION
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
# VERIFY FINAL ISO
# ============================================================================

def verify_custom_iso():

    header(
        "VERIFYING CUSTOMIZED ISO"
    )

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
        f"Output ISO exists:\n"
        f"     {OUTPUT_ISO}"
    )

    ok(
        f"Output ISO size:\n"
        f"     {output_size:,} bytes"
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
        # Verify BOOT.CFG.
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
                f"Expected:\n"
                f"{EXPECTED_KERNELOPT}\n\n"
                f"Found:\n"
                f"{found_kernelopt}"
            )

        ok(
            "BOOT.CFG contains correct kernelopt:\n"
            f"     {found_kernelopt}"
        )

    finally:

        iso.close()

        for temp_file in temp_files:
            try:
                temp_file.unlink()
            except OSError:
                pass


# ============================================================================
# DISPLAY RESULT
# ============================================================================

def display_iso_summary():

    output_size = (
        OUTPUT_ISO.stat().st_size
    )

    header(
        "ISO SUMMARY"
    )

    print(
        f"Customized ISO : {OUTPUT_ISO}"
    )

    print(
        f"Size           : {output_size:,} bytes"
    )

    print()

    print(
        "Kickstart URL:"
    )

    print(
        f"  {KS_URL}"
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


# ============================================================================
# CLEANUP
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
        "ESXi 8.0U1 HTTP-KICKSTART ISO BUILDER"
    )

    print(
        f"Current ISO : {SOURCE_ISO}"
    )

    print(
        f"BOOT.CFG    : {BOOT_CFG}"
    )

    print(
        f"Output ISO  : {OUTPUT_ISO}"
    )

    print(
        f"KS URL      : {KS_URL}"
    )

    # ------------------------------------------------------------
    # Validate HTTP KS.CFG first.
    # ------------------------------------------------------------

    verify_http_kickstart()

    # ------------------------------------------------------------
    # Validate BOOT.CFG.
    # ------------------------------------------------------------

    verify_boot_cfg_source()

    # ------------------------------------------------------------
    # Backup current ISO.
    # ------------------------------------------------------------

    create_source_backup()

    try:

        # --------------------------------------------------------
        # Build.
        # --------------------------------------------------------

        build_custom_iso()

        # --------------------------------------------------------
        # Verify.
        # --------------------------------------------------------

        verify_custom_iso()

        # --------------------------------------------------------
        # Display.
        # --------------------------------------------------------

        display_iso_summary()

        header(
            "SUCCESS"
        )

        print(
            "The ISO now points to the HTTP kickstart:"
        )

        print(
            f"  {KS_URL}"
        )

        print()

        print(
            "BOOT.CFG:"
        )

        print(
            f"  {EXPECTED_KERNELOPT}"
        )

        print()

        print(
            "No KS.CFG is required inside the ISO."
        )

    finally:

        cleanup_source_backup()


if __name__ == "__main__":
    main()
