-- Config.lua
-- Minimap button with rotation mode dropdown for RotationCore (3.3.5a, no dependencies)

local DH = RotationCore
if not DH then return end

local ns = DH.ns

-- Localization helper (Locale.lua fills DH.L lazily)
local function L(s)
    local tbl = DH.L
    if tbl and type(s) == "string" then return tbl[s] end
    return s
end

-- ============================================================================
-- ROTATION MODE SYSTEM
-- Class modules register available modes via DH:RegisterMode() (defined in RotationCore.lua)
-- ============================================================================

-- Get the active mode data
function DH:GetActiveMode()
    local modeKey = self.db and self.db.mode or nil
    for _, mode in ipairs(ns.registered.modes) do
        if mode.key == modeKey then
            return mode
        end
    end
    -- Fallback to first registered mode
    return ns.registered.modes[1]
end

-- DH:ApplyMode() / DH:SetMode() / DH:AutoDetectMode() live in
-- RotationCore.lua so the core, the minimap dropdown and the options
-- window all share one implementation.

-- ============================================================================
-- MINIMAP BUTTON (LibDataBroker + LibDBIcon)
-- The old self-made frame is gone: a broker object drives the button, so
-- LibDBIcon handles positioning, dragging and hide/show (part F).
-- ============================================================================

local function RegisterMinimapButton()
    if ns.MinimapButton then return ns.MinimapButton end
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return nil end

    local dataObj = LDB:NewDataObject("RotationCore", {
        type = "launcher",
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        label = "RotationCore",
        OnClick = function(_, mouseButton)
            if mouseButton == "RightButton" then
                if DH.OpenOptions then
                    DH:OpenOptions()
                end
                return
            end
            if mouseButton == "MiddleButton" then
                if DH.db and DH.db.minimap then DH.db.minimap.minimapPos = 225 end
                if LDBIcon and LDBIcon.Refresh then LDBIcon:Refresh("RotationCore") end
                return
            end
            if not DH.db then return end
            DH:SetEnabled(not DH.db.enabled)
            DH:Print(string.format(L("RotationCore %s"), DH.db.enabled and L("enabled") or L("disabled")))
            DH:NotifyOptions()
        end,
        OnTooltipShow = function(tip)
            tip:AddLine("RotationCore v" .. (DH.Version or ""))
            local mode = DH:GetActiveMode()
            if mode then
                tip:AddLine(L("Mode") .. ": |cFF00FF00" .. mode.name .. "|r", 1, 1, 1)
            end
            tip:AddLine("|cFFFFFFFF" .. L("Minimap Left Click") .. "|r", 0.7, 0.7, 0.7)
            tip:AddLine("|cFFFFFFFF" .. L("Minimap Right Click") .. "|r", 0.7, 0.7, 0.7)
            tip:AddLine("|cFFFFFFFF" .. L("Minimap Middle Click") .. "|r", 0.7, 0.7, 0.7)
        end,
    })
    if not dataObj then return nil end

    local mm = DH.db and DH.db.minimap
    if mm then
        -- migrate fields written by the old self-made button
        if mm.minimapPos == nil and mm.position ~= nil then
            mm.minimapPos = mm.position
        end
        if mm.lock == nil and mm.locked ~= nil then
            mm.lock = mm.locked
        end
    else
        mm = { hide = false, minimapPos = 225 }
        if DH.db then DH.db.minimap = mm end
    end

    LDBIcon:Register("RotationCore", dataObj, mm)
    ns.MinimapButton = LDBIcon:GetMinimapButton("RotationCore")

    local mode = DH:GetActiveMode()
    if ns.MinimapButton and ns.MinimapButton.icon and mode and mode.icon then
        ns.MinimapButton.icon:SetTexture(mode.icon)
    end

    -- Back-compat helpers used by DH:RefreshConfig / legacy callers
    if ns.MinimapButton then
        ns.MinimapButton.ApplyPosition = function()
            LDBIcon:Refresh("RotationCore")
        end
    end

    return ns.MinimapButton
end

-- ============================================================================
-- OVERRIDE ROTATION DISPATCH
-- Use the selected mode's rotation instead of spec-based dispatch
-- ============================================================================

-- Smoothing: Rec1 always shows the sim's top pick (no smoothing on slot 1).
-- Slots 2-3 resist changing for SMOOTH_LOCK_DURATION to prevent stutter,
-- unless the old ability is no longer in the recommendations at all.
local smoothState = {
    abilities = {},     -- { [slot] = abilityKey }
    changeTime = {},    -- { [slot] = GetTime() when this slot last changed }
}
local SMOOTH_LOCK_DURATION = 0.5

-- Signature early-out: when the sim output is unchanged and no smoothing lock
-- can expire before the next call, reuse the previous result as-is.
local smoothCache = { sig = nil, result = nil, safeUntil = 0 }

-- Reset the smoothing lock (called on spec/mode/profile change so a new
-- rotation is not stuck behind an old locked slot-2/3 ability).
function ns.ResetSmoothing()
    smoothState.abilities = {}
    smoothState.changeTime = {}
    smoothCache.sig = nil
    smoothCache.result = nil
    smoothCache.safeUntil = 0
end

-- Exposed on ns so the core UpdateRecommendations (RotationCore.lua) can call it.
ns.SmoothRecommendations = function(newRecs)
    local now = GetTime()

    local sig = (newRecs[1] and newRecs[1].ability or "-") .. "|" ..
                (newRecs[2] and newRecs[2].ability or "-") .. "|" ..
                (newRecs[3] and newRecs[3].ability or "-")
    if sig == smoothCache.sig and now < smoothCache.safeUntil then
        return smoothCache.result
    end

    local smoothed = {}
    local used = {}  -- Prevent same ability in multiple slots

    for i = 1, 3 do
        local newAbility = newRecs[i] and newRecs[i].ability or nil
        local oldAbility = smoothState.abilities[i]
        local lastChange = smoothState.changeTime[i] or 0
        local locked = (now - lastChange) < SMOOTH_LOCK_DURATION

        -- Slot 1: always follow the sim — this is what to press NOW
        if i == 1 or newAbility == oldAbility or not oldAbility or not locked then
            smoothed[i] = newRecs[i]
            if newAbility then used[newAbility] = true end
            if newAbility ~= oldAbility then
                smoothState.abilities[i] = newAbility
                smoothState.changeTime[i] = now
            end
        else
            -- Slots 2-3 locked: keep old ability if still recommended AND not already used
            local oldStillValid = false
            if not used[oldAbility] then
                for j = 1, #newRecs do
                    if newRecs[j].ability == oldAbility then
                        oldStillValid = true
                        break
                    end
                end
            end

            if oldStillValid then
                for j = 1, #newRecs do
                    if newRecs[j].ability == oldAbility then
                        smoothed[i] = newRecs[j]
                        used[oldAbility] = true
                        break
                    end
                end
            else
                -- Old ability gone or already used — accept new if not used
                if newAbility and not used[newAbility] then
                    smoothed[i] = newRecs[i]
                    used[newAbility] = true
                else
                    -- Find any unused rec
                    for j = 1, #newRecs do
                        if not used[newRecs[j].ability] then
                            smoothed[i] = newRecs[j]
                            used[newRecs[j].ability] = true
                            break
                        end
                    end
                end
                smoothState.abilities[i] = smoothed[i] and smoothed[i].ability or nil
                smoothState.changeTime[i] = now
            end
        end
    end

    smoothCache.sig = sig
    smoothCache.result = smoothed
    -- Result stays valid until the earliest still-active lock expires.
    local safeUntil = math.huge
    for i = 2, 3 do
        local lc = smoothState.changeTime[i]
        if lc and lc > 0 then
            local exp = lc + SMOOTH_LOCK_DURATION
            if exp > now and exp < safeUntil then safeUntil = exp end
        end
    end
    smoothCache.safeUntil = safeUntil

    return smoothed
end

-- Decision log (part 7.4): buffer recommendations for /rc log dump.
-- Repeated identical decisions are skipped so event spam cannot flood
-- the buffer before log_max_lines has any meaning.
local function LogDecision(self, recs)
    local mode = self:GetActiveMode()
    local function keyAt(i)
        return recs[i] and recs[i].ability or "-"
    end
    local r1, r2, r3 = keyAt(1), keyAt(2), keyAt(3)
    local spec = (mode and mode.key) or "-"

    local sig = spec .. ">" .. r1 .. ">" .. r2 .. ">" .. r3
    if sig == ns.logSig then return end
    ns.logSig = sig

    local st = self.State or {}
    local mana = (st.mana and st.mana.current) or 0
    local energy = (st.energy and st.energy.current) or 0

    local line = string.format("[%.1f] %s -> %s > %s > %s | mana=%d energy=%d",
        GetTime(), spec, r1, r2, r3,
        math.floor(mana + 0.5), math.floor(energy + 0.5))

    -- Ring buffer: append is O(1); when full the oldest line is overwritten.
    local cap = math.max(1, tonumber(self:GetSetting("log_max_lines")) or 1000)
    local ring = ns.logBuffer
    if type(ring) ~= "table" or ring.cap ~= cap or not ring.items then
        local fresh = { items = {}, cap = cap, head = 1, count = 0 }
        if type(ring) == "table" then
            -- Migrate a legacy plain array (keep the newest `cap` lines, in order)
            local n = #ring
            local over = math.max(0, n - cap)
            for i = 1, math.min(n, cap) do
                fresh.count = fresh.count + 1
                fresh.items[fresh.count] = ring[i + over]
            end
        end
        ring = fresh
        ns.logBuffer = ring
    end
    if ring.count < ring.cap then
        ring.count = ring.count + 1
        ring.items[ring.count] = line
    else
        ring.items[ring.head] = line
        ring.head = (ring.head % ring.cap) + 1
    end

end

ns.LogDecision = LogDecision

-- NOTE: DH:UpdateRecommendations now lives in RotationCore.lua (single
-- implementation). Smoothing and decision logging are exposed above as
-- ns.SmoothRecommendations / ns.LogDecision for the core to call.

-- ============================================================================
-- INITIALIZATION
-- RotationCore.lua calls ConfigOnInit from OnInitialize (ADDON_LOADED, the
-- saved variables are available by then) and ConfigOnEnable from OnEnable.
-- Nothing here may run at file scope against RotationCoreDB - that was the
-- bug that made settings revert on every game restart.
-- ============================================================================

-- Slash command to toggle minimap visibility
DH:RegisterSlashCommand("minimap", function(cmd)
    if not DH.db then return end
    if DH.db.minimap then
        DH.db.minimap.hide = not DH.db.minimap.hide
        local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
        if LDBIcon then
            LDBIcon:Refresh("RotationCore")
        elseif ns.MinimapButton then
            if DH.db.minimap.hide then
                ns.MinimapButton:Hide()
            else
                ns.MinimapButton:Show()
            end
        end
        DH:Print(L("Minimap button: ") .. (DH.db.minimap.hide and L("hidden") or L("shown")))
    end
end, "minimap - Toggle minimap button visibility")

-- Decision log: /rc log dump | /rc log clear (part 7.4)
DH:RegisterSlashCommand("log", function(cmd)
    local sub = cmd and cmd:match("^log%s+(%S+)") or ""
    if sub == "dump" then
        local ring = ns.logBuffer
        local n = (type(ring) == "table" and ring.count) or 0
        if n == 0 then
            DH:Print(L("Log is empty."))
            return
        end
        local first = math.max(1, n - 29)
        if first > 1 then
            DH:Print(string.format(L("Last %d of %d log lines:"), n - first + 1, n))
        end
        for k = first, n do
            local idx = ((ring.head - 1 + k - 1) % ring.cap) + 1
            DH:Print(ring.items[idx])
        end
    elseif sub == "clear" then
        ns.logBuffer = nil
        ns.logSig = nil
        DH:Print(L("Log cleared."))
    else
        DH:Print(L("Usage: /rc log dump - show the last recorded decisions"))
        DH:Print(L("       /rc log clear - clear the log"))
    end
end, "log dump|clear|file - Decision log")

-- Interop: /rc conflicts - list installed addons that may conflict with us.
DH:RegisterSlashCommand("conflicts", function()
    local conflicts = (DH.ScanConflicts and DH:ScanConflicts()) or {}
    if #conflicts == 0 then
        DH:Print(L("No addon conflicts detected."))
        return
    end
    DH:Print(L("Potential addon conflicts:"))
    for _, c in ipairs(conflicts) do
        DH:Print(string.format("|cFFFFD100%s|r - %s", table.concat(c.addons, ", "), L(c.reason)))
        if c.suggest then DH:Print("  " .. L(c.suggest)) end
    end
end, "conflicts - check for addon conflicts")

-- Config defaults (injected at file scope so BuildDefaults() picks them up)
local configDefaults = {
    minimap = {
        hide = false,
        locked = false,
        position = 225,
        detached = false,
    },
}

-- Same merge as MergeDefaults() in RotationCore.lua, but this file keeps
-- its own copy so it also works when the database was loaded before us.
local function MergeIfMissing(saved, defaults)
    if type(saved) ~= "table" then return end
    for k, v in pairs(defaults) do
        if saved[k] == nil then
            if type(v) == "table" then
                saved[k] = {}
                MergeIfMissing(saved[k], v)
            else
                saved[k] = v
            end
        elseif type(v) == "table" and type(saved[k]) == "table" then
            MergeIfMissing(saved[k], v)
        end
    end
end

-- Inject config defaults into the registered defaults table (file scope is
-- safe here: it never touches the saved variables file)
for k, v in pairs(configDefaults) do
    ns.registered.defaults[k] = ns.registered.defaults[k] or v
end

-- Called from DH:OnInitialize() after the database is loaded
function DH:ConfigOnInit()
    if not self.db then return end
    MergeIfMissing(self.db, configDefaults)
    self:ApplyProfileDefaults()
end

-- ============================================================================
-- POST-PHASE 2 / 4: KEY BINDINGS (ALT-SHIFT-L training, ALT-SHIFT-V PvP)
-- Hidden buttons receive CLICK bindings so the keys are rebindable from the
-- standard Key Bindings UI (the actions appear under the "RotationCore" group).
-- ============================================================================
BINDING_HEADER_ROTATIONCORE = BINDING_HEADER_ROTATIONCORE or "RotationCore"
BINDING_NAME_ROTATIONCORE_TRAINING = L("Toggle training mode")
BINDING_NAME_ROTATIONCORE_PVP = L("Toggle PvP mode")
BINDING_NAME_ROTATIONCORE_EXAM = L("Toggle exam mode")
BINDING_NAME_ROTATIONCORE_MENTOR = L("Toggle mentor mode")

local function RegisterKeybinds()
    if ns._keybindsRegistered then return end
    ns._keybindsRegistered = true

    local trainBtn = CreateFrame("Button", "RotationCoreTrainingButton", UIParent)
    trainBtn:Hide()
    trainBtn:RegisterForClicks("AnyUp")
    trainBtn:SetScript("OnClick", function()
        if DH.ToggleTrainingMode then DH:ToggleTrainingMode() end
    end)

    local pvpBtn = CreateFrame("Button", "RotationCorePvPButton", UIParent)
    pvpBtn:Hide()
    pvpBtn:RegisterForClicks("AnyUp")
    pvpBtn:SetScript("OnClick", function()
        if DH.TogglePvPMode then DH:TogglePvPMode() end
    end)

    -- v3.3.0 phase 2: exam / mentor toggles
    local examBtn = CreateFrame("Button", "RotationCoreExamButton", UIParent)
    examBtn:Hide()
    examBtn:RegisterForClicks("AnyUp")
    examBtn:SetScript("OnClick", function()
        if DH.ToggleExamMode then DH:ToggleExamMode() end
    end)

    local mentorBtn = CreateFrame("Button", "RotationCoreMentorButton", UIParent)
    mentorBtn:Hide()
    mentorBtn:RegisterForClicks("AnyUp")
    mentorBtn:SetScript("OnClick", function()
        if DH.ToggleMentorMode then DH:ToggleMentorMode() end
    end)

    -- v3.4.0: arena mode cycle (ALT-SHIFT-A)
    local arenaBtn = CreateFrame("Button", "RotationCoreArenaButton", UIParent)
    arenaBtn:Hide()
    arenaBtn:RegisterForClicks("AnyUp")
    arenaBtn:SetScript("OnClick", function()
        if DH.CycleArenaMode then DH:CycleArenaMode() end
    end)

    -- Bind the defaults only when the keys are free (never clobber a player's)
    if GetBindingAction and SetBinding then
        if GetBindingAction("ALT-SHIFT-L") == "" then
            SetBinding("ALT-SHIFT-L", "CLICK RotationCoreTrainingButton:LeftButton")
        end
        if GetBindingAction("ALT-SHIFT-V") == "" then
            SetBinding("ALT-SHIFT-V", "CLICK RotationCorePvPButton:LeftButton")
        end
        if GetBindingAction("ALT-SHIFT-E") == "" then
            SetBinding("ALT-SHIFT-E", "CLICK RotationCoreExamButton:LeftButton")
        end
        if GetBindingAction("ALT-SHIFT-M") == "" then
            SetBinding("ALT-SHIFT-M", "CLICK RotationCoreMentorButton:LeftButton")
        end
        if GetBindingAction("ALT-SHIFT-A") == "" then
            SetBinding("ALT-SHIFT-A", "CLICK RotationCoreArenaButton:LeftButton")
        end
        -- NOTE: never call SaveBindings() here. It persists the in-memory
        -- bindings to disk and, if run before the client loaded the player's
        -- own set (or while a character-specific set is active), it wipes the
        -- user's key bindings. SetBinding() applies the default immediately;
        -- it is re-applied on every login, so nothing needs to be saved.
    end
end

-- Called from DH:OnEnable() once the UI exists
function DH:ConfigOnEnable()
    if not self.db then return end
    self:ApplyProfileDefaults()
    RegisterMinimapButton()
    RegisterKeybinds()
end

-- Re-apply settings to on-screen elements (minimap button, options window)
function DH:RefreshConfig()
    if not self.db then return end

    local button = ns.MinimapButton
    if button then
        local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
        if LDBIcon then
            -- re-reads db.hide / db.minimapPos / db.lock
            LDBIcon:Refresh("RotationCore")
        end
        local mode = self:GetActiveMode()
        if mode and mode.icon and button.icon then
            button.icon:SetTexture(mode.icon)
        end
    end

    self:UpdateUI()

    if ns.RefreshSpellFrame then
        ns.RefreshSpellFrame()
    end

    if ns.RefreshExtraFrames then
        ns.RefreshExtraFrames()
    end

    if self.RefreshOptions then
        self:RefreshOptions()
    end
end

-- If the main file already initialized (custom load order), run our part now
if DH._initialized then DH:ConfigOnInit() end
if DH._enabled then DH:ConfigOnEnable() end



-- ============================================================================
-- UI STYLE + SHELL ADAPTATION (auto)
-- The window style is always the Blizzard base theme; the shell is detected
-- from loaded addons (ElvUI gets a flat dark theme, Bartender4/Dominos keep
-- the standard look). No user setting for this anymore.
-- ============================================================================

ns.UI_STYLES = ns.UI_STYLES or {
    blizzard = {
        theme = {
            backdrop = { 0.10, 0.10, 0.10, 0.88 },
            border = { 0.85, 0.70, 0.45, 0.95 },
            title = { 1, 0.90, 0.55 },
            accent = { 1, 0.82, 0 },
            text = { 0.95, 0.95, 0.95 },
        },
    },
    custom = {
        theme = {
            backdrop = { 0.05, 0.05, 0.05, 0.95 },
            border = { 0.4, 0.4, 0.4, 0.8 },
            title = { 1, 0.82, 0 },
            accent = { 1, 0.82, 0 },
            text = { 0.9, 0.9, 0.9 },
        },
    },
    classic = {
        theme = {
            backdrop = { 0.14, 0.10, 0.05, 0.9 },
            border = { 0.72, 0.60, 0.32, 0.9 },
            title = { 1, 0.85, 0.4 },
            accent = { 1, 0.82, 0 },
            text = { 0.95, 0.88, 0.75 },
        },
    },
}

ns.SHELL_THEMES = ns.SHELL_THEMES or {
    elvui = {
        backdrop = { 0.06, 0.06, 0.06, 0.96 },
        border = { 0.12, 0.12, 0.12, 0.98 },
        title = { 0.95, 0.75, 0.2 },
        accent = { 0.95, 0.55, 0.2 },
        text = { 0.85, 0.85, 0.85 },
    },
}

-- Detect the active UI shell (always auto-detected from loaded addons).
function DH:DetectShell()
    if type(IsAddOnLoaded) == "function" then
        if IsAddOnLoaded("ElvUI") then return "elvui" end
        if IsAddOnLoaded("Bartender4") then return "bartender4" end
        if IsAddOnLoaded("Dominos") then return "dominos" end
    end
    return "blizzard"
end

-- Resolve the active window style and the shell.
function DH:GetUIStyle()
    return ns.UI_STYLES.blizzard, self:DetectShell()
end

-- Force windows to re-read the style/shell (called on toggle and at login).
function DH:ApplyShellStyle()
    if self.GetUITheme then self:GetUITheme() end
    if self.RefreshOptions then self:RefreshOptions() end
    if self.UpdateUI then self:UpdateUI() end
    if ns.RefreshExtraFrames then ns.RefreshExtraFrames() end
end
