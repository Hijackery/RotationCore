-- Registration.lua
-- Registration API. Split out of RotationCore.lua.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

-- ============================================================================
-- REGISTRATION API
-- Class modules use these to register their data into the framework.
-- ============================================================================

-- Registered class data (populated by class modules)
ns.registered = {
    buffs = {}, -- List of buff keys to track
    debuffs = {}, -- List of debuff keys to track
    cooldowns = {}, -- { key = spellId } for cooldown tracking
    talents = {}, -- { { tab, index, key }, ... }
    glyphs = {}, -- { [glyphSpellId] = key, ... }
    buffMap = {}, -- { [spellId] = buffKey, ... }
    debuffMap = {}, -- { [spellId] = debuffKey, ... }
    externalDebuffMap = {}, -- { [spellId] = debuffKey, ... }
    debuffNamePatterns = {}, -- { { pattern, key }, ... } for name-based fallback
    externalDebuffNamePatterns = {}, -- same for external debuffs
    buffNamePatterns = {}, -- { { pattern, key }, ... } for name-based buff fallback
    combatLogHandlers = {}, -- Functions called on COMBAT_LOG_EVENT_UNFILTERED
    formHandlers = {}, -- { formId = { update = fn, spec = fn }, ... }
    specDetector = nil, -- Function that returns current spec string
    buildDetector = nil, -- Function (spec, state, mode) -> buildKey, source
    modes = {}, -- Rotation modes for minimap dropdown
    gcdSpellId = nil, -- Spell ID used to check GCD
    defaults = {}, -- Class-specific default settings
    fallbackAbilities = {}, -- Last-resort ability keys per class (class-registered)
    procBuffs = {}, -- { [buffKey] = { minStacks = n } } proc-sound triggers
    spellSchool = nil, -- Spell school for GetSpellBonusDamage (nil = Nature)
}

-- Register buff keys to track
function DH:RegisterBuffs(buffs)
    for _, buff in ipairs(buffs) do
        table.insert(ns.registered.buffs, buff)
    end
end

-- Register debuff keys to track
function DH:RegisterDebuffs(debuffs)
    for _, debuff in ipairs(debuffs) do
        table.insert(ns.registered.debuffs, debuff)
    end
end

-- Register cooldowns: { key = spellId, ... }
function DH:RegisterCooldowns(cooldowns)
    for key, spellId in pairs(cooldowns) do
        ns.registered.cooldowns[key] = spellId
    end
end

-- Register talents.
-- Entries may use the legacy { tab, index, key } row-major ordinal form or
-- the preferred { tab=, tier=, column=, key= } coordinate form (resolved at
-- runtime against the real tree, so it survives index quirks). State.lua
-- handles both via a (tier,column)->ordinal lookup built at talent update.
function DH:RegisterTalents(talents)
    for _, data in ipairs(talents) do
        table.insert(ns.registered.talents, data)
    end
end

-- Register glyphs: { [referenceGlyphSpellId] = key, ... }
-- The spell id is only used to derive the glyph's localized name; the socketed
-- glyph is then matched by name (see State.lua UpdateGlyphs).
function DH:RegisterGlyphs(glyphs)
    for spellId, key in pairs(glyphs) do
        ns.registered.glyphs[spellId] = key
    end
end

-- Register last-resort basic abilities (class keys) used when every
-- recommendation was filtered out as unknown. Class modules call this so the
-- core no longer hardcodes any class's ability keys.
function DH:RegisterFallbackAbilities(list)
    for _, key in ipairs(list) do
        table.insert(ns.registered.fallbackAbilities, key)
    end
end

-- Register a buff whose rising edge plays the proc sound.
-- opts (optional): { minStacks = n } requires that many stacks before it
-- counts as a proc (e.g. Maelstrom Weapon at 5). Class modules call this so
-- the core no longer hardcodes which class buffs are "procs".
function DH:RegisterProcBuff(key, opts)
    ns.registered.procBuffs[key] = opts or {}
end

-- Register the spell school used by GetSpellBonusDamage (e.g. 4 = Nature,
-- 3 = Fire, 16 = Frost). Defaults to Nature when no class registers one.
function DH:RegisterSpellSchool(schoolId)
    ns.registered.spellSchool = schoolId
end

-- Register buff spell ID mapping: { [spellId] = buffKey, ... }
function DH:RegisterBuffMap(map)
    for spellId, key in pairs(map) do
        ns.registered.buffMap[spellId] = key
    end
end

-- Register debuff spell ID mapping: { [spellId] = debuffKey, ... }
function DH:RegisterDebuffMap(map)
    for spellId, key in pairs(map) do
        ns.registered.debuffMap[spellId] = key
    end
end

-- Register external debuff mapping (from other players)
function DH:RegisterExternalDebuffMap(map)
    for spellId, key in pairs(map) do
        ns.registered.externalDebuffMap[spellId] = key
    end
end

-- Register debuff name patterns for fallback matching
function DH:RegisterDebuffNamePatterns(patterns)
    for _, data in ipairs(patterns) do
        table.insert(ns.registered.debuffNamePatterns, data)
    end
end

-- Register buff name patterns for fallback matching
function DH:RegisterBuffNamePatterns(patterns)
    for _, data in ipairs(patterns) do
        table.insert(ns.registered.buffNamePatterns, data)
    end
end

-- Register external debuff name patterns
function DH:RegisterExternalDebuffNamePatterns(patterns)
    for _, data in ipairs(patterns) do
        table.insert(ns.registered.externalDebuffNamePatterns, data)
    end
end

-- Register combat log handler function
function DH:RegisterCombatLogHandler(fn)
    if type(fn) ~= "function" then
        return
    end
    table.insert(ns.registered.combatLogHandlers, fn)
end

-- Register spec detector function
function DH:RegisterSpecDetector(fn)
    ns.registered.specDetector = fn
end

-- Register a fallback spec detector (used when the primary detector
-- returns nil/unknown). LibClassicSpecs hooks in here so the class
-- module detectors (registered later via RegisterSpecDetector) win.
function DH:RegisterSpecDetectorFallback(fn)
    ns.registered.specDetectorFallback = fn
end

-- Register a build detector (Improvement 2). fn(spec, state, mode) returns a
-- build key plus a source tag ("talents"/"glyphs"/"stats") or nil to fall back
-- to the spec. Only invoked lazily by State:GetBuildInfo().
function DH:RegisterBuildDetector(fn)
    ns.registered.buildDetector = fn
end

-- Return the cached build descriptor (or nil before State exists).
function DH:GetBuildInfo()
    if self.State and self.State.GetBuildInfo then
        return self.State:GetBuildInfo()
    end
    return nil
end

-- Convenience: just the build key.
function DH:GetBuild()
    local info = self:GetBuildInfo()
    return info and info.key or nil
end

-- Register a rotation mode for the minimap dropdown
-- key: unique string, data: { name, icon, rotation = fn(addon) }
function DH:RegisterMode(key, data)
    ns.registered.modes = ns.registered.modes or {}
    data.key = key
    table.insert(ns.registered.modes, data)
end

-- Register a "safe" mode for specs whose rotation is not implemented (e.g.
-- healers). It recommends nothing and prints an informative message when it
-- becomes active, instead of silently running the wrong DPS rotation.
function DH:RegisterSafeMode(key, name, icon, message)
    return self:RegisterMode(key, {
        name = name,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        safe = true,
        message = message or "Rotations for this spec are not supported",
        rotation = function()
            return {}
        end,
    })
end

-- Register a real healer mode. Heal modes are isolated from the DPS modes:
-- they only produce heal recommendations, never borrow a DPS rotation unless
-- the explicit heal_dps_mode setting allows it. The core also suppresses the
-- generic "first known attack" fallback while a heal mode is active.
function DH:RegisterHealMode(key, name, icon, rotation)
    return self:RegisterMode(key, {
        name = name,
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        heal = true,
        rotation = rotation or function()
            return {}
        end,
    })
end

-- Post-phase 4: register a class PvP priority branch.
-- fn(addon, state, ctx) -> recs. ctx = { burst = bool, burstThreshold = n }.
-- Consulted instead of the PvE rotation while pvp_mode_enabled is true.
function DH:RegisterPvPRotation(fn)
    ns.registered.pvpRotation = fn
end

-- Register a declarative PvP priority spec:
--   { interrupt={...}, control={...}, burst={...}, survival={...},
--     dot={...}, filler={...} }
-- Builds the recommendation list as:
--   interrupt (target casting) -> control -> burst (target hp <= threshold)
--   -> survival -> dot (missing) -> filler.
function DH:RegisterPvPSpec(spec)
    ns.registered.pvpSpec = spec
    self:RegisterPvPRotation(function(addon, state, ctx)
        return self:BuildPvPRecommendations(addon, state, ctx)
    end)
end

function DH:BuildPvPRecommendations(addon, state, ctx)
    local spec = ns.registered.pvpSpec
    local recs = {}
    if not spec then
        return recs
    end
    local abilities = addon.Class and addon.Class.abilities or {}
    local function Ready(key)
        local a = abilities[key]
        if not a then
            return false
        end
        return DH:SpellReady(a.id)
    end
    local function add(list)
        for _, key in ipairs(list or {}) do
            if abilities[key] and Ready(key) then
                recs[#recs + 1] = { ability = key, priority = #recs + 1 }
            end
        end
    end
    local casting = state and state.target and state.target.casting
    if casting then
        add(spec.interrupt)
    end
    add(spec.control)
    if ctx and ctx.burst then
        add(spec.burst)
    end
    add(spec.survival)
    if not casting then
        add(spec.interrupt)
    end
    for _, key in ipairs(spec.dot or {}) do
        local d = state and state.debuff and state.debuff[key]
        if abilities[key] and not (d and d.up) and Ready(key) then
            recs[#recs + 1] = { ability = key, priority = #recs + 1 }
        end
    end
    add(spec.filler)
    return recs
end

-- Register GCD reference spell
function DH:RegisterGCDSpell(spellId)
    ns.registered.gcdSpellId = spellId
end

-- Register abilities that are melee range (for UI range overlay)
function DH:RegisterMeleeAbilities(keys)
    for _, key in ipairs(keys) do
        DH.Class.meleeAbilities[key] = true
    end
end

-- Register class-specific default settings (merged into defaults)
function DH:RegisterDefaults(classDefaults)
    -- Merge instead of replace: Config.lua injects its own defaults into the
    -- same table and class modules may load after that (LoadOnDemand).
    for k, v in pairs(classDefaults) do
        ns.registered.defaults[k] = v
    end
end

-- ============================================================================
-- M29: shared class-module factories
-- These remove the repeated boilerplate that every RotationCore_<Class> module
-- carried inline (ability-table finalisation, the `common` defaults block, the
-- status slash command and the live-debug frame updater). Behaviour is
-- byte-for-byte identical to the old inline code; only the location moved.
-- ============================================================================

-- Tag every ability with its key, index it by name and resolve its texture
-- from the spell id. This exact loop was duplicated in all ten class modules.
function DH:RegisterAbilityTable()
    local abilities = DH.Class and DH.Class.abilities
    if not abilities or not DH.Class.abilityByName then
        return
    end
    for key, ability in pairs(abilities) do
        ability.key = key
        DH.Class.abilityByName[ability.name] = ability
        if ability.id then
            local name, rank, icon = GetSpellInfo(ability.id)
            if icon then
                ability.texture = icon
            end
        end
    end
end

-- Settings stored under the `common` key are identical for every class bar a
-- handful of extras. Classes call RegisterCommonDefaults(extras); extras win
-- over the base values and the merged table is registered as usual.
ns.COMMON_DEFAULTS = {
    dummy_ttd = 300,
    menu_mode = "simple",
    auto_cooldowns = true,
    cooldown_order = "priority",
    target_mode = "single",
    activity_profile = "raid",
    ttd_raid = 300,
    ttd_dungeon = 60,
    ttd_solo = 15,
    ttd_pvp = 30,
    hold_cd_at_end = true,
    cd_hold_ttd = 30,
    use_glyphs = true,
    raid_buffs = true,
    display_count = 3,
    sound_procs = false,
    sound_procs_file = "Sound\\Interface\\AlarmClockWarning3.wav",
    proc_flash = false,
    proc_flash_speed = 3.0,
    log_decisions = false,
    log_max_lines = 1000,
    icon_size = 36,
    icon_gap = 4,
    icon_columns = 3,
    glow_style = "pulse",
    guide_marker = false, -- bobbing chevron above the next ability button
    glow_frequency = 1.0, -- pulse speed multiplier (1 = style default)
    glow_lines = 1, -- concentric border rings (1 = classic single ring)
    glow_thickness = 1.5, -- border size multiplier
    spellframe_font = "default",
    spellframe_font_size = 0, -- 0 = keep the client default size
    spellFrame_pos_per_spec = false,
}

function DH:RegisterCommonDefaults(extra)
    local merged = {}
    for k, v in pairs(ns.COMMON_DEFAULTS) do
        merged[k] = v
    end
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            merged[k] = v
        end
    end
    ns.registered.defaults.common = merged
end

-- Build the live-debug frame updater from a class `buildLines(s, rec1, rec2,
-- rec3)` callback returning the class-specific middle lines. The factory owns
-- the header, the three recommendation slots and the frame text/show calls.
function DH:MakeDebugFrameUpdater(buildLines)
    return function()
        if not ns.DebugFrame then
            return
        end
        local s = DH.State
        local rec1 = ns.recommendations[1] and ns.recommendations[1].ability or "none"
        local rec2 = ns.recommendations[2] and ns.recommendations[2].ability or "none"
        local rec3 = ns.recommendations[3] and ns.recommendations[3].ability or "none"
        local lines = { "|cFFFFFF00=== Live Debug ===|r" }
        if buildLines then
            local mid = buildLines(s, rec1, rec2, rec3)
            if type(mid) == "table" then
                for i = 1, #mid do
                    lines[#lines + 1] = mid[i]
                end
            end
        end
        lines[#lines + 1] = string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3)
        ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
        ns.DebugFrame:Show()
    end
end

-- Register form update handler
function DH:RegisterFormHandler(formId, handler)
    ns.registered.formHandlers[formId] = handler
end

-- v3.4.0: the class defensive that the battle-context gate recommends first
-- during a "defensive" phase (Improvement 1). Optional; without it the gate
-- stays inactive.
function DH:RegisterDefensiveAbility(key)
    ns.defensiveKey = key
end
