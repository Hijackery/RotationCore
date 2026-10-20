# Contributing to RotationCore

Thanks for helping improve RotationCore. This project targets **World of Warcraft
3.3.5a (WotLK)** and is kept intentionally dependency-free and taint-safe.

This is the short contribution guide. For the full technical documentation
(architecture, registration API, simulation model, data conventions) see
[docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md).

## Ways to help

- Report a wrong/missing ability or spell id.
- Improve a class rotation (priority order, talent/glyph handling).
- Add or fix a translation.
- Improve the static checks, CI or docs.

## Ground rules

1. **Verify spell ids** against the 3.3.5a database before adding them:
   `https://wotlkdb.com/?spell=<id>` (secondary: `db.rising-gods.de`,
   `wotlk.cavernoftime.com`).
2. **Localise every user-facing string.** The English string is the base key;
   add it to `RotationCore/RotationCore/Locale.lua` (RU) and the eight mirror
   files (`Locale_deDE`, `Locale_frFR`, `Locale_esES`, `Locale_itIT`,
   `Locale_ptBR`, `Locale_koKR`, `Locale_zhCN`, `Locale_zhTW`).
   `verify.py` fails on key-set drift.
3. **No forbidden APIs.** Do not introduce `C_*`, API 4.0+ calls, `loadstring`,
   `securecallfunction`, Ace3 or any external dependency. The only bundled
   libraries live in `RotationCore/RotationCore/Libs/`.
4. **Keep it taint-safe.** Only the public addon API; never touch secure frames
   or combat-locked state.

## Setup

```bash
pip install -r requirements-dev.txt   # luaparser, lupa
python3 RotationCore/verify.py        # must print: PASS
```

`verify.py` checks:

- every `.lua` file parses;
- locale key parity across all mirrors;
- version consistency between the 11 `.toc` files and `DH.Version`;
- no forbidden API calls.

## Class module layout

```
RotationCore_<Class>/
├── <Class>.lua   abilities / SPELLS constants, buff+debuff+glyph+talent maps,
│                 RegisterAbilityTable, RegisterGlyphs, RegisterBuffs, …
└── Core.lua      per-spec getPriority simulation, initState, onCast,
                  getAdvanceTime, cooldowns
```

Register data through the core API; do not read `DH.db` at file scope.

## Adding or fixing an ability

1. Add the spell id to `SPELLS` in `<Class>.lua` and to the ability table
   (`id`, `name`, optional `texture`).
2. If it applies a buff/debuff/glyph, register it in the matching map.
3. Wire it into the relevant `getPriority` in `Core.lua` with a setting
   (`use_x`) and, if it is on a real cooldown, add it to `cds`/`baseCDs`.
4. Run `verify.py` and test in game with `/rc test rotation` and
   `/rc selfcheck`.

## Release process

1. Bump `DH.Version` in `RotationCore/RotationCore/RotationCore.lua` and
   `## Version:` in all 11 `.toc` files (must match).
2. Add a section to `CHANGELOG.md`.
3. Commit, tag `v<version>`, push the tag. The release workflow verifies, builds
   `RotationCore-<version>.zip` and publishes a GitHub Release.

## Pull requests

- Keep changes focused; describe what and why.
- Include the `verify.py` result in the PR description.
- Screenshots/GIFs are welcome for UI changes.
