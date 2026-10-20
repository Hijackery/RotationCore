# RotationCore

[![CI](https://github.com/Hijackery/RotationCore/actions/workflows/ci.yml/badge.svg)](https://github.com/Hijackery/RotationCore/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Hijackery/RotationCore?include_prereleases&sort=semver)](https://github.com/Hijackery/RotationCore/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![WoW](https://img.shields.io/badge/WoW-3.3.5a-orange.svg)](https://github.com/Hijackery/RotationCore)

**RU:** [README.ru.md](./README.ru.md)

Priority rotation helper for **World of Warcraft 3.3.5a (WotLK)**, v1.0.0.

The addon watches your spec, talents, resources and target, then highlights the
next ability to use. It is class-modular: a small core plus one LoadOnDemand
module per class.

## Install

1. Copy the `RotationCore` folder and the `RotationCore_<Class>` folders you
   need into `World of Warcraft/Interface/AddOns/`.
2. Make sure "Load out of date AddOns" is enabled (Interface 30300).
3. `/rc` opens the options window.

## Features

- **Rotation highlight** on action bar buttons with priority colors and glow
  styles (pulse / static / flash / rainbow), plus a colour-blind-friendly
  palette (Display → Highlight).
- **Icon window** with your top recommendations, keybind overlay, target-mode
  indicator (S / A / Au) and an idle reason when there is nothing to do.
- **Live DPS forecast** above the icon window (`~5200 DPS` plus actual DPS and
  loss %) while in combat.
- **Class pulse** — a green/yellow/red indicator of how well you are executing
  (cast accuracy, DoT uptime, cooldown usage).
- **Cooldowns window** (ready-first ordering, configurable minimum CD).
- **Interrupt window** that reacts the moment your target starts casting.
- **Boss timeline** from DBM / BigWigs (works without them too): `Hold CD` /
  `Prepare` / `BURST` hints and optional phase-based target-mode switching.
- **Custom APL** — a plain-text priority list (`/rc apl import`) that replaces
  the class rotation; export and one-line share via `/rc apl share`.
- **Exam mode** — no action-bar glow, only REC1 shown, accuracy report.
- **Mentor mode** — explains your mistakes after N in a row.
- **Adaptive rotation** — `simple` / `normal` / `complex` chosen automatically
  from your average item level.
- **Learning stats** — per-fight accuracy / DPS history (`/rc learning`).
- **Boss profiles** — per-encounter setting overrides (ICC/ToC/Ulduar/Naxx/RS
  presets).
- **Healer assist** (`/rc` > Healer tab): recommends a heal for the lowest-HP
  group member from per-class heal sets; plus a group health monitor. The tab
  is listed for every class but only healer classes can edit it.
- **Extras** (Advanced): DoT/debuff panel with class key-DoT marking, enemy
  counter, resource-cap warnings, racial cooldowns, melee swing timer,
  timeline bars and an end-of-fight report.
- **Themes**: Class colour (default), Dark, Light, High contrast; compact icon
  window; unified window font with a large/readable mode.
- **Panel configuration** (Dominos-style): a grid with highlights; click a
  window to configure it, snap-to-grid while dragging.
- **Background styles** (rounded / glass / matte), custom window font + title
  shadow, glass slot edges and animated window fades.
- **Coach hub** (`/rc hub`): status/grade, cooldown plan, fight breakdown
  (`/rc analyze`), analytics history; **simulator** (`/rc sim`), **APL editor**
  (`/rc apl edit`), **talent check** (`/rc talents`), **group health monitor**;
  public API (`DH:SetRecommendationCallback`).
- **Setup Wizard** for guided configuration.
- **Option tooltips** for every control (checkbox, slider, dropdown, button),
  with a localised label fallback.
- **Profile import / export** as plain text (safe custom parser, no code
  execution) and **per-specialization settings**.
- **Training mode** - keeps recommending on a dummy and explains *why*.
- **Heal-spec DPS** - borrows your class DPS rotation while healing.
- **PvP mode** - interrupt > control > burst > survival priority branch.
- **Aggregate / per-fight analytics**: `/rc stats`, `/rc stats dps`, `/rc log`.
- **Localisation**: RU base coverage for the UI, tooltips and `/rc <class>`
  status output (EN fallback; parity-checked across all 8 mirrors).

## Hotkeys

| Binding       | Action        |
|---------------|---------------|
| ALT-SHIFT-L   | Training mode |
| ALT-SHIFT-V   | PvP mode      |
| ALT-SHIFT-E   | Exam mode     |
| ALT-SHIFT-M   | Mentor mode   |

Bind them, plus **Open settings** and **Panel configuration**, under
**Key Bindings > RotationCore**.

## Slash commands

| Command            | Action                                   |
|--------------------|------------------------------------------|
| `/rc`              | Open the options window                  |
| `/rc close`        | Close the options window                 |
| `/rc help`         | Open the Help tab                        |
| `/rc help full`    | Open the Setup Wizard                    |
| `/rc toggle`       | Enable / disable the addon               |
| `/rc profile <n>`  | Switch profile                           |
| `/rc profile copy <from> to <to>` | Copy a profile                  |
| `/rc move` / `lock`| Move / lock the icon window              |
| `/rc train`        | Toggle training mode                     |
| `/rc pvp`          | Toggle PvP mode                          |
| `/rc exam`         | Toggle exam mode                         |
| `/rc mentor`       | Toggle mentor mode                       |
| `/rc dps`          | Toggle the DPS forecast                  |
| `/rc apl import|export|share|clear|enable|disable` | custom APL management |
| `/rc learning [graph|export|clear]` | learning statistics      |
| `/rc spec <name>`  | Pick a build (no name lists them)        |
| `/rc pause`        | Freeze recommendations (toggle)          |
| `/rc test rotation`| Self-test the current rotation            |
| `/rc selfcheck`    | Run in-game invariant tests (PASS/FAIL)   |
| `/rc timeline`     | Toggle the boss timeline                 |
| `/rc palette <name>`| Set the color palette                  |
| `/rc layout <preset>`| Apply a display layout                 |
| `/rc boss ...`     | Boss-profile management                  |
| `/rc log [dump|clear]` | decision log                          |
| `/rc stats`, `/rc stats dps`, `/rc stats reset` | analytics         |
| `/rc wizard`       | Run the Setup Wizard                     |
| `/rc debug spec`   | Show active / primary / fallback spec    |
| `/rc glow / size / numbers / pulse / frame / test / status / live / debug` | utility |

## Settings highlights

- `menu_mode` - Simple / Advanced menus.
- `colorblind_mode` - orange/blue/grey priority palette.
- `interrupt_ready_sound` - play a sound when the kick is ready.
- `dot_panel_enabled`, `swing_timer_enabled`, `enemy_count_enabled`,
  `resource_warning_enabled`, `use_racial_cooldowns`, `session_report_enabled`,
  `timeline_bars_enabled` - Extras.
- `spellframe_compact`, `ui_font`, `ui_font_large` - window look.
- `color_palette`, `color_custom` - priority colors / accessibility palettes.
- `animations_enabled`, `animation_speed` - icon transitions.
- `display_layout` - `center` / `side` / `minimal` / `raid` / `custom`.
- `timeline_enabled`, `timeline_show_burst`, `timeline_auto_phase`,
  `timeline_burst_window`.
- `dps_forecast_enabled`, `dps_forecast_position` (+ Class pulse, positions).
- `exam_mode`, `mentor_mode`, `mentor_error_threshold`.
- `adaptive_rotation`, `ilvl_threshold_simple`, `ilvl_threshold_complex`.
- `learning_stats_enabled`, `learning_stats_max_sessions`.
- `custom_apl_enabled`, `custom_apl`.
- `build_detect_mode` - `talents` / `talents_glyphs` / `talents_glyphs_stats`.
- `show_tooltips`, `tooltip_delay` - option tooltips.
- `training_mode`, `training_chat_output`, `training_sound`.
- `heal_dps_mode` - Auto / On / Off.
- `pvp_mode_enabled`, `pvp_burst_threshold`.
- `show_cooldowns_display`, `cooldowns_min_cd`, `cooldowns_scale` (resizable window).
- `spec_profiles_enabled`, `profile_export_enabled`.
- `auto_reload_on_talent_change`.

## Compatibility

- Interface **30300** (3.3.5a). No `C_*` / API 4.0+ calls, no Ace3, no
  `loadstring` on user input (APL and profiles use safe hand-written parsers).
- One LoadOnDemand module per class (`RotationCore_<Class>`), no external
  libraries beyond the bundled Libs.
- Locales: enUS/enGB (base), ruRU, deDE, frFR, esES/esMX (one file serves
  both Spanish variants), ptBR, itIT, koKR, zhCN, zhTW — all 12 official
  WotLK 3.3.5a locales.
- **Static verification**: run `python3 verify.py` in this folder (luaparser,
  locale parity, version check, forbidden-API scan). In-game analogue:
  `/rc selfcheck`.

## License

MIT — see [LICENSE](./LICENSE).

## Screenshots

<!-- Add screenshots of the icon window, cooldowns window and options here.
     Example:
     ![Icon window](docs/screenshots/icon-window.png)
-->

## Development

The addon source lives in `RotationCore/`:

```
RotationCore/
├── RotationCore/               # core (engine, state, options, UI)
├── RotationCore_<Class>/       # one LoadOnDemand module per class
└── verify.py                   # static verification harness
```

Static checks (no WoW client needed):

```bash
pip install luaparser
python3 RotationCore/verify.py
```

`verify.py` checks Lua parse, locale key parity across all mirrors, version
consistency between the 11 `.toc` files and `DH.Version`, and scans for
forbidden API calls (`C_*`, `loadstring`, …). CI runs the same script on every
push and pull request.

### Cutting a release

1. Bump `DH.Version` in `RotationCore/RotationCore/RotationCore.lua` and
   `## Version:` in all 11 `.toc` files (keep them identical — `verify.py`
   enforces this).
2. Add a section to `CHANGELOG.md`.
3. Commit, then tag and push:

   ```bash
   git tag v1.0.0
   git push origin main v1.0.0
   ```

The release workflow re-runs verification, builds
`RotationCore-<version>.zip` (folders ready to drop into `Interface/AddOns/`)
and publishes a GitHub Release with notes taken from `CHANGELOG.md`.

### Contributing

- New spell / ability ids must be verified against the 3.3.5a database
  (`https://wotlkdb.com/?spell=<id>`).
- Every user-facing string must be localised (EN base + the 8 mirror files);
  `verify.py` fails on key-set drift.
- Do not introduce `C_*` / API 4.0+ calls, `loadstring`, or external
  dependencies beyond the bundled `Libs/`.