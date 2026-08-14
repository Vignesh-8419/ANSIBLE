#!/usr/bin/env python3

import shutil
from pathlib import Path
from tempfile import NamedTemporaryFile

import pycdlib


ORIGINAL_ISO = Path(
    "/cygdrive/d/ESXI/esxi-auto/ESXi-8.0.1-original.iso"
)

WORK_ISO_DIR = Path(
    "/cygdrive/d/ESXI/esxi-auto/work/iso"
)

BOOT_CFG = WORK_ISO_DIR / "BOOT.CFG"
KS_CFG = WORK_ISO_DIR / "KS.CFG"

OUTPUT_DIR = Path(
    "/cygdrive/d/ESXI/esxi-auto/output"
)

OUTPUT_ISO = OUTPUT_DIR / "ESXi-8.0.1-auto.iso"

ORIGINAL_BACKUP = (
    OUTPUT_DIR / "ESXi-8.0.1-original-backup.iso"
)


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


def require_file(path, description):
    if not path.exists():
        fail(f"{description} does not exist:\n\n{path}")

    if not path.is_file():
        fail(f"{description} is not a regular file:\n\n{path}")


def verify_boot_cfg_source():
    require_file(BOOT_CFG, "Source BOOT.CFG")

    text = BOOT_CFG.read_text(
        encoding="utf-8",
        errors="replace"
    )

    kernelopt = None

    for line in text.splitlines():
        if line.startswith("kernelopt="):
            kernelopt = line.strip()
            break

    expected = (
        "kernelopt=runweasel "
        "cdromBoot ks=cdrom:/KS.CFG"
    )

    if kernelopt != expected:
        fail(
            "BOOT.CFG is not configured correctly.\n\n"
            f"Expected:\n{expected}\n\n"
            f"Found:\n{kernelopt}"
        )

    ok(f"BOOT.CFG kernelopt: {kernelopt}")


def verify_ks_cfg_source():
    require_file(KS_CFG, "Source KS.CFG")

    text = KS_CFG.read_text(
        encoding="utf-8",
        errors="replace"
    )

    required_strings = [
        "vmaccepteula",
        "rootpw ",
        "install --firstdisk --overwritevmfs",
        "reboot",
        "%firstboot",
    ]

    for required in required_strings:
        if required not in text:
            fail(
                "KS.CFG is missing required content:\n\n"
                f"{required}"
            )

    ok("KS.CFG contains all required directives")


def preserve_original_iso():
    require_file(
        ORIGINAL_ISO,
        "Original ESXi ISO"
    )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    if ORIGINAL_BACKUP.exists():
        ok(
            "Original ISO backup already exists:\n"
            f"     {ORIGINAL_BACKUP}"
        )
        return

    shutil.copy2(
        ORIGINAL_ISO,
        ORIGINAL_BACKUP
    )

    ok(
        "Original ISO backup created:\n"
        f"     {ORIGINAL_BACKUP}"
    )


def build_custom_iso():
    header("OPENING ORIGINAL ESXi ISO")

    iso = pycdlib.PyCdlib()

    try:
        iso.open(str(ORIGINAL_ISO))

        ok("Original ISO opened")

        if iso.eltorito_boot_catalog is None:
            fail(
                "Original ISO does not contain "
                "an El Torito boot catalog."
            )

        ok("Existing El Torito boot catalog detected")

        # ------------------------------------------------------------
        # Remove any previous customized output.
        # This NEVER touches the original ISO.
        # ------------------------------------------------------------

        if OUTPUT_ISO.exists():
            info(
                "Removing previous customized ISO only:\n"
                f"     {OUTPUT_ISO}"
            )
            OUTPUT_ISO.unlink()

        # ------------------------------------------------------------
        # Replace existing BOOT.CFG
        #
        # PyCdlib requires:
        #   1. rm_file()
        #   2. add_file()
        #
        # This is important because add_file() alone would create
        # another BOOT.CFG instead of replacing the existing one.
        # ------------------------------------------------------------

        try:
            iso.rm_file(
                iso_path="/BOOT.CFG;1"
            )
            ok("Original BOOT.CFG removed")
        except Exception as exc:
            fail(
                "Could not remove original BOOT.CFG:\n\n"
                f"{exc}"
            )

        try:
            iso.add_file(
                str(BOOT_CFG),
                iso_path="/BOOT.CFG;1"
            )
            ok("Modified BOOT.CFG added")
        except Exception as exc:
            fail(
                "Could not add modified BOOT.CFG:\n\n"
                f"{exc}"
            )

        # ------------------------------------------------------------
        # Add KS.CFG
        # ------------------------------------------------------------

        try:
            iso.add_file(
                str(KS_CFG),
                iso_path="/KS.CFG;1"
            )
            ok("KS.CFG added")
        except Exception as exc:
            fail(
                "Could not add KS.CFG:\n\n"
                f"{exc}"
            )

        # ------------------------------------------------------------
        # Write customized ISO
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


def extract_iso_file(iso, iso_path, suffix):
    temp_file = NamedTemporaryFile(
        prefix="esxi_iso_",
        suffix=suffix,
        delete=False
    )

    temp_path = Path(temp_file.name)
    temp_file.close()

    iso.get_file_from_iso(
        local_path=str(temp_path),
        iso_path=iso_path
    )

    return temp_path


def verify_custom_iso():
    header("VERIFYING CUSTOMIZED ISO")

    require_file(
        OUTPUT_ISO,
        "Customized ISO"
    )

    output_size = OUTPUT_ISO.stat().st_size

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
        iso.open(str(OUTPUT_ISO))

        ok("Customized ISO opens successfully")

        if iso.eltorito_boot_catalog is None:
            fail(
                "Customized ISO does not contain "
                "an El Torito boot catalog."
            )

        ok("El Torito boot catalog preserved")

        boot_cfg_temp = None

        try:
            boot_cfg_temp = extract_iso_file(
                iso,
                "/BOOT.CFG;1",
                ".cfg"
            )

            temp_files.append(boot_cfg_temp)

            boot_cfg_text = boot_cfg_temp.read_text(
                encoding="utf-8",
                errors="replace"
            )

        except Exception as exc:
            fail(
                "Could not read BOOT.CFG from customized ISO:\n\n"
                f"{exc}"
            )

        expected_kernelopt = (
            "kernelopt=runweasel "
            "cdromBoot ks=cdrom:/KS.CFG"
        )

        found_kernelopt = None

        for line in boot_cfg_text.splitlines():
            if line.startswith("kernelopt="):
                found_kernelopt = line.strip()
                break

        if found_kernelopt != expected_kernelopt:
            fail(
                "Customized ISO contains incorrect BOOT.CFG.\n\n"
                f"Expected:\n{expected_kernelopt}\n\n"
                f"Found:\n{found_kernelopt}"
            )

        ok(
            "BOOT.CFG contains correct kernelopt:\n"
            f"     {found_kernelopt}"
        )

        ks_cfg_temp = None

        try:
            ks_cfg_temp = extract_iso_file(
                iso,
                "/KS.CFG;1",
                ".cfg"
            )

            temp_files.append(ks_cfg_temp)

            ks_cfg_text = ks_cfg_temp.read_text(
                encoding="utf-8",
                errors="replace"
            )

        except Exception as exc:
            fail(
                "Could not read KS.CFG from customized ISO:\n\n"
                f"{exc}"
            )

        required_strings = [
            "vmaccepteula",
            "rootpw ",
            "install --firstdisk --overwritevmfs",
            "reboot",
            "%firstboot",
        ]

        for required in required_strings:
            if required not in ks_cfg_text:
                fail(
                    "KS.CFG inside customized ISO is missing:\n\n"
                    f"{required}"
                )

        ok(
            "KS.CFG exists and contains required directives"
        )

    finally:
        iso.close()

        for temp_file in temp_files:
            try:
                temp_file.unlink()
            except OSError:
                pass


def display_iso_sizes():
    original_size = ORIGINAL_ISO.stat().st_size
    output_size = OUTPUT_ISO.stat().st_size

    header("ISO SIZE SUMMARY")

    print(
        f"Original ISO   : {original_size:,} bytes"
    )

    print(
        f"Customized ISO : {output_size:,} bytes"
    )

    print(
        f"Difference     : "
        f"{output_size - original_size:+,} bytes"
    )


def main():
    header("ESXi 8.0U1 UNATTENDED ISO BUILDER")

    print(f"Original ISO : {ORIGINAL_ISO}")
    print(f"BOOT.CFG     : {BOOT_CFG}")
    print(f"KS.CFG       : {KS_CFG}")
    print(f"Output ISO   : {OUTPUT_ISO}")
    print(f"Backup ISO   : {ORIGINAL_BACKUP}")

    require_file(
        ORIGINAL_ISO,
        "Original ESXi ISO"
    )

    verify_boot_cfg_source()
    verify_ks_cfg_source()

    preserve_original_iso()

    build_custom_iso()

    verify_custom_iso()

    display_iso_sizes()

    header("SUCCESS")

    print("Original ISO was NOT modified:")
    print(f"  {ORIGINAL_ISO}")
    print()
    print("Original backup:")
    print(f"  {ORIGINAL_BACKUP}")
    print()
    print("Customized ISO:")
    print(f"  {OUTPUT_ISO}")
    print()
    print(
        "Kernel option:"
    )
    print(
        "  kernelopt=runweasel cdromBoot ks=cdrom:/KS.CFG"
    )
    print()
    print("Kickstart:")
    print("  KS.CFG")


if __name__ == "__main__":
    main()
