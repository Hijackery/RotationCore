# Changelog

All notable changes to RotationCore.

## [1.0.3] - 2026-10-27

- Hardened the simulation: class rotations now always receive `sim:ready` and
  `sim:remains`, fixing the Mage Frost "attempt to call method 'ready'" error
  that could appear with mixed addon versions.

## [1.0.2] - 2026-10-27

- Added the addon logo: in-game addon list icon and minimap button, plus a
  centered logo header in the English and Russian READMEs.
- Translated the remaining UI strings in all 8 locale mirrors and removed a
  duplicate Russian key.
- Added the store listing kit, icon set, social preview artwork and product
  screenshots.

## [1.0.1] - 2026-10-27

- Removed the end-of-fight report popup. It appeared after trash kills and is
  gone from the core module and the options window.

## [1.0.0] - 2026-10-20

First public release (MIT).

- Core engine plus 10 LoadOnDemand class modules (Death Knight, Druid, Hunter,
  Mage, Paladin, Priest, Rogue, Shaman, Warlock, Warrior).
- Rotation highlight, icon window, DPS forecast, cooldowns / interrupt windows,
  boss timeline, custom APL, exam / mentor / training / PvP modes, healer
  assist, per-spec profiles, boss presets and analytics.
- All 12 official WotLK 3.3.5a locales (enUS base + 8 mirrors + ruRU).
- Static verification harness (`verify.py`), CI workflow and an automated
  release pipeline (tag `v*` → verify → zip → GitHub Release).
- Full spell-id audit against the 3.3.5a database (see 3.4.0-hotfix42 below for
  the detailed corrections folded into this release).

## [3.4.0-hotfix42] - 2026-10-18

### Spell-id audit against the 3.3.5a database (all classes)

Every registered spell id (abilities, buffs, debuffs, glyphs and cooldowns)
was cross-checked against the WotLK 3.3.5a spell database. Corrections:
- Hunter: moved Silencing Shot lower in priority. Added conservative aspect-dance (Aspect of the Viper at low mana ↔ Aspect of the Dragonhawk at high mana), setting `use_aspect_dance`. getAdvanceTime=0 for aspects.

- **Death Knight**: Blood and Frost Presence ids were swapped (48263/48266),
  so the rotation could recommend the wrong presence. Fixed here and in the
  buff map. Sudden Doom used a non-existent id (81340) so the free-Death-Coil
  proc was never detected; it now matches the real proc ranks (49018/49529/
  49530). The glyph table was scrambled (e.g. "Glyph of Plague Strike" was
  registered as *Obliterate*); all 7 mismatched DK glyphs are now correct.
- **Druid**: debuff map had a Rip rank tagged as Rake and two foreign ids
  (Shred, Hurricane) tagged as Rip/Insect Swarm; corrected to the real ranks.
- **Hunter**: the Aimed Shot glyph pointed at a placeholder spell
  ("Death Knight Glyph 25"); corrected to the real Glyph of Aimed Shot.
- **Priest**: Shadow Word: Pain debuff map listed two non-SW:P ids
  (a Rain of Fire id and an unused id); replaced with the real low ranks.
- **Shaman**: Flame Shock debuff map listed a Frostbrand Attack id; replaced
  with the real Flame Shock ranks.
- **Warrior**: Rend debuff map listed a test spell and a Viscidus id;
  replaced with the real Rend ranks. The Hamstring ability now uses the max
  rank id (7373) instead of rank 1 (1715).
- Remaining flagged names are cosmetic only (database display name differs
  from the internal key; ids are valid), e.g. Warrior Bloodsurge = "Slam!",
  Warlock "Curse of the Elements", DK "Hysteria" (Unholy Frenzy).

## [3.4.0-hotfix41] - 2026-10-18

### Rotation data corrections, batch 2 (verified against 3.3.5a spell data)

- **Rogue**: Preparation cooldown corrected to 8 minutes (480 s); it was 5 min.
- **Druid**: Berserk (feral) cooldown corrected to 3 minutes (180 s); it was 2 min.
- **Paladin**: Exorcism (Art of War) now respects only its own ability toggle
  instead of the global cooldown gate, so the proc is used even when automatic
  cooldowns are disabled. Added seal upkeep (a missing seal is restored; AoE
  swaps to Seal of Command) for Retribution and Protection without overriding a
  seal the player deliberately keeps.
- Verified without change (cooldowns matched the 3.3.5a database): Warlock,
  Warrior, Priest, Shaman and Mage major cooldowns, plus the remaining Druid
  (Force of Nature, Starfall) and Rogue (Vanish, Blade Flurry) abilities.

## [3.4.0-hotfix40] - 2026-10-18

### Rotation data corrections (verified against 3.3.5a spell data)

- **Hunter**: Aimed Shot is instant in 3.3.5a (10 s cooldown); the sim no
  longer models it as a 2.9 s cast. Kill Command corrected to a 60 s cooldown
  (was 50 s) and treated as off the global cooldown.
- **Paladin**: removed the Art of War **talent** id (53488) and an unknown id
  (53490) from the proc map - only the real proc buffs (59578, 53489) are
  tracked, so Art of War no longer reads as permanently active. Protection now
  populates `has_ds` so Divine Storm can be recommended in AoE.
- **Mage**: corrected the Conjure Mana Gem spell id (42985).
- **Death Knight**: Unholy now detects Howling Blast for its AoE branch; Blood
  and Unholy Blood Tap now respect its real 60 s cooldown and the "use Blood
  Tap" setting (it could previously fire while on cooldown).

## [3.4.0-hotfix39] - 2026-10-17

### Options UI: spacing, UX order and theme consistency

- **Spacing (all tabs)**: every interactive row now reserves enough height so
  widgets never touch - checkboxes, dropdowns, scroll lists, buttons and edit
  boxes got more room, plus a small gap above buttons and section headers.
  Fixes the overlapping controls in General and System.
- **Coach hub / dialogs**: primary buttons unified to 26 px to match the
  Options and Wizard buttons.
- **General tab order (UX)**: the primary toggle ("Enable rotation highlight")
  and build selection now lead; the low-frequency Minimap / Menu controls moved
  into a new "Interface" section at the bottom (Serial-position + chunking).
- **Theme control**: added the missing Dark / Light "Theme" dropdown in
  General > Interface (the setting, tooltips and locale strings already existed;
  the control was absent).
- **Class-colour palette + custom accent**: the Theme dropdown now offers
  "Class color" (default), "Custom", Dark, Light and "High contrast". An
  "Accent color" swatch in General > Interface always opens the built-in colour
  picker; picking a colour switches the palette to Custom and applies it to the
  chrome (borders and titles) of every RotationCore window, not just the Options
  window.
- **Tab order (UX)**: the Display, Class and Advanced tabs now follow the same
  "most important / most frequent first" rule as General. Display leads with the
  spell queue and highlight, then arrangement, then window appearance/behaviour,
  colours and animations. Class leads with the per-spec ability switches and
  moves "Rotation complexity" to the bottom. Advanced leads with the feature
  toggles, then the timer fine-tuning, and the action-bar test button is last.
- **Status tiles**: the live-state tiles are compact single-line cards (26 px)
  so the Status tab matches the control scale used everywhere else.
- **Theme consistency**: content colours (status tiles, font/sound scroll lists,
  sidebar tabs) now come from the active palette, so the light theme is readable
  everywhere instead of leaving hard-coded gold/grey text on a light background.
- **Font / sound lists**: the lists no longer use a ScrollFrame. A ScrollFrame's
  scroll-child rows stay clickable even when scrolled out of view, so on the
  General tab (Sound) they leaked mouse input over every control below them -
  hovering made the buttons flicker and clicking them did nothing. The lists are
  now clipped: only the rows that fit are shown, the rest are hidden and never
  receive mouse input, and a thin inset border frames the list again.
- **Help**: corrected the tab overview and look-and-feel text (removed the
  retired "rounded / glass" skins, moved the minimap note to General, documented
  the class-colour / custom palette).

### Reliability hardening

- **Saved data**: the profile merge now type-checks saved values, so a corrupt
  or hand-edited SavedVariables entry (e.g. a string where a number belongs) is
  replaced with the default instead of surviving into the running profile.
- **Settings access**: `GetSetting`/`SetSetting` and the per-spec profile store
  tolerate a malformed table (non-table mode/spec entry) without erroring.
- **Event loop**: every event is dispatched through a guard, so one malformed
  payload cannot abort the handler or leave the addon half-initialised; the
  combat-log handler list is validated per entry.
- **Update loop**: the per-frame update and the extras driver stop themselves and
  log once if an error occurs, instead of spamming the error handler every frame.
  The deferred-task frame now queues every task and runs each guarded.
- **Spec detection**: the talent-point fallback reads the 3.3.5a return order
  (points spent is the third value) and both the primary and fallback detectors
  run guarded, so spec detection degrades to "unknown" instead of erroring.
- **Window position**: the Options window position/size are now saved to the
  shared `global` store (they were written to a per-profile table that never
  existed, so the window reopened centred every time).
- **Error store**: analytics history and the error log are normalised on load so
  a corrupt entry cannot break the coach window or the diagnostics view.

## [3.4.0-hotfix38] - 2026-10-17

### Readability, localization and healer fixes

- **Options window**: solid by default - the opacity slider now drives the
  backdrop alpha alone (removed the double-dimming that made the window look
  see-through).
- **Proc sound**: a 0.4 s throttle stops the alert from stacking on itself when
  several procs land at once.
- **General tab**: long info/note lines now wrap and shrink their row instead of
  overflowing the content column.
- **Setup Wizard**: the Extras step lays Yes/No pairs out in columns, so the
  step fits the window instead of running off the bottom.
- **Queue window**: tightened the gap between the icon rows and the window edge.
- **Healer tab**: now listed for every class for discoverability; only healer
  classes (Priest / Druid / Shaman / Paladin) can edit it, others see a short
  note. Help updated to match.
- **Healer rotation** (3.3.5a): corrected spell ids - Prayer of Healing is now
  48072 (was Prayer of Mending 48113) and Wild Growth now uses max rank 53251;
  added a cheaper fallback tier so a Paladin gets Flash of Light instead of
  Sacred Shield for small deficits.
- **Tooltips**: finished the RU + 8-mirror translation pass (~296 strings) and
  completed the English base (added 70 missing entries and fixed two entries
  that held Russian text). Removed technical wording (slash-command references,
  "temp tables / cache spell cards") from player-facing tooltips.
- **Queue window**: fixed minimum width to be title-aware so icons hug the
  window (no more forced 120-px empty margin).
- **Setup Wizard**: default window size increased to 780×560; step counter
  moved left to avoid overlapping the close button; dynamic text width prevents
  horizontal overflow.
- **General tab**: button size/anchor adjusted for a better, more consistent
  click area.

## [3.4.0-hotfix37] - 2026-10-16

### Visual pack: rounded corners, backgrounds, title font, fades, tab glide

- **Background styles** (System > Interface style): Default / Rounded / Glass /
  Matte. Rounded & Glass use a shipped 9-slice rounded texture (Textures are
  generated in `textures/`), so windows get real rounded corners and edges.
- **Custom title font + shadow**: window titles use the chosen LibSharedMedia
  font (with the large-text option) and a soft drop shadow.
- **Fade + pop on show** for the cooldown / interrupt / timeline windows, now
  combined with their opacity setting (the window fades in to its opacity).
- **Animated active-tab highlight**: a class-coloured bar glides to the active
  sidebar tab.
- All new strings localised (RU + 8 mirrors); tooltip coverage complete.

## [3.4.0-hotfix36] - 2026-10-16

### Visual: glass slot edges + eased tab fade

- Icon slots (queue window and the cooldown/interrupt windows) now have a thin
  top highlight in the priority colour - a "glass" edge that makes each icon
  read cleanly.
- The options content fade on tab change uses an ease-out curve (smoother).

## [3.4.0-hotfix35] - 2026-10-16

### Wizard overhaul + visual polish + healer verify

- **Wizard**:
  - New first question **Menu style** (Simple / Advanced).
  - New **Healing** step (healer classes only): heal assist, group health,
    heal-DPS mode.
  - New **Extras** step (advanced mode only): enemy counter, resource warnings,
    DoT panel, swing timer, timeline bars, colourblind palette.
  - **Compact window** question in the display step.
  - **Contextual steps**: Queue details / Advanced behaviour / Extras only show
    in Advanced menu mode; the healer step only for healer classes -> a much
    shorter, calmer flow for newcomers.
  - **Start over** button; summary now includes menu mode and compact window.
- **Visual polish**: every window now gets a soft drop shadow, a translucent
  title strip and a thin class-coloured accent cap (shared chrome helper). The
  options sidebar highlights the active tab with a class-coloured accent bar,
  tinted icon and brighter plate.
- **Healer rotation** cross-checked against 3.3.5a databases; heal sets now
  match max-rank ids with **base-rank fallbacks** (IsSpellKnown on either), so
  the assist works regardless of rank.
- All new strings localised (RU + 8 mirrors); tooltip coverage complete.

## [3.4.0-hotfix34] - 2026-10-16

### Healer module + settings repackaged

- **Healer assist** (`Heal.lua`, new): recommends a heal for the lowest-health
  group member from per-class heal sets (Priest / Druid / Shaman / Paladin),
  choosing a tier (big / medium / HoT / instant / AoE) from the health deficit,
  mana and which heals you actually know. Shown in a movable, colour-coded
  window. Also exposes `ns.GetHealSuggestion(unit)` and `ns.IsHealerClass()`.
- **New "Healer" tab** (only for healer classes): heal-DPS mode, heal assist and
  group health together.
- **Settings repackaged**:
  - Minimap button moved from System (advanced-only) to General (was hidden in
    Simple mode).
  - "Sound" section renamed to "Alerts"; the heal-DPS option moved out of it.
  - Group health + heal assist now live on the Healer tab.
- Removed the empty statement in the APL editor; verified no dangling settings.

## [3.4.0-hotfix33] - 2026-10-16

### Simulator, APL editor, talent check, group health

- **Rotation simulator** (`/rc sim`): DPS forecast, last-fight/Details DPS,
  targets/activity, and the predicted next cast sequence over a chosen window.
- **Visual rotation editor** (`/rc apl edit`): list of APL rules with move
  up/down, delete and add; saves straight to the custom APL.
- **Talent check** (`/rc talents`): flags key rotation abilities you have not
  learned (candidate talents) and shows the active spec/rotation.
- **Group health monitor** (Advanced > Extras): party/raid HP sorted lowest
  first, colour-coded (healer foundation).
- Help/README updated; all new strings localised (RU + 8 mirrors); tooltip
  coverage complete.

Note: a full **healer module** (per-class heal rotations) needs class-specific
heal data that the class modules do not currently provide, so it is left as a
separate large effort; the group health monitor is the foundation for it.

## [3.4.0-hotfix32] - 2026-10-16

### New module: Coach Hub (hub / API / analytics / breakdown / plan)

New file `Hub.lua` (added to the TOC, `RotationCoreAnalytics` SavedVariable):

- **Public API** for other addons: `DH:GetRecommendations()` and
  `DH:SetRecommendationCallback(fn)` (fires on every rotation update, no
  network).
- **Coach hub window** (`/rc hub`, or General > Quick actions): live status
  (grade S/A/B/C/D, spec/rotation, accuracy, DoT uptime, CD usage), cooldown
  plan from DBM/BigWigs timers, recent-fight history and lessons.
- **Analytics**: per-fight results (boss/spec/DPS/accuracy/duration) stored in
  `RotationCoreAnalytics` (capped) with a clear-history button.
- **Fight breakdown** window (`/rc analyze`): duration, damage, DPS, accuracy,
  DoT uptime, CD usage, grade and top misses.
- **Details/Recount** DPS read (best-effort, fully guarded) shown in the hub.
- **APL import** window (paste text → parsed into the custom APL).
- **Lessons**: built-in scenarios (accuracy / DoT uptime / CD usage) that
  complete during fights.

Still queued from the big list: A (full simulator), C (visual rotation editor),
O (talent/glyph advice), J (healer module).

## [3.4.0-hotfix31] - 2026-10-16

### Section tooltips, interrupt sound, baked auto-behaviour, AUDIT

- **Section tooltips**: hovering a section header shows a short description of
  the section (RU + all 8 mirrors).
- **Interrupt-ready sound**: an option to play a sound when your interrupt comes
  off cooldown (Display > Cooldowns and interrupt windows).
- **Baked auto-behaviour**: removed the `ui_style` / `ui_shell` /
  `zero_impact_mode` / `compat_check` settings; the style/shell and scheduling
  are now fully automatic (single source of truth).
- **AUDIT.md** refreshed with the current feature set and the removed items.

## [3.4.0-hotfix30] - 2026-10-15

### Extras round: DoT sets, colourblind mode, bindings, translation, cleanup

- **Timeline bars** use the real timer duration from DBM/BigWigs.
- **Fight report** adds DoT uptime and your top missed abilities.
- **Key bindings**: "Open settings" and "Panel configuration" under
  Key Bindings > RotationCore (Bindings.xml).
- **Colourblind-friendly palette** (orange/blue/grey) toggle in Display.
- **Class DoT sets**: the DoT panel marks your class' key DoTs and sorts them
  first.
- **Build mismatch warning**: a chat notice + a Status line when the manual
  rotation does not match the detected talents.
- **Extras driver** is now dormant unless a feature is active/in combat
  (zero-impact).
- **Cleanup**: removed the legacy `spellframe_locked` and dead `ui_shell`/
  `ui_style` choices, pruned ~17 orphan locale keys.
- **Translation**: translated ~570 remaining non-tooltip strings across the 8
  mirrors (headers, labels, intros, format strings). The audit is now 0.
- **README** updated; Help updated (colourblind palette, bindings).

## [3.4.0-hotfix29] - 2026-10-15

### Section merges + Help moved, mode-safe

- Display: "Window" and "Window move" merged into one "Window" section.
- Profiles: the two boss headers merged into one "Boss Profiles" section.
- The /rc troubleshooting block moved from Advanced to Help (Help is always
  visible, so it now shows in both simple and advanced menu mode).
- Help overview updated to the current tabs/sections; tooltips re-audited
  (0 missing, 0 untranslated) and all option/section dependencies verified.
- Verified the simple/advanced menu modes are unaffected: the moves happen
  inside always-visible tabs (Display/Profiles/Help); the advanced-only tabs
  and the mode-gated "Open full status" button are unchanged.

## [3.4.0-hotfix28] - 2026-10-15

### Settings reorganised into a logical structure

- Cooldown/interrupt window settings are no longer split: the enable toggles
  and the size/count options live together under Display > "Cooldowns and
  interrupt windows".
- The icon-window block moved to Display (renamed "Icon window options"); the
  minimap button moved to System; General is ordered Base -> Build detection ->
  Targets -> Activity -> Cooldowns -> Sound.
- Renamed sections for clarity ("Profile options" instead of a second
  "Advanced", "Cooldowns and interrupt windows", "Icon window options").

## [3.4.0-hotfix27] - 2026-10-15

### Config-click, tabs reorganised, missing tooltips, cleanup

- **Panel configuration**: a plain click (left or right, no drag) on a window
  now reliably opens its settings; the panel flips to the other side near a
  screen edge and sits above the highlights. Double-click-to-hide is disabled
  while configuring.
- **Status tab** now has a valid icon; the interrupt window widens to fit its
  title so the text no longer overflows.
- **Test sound** sits above the sound list (no overlap with the scroll list).
- **Sections reorganised**: the icon-window settings moved from Advanced to
  Display, the minimap button moved to System, and several section headers were
  renamed for clarity.
- **Tooltips**: every option now has a title + description in RU and all 8
  mirrors (17 missing ones added).
- Cleaned unused locals; verified no references to removed features remain.

## [3.4.0-hotfix26] - 2026-10-15

### Sound picker, smoother opacity, less clutter, panel-config polish

- **Proc sound** is now a scrollable list (mouse-wheel) instead of one long
  dropdown, so a big LibSharedMedia list stays usable.
- **Options opacity** slider is smooth: it fades the window live and no longer
  rebuilds the options on every step (that caused the jitter).
- **Tooltips added** for every Extras/new option (enemy counter, resource
  warnings, racial cooldowns, fight report, timeline bars, DoT panel, swing
  timer, compact mode, window font, large text, test sound, proc sound) in RU
  and all 8 mirrors.
- **Removed technical UI**: the Performance section (zero-impact / compatibility
  check), the Debug section and the internal encounter-id text in Boss
  Profiles; the "Current boss" / "Seen this session" lines are localized.
- **Duplicate settings removed**: the second "Show keybind" checkbox and the
  duplicated "Reset current profile" button.
- **Panel configuration** highlight no longer re-sets its text/colour every
  frame (cached), so the mode is calm and stable.

## [3.4.0-hotfix25] - 2026-10-15

### Status fix, icon fit, sound test, dedupe, full tooltip translation

- **Status tiles** no longer overlap the text (they are anchored to the top of
  their reserved row; two per row to fit the content width).
- **Icon window**: reduced frame padding so the icons fill the window better.
- **Options opacity** slider uses a finer 0.01 step.
- **Test sound** button next to the proc-alert sound dropdown to preview it.
- **Removed the duplicate Theme setting** (it overlapped with UI skin); the
  class-colour accents stay automatic. Removed the duplicate
  "Reset current profile" button from General (kept on Profiles).
- **All tooltips translated** in the 8 mirrors (116 used + extras), no English
  left; `verify.py` parity intact.

## [3.4.0-hotfix24] - 2026-10-15

### Visual overhaul (one look for the whole addon)

- **Theme presets**: Class color (new default), Dark, Light and High contrast,
  applied to every window through one shared chrome helper.
- **Unified window chrome**: icon window, cooldowns, interrupts, timeline, DoT
  panel, swing timer, wizard and the config panels now share the same
  backdrop / border / title colour.
- **Class-coloured accents**: header pips, the wizard progress bar and the
  active tab follow the player's class colour.
- **Priority frames**: each recommended icon gets a soft, priority-tinted
  backdrop behind the glow border.
- **Compact icon window**: an option to hide the frame/title (icons only).
- **Unified font + large mode**: pick a window font (LibSharedMedia) and a
  larger, more readable text size.
- **Config colour swatches**: the tint button is replaced by a row of colour
  swatches.
- **Grid snap**: windows snap to a 32 px grid while dragging in config mode.
- **Fade/pop**: DoT panel, swing timer and the fight report fade in/out.
- **Status metric tiles** and **tab header icons**; segmented wizard progress.

## [3.4.0-hotfix23] - 2026-10-15

### Fixes after the cleanup

- Fixed a crash: `attempt to call method 'Log'` - leftover `DH:Log(...)` calls
  from the removed file-log feature are gone.
- Wizard "Queue details": the long GCD note now advances the layout by its
  real (wrapped) height, so it no longer overlaps the options; "Show the key
  binding?" is visible again.
- Interrupt window: when the window is enabled it is now visible at idle too
  (shows the interrupt spell with its cooldown), not only while the target
  casts.
- Fight report only appears for fights of 5 s or longer (no spam on trash).

## [3.4.0-hotfix22] - 2026-10-15

### Cleanup (removed bloat) + new Extras

Removed (as agreed):
- **Broadcast** (addon-message state sharing), **Combat log CSV / file logging**
  (`RotationCoreLog`/`RotationCoreCSV` SavedVariables dropped from the TOC),
  **Replays**, **Scanner debug** ("show all action buttons") and the **Raw
  settings** dump in Status. Settings, options sections, slash commands, help
  text and locale keys were removed with them.

Added (new `Extras.lua`, toggles in Advanced > Extras):
- **DoT / debuff panel** - your own debuffs on the target with live timers.
- **Enemy counter** - live enemy count near the icon window (auto cleave/AoE
  already switches on it).
- **Resource-cap warnings** - combo points / energy / rage / runic power / mana.
- **Racial cooldowns** - Blood Fury, Berserking, Arcane Torrent, ... join the
  cooldown window (toggleable).
- **Swing timer** - melee auto-attack bar, driven by the combat log.
- **Timeline bars** - a fill bar behind each timeline row.
- **Interrupt cooldown** - the interrupt countdown is shown in red.
- **Fight report popup** - duration, damage, DPS and rotation accuracy at the
  end of a fight.

## [3.4.0-hotfix21] - 2026-10-15

### Dominos-style config: right-click settings, smooth highlights, fixed sizes

- **Panel configuration** no longer shows four fixed settings boxes. Entering
  the mode draws the grid + a live highlight on every window, and
  **right-clicking a window** opens its own settings (enable, size, scale,
  opacity, tint). A close button hides the panel again.
- **Highlight animation is smooth**: the outline now tracks the windows every
  frame instead of a 10 Hz timer, so it slides cleanly while dragging.
- **Fixed window sizes**: the icon window keeps one size (from the configured
  icon count) whether or not there is a target / picks; the cooldown window
  keeps the size of the configured icon count even when fewer are ready. No
  more size jumps.
- **Interrupt window**: ticking "Show window" now has a visible effect: while
  configuring, the window shows the interrupt spell even when your target is
  not casting.

## [3.4.0-hotfix20] - 2026-10-15

### Activity Auto, Dominos-style panel config, tab/help cleanup

- **Activity "Auto"** is now a real entry in the Activity list (Options and
  Wizard). It follows the current content and re-evaluates on
  `ENCOUNTER_START` / `ENCOUNTER_END`, not just zone changes.
- **Panel configuration (Dominos-style)**: a faint screen grid is drawn while
  the mode is open, every window gets a live highlight that follows it
  (green = enabled, grey = off, gold = selected by hovering its panel), and
  each panel has a "Show window" checkbox plus size / scale / opacity / tint.
- **Boss timeline window** now resizes its contents instead of scaling the
  frame, so it drags freely like the cooldown/interrupt windows.
- **Wizard**: fixed the inverted corner-grip resize (dragging down now grows
  the window); the GCD explanation is now detailed.
- **Tabs**: every tab opens with a one-line description to reduce visual noise
  and make the layout predictable.
- **Tooltips / Help**: removed the last technical strings (log file paths),
  Help rewritten to match the current features (panel config, Auto activity,
  Exam/Mentor, all slash commands); all strings localized (RU + 8 mirrors).

## [3.4.0-hotfix19] - 2026-10-14

### Panel config mode, cleaner headers, achievements removed

- **Panel configuration mode** (Dominos-style): `/rc config` or Display >
  "Configure panels" opens a top bar plus one settings panel per window
  (icon window, cooldowns, interrupts, timeline) with sliders for size/scale
  and opacity, and a Tint button that recolours the window. Panels are
  draggable; settings save automatically.
- **Timeline window** now actually resizes: the wheel / size slider applies
  `SetScale` (it previously changed only the stored value).
- **Header styling**: the section underline/pip was sitting under the title
  text; it now has a clear gap below the title, so headers read cleanly.
- **Proc sound**: the sound dropdown is always visible (it was hidden while the
  proc-sound option was off) and shows built-in sounds plus LibSharedMedia.
- **Wizard**: removed the "Interface shell" step (RotationCore adapts to
  ElvUI / Bartender4 / Dominos automatically), 10 steps now.
- **Achievements removed** entirely: registry, tracking hooks, Options section
  and the `/rc achievement` command are gone (no UI/help mention remains).
- **Options opacity** slider step reduced to 0.02 for a smoother fade.
- **Help/tooltips**: re-checked; added panel-configuration notes and `/rc
  config`, no stale achievement/shell references.
- Fixes found on review: `/rc config` was shadowed by the options alias (now
  `/rc options` / `/rc menu` open options, `/rc config` opens panel settings);
  the config "Reset positions" button called a missing function (implemented
  `ns.ResetWindowPositions`); removed dead wizard `SHELL_OPTS` / "eleven"
  wording / `shellInfoFs` misnomer; config control panels are static (the real
  windows are what you drag).

## [3.4.0-hotfix18] - 2026-10-14

### Options overhaul: layout, themes, skins, windows, achievements

- **Layout**: content width now fits the scroll area (no clipped headers),
  extra top padding, and the duplicated inner tab header ("General" /
  "Profiles") is removed.
- **Colour palette**: removed the per-priority R/G/B sliders and the "Custom"
  palette entry; only the (colour-blind friendly) preset palettes remain.
- **Tooltips**: fixed a leak where missing tooltip keys were shown raw
  (`tooltip_priority_2_g_title`); `GetTooltipLines` now ignores the
  `DH.L.__index` fallback. Removed the technical palette tooltips.
- **Integrations** list now shows addons only (DBM, BigWigs, ElvUI,
  Bartender4, Dominos, WeakAuras) - libraries are no longer listed.
- **Windows**: cooldowns window now supports 1-10 icons, a "hide when empty"
  toggle and a size slider; the interrupt window can stay visible when idle and
  has its own size slider; the timeline window resizes with the mouse wheel and
  has a size slider. Move overlays no longer print raw coordinates on the extra
  windows.
- **Deep timeline**: settings are always visible now (previously hidden behind
  `timeline_enabled`).
- **Wizard**: resizable via a corner grip or the mouse wheel, preserving the
  7:5 aspect ratio and remembering the size.
- **Look and feel**: fixed the light theme (solid plate so the tint reads);
  added an options-window opacity slider; replaced the do-nothing "UI style" /
  "UI shell" dropdowns with automatic adaption; added 7 extra colour skins
  (Fel, Frost, Void, Blood, Jade, Gold, Ember) next to Default/ElvUI/Minimal/
  Classic.
- **Sound**: the proc alert is now chosen from a list (built-in sounds plus
  LibSharedMedia), not a raw file path.
- **Indicators**: class-pulse and DPS-forecast text colours are configurable
  (Auto / named colours).
- **Achievements**: added icons, names, descriptions and a live progress
  (current/target) list in System, plus a richer `/rc achievement` output.
- **Broadcast**: clearer description of what the option shares.
- **Help**: updated with an "Indicators and forecasts" section (GCD, combat
  forecast, DPS forecast, class pulse) and corrected the look-and-feel notes.

## [3.4.0-hotfix17] - 2026-10-14

### Deep timeline fix, timeline window, fonts/sounds, guide marker

- **Deep timeline now actually fills**: `ns.InitTimeline` is retryable and each
  source (DBM / BigWigs) is hooked once; it is re-run on `ADDON_LOADED` for
  `DBM-Core` / `BigWigs`, so callbacks register even when the boss mod loads
  after RotationCore. Previously the one-shot init ran too early and the phase
  log stayed empty.
- **Boss Timeline window**: new optional display (Display > Timeline, on by
  default) showing the current phase and the upcoming DBM/BigWigs timers with
  countdowns; drag it like the other windows (`/rc move`), resizable.
- **Live Status metrics**: memory/CPU are polled at most every 2 s and cached
  (`ns.UpdateMetrics`), so the Status rows stay informative instead of only the
  uptime changing.
- **LibSharedMedia**: optional fonts and sounds. `spellframe_font` /
  `spellframe_font_size` now resolve LSM font names (the old raw
  "RotationCore Font" default that never loaded is replaced by `default`), and
  the proc alert uses an LSM sound picker. New Display > Font / Font size and
  General > Proc alert sound dropdowns.
- **Guide marker**: optional bobbing chevron above the next ability button
  (Display > Highlight).
- **Idle reasons**: added the missing "Addon disabled" / "Settings not loaded"
  translations.
- **Help** updated for the timeline window, guide marker and LibSharedMedia.

## [3.4.0-hotfix16] - 2026-10-14

### UI/UX, out-of-the-box defaults and localization

- **Sidebar menu**: group separators are now placed dynamically (before
  `Class` and `Profiles`) instead of one fixed line that overlapped the third
  button. Spacing between groups no longer forms a "mess of underlines".
- **"Reload UI" popup**: shortened the RU prompt and button
  ("Перезагрузить") so the button no longer overflows the dialog.
- **DPS forecast / class pulse**: removed the in-combat gate so both appear
  whenever there is data (works on a training dummy), not only mid-fight.
- **Deep timeline**: wired the DBM `DBM_Announce` and BigWigs
  `BigWigs_Message`/`BigWigs_StartBar` callbacks into the phase log and
  surface the newest phase message in the icon window. `timeline_deep_enabled`
  now defaults on; phase chat announce defaults off.
- **Status tab redesign**: live rows (activity, target mode, priority count,
  timeline phase, CPU/errors), integrations now list every known addon with a
  found/missing colour, and conflicts moved behind a dedicated
  "Show addon conflicts" button (popup report) instead of inline clutter.
- **Profiles simplified**: only the essentials (switch/create/reset/delete)
  show by default; import/export, per-spec, replays and boss profiles are
  behind a new "Show advanced profile options" toggle (deep personalization).
- **Glow styles**: added Breathe, Chase, Wave and Shimmer next to the existing
  Pulse/Static/Flash/Rainbow in Display > Highlight.
- **Help**: refreshed to match the new tabs, glow styles, deep timeline,
  simplified profiles and status layout.
- **Localization**: all `tooltip_*` keys were already translated; filled in
  the remaining ~300-680 UI strings in every mirror (de/fr/es/it/pt/ko/zhCN/zhTW).
  Only genuine cognates/acronyms remain identical to English.
- Added `AGENTS.md` with the standing rules (help always current, localize
  everything including tooltips, no technical clutter in player-facing tabs).

## [3.4.0-hotfix15] - 2026-10-14

### Localization fix

- The setup wizard question `"Combat forecast?"` had no translation and leaked
  the English string on non-English clients. Added the RU translation
  ("Прогноз боя?") plus EN fallback entries in all 8 locale mirrors.

## [3.4.0-hotfix14] - 2026-10-14

### Locale-independent boss detection, complete raid/dungeon presets

- **NPC-id matching**: presets now match the target's creature id from
  `UnitGUID` (`DH:GetUnitNpcID`) instead of the localised `UnitName`, so boss
  detection works on every client locale (ruRU included). `ENCOUNTER_START`
  carries a DungeonEncounter id (not the NPC id), which is why the old
  name-based path only worked on enUS/enGB.
- **Target detection covers raids and dungeons**: `DH:HandleDungeonBossTarget`
  / `HandleDungeonBossCombatEnd` became `DH:HandleBossTarget` /
  `DH:HandleBossCombatEnd`. A stored encounter profile (applied on
  ENCOUNTER_START) always takes precedence and is never clobbered by the
  target-detected preset.
- **Missing raids added**: Obsidian Sanctum, Eye of Eternity, Vault of
  Archavon and Onyxia's Lair.
- **Missing dungeon bosses added**: Dalronn the Controller, Commander
  Stoutbeard/Kolurg, Amanitar, six extra Violet Hold bosses, Drakkari Colossus,
  Eck the Ferocious, Tribunal of Ages, Infinite Corruptor and the Trial of the
  Champion bosses. Presets now carry NPC ids for 9 raids / 16 dungeons
  (125 bosses).

## [3.4.0-hotfix13] - 2026-10-14

### Dungeon presets, 5-man boss fallback, dead-toggle cleanup

- **WotLK 5-man dungeon presets**: `ns.bossPresets` now carries all WotLK
  5-man dungeons (16 dungeons / 52 bosses) with a per-boss `target_mode` and
  `activity_profile = "dungeon"`. Preset lookup is now kind-aware
  (`DH:FindPreset(id, name, kind)`) so raid and dungeon bosses that share a
  name ("Anub'arak", "The Lich King") resolve to the correct encounter.
- **5-man boss fallback detection**: ENCOUNTER_START does not reliably fire
  for 5-man bosses in 3.3.5a, so `DH:HandleDungeonBossTarget` detects the boss
  from the current target inside a party instance and applies / clears the
  matching preset (opt-in via "Enable boss profiles"). Cleared on combat end,
  target change away and instance change.
- **`/rc boss presets`**: lists every built-in preset (raid + dungeon).
- **Dead toggles removed**: "Memory optimization" and "Lazy loading" had no
  effect (never read outside Options) and were removed from the UI, defaults
  and all locales.
- **"Track achievements" now works**: the flag previously only gated its own
  sub-option; it now actually enables/disables achievement tracking
  (`DH:AchievementsFightStart/Rec/FightEnd/CheckAchievements`).

## [3.4.0-hotfix12] - 2026-10-14

### Residual audit fixes + extended file log

- **Wizard step 2 (spec list)**: `STEPS[2]` captured `GetModeOptions()` at file
  scope, before the LoadOnDemand class modules had registered their modes, so the
  specialization list was always empty. It is now (re)built in `UpdateStep()`
  when the step is shown.
- **Wizard player info**: `PlayerInfoLines()` called `DH:GetActiveMode().name`
  without a nil guard, so a missing mode threw. Now guarded via a local.
- **Mage AoE spell IDs (rank 1 → max rank 3.3.5a)**: Blizzard `10 → 42938`,
  Cone of Cold `120 → 42931`, Flamestrike `2120 → 42926`, Blast Wave
  `11113 → 42945`. Rank-specific `GetSpellCooldown` / `IsSpellKnown` now resolve
  against the trained rank.
- **File log extended**: new public `DH:Log(tag, fmt, ...)`; `DH:Debug()` is also
  mirrored to the file log; `OnEvent` now records COMBAT start/end, BOSS
  start/end, SPEC changes and attackable TARGET changes (in addition to
  INIT / ENABLE / MODE / ERROR / DECISION).

## [3.4.0-hotfix11] - 2026-10-14

### Persistent debug log (own SavedVariables file)

- **New "Write logs to file" option** (Options → System → Logging): when enabled,
  errors, decision-log lines and key events (login, enable/disable, rotation-mode
  switch) are appended to a dedicated `RotationCoreLog` SavedVariable. The client
  writes it to `WTF/Account/<account>/SavedVariables/RotationCoreLog.lua` on
  `/reload` or logout. 3.3.5a addons cannot write arbitrary files, so a
  SavedVariables file is the only persistent sink; this keeps a bug report to one
  file instead of a live reproduction.
- Bounded by `log_file_max_lines` (default 3000); oldest lines drop off first.
  The in-memory decision ring buffer and the separate error log are unchanged;
  decisions/errors are simply mirrored into the file when the option is on.
- `/rc log file` prints the on-disk path; `/rc log clear` now also clears the
  file log. New localized label + tooltip (EN base + all 9 locale files).

## [3.4.0-hotfix10] - 2026-10-14

### Code-audit bug fixes

- **`boss_profiles_enabled` duplicate default (HIGH)**: the key was declared
  twice in the defaults table (`false` then `true`); the later value silently won
  and contradicted the documented opt-in default. The duplicate was removed, so
  the documented default (`false`, per CHANGELOG hotfix entry and AUDIT) holds.
- **Replay recording (MED)**: `/rc replay` stored `duration = 0` for every fight
  (`buf.frames[#buf.frames] and 0 or 0`); it now parses the last frame timestamp.
  Pruning used `#list` on a hash-keyed map (always 0), so `replay_max_count` was
  never enforced and records grew without bound; the entry count is now computed
  explicitly before pruning.
- **Group-buff detection (MED)**: `GetGroupBuffs` matched buff names by their
  first 6 characters, so any blessing satisfied Kings/Might/Wisdom at once. It
  now matches the full name (still finds "Greater Blessing of X").
- **Arena Options info (LOW)**: `x or "auto" == "auto"` precedence made the
  AddInfo always visible; parenthesised so it shows only in "auto".
- **Interrupt tooltip range (LOW)**: `select(6, GetSpellInfo(...))` printed the
  power type; corrected to `select(9, ...)` (maxRange).

## [3.4.0-hotfix9] - 2026-10-13

### Menu localisation + official ruRU terms

- **Menu tooltips completed (EN + RU)**: 54 controls (checkboxes, dropdowns,
  sliders and the shared priority-weight slider) had a RU title/description but
  no English base entry, so EN clients showed a label with no tooltip body. All
  titles + descriptions were added to the EN `tooltips` table, and RU gained the
  missing `priority` pair. Every menu control now resolves
  `tooltip_<slug>_{title,desc}` in both locales; EN and RU tooltip key sets match
  exactly (0/0).
- **RU text leaks (MED)**: `tooltip_boss_profile_title` and
  `tooltip_enable_boss_profiles_title` still held English; both translated.
- **Official ruRU spell names (HIGH)**: status/queue terms now match the 3.3.5a
  ruRU client, verified against a WotLK ruRU spell database: Frost Fever →
  Озноб, Rake → Глубокая рана, Lacerate → Растерзать, Rend → Кровопускание,
  Haunt → Блуждающий дух, Bloodsurge → Сокрушить!, Hot Streak → Путь огня,
  Missile Barrage → Заградительные стрелы, Lock and Load → На изготовку!,
  Vengeance → Отмщение, Omen of Clarity → Знамение ясности, Shred → Полоснуть,
  Black Arrow → Черная стрела, Sunder Armor → Раскол брони, Faerie Fire →
  Волшебный огонь.
- **Runtime official spell names (all locales)**: new `SpellNames.lua`
  (registered in the TOC right after the locale files) overrides status/queue
  term values at load for non-EN clients using `GetSpellInfo(spellId)` and an
  exact-key → spellId map (e.g. Frost Fever 55095, Rake 1822, Hot Streak 44445,
  Black Arrow 3674). Every client now shows its own official 3.3.5a spell names;
  EN clients are untouched.
- **Automated prose translation (de/fr/es/it/pt)**: ~350–400 UI/status prose
  strings per Latin-script locale were machine-translated offline (Argos
  en→xx) with a curated gaming-term glossary (Cooldown/Tank/Healer/Stats/…)
  and strict `%`-placeholder, colour-code and whitespace protection. Acronyms,
  format strings, colour-coded strings and `/rc` commands were deliberately
  left as English fallback. Korean/Chinese mirrors were kept on English
  fallback (MT quality insufficient; `|c`/`%` corruption).
- **Invisible cursor fix (MED)**: the queue / cooldowns / interrupts windows
  called `SetCursor("UI_CURSOR_HAND")` on hover. On 3.3.5a `SetCursor` treats an
  unknown string as a texture path, and a non-existent path *hides* the cursor
  (WoWWiki `API_SetCursor`), so the pointer vanished over every display window.
  The invalid path was removed (the default arrow is used) and `OnHide` handlers
  now reset the cursor, so it can no longer stick when a window is hidden while
  the mouse is over it.
- **Wizard (plugin pass)**: the "Recommendation display" step was split into
  "Queue details" (step 7) so the body no longer overflows the fixed 700×500
  frame; `Finish` now applies answers and closes the window, calling
  `DH:ApplyShellStyle()` with the correct method receiver.
- **Locale size**: RU table now holds 1318 keys, 0 duplicates, parity 0/0 across
  all 8 mirrors. Non-EN translated (of 1318): de 1129, fr 1172, es 1121, it 1153,
  pt 1170; ko/zh/zhTW remain on English fallback except the runtime spell names.

## [3.4.0-hotfix8] - 2026-10-13

### Audit close-out #3 (deep RU localisation)

- **Class status localisation (HIGH)**: all `/rc <class>` status commands now
  route their output through `L()`. A `local L` helper was added to every class
  module; 10 status headers and all status labels (Runes, Frost Fever, Blood
  Plague, Energy, Combo Points, Rage, Mangle, Rip, Rake, Serpent Sting,
  Corruption, ...) resolve in RU.
- **Debug-frame localisation (MED)**: the on-screen debug frame
  (`MakeDebugFrameUpdater`) returned English-only lines; all 24 status format
  strings and the `Y`/`N`/`RDY` tokens are now localised (specifiers preserved).
- **Localisation gap (HIGH)**: 162 `L()` keys that were used in code but absent
  from the RU table (core boss/log/stats/selfcheck messages, achievement and
  replay output, status labels) were added. The RU table now has 1282 keys,
  0 duplicates, and parity 0/0 across all 8 mirrors.
- **Dead code (HIGH)**: removed unused `DH:MakeStatusCommand` (0 callers).
- **Duplicate keys (MED)**: removed 11 duplicate entries from the RU table.
- **TTD gating (MED)**: all 11 class status commands print TTD only when debug
  mode is enabled (`DH.db.debug`).
- **Glow flash (MED)**: `glow_frequency` now drives the flash style (`UI.lua`
  read the `FLASH_RATE` constant instead of the configured rate).
- **Spec fallback (MED)**: the LibClassicSpecs fallback now maps LCS static
  names to module keys (`"Restoration" -> resto`, spaces -> `_`); dead
  `classKey` local removed.
- **Mirrors**: new keys keep the documented English-fallback convention; all
  mirrors remain structurally identical to RU (parity enforced by `verify.py`).

## [3.4.0-hotfix7] - 2026-10-13

### Audit close-out #2 (17 items)

- **Window lock (CRITICAL)**: `SpellFrame.lua` called the non-existent
  `DH:IsWindowsLocked()` / `DH.IsWindowsLocked`, so the lock was never applied.
  All four call sites now use `DH:WindowsLocked()`.
- **Minimap (CRITICAL)**: `OnTooltipShow` now uses `L(...)`; the minimap button
  gained a middle-click handler that resets the saved position and refreshes
  `LibDBIcon`.
- **Tooltips (HIGH)**: every checkbox/slider/dropdown/button now has a tooltip.
  `AttachTooltip(widget, key, fallback)` falls back to the localised widget
  label when no dedicated key exists; full title+desc keys were added for the
  lock/drag, glow (frequency/lines), UI shell/style, proc-sound and all
  Save/Reset/Export/Import/Refresh buttons.
- **REC icons (HIGH)**: primary spell slots show a per-icon tooltip (spell
  hyperlink + reason + Ready/CD); extra frames show Range (interrupts) or
  Ready/CD (cooldowns).
- **Class help (HIGH)**: `/rc help` prints the localised help text.
- **Glow (HIGH)**: `glow_frequency` now affects the flash and rainbow styles
  (not only the built-in solid pulse).
- **TTD (MED)**: only printed in debug mode and prefixed with `Debug:`.
- **New command (MED)**: `/rc debug spec` reports active/primary/fallback spec
  detector results.
- **Localisation**: 81 new keys added to the RU table and all 8 mirrors; 5
  orphan tooltip groups removed (`glow_size`, `lock_icon_window_rc_move_to_unlock`,
  `heal_dps_rotation`, `highlighted_abilities`, `show_priority_numbers_1_2_3`);
  13 previously untranslated widget labels localised.

## [3.4.0-hotfix6] - 2026-10-13

### Audit close-out

- **Lock conflict (CRITICAL)**: windows are now genuinely movable by default.
  `DH:WindowsLocked()` reads a single flag (`frames_locked`); the legacy
  `spellframe_locked` no longer forces the drag gate closed. `/rc lock` /
  `/rc move` and the "Lock windows" / "Drag windows by default" options manage
  the one flag. The duplicate "Lock icon window" checkbox was removed.
- **Glow settings wired up (HIGH)**: `glow_thickness`, `glow_lines` and
  `glow_frequency` are now read by the renderer (thickness = border size,
  lines = concentric rings, frequency = pulse speed) and exposed in
  Display -> Highlight. `LibCustomGlow-1.0` is used when present, otherwise the
  built-in renderer is used.
- **Lifecycle hooks (HIGH)**: `DH:RegisterHook(event, fn)` + `ns.RunHooks`
  replace the fragile method re-wrapping for `StartFight`, `EndFight` and
  `OnEncounterStart`; the feature pack subscribes instead of overriding, so load
  order can no longer drop the original logic.
- **verify.py**: docstring/version aligned to 3.4.0, dead branch removed,
  locale parity now scans every key in the file (not just the first table).
- **Dead settings removed**: `proc_sound`, `auto_save`, `wizard_comprehensive`,
  `spellframe_hide_empty_slots`, `fire_build`, `flowerweaving_enabled`,
  `bearweaving_enabled`, `lunar_cooldown_leeway`, `living_bomb_threshold`.
- **Naming**: camelCase settings renamed to snake_case (`num_icons`,
  `spellframe_icons`, `spellframe_scale`, `show_numbers`, `glow_size`,
  `auto_mode`, `combat_only`, `show_spellframe`, `show_debug_frame`) with a
  load-time alias migration for existing profiles.
- **Localisation**: hard-coded UI strings in core/Options/Config moved to
  `Locale.lua` (+ value, + 8 mirrors).

### Fixed (live screen report)

- **Wizard layout**: progress bar and step counter recomputed from `#STEPS`
  (never "1/1"); bottom bar is a single right-to-left chain; option rows
  centered; window 700x500.
- **Cooldowns window**: shown even with zero active cooldowns ("No cooldowns"
  title); `GetCooldownItems` falls back to a `GetSpellCooldown` scan;
  `/rc debug cooldowns` reports exists / isShown / alpha / position / count.
- **SpellFrame**: fixed width by icon count (`spellframe_fixed_size`); empty
  slots hidden; slots enable the mouse (icon click casts, not drags).

## [3.4.0-hotfix4] - 2026-10-13

### Fixed

- **"Release Spirit" was blocked after death**: the icon window / cooldowns /
  interrupts windows stayed visible over the ghost UI and consumed the click.
  On `PLAYER_DEAD` the addon now hides every window and clears the glows
  (`ns.HideAllWindows` + guards inside `UpdateSpellFrame` /
  `UpdateCooldownsFrame` / `UpdateInterruptsFrame` / `ShowUI`); on
  `PLAYER_ALIVE` state is restored. Window scale range tightened to 0.5x-2.5x.

## [3.4.0-hotfix3] - 2026-10-13

### Fixed

- **Cooldowns / interrupts window toggles are now on the Display tab**
  ("Optional displays"), reachable in simple menu mode too; the fine-tuning
  sliders (icon count, min CD, window size, ready-order, reset positions) stay
  in Advanced -> "Optional windows (fine-tuning)". Verified at runtime in a
  headless build: `UpdateCooldownsFrame` creates and renders the window.
- **Resize the icon window always works**: mouse-wheel scaling no longer
  requires unlocking (`spellframe_locked` only blocks dragging), and the
  visible corner grip scales via `spellFrameScale` (0.25x-8x).

## [3.4.0-audit-cleanup] - 2026-10-13

### Cleanup / optimization

- Removed dead code: `KEY_DESC` (Options.lua, unused after the Class tab
  rewrite) and `ACTIVITY_LABEL` (RotationCore.lua, never referenced).
- **Hot-path**: achievements no longer write the profile table or run unlock
  checks on every update tick. `DH:AchievementsRec` now accumulates in memory
  and flushes + checks at most every 5 s (or on fight end) - the only per-tick
  cost left in the update pipeline is a counter increment (broadcast and
  replay remain opt-in, default off).
- Stale hint text removed from the Learning-stats info line.
- Cosmetic: collapsed triple-blank runs in UI.lua.

### Verified

- Full static scan of all files: no duplicate section headers, no leftover
  placeholders, no unused local functions besides the two removed.
- verify.py PASS, 41/41 parse, harness covers all 10 tabs + sidebar clicks +
  wizard.

## [3.4.0-hotfix2] - 2026-10-13

### Fixed

- **Tab clicks were dead**: the sidebar `OnClick` referenced `BuildContent`
  before its declaration, so Lua treated it as a nil global on every click.
  `BuildContent` is now forward-declared (captured as a local). Regression
  covered by the harness: every sidebar button is clicked after opening.
- **Unified window styling**: the icon-window backdrop now reads the active
  theme (`DH:GetUITheme`) like the options/wizard/cooldowns windows, so the
  whole addon matches by default; skins still override.
- **Resize to any size**: scale clamps widened to 0.25x - 8x for the icon
  window, cooldowns and interrupts windows (grips + wheel + `Icon window
  scale`/`Cooldowns window size` sliders).
- **Fine-tuning sliders moved to Advanced**: "Tooltip delay", "Glow border
  thickness", "Animation speed" no longer clutter General/Display; a new
  "Fine-tuning" section in Advanced holds them.

### Added

- **More tabs** (less scrolling per sheet): Advanced is split into
  `Advanced` (scanner / windows / labels / optional displays / debug / combat
  log / minimap / fine-tuning), `Coaching` (APL + DPS forecast / class pulse /
  exam / mentor / learning), `Timeline` (boss timeline + deep BigWigs), and
  `System` (broadcast / achievements / arena / performance / UI skin). All new
  tabs are advanced-only; Simple mode keeps 4 tabs.
- **Tooltips for every setting**: descriptions generated for all settings that
  lacked one (54 pairs RU + 8 mirrors, parity green).
- **Status **: CPU (ms/frame) row added for performance monitoring.

## [3.4.0-hotfix] - 2026-10-13

### Fixed (live-client report)

- **Empty options window**: `CatButtonFactory` dereferenced
  `GetPushedTexture()/GetNormalTexture()/GetHighlightTexture()` without a nil
  check. On some 3.3.5a clients those return nil after `Set*Texture(path)`, so
  the very first `EnsureFrame` threw, leaving a partially-built frame cached
  (content never created) - every later `/rc config` built an empty window.
  Now: nil-guarded textures, `EnsureFrame` is transactional (a failed build
  drops the partial frame and retries cleanly), `BuildContent` guards a missing
  `content` and surfaces any builder error as red text in the window.
- The same transactional guard was applied to `Wizard.EnsureFrame`.
- **No resize grip on the spell-queue window**: the primary window only had
  mouse-wheel scaling; a visible grip button was added (drag to scale, saved to
  `spellFrameScale`).

## [3.4.0-hotfix5] - 2026-10-13

### Wizard (comprehensive, 10 steps)

- **10 steps**: welcome / class+spec + ilvl / role / activity (+Arena) /
  target mode / display (icons, size, orientation, keybind, GCD, numbers) /
  cooldowns & procs (auto-cd, order, sound, flash, training) / advanced
  behaviour (adaptive, phase indicator, group buffs, combat forecast) /
  interface shell / done + summary + highlight test.
- **One answer per question**: each group stores its own key
  (`answers["<step>@<group>"]`); radio-like single selection retained on Back.
- **Validation**: "Next" is disabled until every question on the step is
  answered (`wizard_require_all_answers`, pre-filled from the profile).
- **Layout**: window 700x550 (`wizard_window_size`), progress bar, fixed
  footer row (Back / Next / Skip / Cancel, 12 px gap), no overlapping buttons.

### UI shell & Blizzard style

- New settings `ui_style` (blizzard/custom/classic) and `ui_shell`
  (auto/blizzard/elvui/bartender4/dominos) in System -> Interface style.
  `DetectShell()` reads loaded addons (ElvUI / Bartender4 / Dominos);
  `GetUITheme` resolves style + shell (+ optional skin overlay).

### Cooldowns window

- Now reachable everywhere: the toggles sit on Display; a **placeholder** is
  shown when enabled but no long cooldowns exist; default `show_cooldowns_display`
  is true; default position {x=-150, y=0}. `/rc debug cooldowns` prints
  enabled/shown/count and force-enables; `/rc cleanup` recreates the frames.

### Other

- SpellFrame normalised: with target = recs or idle reason; without target a
  compact "No target" is kept even when the idle-reason toggle is off
  (unless hide_no_target). Window scale range is 0.5x-2.5x.
- Extra frames raise their frame level above neighbours (no overlap with
  other addons). Locale: new keys RU + 8 mirrors, parity green.

## [3.4.0] - 2026-10-13

### Feature pack (12 improvements + status + auto-activity)

- **1 Battle context**: `DH:GetBattlePhase()` (opener/sustain/burst/execute/
  defensive/aoe/cleave, cached 1s) exposed to every class sim as
  `sim.battle_phase`; a defensive-phase gate recommends the registered class
  defensive first (`DH:RegisterDefensiveAbility` in 8 class cores).
- **2 Combat forecast**: `DH:ForecastNext(window)` renders "through Ns: <cd>
  ready / <buff> expires" lines on the icon window (Display -> Combat forecast).
- **3 Group awareness**: `DH:GetGroupBuffs()` scans party/raid raid-buff
  coverage (kings/might/wisdom/fortitude/totems/bloodlust, cached 3s), gated by
  `group_awareness_enabled`.
- **4 Boss profiles x class x spec**: storage `bossClassProfiles[boss][class]
  [spec]`, auto-load on ENCOUNTER_START (`boss_profile_autoload`), UI in
  Profiles -> Boss profiles, raid presets unchanged.
- **6 Replays**: `/rc replay list|export <id>|clear`, up to `replay_max_count`,
  ring-buffered frames per fight.
- **17 Deep timeline**: BigWigs message hook (`BigWigsLoader.RegisterMessage`)
  when `timeline_deep_enabled`; phase events + chat announce.
- **18 Broadcast**: `RotationCore_State` addon message with `RC:rec1=..;rec2=
  ..;rec3=..` payload, `DH:SetBroadcastCallback`, party/raid/say channel.
- **21 Zero-impact**: `zero_impact_mode` (default on) forces the event-driven
  scheduler (no idle OnUpdate); 0.1s update throttle.
- **22 Memory**: `DH:GetCachedSpellInfo` cache, fight-table cleanup, replay
  buffer release; `/rc mem`.
- **23 Lazy load**: heavy caches built on first use; class modules remain
  LoadOnDemand.
- **24 Compat**: `DH:RunCompatCheck` (ElvUI / Bartender4 / Dominos detection),
  runs at login when `compat_check` is on; no global names added.
- **27 Skins**: `default / elvui / minimal / classic`, `DH:RegisterSkin`
  auto-discovery API, skins override `GetUITheme`; UI dropdown in Advanced.
- **28 Achievements**: persisted counters (fights / clean fights / recs),
  unlock + chat announce (100 clean, 1000 recs, 10 fights), `/rc achievement`.
- **30 Arena**: `DH:GetArenaMode` (2v2/3v3/5v5 by zone), ALT-SHIFT-A cycle,
  Advanced -> Arena.
- **Auto-activity**: `auto_activity` (default on) maps the current situation to
  `activity_profile` (raid / dungeon / arena-bg / world-group / solo) via a
  dedicated event frame (entering world, leaving world, group roster, instance).
- **Status tab** (advanced menu only): version/build, live addon state
  (enabled/spec/mode/profile/spellframe/OnUpdate/memory/uptime/errors),
  integrations table with rescan, diagnostics + copy-to-chat; General shows a
  compact status summary in simple mode.
- All 20+ new settings ship in `coreDefaults.common` and migrate into every
  profile through `MergeDefaults`.


### Added

- **Menu dependency system**: every Add* widget accepts an optional
  `condition`; when it returns false the widget is skipped on the next rebuild.
  Toggling a parent re-runs `BuildContent()` with no reload:
  use_cooldowns -> cooldown_order, timeline_enabled -> burst / auto-switch /
  burst window, dps_forecast_enabled -> show-actual / position,
  mentor_mode -> error threshold, custom_apl_enabled -> import/export/share,
  adaptive_rotation ~= simple -> ilvl thresholds, target_mode -> aoe/cleave
  thresholds, show_tooltips -> tooltip delay, spec_profiles_enabled ->
  per-spec actions, boss_profiles_enabled -> boss list, numIcons > 0 ->
  GCD timer.
- **Menu mode tabs**: `simple` shows General / Display / Profiles / Help;
  `advanced` adds Class and Advanced. Toggling Menu mode re-sorts the sidebar
  immediately.
- **6-tab layout** with a 160x32 gold-highlight sidebar and separators; the
  content fades in (0.2s, skipped in combat / when animations are disabled).
- **Wizard v3.4.0**: 7 steps with a progress bar, [Back] / [Next] / [Skip] /
  [Cancel], answers pre-filled from the profile, a live class/spec/level/ilvl
  line on step 2, and a summary screen with "run a highlight test now".
- **Theme** dropdown in General (dark / light); section headers draw a thin
  gold underline.

### Changed

- **Deduplicated settings**: Theme moved to General (was duplicated in the
  spell queue), glow controls moved to Display (were duplicated in Advanced),
  priority-numbers and keybind-on-icons duplicates removed, adaptive rotation
  + ilvl thresholds moved to Class, and `common` is excluded from the Class
  advanced dump so cooldown / target / activity settings are not listed twice.
- Version bumped to 3.4.0 (RotationCore.lua, all 11 .toc, verify.py).

### Verified

- 41 files parse; `verify.py` PASS (0 problems); headless smoke harness
  builds all six tabs in both menu modes and steps the full 7-step wizard
  without errors; wizard answer application smoke passes; DPS-forecast
  regression smoke unchanged.

## [3.3.0-m29] - 2026-10-13

### Changed

- Refactored the ten class modules onto four shared framework factories in
  `RotationCore.lua` (closes audit item **M29**). No gameplay change:
  - `DH:RegisterAbilityTable()` replaces the byte-identical ability
    finalisation loop (key tag, `abilityByName` index, texture resolution)
    that every `<Class>.lua` carried inline.
  - `DH:RegisterCommonDefaults(extras)` registers the shared `common`
    settings block that was copy-pasted into all ten `RegisterDefaults`
    calls. Per-class extras (Druid weaving flags, Mage `fire_build`, Warlock
    `aoe_threshold`/`mana_threshold_life_tap`) are merged on top.
  - `DH:MakeDebugFrameUpdater(buildLines)` builds the live-debug updater from
    a class lines callback; the factory owns the header, the three
    recommendation slots and the frame text/show calls.
  - `DH:MakeStatusCommand{ title, lines, ttd }` builds the status slash
    handler (`mage`/`dk`/`hunt`/`ret`/`prot`/`sp`/`rog`/`enh`/`ele`/`lock`/`war`).

### Verified

- 41 files parse, `verify.py` green (0 problems), DPS-forecast regression
  smoke = 1138 DPS, all four factories unit-tested in isolation.

## [3.3.0-post-audit] - 2026-10-13

### Added

- **`/rc selfcheck`** - runs in-game invariant tests (ability-table integrity,
  build detection, rotation modes, stored APL parse, locale keys, timeline
  init) and prints a PASS/FAIL summary; mirrors the offline `verify.py`.
- **`verify.py`** check-in: static harness (luaparser over all 41 .lua files,
  RU↔locale key parity, version consistency, forbidden-API scan). Exit code 0
  = green; run with `python3 verify.py`.
- **Per-class DPS coefficients** - all 10 `<Class>.lua` files now call
  `DH:RegisterSpellDamage` with approximate `min/max/coeff/cast/ap` for their
  main direct-damage abilities, so the forecast is meaningful from the first
  second (observed combat-log averages still override once spells land). The
  registered `cast` time now feeds the GCD estimate.

### Changed

- **Cache** for `DH:GetRotationComplexity()` (signature = item level +
  thresholds), removing a redundant per-ability stat read in `CanUseCooldown`.
- **Options → Advanced → Combat log**: new "Record combat log automatically"
  checkbox wiring the previously-unexposed `combat_log_enabled`.
- **Timeline execute hook**: Warrior (`execute`) and Warlock (`drain_soul`)
  branches now also trigger on `DH:IsExecutePhase()` (phase 3), in addition to
  the existing target-HP threshold.
- Locale duplicates removed from the 8 `Locale_*.lua` files (each key now
  appears once); locale coverage is 12/12 (esES file serves esMX too).

## [3.3.0-phase3] - 2026-10-12

### Added

- **Adaptive rotation by item level (Improvement 1).** `State:GetItemLevel()`
  averages equipped item levels via `GetInventoryItemLink` / `GetItemInfo`,
  cached and invalidated on `PLAYER_EQUIPMENT_CHANGED`.
  `DH:GetRotationComplexity()` returns `simple` / `normal` / `complex`
  (`adaptive_rotation = "auto"` by default, thresholds `ilvl_threshold_simple`
  = 200, `ilvl_threshold_complex` = 245). A `simple` rotation keeps long
  cooldowns out of the queue (`DH:CanUseCooldown`) and shows only the top
  ability; helpers `DH:IsSimpleRotation()` / `DH:IsComplexRotation()` are
  available to class modules. `/rc status` shows `Adaptive: <mode> (ilvl N)`.
- **Learning statistics (Improvement 2).** `DH.db.learning_stats.sessions`
  stores one entry per fight (`date`, `accuracy`, `dps`, `loss`, `ilvl`,
  `spec`), capped at `learning_stats_max_sessions` (default 100). `/rc learning`
  prints the summary and improvement, `/rc learning graph` an ASCII chart,
  `/rc learning export` CSV, `/rc learning clear` resets. Controlled by
  `learning_stats_enabled`.

## [3.3.0-phase2] - 2026-10-12

### Added

- **Live DPS forecast (Improvement 1).** `ns.dpsForecast` estimates the DPS of
  the current recommendation queue (observed per-spell averages where
  available, then optional `DH:RegisterSpellDamage` coefficients, then a
  stat-based estimate), shown above the icon window as `~5200 DPS` plus actual
  DPS and loss (`4800 (-8%)`). Updates every `dps_forecast_update_interval`
  (default 1s), only in combat. `dps_forecast_enabled` (default off),
  `dps_forecast_show_actual`, `dps_forecast_position`.
- **Class pulse (Improvement 2).** A coloured indicator next to the icon window
  (green > 90%, yellow 70-90%, red < 70%) built from cast accuracy, DoT uptime
  and cooldown usage. `class_pulse_enabled` (default on), `class_pulse_position`.
- **Exam mode (Improvement 3).** ALT-SHIFT-E. The action bars are never
  highlighted (UI.lua) and only REC1 is shown; correct / wrong presses are
  counted and summarised after the fight. `exam_mode`, `exam_report_in_chat`.
- **Mentor mode (Improvement 4).** ALT-SHIFT-M. Counts consecutive mistakes; at
  `mentor_error_threshold` (default 3) it explains the mistake (proc, DoT,
  execute, cooldown). `mentor_mode`, `mentor_show_in_chat`.
- Options → Advanced: Coaching and Adaptive Rotation sections.

### Changed

- Version bumped to 3.3.0 across all 11 `.toc` files and `DH.Version`.
- Locale: added `DPS Forecast`, `Class Pulse`, `Exam Mode`, `Mentor Mode`,
  `Adaptive Rotation`, `Learning Stats` and related strings to every locale
  file (RU translated, others fall back to English).

## [3.3.0-phase1] - 2026-10-12

Phase 1 of the v3.3 line: three foundational systems that later phases build
on. All changes are additive; existing profiles migrate automatically via
`MergeDefaults`.

### Added

- **Improvement 7 - deep talent / glyph / stat build detection.**
  `build_detect_mode` now defaults to `talents_glyphs_stats`. A reusable
  `State:GetStatProfile()` exposes `spell_power` / `attack_power` / `crit` /
  `haste`, and `State:DetectBuild()` attaches it to `build.stats`. The Mage
  detector now also returns `arcane_blast` / `frostbolt` sub-builds from the
  matching glyphs (in addition to the existing `ttw` / `ffb`), while the other
  nine classes keep using their spec as the build. Detection is cached and
  invalidated by `PLAYER_TALENT_UPDATE`, `ACTIVE_TALENT_GROUP_CHANGED`,
  `GLYPH_ADDED`, `GLYPH_REMOVED` and `GLYPH_UPDATED`.
- **Improvement 6 - custom APL priority format.** A small, human-readable
  language (`priority:` + `- Ability if cond and cond`) parsed by
  `ns.ParseAPL` (pure string work, never `loadstring`) and evaluated by
  `ns.EvaluateAPL`. Conditions: `cooldown_ready`, `buff_active(x)`,
  `buff_remaining(x[, n])`, `target_has_debuff(x)`, `target_hp`,
  `player_hp`, `mana_pct`, `combo_points` (with `< <= > >= ==`),
  `always`, plus `and` and `not`. `ns.SetCustomAPL` / `ns.ExportAPL` /
  `ns.ExportAPLShare` (`RCAPL1:` one-liner) / `ns.DecodeAPLShare`. When
  `custom_apl_enabled` is on and the APL parsed to at least one rule, it
  replaces the class rotation in `DH:UpdateRecommendations`. Options →
  Advanced → Priorities (APL) plus a safe import/export text window; slash
  `/rc apl enable|disable|import [text]|export|share|clear`.
- **Improvement 5 - boss timeline phases.** `timeline_show_burst`,
  `timeline_auto_phase` and `timeline_burst_window` (default 15s). Phase
  tracking (`ns.SetTimelinePhase` / `ns.GetTimelinePhase`) parsed from
  DBM/BigWigs text and boss cast/aura names ("Phase 2", "фаза 2", "P2").
  When `timeline_auto_phase` is on, `DH:ResolveTargetMode` forces phase 2 →
  `aoe` and phase 3 → `single` execute, and `DH:IsExecutePhase()` gives
  rotations an execute hook. `ns.GetTimelineHint` honours the configurable
  burst window and `timeline_show_burst`. Still pcall-guarded and fully
  functional without DBM/BigWigs (combat-log only).

- Options → Advanced: Boss timeline and Priorities (APL) sections.

### Changed

- `build_detect_mode` default is now `talents_glyphs_stats`.
- Version bumped to 3.3.0 across all 11 `.toc` files and `DH.Version`.
- Locale: added `Timeline`, `Build Detection`, `APL`, `Import APL`,
  `Export APL`, `Share APL`, `Boss timeline` and related strings to every
  locale file (RU translated, others fall back to English).

## [3.2.2] - 2026-10-12

### Added

- **Customisable colours.** Five accessibility palettes (`default`,
  `protanopia`, `deuteranopia`, `tritanopia`, `high_contrast`) plus a custom
  palette (`color_custom = { [i] = { r, g, b } }`). `ns.GetPalette()` /
  `ns.ApplyPalette()` feed the action-bar glow and the icon window; Options →
  Interface → Colors exposes a palette dropdown and nine R/G/B sliders (editing
  one switches the palette to `custom`). `/rc palette <name>` sets it directly.
- **Animated transitions.** The icon window now fades icons in on appear
  (0.2s), crossfades when an icon changes (0.15s) and fades them out on
  disappear (0.15s), driven by a temporary per-slot `OnUpdate` that is removed
  when the tween ends. Options → Interface → Animations (`animations_enabled`,
  `animation_speed` 0.5–2.0). Transitions are skipped automatically when the
  window is refreshed more than ~25/s (busy CPU) or when icons change faster
  than 0.3s.
- **Boss timeline.** Optional DBM / BigWigs integration via
  `DBM:RegisterCallback` / `BigWigsLoader.RegisterMessage` (pcall-guarded, safe
  without either addon) plus `SPELL_CAST_START` / `SPELL_AURA_APPLIED` capture.
  Burst-classified timers drive a hint on the icon window: `BURST` (<= 2s),
  `Hold CD` (< 15s) and `Prepare` (15–30s), with a `Burst in Ns` countdown.
  `timeline_enabled` (default off); `/rc timeline` toggles it.
- **Display layout presets.** `center` / `side` / `minimal` / `raid` / `custom`
  arrange the primary, cooldowns and interrupt windows (positions, scale and
  visibility). `ns.ApplyLayout` / `ns.ExportLayout` / `ns.ImportLayout`;
  Options → Interface → Layout; `/rc layout <preset|export|import>`. A manual
  drag switches the layout to `custom`.

### Changed

- Options → Interface now includes Colors, Animations and Layout sections.
- Locale: added `Colors`, `Animations`, `Layout`, `Display layout`,
  `Color palette`, `Enable animations`, `Animation speed`,
  `Apply layout preset`, `Export/Import layout`, `Boss timeline: `, `Palette: `,
  `BURST`, `Hold CD`, `Prepare`, preset names and related strings to every
  locale file (RU translated, others fall back to English).
- Version bumped to 3.2.2 across all 11 `.toc` files and `DH.Version`.

## [3.2.1] - 2026-10-12

### Added

- **Boss profiles.** `db.boss_profiles[encounterID]` stores per-boss overrides
  (`target_mode`, `cooldowns`, `cooldown_order`, `activity_profile`,
  `display_count`). `ENCOUNTER_START` applies the stored profile (or a raid
  preset when none is stored); `ENCOUNTER_END` restores the player's own
  settings. New `DH:ApplyBossProfile` / `DH:RestoreDefaultProfile` /
  `DH:OnEncounterStart` / `DH:OnEncounterEnd`, plus `DH:ExportBossProfiles` /
  `DH:ImportBossProfiles` (safe text, no `loadstring`). Raid presets for ICC,
  ToC, Ulduar, Naxxramas and RS ship as recommendations. Controlled by
  `boss_profiles_enabled` (default off).
- **Combat log (CSV).** `/rc log start|stop|dump|csv|clear` records one row per
  player `SPELL_CAST_SUCCESS` (`time,spec,rec1,rec2,rec3,mana,hp,target_hp,action_cast`).
  Capped at 5000 rows (oldest dropped). `/rc log csv` copies the CSV into the
  `RotationCoreCSV` SavedVariable (WoW cannot write arbitrary files mid-session;
  the client writes `SavedVariables/RotationCoreCSV.lua` on reload/logout).
  Controlled by `combat_log_enabled` (default off).
- **Skill statistics.** `ns.skillStats[spellId] = { recommended, cast, missed }`
  tracks how often each ability was suggested and whether the player followed
  it. `/rc stats` lists the top 10 by missed casts; `/rc stats reset` clears the
  table (also reset on each `ENCOUNTER_START`). Controlled by `stats_enabled`.
- **Ideal-DPS comparison.** Fights are timed from `PLAYER_REGEN_*` /
  `ENCOUNTER_*` and player damage is summed from the combat log. On fight end
  `DH:ReportFight` prints `DPS`, estimated ideal DPS and the loss percentage,
  plus the five worst abilities by lost damage. `/rc stats dps` reprints the
  last fight. Controlled by `ideal_dps_enabled`.
- Options → **Profiles → Boss Profiles**: enable toggle, known-boss list with
  apply/save/delete, "capture current encounter", export/import and one-click
  raid presets.

### Changed

- `RotationCore.toc` SavedVariables gained `RotationCoreCSV`.
- Locale: added `Boss Profiles`, `Log`, `Stats`, `Comparison`,
  `No stats recorded.`, `Boss profile applied: `, `Default profile restored.`
  and `Combat log recording: ` to every locale file.
- Version bumped to 3.2.1 across all 11 `.toc` files and `DH.Version`.

## [3.2.0] - 2026-10-12

### Added

- **Event-driven update loop.** `update_mode = "events"` (new default) reacts
  to combat log, resource and aura events instantly and no longer runs an
  `OnUpdate` poller out of combat; `poll_frequency` (1-30 Hz) only applies to
  `update_mode = "poll"`. `DH:SyncUpdateLoop()` installs/removes the OnUpdate
  script so an idle client costs nothing.
- **Build auto-detection.** New `DH:RegisterBuildDetector`,
  `DH:GetBuildInfo()` / `DH:GetBuild()` and a cached `state.build` descriptor
  (`key` / `spec` / `source` / `confident`), invalidated on talent and glyph
  changes. Mage fire is split into `ttw` / `ffb`; the other nine classes use
  their spec. Controlled by `build_detect_mode`
  (off / talents / talents_glyphs / talents_glyphs_stats) and
  `build_detect_log`.
- **Cleave target mode.** `target_mode` is now `single` / `cleave` (2-3
  enemies) / `aoe` / `auto`, backed by `cleave_threshold` (default 2) and
  `aoe_threshold` (now default 4). `auto` resolves 1 enemy to single, 2-3 to
  cleave and 4+ to AOE. `DH:IsMultiTarget(sim)` / `DH:IsCleave(sim)` route a
  cleave through the class's multi-target list; nine classes received a
  dedicated cleave priority block (Warlock, Warrior, Mage, Death Knight,
  Hunter, Paladin, Priest, Rogue, Shaman); Druid reuses its existing
  multi-target block (Swipe / Hurricane).
- **Combat-log enemy counting.** Enemies the player has recently damaged are
  tracked for five seconds (`State:TrackCombatEnemy` /
  `State:UpdateCleaveEnemies`) and merged into the active-enemy count, so the
  cleave / AOE decision no longer depends on nameplate unit tokens.

### Changed

- Options: added AOE and cleave threshold sliders, a Build detection dropdown
  and an "uncertain build" log toggle (written to `/rc errors`).
- Locale: added `Cleave` and `Auto (single/cleave/aoe)` to every locale file
  (EN base, RU translation, fallback elsewhere).
- Settings migration: existing profiles keep their values; the new keys
  receive the defaults above via `MergeDefaults`.
- Version bumped to 3.2.0 across all 11 `.toc` files and `DH.Version`.

## [3.1.1] - 2026-10-11

### Fixed

- **Critical:** single-target (`target_mode = "single"`) could show an empty
  queue in raid/dungeon while AOE worked. The central fallback now recommends
  the first known ability whenever the rotation returns nothing, and
  `State:UpdateActiveEnemies` clamps to at least 1 for an attackable target.
- Duplicate recommendations: a repeated ability no longer fills the queue
  (spam-only gate in `RunSimulation`), fixing "frostbolt x3".
- `/rc lock` now tears down the Cooldowns/Interrupts move boxes explicitly so
  no black square is left behind.
- Fixed `attempt to call global 'EnsureFrame' (a nil value)` on the icon
  window's right-click handler (forward declaration in `SpellFrame.lua`).
- Option rows no longer overlap: taller, evenly spaced rows for checkboxes,
  sliders and dropdowns; the slider label is now anchored above the slider and
  its min/max labels below it, so every row fits inside its own band.
- **Menu mode** (Simple / Advanced) now really drives the window: in Simple
  mode the **Advanced** tab (glow / scanner / debug) is hidden and any open
  advanced tab falls back to General. The Class tab's "Show advanced settings"
  reveal is now persisted (`show_advanced_settings`).

### Added

- **Spell queue** settings section: orientation (row/column), icon size and
  gap, number of icons, and visibility toggles. GCD timer, remaining-time
  countdown and priority numbers are wired into the icon rendering.
- **Dark / light theme** (`theme`) applied to the options window, the Setup
  Wizard and the icon window through a shared palette.
- **Resizable options window** with a custom 3.3.5a resize grip and persisted
  size.
- **Wizard "Spell queue" step** (Compact / Standard / Large / Vertical
  presets).
- `/rc spec <name>` (build picker), `/rc pause` (freeze recommendations) and
  `/rc test rotation` (rotation self-test).
- **Window** toggles for the icon window: show background, border and title
  (`show_background`, `show_border`, `show_title`) plus the paused label
  (`paused_text`). `auto_save` remains a reserved key (SavedVariables persist
  automatically on 3.3.5a).
- Complete option tooltips: an English base is now loaded for every locale
  (previously non-RU clients saw raw keys) and the RU overrides were extended,
  so every setting shows a localized title + description.
- The old single, very long **General** tab was split into three menu sections:
  **General**, **Interface** (icon-window look) and **Advanced**.
- Resizable **Cooldowns** window: a corner drag-grip (and a "Cooldowns window
  size" slider) scales it; the size is saved per profile.
- Localization now supports every official WotLK 3.3.5a locale (enUS, enGB,
  deDE, frFR, esES, esMX, ruRU, ptBR, itIT, koKR, zhCN, zhTW). Each language
  lives in its own `Locale_<code>.lua` and all are **complete** (628 keys,
  verified against the RU key set): deDE, frFR, esES (also covers esMX), ptBR,
  itIT, koKR, zhCN and zhTW. enUS/enGB use the English base, ruRU stays in
  `Locale.lua`.
- Training reason taxonomy (`execute_phase`, `burst_cd_ready`, `proc_active`,
  `dot_missing`, `gcd_wait`, `resource_low`, `filler`, `priority`) printed as
  `Cast <name> (<reason>)`.

### Removed

- **WeakAuras bridge** - `/rc wa`, callback registration, `BuildAuraData`,
  `ExportToWeakAuras`, `FireAuraCallbacks`, defaults (`weakauras_export_enabled`,
  `weakauras_aura_name`) and all locale/doc references.
- Character resource / "HP" bar in the bottom-left of the options window.

### Changed

- Version bumped to **3.1.1** in all `.toc` files.

## [3.1.0] - 2026-10-11

### Added

- **Help tab** (sections A-J): quick start, priority legend, icon/cooldown/
  interrupt windows, training mode, import/export, per-spec settings, PvP,
  heal-spec DPS, hotkeys and slash commands, RU + EN.
- `/rc help` (Help tab) and `/rc help full` (Setup Wizard); "Open help" button
  on the Wizard's final step.
- **Option tooltips** with `_desc`, `_default` and `_affects` for the core
  general/advanced settings (40+ settings).
- **Training mode** reasons: every recommendation carries a category
  (Priority / Cooldown / DoT / GCD / Execute), shown in the icon tooltip;
  chat + optional sound fire only when the top recommendation changes.
- **Heal-spec DPS** dedicated modes: `holy_paladin_dps`, `resto_shaman_dps`,
  `resto_druid_dps`, `discipline_dps`, `holy_priest_dps`, plus new abilities
  (Holy Shock, Smite, Holy Fire, Holy Nova, ...).
- **PvP priority branches** for all 10 classes (`RegisterPvPSpec`):
  interrupt > control > burst > survival > DoT > filler, gated by
  `pvp_mode_enabled` (`pvp_burst_threshold` default 50).
- New PvP abilities (Counterspell, Polymorph, Frost Nova, Ice Block, Blink,
  Fear, Howl of Terror, Spell Lock, Pummel, Hamstring, Intimidating Shout,
  Mind Freeze, Strangulate, Chains of Ice, Cyclone, Entangling Roots, Bash,
  Scatter Shot, Wyvern Sting, Intimidation, Deterrence, Hammer of Justice,
  Repentance, Psychic Scream, Silence, Fear Ward, Kick, Kidney Shot, Blind,
  Sap).
- New settings: `auto_reload_on_talent_change`, `training_chat_output`,
  `training_sound`, `pvp_mode_enabled`, `pvp_burst_threshold`,
  `weakauras_export_enabled`, `weakauras_aura_name`.

### Changed

- Renamed `aura_export_enabled` -> `weakauras_export_enabled`.
- Talent changes now drop the cached talent index (`ns.talentIndex`), rebuild
  caches immediately and (optionally) defer the rebuild one frame via
  `C_Timer.After` so talent data is never read mid-event.
- `TogglePvPMode` uses the `pvp_mode_enabled` flag instead of switching
  `activity_profile`.
- Version bumped to **3.1.0** in all `.toc` files.

### Notes

- No `loadstring` on raw text; profile import uses a custom parser.
- No API 4.0+ / `C_*` usage.

## [3.0.0]

- Baseline: core highlight engine, icon window, cooldowns/interrupt windows,
  profiles, per-class rotation modules.
