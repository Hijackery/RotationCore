# RotationCore

**A rotation helper for World of Warcraft 3.3.5a (WotLK).**

[![CI](https://github.com/Hijackery/RotationCore/actions/workflows/ci.yml/badge.svg)](https://github.com/Hijackery/RotationCore/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Hijackery/RotationCore?sort=semver)](https://github.com/Hijackery/RotationCore/releases)
[![Downloads](https://img.shields.io/github/downloads/Hijackery/RotationCore/total)](https://github.com/Hijackery/RotationCore/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![WoW](https://img.shields.io/badge/WoW-3.3.5a-orange.svg)](#compatibility)
[![Locales](https://img.shields.io/badge/locales-12-blue.svg)](#compatibility)

**English** · [Русский](./README.ru.md)

---

RotationCore watches your spec, talents, resources and target, then highlights
the next ability to press. It is **class-modular** — a small core plus one
LoadOnDemand module per class — and is built for reliability: no insecure API,
no taint, no external dependencies beyond the bundled libraries.

> **At a glance:** 10 classes · 29 specs · 12 locales · static verification,
> CI and automated releases on every tag.

## Contents

- [Quick start](#quick-start)
- [Screenshots](#screenshots)
- [Features](#features)
- [Supported classes & specs](#supported-classes--specs)
- [How it works](#how-it-works)
- [Slash commands](#slash-commands)
- [FAQ](#faq)
- [Compatibility](#compatibility)
- [Development](#development)
- [License](#license)

## Quick start

1. Download the latest `RotationCore-<version>.zip` from
   [**Releases**](https://github.com/Hijackery/RotationCore/releases).
2. Extract it into `World of Warcraft/Interface/AddOns/` so the folders land as
   `AddOns/RotationCore` and `AddOns/RotationCore_<Class>`.
3. Enable **Load out of date AddOns** (Interface `30300`).
4. Type `/rc` in game to open the options window, or `/rc wizard` for guided
   setup.

No configuration is required — the addon detects your spec and works out of the
box.

## Screenshots

<!-- Replace with real images (docs/screenshots/). Suggested shots:
     icon window + glow, cooldowns window, DPS forecast, options window. -->

| Icon window & glow | Cooldowns & interrupts | Options |
|:---:|:---:|:---:|
| _screenshot_ | _screenshot_ | _screenshot_ |

## Features

### Core rotation
- **Action-bar highlight** with priority colours and glow styles (pulse /
  static / flash / rainbow), plus colour-blind friendly palettes.
- **Icon window** with your top recommendations, keybind overlay, target-mode
  indicator (S / A / Au) and an idle reason when there is nothing to do.
- **Live DPS forecast** above the icon window (`~5200 DPS` plus actual DPS and
  loss %) while in combat.
- **Cooldowns window** (ready-first ordering, configurable minimum CD).
- **Interrupt window** that reacts the moment your target starts casting.
- **Boss timeline** from DBM / BigWigs (works without them too): `Hold CD` /
  `Prepare` / `BURST` hints and optional phase-based target-mode switching.

### Guidance & learning
- **Class pulse** — green/yellow/red execution quality (cast accuracy, DoT
  uptime, cooldown usage).
- **Mentor mode** — explains mistakes after N in a row.
- **Exam mode** — no action-bar glow, only REC1 shown, accuracy report.
- **Training mode** — keeps recommending on a dummy and explains *why*.
- **Adaptive rotation** — `simple` / `normal` / `complex` chosen from average
  item level.
- **Learning stats** — per-fight accuracy / DPS history (`/rc learning`).
- **Coach hub** (`/rc hub`) — status/grade, cooldown plan, fight breakdown
  (`/rc analyze`), simulator (`/rc sim`), APL editor (`/rc apl edit`), talent
  check (`/rc talents`) and a group-health monitor.

### Automation & customisation
- **Custom APL** — a plain-text priority list (`/rc apl import`) that replaces
  the class rotation; export and one-line share via `/rc apl share`.
- **Boss profiles** — per-encounter setting overrides (ICC / ToC / Ulduar /
  Naxx / RS presets).
- **Per-spec profiles** and **text import / export** (safe parser, no code
  execution).
- **PvP mode** — interrupt > control > burst > survival priority branch.
- **Healer assist** — recommends a heal for the lowest-HP group member from
  per-class heal sets, plus a group-health monitor.
- **Heal-spec DPS** — borrows the class DPS rotation while healing.
- **Themes** — Class colour (default), Dark, Light, High contrast; compact icon
  window; unified window font with a large/readable mode.
- **Panel configuration** (Dominos-style) — grid with highlights, click a window
  to configure it, snap-to-grid while dragging.
- **Background styles** (rounded / glass / matte), custom window font + title
  shadow and animated window fades.
- **Extras** — DoT/debuff panel, enemy counter, resource-cap warnings, racial
  cooldowns, melee swing timer, timeline bars, end-of-fight report (off by
  default, boss-only when enabled).
- **Setup Wizard** and **option tooltips** for every control.

## Supported classes & specs

| Class | Specs | Notes |
|-------|-------|-------|
| Death Knight | Blood · Frost · Unholy | DPS rotations |
| Druid | Balance · Feral (Cat) · Feral (Bear) | + healer assist |
| Hunter | Beast Mastery · Marksmanship · Survival | pet handling, aspect dance |
| Mage | Arcane · Fire · Frost | |
| Paladin | Retribution · Protection · Holy (DPS) | + healer assist |
| Priest | Shadow · Discipline · Holy | + healer assist |
| Rogue | Assassination · Combat · Subtlety | |
| Shaman | Elemental · Enhancement | + healer assist |
| Warlock | Affliction · Demonology · Destruction | |
| Warrior | Arms · Fury · Protection | |

## How it works

```
RotationCore/                 core: engine, state, options, UI, localization
RotationCore_<Class>/         one LoadOnDemand module per class
  ├── <Class>.lua             abilities, spell ids, buffs/debuffs, glyphs, talents
  └── Core.lua                per-spec priority simulation
```

Every class module registers its data through a small registration API
(`RegisterAbilityTable`, `RegisterGlyphs`, `RegisterBuffs`, `RegisterTalentMap`,
…). The core runs a short forward simulation each frame to pick the next action,
respecting target mode, cooldowns, resources and fight length. All spell ids are
cross-checked against the official 3.3.5a database.

## Slash commands

| Command | Action |
|---------|--------|
| `/rc` / `/rc close` / `/rc help` | Open / close options · open Help |
| `/rc wizard` / `/rc help full` | Setup Wizard |
| `/rc toggle` | Enable / disable the addon |
| `/rc profile <n>` · `/rc profile copy <from> to <to>` | Profiles |
| `/rc spec <name>` | Pick a build (no name lists them) |
| `/rc pause` | Freeze recommendations (toggle) |
| `/rc move` / `/rc lock` | Move / lock the icon window |
| `/rc train` · `/rc pvp` · `/rc exam` · `/rc mentor` | Mode toggles |
| `/rc dps` · `/rc timeline` · `/rc palette <name>` · `/rc layout <preset>` | Display |
| `/rc apl import\|export\|share\|clear\|enable\|disable` | Custom APL |
| `/rc learning [graph\|export\|clear]` | Learning statistics |
| `/rc boss …` | Boss-profile management |
| `/rc stats` · `/rc stats dps` · `/rc stats reset` · `/rc log [dump\|clear]` | Analytics |
| `/rc test rotation` · `/rc selfcheck` | Self-tests (in-game) |
| `/rc hub` · `/rc sim` · `/rc analyze` · `/rc talents` | Coach tools |

## FAQ

**Does it play the game for me?**
No. It only highlights the next ability on your bars/icon window; you still
press every button.

**Will it work without DBM/BigWigs?**
Yes. The boss timeline degrades gracefully; DBM/BigWigs add precise timers.

**Does it support private-server custom spell ids?**
The shipped data targets the official 3.3.5a ids. For custom servers use the
custom APL (`/rc apl`) or override ids in the class module.

**Is my data safe?**
Settings are stored in `RotationCoreDB` (SavedVariables). Profile import uses a
hand-written parser — no `loadstring`, no code execution.

**Why is a spell missing?**
Report it with the spell id from `https://wotlkdb.com/?spell=<id>` in a
[bug report](https://github.com/Hijackery/RotationCore/issues/new/choose).

## Compatibility

- Interface **30300** (3.3.5a). No `C_*` / API 4.0+ calls, no Ace3, no
  `loadstring` on user input.
- One LoadOnDemand module per class (`RotationCore_<Class>`); no external
  libraries beyond the bundled `Libs/`.
- Locales: enUS/enGB (base), ruRU, deDE, frFR, esES/esMX, ptBR, itIT, koKR,
  zhCN, zhTW — all 12 official WotLK 3.3.5a locales.
- **Static verification:** `python3 RotationCore/verify.py` (parse, locale
  parity, version consistency, forbidden-API scan). In-game: `/rc selfcheck`.

## Development

See [CONTRIBUTING.md](./CONTRIBUTING.md). Static checks (no WoW client needed):

```bash
pip install -r requirements-dev.txt
python3 RotationCore/verify.py
```

CI runs the same checks on every push and pull request. Releases are automated:
push a `v<version>` tag and the pipeline verifies, builds the zip and publishes
a GitHub Release.

## License

MIT — see [LICENSE](./LICENSE).
