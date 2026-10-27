#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build a distributable RotationCore release zip.

Produces: dist/RotationCore-<version>.zip

The zip contains the addon folders at its top level so users can extract it
straight into Interface/AddOns/:

    RotationCore-1.0.4.zip
    ├── RotationCore/                (core addon folder)
    └── RotationCore_<Class>/        (LoadOnDemand class modules)

The version is read from the core .toc file. Internal/dev files (verify.py,
docs/, scripts/) are excluded.
"""
from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON_SRC = ROOT / "RotationCore"
DIST = ROOT / "dist"

# Folders shipped in the zip (addon folders the client loads).
SHIP_FOLDERS = [
    "RotationCore",
    "RotationCore_DeathKnight",
    "RotationCore_Druid",
    "RotationCore_Hunter",
    "RotationCore_Mage",
    "RotationCore_Paladin",
    "RotationCore_Priest",
    "RotationCore_Rogue",
    "RotationCore_Shaman",
    "RotationCore_Warlock",
    "RotationCore_Warrior",
]

# Never ship these even if they live inside a shipped folder.
EXCLUDE_NAMES = {"__pycache__", ".DS_Store", "Thumbs.db"}
EXCLUDE_SUFFIXES = {".pyc", ".pyo", ".luac", ".zip"}


def read_version() -> str:
    toc = ADDON_SRC / "RotationCore" / "RotationCore.toc"
    m = re.search(r"##\s*Version:\s*(\S+)", toc.read_text(encoding="utf-8"))
    if not m:
        sys.exit(f"could not read ## Version from {toc}")
    return m.group(1)


def collect_files() -> list[tuple[Path, str]]:
    """Return (abs_path, archive_name) pairs for everything to ship."""
    out: list[tuple[Path, str]] = []
    for folder in SHIP_FOLDERS:
        src_dir = ADDON_SRC / folder
        if not src_dir.is_dir():
            sys.exit(f"missing addon folder: {src_dir}")
        for path in sorted(src_dir.rglob("*")):
            if not path.is_file():
                continue
            if path.name in EXCLUDE_NAMES or path.suffix in EXCLUDE_SUFFIXES:
                continue
            rel = path.relative_to(ADDON_SRC)  # e.g. RotationCore/State.lua
            out.append((path, rel.as_posix()))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", help="output dir (default: dist/)")
    args = parser.parse_args()

    version = read_version()
    out_dir = Path(args.out) if args.out else DIST
    out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / f"RotationCore-{version}.zip"

    files = collect_files()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for abs_path, arc_name in files:
            zf.write(abs_path, arc_name)

    print(f"built {zip_path} ({len(files)} files, version {version})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
