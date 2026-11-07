# RotationCore Architecture

Technical map of the addon. For setup and the module API see
[DEVELOPMENT.md](DEVELOPMENT.md).

## Runtime

- Target: World of Warcraft 3.3.5a, Interface `30300`.
- Lua 5.1 sandbox. No external runtime dependencies.
- SavedVariables: `RotationCoreDB`, `RotationCoreErrors`,
  `RotationCoreAnalytics`.
- `RotationCore.toc` loads the core, then class modules load on demand.

## Core modules (`RotationCore/RotationCore/`)

| File | Responsibility |
|---|---|
| `RotationCore.lua` | Lifecycle, mode selection, `UpdateRecommendations`, slash commands, status/compat helpers. |
| `Schema.lua` | `ns.SCHEMA_VERSION` and `ns.MigrateSaved`: flat-to-profile migration, legacy key aliases, schema stamping. |
| `Simulation.lua` | Shared simulation framework and `DH:RunSimulation`. |
| `Registration.lua` | Class registration API, safe/heal/PvP modes, defaults, ability tables. |
| `KnownSpells.lua` | Spellbook scan, known-spell cache, fallback filtering. |
| `SharedSettings.lua` | `GetSetting`/`SetSetting`, themes, target-mode resolution, idle reasons. |
| `Profiles.lua` | Profile create/copy/import/export, defaults merge, schema helpers. |
| `Events.lua` | Event frame, update scheduling, combat/roster/user events. |
| `BossProfiles.lua` | Boss profiles, skill stats, ideal DPS, fight reporting, raid presets. |
| `BossTimeline.lua` | DBM/BigWigs timeline collection and phase hints. |
| `CustomAPL.lua` | Player-facing priority language parser/evaluator and APL import/export. |
| `Analytics.lua` | DPS forecast, pulse, exam/mentor modes, persistent learning stats. |
| `OptionsIO.lua` | Profile, boss-profile, layout and APL import/export windows. |
| `SpellFrameExtras.lua` | Cooldown, interrupt and boss-timeline windows. |
| `State.lua` | Live unit/player state: health, resources, buffs, debuffs, talents, glyphs, cooldowns. Caches known spells and item level. |
| `UI.lua` | Action-bar scanning, glow painting, window show/hide, shared UI helpers. |
| `SpellFrame.lua` | Icon window, action-bar matching, animations, window configuration grid. |
| `Extras.lua` | DoT panel, swing timer, fight report and optional extras. |
| `Hub.lua` | Coach hub, cooldown plan, history and lessons. |
| `Heal.lua` | Heal-assist window and shared heal-rotation helpers (`ns.GetHealContext`, `ns.GetHealTarget`, `ns.CanHeal`, ...). |
| `Diagnostics.lua` | Rate-limited error reporting, copyable report window, `/rc report`, `/rc errors export`, GitHub issue link. |
| `Feedback.lua` | One-time feedback prompt and options entry point. Safe-context checks live here. |
| `Config.lua` | Rotation mode selection helpers, minimap button, smoothing. |
| `Options.lua` | Options window and tab builders. Large file; tab builders are the natural split points. |
| `Wizard.lua` | First-run setup wizard. |
| `Locale.lua` | EN + RU base and lookup metatable. |
| `Locale_<code>.lua` | Locale overrides guarded by `GetLocale()`, so only the active language writes into `DH.L`. |
| `SpellNames.lua` | Replaces translated spell labels with client `GetSpellInfo` names. |

## Class modules (`RotationCore/RotationCore_<Class>/`)

- `<Class>.lua`: spell IDs, ability table, buff/debuff maps, cooldowns,
  talents, glyphs, spec detector, defaults.
- `Core.lua`: per-spec priority logic and mode registration.

Healer modes are registered with `DH:RegisterHealMode` and are isolated from
the DPS simulation:

- `discipline`, `holy_priest`, `holy_paladin`, `resto_shaman`, `resto_druid`.
- They never borrow a DPS rotation unless `heal_dps_mode` explicitly allows it.
- The generic "first known attack" fallback is suppressed while a heal mode runs.
- The heal-DPS borrow keys remain `*_dps` and are used for solo play or an
  explicit setting.

## Saved variables and migrations

`RotationCoreDB.schema_version` is the current schema (`ns.SCHEMA_VERSION`).
`MigrateSaved` promotes the old flat layout to the profile layout, applies
camelCase aliases, normalizes missing containers and stamps the schema version.
Bump the version only when a migration changes the stored shape.

## Error handling

- Every event, deferred task, rotation tick and UI paint runs behind `pcall`.
- `ns.ReportError(context, err)` logs every failure but prints at most one chat
  line per context every 30 seconds. Full history stays in `/rc errors`.
- The update loop stops itself after a persistent tick error instead of spamming
  the error handler every frame.

## Performance rules

- Update scheduling is event-driven. The poll mode is opt-in.
- The UI repaint from `UpdateRecommendations` is capped at 20 Hz.
- Known spells, item level, addon memory/CPU readings and `GetSpellInfo`
  display lookups are cached and invalidated by the relevant events.
- Heal rotations scan the group once per update (`ns.GetHealContext`); avoid
  calling it repeatedly inside one priority function.

## Magic numbers

| Value | Where | Meaning |
|---|---|---|
| `0.1` | `UPDATE_THROTTLE` in `RotationCore.lua` | Minimum seconds between coalesced event updates. |
| `0.05` | UI paint throttle | 20 Hz cap for icon/glow repaints. |
| `20` | `poll_frequency` clamp | Maximum poll rate in Hz. |
| `200` | `ns.MAX_ERRORS` | Error log ring-buffer size. |
| `30` | `REPORT_COOLDOWN` in `Diagnostics.lua` | Seconds between chat error lines per context. |
| `3 * 3600` / `5` | `Feedback.lua` | Hours of use / boss kills before one feedback prompt. |
| `6788` | `RotationCore_Priest/Core.lua` | Weakened Soul aura ID. |
| `0.05` / `20` | target-mode thresholds | Auto AoE at 4+ enemies (see `IsMultiTarget`). |

## Split status

Done: schema/migrations, simulation, registration, known spells, shared settings,
profiles/import-export, events, boss profiles/timeline, custom APL, analytics,
diagnostics, feedback, options import/export windows and spell-frame extras are
separate modules. Class rotations now use the shared `DH:Ready(sim, key)` DSL.

Remaining: tab builders in `Options.lua` can still be split further if needed.

Keep the TOC order in mind when extracting: core helpers must load before
`State.lua`, `UI.lua`, `Heal.lua` and the class modules.
