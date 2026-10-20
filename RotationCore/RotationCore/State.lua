-- State.lua
-- Generic game state tracking for RotationCore (3.3.5a compatible)
-- Class modules register buffs, debuffs, cooldowns, talents, glyphs via the registration API.

local DH = RotationCore
if not DH then return end

local ns = DH.ns
local state = DH.State

-- Localization helper (Locale.lua fills DH.L lazily)
local function L(s)
    local tbl = DH.L
    if tbl and type(s) == "string" then return tbl[s] end
    return s
end

-- LibClassicSpecs fallback for spec detection (3.3.5a Wrath).
-- The lib registers as 'LibClassicSpecs-Doadin'; module-level talent
-- detectors stay authoritative, LCS is only a safety net.
-- LCS returns the lib's static English spec name ("Beast Mastery",
-- "Restoration", ...). Normalise it to the key shape used by the class
-- modules ("beast_mastery", "resto", ...).
local SPEC_NAME_ALIASES = {
    restoration = "resto",
}
do
    local ok, LCS = pcall(function() return LibStub and LibStub("LibClassicSpecs-Doadin", true) end)
    if ok and LCS and DH.RegisterSpecDetectorFallback then
        DH:RegisterSpecDetectorFallback(function()
            local specIndex = LCS:GetSpecialization()
            if not specIndex then return nil end
            local specId, specName = LCS:GetSpecializationInfo(specIndex)
            if not specId or not specName then return nil end
            local key = specName:lower():gsub("%s+", "_")
            return SPEC_NAME_ALIASES[key] or key
        end)
    end
end


-- State variables
state.now = 0
state.offset = 0
state.gcd = 0
state.gcd_remains = 0
state.latency = 0.05

state.inCombat = false
state.GUID = nil
state.level = 1

-- Resources (using power type numbers for 3.3.5a)
-- 0 = Mana, 1 = Rage, 2 = Focus, 3 = Energy, 4 = Happiness, 5 = Runes, 6 = Runic Power
state.health = { current = 0, max = 0, pct = 0 }
state.mana = { current = 0, max = 0, pct = 0, regen = 0 }
state.energy = { current = 0, max = 100, regen = 10 }
state.rage = { current = 0, max = 100 }
state.combo_points = { current = 0, max = 5 }
state.runic_power = { current = 0, max = 100 }

-- Target info
state.target = {
    exists = false,
    guid = nil,
    health = { current = 0, max = 0, pct = 0 },
    time_to_die = 300,
    distance = 0,
    inRange = false,
    canAttack = false,
}

-- Buffs and debuffs
state.buff = {}
state.debuff = {}

-- Cooldowns
state.cooldown = {}

-- Talent tracking
state.talent = {}

-- Glyph tracking
state.glyph = {}

-- Form tracking (Druid forms, stances, etc.)
state.form = 0
state.cat_form = false
state.bear_form = false
state.moonkin_form = false

-- Active enemies tracking
state.active_enemies = 1

-- Boss encounter tracking (prompt 2): set on ENCOUNTER_START, cleared on END.
state.encounter_id = nil
state.encounter_name = nil

-- Stat tracking
state.stat = {
    attack_power = 0,
    spell_power = 0,
    crit = 0,
    haste = 0,
    armor_pen_rating = 0,
    spell_haste = 1,
}

-- Settings shortcut
state.settings = {}

-- Dirty flags for expensive, event-driven state groups. true = rebuild on the
-- next Reset(); set by DH:MarkStateDirty from the core event handler.
state._dirty = {
    resources = true,
    cooldowns = true,
    auras = true,
    talents = true,
    glyphs = true,
    stats = true,
}

-- Mark one group (or "all") dirty so the next Reset() rebuilds it.
function state:MarkDirty(kind)
    if kind == "all" or kind == nil then
        for k in pairs(self._dirty) do self._dirty[k] = true end
        return
    end
    if self._dirty[kind] ~= nil then
        self._dirty[kind] = true
    end
end

-- ============================================================================
-- METATABLES
-- ============================================================================

-- Metatable for buff tracking
local buffMT = {
    __index = function(t, k)
        if k == "up" then
            return t.remains > 0
        elseif k == "down" then
            return t.remains <= 0
        elseif k == "remains" then
            return t.expires and math.max(0, t.expires - GetTime()) or 0
        elseif k == "stack" or k == "stacks" then
            return t.count or 0
        elseif k == "duration" then
            return t._duration or 0
        end
        return rawget(t, k)
    end
}

local function CreateAuraTable()
    return setmetatable({
        expires = 0,
        count = 0,
        _duration = 0,
        applied = 0,
        last_applied = 0,
    }, buffMT)
end

-- Metatable for cooldown tracking
local cooldownMT = {
    __index = function(t, k)
        if k == "up" or k == "ready" then
            return t.remains <= 0.1
        elseif k == "down" then
            return t.remains > 0.1
        elseif k == "remains" then
            local start, duration = t.start or 0, t.duration or 0
            if start == 0 then return 0 end
            local now = state.now or GetTime()
            return math.max(0, start + duration - now)
        end
        return rawget(t, k)
    end
}

local function CreateCooldownTable()
    return setmetatable({
        start = 0,
        duration = 0,
    }, cooldownMT)
end

-- Shared read-only sentinels: returned on a metatable miss so we don't allocate
-- a fresh table per lookup (L11). Nothing writes through these.
local ZERO_TALENT = { rank = 0 }
local DISABLED_GLYPH = { enabled = false }

-- Metatable for talents
local talentMT = {
    __index = function(t, k)
        local data = rawget(t, k)
        if data then return data end
        return ZERO_TALENT
    end
}

-- Metatable for glyphs
local glyphMT = {
    __index = function(t, k)
        return DISABLED_GLYPH
    end
}

-- Export CreateAuraTable for class modules that need custom aura tracking
ns.CreateAuraTable = CreateAuraTable
ns.CreateCooldownTable = CreateCooldownTable

-- ============================================================================
-- INITIALIZATION (uses registered data)
-- ============================================================================

function state:Init()
    self.GUID = UnitGUID("player")
    self.level = UnitLevel("player")

    -- Initialize buff tables from registered data
    for _, buff in ipairs(ns.registered.buffs) do
        self.buff[buff] = CreateAuraTable()
    end

    -- Initialize debuff tables from registered data
    for _, debuff in ipairs(ns.registered.debuffs) do
        self.debuff[debuff] = CreateAuraTable()
    end

    -- Initialize cooldown tables from registered data
    for key, _ in pairs(ns.registered.cooldowns) do
        self.cooldown[key] = CreateCooldownTable()
    end

    -- Set metatables
    setmetatable(self.talent, talentMT)
    setmetatable(self.glyph, glyphMT)
end

-- ============================================================================
-- STATE RESET (called each update cycle)
-- ============================================================================

function state:Reset()
    self.now = GetTime()
    self.GUID = UnitGUID("player")
    self.level = UnitLevel("player")

    -- Update combat state
    self.inCombat = UnitAffectingCombat("player")
    ns.inCombat = self.inCombat

    -- Movement detection
    self.isMoving = (GetUnitSpeed("player") or 0) > 0

    -- Update GCD
    -- GetSpellCooldown returns (start, duration) — if a spell has no real CD,
    -- it returns the GCD. If it has a real CD, it returns whichever is longer.
    -- We check the registered GCD spell first. If it reports a long CD (it has
    -- a real cooldown), we scan registered cooldowns to find one that's only on GCD.
    self.gcd = 1.5
    self.gcd_remains = 0
    self._gcd_start = 0

    local gcdSpellId = ns.registered.gcdSpellId
    local gcdStart, gcdDuration

    if gcdSpellId then
        local knownId = DH.ResolveKnownSpellId and DH:ResolveKnownSpellId(gcdSpellId) or gcdSpellId
        gcdStart, gcdDuration = GetSpellCooldown(knownId)
    end

    -- If the reference spell is on a real CD (> 2s) or missing, use a spell that
    -- is only on the GCD. The pick is cached and reused until it stops
    -- reporting a GCD, so the full registered-cooldown scan is rare (M4).
    if not gcdStart or not gcdDuration or gcdDuration > 2 then
        local cachedId = ns._gcdSpellResolved
        if cachedId then
            local s, d = GetSpellCooldown(cachedId)
            if s and s > 0 and d and d > 0 and d <= 2 then
                gcdStart, gcdDuration = s, d
            else
                ns._gcdSpellResolved = nil
                cachedId = nil
            end
        end
        if not cachedId then
            for _, spellId in pairs(ns.registered.cooldowns) do
                local knownId = DH.ResolveKnownSpellId and DH:ResolveKnownSpellId(spellId) or spellId
                local s, d = GetSpellCooldown(knownId)
                if s and s > 0 and d and d > 0 and d <= 2 then
                    gcdStart, gcdDuration = s, d
                    ns._gcdSpellResolved = knownId
                    break
                end
            end
        end
    end

    if gcdStart and gcdStart > 0 and gcdDuration and gcdDuration > 0 and gcdDuration <= 2 then
        self.gcd = gcdDuration  -- Actual GCD (affected by haste)
        self.gcd_remains = math.max(0, gcdStart + gcdDuration - self.now)
        self._gcd_start = gcdStart
    end

    -- Track current cast (spells with cast time longer than GCD)
    self.cast_remains = 0
    local spell, _, _, _, startTime, endTime = UnitCastingInfo("player")
    if spell and endTime then
        self.cast_remains = math.max(0, endTime / 1000 - self.now)
    end
    -- Also check channels (e.g. Drain Soul)
    if self.cast_remains == 0 then
        spell, _, _, _, startTime, endTime = UnitChannelInfo("player")
        if spell and endTime then
            self.cast_remains = math.max(0, endTime / 1000 - self.now)
        end
    end

    -- Cheap, always-current updates
    self:UpdateTarget()
    self:UpdateActiveEnemies()
    self:UpdateForm()
    self:UpdateStats()

    -- Expensive groups: only rebuilt when their driving event fired
    -- (see DH:MarkStateDirty). Between events the *_remains/expires accessors
    -- keep ticking down dynamically, so cached values stay accurate.
    if self._dirty.resources then
        self:UpdateResources()
        self._dirty.resources = false
    end

    if self._dirty.auras then
        self:UpdateBuffs()
        self:UpdateDebuffs()
        self._dirty.auras = false
    end

    if self._dirty.cooldowns then
        self:UpdateCooldowns()
        self._dirty.cooldowns = false
    end

    if self._dirty.talents then
        self:UpdateTalents()
        self._dirty.talents = false
    end

    if self._dirty.glyphs then
        self:UpdateGlyphs()
        self._dirty.glyphs = false
    end

    -- Update settings reference
    if DH.db then
        self.settings = DH.db
    end
end

-- ============================================================================
-- RESOURCE UPDATES
-- ============================================================================

function state:UpdateResources()
    -- Health
    self.health.current = UnitHealth("player")
    self.health.max = UnitHealthMax("player")
    self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 0

    -- Mana (power type 0)
    self.mana.current = UnitPower("player", 0)
    self.mana.max = UnitPowerMax("player", 0)
    self.mana.pct = self.mana.max > 0 and (self.mana.current / self.mana.max * 100) or 0

    -- Energy (power type 3)
    self.energy.current = UnitPower("player", 3)
    self.energy.max = UnitPowerMax("player", 3)
    if self.energy.max == 0 then self.energy.max = 100 end

    -- Rage (power type 1)
    self.rage.current = UnitPower("player", 1)
    self.rage.max = 100

    -- Combo Points
    self.combo_points.current = GetComboPoints("player", "target")

    -- Runic Power (power type 6)
    self.runic_power.current = UnitPower("player", 6)
    self.runic_power.max = UnitPowerMax("player", 6)
    if self.runic_power.max == 0 then self.runic_power.max = 100 end
end

-- Active-enemy scan is throttled (0.5s) so the AoE check does not run every
-- tick. Force a rescan on target change via state:ForceEnemyScan().
local ENEMY_SCAN_INTERVAL = 0.5

-- Count distinct attackable units near the player (target, focus, mouseover,
-- nameplates, party targets). Deduplicated by GUID so the same mob referenced
-- by several unit tokens is only counted once.
local function CountActiveEnemies()
    local seen = {}
    local count = 0

    local function consider(unit)
        if not unit or not UnitExists(unit) then return end
        if not UnitCanAttack("player", unit) then return end
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return end
        local guid = UnitGUID(unit)
        if guid then
            if seen[guid] then return end
            seen[guid] = true
        end
        count = count + 1
    end

    consider("target")
    consider("focus")
    consider("mouseover")
    consider("targettarget")
    consider("pettarget")

    for i = 1, 4 do
        consider("nameplate" .. i)
    end

    if IsInGroup and IsInGroup() then
        for i = 1, 4 do
            consider("party" .. i .. "target")
        end
    end

    return count
end

function state:UpdateActiveEnemies()
    local now = self.now or GetTime()
    if now - (self._lastEnemyScan or 0) >= ENEMY_SCAN_INTERVAL then
        self._lastEnemyScan = now
        local n = CountActiveEnemies()
        n = math.max(n, self:UpdateCleaveEnemies())
        -- Defensive: a single attackable target is always at least one enemy,
        -- even if the scan missed it (e.g. throttling / token gaps). AOE/AUTO
        -- decisions must never see 0 when there is something to hit.
        if n < 1 and UnitExists("target") and UnitCanAttack("player", "target") then
            n = 1
        end
        self.active_enemies = n
    end
end

-- Force the next UpdateActiveEnemies() to rescan (e.g. on target change).
function state:ForceEnemyScan()
    self._lastEnemyScan = 0
end

-- Combat-log memory of enemies the player recently damaged (Improvement 3).
-- The cleave/AOE decision can therefore rely on real combat data instead of
-- nameplate unit tokens. An enemy is forgotten CLEAVE_MEMORY seconds after the
-- last damage event.
local CLEAVE_MEMORY = 5

function state:TrackCombatEnemy(destGUID)
    if not destGUID then return end
    self.recentEnemies = self.recentEnemies or {}
    self.recentEnemies[destGUID] = (self.now or GetTime()) + CLEAVE_MEMORY
end

function state:UpdateCleaveEnemies()
    local now = self.now or GetTime()
    local n = 0
    if self.recentEnemies then
        for guid, expiry in pairs(self.recentEnemies) do
            if expiry > now then
                n = n + 1
            else
                self.recentEnemies[guid] = nil
            end
        end
    end
    self.cleave_enemies = n
    return n
end

function state:UpdateTarget()
    self.target.exists = UnitExists("target")
    self.target.guid = UnitGUID("target")

    if self.target.exists then
        self.target.health.current = UnitHealth("target")
        self.target.health.max = UnitHealthMax("target")
        self.target.health.pct = self.target.health.max > 0 and (self.target.health.current / self.target.health.max * 100) or 0

        -- Estimate time to die
        if self.target.health.pct < 20 then
            self.target.time_to_die = 10
        elseif self.target.health.pct < 35 then
            self.target.time_to_die = 30
        else
            self.target.time_to_die = (DH.GetTTD and DH:GetTTD()) or 300
        end

        -- Check if target is a training dummy
        local name = UnitName("target")
        if name and name:find("Dummy") then
            self.target.time_to_die = (DH.GetSetting and DH:GetSetting("dummy_ttd")) or 300
            if self.debuff.training_dummy then
                self.debuff.training_dummy.expires = self.now + 3600
            end
        else
            if self.debuff.training_dummy then
                self.debuff.training_dummy.expires = 0
            end
        end

        -- Range check: native 3.3.5a CheckInteractDistance only.
        -- Recompute on target switch (guid change) or while unknown (0);
        -- never cache a value measured for a previous target.
        if self.target.distance == 0 or self._rangeGuid ~= self.target.guid then
            self._rangeGuid = self.target.guid
            -- fallback to CheckInteractDistance
            if CheckInteractDistance("target", 3) then
                self.target.distance = 5
                self.target.inRange = true
            elseif CheckInteractDistance("target", 4) then
                self.target.distance = 20
                self.target.inRange = false
            else
                self.target.distance = 40
                self.target.inRange = false
            end
        end

        self.target.canAttack = UnitCanAttack("player", "target")
    else
        self.target.health.current = 0
        self.target.health.max = 0
        self.target.health.pct = 0
        self.target.time_to_die = 0
        self.target.distance = 40
        self.target.inRange = false
        self.target.canAttack = false
        self._rangeGuid = nil
    end
end

-- ============================================================================
-- FORM / STANCE
-- ============================================================================

function state:UpdateForm()
    self.form = GetShapeshiftForm()

    -- Reset form booleans (class modules set these via form handlers)
    self.cat_form = false
    self.bear_form = false
    self.moonkin_form = false

    -- Dispatch to registered form handlers
    for formId, handler in pairs(ns.registered.formHandlers) do
        if self.form == formId then
            handler(self)
        end
    end
end

-- ============================================================================
-- BUFF / DEBUFF UPDATES (using registered maps)
-- ============================================================================

-- Buffs whose rising edge triggers the proc sound are registered by class
-- modules via DH:RegisterProcBuff (see ns.registered.procBuffs).

function state:UpdateBuffs()
    if type(UnitBuff) ~= "function" then return end
    -- Track which buff keys are form-related (set by form handlers)
    local formBuffKeys = {}
    for formId, _ in pairs(ns.registered.formHandlers) do
        -- Form handlers manage their own buff state, skip those
    end

    -- Reset non-form buff expires
    for key, buff in pairs(self.buff) do
        if type(buff) == "table" and buff.expires then
            -- Don't reset form buffs (handled by UpdateForm via form handlers)
            if not buff._isForm then
                buff.expires = 0
                buff.count = 0
            end
        end
    end

    -- Scan player buffs
    for i = 1, 40 do
        local name, _, icon, count, debuffType, duration, expirationTime, source, _, _, spellId = UnitBuff("player", i)
        if not name then break end

        local key = ns.registered.buffMap[spellId]

        -- Fallback to name patterns
        if not key and name then
            local lowerName = name:lower()
            for _, pattern in ipairs(ns.registered.buffNamePatterns) do
                if lowerName:find(pattern[1]) then
                    key = pattern[2]
                    break
                end
            end
        end

        if key and self.buff[key] then
            -- Permanent buffs (Righteous Fury, auras, etc.) have expirationTime = 0
            if not expirationTime or expirationTime == 0 then
                self.buff[key].expires = self.now + 7200  -- Treat as 2 hours
            else
                self.buff[key].expires = expirationTime
            end
            self.buff[key].count = count or 1
            self.buff[key]._duration = duration or 0
            self.buff[key].applied = (expirationTime and expirationTime > 0) and (expirationTime - (duration or 0)) or self.now
        end
    end

    -- Proc sound: play once each time a tracked proc appears (part 7).
    -- State is tracked even while the setting is off so re-enabling does
    -- not replay a stale edge.
    if not ns.prevProcs then ns.prevProcs = {} end
    local prev = ns.prevProcs
    local rose = false
    for key, opts in pairs(ns.registered.procBuffs) do
        local buff = self.buff[key]
        local active = false
        if buff then
            if opts.minStacks then
                active = (buff.count or 0) >= opts.minStacks
            else
                active = buff.up or false
            end
        end
        if active and not prev[key] then rose = true end
        prev[key] = active
    end
    if rose and DH.GetSetting and DH:GetSetting("sound_procs") and PlaySoundFile then
        -- Several procs can land inside one server batch; without a guard the
        -- sounds stack on top of each other. One play per 0.4 s is enough.
        local nowS = GetTime()
        if ns.lastProcSound and (nowS - ns.lastProcSound) < 0.4 then
            rose = false
        else
            ns.lastProcSound = nowS
        end
    end
    if rose and DH.GetSetting and DH:GetSetting("sound_procs") and PlaySoundFile then
        local file = DH:GetSetting("sound_procs_file")
        if ns.ResolveSound then
            file = ns.ResolveSound(file)
        end
        if not file or file == "" then
            file = "Sound\\Interface\\AlarmClockWarning3.wav"
        end
        PlaySoundFile(file)
    end
end

function state:UpdateDebuffs()
    if not self.target.exists then return end
    if type(UnitDebuff) ~= "function" then return end

    -- Reset debuff expires
    for key, debuff in pairs(self.debuff) do
        if type(debuff) == "table" and debuff.expires and key ~= "training_dummy" then
            debuff.expires = 0
            debuff.count = 0
        end
    end

    -- Scan target debuffs
    for i = 1, 40 do
        local name, _, icon, count, debuffType, duration, expirationTime, source, _, _, spellId = UnitDebuff("target", i)
        if not name then break end

        if source == "player" then
            -- Try spell ID map first
            local key = ns.registered.debuffMap[spellId]

            -- Fallback to name patterns
            if not key and name then
                local lowerName = name:lower()
                for _, pattern in ipairs(ns.registered.debuffNamePatterns) do
                    if lowerName:find(pattern[1]) then
                        key = pattern[2]
                        break
                    end
                end
            end

            if key and self.debuff[key] then
                self.debuff[key].expires = expirationTime or (self.now + 3600)
                self.debuff[key].count = count or 1
                self.debuff[key]._duration = duration or 0
            end
        end

        -- Track external debuffs (from other players)
        if source ~= "player" then
            local key = ns.registered.externalDebuffMap[spellId]

            if not key and name then
                local lowerName = name:lower()
                for _, pattern in ipairs(ns.registered.externalDebuffNamePatterns) do
                    if lowerName:find(pattern[1]) then
                        key = pattern[2]
                        break
                    end
                end
            end

            if key and self.debuff[key] then
                self.debuff[key].expires = expirationTime or (self.now + 3600)
            end
        end
    end
end

-- ============================================================================
-- COOLDOWN UPDATES (using registered data)
-- ============================================================================

function state:UpdateCooldowns()
    local gcdStart = self._gcd_start or 0
    local gcdDuration = self.gcd or 1.5

    for key, spellId in pairs(ns.registered.cooldowns) do
        -- Track the rank the player actually knows (max-rank ids registered by
        -- the class modules are wrong below max level).
        local knownId = DH.ResolveKnownSpellId and DH:ResolveKnownSpellId(spellId) or spellId
        local start, duration, enabled = GetSpellCooldown(knownId)
        if self.cooldown[key] then
            -- Filter out the GCD only when this spell reports exactly the same
            -- cooldown start/duration as the GCD; a real short cooldown must
            -- not be mistaken for the GCD.
            local isJustGCD = false
            if start and duration
               and start == gcdStart
               and math.abs(duration - gcdDuration) < 0.01 then
                isJustGCD = true
            end

            if not isJustGCD and duration and duration > 0 then
                self.cooldown[key].start = start or 0
                self.cooldown[key].duration = duration or 0
            else
                self.cooldown[key].start = 0
                self.cooldown[key].duration = 0
            end
        end
    end
end

-- ============================================================================
-- STAT UPDATES
-- ============================================================================

function state:UpdateStats()
    -- Cheap and always current: the sim reads the haste ratings every tick.
    self.stat.haste = GetCombatRatingBonus(18) -- CR_HASTE_MELEE
    local spellHaste = GetCombatRatingBonus(20) -- CR_HASTE_SPELL
    self.stat.spell_haste = 1 + (spellHaste / 100)

    -- Heavier stats are only read by external consumers, so rebuild them on the
    -- driving events (PLAYER_STATS / equipment / rating) instead of every tick.
    if self._dirty.stats then
        self:UpdateExtendedStats()
        self._dirty.stats = false
    end
end

-- Attack power / spell power / crit / armor penetration. Spell power uses the
-- class-registered school (DH:RegisterSpellSchool) and falls back to Nature.
function state:UpdateExtendedStats()
    local base, posBuff, negBuff = UnitAttackPower("player")
    self.stat.attack_power = base + posBuff + negBuff

    self.stat.spell_power = GetSpellBonusDamage(ns.registered.spellSchool or 4)

    self.stat.crit = GetCritChance()
    self.stat.armor_pen_rating = GetCombatRating(25) -- CR_ARMOR_PENETRATION
end

-- ============================================================================
-- TALENT / GLYPH UPDATES (using registered data)
-- ============================================================================

function state:BuildTalentIndexLookup()
    self._talentIndex = {}
    self._numTalents = {}

    if type(GetNumTalentTabs) ~= "function" or type(GetNumTalents) ~= "function"
        or type(GetTalentInfo) ~= "function" then
        return
    end

    local numTabs = GetNumTalentTabs()
    for tab = 1, numTabs do
        local n = GetNumTalents(tab)
        self._numTalents[tab] = n
        local byTier = {}
        -- Ordinals are row-major (left-to-right, top-to-bottom) and must NOT
        -- be assumed to equal a (tier,column) pair. To resolve a module's
        -- { tab, tier, column } registration we scan every ordinal and record
        -- the (tier,column) each one exposes via GetTalentInfo.
        for i = 1, n do
            local name, _, tier, column = GetTalentInfo(tab, i)
            if name and tier and column then
                byTier[tier] = byTier[tier] or {}
                byTier[tier][column] = i
            end
        end
        self._talentIndex[tab] = byTier
    end
end

-- Resolve a talent registration entry to (tab, ordinalIndex).
-- Entry forms:
--   { tab, index, key }          legacy row-major ordinal (correct by design)
--   { tab = t, tier = r, column = c, key = k }   resolved via index lookup
--   { tab = t, index = i, key = k }              explicit ordinal (mixed form)
-- Returns tab, index, key. index is nil when the entry cannot be resolved.
local function ResolveTalentEntry(state, entry)
    if type(entry) ~= "table" then return end
    local tab = entry[1] or entry.tab
    if type(tab) ~= "number" then return end

    if entry.tier ~= nil then
        -- Preferred form: language-independent tree coordinates.
        local byTier = state._talentIndex[tab] and state._talentIndex[tab][entry.tier]
        local index = byTier and byTier[entry.column]
        return tab, index, entry.key
    end

    return tab, entry[2] or entry.index, entry[3] or entry.key
end

function state:UpdateTalents()
    self:BuildTalentIndexLookup()

    local debugLog = DH.GetSetting and DH:GetSetting("debug")
        and not ns.registered._talentDiagnosticDone
    ns.registered._talentDiagnosticLog = ns.registered._talentDiagnosticLog or {}

    for _, entry in ipairs(ns.registered.talents) do
        local tab, index, key = ResolveTalentEntry(self, entry)
        if not key then key = entry[3] or entry.key end

        local rank = 0
        local resolvedName

        -- Out-of-range (tab,index) can raise a script error in the client,
        -- so validate against GetNumTalentTabs()/GetNumTalents() first and
        -- fall back to a protected call otherwise.
        if type(tab) == "number" and tab >= 1 and type(index) == "number"
            and self._numTalents and (self._numTalents[tab] or 0) >= index then
            local ok, name, _, _, _, r = pcall(GetTalentInfo, tab, index)
            if ok and name then
                rank = r or 0
                resolvedName = name
            end
        end

        if key then
            self.talent[key] = { rank = rank }
            if resolvedName then
                self.talent[key].name = resolvedName
            end
        end

        -- Self-diagnostic: with debug on, warn once per session about any
        -- talent registration that does not resolve to a real talent so the
        -- owning module's (tab,index) can be corrected.
        if debugLog and key and ns.registered._talentDiagnosticLog[key] ~= true then
            if index == nil or not resolvedName then
                ns.registered._talentDiagnosticLog[key] = true
                DH:Print(L("talent '") .. tostring(key) .. L("' (tab=") .. tostring(tab)
                    .. ", index=" .. tostring(index) .. ") " .. L("not found"))
            end
        end
    end
    if debugLog then ns.registered._talentDiagnosticDone = true end
    self:InvalidateBuild()
end

function state:UpdateGlyphs()
    if type(GetGlyphSocketInfo) ~= "function" then return end

    -- Reset all registered glyph keys
    local glyphKeys = {}
    for _, key in pairs(ns.registered.glyphs) do
        glyphKeys[key] = true
    end
    for key in pairs(glyphKeys) do
        self.glyph[key] = { enabled = false }
    end

    -- Build a localized glyph-name -> key index from the registered spell ids.
    -- A glyph's socketed spell always shares its name with the reference glyph
    -- spell ("Glyph of X"), while the raw spell-id tables shipped by the client
    -- are unreliable across guild/expansion data. Matching by the localized name
    -- therefore resolves glyphs correctly on every locale.
    local nameIndex = {}
    for spellId, key in pairs(ns.registered.glyphs) do
        if type(spellId) == "number" and type(key) == "string" then
            local name = GetSpellInfo(spellId)
            if name then
                nameIndex[string.lower(name)] = key
            end
        end
    end

    -- Scan equipped glyphs (3.3.5a has 6 glyph slots).
    -- Returns differ by client version:
    --   3.3.5a : enabled, glyphType, glyphSpell,          icon
    --   4.0.1+ : enabled, glyphType, glyphTooltipIndex,   glyphSpell, icon
    -- Pick whichever positional value is a plausible spell id (glyph spell ids
    -- are always well above 1000; tooltip indexes and icons are not).
    -- use_glyphs = false disables glyph scanning entirely (setting wired).
    if DH.GetSetting and DH:GetSetting("use_glyphs") ~= false then
        for i = 1, 6 do
            local enabled, glyphType, v3, v4 = GetGlyphSocketInfo(i)
            if enabled then
                local spellId
                if type(v4) == "number" and v4 > 1000 then
                    spellId = v4
                elseif type(v3) == "number" and v3 > 1000 then
                    spellId = v3
                end
                local key
                if spellId then
                    key = ns.registered.glyphs[spellId]
                    if not key then
                        local name = GetSpellInfo(spellId)
                        if name then
                            key = nameIndex[string.lower(name)]
                        end
                    end
                end
                if key then
                    self.glyph[key] = { enabled = true }
                end
            end
        end
    end
    self:InvalidateBuild()
end

-- ============================================================================
-- BUILD DETECTION (Improvement 2)
-- ============================================================================
-- A "build" is the fine-grained sub-spec that selects the rotation, e.g. a
-- Mage fire build is "ttw" or "ffb". Class modules may register a detector via
-- DH:RegisterBuildDetector(fn); without one the build falls back to the spec.
-- Detection is cached and invalidated by talent/glyph updates.

function state:InvalidateBuild()
    self._buildDirty = true
end

function state:DetectBuild()
    local mode = (DH.GetSetting and DH:GetSetting("build_detect_mode")) or "talents_glyphs"
    local spec = (DH.GetActiveSpec and DH:GetActiveSpec()) or "unknown"
    local key, source

    local detector = ns.registered.buildDetector
    if mode ~= "off" and type(detector) == "function" then
        key, source = detector(spec, self, mode)
    end
    if not key or key == "" then
        key, source = spec, "spec"
    end

    self.build = self.build or {}
    self.build.key = key
    self.build.spec = spec
    self.build.source = source or "detector"
    self.build.confident = (source ~= nil and source ~= "spec")
    self.build.mode = mode
    self.build.at = (GetTime and GetTime()) or 0
    -- Improvement 7: expose the stat profile alongside the detected build.
    self.build.stats = self.GetStatProfile and self:GetStatProfile() or nil
    self._buildDirty = false
    return key
end

function state:GetBuild()
    if self._buildDirty or not self.build then
        return self:DetectBuild()
    end
    return self.build.key
end

function state:GetBuildInfo()
    if self._buildDirty or not self.build then
        self:DetectBuild()
    end
    return self.build
end

-- Improvement 7: a compact stat profile. Build detectors (and the APL
-- condition engine) read this instead of touching self.stat directly, so the
-- shape stays stable. Values come from the already-updated stat table.
function state:GetStatProfile()
    local s = self.stat or {}
    return {
        spell_power = s.spell_power or 0,
        attack_power = s.attack_power or 0,
        crit = s.crit or 0,
        haste = s.haste or 0,
        spell_haste = s.spell_haste or 1,
    }
end

-- phase-3 #1: average equipped item level (0 when unavailable). Cached and
-- invalidated on PLAYER_EQUIPMENT_CHANGED via state:InvalidateItemLevel().
function state:InvalidateItemLevel()
    self._ilvlDirty = true
end

function state:GetItemLevel()
    if (not self._ilvlDirty) and self._ilvl then return self._ilvl end
    local total, count = 0, 0
    if type(GetInventoryItemLink) == "function" and type(GetItemInfo) == "function" then
        for slot = 1, 19 do
            local link = GetInventoryItemLink("player", slot)
            if link then
                local _, _, _, ilvl = GetItemInfo(link)
                if type(ilvl) == "number" and ilvl > 0 then
                    total = total + ilvl
                    count = count + 1
                end
            end
        end
    end
    self._ilvl = (count > 0) and (total / count) or 0
    self._ilvlDirty = false
    return self._ilvl
end

-- ============================================================================
-- CONVENIENCE ACCESSORS
-- ============================================================================

setmetatable(state, {
    __index = function(t, k)
        if k == "ttd" then
            return t.target.time_to_die
        elseif k == "time" then
            return t.now
        elseif k == "query_time" then
            return t.now + t.offset
        elseif k == "haste" then
            return 1 / (1 + t.stat.haste / 100)
        elseif k == "mainhand_speed" then
            local speed = UnitAttackSpeed("player")
            return speed or 2.5
        end
        return rawget(t, k)
    end
})

-- Initialize on load
state:Init()

-- ============================================================================
-- v3.4.0 FEATURE PACK (battle context, forecast, group awareness)
-- Live data for the rotations and the icon-window indicators.
-- ============================================================================

ns._phaseCacheTime = 0
ns._phaseCacheValue = nil

-- Improvement 1: battle context. Returns one of
--   opener / burst / sustain / execute / aoe / cleave / defensive / idle
local function IsDefensiveNeeded()
    local st = DH.State
    if not st or not st.health then return false end
    return (st.health.pct or 100) < 30
end

function DH:GetBattlePhase()
    local st = DH.State
    if not st then return "idle" end
    local now = GetTime()
    if ns._phaseCacheTime and (now - ns._phaseCacheTime) < 1 then
        return ns._phaseCacheValue or "idle"
    end
    ns._phaseCacheTime = now

    if not ns.inCombat then
        ns._phaseCacheValue = "idle"
        return "idle"
    end

    local enemies = st.active_enemies or 1
    local aoeT = DH.GetSetting and DH:GetSetting("aoe_threshold") or 4
    if enemies >= aoeT then
        ns._phaseCacheValue = "aoe"
        return "aoe"
    end
    local cleaveT = DH.GetSetting and DH:GetSetting("cleave_threshold") or 2
    if enemies >= cleaveT then
        ns._phaseCacheValue = "cleave"
        return "cleave"
    end

    -- Execute window: an explicit target below 21% HP.
    local hp = 100
    if st.target and st.target.health then
        hp = st.target.health.pct or 100
    end
    if hp < 21 then
        ns._phaseCacheValue = "execute"
        return "execute"
    end

    if IsDefensiveNeeded() then
        ns._phaseCacheValue = "defensive"
        return "defensive"
    end

    -- Burst window: fight age and the target phase (timeline) both qualify.
    local fightAge = 0
    if ns.fight and ns.fight.active and ns.fight.startTime then
        fightAge = now - ns.fight.startTime
    end
    if fightAge < 8 then
        ns._phaseCacheValue = "opener"
        return "opener"
    end
    if DH.IsExecutePhase and DH:IsExecutePhase() then
        ns._phaseCacheValue = "burst"
        return "burst"
    end

    ns._phaseCacheValue = "sustain"
    return "sustain"
end

-- Improvement 3: group raid buffs. Scans player + party + raid for the common
-- WotLK raid buffs. Cached for 3 seconds (the scan touches many units).
local GROUP_BUFFS = {
    kings = { "Blessing of Kings" },
    may = { "Blessing of Might" },
    wisdom = { "Blessing of Wisdom" },
    survival = { "Gift of the Wild", "Mark of the Wild" },
    fortitude = { "Power Word: Fortitude" },
    health = { "Commanding Shout" },
    wrath_of_air = { "Wrath of Air Totem" },
    strength_of_earth = { "Strength of Earth Totem" },
    windfury = { "Windfury Totem" },
    trueshot = { "Trueshot Aura", "Ferocious Inspiration" },
    retribution = { "Retribution Aura" },
    bloodlust = { "Bloodlust", "Heroism" },
}

function DH:GetGroupBuffs()
    if (DH.GetSetting and DH:GetSetting("group_awareness_enabled")) == false then
        return {}
    end
    local now = GetTime()
    if ns._groupBuffsTime and (now - ns._groupBuffsTime) < 3 then
        return ns._groupBuffsCache or {}
    end
    if not ns.inCombat and ns._groupBuffsCache then
        return ns._groupBuffsCache or {}
    end

    local out = {}
    local function Has(unit, name)
        if type(UnitBuff) ~= "function" then return false end
        local i = 1
        local ok, bn = pcall(UnitBuff, unit, i)
        while ok and bn do
            local bname = tostring(bn or "")
            -- Match the full buff name (plain substring) so "Greater Blessing of
            -- Kings" is found without conflating "Blessing of Might/Wisdom": the
            -- previous sub(1,6) prefix matched every "Blessi..." blessing.
            if bname:lower():find(name:lower(), 1, true) then
                return true
            end
            if bname:find("^" .. name .. "$") then return true end
            i = i + 1
            if i > 40 then break end
            ok, bn = pcall(UnitBuff, unit, i)
        end
        return false
    end

    local units = { "player" }
    if type(GetNumPartyMembers) == "function" then
        for i = 1, GetNumPartyMembers() do units[#units + 1] = "party" .. i end
    end
    if type(GetNumRaidMembers) == "function" then
        for i = 1, GetNumRaidMembers() do units[#units + 1] = "raid" .. i end
    end
    for key, names in pairs(GROUP_BUFFS) do
        for _, u in ipairs(units) do
            for _, nm in ipairs(names) do
                if Has(u, nm) then
                    out[key] = true
                    break
                end
            end
            if out[key] then break end
        end
        if not out[key] then out[key] = false end
    end

    ns._groupBuffsTime = now
    ns._groupBuffsCache = out
    return out
end

local function FriendlySpellName(key)
    local ab = DH.Class and DH.Class.abilities and DH.Class.abilities[key]
    if ab then
        if ab.name and ab.name ~= "" then return ab.name end
    end
    return tostring(key)
end

-- Improvement 2: combat forecast. `window` seconds of look-ahead. Returns an
-- array of lines like "Through 3.2s: Icy Veins ready".
function DH:ForecastNext(window)
    local st = DH.State
    if not st then return {} end
    local out = {}
    local w = tonumber(window) or 5
    if w <= 0 then return out end

    -- Major cooldowns / spells coming off cooldown within the window.
    if st.cooldown then
        local rows = {}
        for key, cd in pairs(st.cooldown) do
            if cd and type(cd) == "table" and cd.remains and cd.remains > 0 and cd.remains <= w then
                rows[#rows + 1] = { t = cd.remains, key = key }
            end
        end
        table.sort(rows, function(a, b) return a.t < b.t end)
        for _, r in ipairs(rows) do
            out[#out + 1] = string.format("|cFF9ECBFF%s %.1fs|r: %s",
                L("Through"), r.t, FriendlySpellName(r.key))
        end
    end

    -- Known short procs/buffs that will expire soon.
    if st.buff then
        local rows = {}
        for key, b in pairs(st.buff) do
            if b and type(b) == "table" and b.remains and b.remains > 0 and b.remains <= w
                and b.up ~= false then
                rows[#rows + 1] = { t = b.remains, key = key }
            end
        end
        table.sort(rows, function(a, b) return a.t < b.t end)
        for _, r in ipairs(rows) do
            out[#out + 1] = string.format("|cFF7FBF7F%.1fs|r: %s %s",
                r.t, L("expires:"), FriendlySpellName(r.key))
        end
    end
    return out
end

-- Improvement 30: arena size detection (2v2 / 3v3 / 5v5).
function DH:GetArenaMode()
    local m = DH.GetSetting and DH:GetSetting("arena_mode") or "auto"
    if m and m ~= "auto" then return m end
    if type(GetInstanceType) ~= "function" then return nil end
    local ok, itype = pcall(GetInstanceType)
    local zone = ok and itype or nil
    if zone ~= "arena" then return nil end
    local n = (type(GetNumArenaOpponents) == "function") and GetNumArenaOpponents() or 0
    local total = (tonumber(n) or 0) + 1
    if total == 2 then return "2v2" end
    if total == 3 then return "3v3" end
    if total >= 5 then return "5v5" end
    return nil
end

function DH:CycleArenaMode()
    local order = { "auto", "2v2", "3v3", "5v5" }
    local cur = DH.GetSetting and DH:GetSetting("arena_mode") or "auto"
    local next = "auto"
    for i, v in ipairs(order) do
        if v == cur then
            next = order[(i % #order) + 1]
            break
        end
    end
    DH:SetSetting("arena_mode", next)
    if DH.Print then DH:Print(L("Arena mode: ") .. tostring(next)) end
    return next
end

