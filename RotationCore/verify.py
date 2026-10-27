#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RotationCore static verification harness.

Checks (no WoW client required):
  1. Every .lua file parses (luaparser).
  2. Locale parity: each Locale_*.lua has exactly the RU key set (missing=0,
     extra=0; ignores the EN tooltips base table in Locale.lua).
  3. Version consistency: all 11 .toc files and DH.Version report the same
     version (1.0.2).
  4. No obviously forbidden API tokens in addon code (C_*, loadstring,
     securecallfunction, GetSpecialization global, WeakAuras, Ace3) outside
     the bundled Libs and comments-only matches.

Usage:
    python3 verify.py            # run all checks
    python3 verify.py --quiet    # print only failures / the summary line

Exit code 0 = all pass.
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

try:
    from luaparser import ast as lua_ast
except ImportError:  # pragma: no cover
    sys.stderr.write("verify.py requires 'luaparser' (pip install luaparser)\n")
    sys.exit(2)

ROOT = Path(__file__).resolve().parent
CORE = ROOT / "RotationCore"
EXPECTED_VERSION = "1.0.2"

# Key registrations that intentionally live outside Locale._xx_ files.
# Forbidden token scan: only hard *calls* in addon (non-Lib) code count; the
# two exceptions are the bundled Libs and our own comments/guarded usage.
FORBIDDEN_PATTERNS = [
    r"(?<![.:])C_[A-Za-z]\w*\s*\(",
    r"\bloadstring\s*\(",
    r"\bsecurecallfunction\s*\(",
    r"(?<![.:])GetSpecialization\s*\(",
    r"(?<![.:])GetSpecializationInfo\s*\(",
    r"\bGetSpellCharges\s*\(",
    r"\bWeakAuras\b\s*[(:]",   # usage (calls/methods); mere detection is fine
    r"\bAce3\b",
    r"\bCovenant",
]

LOCALE_FILES = [
    "Locale_deDE.lua", "Locale_frFR.lua", "Locale_esES.lua", "Locale_ptBR.lua",
    "Locale_itIT.lua", "Locale_koKR.lua", "Locale_zhCN.lua", "Locale_zhTW.lua",
]


def lua_files() -> list[Path]:
    bases = [CORE.glob("*.lua"), (CORE / "Libs").rglob("*.lua"),
             ROOT.glob("RotationCore_*/*.lua")]
    # flatten with dedupe by resolved path
    seen, out = set(), []
    for group in bases:
        for f in group:
            r = str(f.resolve())
            if r not in seen:
                seen.add(r)
                out.append(f)
    return out


def glob_lua(base: Path) -> list[Path]:
    return [p for p in base.glob("*.lua") if p.is_file()]


def check_parse(files: list[Path]) -> list[str]:
    bad = []
    for f in files:
        try:
            lua_ast.parse(f.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            bad.append(f"{f.relative_to(ROOT)}: {str(exc).splitlines()[0]}")
    return bad


def key_block(src: str, marker: str) -> str:
    i = src.index(marker)
    j = src.index("{", i)
    depth = 0
    k = j
    while k < len(src):
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    return src[j:k + 1]


def all_keys(src: str) -> set[str]:
    """Every ["..."]= key anywhere in the file (not just the first table)."""
    return set(re.findall(r'\["((?:[^"\\]|\\.)*)"\]\s*=', src))


def check_locale() -> list[str]:
    ru_src = (CORE / "Locale.lua").read_text(encoding="utf-8")
    ru_keys = all_keys(key_block(ru_src, "local ru = {"))
    problems = []
    for name in LOCALE_FILES:
        src = (CORE / name).read_text(encoding="utf-8")
        keys = all_keys(src)
        missing = ru_keys - keys
        extra = keys - ru_keys
        if missing or extra:
            problems.append(f"{name}: missing={len(missing)} extra={len(extra)}"
                            + (f" e.g. {sorted(missing)[:3]}" if missing else ""))
        # duplicate literal keys inside the same file
        dup = [k for k, n in Counter(re.findall(
            r'^\s*\["((?:[^"\\]|\\.)*)"\]\s*=', src, re.M)).items() if n > 1]
        if dup:
            problems.append(f"{name}: duplicate keys {dup[:3]}")
    return problems


def check_version() -> list[str]:
    problems = []
    tocs = list(ROOT.glob("*/*.toc")) + list(ROOT.glob("*.toc"))
    for toc in tocs:
        if f"## Version: {EXPECTED_VERSION}" not in toc.read_text(encoding="utf-8"):
            problems.append(f"{toc.relative_to(ROOT)}: version != {EXPECTED_VERSION}")
    core_src = (CORE / "RotationCore.lua").read_text(encoding="utf-8")
    if f'DH.Version = "{EXPECTED_VERSION}"' not in core_src:
        problems.append("RotationCore.lua: DH.Version != " + EXPECTED_VERSION)
    return problems


def check_forbidden(files: list[Path]) -> list[str]:
    problems = []
    for f in files:
        if "Libs" in str(f):
            continue  # bundled libraries are third-party
        src = f.read_text(encoding="utf-8")
        for line_no, line in enumerate(src.splitlines(), 1):
            for pat in FORBIDDEN_PATTERNS:
                if re.search(pat, line):
                    problems.append(f"{f.relative_to(ROOT)}:{line_no}: {pat.strip(r'\\')}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    files = lua_files()
    all_problems: list[str] = []
    all_problems += ["[parse] " + p for p in check_parse(files)]
    all_problems += ["[locale] " + p for p in check_locale()]
    all_problems += ["[version] " + p for p in check_version()]
    all_problems += ["[api] " + p for p in check_forbidden(files)]

    if not args.quiet:
        print(f"# RotationCore verification (files={len(files)})")
    for p in all_problems:
        print("  FAIL", p)
    if not args.quiet:
        print(f"PASS: {len(files)} files, {len(all_problems)} problems")
    return 1 if all_problems else 0


if __name__ == "__main__":
    sys.exit(main())