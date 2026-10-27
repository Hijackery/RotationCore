# RotationCore

**A rotation helper for World of Warcraft 3.3.5a (WotLK).**

[![CI](https://github.com/Hijackery/RotationCore/actions/workflows/ci.yml/badge.svg)](https://github.com/Hijackery/RotationCore/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Hijackery/RotationCore?sort=semver)](https://github.com/Hijackery/RotationCore/releases)
[![Downloads](https://img.shields.io/github/downloads/Hijackery/RotationCore/total)](https://github.com/Hijackery/RotationCore/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![WoW](https://img.shields.io/badge/WoW-3.3.5a-orange.svg)](https://github.com/Hijackery/RotationCore)
[![Languages](https://img.shields.io/badge/languages-12-blue.svg)](#supported-classes--specs)

**English** · [Русский](./README.ru.md)

---

RotationCore watches your spec, talents, resources and target, then highlights
the next ability to press. It works out of the box and needs no setup.

> **10 classes · 29 specs · 12 languages**

## Contents

- [Quick start](#quick-start)
- [Screenshots](#screenshots)
- [Features](#features)
- [Supported classes & specs](#supported-classes--specs)
- [Slash commands](#slash-commands)
- [FAQ](#faq)
- [License](#license)

## Quick start

1. Download the latest `RotationCore-<version>.zip` from
   [**Releases**](https://github.com/Hijackery/RotationCore/releases).
2. Extract it into `World of Warcraft/Interface/AddOns/` so the folders land as
   `AddOns/RotationCore` and `AddOns/RotationCore_<Class>`.
3. Enable **Load out of date AddOns** in the addon list.
4. Type `/rc` in game to open the options window, or `/rc wizard` for guided
   setup.

## Screenshots

<!-- Replace with real images (docs/screenshots/). Suggested shots:
     icon window + glow, cooldowns window, DPS forecast, options window. -->

| Icon window & glow | Cooldowns & interrupts | Options |
|:---:|:---:|:---:|
| _screenshot_ | _screenshot_ | _screenshot_ |

## Features

### Rotation
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
- **Class pulse**: green/yellow/red execution quality (cast accuracy, DoT
  uptime, cooldown usage).
- **Mentor mode**: explains mistakes after N in a row.
- **Exam mode**: no action-bar glow, only REC1 shown, accuracy report.
- **Training mode**: keeps recommending on a dummy and explains *why*.
- **Adaptive rotation**: adapts to your average item level.
- **Learning stats**: per-fight accuracy / DPS history (`/rc learning`).
- **Coach hub** (`/rc hub`): status/grade, cooldown plan, fight breakdown
  (`/rc analyze`), simulator (`/rc sim`), APL editor (`/rc apl edit`), talent
  check (`/rc talents`) and a group-health monitor.

### Automation & customisation
- **Custom rotation**: a plain-text priority list (`/rc apl import`) that
  replaces the built-in rotation; export and share it in one line.
- **Boss profiles**: per-encounter setting overrides (ICC / ToC / Ulduar /
  Naxx / RS presets).
- **Per-spec profiles** and text import / export.
- **PvP mode**: interrupt > control > burst > survival priority branch.
- **Healer assist**: recommends a heal for the lowest-HP group member, plus a
  group-health monitor.
- **Heal-spec DPS**: keeps doing damage while healing.
- **Themes**: Class colour (default), Dark, Light, High contrast; compact icon
  window; large/readable text.
- **Panel configuration** (Dominos-style): click a window to configure it,
  snap-to-grid while dragging.
- **Background styles** (rounded / glass / matte), custom fonts and animations.
- **Extras**: DoT/debuff panel, enemy counter, resource-cap warnings, racial
  cooldowns, melee swing timer and timeline bars.
- **Setup Wizard** and **tooltips** for every option.

## Supported classes & specs

| Class | Specs |
|-------|-------|
| Death Knight | Blood · Frost · Unholy |
| Druid | Balance · Feral (Cat) · Feral (Bear) |
| Hunter | Beast Mastery · Marksmanship · Survival |
| Mage | Arcane · Fire · Frost |
| Paladin | Retribution · Protection · Holy |
| Priest | Shadow · Discipline · Holy |
| Rogue | Assassination · Combat · Subtlety |
| Shaman | Elemental · Enhancement |
| Warlock | Affliction · Demonology · Destruction |
| Warrior | Arms · Fury · Protection |

## Slash commands

| Command | Action |
|---------|--------|
| `/rc` / `/rc close` | Open / close options |
| `/rc help` · `/rc wizard` | Help · Setup Wizard |
| `/rc toggle` | Enable / disable the addon |
| `/rc profile <n>` | Switch profile |
| `/rc spec <name>` | Pick a build |
| `/rc pause` | Freeze recommendations |
| `/rc move` / `/rc lock` | Move / lock the icon window |
| `/rc train` · `/rc pvp` · `/rc exam` · `/rc mentor` | Mode toggles |
| `/rc dps` · `/rc timeline` · `/rc palette <name>` · `/rc layout <preset>` | Display |
| `/rc apl …` | Custom rotation |
| `/rc learning` | Learning statistics |
| `/rc boss …` | Boss profiles |
| `/rc stats` · `/rc log` | Analytics |
| `/rc hub` · `/rc sim` · `/rc analyze` · `/rc talents` | Coach tools |
| `/rc selfcheck` | Self-test (PASS/FAIL) |

## FAQ

**Does it play the game for me?**
No. It only highlights the next ability: you press every button yourself.

**Will it work without DBM/BigWigs?**
Yes. The boss timeline works on its own; DBM/BigWigs add precise timers.

**Is my data safe?**
Yes. Settings are stored locally by the game and never leave your client.

**Why is a spell missing or wrong?**
Open a [bug report](https://github.com/Hijackery/RotationCore/issues/new/choose)
with the spell name and your class/spec.

**Does it work on private servers?**
It targets the standard 3.3.5a game data and works on private servers running
3.3.5a. For custom abilities you can define your own rotation with `/rc apl`.

## License

MIT. See [LICENSE](./LICENSE).

---

Contributions are welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md). For the
technical guide, see [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md).
