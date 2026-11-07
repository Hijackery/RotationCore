#!/usr/bin/env python3
"""Run the Lua behavior tests against a small WoW API mock.

The addon targets Lua 5.1; lupa is used as the test interpreter. Each
class runs in a fresh runtime so mode registration cannot leak between suites.
"""

from __future__ import annotations

import sys
from pathlib import Path

import lupa

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "RotationCore" / "RotationCore"
TESTS = ROOT / "tests" / "lua"

CORE_FILES = [
    "RotationCore.lua",
    "Schema.lua",
    "Simulation.lua",
    "Registration.lua",
    "KnownSpells.lua",
    "SharedSettings.lua",
    "Profiles.lua",
    "BossProfiles.lua",
    "BossTimeline.lua",
    "CustomAPL.lua",
    "Analytics.lua",
    "State.lua",
    "Heal.lua",
    "Config.lua",
]

CLASS_SUITES = [
    ("Druid", "DRUID", ["RotationCore_Druid/Druid.lua", "RotationCore_Druid/Core.lua"]),
    ("Paladin", "PALADIN", ["RotationCore_Paladin/Paladin.lua", "RotationCore_Paladin/Core.lua"]),
    ("Shaman", "SHAMAN", ["RotationCore_Shaman/Shaman.lua", "RotationCore_Shaman/Core.lua"]),
    ("Priest", "PRIEST", ["RotationCore_Priest/Priest.lua", "RotationCore_Priest/Core.lua"]),
]


def execute_file(runtime: lupa.LuaRuntime, path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    runtime.execute(source)


SMOKE_FILES = [
    "RotationCore.lua",
    "Schema.lua",
    "Simulation.lua",
    "Registration.lua",
    "KnownSpells.lua",
    "SharedSettings.lua",
    "Profiles.lua",
    "Events.lua",
    "BossProfiles.lua",
    "BossTimeline.lua",
    "CustomAPL.lua",
    "Analytics.lua",
    "State.lua",
    "SpellFrame.lua",
    "SpellFrameExtras.lua",
    "OptionsIO.lua",
]


def run_smoke() -> bool:
    runtime = lupa.LuaRuntime(unpack_returned_tuples=True)
    execute_file(runtime, TESTS / "mock.lua")
    for name in SMOKE_FILES:
        execute_file(runtime, CORE / name)
    runtime.execute(
        """
        local DH = RotationCore
        local ns = DH.ns
        DH.db = {
            enabled = true,
            common = {
                show_cooldowns_display = true,
                cooldowns_num_icons = 3,
                cooldowns_hide_empty = true,
                cooldowns_scale = 1,
                frames_locked = true,
                show_interrupts_display = true,
                show_timeline_display = true,
            },
            display = {},
        }
        DH.State.playerDead = false
        SMOKE_ERRORS = {}
        for _, c in ipairs({
            { "cooldowns", ns.UpdateCooldownsFrame },
            { "interrupts", ns.UpdateInterruptsFrame },
            { "timeline", ns.UpdateTimelineFrame },
            { "profile export", ns.ShowProfileExportWindow },
            { "profile import", ns.ShowProfileImportWindow },
            { "apl export", ns.ShowAPLExportWindow },
        }) do
            local ok, err = pcall(c[2])
            if not ok then
                SMOKE_ERRORS[#SMOKE_ERRORS + 1] = c[1] .. ": " .. tostring(err)
            end
        end
        """
    )
    errors = runtime.globals().SMOKE_ERRORS
    if errors is not None and len(errors) > 0:
        print("\n[Smoke] FAIL")
        for i in range(1, len(errors) + 1):
            print(f"  {errors[i]}")
        return False
    print("\n[Smoke] windows/import-export: 6 passed")
    return True


def run_suite(class_name: str, class_tag: str, class_files: list[str]) -> tuple[int, int]:
    runtime = lupa.LuaRuntime(unpack_returned_tuples=True)
    execute_file(runtime, TESTS / "mock.lua")
    runtime.execute(
        f"mock.class = {class_name!r}; mock.classTag = {class_tag!r}"
    )

    for name in CORE_FILES:
        execute_file(runtime, CORE / name)
    for name in class_files:
        execute_file(runtime, ROOT / "RotationCore" / name)
    execute_file(runtime, TESTS / "tests.lua")

    summary = runtime.globals().TEST_SUMMARY
    passed = int(summary["passed"])
    failed = int(summary["failed"])
    print(f"\n[{class_name}] {passed} passed, {failed} failed")
    for line in summary["results"].values():
        print(f"  {line}")
    return passed, failed


def main() -> int:
    total_passed = 0
    total_failed = 0
    for class_name, class_tag, files in CLASS_SUITES:
        passed, failed = run_suite(class_name, class_tag, files)
        total_passed += passed
        total_failed += failed

    smoke_ok = run_smoke()
    print(f"\nTotal: {total_passed} passed, {total_failed} failed")
    return 0 if total_passed and not total_failed and smoke_ok else 1


if __name__ == "__main__":
    sys.exit(main())
