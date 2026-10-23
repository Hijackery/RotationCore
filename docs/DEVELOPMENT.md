# RotationCore Developer Guide

This is the technical guide for working on RotationCore. For the user-facing
overview see [README.md](../README.md); for the contribution workflow see
[CONTRIBUTING.md](../CONTRIBUTING.md).

- **Target:** World of Warcraft 3.3.5a (WotLK), Interface `30300`.
- **Language:** Lua 5.1 (WoW client sandbox). No external runtime dependencies.
- **Source root:** [`RotationCore/`](../RotationCore).

---

## 1. Repository layout

```
RotationCore/
├── RotationCore/                    core addon
│   ├── RotationCore.toc             load order + SavedVariables
│   ├── RotationCore.lua             engine, registration API, events
│   ├── State.lua                    live state (buffs, debuffs, glyphs, talents)
│   ├── Options.lua                  options window (Simple/Advanced)
│   ├── Wizard.lua                   Setup Wizard
│   ├── UI.lua                       icons, highlights, windows, fonts/sounds
│   ├── SpellFrame.lua               action-bar glow
│   ├── Extras.lua                   DoT panel, swing timer, fight report…
│   ├── Hub.lua / Heal.lua           coach hub, healer assist
│   ├── SpellNames.lua               spell-id → name helpers
│   ├── Locale.lua                   EN base + RU; 8 mirror Locale_*.lua
│   └── Libs/                        LibStub, CallbackHandler, LibDataBroker,
│                                    LibDBIcon, LibClassicSpecs
├── RotationCore_<Class>/            one LoadOnDemand module per class
│   ├── RotationCore_<Class>.toc
│   ├── <Class>.lua                  data: abilities, SPELLS, maps, detectors
│   └── Core.lua                     per-spec priority simulation
└── verify.py                        static verification harness
```

The class modules are `LoadOnDemand: 1` and depend on `RotationCore`. The core
loads a module with `DH:LoadClassModule()` when the player's class is detected.

---

## 2. Architecture

### 2.1 Core engine (`RotationCore.lua`)

- Namespace: `RotationCore` (`DH`) and internal `DH.ns`.
- `DH.Version` must equal the `## Version:` of all 11 `.toc` files.
- Registration API. Class modules call these at file scope:

  | Function | Purpose |
  |---|---|
  | `DH:RegisterAbilityTable()` | index `class.abilities` by name, resolve textures |
  | `DH:RegisterCooldowns(t)` / `RegisterBaseCDs(t)` | cooldown keys / base durations |
  | `DH:RegisterGlyphs(t)` | glyph spell-id → key |
  | `DH:RegisterBuffs(list)` / `RegisterDebuffs(list)` | tracked aura keys |
  | `DH:RegisterBuffMap(t)` / `RegisterDebuffMap(t)` | aura spell-id → key |
  | `DH:RegisterExternalDebuffMap(t)` | other-class debuffs (e.g. Sunder) |
  | `DH:RegisterTalentMap(t)` | talent positions → key |
  | `DH:RegisterSpecDetector(fn)` | returns the active spec key |
  | `DH:RegisterDefaults(t)` / `RegisterCommonDefaults(extras)` | settings defaults |
  | `DH:RegisterDefensiveAbility(key)` | one defensive pushed in "defensive" phase |
  | `DH:RegisterProcBuff(key, opts)` | play a sound on the buff's rising edge |
  | `DH:RegisterSnoozeable(key, sec)` | suppress a skipped cooldown |

- `DH:RunSimulation(state, config)` runs the priority simulation for a spec
  `config` (`getPriority`, `initState`, `onCast`, `getAdvanceTime`, `cds`,
  `baseCDs`, `auras`).
- `DH:CanUseCooldown(sim, key, setting)` enforces `auto_cooldowns`,
  `cooldown_order == "manual"`, the "simple" complexity rule for long CDs and
  `IsAbilityKnown`. **Do not** wrap core rotation abilities in it; gate those
  with `DH:GetSetting("use_x")` directly.
- `DH:PickKnownAction` calls `config.getPriority`, then requires
  `IsAbilityKnown`; `config.onCast(sim, action)` is called every loop (use it to
  flip sim flags such as `sim.seal_up` to avoid repeat recommendations).

### 2.2 State (`State.lua`)

`State:Update...` fills the table passed to rotations:

- `s.mana`: `{ current, max, pct, regen }` from `UnitPower("player", 0)`.
- `s.buff[key]`: `{ up, stacks, remains }`; seeded from `RegisterBuffs`, mapped
  by `buffMap`, with a name-pattern fallback. `expirationTime == 0` is treated
  as permanent (≈2h).
- `s.debuff[key]`: same model for target debuffs.
- `s.glyph[key]`: `{ enabled }`; resolved by direct spell-id lookup, then by
  glyph-name fallback.
- `s.talent[key].rank`: from `GetTalentInfo` (rank index **5**).
- `s.spec`, `s.ttd`, `s.in_execute`, `s.battle_phase`, etc.

3.3.5a API notes: `GetTalentTabInfo(tab).pointsSpent` is index **3**;
`GetTalentInfo` rank index **5**; GCD is 1.5 s (1.0 s melee). Do **not** use
`C_*`, `loadstring`, `securecallfunction`, `GetSpecialization*`, or any API
newer than 3.3.5a.

### 2.3 UI (`UI.lua`, `SpellFrame.lua`, `Options.lua`)

- The options window is created lazily and rebuilt on any setting change
  (`DH:RefreshOptions`). Widgets never read the DB at file scope.
- Layout tokens: 8 px grid, `AddRow(h)`, `AddCheckbox`, `AddSlider`,
  `AddDropdown`, `AddScrollList`, `AddButton`, `AddColorRow`, `AddInfo`.
- Use `L(text)` / `ContentFS(...)` for every visible string (localisation).
- Frames use `BackdropTemplate` and theme colours from `DH:GetUITheme()`.

---

## 3. Class module anatomy

### 3.1 `<Class>.lua` (data)

```lua
local DH = RotationCore
local ns = DH.ns
local SPELLS = {
    -- spell ids verified against https://wotlkdb.com/?spell=<id>
}
ns.SPELLS = SPELLS

DH.Class = DH.Class or {}
DH.Class.abilities = {
    ability_key = { id = SPELLS.X, name = "Ability Name", texture = 123456 },
    -- texture is optional; RegisterAbilityTable resolves it from the id
}

DH:RegisterCooldowns({ ability_key = "ability_key" })
DH:RegisterBaseCDs({ ability_key = 30 })
DH:RegisterGlyphs({ [glyphId] = "glyph_key" })
DH:RegisterBuffs({ "buff_key" })
DH:RegisterDebuffs({ "debuff_key" })
DH:RegisterBuffMap({ [spellId] = "buff_key" })
DH:RegisterDebuffMap({ [spellId] = "debuff_key" })
DH:RegisterExternalDebuffMap({ [47467] = "sunder_armor" })
DH:RegisterTalentMap({ { tab, position, "talent_key" } })
DH:RegisterAbilityTable()
DH:RegisterDefaults({ spec_key = { enabled = true, use_x = true, ... } })
DH:RegisterCommonDefaults()
DH:RegisterSpecDetector(function() ... end)
```

### 3.2 `Core.lua` (simulation)

```lua
local config = {
    gcdType = "spell",          -- "spell" | "melee"
    maxRecs = 3,
    allowDupes = true,
    cds = { ability_key = "ability_key" },
    baseCDs = { ability_key = 30 },
    auras = { { up = "dot_up", remains = "dot_remains" } },
    initState = function(sim, s)
        sim.dot_up = s.debuff.dot.up
        sim.mana_pct = s.mana.pct
        sim.spec_rank = s.talent.some_talent.rank
    end,
    getPriority = function(sim, recs)
        if DH:IsCleave(sim) and sim:ready("aoe") then return "aoe" end
        if DH:GetSetting("use_x") and sim:ready("x") then return "x" end
        return "filler"
    end,
    onCast = function(sim, key)
        if key == "dot" then sim.dot_up = true; sim.dot_remains = 15 end
    end,
    getAdvanceTime = function(sim, action)
        if action == "off_gcd_ability" then return 0 end
        return sim.gcd
    end,
}
```

`getPriority` returns the next ability key (or `nil`). `sim:ready(key)` checks
the simulated cooldown. Off-GCD abilities should return `0` from
`getAdvanceTime`.

---

## 4. Data conventions

- **Spell ids:** verify every id against the 3.3.5a database
  (`https://wotlkdb.com/?spell=<id>`, secondary `db.rising-gods.de`,
  `wotlk.cavernoftime.com`). Wrong ids silently break buff/glyph detection.
- **Glyphs:** detection is by spell id first, then glyph name. A wrong glyph id
  is a real bug (the name fallback may hide it on one locale only).
- **Buffs/debuffs:** each rank needs its own map entry; do not use a rank for a
  different spell.
- **Talents:** positions are `{tab, talentIndex, key}`; keep keys unique and
  positions within the tree.
- **Cosmetic name mismatches** (e.g. a proc whose DB name differs from the key)
  are harmless; the key is internal.

---

## 5. Localisation

- `Locale.lua`: `tooltips` is the EN base; a `local ru = { ... }` table is
  merged with `rawset(DH.L, k, v)`.
- Each mirror `Locale_<code>.lua` has `local T = { ... }` and the same merge
  loop. Supported: ruRU, deDE, frFR, esES, itIT, ptBR, koKR, zhCN, zhTW.
- All 8 mirrors must have **the same key set as RU**; `verify.py` enforces this.
- Add every user-facing string: options labels, tooltips (`tooltip_<key>_title`
  / `_desc`), Help, slash output, error banner.
- Only cognates, acronyms, units and format strings may stay identical to EN.

---

## 6. Verification & CI

```bash
pip install -r requirements-dev.txt
python3 RotationCore/verify.py      # must print PASS
```

`verify.py` checks:

1. every `.lua` parses (`luaparser`);
2. locale key parity across all mirrors;
3. version consistency between all 11 `.toc` files and `DH.Version`;
4. forbidden API scan (`C_*`, `loadstring`, `securecallfunction`, Ace3, …).

CI (`.github/workflows/ci.yml`) additionally compiles every Lua file with
`lupa` (compile-only) and runs a dry-run release build.

In-game checks: `/rc selfcheck`, `/rc test rotation`. See
[TEST_CHECKLIST.md](./dev/TEST_CHECKLIST.md) for the manual QA matrix.

---

## 7. Release process

1. Bump `DH.Version` in `RotationCore/RotationCore/RotationCore.lua` **and**
   `## Version:` in all 11 `.toc` files (identical; `verify.py` enforces it).
2. Add a section to `CHANGELOG.md`.
3. Commit, tag `v<version>`, push the tag:

   ```bash
   git tag v<version>
   git push origin main v<version>
   ```

`.github/workflows/release.yml` re-runs verification, checks the tag against the
`.toc` version, builds `dist/RotationCore-<version>.zip` via
`scripts/build_release.py`, extracts the matching `CHANGELOG.md` section as
release notes and publishes a GitHub Release with the zip attached.

Build locally:

```bash
python3 scripts/build_release.py    # → dist/RotationCore-<version>.zip
```

---

## 8. Design notes & known limits

- **One defensive key per class** (`RegisterDefensiveAbility`): the engine pushes
  a single registered defensive during a "defensive" battle phase. Extra
  defensive cooldowns stay in `cds` as manual/toggle abilities.
- **Target modes:** `single` / `cleave` / `aoe` / `auto`; `DH:IsCleave` /
  `DH:IsMultiTarget` drive the branches.
- **Complexity:** "simple" mode excludes base cooldowns ≥ 60 s from the queue.
- **Battle phases:** `opener / burst / sustain / execute / aoe / cleave /
  defensive / idle`, derived in `State.lua`.
- **No secure/tainted actions:** the addon only draws and prints; it never
  performs casts or touches protected frames.

## 9. Adding a class module

1. Copy `RotationCore_<Class>` from a similar class as a starting point.
2. Update the `.toc` (`Title`, `Dependencies: RotationCore`, `LoadOnDemand: 1`).
3. Fill `SPELLS`, `abilities`, maps and `RegisterSpecDetector`.
4. Implement one `config` per spec in `Core.lua` and dispatch on `s.spec`.
5. Register defaults (`use_*` toggles) and add every string to the locales.
6. Add the folder to `SHIP_FOLDERS` in `scripts/build_release.py`.
7. Run `verify.py`, `/rc test rotation`, `/rc selfcheck`.
