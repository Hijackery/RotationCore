-- RotationCore.lua
-- Rotation helper framework for WotLK 3.3.5a
-- Class modules register their data via the registration API

-- Create addon namespace
RotationCore = {}
local DH = RotationCore

DH.Version = "1.3.0"

-- Namespace for internal data
local ns = {}
DH.ns = ns

-- Localization helper: Locale.lua fills DH.L after this file loads, so look it
-- up lazily on every call (missing keys return the English source string).
local function L(s)
    local tbl = DH.L
    if tbl and type(s) == "string" then return tbl[s] end
    return s
end

ns.debug = {}
ns.inCombat = false

-- Aura tracking cache
ns.auras = {
    target = { buff = {}, debuff = {} },
    player = { buff = {}, debuff = {} }
}

-- Player class (detected at load time)
DH.playerClass = select(2, UnitClass("player"))
DH.playerRace = select(2, UnitRace("player"))

local CLASS_COLORS = {
    MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 },
    PRIEST = { 1.00, 1.00, 1.00 }, ROGUE = { 1.00, 0.96, 0.41 },
    WARRIOR = { 0.78, 0.61, 0.43 }, DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN = { 0.00, 0.44, 0.87 }, HUNTER = { 0.67, 0.83, 0.45 },
    DRUID = { 1.00, 0.49, 0.04 }, PALADIN = { 0.96, 0.55, 0.73 },
}
function DH:GetClassColor()
    local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[self.playerClass]
    if rc then return rc.r, rc.g, rc.b end
    local c = CLASS_COLORS[self.playerClass]
    if c then return c[1], c[2], c[3] end
    return 1, 0.82, 0
end

-- Class data structure
DH.Class = {
    file = DH.playerClass,
    resources = {},
    talents = {},
    glyphs = {},
    auras = {},
    abilities = {},
    abilityByName = {},
    meleeAbilities = {},  -- Keys of abilities that are melee range
    range = 5,
    settings = {},
}

-- State will be initialized in State.lua
DH.State = {}

-- Recommendation queue
ns.queue = {}
ns.recommendations = {}

-- Cached GetSpellInfo for hot display paths. The client never changes a
-- spell's name/icon during a session, so caching avoids repeated lookups in
-- the icon window and action-bar glow updater.
ns.spellInfoCache = ns.spellInfoCache or {}
function ns.CachedSpellInfo(id)
    if not id or type(GetSpellInfo) ~= "function" then return nil end
    local hit = ns.spellInfoCache[id]
    if hit then return hit[1], hit[2], hit[3] end
    local name, rank, icon = GetSpellInfo(id)
    if name then
        ns.spellInfoCache[id] = { name, rank, icon }
    end
    return name, rank, icon
end

-- ============================================================================
-- ERROR LOG (written to its own SavedVariables file: RotationCoreErrors.lua)
-- seterrorhandler catches every Lua error. The last few are kept (duplicates
-- collapsed) so the player can send the file without digging in the normal DB.
-- ============================================================================

ns.MAX_ERRORS = 200
ns.errorLog = {}

function ns.AddError(msg)
    local log = ns.errorLog
    if not log then
        log = {}
        ns.errorLog = log
    end
    msg = tostring(msg)
    local last = log[#log]
    if type(last) == "table" and last.msg == msg then
        last.count = (last.count or 1) + 1
        return
    end
    ns.lastErrorTime = GetTime()
    ns.lastErrorMsg = msg
    log[#log + 1] = { msg = msg, count = 1 }
    while #log > ns.MAX_ERRORS do
        table.remove(log, 1)
    end
end

-- Chain to the previous handler so the default red error box still appears.
do
    local prev = geterrorhandler and geterrorhandler()
    if seterrorhandler then
        seterrorhandler(function(msg)
            ns.AddError(msg)
            if prev then prev(msg) end
        end)
    end
end

-- Recommendation stability: prevent flickering by keeping recommendations
-- stable for at least one GCD. If the new recommendations differ from the
-- previous ones, only update if enough time has passed.
ns.lastRecTime = 0
ns.lastRecAbilities = {}

-- UI elements
ns.UI = {
    MainFrame = nil,
    Buttons = {}
}

-- ============================================================================
-- COOLDOWN SNOOZE SYSTEM
-- When the addon recommends a major cooldown but the player uses a different
-- ability instead, the CD recommendation is snoozed for a duration. If the
-- player manually uses the CD, the snooze clears immediately.
-- ============================================================================

ns.snooze = {}          -- { [abilityKey] = expireTime }
ns.lastRecommended = nil -- The first recommended ability key from last update

-- Check if an ability is currently snoozed
function DH:IsSnoozed(key)
    local expires = ns.snooze[key]
    if expires and GetTime() < expires then
        return true
    end
    ns.snooze[key] = nil
    return false
end

-- Snooze an ability for a duration (default 60s)
function DH:Snooze(key, duration)
    ns.snooze[key] = GetTime() + (duration or 60)
end

-- Clear snooze for an ability (player used it)
function DH:ClearSnooze(key)
    ns.snooze[key] = nil
end

-- Register an ability as snoozeable with a duration
-- When recommended but skipped, it won't be recommended again for `duration` seconds
ns.snoozeable = {}
function DH:RegisterSnoozeable(key, duration)
    ns.snoozeable[key] = duration or 60
end

-- Simulation framework lives in Simulation.lua.

-- Registration API lives in Registration.lua.

-- Learned abilities lives in KnownSpells.lua.

-- Shared settings API lives in SharedSettings.lua.

-- Settings and profiles lives in Profiles.lua.

-- Event handling lives in Events.lua.

-- ============================================================================
-- ENABLE / DISABLE
-- ============================================================================

function DH:SetEnabled(enabled)
    if not self.db then return false end
    enabled = enabled and true or false
    if self.db.enabled == enabled then return true end

    self.db.enabled = enabled
    if enabled then
        ns.eventFrame:Show()
        self:ShowUI()
        self:UpdateUI()
    else
        ns.recommendations = {}
        ns.eventFrame:Hide()
        self:HideUI()
        -- Hide every on-screen display, not just the glows
        if ns.HideSpellFrame then ns.HideSpellFrame() end
        if ns.UpdateCooldownsFrame then ns.UpdateCooldownsFrame() end
        if ns.UpdateInterruptsFrame then ns.UpdateInterruptsFrame() end
        if ns.UpdateTimelineFrame then ns.UpdateTimelineFrame() end
        if ns.UpdateDebugFrame then ns.UpdateDebugFrame() end
    end

    -- Enabling/disabling changes whether the poll loop should run.
    self:SyncUpdateLoop()

    if self.RefreshOptions then
        self:RefreshOptions()
    end
    return true
end

-- Tell the options window a setting changed (no-op when it is closed)
function DH:NotifyOptions()
    if self.RefreshOptions then
        self:RefreshOptions()
    end
end

-- ============================================================================
-- ROTATION MODE / BUILD SELECTION
-- Class modules register one mode per build (arcane, fire, frost_mage, ...).
-- With auto_mode the build follows the player's talents automatically.
-- ============================================================================

local function CommonPrefixLen(a, b)
    local n = math.min(#a, #b)
    for i = 1, n do
        if a:byte(i) ~= b:byte(i) then
            return i - 1
        end
    end
    return n
end

-- Map a spec detector result ("frost", "retribution", "protection") onto a
-- registered mode key ("frost_mage", "ret", "prot_warrior", ...).
-- "Safe" (healer) modes are matched before their DPS-borrow variants so that
-- e.g. "holy" resolves to "holy_paladin" (not "holy_paladin_dps"); the core
-- then borrows the DPS rotation from the safe mode only when heal_dps_mode
-- allows it (see GetHealDpsMode). Matching a DPS key directly would bypass
-- that gate and run a DPS rotation for grouped healers.
function DH:MatchModeKey(spec)
    if type(spec) ~= "string" or spec == "" then return nil end
    local modes = ns.registered.modes

    local function match(group)
        for _, mode in ipairs(group) do
            if mode.key == spec then return mode.key end
        end
        for _, mode in ipairs(group) do
            local mk = mode.key
            if mk:sub(1, #spec) == spec or spec:sub(1, #mk) == mk then
                return mk
            end
        end
        for _, mode in ipairs(group) do
            if CommonPrefixLen(spec, mode.key) >= 4 then
                return mode.key
            end
        end
        return nil
    end

    local safeModes, otherModes = {}, {}
    for _, mode in ipairs(modes) do
        if mode.safe or mode.heal then
            safeModes[#safeModes + 1] = mode
        else
            otherModes[#otherModes + 1] = mode
        end
    end

    return match(safeModes) or match(otherModes)
end

-- Apply a rotation mode (updates db, minimap icon, recommendations)
function DH:ApplyMode(modeKey)
    if not self.db then return false end

    local found
    for _, mode in ipairs(ns.registered.modes) do
        if mode.key == modeKey then
            found = mode
            break
        end
    end
    if not found then return false end

    self.db.mode = modeKey

    -- Drop the smoothing lock so the new mode's rotation is not stuck behind
    -- an old locked slot (provided by Config.lua).
    if ns.ResetSmoothing then ns.ResetSmoothing() end

    -- Inform once when a safe (unimplemented) mode becomes active - but stay
    -- quiet when heal-spec DPS is enabled (the borrowed rotation is intended).
    local healDps = self.GetHealDpsMode and self:GetHealDpsMode(found)
    if found.safe then
        if found.message and ns._safeModeKey ~= modeKey and not healDps then
            ns._safeModeKey = modeKey
            DH:Print(L(found.message))
        end
    else
        ns._safeModeKey = nil
    end

    if ns.MinimapButton and ns.MinimapButton.icon and found.icon then
        ns.MinimapButton.icon:SetTexture(found.icon)
    end
    if self.UpdateRecommendations then
        self:UpdateRecommendations()
    end
    if self.RefreshOptions then
        self:RefreshOptions()
    end
    return true
end

-- Manual selection: the choice is remembered and auto-detection stops
function DH:SetMode(modeKey)
    if not self:ApplyMode(modeKey) then return false end
    self.db.auto_mode = false
    return true
end

-- True when the currently stored mode is a healer (or legacy safe) mode.
-- Uses db.mode directly so it is safe to call before the full rotation update.
function DH:IsActiveHealMode()
    local key = self.db and self.db.mode
    if not key then return false end
    for _, mode in ipairs(ns.registered.modes or {}) do
        if mode.key == key and (mode.heal or mode.safe) then
            return true
        end
    end
    return false
end

-- Follow the talents (only while auto_mode is on)
function DH:AutoDetectMode()
    if not self.db then return nil end
    local spec = self:GetActiveSpec()
    local key = self:MatchModeKey(spec)
    if not self.db.auto_mode then
        -- Warn once if the manual rotation does not match the detected talents.
        if key and self.db.mode and key ~= self.db.mode then
            local sig = tostring(self.db.mode) .. "|" .. tostring(key)
            if ns._warnedMismatch ~= sig then
                ns._warnedMismatch = sig
                self:Print(string.format(L("Build may not match your talents: rotation '%s' vs detected '%s'."),
                    tostring(self.db.mode), tostring(key)))
            end
        end
        return key
    end

    -- Fallback: the detected spec has no registered mode - use the first mode
    -- so the player still gets a rotation instead of "Rec: none", and warn.
    if not key then
        local modes = ns.registered.modes
        if modes and modes[1] then
            key = modes[1].key
            if spec ~= ns._warnedSpec then
                ns._warnedSpec = spec
                DH:Print(L("Unknown spec (") .. tostring(spec)
                    .. L("), using ") .. tostring(modes[1].name or modes[1].key))
            end
        end
    end
    if key and key ~= self.db.mode then
        self:ApplyMode(key)
    end
    return key
end

-- ============================================================================
-- CLASS MODULES
-- The rotation modules are separate addons (RotationCore_Mage, ...) that
-- the user can switch in the addon list. They are LoadOnDemand and the core
-- loads the module matching the player's class at login.
-- ============================================================================

local CLASS_MODULES = {
    DRUID = "RotationCore_Druid",
    PALADIN = "RotationCore_Paladin",
    WARLOCK = "RotationCore_Warlock",
    SHAMAN = "RotationCore_Shaman",
    WARRIOR = "RotationCore_Warrior",
    HUNTER = "RotationCore_Hunter",
    DEATHKNIGHT = "RotationCore_DeathKnight",
    ROGUE = "RotationCore_Rogue",
    MAGE = "RotationCore_Mage",
    PRIEST = "RotationCore_Priest",
}

function DH:GetClassModuleName()
    return CLASS_MODULES[self.playerClass]
end

-- Load the rotation module for the player's class (LoadOnDemand addon)
function DH:LoadClassModule()
    local name = self:GetClassModuleName()
    if not name then return false end
    if IsAddOnLoaded and IsAddOnLoaded(name) then return true end

    local loaded, reason = LoadAddOn(name)
    if loaded then
        self:Print(L("Loaded ") .. name)
        self:ApplyModuleDefaults()
        return true
    end

    if reason == "DISABLED" then
        self:Print(name .. L(" is disabled - enable it in the addon list (/addons)"))
    else
        self:Print(L("Could not load ") .. name .. " (" .. tostring(reason) .. ")")
    end
    return false
end

-- Class module files run AFTER the core finished initializing, so their
-- registrations (defaults, modes, cooldowns) have to be merged in afterwards.
function DH:ApplyModuleDefaults()
    if not self.db then return end

    -- Buff/debuff/cooldown tables for the newly registered class data
    if self.State and self.State.Init then
        self.State:Init()
    end

    -- New class defaults into the active profile
    ns.MergeDefaults(self.db, ns.BuildDefaults(), true)
    self:ApplyProfileDefaults()

    if self.RefreshConfig then
        self:RefreshConfig()
    end
    if self.UpdateRecommendations then
        self:UpdateRecommendations()
    end
end

-- Initialize addon (runs on ADDON_LOADED - saved variables ARE available here).
-- The body is run through pcall so a corrupt saved-variable file degrades to a
-- fresh profile instead of bricking the whole session.
local function DoInitialize(self)
    -- Saved variables are loaded by the client between file load and
    -- ADDON_LOADED, so this is the first safe place to read them.

    RotationCoreDB = ns.MigrateSaved(RotationCoreDB)
    self.dbRoot = RotationCoreDB
    self.profileKey = ns.GetProfileKey()

    local activeProfile = RotationCoreDB.profileKeys[self.profileKey] or "Default"
    if not RotationCoreDB.profiles[activeProfile] then
        activeProfile = "Default"
    end
    self:LoadProfile(activeProfile)

    -- Error log has its own file: append what was saved last session and point
    -- the SavedVariable at our (now merged) live table.
    if type(RotationCoreErrors) == "table" then
        for _, e in ipairs(RotationCoreErrors) do
            if type(e) == "table" and type(e.msg) == "string" then
                ns.errorLog[#ns.errorLog + 1] = { msg = e.msg, count = tonumber(e.count) or 1 }
            end
        end
        -- Keep only the most recent entries if the saved file is bloated.
        while #ns.errorLog > ns.MAX_ERRORS do
            table.remove(ns.errorLog, 1)
        end
    end
    RotationCoreErrors = ns.errorLog


    -- Register slash commands
    -- Main short alias for the new addon name
    SLASH_ROTATIONCORE1 = "/rc"
    -- Fallback: the old command is kept for compatibility
    SLASH_ROTATIONCORE2 = "/ph"
    -- Full command
    SLASH_ROTATIONCORE3 = "/rotationcore"
    SlashCmdList["ROTATIONCORE"] = function(msg)
        DH:SlashCommand(msg)
    end

    -- Config.lua / Options.lua register their own hooks
    if self.ConfigOnInit then
        self:ConfigOnInit()
    end

    -- Prompt 3.3: wire DBM / BigWigs timelines if the addons are present.
    if ns.InitTimeline then ns.InitTimeline() end

    self:Print("v" .. self.Version .. L(" loaded. Profile: ") .. self:GetCurrentProfileName() .. L(". Type /rc for options."))
end

function DH:OnInitialize()
    if self._initialized then return end
    local ok, err = pcall(DoInitialize, self)
    -- Mark initialised only after the attempt, so a thrown error still leaves a
    -- usable (fresh) database for this session rather than a half-dead addon.
    self._initialized = true
    if not ok then
        if ns.AddError then ns.AddError("OnInitialize failed: " .. tostring(err)) end
        if type(self.dbRoot) ~= "table" then
            RotationCoreDB = ns.MigrateSaved(nil)
            self.dbRoot = RotationCoreDB
            self.profileKey = ns.GetProfileKey()
            pcall(function() self:LoadProfile("Default") end)
        end
    end
end

-- Run the setup wizard once, the very first time this profile is used.
-- Answers are written straight into the current profile (ApplyAnswers).
function DH:MaybeShowFirstRunWizard()
    if not self.db then return end
    if self.db.wizardShown then return end
    self.db.wizardShown = true
    if not (ns.Wizard and ns.Wizard.Show) then return end

    -- Delay ~1s so the class module, modes and UI are ready first.
    local f = CreateFrame("Frame")
    self._wizardTimer = f
    local elapsedTotal = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal >= 1 then
            f:SetScript("OnUpdate", nil)
            f:Hide()
            DH._wizardTimer = nil
            ns.Wizard.Show()
        end
    end)
    f:Show()
end

-- Enable addon
function DH:OnEnable()
    if self._enabled then return end
    self._enabled = true

    -- Enabled by default: only an explicit /rc toggle turns it off.
    if self.db and self.db.enabled == nil then
        self.db.enabled = true
    end

    if ns.FeedbackOnEnable then ns.FeedbackOnEnable() end

    -- Register events
    ns.eventFrame:RegisterEvent("PLAYER_LOGOUT")
    ns.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    ns.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    ns.eventFrame:RegisterEvent("PLAYER_DEAD")
    ns.eventFrame:RegisterEvent("PLAYER_ALIVE")
    ns.eventFrame:RegisterEvent("UNIT_AURA")
    -- Power changes (3.3.5a: one event per resource; UNIT_POWER is 4.0+)
    ns.eventFrame:RegisterEvent("UNIT_MANA")
    ns.eventFrame:RegisterEvent("UNIT_RAGE")
    ns.eventFrame:RegisterEvent("UNIT_ENERGY")
    ns.eventFrame:RegisterEvent("UNIT_FOCUS")
    ns.eventFrame:RegisterEvent("UNIT_RUNIC_POWER")
    ns.eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ns.eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    ns.eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

    ns.eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    -- Learned spells / build detection
    ns.eventFrame:RegisterEvent("SPELLS_CHANGED")
    ns.eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    ns.eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    ns.eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")

    -- Glyph changes (3.3.5a)
    ns.eventFrame:RegisterEvent("GLYPH_ADDED")
    ns.eventFrame:RegisterEvent("GLYPH_REMOVED")
    ns.eventFrame:RegisterEvent("GLYPH_UPDATED")

    -- Prompt 2: boss encounters drive boss profiles + fight analytics
    ns.eventFrame:RegisterEvent("ENCOUNTER_START")
    ns.eventFrame:RegisterEvent("ENCOUNTER_END")

    -- Initialize state
    if self.State and self.State.Init then
        self.State:Init()
    end

    -- Create UI
    self:InitializeUI()

    -- Event frame must stay shown so events keep arriving; the OnUpdate poll is
    -- installed separately by SyncUpdateLoop() based on mode/combat/target.
    if not self.db or self.db.enabled then
        ns.eventFrame:Show()
    else
        ns.eventFrame:Hide()
    end
    self:SyncUpdateLoop()

    -- Config.lua / Options.lua finish their setup (minimap button, ...)
    if self.ConfigOnEnable then
        self:ConfigOnEnable()
    end
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

-- Registered slash command handlers from class modules
ns.slashCommands = {}

function DH:RegisterSlashCommand(cmd, handler, helpText)
    ns.slashCommands[cmd] = { handler = handler, help = helpText }
end

function DH:SlashCommand(input)
    local cmd = string.lower(input or "")

    if cmd == "debug spec" then
        local primary = ns.registered.specDetector and ns.registered.specDetector() or "nil"
        local fallback = ns.registered.specDetectorFallback and ns.registered.specDetectorFallback() or "nil"
        self:Print(L("Debug spec:") .. " active=" .. tostring(self:GetActiveSpec() or "nil") .. " primary=" .. tostring(primary) .. " fallback=" .. tostring(fallback))
    elseif cmd == "debug" then
        self.db.debug = not self.db.debug
        self:Print(L("Debug mode: ") .. (self.db.debug and L("ON") or L("OFF")))
    elseif cmd == "toggle" then
        local newState = not self.db.enabled
        self:SetEnabled(newState)
        self:Print(string.format(L("RotationCore %s"), newState and L("enabled") or L("disabled")))
    elseif cmd == "options" or cmd == "menu" then
        if self.OpenOptions then
            self:OpenOptions()
        else
            self:Print(L("Options are still loading"))
        end
    elseif cmd == "close" then
        if self.CloseOptions then self:CloseOptions() end
    elseif cmd == "help full" then
        if self.OpenOptionsTab then
            self:OpenOptionsTab("wizard")
        end
    elseif cmd == "help" then
        if self.OpenOptionsTab then
            self:OpenOptionsTab("help")
        elseif self.OpenOptions then
            self:OpenOptions()
        end
    elseif string.match(cmd, "^profile ") then
        local name = string.match(cmd, "^profile%s+(.+)")
        local from, toName = string.match(cmd, "^profile%s+copy%s+(.-)%s+to%s+(.+)$")
        if from then
            local ok, err = self:CopyProfile(from, toName)
            if ok then
                self:Print(L("Profile copied: ") .. tostring(from) .. " -> " .. tostring(toName))
            else
                self:Print(L("Profile copy failed: ") .. tostring(err))
            end
        elseif name and name ~= "" then
            if self:SetProfile(name) then
                -- profile switched
            else
                self:Print(L("Profile not found: ") .. tostring(name))
            end
        else
            self:Print(L("Current profile: ") .. self:GetCurrentProfileName())
            self:Print(L("Usage: /rc profile <name> | copy <from> to <to>"))
        end
    elseif cmd == "show" then
        self:InitializeUI()
        self:ShowUI()
        self:UpdateState()
        self:UpdateRecommendations()
        self:Print(L("Action bar glow forced on"))
    elseif cmd == "test" then
        self:InitializeUI()
        if ns.ShowTestGlow then
            ns.ShowTestGlow()
        end
    elseif cmd == "test rotation" then
        self:RunRotationSelfTest()
    elseif cmd == "pause" then
        self.db.paused = not (self.db.paused == true)
        self:Print(L("Paused: ") .. (self.db.paused and L("ON") or L("OFF")))
        if self.UpdateRecommendations then self:UpdateRecommendations() end
    elseif cmd == "spec" or string.match(cmd, "^spec%s") then
        local name = string.match(cmd, "^spec%s+(.+)")
        if not name or name == "" then
            self:Print(L("Build: ") .. (self.db.auto_mode and L("auto") or tostring(self.db.mode or L("unknown"))))
            if ns.registered.modes then
                for _, m in ipairs(ns.registered.modes) do
                    self:Print("  " .. tostring(m.key) .. " - " .. L(m.name or m.key))
                end
            end
        else
            name = string.lower(name)
            local target
            for _, m in ipairs(ns.registered.modes or {}) do
                if string.lower(tostring(m.key)) == name
                   or string.lower(tostring(m.name or "")) == name then
                    target = m.key
                    break
                end
            end
            if target and self:SetMode(target) then
                self:Print(L("Build set to ") .. target)
                if self.UpdateRecommendations then self:UpdateRecommendations() end
            else
                self:Print(L("Unknown build: ") .. name)
            end
        end
    elseif cmd == "numbers" then
        local v = not (self:GetSetting("show_priority_numbers") == true)
        self:SetSetting("show_priority_numbers", v)
        self.db.display.show_numbers = nil
        self:Print(L("Priority numbers: ") .. (v and L("ON") or L("OFF")))
        self:UpdateUI()
        self:NotifyOptions()
    elseif cmd == "pulse" then
        local enabled = not (self.db.display.pulse == false)
        self.db.display.pulse = not enabled
        self:Print(L("Glow pulse: ") .. (not enabled and L("ON") or L("OFF")))
        self:UpdateUI()
        self:NotifyOptions()
    elseif cmd == "frame" then
        self.db.display.show_spellframe = not self.db.display.show_spellframe
        self:Print(L("Icon window: ") .. (self.db.display.show_spellframe and L("ON") or L("OFF")))
        self:UpdateUI()
        self:NotifyOptions()
    elseif cmd == "selfcheck" or cmd == "check" then
        if self.RunSelfCheck then self:RunSelfCheck() end
    elseif cmd == "status" then
        self:Print(L("--- Status ---"))
        self:Print(L("Addon: ") .. (self.db.enabled and L("enabled") or L("disabled")))
        self:Print(L("Class: ") .. tostring(self.playerClass))
        self:Print(L("Spec: ") .. tostring(self:GetActiveSpec()))
        if self.GetRotationComplexity then
            self:Print(L("Adaptive: ") .. tostring(self:GetRotationComplexity())
                .. " (ilvl " .. tostring(math.floor((self:GetItemLevel() or 0) + 0.5)) .. ")")
        end
        self:Print(L("Target: ") .. tostring(UnitExists("target")) .. L(", CanAttack: ") .. tostring(UnitCanAttack("player", "target")))
        self:Print(L("Recommendations: ") .. #ns.recommendations)
        self:Print(L("Profile: ") .. tostring(self:GetCurrentProfileName()))
        self:Print(L("Action buttons found: ") .. tostring(ns.GetScanCount and ns.GetScanCount() or 0))
        self:Print(L("Glow: ") .. (ns.glowVisible and L("visible") or L("hidden")))
    elseif cmd == "errors" or string.match(cmd, "^errors%s") then
        local sub = string.match(cmd, "^errors%s+(%S+)") or ""
        local log = ns.errorLog or {}
        if sub == "clear" then
            ns.errorLog = {}
            RotationCoreErrors = ns.errorLog
            self:Print(L("Error log cleared."))
        elseif sub == "file" then
            self:Print(L("Error log is saved to:"))
            self:Print("WTF/Account/<account>/SavedVariables/RotationCoreErrors.lua")
        elseif sub == "export" then
            if ns.ShowErrorExport then
                ns.ShowErrorExport()
            else
                self:Print(L("Error export is not available."))
            end
        elseif #log == 0 then
            self:Print(L("No errors recorded. /rc errors file shows where the log is saved."))
        else
            local first = math.max(1, #log - 19)
            self:Print(L("Last ") .. (#log - first + 1) .. L(" error line(s):"))
            for i = first, #log do
                local e = log[i]
                if e.count and e.count > 1 then
                    self:Print("(x" .. e.count .. ") " .. e.msg)
                else
                    self:Print(e.msg)
                end
            end
        end
    elseif cmd == "report" then
        if ns.ShowReport then
            ns.ShowReport()
        else
            self:Print(L("Report is not available."))
        end
    elseif cmd == "feedback" then
        if self.OpenFeedback then
            self:OpenFeedback()
        else
            self:Print(L("Feedback is not available."))
        end
    elseif cmd == "live" then
        self.db.show_debug_frame = not self.db.show_debug_frame
        self:Print(L("Live debug: ") .. (self.db.show_debug_frame and L("ON") or L("OFF")))
        if ns.DebugFrame then
            if self.db.show_debug_frame then
                ns.DebugFrame:Show()
            else
                ns.DebugFrame:Hide()
            end
        end
    elseif cmd == "wizard" then
        -- Phase 1.3: re-run the guided setup at any time
        if self.db then self.db.wizardShown = false end
        if ns.Wizard and ns.Wizard.Show then
            ns.Wizard:Show()
        else
            self:Print(L("Setup Wizard is not loaded."))
        end
    elseif cmd == "move" then
        -- Unlock every window (default state; remaining for power users)
        self:SetSetting("frames_locked", false)
        if ns.SetMoveMode then ns.SetMoveMode(true) end
        self:Print(L("Move mode: drag the boxes, then /rc lock to fix them."))
    elseif cmd == "lock" then
        self:SetSetting("frames_locked", true)
        if ns.SetMoveMode then ns.SetMoveMode(false) end
        self:Print(L("Window(s) locked."))
    elseif cmd == "config" then
        local on = not (ns.IsConfigMode and ns.IsConfigMode())
        if ns.SetConfigMode then ns.SetConfigMode(on) end
        self:Print(on and L("Panel configuration opened.") or L("Panel configuration closed."))
    elseif cmd == "train" then
        -- Post-phase 2: training mode toggle
        self:ToggleTrainingMode()
    elseif cmd == "exam" then
        -- v3.3.0 phase 2: exam mode toggle
        self:ToggleExamMode()
    elseif cmd == "mentor" then
        -- v3.3.0 phase 2: mentor mode toggle
        self:ToggleMentorMode()
    elseif cmd == "dps" then
        -- v3.3.0 phase 2: DPS forecast toggle
        local v = not (self:GetSetting("dps_forecast_enabled") == true)
        self:SetSetting("dps_forecast_enabled", v)
        self:Print(L("DPS forecast: ") .. (v and L("ON") or L("OFF")))
        if self.UpdateUI then self:UpdateUI() end
        if self.NotifyOptions then self:NotifyOptions() end
    elseif string.match(cmd, "^learning") then
        -- v3.3.0 phase 3: learning statistics
        local sub = string.match(cmd, "^learning%s+(%S+)") or ""
        if sub == "graph" then
            self:PrintLearningGraph()
        elseif sub == "clear" or sub == "reset" then
            self:ClearLearning()
        else
            self:PrintLearning()
        end
    elseif cmd == "pvp" then
        -- Post-phase 4: PvP mode toggle
        self:TogglePvPMode()
    elseif string.match(cmd, "^boss") then
        -- Prompt 2: boss profiles
        local sub = string.match(cmd, "^boss%s+(%S+)") or ""
        local arg = string.match(cmd, "^boss%s+%S+%s+(.+)")
        if sub == "list" then
            local n = 0
            for id, p in pairs(self:GetBossProfiles()) do
                n = n + 1
                self:Print("  " .. tostring(id) .. " - " .. tostring(p.name or ""))
            end
            if n == 0 then self:Print(L("No boss profiles yet.")) end
        elseif sub == "save" then
            local id = arg or (self.State and self.State.encounter_id)
            if not id then
                self:Print(L("No boss profile for this encounter."))
            else
                local data = {}
                for _, k in ipairs(ns.bossOverrideKeys) do
                    local v = self:GetSetting(k)
                    if v ~= nil then data[k] = v end
                end
                data.name = (self.State and self.State.encounter_name)
                    or tostring(id)
                self:SetBossProfile(id, data)
                self:Print(L("Boss profile saved: ") .. tostring(id))
            end
        elseif sub == "apply" then
            if not arg then
                self:Print(L("Usage: /rc boss apply <id>"))
            elseif self:ApplyBossProfile(arg) then
                self:Print(L("Boss profile applied: ") .. tostring(arg))
            else
                self:Print(L("No boss profile for this encounter."))
            end
        elseif sub == "clear" or sub == "delete" then
            if not arg then
                self:Print(L("Usage: /rc boss clear <id>"))
            else
                self:DeleteBossProfile(arg)
                self:Print(L("Boss profile removed."))
            end
        elseif sub == "export" then
            self:Print(self:ExportBossProfiles())
        elseif sub == "import" then
            if ns.ShowBossImportWindow then ns.ShowBossImportWindow() end
        elseif sub == "presets" then
            for _, g in ipairs(ns.bossPresets) do
                local names = {}
                for _, b in ipairs(g.bosses) do names[#names + 1] = b.name end
                self:Print("  " .. tostring(g.raid or g.dungeon or "?")
                    .. " (" .. tostring(g.kind or "raid") .. "): "
                    .. table.concat(names, ", "))
            end
        else
            self:Print(L("Boss profiles: /rc boss list|save [id]|apply <id>|clear <id>|export|import|presets"))
        end
    elseif string.match(cmd, "^stats") then
        -- Prompt 2: skill stats + ideal-DPS comparison (Improvements 3/4)
        local sub = string.match(cmd, "^stats%s+(%S+)") or ""
        if sub == "reset" then
            ns.skillStats = {}
            ns.lastFight = nil
            self:Print(L("Stats reset."))
        elseif sub == "dps" then
            self:PrintDPS()
        else
            self:PrintStats()
        end
    elseif string.match(cmd, "^palette") then
        -- Prompt 3.1: colour palette
        local name = string.match(cmd, "^palette%s+(%S+)") or ""
        local pal = ns.PALETTES or {}
        if name == "" then
            self:Print(L("Palette: ") .. tostring(self:GetSetting("color_palette")))
        elseif pal[name] or name == "custom" then
            self:SetSetting("color_palette", name)
            if self.UpdateUI then self:UpdateUI() end
            if self.NotifyOptions then self:NotifyOptions() end
            self:Print(L("Palette set: ") .. name)
        else
            self:Print(L("Usage: /rc palette default|protanopia|deuteranopia|tritanopia|high_contrast|custom"))
        end
    elseif string.match(cmd, "^layout") then
        -- Prompt 3.4: display layout presets
        local sub = string.match(cmd, "^layout%s+(%S+)") or ""
        if sub == "export" then
            self:Print(ns.ExportLayout and ns.ExportLayout() or "")
        elseif sub == "import" then
            if ns.ShowLayoutImportWindow then ns.ShowLayoutImportWindow() end
        elseif ns.LAYOUT_PRESETS and ns.LAYOUT_PRESETS[sub] then
            ns.ApplyLayout(sub)
            self:Print(L("Layout applied: ") .. sub)
        else
            self:Print(L("Layout: /rc layout center|side|minimal|raid|export|import"))
        end
    elseif string.match(cmd, "^timeline") then
        -- Prompt 3.3: boss timeline toggle
        local on = not (self:GetSetting("timeline_enabled") == true)
        self:SetSetting("timeline_enabled", on)
        self:Print(L("Boss timeline: ") .. (on and L("ON") or L("OFF")))
        if self.UpdateUI then self:UpdateUI() end
        if self.NotifyOptions then self:NotifyOptions() end
    elseif string.match(cmd, "^apl") then
        -- Improvement 6: custom APL management
        local sub = string.match(cmd, "^apl%s+(%S+)") or ""
        local arg = string.match(cmd, "^apl%s+%S+%s+(.+)")
        if sub == "enable" or sub == "on" then
            self:SetSetting("custom_apl_enabled", true)
            self:Print(L("Custom APL: ") .. L("ON"))
            self:UpdateUI()
            self:NotifyOptions()
        elseif sub == "disable" or sub == "off" then
            self:SetSetting("custom_apl_enabled", false)
            self:Print(L("Custom APL: ") .. L("OFF"))
            self:UpdateUI()
            self:NotifyOptions()
        elseif sub == "clear" then
            self:SetSetting("custom_apl", {})
            self:SetSetting("custom_apl_source", "")
            self:Print(L("APL cleared."))
            self:UpdateUI()
            self:NotifyOptions()
        elseif sub == "import" then
            if arg and arg ~= "" then
                local n, err = ns.SetCustomAPL(self, ns.DecodeAPLShare(arg))
                if n and n > 0 then
                    self:SetSetting("custom_apl_enabled", true)
                    self:Print(L("APL imported: ") .. n .. " " .. L("rules"))
                else
                    self:Print(L("APL error: ") .. tostring(err))
                end
                self:UpdateUI()
                self:NotifyOptions()
            elseif ns.ShowAPLImportWindow then
                ns.ShowAPLImportWindow()
            else
                self:Print(L("Usage: /rc apl import <text>"))
            end
        elseif sub == "export" then
            self:Print(ns.ExportAPL(self))
        elseif sub == "share" then
            self:Print(ns.ExportAPLShare(self))
        else
            self:Print(L("APL: /rc apl enable|disable|import [text]|export|share|clear"))
        end
    elseif string.match(cmd, "^glow ") or string.match(cmd, "^icons ") then
        local val = tonumber(string.match(cmd, "^%S+%s+(%d+)"))
        if val and val >= 1 and val <= 5 then
            self.db.display.num_icons = val
            self:Print(L("Highlighting next ") .. val .. L(" abilities"))
            self:UpdateUI()
            self:NotifyOptions()
        else
            self:Print(L("Invalid. Use /rc glow <1-5>"))
        end
    elseif string.match(cmd, "^size ") then
        local val = tonumber(string.match(cmd, "^size (.+)"))
        if val and val >= 0.8 and val <= 2.5 then
            self.db.display.glow_size = val
            self:Print(L("Glow size set to ") .. val)
            self:UpdateUI()
            self:NotifyOptions()
        else
            self:Print(L("Invalid size. Use 0.8 to 2.5"))
        end
    else
        -- Try class-registered slash commands
        local handled = false
        for pattern, data in pairs(ns.slashCommands) do
            if cmd == pattern or string.match(cmd, "^" .. pattern .. " ") or string.match(cmd, "^" .. pattern .. "$") then
                data.handler(cmd)
                handled = true
                break
            end
        end

        if not handled then
            self:Print(L("Commands:"))
            self:Print(L("  /rc - Open the options window"))
            self:Print(L("  /rc config - Open the panel configuration (size, scale, opacity, colour)"))
            self:Print(L("  /rc toggle - Enable/disable addon"))
            self:Print(L("  /rc profile <name> - Switch profile"))
            self:Print(L("  /rc glow <1-5> - How many abilities are highlighted"))
            self:Print(L("  /rc size <0.8-2.5> - Glow border size"))
            self:Print(L("  /rc numbers - Toggle priority numbers"))
            self:Print(L("  /rc pulse - Toggle glow animation"))
            self:Print(L("  /rc frame - Toggle the spell icon window"))
            self:Print(L("  /rc test - Test glow on your action bars"))
            self:Print(L("  /rc status - Show debug status"))
            self:Print(L("  /rc errors - Show recent errors (/rc errors export for a report)"))
            self:Print(L("  /rc report - Copyable bug report + GitHub issue link"))
            self:Print(L("  /rc feedback - Open the feedback report"))
            self:Print(L("  /rc live - Toggle live debug frame"))
            self:Print(L("  /rc debug - Toggle debug mode"))
            self:Print(L("  /rc help - Open the help tab (/rc help full for the wizard)"))
            self:Print(L("  /rc wizard - Run the guided setup wizard"))
            self:Print(L("  /rc move - Unlock the icon window to move it"))
            self:Print(L("  /rc lock - Lock the icon window in place"))
            self:Print(L("  /rc train - Toggle training mode (ALT-SHIFT-L)"))
            self:Print(L("  /rc pvp - Toggle PvP mode (ALT-SHIFT-V)"))
            self:Print(L("  /rc boss - Boss profiles (/rc boss list|save|apply)"))
            self:Print(L("  /rc stats - Skill stats (/rc stats, /rc stats dps, /rc stats reset)"))
            -- Show class-registered commands
            for pattern, data in pairs(ns.slashCommands) do
                if data.help then
                    self:Print("  /rc " .. L(data.help))
                end
            end
        end
    end
end

-- ============================================================================
-- COMBAT LOG
-- ============================================================================

function DH:OnCombatLogEvent(timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId, spellName, spellSchool, ...)
    local playerGUID = (self.State and self.State.GUID) or UnitGUID("player")
    if sourceGUID ~= playerGUID then return end

    -- Track enemies the player recently damaged (Improvement 3). The cleave
    -- and AOE decisions use this combat-log signal instead of nameplate tokens.
    if destGUID and self.State and self.State.TrackCombatEnemy
       and type(subevent) == "string" and subevent:find("DAMAGE", 1, true) then
        self.State:TrackCombatEnemy(destGUID)
    end

    -- Build the spellId -> ability key map once (L10 optimization).
    local classAbil = self.Class and self.Class.abilities
    local abilMap = ns._abilityIdMap
    if not abilMap or ns._abilityIdMapSrc ~= classAbil then
        abilMap = {}
        if classAbil then
            for key, ability in pairs(classAbil) do
                local id = ability and ability.id
                if id and not abilMap[id] then abilMap[id] = key end
            end
        end
        ns._abilityIdMap = abilMap
        ns._abilityIdMapSrc = classAbil
    end
    local numericId = spellId and tonumber(spellId)
    local castKey = (numericId and abilMap[numericId]) or abilMap[spellId]

    -- Prompt 2: damage accumulation (fight analytics / ideal DPS) and the
    -- per-cast skill statistics + combat-log CSV row.
    if subevent == "SWING_DAMAGE" or subevent == "SPELL_DAMAGE"
        or subevent == "RANGE_DAMAGE" then
        ns.RecordDamage(self, spellId, select(1, ...))
    end
    if subevent == "SPELL_CAST_SUCCESS" then
        ns.RecordCast(self, castKey, spellId)
        -- v3.3.0: exam / mentor / pulse accuracy on every player cast.
        if ns.OnPlayerCast then ns.OnPlayerCast(self, castKey, spellId) end
    end

    -- Snooze detection: when player uses any ability, check if they skipped a snoozeable recommendation
    if subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_DAMAGE" or subevent == "SPELL_AURA_APPLIED" then
        local topRec = ns.recommendations[1]
        if topRec and castKey then
            local topAbility = topRec.ability
            if ns.snooze[castKey] then
                self:ClearSnooze(castKey)
            end

            -- Player used a different ability than recommended — snooze the recommended one
            if castKey ~= topAbility and ns.snoozeable and ns.snoozeable[topAbility] then
                self:Snooze(topAbility, ns.snoozeable[topAbility])
            end
        end
    end

    -- Dispatch to registered handlers. Each is pcall-guarded so one class
    -- module error cannot skip the remaining handlers for this event.
    for _, handler in ipairs(ns.registered.combatLogHandlers) do
        if type(handler) == "function" then
            local ok, err = pcall(handler, subevent, sourceGUID, destGUID, spellId, spellName, ...)
            if not ok and ns.AddError then
                ns.AddError("Combat-log handler failed: " .. tostring(err))
            end
        end
    end
end

-- Boss profiles, skill stats and ideal DPS lives in BossProfiles.lua.

-- Boss timeline lives in BossTimeline.lua.

-- Custom APL lives in CustomAPL.lua.

-- Analytics, learning and DPS forecast lives in Analytics.lua.

-- ============================================================================
-- /rc selfcheck: in-game invariant tests (no live client needed - the same
-- checks as verify.py, run against the running addon).
-- ============================================================================
function DH:RunSelfCheck()
    local results = {}
    local function check(name, ok, detail)
        results[#results + 1] = { name = name, ok = ok and true or false, detail = detail }
    end

    -- 1) core / class module loaded
    check("core db", self.db ~= nil, self.db and "profile: " .. self:GetCurrentProfileName() or "no db")
    if self.Class and type(self.Class.abilities) == "table" then
        local n = 0
        for _ in pairs(self.Class.abilities) do n = n + 1 end
        check("class module", true, "abilities: " .. n)
    else
        check("class module", false, "not loaded")
    end

    -- 2) ability integrity (id/name/texture)
    if self.Class and type(self.Class.abilities) == "table" then
        local bad = 0
        for key, a in pairs(self.Class.abilities) do
            if type(a) ~= "table" or type(a.id) ~= "number" or not a.name or not a.texture then
                bad = bad + 1
            end
        end
        check("ability table", bad == 0, bad .. " entries missing id/name/texture")
    end

    -- 3) build detection
    local info = self.GetBuildInfo and self:GetBuildInfo() or nil
    check("build detection", info ~= nil and info.key ~= nil,
        info and tostring(info.key) .. " (source " .. tostring(info.source) .. ")" or "no build")

    -- 4) registered modes
    local modeCount = (ns.registered.modes and #ns.registered.modes) or 0
    check("rotation modes", modeCount > 0, modeCount)

    -- 5) APL parse (if a source is stored)
    local aplSrc = self:GetSetting("custom_apl_source")
    if type(aplSrc) == "string" and aplSrc ~= "" then
        local rules = ns.ParseAPL(aplSrc)
        check("APL", #rules > 0, #rules .. " rules")
    else
        check("APL", true, "no custom APL stored")
    end

    -- 6) locale keys present
    local L = DH.L
    local missing = 0
    for _, key in ipairs({ "General", "Cooldowns", "Colors", "APL", "BURST", "Learning Stats" }) do
        if not (L and L[key]) then missing = missing + 1 end
    end
    check("locale keys", missing == 0, missing .. " missing of 6 probed")

    -- 7) active mode has a rotation and baseCDs
    local mode = self.GetActiveMode and self:GetActiveMode()
    check("active mode rotation", mode ~= nil and mode.rotation ~= nil, mode and tostring(mode.key) or "none")

    -- 8) resists the timeline frame
    check("timeline init", ns._timelineFrame ~= nil, ns._timelineFrame and "registered" or "not started")

    self:Print(L("--- RotationCore selfcheck ---"))
    local failed = 0
    for i = 1, #results do
        local r = results[i]
        if not r.ok then failed = failed + 1 end
        self:Print(string.format("  [%s] %s: %s",
            r.ok and L("PASS") or L("FAIL"), r.name, tostring(r.detail)))
    end
    self:Print(string.format(L("Selfcheck: %d/%d passed"), #results - failed, #results))
end

-- ============================================================================
-- CORE LOGIC
-- ============================================================================

-- Update state
function DH:UpdateState()
    if not self.db or not self.db.enabled then return end
    if self.State and self.State.Reset then
        self.State:Reset()
    end
end

-- Mark a state group (or "all") for refresh on the next UpdateState().
-- Expensive groups are only rebuilt when their driving event fires.
-- kind: "resources" | "auras" | "cooldowns" | "talents" | "glyphs" | "stats" | "all"
function DH:MarkStateDirty(kind)
    kind = kind or "all"
    if self.State and self.State.MarkDirty then
        self.State:MarkDirty(kind)
    end
end

-- Get active spec using registered detector
function DH:GetActiveSpec()
    local key
    if ns.registered.specDetector then
        local ok, res = pcall(ns.registered.specDetector)
        if ok then key = res end
    end
    if (not key or key == "unknown" or key == "") and ns.registered.specDetectorFallback then
        local ok, res = pcall(ns.registered.specDetectorFallback)
        if ok then key = res end
    end
    if type(key) ~= "string" or key == "" then return "unknown" end
    return key
end

-- ============================================================================
-- PHASE 3.3: PER-SPECIALIZATION SETTINGS
-- spec_profiles[specKey] holds a full copy of the shared settings for that
-- spec; GetSetting/SetSetting consult it while spec_profiles_enabled is true.
-- ============================================================================

-- Snapshot the current shared settings as the active spec's profile
function DH:SaveSpecProfile(spec)
    spec = spec or (self.GetActiveSpec and self:GetActiveSpec()) or nil
    if type(spec) ~= "string" or spec == "" or spec == "unknown" then
        return false, "Unknown spec"
    end
    if not self.db then return false, "Database not ready" end
    if type(self.db.spec_profiles) ~= "table" then self.db.spec_profiles = {} end
    self.db.spec_profiles[spec] = ns.DeepCopy(self.db.common or {})
    return true
end

-- Drop the active spec's overrides (falls back to the shared settings)
function DH:ClearSpecProfile(spec)
    spec = spec or (self.GetActiveSpec and self:GetActiveSpec()) or nil
    if type(spec) ~= "string" or self.db == nil then return false end
    if type(self.db.spec_profiles) == "table" then
        self.db.spec_profiles[spec] = nil
    end
    return true
end

-- Make the active spec the one GetSetting/SetSetting target and refresh
function DH:LoadSpecProfile(spec)
    if not self.db then return false end
    spec = spec or (self.GetActiveSpec and self:GetActiveSpec()) or nil
    self.db.spec_profiles_active = spec
    if self.RefreshConfig then self:RefreshConfig() end
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    return true
end

-- Re-apply settings after the player switches talents/spec
function DH:OnSpecChange()
    if not self.db then return end
    if not self:IsSpecProfilesEnabled() then return end
    self:LoadSpecProfile(self.GetActiveSpec and self:GetActiveSpec() or nil)
    if self.NotifyOptions then self:NotifyOptions() end
end

-- ============================================================================
-- POST-PHASE 1: RELOAD ROTATION
-- A single entry point the client calls after talents/spec/level change so the
-- whole pipeline (spell book cache, mode detection, settings, UI) rebuilds.
-- ============================================================================
function DH:ReloadRotation()
    if not self.db then return end
    if self.MarkStateDirty then self:MarkStateDirty("all") end
    if self.InvalidateKnownSpells then self:InvalidateKnownSpells() end
    if self.AutoDetectMode then self:AutoDetectMode() end
    if self.ApplyProfileDefaults then self:ApplyProfileDefaults() end
    if self.OnSpecChange then self:OnSpecChange() end
    if self.RefreshConfig then self:RefreshConfig() end
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
end

-- Is a spell off cooldown right now? (used by the direct heal-DPS lists)
function DH:SpellReady(spellId)
    if not spellId or type(GetSpellCooldown) ~= "function" then return true end
    -- Registered ids are often max-rank; resolve to the rank the player knows,
    -- otherwise GetSpellCooldown reports (0,0) and we'd wrongly say "ready".
    local id = spellId
    if self.ResolveKnownSpellId then
        id = self:ResolveKnownSpellId(spellId) or spellId
    end
    local start, dur = GetSpellCooldown(id)
    if not start or start == 0 then return true end
    return (start + (dur or 0)) <= GetTime()
end

-- Friendly name for an ability key (used by the aura bridge / debug)
function DH:GetAbilityName(key)
    local ability = self.Class and self.Class.abilities and self.Class.abilities[key]
    if ability and ability.name then return ability.name end
    if key == nil then return "" end
    return tostring(key)
end

-- Explain why an ability is being recommended right now (training mode).
-- Returns a localized reason category key and the ability name.
function DH:DescribeRecommendation(rec)
    if not rec or not rec.ability then return nil, nil end
    local key = rec.ability
    local ability = (self.Class and self.Class.abilities and self.Class.abilities[key]) or {}
    local st = self.State
    local manaPct = st and st.mana and st.mana.pct
    local rk
    if rec.execute then
        rk = "execute_phase"
    elseif ability.cd and ability.cd >= 60 then
        rk = "burst_cd_ready"
    elseif ability.proc then
        rk = "proc_active"
    elseif ability.dot or ability.duration then
        rk = "dot_missing"
    elseif st and st.gcd_remains and st.gcd_remains > 0.35 then
        rk = "gcd_wait"
    elseif manaPct and manaPct < 20 then
        rk = "resource_low"
    elseif ability.filler then
        rk = "filler"
    else
        rk = "priority"
    end
    return rk, self:GetAbilityName(key)
end

-- Print/sound on REC1 change while training mode is on (never spams)
function DH:MaybeTrainingChat(recs)
    local top = recs and recs[1] or nil
    local key = top and top.ability or nil
    if key == self._trainingLastKey then return end
    self._trainingLastKey = key
    if not top then return end
    if self:GetSetting("training_chat_output") ~= false then
        local label = L(top.reason_key or "priority")
        self:Print(L("Cast") .. " " .. self:GetAbilityName(key) .. " (" .. label .. ")")
    end
    if self:GetSetting("training_sound") and PlaySoundFile then
        PlaySoundFile("Sound\\Interface\\igMainMenuOptionCheckBoxOn.wav")
    end
end

-- ============================================================================
-- POST-PHASE 2: TRAINING MODE (toggle: ALT-SHIFT-L)
-- Keeps recommending on a live target out of combat (e.g. a training dummy)
-- instead of hiding the window.
-- ============================================================================
function DH:ToggleTrainingMode()
    if not self.db then return end
    local v = not (self:GetSetting("training_mode") == true)
    self:SetSetting("training_mode", v)
    self:Print(L("Training mode: ") .. (v and L("ON") or L("OFF")))
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
    return v
end

-- ============================================================================
-- v3.3.0 PHASE 2: EXAM MODE (toggle: ALT-SHIFT-E)
-- The icon window still shows REC1 but the action bars are never highlighted,
-- so the player must recognise the ability themselves.
-- ============================================================================
function DH:ToggleExamMode()
    if not self.db then return end
    local v = not (self:GetSetting("exam_mode") == true)
    self:SetSetting("exam_mode", v)
    if ns.ResetAnalytics then ns.ResetAnalytics() end
    self:Print(L("Exam mode: ") .. (v and L("ON") or L("OFF")))
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
    return v
end

-- ============================================================================
-- v3.3.0 PHASE 2: MENTOR MODE (toggle: ALT-SHIFT-M)
-- Counts consecutive mistakes and explains why when the threshold is reached.
-- ============================================================================
function DH:ToggleMentorMode()
    if not self.db then return end
    local v = not (self:GetSetting("mentor_mode") == true)
    self:SetSetting("mentor_mode", v)
    ns.mentorErrors = 0
    ns.mentorCorrect = 0
    self:Print(L("Mentor mode: ") .. (v and L("ON") or L("OFF")))
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
    return v
end

-- ============================================================================
-- POST-PHASE 4: PVP MODE (toggle: ALT-SHIFT-V)
-- Switches activity_profile to "pvp" and back to the previous profile.
-- ============================================================================

function DH:TogglePvPMode()
    if not self.db then return end
    if self:GetSetting("pvp_mode_enabled") then
        self:SetSetting("pvp_mode_enabled", false)
        self:Print(L("PvP mode: ") .. L("OFF"))
    else
        self:SetSetting("pvp_mode_enabled", true)
        self:Print(L("PvP mode: ") .. L("ON") .. " (" .. L("burst under")
            .. " " .. tostring(self:GetSetting("pvp_burst_threshold") or 50) .. "%)")
    end
    if self.UpdateRecommendations then self:UpdateRecommendations() end
    if self.NotifyOptions then self:NotifyOptions() end
end

-- ============================================================================
-- POST-PHASE 3: HEAL-SPEC DPS ROTATIONS (heal_dps_mode = "auto"/"on"/"off")
-- When the active mode is a "safe" healer mode, borrow the class's closest
-- DPS rotation. FilterKnown drops abilities the healer has not learned and the
-- central fallback keeps the UI alive, so nothing wrong is recommended.
-- ============================================================================
local HEAL_DPS_MODE = {
    discipline = "discipline_dps",
    holy_priest = "holy_priest_dps",
    holy_paladin = "holy_paladin_dps",
    resto_druid = "resto_druid_dps",
    resto_shaman = "resto_shaman_dps",
}

-- Should a healer run the borrowed DPS rotation right now?
function DH:IsHealDpsActive()
    local setting = self:GetSetting("heal_dps_mode")
    if setting == false or setting == "off" then return false end
    if setting == true or setting == "on" then return true end
    -- "auto" (default): only while solo / not grouped
    local prof = self:GetSetting("activity_profile") or "raid"
    if prof == "solo" then return true end
    if IsInRaid and IsInRaid() then return false end
    if IsInGroup and IsInGroup() then return false end
    return true
end

-- Return the DPS mode to borrow for a safe/healer mode, or nil
function DH:GetHealDpsMode(mode)
    if not mode or not (mode.safe or mode.heal) then return nil end
    if not self:IsHealDpsActive() then return nil end
    local dpsKey = HEAL_DPS_MODE[mode.key]
    if not dpsKey then return nil end
    local modes = ns.registered and ns.registered.modes
    if not modes then return nil end
    for _, m in ipairs(modes) do
        if m.key == dpsKey then return m end
    end
    return nil
end


-- Update recommendations (single implementation).
-- Smoothing / decision logging are provided by Config.lua via ns.*
-- and are optional here so the core still works if Config did not load.
function DH:UpdateRecommendations()
    -- Glow test overrides the normal target/combat gating so the user can
    -- verify action-bar detection any time (see ns.ShowTestGlow).
    if ns.IsTestGlow and ns.IsTestGlow() then
        self:UpdateUI()
        return
    end
    if not self.db or not self.db.enabled then
        ns.recommendations = {}
        self:HideUI()
        return
    end
    if self.db.paused then
        -- /rc pause: keep the window up (so it can show "Paused") but stop
        -- recommending. UpdateUI drives the idle-reason text.
        ns.recommendations = {}
        self:UpdateUI()
        return
    end
    local mode = self.GetActiveMode and self:GetActiveMode() or nil
    local healMode = mode and (mode.safe or mode.heal) or false
    local healDps = healMode and self.GetHealDpsMode and self:GetHealDpsMode(mode) or nil

    local training = (self:GetSetting("training_mode") == true)
    -- Real heal modes keep running out of combat so shields/HoTs/buffs can be
    -- refreshed. A healer running the solo DPS borrow (or a legacy safe mode)
    -- still hides when idle, like every DPS mode.
    local healModeActive = (mode and mode.heal and not healDps) and true or false
    if not UnitExists("target") and not ns.inCombat and not training and not healModeActive then
        ns.recommendations = {}
        self:HideUI()
        -- Still refresh the icon window so it can show an idle reason
        -- (phase 1.2) instead of silently disappearing.
        self:UpdateUI()
        return
    end

    -- Ensure state is updated (throttled/cached inside State:Reset)
    self:UpdateState()

    local recommendations = {}

    -- Healer in a "safe" or real heal mode: borrow the class's DPS rotation
    -- only when heal_dps_mode explicitly allows it. Otherwise the healer's own
    -- isolated rotation runs below.
    local rotationMode = mode
    local useHealRotation = false
    if healMode then
        if healDps then
            rotationMode = healDps
        else
            useHealRotation = true
        end
    end

    -- Post-phase 4: PvP priority branch takes over when enabled for this class.
    -- Heal modes stay on their heal rotation; a PvP DPS list must not replace
    -- the healer's job.
    local pvpRotation = ns.registered.pvpRotation
    if rotationMode and not useHealRotation and self:GetSetting("pvp_mode_enabled") and pvpRotation then
        local threshold = tonumber(self:GetSetting("pvp_burst_threshold")) or 50
        local target = self.State and self.State.target
        local hp = target and target.health and target.health.pct or 100
        recommendations = pvpRotation(self, self.State, {
            burst = hp <= threshold,
            burstThreshold = threshold,
        }) or {}
    elseif rotationMode and rotationMode.rotation then
        recommendations = rotationMode.rotation(self) or {}
    end

    -- Improvement 6: a user-authored APL replaces the class rotation when it
    -- is enabled and parsed to at least one rule. Keep heal modes isolated.
    if not useHealRotation and self:GetSetting("custom_apl_enabled") == true and ns.EvaluateAPL then
        local aplRecs, aplValid = ns.EvaluateAPL(self)
        if aplValid then recommendations = aplRecs end
    end

    -- Never recommend abilities the player has not learned yet
    recommendations = self:FilterKnown(recommendations)

    -- Central fallback: if a rotation produced nothing for an attackable
    -- target, recommend the first known basic ability instead of showing
    -- "Rec: none" with a dead UI. This is the safety net for specs/modes
    -- whose single-target branch returns nil (e.g. target_mode = "single").
    -- Never do this for an active heal mode: recommending a DPS ability to a
    -- healer is worse than showing that nobody needs healing.
    if #recommendations == 0 and not useHealRotation then
        local tgt = self.State and self.State.target
        -- Only fall back when there is something to hit (or no target data);
        -- never suggest attacking a friendly / non-attackable target.
        if (not tgt) or (tgt.canAttack ~= false) then
            local fb = self.FirstKnownFallback and self:FirstKnownFallback()
            if fb then
                recommendations = { { ability = fb, priority = 1 } }
            end
        end
    end

    -- Apply smoothing to prevent stutter (provided by Config.lua)
    if ns.SmoothRecommendations then
        recommendations = ns.SmoothRecommendations(recommendations)
    end

    -- Training / mentor mode: annotate every recommendation with a short
    -- reason and announce REC1 changes (chat/sound), throttled to changes.
    if self:GetSetting("training_mode") or self:GetSetting("mentor_mode") then
        for i = 1, #recommendations do
            local rk, name = self:DescribeRecommendation(recommendations[i])
            recommendations[i].reason_key = rk
            if rk and name and self:GetSetting("training_mode") then
                recommendations[i].reason = L(rk) .. " (" .. name .. ")"
            end
        end
    end

    ns.recommendations = recommendations

    -- Prompt 2: record the recommendation set for /rc stats (Improvement 3).
    ns.RecordRecommendations(self, recommendations)

    -- v3.3.0: refresh the live DPS forecast (throttled by its own interval).
    if ns.UpdateDPSForecast then ns.UpdateDPSForecast(self) end

    if self:GetSetting("training_mode") then
        self:MaybeTrainingChat(recommendations)
    end

    -- Decision log (provided by Config.lua)
    if ns.LogDecision and self:GetSetting("log_decisions") then
        ns.LogDecision(self, recommendations)
    end

    if #recommendations > 0 then
        self:ShowUI()
    end
    -- Throttle the icon/glow refresh to at most 20 Hz. The rotation may poll
    -- faster, but painting the UI that often is wasted work and can cause
    -- visible flicker on low-end clients.
    local nowUI = GetTime()
    if nowUI - (ns.lastUIPaint or 0) >= 0.05 then
        ns.lastUIPaint = nowUI
        self:UpdateUI()
    end
end

-- ============================================================================
-- UI FUNCTIONS (implemented in UI.lua - action bar glow display)
-- ============================================================================

function DH:InitializeUI()
    if ns.InitializeUI then
        ns.InitializeUI(self)
    end
end

function DH:UpdateUI()
    if not ns.UpdateUI then return end
    local ok, err = pcall(ns.UpdateUI, self)
    if not ok and ns.ReportError then ns.ReportError("UpdateUI", err) end
end

function DH:ShowUI()
    if not ns.ShowUI then
        ns.glowVisible = true
        return
    end
    local ok, err = pcall(ns.ShowUI)
    if not ok and ns.ReportError then ns.ReportError("ShowUI", err) end
end

function DH:HideUI()
    if not ns.HideUI then
        ns.glowVisible = false
        if ns.ClearGlows then ns.ClearGlows() end
        return
    end
    local ok, err = pcall(ns.HideUI)
    if not ok and ns.ReportError then ns.ReportError("HideUI", err) end
end


-- ============================================================================
-- v3.4.0 FEATURE PACK (part 2): status data,
-- skins, boss-class profiles, deep timeline, memory/load/compat helpers.
-- ============================================================================

ns._loadedAt = ns._loadedAt or GetTime()

ns.BUILD = {
    version = "3.4.0",
    interface = 30300,
    author = "Custom",
    date = "2026-10-13",
    files = 36,
    loc = 31667,
}

-- ---------------------------------------------------------------------------
-- STATUS TAB DATA
-- ---------------------------------------------------------------------------

function DH:GetOwnAddonIndex()
    if type(GetNumAddOns) ~= "function" or type(GetAddOnInfo) ~= "function" then
        return nil
    end
    local okN, n = pcall(GetNumAddOns)
    if not okN or type(n) ~= "number" then return nil end
    for i = 1, n do
        local ok, name = pcall(GetAddOnInfo, i)
        if ok and name == "RotationCore" then return i end
    end
    return nil
end

ns.metrics = ns.metrics or { memMB = nil, cpu = nil, at = 0 }

-- Refresh the memory / CPU readings at most once every couple of seconds and
-- cache them, so the live Status rows stay informative without hammering the
-- API every tick.
function ns.UpdateMetrics()
    local idx = DH.GetOwnAddonIndex and DH:GetOwnAddonIndex()
    if not idx then return end
    if type(UpdateAddOnMemoryUsage) == "function" then
        pcall(UpdateAddOnMemoryUsage)
    end
    if type(GetAddOnMemoryUsage) == "function" then
        local ok, m = pcall(GetAddOnMemoryUsage, idx)
        if ok and m then ns.metrics.memMB = m / 1024 end
    end
    if type(GetAddOnCPUUsage) == "function" then
        local ok, c = pcall(GetAddOnCPUUsage, idx)
        if ok and c then ns.metrics.cpu = c end
    end
    ns.metrics.at = GetTime()
end

function DH:GetAddonState()
    local enabled = self.db and self.db.enabled ~= false
    local spec = self.GetActiveSpec and self:GetActiveSpec() or "?"
    local mode = self.GetActiveMode and self:GetActiveMode()
    local modeName = mode and (mode.name or mode.key) or "?"
    local role = "?"
    if mode and mode.key and self.db and self.db[mode.key] then
        role = self.db[mode.key].role or "?"
    end
    if ns.UpdateMetrics and (GetTime() - (ns.metrics.at or 0)) > 2 then
        ns.UpdateMetrics()
    end
    return {
        enabled = enabled,
        spec = spec,
        specRole = role,
        mode = modeName,
        profile = self:GetCurrentProfileName(),
        spellframe = self.db and self.db.display and self.db.display.show_spellframe ~= false,
        updateActive = self:IsUpdateActive() and true or false,
        memoryMB = ns.metrics.memMB,
        cpu = ns.metrics.cpu,
        uptime = ns._loadedAt and (GetTime() - ns._loadedAt) or 0,
        errors = #(ns.errorLog or {}),
        lastErrorAt = ns.lastErrorTime,
    }
end

function DH:HasLib(id)
    if type(LibStub) ~= "function" then return false end
    local ok, lib = pcall(LibStub, id, true)
    return ok and lib ~= nil
end

function DH:ScanIntegrations()
    local list = {}
    local function row(addon, found, what)
        list[#list + 1] = { addon = addon, found = not not found, what = what }
    end
    row("DBM", type(DBM) == "table" or type(DBMLoader) == "table", "Timeline, boss phases")
    row("BigWigs", type(BigWigs) == "table" or type(BigWigsLoader) == "table", "Timeline, boss phases")
    row("ElvUI", type(ElvUI) == "table", "Action bars, cooldowns")
    row("Bartender4", type(Bartender4) == "table", "Action bars")
    row("Dominos", type(Dominos) == "table", "Action bars")
    row("WeakAuras", type(WeakAuras) == "table", "Display the rotation state")
    return list
end

-- ---------------------------------------------------------------------------
-- ADDON INTEROP: read the installed addons and flag likely conflicts.
-- Addons cannot read files from disk, so Interface\AddOns is inspected through
-- the addon-list API (GetNumAddOns / GetAddOnInfo), which reports every
-- installed addon together with its enabled / loaded state.
-- ---------------------------------------------------------------------------

ns.CONFLICT_RULES = {
    {
        id = "rotation", min = 1, level = "high",
        addons = { "MaxDps", "Ovale", "Hekili", "SpellFlash", "CLCInfo", "CLCRet",
                   "AethysRotation", "RotationMaster" },
        reason = "Another rotation addon is installed. Both addons may highlight or queue abilities at the same time.",
        suggest = "Use only one rotation helper at a time.",
    },
    {
        id = "actionbar", min = 2, level = "medium",
        addons = { "Bartender4", "Dominos", "ElvUI" },
        reason = "Several action-bar replacements are installed. They share the same buttons and can taint each other.",
        suggest = "Keep a single action-bar addon active.",
    },
    {
        id = "bossmod", min = 2, level = "low",
        addons = { "DBM", "BigWigs" },
        reason = "Two boss mods are installed; timeline hooks may fire twice.",
        suggest = "Run either DBM or BigWigs, not both.",
    },
}

function DH:ListInstalledAddons()
    local out = {}
    if type(GetNumAddOns) ~= "function" or type(GetAddOnInfo) ~= "function" then
        return out
    end
    local okN, n = pcall(GetNumAddOns)
    if not okN or type(n) ~= "number" then return out end
    for i = 1, n do
        local ok, name, title, _notes, enabled = pcall(GetAddOnInfo, i)
        if ok and type(name) == "string" and name ~= "" and name:sub(1, 9) ~= "Blizzard_" then
            out[#out + 1] = {
                name = name,
                title = (type(title) == "string" and title ~= "" and title) or name,
                enabled = (enabled ~= nil and enabled ~= 0 and enabled ~= false) or false,
                loaded = (type(IsAddOnLoaded) == "function" and IsAddOnLoaded(name)) and true or false,
            }
        end
    end
    return out
end

-- Match an installed addon against a base name ("DBM" matches "DBM-Core").
local function MatchInstalledAddon(installed, token)
    for _, a in ipairs(installed) do
        if a.name == token or a.name:sub(1, #token) == token then
            return a
        end
    end
    return nil
end

function DH:ScanConflicts()
    local installed = self:ListInstalledAddons()
    local conflicts = {}
    for _, rule in ipairs(ns.CONFLICT_RULES) do
        local hits, active, names = {}, 0, {}
        for _, token in ipairs(rule.addons) do
            local a = MatchInstalledAddon(installed, token)
            if a then
                hits[#hits + 1] = a
                if a.enabled or a.loaded then
                    active = active + 1
                    names[#names + 1] = a.title
                end
            end
        end
        if active >= (rule.min or 1) then
            conflicts[#conflicts + 1] = {
                id = rule.id, level = rule.level, addons = names,
                reason = rule.reason, suggest = rule.suggest,
            }
        end
    end
    return conflicts
end

function DH:StatusReport()
    local st = self:GetAddonState()
    local buf = {}
    buf[#buf + 1] = "RotationCore v" .. tostring(self.Version or "?") .. " status"
    buf[#buf + 1] = string.format("Enabled: %s | Spec: %s (%s) | Mode: %s",
        st.enabled and "YES" or "NO", st.spec, st.specRole, st.mode)
    buf[#buf + 1] = string.format("Profile: %s | SpellFrame: %s | OnUpdate: %s",
        st.profile, st.spellframe and "shown" or "hidden",
        st.updateActive and "active" or "idle")
    buf[#buf + 1] = string.format("Memory: %.1f MB | Uptime: %ds | Errors: %d",
        st.memoryMB or 0, math.floor(st.uptime), st.errors)
    local ints = self:ScanIntegrations()
    local found = {}
    for _, r in ipairs(ints) do
        if r.found then found[#found + 1] = r.addon end
    end
    buf[#buf + 1] = "Integrations: " .. ((#found > 0 and table.concat(found, ", ")) or "none")
    return table.concat(buf, "\n")
end

function DH:GetLastErrors(n)
    local log = ns.errorLog or {}
    local out = {}
    local limit = math.min(n or 10, #log)
    for i = math.max(1, #log - limit + 1), #log do
        out[#out + 1] = log[i].msg
    end
    return out
end

-- ---------------------------------------------------------------------------
-- IMPROVEMENT 27: UI SKINS
-- ---------------------------------------------------------------------------

ns.DEFAULT_BG = "Interface\\DialogFrame\\UI-DialogBox-Background"
ns.DEFAULT_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"

ns.UI_SKINS = ns.UI_SKINS or {}
ns.UI_SKINS.default = {
    name = "default",
    bg = ns.DEFAULT_BG, edge = ns.DEFAULT_EDGE,
    edgeSize = 16, tile = true, tileSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
    theme = {
        backdrop = { 0.05, 0.05, 0.05, 0.95 },
        border = { 0.3, 0.3, 0.3, 0.8 },
        title = { 1, 0.82, 0 },
        accent = { 1, 0.82, 0 },
        text = { 0.9, 0.9, 0.9 },
    },
}
ns.UI_SKINS.elvui = {
    name = "elvui",
    -- Flat modern look: solid plate + a razor-thin 1px edge.
    bg = "Interface\\Buttons\\WHITE8X8", edge = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1, tile = true, tileSize = 64,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
    theme = {
        backdrop = { 0.07, 0.07, 0.07, 0.97 },
        border = { 0.10, 0.10, 0.10, 0.98 },
        title = { 0.95, 0.78, 0.20 },
        accent = { 0.95, 0.55, 0.20 },
        text = { 0.90, 0.90, 0.90 },
    },
}
ns.UI_SKINS.minimal = {
    name = "minimal",
    bg = "Interface\\Buttons\\WHITE8X8", edge = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8, tile = true, tileSize = 64,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
    theme = {
        backdrop = { 0.02, 0.02, 0.02, 0.86 },
        border = { 0.28, 0.28, 0.28, 0.7 },
        title = { 1, 1, 1 },
        accent = { 1, 1, 1 },
        text = { 0.95, 0.95, 0.95 },
    },
}
ns.UI_SKINS.classic = {
    name = "classic",
    bg = "Interface\\FrameGeneral\\UI-Background-Rock", edge = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16, tile = true, tileSize = 256,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
    theme = {
        backdrop = { 0.34, 0.29, 0.19, 0.96 },
        border = { 0.72, 0.60, 0.32, 0.9 },
        title = { 1, 0.90, 0.50 },
        accent = { 1, 0.82, 0 },
        text = { 0.98, 0.95, 0.88 },
    },
}

-- v3.4.0-hotfix18: extra colour skins (flat WHITE8X8 plates + a thin edge).
local function FlatSkin(name, backdrop, border, title, accent, text)
    return {
        name = name,
        bg = "Interface\\Buttons\\WHITE8X8", edge = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8, tile = true, tileSize = 64,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        theme = { backdrop = backdrop, border = border, title = title, accent = accent, text = text },
    }
end
ns.UI_SKINS.fel    = FlatSkin("fel",    { 0.05, 0.10, 0.04, 0.96 }, { 0.35, 0.65, 0.20, 0.9 }, { 0.55, 1.00, 0.35 }, { 0.55, 1.00, 0.35 }, { 0.90, 0.98, 0.88 })
ns.UI_SKINS.frost  = FlatSkin("frost",  { 0.04, 0.07, 0.11, 0.96 }, { 0.30, 0.55, 0.85, 0.9 }, { 0.55, 0.80, 1.00 }, { 0.35, 0.70, 1.00 }, { 0.90, 0.95, 1.00 })
ns.UI_SKINS.void   = FlatSkin("void",   { 0.07, 0.04, 0.11, 0.96 }, { 0.50, 0.30, 0.80, 0.9 }, { 0.78, 0.55, 1.00 }, { 0.62, 0.40, 1.00 }, { 0.94, 0.90, 1.00 })
ns.UI_SKINS.blood  = FlatSkin("blood",  { 0.10, 0.03, 0.03, 0.96 }, { 0.75, 0.18, 0.18, 0.9 }, { 1.00, 0.45, 0.40 }, { 0.95, 0.25, 0.20 }, { 1.00, 0.90, 0.88 })
ns.UI_SKINS.jade   = FlatSkin("jade",   { 0.03, 0.09, 0.08, 0.96 }, { 0.20, 0.70, 0.60, 0.9 }, { 0.40, 0.95, 0.80 }, { 0.25, 0.85, 0.70 }, { 0.88, 0.98, 0.95 })
ns.UI_SKINS.gold   = FlatSkin("gold",   { 0.11, 0.08, 0.02, 0.96 }, { 0.85, 0.65, 0.15, 0.9 }, { 1.00, 0.85, 0.35 }, { 1.00, 0.75, 0.20 }, { 1.00, 0.96, 0.85 })
ns.UI_SKINS.ember  = FlatSkin("ember",  { 0.11, 0.05, 0.02, 0.96 }, { 0.90, 0.45, 0.10, 0.9 }, { 1.00, 0.60, 0.25 }, { 1.00, 0.50, 0.15 }, { 1.00, 0.92, 0.85 })

function DH:GetUISkin()
    local name = self.GetSetting and self:GetSetting("ui_skin") or "default"
    local skin = ns.UI_SKINS[name]
    if skin then return skin end
    return ns.UI_SKINS.default
end

function DH:RegisterSkin(name, def)
    if type(name) ~= "string" or type(def) ~= "table" then return false end
    ns.UI_SKINS[name] = def
    return true
end

-- ---------------------------------------------------------------------------
-- IMPROVEMENT 4 (v3.4.0): BOSS PROFILES X CLASS X SPEC
-- Stored under db.common.bossClassProfiles[bossId][class][spec] = settings.
-- ---------------------------------------------------------------------------

function DH:GetBossClassProfile(bossId, class, spec)
    local root = self.db and self.db.common and self.db.common.bossClassProfiles
    return root and root[tostring(bossId)] and root[tostring(bossId)][class]
        and root[tostring(bossId)][class][spec] or nil
end

function DH:SetBossClassProfile(bossId, class, spec, data)
    if not (self.db and self.db.common) then return end
    if type(self.db.common.bossClassProfiles) ~= "table" then
        self.db.common.bossClassProfiles = {}
    end
    local root = self.db.common.bossClassProfiles
    local cid = tostring(bossId)
    root[cid] = root[cid] or {}
    root[cid][class] = root[cid][class] or {}
    root[cid][class][spec] = data
end

function DH:DeleteBossClassProfile(bossId, class, spec)
    local p = self:GetBossClassProfile(bossId, class, spec)
    if not p then return false end
    local root = self.db.common.bossClassProfiles
    root[tostring(bossId)][class][spec] = nil
    return true
end

function DH:CurrentClassSpec()
    local cls = self.playerClass or select(2, UnitClass("player"))
    local spec = self.GetActiveSpec and self:GetActiveSpec() or nil
    if not spec and self.GetActiveMode then
        spec = (self:GetActiveMode() or {}).key
    end
    return tostring(cls or "?"), tostring(spec or "?")
end

function DH:ApplyEncounterBossClassProfile(encounterID, encounterName)
    if (self:GetSetting("boss_profile_autoload")) ~= true then return false end
    if not encounterID then return false end
    local cls, spec = self:CurrentClassSpec()
    local prof = self:GetBossClassProfile(encounterID, cls, spec)
    if not prof then return false end
    local count = 0
    for k, v in pairs(prof) do
        if type(v) ~= "table" then
            self:SetSetting(k, v)
            count = count + 1
        end
    end
    if count > 0 and self.Print then
        self:Print(L("Boss profile applied: ") .. tostring(encounterName or encounterID)
            .. " (" .. cls .. "/" .. spec .. ")")
    end
    return count > 0
end

-- ---------------------------------------------------------------------------
-- IMPROVEMENT 17: DEEP TIMELINE (BigWigs messages -> phase events)
-- ---------------------------------------------------------------------------

ns.timelinePhaseEvents = {}

function DH:SetupDeepTimeline()
    if not (self.GetSetting and self:GetSetting("timeline_deep_enabled")) then return end
    if ns.InitTimeline then ns.InitTimeline() end
end

function DH:OnDeepMessage(addon, msg, ...)
    local text = tostring(msg or "")
    ns.RecordPhaseEvent(text)
    if (self.GetSetting and self:GetSetting("timeline_deep_enabled"))
        and (self:GetSetting("timeline_phase_announce")) ~= false and self.Print then
        self:Print("|cFF9ECBFF[phases]|r " .. text)
    end
end

-- ---------------------------------------------------------------------------
-- IMPROVEMENTS 22 / 23 / 24: MEMORY / LOAD / COMPAT
-- ---------------------------------------------------------------------------

ns._spellCache = {}
ns._spellCacheVersion = 0

function DH:GetCachedSpellInfo(id)
    if ns._spellCache[id] then return ns._spellCache[id] end
    if type(GetSpellInfo) ~= "function" then return nil end
    local name, rank, icon = GetSpellInfo(id)
    ns._spellCache[id] = { name = name, rank = rank, icon = icon }
    return ns._spellCache[id]
end

function DH:MemCleanupFight()
    ns.timelinePhaseEvents = ns.timelinePhaseEvents or {}
end

function DH:RunCompatCheck()
    local log = {}
    if type(ElvUI) == "table" then
        log[#log + 1] = "ElvUI skin detected - if the highlight looks wrong, try ui_skin = elvui."
    end
    if type(Bartender4) == "table" or type(Dominos) == "table" then
        log[#log + 1] = "Custom action bars detected (Bartender4/Dominos)."
    end
    return log
end

ns._hooks = ns._hooks or {}
function DH:RegisterHook(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return end
    ns._hooks[event] = ns._hooks[event] or {}
    table.insert(ns._hooks[event], fn)
end
function ns.RunHooks(event, ...)
    local list = ns._hooks and ns._hooks[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok and DH.Print then
            DH:Print(string.format(L("Hook %s: %s"), tostring(event), tostring(err)))
        end
    end
end

-- ---------------------------------------------------------------------------
-- LIFECYCLE WRAPPERS: feed the new features from the existing flow.
-- ---------------------------------------------------------------------------

-- Feature pack attaches through hooks (no method wrapping).
DH:RegisterHook("EndFight", function(endStatus)
    DH:MemCleanupFight()
end)

DH:RegisterHook("OnEncounterStart", function(encounterID, encounterName)
    if (DH.GetSetting and DH:GetSetting("timeline_deep_enabled")) == true
        and DH.SetupDeepTimeline then
        DH:SetupDeepTimeline()
    end
    DH:ApplyEncounterBossClassProfile(encounterID, encounterName)
end)

-- UpdateRecommendations keeps a thin wrapper: it transforms the return value.
local _updateRecs = DH.UpdateRecommendations

function DH:UpdateRecommendations()
    local ok, recs = pcall(_updateRecs, self)
    if ok and type(recs) == "table" then
        return recs
    end
    if ok then
        return ns.recommendations or {}
    end
    if ns.ReportError then
        ns.ReportError("UpdateRecommendations", recs)
    elseif self.Print then
        self:Print(L("UpdateRecommendations error: ") .. tostring(recs))
    end
    return {}
end

-- Compat check at login (guarded by the setting).
if type(GetTime) == "function" and ns._loadedAt then
    local f = CreateFrame("Frame", "RotationCoreCompatTimer", UIParent)
    f:SetScript("OnUpdate", function(self, elapsed)
        self.t = (self.t or 0) + elapsed
        if self.t < 3 then return end
        self:SetScript("OnUpdate", nil)
        self:Hide()
        local log = DH:RunCompatCheck()
        for _, line in ipairs(log) do
            if DH.Print then DH:Print(line) end
        end
    end)
    f:Show()
end

-- ============================================================================
-- v3.4.0 SLASH COMMANDS (arena, memory, load time)
-- ============================================================================

DH:RegisterSlashCommand("arena", function()
    local nextMode = DH:CycleArenaMode() or "auto"
    DH:Print(L("Arena mode: ") .. tostring(nextMode))
end, "arena - cycle arena mode (auto/2v2/3v3/5v5)")

DH:RegisterSlashCommand("mem", function()
    local kb = 0
    local idx = DH:GetOwnAddonIndex()
    if idx then
        if type(UpdateAddOnMemoryUsage) == "function" then
            pcall(UpdateAddOnMemoryUsage)
        end
        if type(GetAddOnMemoryUsage) == "function" then
            local ok, m = pcall(GetAddOnMemoryUsage, idx)
            if ok then kb = m or 0 end
        end
    end
    DH:Print(string.format(L("RotationCore memory: %.2f MB"), (kb or 0) / 1024))
end, "mem - show addon memory usage")

DH:RegisterSlashCommand("loadtime", function()
    local up = ns._loadedAt and (GetTime() - ns._loadedAt) or 0
    DH:Print(string.format(L("RotationCore loaded: %.1f s ago"), up))
end, "loadtime - show time since load")

-- ============================================================================
-- v3.4.0: AUTO-ADAPTATION TO THE CURRENT CONTENT.
-- Maps the player's situation onto the activity_profile that the rotations
-- use for fight-length/cooldown decisions:
--   raid instance -> raid | party dungeon -> dungeon | arena/bg -> pvp
--   world, grouped -> dungeon (short-to-medium fights) | world, solo -> solo
-- ============================================================================

function DH:AutoDetectActivity()
    if type(GetInstanceType) ~= "function" then return nil end
    local ok, itype = pcall(GetInstanceType)
    local t = ok and itype or "none"
    if t == "raid" then return "raid" end
    if t == "party" then return "dungeon" end
    if t == "arena" or t == "pvp" then return "pvp" end
    local grouped = false
    if type(IsInGroup) == "function" and IsInGroup() then grouped = true end
    if type(IsInRaid) == "function" and IsInRaid() then grouped = true end
    if grouped then return "dungeon" end
    return "solo"
end

-- v3.4.0: normalised instance kind ("dungeon" / "raid" / "arena" / "pvp" / nil).
function DH:GetInstanceKind()
    if type(GetInstanceType) ~= "function" then return nil end
    local ok, t = pcall(GetInstanceType)
    t = ok and t or nil
    if t == "party" then return "dungeon" end
    if t == "raid" then return "raid" end
    return t
end

-- v3.4.0: NPC (creature) id from UnitGUID. This is locale-independent, unlike
-- UnitName which is localised. Format: [type]-0-[server]-[instance]-[zone]-[npc]-[spawn].
function DH:GetUnitNpcID(unit)
    if type(UnitGUID) ~= "function" then return nil end
    local ok, guid = pcall(UnitGUID, unit or "target")
    if not ok or type(guid) ~= "string" then return nil end
    local id = select(6, strsplit("-", guid))
    return tonumber(id)
end

-- v3.4.0: 5-man bosses do not reliably fire ENCOUNTER_START in 3.3.5a, and
-- ENCOUNTER_START carries a DungeonEncounter id (not the NPC id), so presets are
-- matched against the current target's NPC id (locale-independent) for both
-- raids and dungeons. A stored encounter profile (applied by ENCOUNTER_START)
-- always wins: we never clobber an active non-target override.
function DH:HandleBossTarget()
    local kind = self:GetInstanceKind()
    local in_instance = (kind == "dungeon" or kind == "raid")
    if not (self.GetSetting and self:GetSetting("boss_profiles_enabled") == true)
       or not in_instance then
        if ns.bossTargetActive then
            self:RestoreDefaultProfile()
            ns.bossTargetActive = nil
        end
        return
    end
    local name = UnitExists("target") and UnitName("target") or nil
    local npc = self:GetUnitNpcID("target")
    local b = npc and self:FindPreset(npc, name, kind) or nil
    if not b and name then b = self:FindPreset(nil, name, kind) end
    if b then
        if ns.bossTargetActive ~= b.name then
            local can_apply = (not ns.bossBackup.active)
                or (ns.bossBackup.src == "target")
            if can_apply then
                if ns.bossBackup.active then self:RestoreDefaultProfile() end
                if self:ApplyBossPresetFor(b.id, b.name, kind) then
                    if ns.bossBackup.active then ns.bossBackup.src = "target" end
                    ns.bossTargetActive = b.name
                    self:Print(L("Boss profile applied: ") .. tostring(b.name))
                end
            end
        end
    elseif ns.bossTargetActive then
        self:RestoreDefaultProfile()
        ns.bossTargetActive = nil
    end
end

-- v3.4.0: clear a target-detected boss override once its fight is over.
function DH:HandleBossCombatEnd()
    if not ns.bossTargetActive then return end
    local kind = self:GetInstanceKind()
    local name = UnitExists("target") and UnitName("target") or nil
    local npc = self:GetUnitNpcID("target")
    local b = npc and self:FindPreset(npc, name, kind) or nil
    if not b and name then b = self:FindPreset(nil, name, kind) end
    if not b or b.name ~= ns.bossTargetActive then
        self:RestoreDefaultProfile()
        ns.bossTargetActive = nil
    end
end

function DH:RefreshAutoActivity()
    if (self.GetSetting and self:GetSetting("auto_activity")) ~= true then return end
    if not self.db then return end
    local v = self:AutoDetectActivity()
    if not v then return end
    local cur = self:GetSetting("activity_profile")
    if cur ~= v then
        self:SetSetting("activity_profile", v)
        if self.NotifyOptions then self:NotifyOptions() end
    end
end

do
    local af = CreateFrame("Frame", "RotationCoreActivity", UIParent)
    af:RegisterEvent("PLAYER_ENTERING_WORLD")
    af:RegisterEvent("PLAYER_LEAVING_WORLD")
    af:RegisterEvent("GROUP_ROSTER_UPDATE")
    af:RegisterEvent("UPDATE_INSTANCE_INFO")
    af:RegisterEvent("ENCOUNTER_START")
    af:RegisterEvent("ENCOUNTER_END")
    af:SetScript("OnEvent", function()
        if DH.RefreshAutoActivity then DH:RefreshAutoActivity() end
        if DH.HandleBossTarget then DH:HandleBossTarget() end
    end)
end

function DH:DebugCooldowns()
    local on = (self.GetSetting and self:GetSetting("show_cooldowns_display")) == true
    local shown, count, alpha, pos = false, 0, 0, {}
    if ns.CooldownState then
        shown, count, alpha, pos = ns.CooldownState()
    end
    self:Print(string.format(
        "Cooldowns window: exists=%s isShown=%s alpha=%s pos=%s,%s count=%s show_setting=%s",
        tostring(ns.CooldownState ~= nil and ns.lastCdConfig ~= nil or false),
        tostring(shown),
        alpha and string.format("%.1f", alpha) or "?",
        pos and tostring(pos.x) or "?", pos and tostring(pos.y) or "?",
        tostring(count), tostring(on)))
    if not on and self.SetSetting then
        self:SetSetting("show_cooldowns_display", true)
        self:Print(L("Show cooldowns window: ENABLED. Drag it to move; /rc lock to stop."))
    end
    if ns.RefreshExtraFrames then ns.RefreshExtraFrames() end
end

DH:RegisterSlashCommand("cleanup", function()
    if ns.CleanupExtraFrames then ns.CleanupExtraFrames() end
    if ns.HideAllWindows then ns.HideAllWindows() end
    if DH.ApplyShellStyle then DH:ApplyShellStyle() end
    DH:Print(L("UI frames cleaned; shell style reapplied."))
end, "cleanup - recreate UI frames / reapply shell style")

DH:RegisterSlashCommand("debug", function(cmd)
    if cmd:match("debug cooldowns") then
        DH:DebugCooldowns()
    else
        DH:Print(L("Usage: /rc debug cooldowns"))
    end
end, "debug cooldowns - inspect the cooldowns window")
