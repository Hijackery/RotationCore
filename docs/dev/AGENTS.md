# AGENTS.md — RotationCore

Guidance for agents working in this repository.

## Product intent (out-of-the-box)

- The addon must work **out of the box on every encounter** (all raids and
  5-man dungeons) with sensible defaults. The Setup Wizard must not force the
  user through optional/fine-grained choices.
- **Automate first, ask never.** Most main settings must be auto-detected
  (spec, build, activity, target mode, boss profile, UI shell, skin, glow).
  Even boss presets apply automatically. Manual options exist only for deep
  personalization.
- Keep the default profile fully functional without opening the options.

## Standing rules (ALWAYS apply to new or changed features)

1. **Update Help** (`Options.lua` -> `BuildHelp`) whenever a feature is added,
   renamed, moved or removed. Help must match the actual tabs/settings.
2. **Localize everything.** Every user-facing string goes through `L(...)` and
   has an entry in `Locale.lua` (RU) plus all 8 mirror files. This includes
   **tooltips** (`tooltip_<slug>_title/_desc/_default/_affects`). Never ship
   English text that can appear on a non-English client.
3. **No technical/debug clutter in player-facing tabs.** Raw keys, internal
   flags, format strings and developer diagnostics belong in the Status/
   Diagnostics area or the slash commands, never in normal tabs or Help.
4. Prefer plain, player-facing wording; hide internal identifiers.

## Localization policy

- RU (`Locale.lua`) is the source of truth and must be complete.
- All 8 mirrors (`deDE/frFR/esES/itIT/ptBR/koKR/zhCN/zhTW`) are translated.
  Only genuine cognates, acronyms, units and format strings may stay identical
  to English (`Auto`, `DPS`, `GCD`, `DoT`, `PvP`, `%s`, `/rc ...`).
- `verify.py` enforces RU<->mirror key parity; run it after editing locales.

## Conventions

- 3.3.5a API only (no `C_*`, no retail APIs). Allowed list is in the project
  audit. No file I/O; persistence is SavedVariables only.
- No code comments unless asked.
- Run `python3 verify.py` (from `RotationCore/`) and `/tmp/dkrec/opts_test.py`
  (from repo root) after changes.
