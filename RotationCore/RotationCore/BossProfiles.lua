-- BossProfiles.lua
-- Boss profiles, skill stats and ideal DPS. Split out of RotationCore.lua.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

local function L(s)
    local tbl = DH.L
    if tbl and type(s) == "string" then
        return tbl[s]
    end
    return s
end

-- ============================================================================
-- PROMPT 2: BOSS PROFILES / SKILL STATS / IDEAL DPS
-- Session-only analytics live on ns (never persisted).
-- ============================================================================

-- Keys a boss profile is allowed to override in db.common.
ns.bossOverrideKeys = {
    "target_mode",
    "use_cooldowns",
    "auto_cooldowns",
    "cooldown_order",
    "activity_profile",
    "display_count",
}

ns.skillStats = {} -- [spellId] = { recommended, cast, missed, damage, name }
ns.fight = { active = false, damage = 0, duration = 0, startTime = 0 }
ns.lastFight = nil
ns.knownBosses = {} -- [encounterID] = encounterName
ns.bossBackup = { active = false }

-- ---------------------------------------------------------------------------
-- SKILL STATS (Improvement 3)
-- ---------------------------------------------------------------------------

function ns.SkillStat(id, name)
    id = tonumber(id)
    if not id then
        return nil
    end
    local s = ns.skillStats[id]
    if not s then
        s = { recommended = 0, cast = 0, missed = 0, damage = 0, name = name }
        ns.skillStats[id] = s
    elseif name and not s.name then
        s.name = name
    end
    return s
end

local function AbilityIdName(self, key)
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    if ab then
        return ab.id, ab.name
    end
    return nil, nil
end

-- Called from UpdateRecommendations with the freshly built list.
function ns.RecordRecommendations(self, recs)
    -- v3.3.0: class-pulse sampling (DoT uptime + cooldown usage). This runs
    -- whenever the pulse indicator is enabled, independent of the stats /
    -- ideal-dps settings.
    if self:GetSetting("class_pulse_enabled") ~= false then
        ns.SamplePulse(self)
        local top = recs and recs[1]
        local topKey = top and top.ability
        local p = ns.pulse
        if ns.IsBigCooldown and ns.IsBigCooldown(self, topKey) then
            if p.lastTopCd ~= topKey then
                p.lastTopCd = topKey
                p.cdSeen = p.cdSeen + 1
            end
        else
            p.lastTopCd = nil
        end
    end

    if not (self:GetSetting("stats_enabled") or self:GetSetting("ideal_dps_enabled")) then
        return
    end
    if type(recs) ~= "table" then
        return
    end
    for i = 1, #recs do
        local id, name = AbilityIdName(self, recs[i].ability)
        id = id or recs[i].id
        if id then
            local s = ns.SkillStat(id, recs[i].name or name)
            if s then
                s.recommended = s.recommended + 1
            end
        end
    end
end

-- Called on the player's SPELL_CAST_SUCCESS.
function ns.RecordCast(self, castKey, spellId)
    if not (self:GetSetting("stats_enabled") or self:GetSetting("ideal_dps_enabled")) then
        return
    end
    local ab = castKey and self.Class and self.Class.abilities and self.Class.abilities[castKey]
    local id = (ab and ab.id) or tonumber(spellId)
    if not id then
        return
    end
    local s = ns.SkillStat(id, ab and ab.name)
    if s then
        s.cast = s.cast + 1
    end

    -- A cast that is not the current top recommendation counts as a miss for
    -- the recommended ability.
    local top = ns.recommendations and ns.recommendations[1]
    if top then
        local topId, topName = AbilityIdName(self, top.ability)
        if topId and topId ~= id then
            local t = ns.SkillStat(topId, top.name or topName)
            if t then
                t.missed = t.missed + 1
            end
        end
    end
end

-- Accumulate player damage for the current fight and per-spell averages.
function ns.RecordDamage(self, spellId, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return
    end
    if ns.fight and ns.fight.active then
        ns.fight.damage = ns.fight.damage + amount
    end
    if self:GetSetting("ideal_dps_enabled") or self:GetSetting("stats_enabled") then
        local id = tonumber(spellId)
        if id then
            local s = ns.SkillStat(id)
            if s then
                s.damage = s.damage + amount
            end
        end
    end
end

local function GlobalAvgDamage()
    local total, casts = 0, 0
    for _, s in pairs(ns.skillStats) do
        total = total + (s.damage or 0)
        casts = casts + (s.cast or 0)
    end
    if casts > 0 then
        return total / casts
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- BOSS PROFILES (Improvement 1)
-- ---------------------------------------------------------------------------

function DH:IsBossProfilesEnabled()
    return (self.GetSetting and self:GetSetting("boss_profiles_enabled") == true) or false
end

function DH:GetBossProfiles()
    if self.db and type(self.db.boss_profiles) == "table" then
        return self.db.boss_profiles
    end
    return {}
end

function DH:SetBossProfile(id, data)
    if not self.db or id == nil then
        return false
    end
    if type(self.db.boss_profiles) ~= "table" then
        self.db.boss_profiles = {}
    end
    self.db.boss_profiles[tostring(id)] = data or {}
    return true
end

function DH:DeleteBossProfile(id)
    if self.db and type(self.db.boss_profiles) == "table" then
        self.db.boss_profiles[tostring(id)] = nil
        return true
    end
    return false
end

-- Snapshot the current values of the overridable keys, apply the profile and
-- remember the snapshot so ENCOUNTER_END can put the user's settings back.
function DH:ApplyBossProfile(id, name)
    local profiles = self:GetBossProfiles()
    local prof = profiles[tostring(id or "")]
    if not prof and name then
        for pid, p in pairs(profiles) do
            if p and p.name and p.name == name then
                prof = p
            end
        end
    end
    if not prof then
        return false, "no-profile"
    end
    if not self.db.common then
        self.db.common = {}
    end

    if not ns.bossBackup.active then
        local snap = {}
        for _, k in ipairs(ns.bossOverrideKeys) do
            snap[k] = self.db.common[k]
            snap["_had_" .. k] = (self.db.common[k] ~= nil)
        end
        ns.bossBackup = { active = true, snap = snap, id = tostring(id or "") }
    end
    for k, v in pairs(prof) do
        if type(k) == "string" and k ~= "name" then
            self.db.common[k] = v
        end
    end
    if prof.name then
        ns.bossBackup.name = prof.name
    end
    ns.bossBackup.id = tostring(id or ns.bossBackup.id or "")
    self:RefreshConfig()
    self:UpdateRecommendations()
    if self.NotifyOptions then
        self:NotifyOptions()
    end
    return true
end

function DH:RestoreDefaultProfile()
    if not ns.bossBackup.active then
        return false
    end
    local snap = ns.bossBackup.snap or {}
    if self.db and self.db.common then
        for _, k in ipairs(ns.bossOverrideKeys) do
            if snap["_had_" .. k] then
                self.db.common[k] = snap[k]
            else
                self.db.common[k] = nil
            end
        end
    end
    ns.bossBackup = { active = false }
    ns.bossTargetActive = nil -- name of the target-detected boss preset currently applied
    self:RefreshConfig()
    self:UpdateRecommendations()
    if self.NotifyOptions then
        self:NotifyOptions()
    end
    return true
end

-- ---------------------------------------------------------------------------
-- LIFECYCLE HOOKS (v3.4.0-hotfix6): the feature pack subscribes here instead
-- of re-wrapping methods, so load order can never silently drop the original.
-- ---------------------------------------------------------------------------
function DH:OnEncounterStart(encounterID, encounterName)
    local id = tostring(encounterID or "")
    if id ~= "" then
        ns.knownBosses[id] = encounterName or ns.knownBosses[id] or id
    end
    if self.State then
        self.State.encounter_id = (id ~= "") and id or nil
        self.State.encounter_name = encounterName
    end
    ns.skillStats = {}
    self:StartFight(encounterID, encounterName)
    if self:IsBossProfilesEnabled() then
        local kind = self.GetInstanceKind and self:GetInstanceKind() or nil
        local applied = self:ApplyBossProfile(encounterID, encounterName)
        if not applied then
            applied = self:ApplyBossPresetFor(encounterID, encounterName, kind)
        end
        if applied then
            if ns.bossBackup and ns.bossBackup.active then
                ns.bossBackup.src = "encounter"
            end
            self:Print(L("Boss profile applied: ") .. tostring(encounterName or id))
        end
    end
    ns.RunHooks("OnEncounterStart", encounterID, encounterName)
end

function DH:OnEncounterEnd(encounterID, encounterName, difficultyID, raidSize, endStatus)
    self:EndFight(endStatus)
    if endStatus == 1 and ns.RegisterFeedbackBossKill then
        ns.RegisterFeedbackBossKill()
    end
    if self.State then
        self.State.encounter_id = nil
        self.State.encounter_name = nil
    end
    if ns.bossBackup.active then
        self:RestoreDefaultProfile()
        self:Print(L("Default profile restored."))
    end
end

-- ---------------------------------------------------------------------------
-- FIGHT ANALYTICS / IDEAL DPS (Improvement 4)
-- ---------------------------------------------------------------------------

function DH:StartFight(id, name)
    ns.fight = {
        active = true,
        damage = 0,
        duration = 0,
        startTime = GetTime(),
        bossId = (id ~= nil) and tostring(id) or nil,
        bossName = name,
    }
    -- v3.3.0: reset the per-fight pulse / exam counters.
    if ns.ResetAnalytics then
        ns.ResetAnalytics()
    end
    ns.RunHooks("StartFight", id, name)
end

function DH:EndFight(endStatus)
    local f = ns.fight
    if not f or not f.active then
        ns.RunHooks("EndFight", endStatus)
        return
    end
    f.active = false
    f.duration = math.max(0.001, GetTime() - (f.startTime or GetTime()))
    if f.duration < 1 then
        ns.RunHooks("EndFight", endStatus)
        return
    end

    local actual = f.damage / f.duration
    local idealDamage = f.damage
    local losses = {}
    local fallbackAvg = GlobalAvgDamage()
    for id, s in pairs(ns.skillStats) do
        if (s.missed or 0) > 0 then
            local avg = (s.cast and s.cast > 0 and s.damage and s.damage > 0) and (s.damage / s.cast) or fallbackAvg
            local lost = s.missed * avg
            if lost > 0 then
                idealDamage = idealDamage + lost
                losses[#losses + 1] = {
                    id = id,
                    name = s.name or tostring(id),
                    lost = lost,
                    missed = s.missed,
                }
            end
        end
    end
    table.sort(losses, function(a, b)
        return a.lost > b.lost
    end)

    f.actual_dps = actual
    f.ideal_dps = idealDamage / f.duration
    f.loss_pct = (f.ideal_dps > 0) and ((1 - actual / f.ideal_dps) * 100) or 0
    f.losses = losses
    f.killed = (endStatus == 1)
    ns.lastFight = f
    self:ReportFight(f)
    -- v3.3.0: exam report + persistent learning session.
    if ns.FinalizeAnalytics then
        ns.FinalizeAnalytics(self)
    end
    ns.RunHooks("EndFight", endStatus)
end

function DH:ReportFight(f)
    if not (self:GetSetting("ideal_dps_enabled") or self:GetSetting("training_mode")) then
        return
    end
    local boss = (f.bossName and f.bossName ~= "") and f.bossName or L("fight")
    self:Print(
        string.format(
            L("Fight: %s | DPS %d | ideal %d | loss %.1f%%"),
            tostring(boss),
            math.floor(f.actual_dps or 0),
            math.floor(f.ideal_dps or 0),
            f.loss_pct or 0
        )
    )
    local losses = f.losses or {}
    if #losses > 0 then
        self:Print(L("Worst skills by lost damage:"))
        for i = 1, math.min(5, #losses) do
            local x = losses[i]
            self:Print(string.format("  %s: -%d (missed %d)", tostring(x.name), math.floor(x.lost), x.missed))
        end
    end
end

-- ---------------------------------------------------------------------------
-- RAID PRESETS
-- ---------------------------------------------------------------------------

local function SP(t)
    return { target_mode = t, activity_profile = "raid" }
end
local function DP(t)
    return { target_mode = t, activity_profile = "dungeon" }
end

-- id = NPC (creature) id, which is locale-independent and matches
-- UnitGUID("target") (see DH:GetUnitNpcID). Name is kept for display and as a
-- secondary match. kind separates raid vs dungeon groups.
ns.bossPresets = {
    {
        kind = "raid",
        raid = "Naxxramas",
        bosses = {
            { id = 15956, name = "Anub'Rekhan", profile = SP("auto") },
            { id = 15953, name = "Grand Widow Faerlina", profile = SP("aoe") },
            { id = 15952, name = "Maexxna", profile = SP("single") },
            { id = 15954, name = "Noth the Plaguebringer", profile = SP("auto") },
            { id = 15936, name = "Heigan the Unclean", profile = SP("single") },
            { id = 16011, name = "Loatheb", profile = SP("single") },
            { id = 16061, name = "Instructor Razuvious", profile = SP("single") },
            { id = 16060, name = "Gothik the Harvester", profile = SP("auto") },
            { id = 16063, name = "The Four Horsemen", profile = SP("cleave") },
            { id = 16028, name = "Patchwerk", profile = SP("single") },
            { id = 15931, name = "Grobbulus", profile = SP("single") },
            { id = 15932, name = "Gluth", profile = SP("aoe") },
            { id = 15928, name = "Thaddius", profile = SP("single") },
            { id = 15989, name = "Sapphiron", profile = SP("single") },
            { id = 15990, name = "Kel'Thuzad", profile = SP("auto") },
        },
    },
    {
        kind = "raid",
        raid = "OS",
        bosses = {
            { id = 28860, name = "Sartharion", profile = SP("auto") },
            { id = 30452, name = "Tenebron", profile = SP("auto") },
            { id = 30451, name = "Shadron", profile = SP("auto") },
            { id = 30449, name = "Vesperon", profile = SP("auto") },
        },
    },
    { kind = "raid", raid = "EoE", bosses = {
        { id = 28859, name = "Malygos", profile = SP("auto") },
    } },
    {
        kind = "raid",
        raid = "VoA",
        bosses = {
            { id = 31125, name = "Archavon the Stone Watcher", profile = SP("single") },
            { id = 33993, name = "Emalon the Storm Watcher", profile = SP("cleave") },
            { id = 35013, name = "Koralon the Flame Watcher", profile = SP("cleave") },
            { id = 38433, name = "Toravon the Ice Watcher", profile = SP("single") },
        },
    },
    {
        kind = "raid",
        raid = "Ulduar",
        bosses = {
            { id = 33113, name = "Flame Leviathan", profile = SP("auto") },
            { id = 33118, name = "Ignis the Furnace Master", profile = SP("auto") },
            { id = 33186, name = "Razorscale", profile = SP("auto") },
            { id = 33293, name = "XT-002 Deconstructor", profile = SP("auto") },
            { id = 32857, name = "Assembly of Iron", profile = SP("cleave") },
            { id = 32930, name = "Kologarn", profile = SP("auto") },
            { id = 33515, name = "Auriaya", profile = SP("auto") },
            { id = 32845, name = "Hodir", profile = SP("single") },
            { id = 32865, name = "Thorim", profile = SP("auto") },
            { id = 32906, name = "Freya", profile = SP("auto") },
            { id = 33350, name = "Mimiron", profile = SP("auto") },
            { id = 33271, name = "General Vezax", profile = SP("single") },
            { id = 33288, name = "Yogg-Saron", profile = SP("auto") },
            { id = 32871, name = "Algalon the Observer", profile = SP("single") },
        },
    },
    {
        kind = "raid",
        raid = "ToC",
        bosses = {
            { id = 34796, name = "Northrend Beasts", profile = SP("aoe") },
            { id = 34780, name = "Lord Jaraxxus", profile = SP("single") },
            { id = 34447, name = "Faction Champions", profile = SP("cleave") },
            { id = 34496, name = "Twin Val'kyr", profile = SP("cleave") },
            { id = 34564, name = "Anub'arak", profile = SP("aoe") },
        },
    },
    { kind = "raid", raid = "Onyxia", bosses = {
        { id = 10184, name = "Onyxia", profile = SP("auto") },
    } },
    {
        kind = "raid",
        raid = "ICC",
        bosses = {
            { id = 36612, name = "Lord Marrowgar", profile = SP("auto") },
            { id = 36855, name = "Lady Deathwhisper", profile = SP("auto") },
            { id = 37813, name = "Deathbringer Saurfang", profile = SP("single") },
            { id = 36626, name = "Festergut", profile = SP("single") },
            { id = 36627, name = "Rotface", profile = SP("auto") },
            { id = 36678, name = "Professor Putricide", profile = SP("auto") },
            { id = 37970, name = "Blood Prince Council", profile = SP("cleave") },
            { id = 37955, name = "Blood-Queen Lana'thel", profile = SP("single") },
            { id = 36789, name = "Valithria Dreamwalker", profile = SP("auto") },
            { id = 36853, name = "Sindragosa", profile = SP("single") },
            { id = 36597, name = "The Lich King", profile = SP("auto") },
        },
    },
    {
        kind = "raid",
        raid = "RS",
        bosses = {
            { id = 39746, name = "General Zarithrian", profile = SP("auto") },
            { id = 39747, name = "Saviana Ragefire", profile = SP("auto") },
            { id = 39751, name = "Baltharus the Warborn", profile = SP("auto") },
            { id = 39863, name = "Halion", profile = SP("auto") },
        },
    },

    -- WotLK 5-man dungeons (16). Matched by NPC id via the target; used as a
    -- fallback because 5-man bosses do not reliably fire ENCOUNTER_START.
    {
        kind = "dungeon",
        dungeon = "Utgarde Keep",
        bosses = {
            { id = 23953, name = "Prince Keleseth", profile = DP("single") },
            { id = 24200, name = "Skarvald the Constructor", profile = DP("single") },
            { id = 24201, name = "Dalronn the Controller", profile = DP("single") },
            { id = 23954, name = "Ingvar the Plunderer", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Utgarde Pinnacle",
        bosses = {
            { id = 26668, name = "Svala Sorrowgrave", profile = DP("single") },
            { id = 26687, name = "Gortok Palehoof", profile = DP("single") },
            { id = 26693, name = "Skadi the Ruthless", profile = DP("single") },
            { id = 26861, name = "King Ymiron", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "The Nexus",
        bosses = {
            { id = 26731, name = "Grand Magus Telestra", profile = DP("cleave") },
            { id = 26763, name = "Anomalus", profile = DP("single") },
            { id = 26794, name = "Ormorok the Tree-Shaper", profile = DP("single") },
            { id = 26723, name = "Keristrasza", profile = DP("single") },
            { id = 26796, name = "Commander Stoutbeard", profile = DP("single") },
            { id = 26799, name = "Commander Kolurg", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "The Oculus",
        bosses = {
            { id = 27654, name = "Drakos the Interrogator", profile = DP("single") },
            { id = 27447, name = "Varos Cloudstrider", profile = DP("single") },
            { id = 27655, name = "Mage-Lord Urom", profile = DP("single") },
            { id = 27656, name = "Ley-Guardian Eregos", profile = DP("auto") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Azjol-Nerub",
        bosses = {
            { id = 28684, name = "Krik'thir the Gatewatcher", profile = DP("cleave") },
            { id = 28921, name = "Hadronox", profile = DP("cleave") },
            { id = 29120, name = "Anub'arak", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Ahn'kahet: The Old Kingdom",
        bosses = {
            { id = 29309, name = "Elder Nadox", profile = DP("cleave") },
            { id = 29308, name = "Prince Taldaram", profile = DP("single") },
            { id = 29310, name = "Jedoga Shadowseeker", profile = DP("cleave") },
            { id = 29311, name = "Herald Volazj", profile = DP("single") },
            { id = 30258, name = "Amanitar", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Drak'Tharon Keep",
        bosses = {
            { id = 26630, name = "Trollgore", profile = DP("cleave") },
            { id = 26631, name = "Novos the Summoner", profile = DP("cleave") },
            { id = 27483, name = "King Dred", profile = DP("single") },
            { id = 26632, name = "The Prophet Tharon'ja", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "The Violet Hold",
        bosses = {
            { id = 29316, name = "Moragg", profile = DP("single") },
            { id = 29315, name = "Erekem", profile = DP("cleave") },
            { id = 29313, name = "Ichoron", profile = DP("cleave") },
            { id = 29312, name = "Lavanthor", profile = DP("single") },
            { id = 29266, name = "Xevozz", profile = DP("single") },
            { id = 29314, name = "Zuramat the Obliterator", profile = DP("single") },
            { id = 31134, name = "Cyanigosa", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Gundrak",
        bosses = {
            { id = 29304, name = "Slad'ran", profile = DP("cleave") },
            { id = 29307, name = "Drakkari Colossus", profile = DP("cleave") },
            { id = 29305, name = "Moorabi", profile = DP("single") },
            { id = 29306, name = "Gal'darah", profile = DP("single") },
            { id = 29932, name = "Eck the Ferocious", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Halls of Stone",
        bosses = {
            { id = 27975, name = "Maiden of Grief", profile = DP("single") },
            { id = 27977, name = "Krystallus", profile = DP("single") },
            { id = 28234, name = "Tribunal of Ages", profile = DP("cleave") },
            { id = 27978, name = "Sjonnir the Ironshaper", profile = DP("cleave") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Halls of Lightning",
        bosses = {
            { id = 28586, name = "General Bjarngrim", profile = DP("cleave") },
            { id = 28587, name = "Volkhan", profile = DP("single") },
            { id = 28546, name = "Ionar", profile = DP("cleave") },
            { id = 28923, name = "Loken", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "The Culling of Stratholme",
        bosses = {
            { id = 26529, name = "Meathook", profile = DP("cleave") },
            { id = 26530, name = "Salramm the Fleshcrafter", profile = DP("cleave") },
            { id = 26532, name = "Chrono-Lord Epoch", profile = DP("single") },
            { id = 26533, name = "Mal'Ganis", profile = DP("single") },
            { id = 32273, name = "Infinite Corruptor", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Trial of the Champion",
        bosses = {
            { id = 35119, name = "Eadric the Pure", profile = DP("cleave") },
            { id = 35097, name = "Confessor Paletress", profile = DP("cleave") },
            { id = 35451, name = "The Black Knight", profile = DP("auto") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "The Forge of Souls",
        bosses = {
            { id = 36497, name = "Bronjahm", profile = DP("single") },
            { id = 36502, name = "Devourer of Souls", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Pit of Saron",
        bosses = {
            { id = 36494, name = "Forgemaster Garfrost", profile = DP("single") },
            { id = 36476, name = "Krick and Ick", profile = DP("cleave") },
            { id = 36658, name = "Scourgelord Tyrannus", profile = DP("single") },
        },
    },
    {
        kind = "dungeon",
        dungeon = "Halls of Reflection",
        bosses = {
            { id = 38112, name = "Falric", profile = DP("single") },
            { id = 38113, name = "Marwyn", profile = DP("single") },
            { id = 36954, name = "The Lich King", profile = DP("auto") },
        },
    },
}

function DH:FindPreset(id, name, kind)
    local ids = tostring(id or "")
    for _, group in ipairs(ns.bossPresets) do
        local gk = group.kind or "raid"
        if not kind or gk == kind then
            for _, b in ipairs(group.bosses) do
                if (ids ~= "" and tostring(b.id) == ids) or (name and b.name == name) then
                    return b
                end
            end
        end
    end
    return nil
end

-- Auto-apply a preset when no stored profile exists (boss_profiles_enabled).
function DH:ApplyBossPresetFor(id, name, kind)
    local b = self:FindPreset(id, name, kind)
    if not b then
        return false
    end
    local prof = { name = b.name }
    for k, v in pairs(b.profile) do
        prof[k] = v
    end
    local key = b.id or b.name
    if key then
        self:SetBossProfile(key, prof)
    end
    return self:ApplyBossProfile(key, b.name)
end

-- ---------------------------------------------------------------------------
-- EXPORT / IMPORT (safe text, no loadstring)
-- ---------------------------------------------------------------------------

function DH:ExportBossProfiles()
    local lines = {}
    for id, prof in pairs(self:GetBossProfiles()) do
        local parts = {}
        for k, v in pairs(prof) do
            if type(v) ~= "table" then
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
            end
        end
        lines[#lines + 1] = tostring(id) .. "|" .. table.concat(parts, ";")
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

function DH:ImportBossProfiles(text)
    if type(text) ~= "string" then
        return 0
    end
    local count = 0
    for line in text:gmatch("[^\n]+") do
        local id, body = line:match("^%s*([^|]+)|(.*)$")
        if id then
            local prof = {}
            for kv in body:gmatch("([^;]+)") do
                local k, v = kv:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                if k and v then
                    if v == "true" then
                        prof[k] = true
                    elseif v == "false" then
                        prof[k] = false
                    elseif tonumber(v) then
                        prof[k] = tonumber(v)
                    else
                        prof[k] = v
                    end
                end
            end
            self:SetBossProfile(id, prof)
            count = count + 1
        end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- /rc stats printers
-- ---------------------------------------------------------------------------

function DH:PrintStats()
    local rows = {}
    for id, s in pairs(ns.skillStats) do
        rows[#rows + 1] = {
            id = id,
            name = s.name or tostring(id),
            recommended = s.recommended or 0,
            cast = s.cast or 0,
            missed = s.missed or 0,
        }
    end
    if #rows == 0 then
        self:Print(L("No stats recorded."))
        return
    end
    table.sort(rows, function(a, b)
        return a.missed > b.missed
    end)
    self:Print(L("Stats: top 10 abilities by missed casts"))
    for i = 1, math.min(10, #rows) do
        local r = rows[i]
        self:Print(string.format("  %s: rec %d, cast %d, missed %d", tostring(r.name), r.recommended, r.cast, r.missed))
    end
end

function DH:PrintDPS()
    local f = ns.fight
    if (not f or not f.active) and not ns.lastFight then
        self:Print(L("No stats recorded."))
        return
    end
    if f and f.active then
        local dur = math.max(0.001, GetTime() - (f.startTime or GetTime()))
        local dps = (f.damage or 0) / dur
        local boss = (f.bossName and f.bossName ~= "") and f.bossName or L("fight")
        self:Print(
            string.format(
                L("Fight: %s | DPS %d | ideal %d | loss %.1f%%"),
                tostring(boss),
                math.floor(dps),
                math.floor(dps),
                0
            )
        )
        return
    end
    self:ReportFight(ns.lastFight)
end
