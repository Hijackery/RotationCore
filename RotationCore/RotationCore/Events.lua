-- Events.lua
-- Event handling. Split out of RotationCore.lua.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

-- Main event frame
local eventFrame = CreateFrame("Frame", "RotationCoreEventFrame", UIParent)
eventFrame:Hide()
ns.eventFrame = eventFrame

-- ----------------------------------------------------------------------------
-- Update scheduling.
--
-- Heavy state groups are event-driven and cached (see DH:MarkStateDirty), so the
-- frame poll is only a *fallback*. Two modes (setting: update_mode):
--   "events" (default): OnUpdate runs only while it matters (in combat or with a
--           target) at PollInterval(), and is removed entirely while idle so the
--           addon costs nothing out of combat. Game events request an update via
--           DH:RequestUpdate(), throttled to UPDATE_THROTTLE so a burst of many
--           events still yields a single update.
--   "poll": legacy fixed-rate polling at poll_frequency Hz, always running.
-- ----------------------------------------------------------------------------
local updateElapsed = 0
local UPDATE_THROTTLE = 0.1 -- min seconds between event-driven updates
local lastUpdateAt = 0
local pendingUpdate = false
local updateLoopActive = false

local function PollInterval()
    local hz = tonumber(DH.GetSetting and DH:GetSetting("poll_frequency")) or 5
    if hz < 1 then
        hz = 1
    elseif hz > 30 then
        hz = 30
    end
    return 1 / hz
end

local function RunUpdate()
    lastUpdateAt = GetTime()
    pendingUpdate = false
    DH:UpdateRecommendations()
    -- Run class-specific glow updater if registered. Guarded so a class module
    -- error cannot break the update loop for other classes / the core UI.
    if ns.registered.glowUpdater then
        local ok, err = pcall(ns.registered.glowUpdater)
        if not ok then
            if ns.ReportError then
                ns.ReportError("glowUpdater", err)
            elseif ns.AddError then
                ns.AddError("glowUpdater failed: " .. tostring(err))
            end
        end
    end
end

local function TickBody(elapsed)
    updateElapsed = updateElapsed + elapsed
    -- Flush a coalesced event request as soon as the throttle window allows.
    if pendingUpdate then
        if updateElapsed >= UPDATE_THROTTLE then
            updateElapsed = 0
            RunUpdate()
            if DH.SyncUpdateLoop then
                DH:SyncUpdateLoop()
            end
        end
        return
    end
    if updateElapsed >= PollInterval() then
        updateElapsed = 0
        RunUpdate()
    end
end

local function OnUpdateTick(_, elapsed)
    local ok, err = pcall(TickBody, elapsed)
    if not ok then
        -- Stop the loop so a persistent error cannot spam the error handler
        -- every frame; a later event can reinstall it via SyncUpdateLoop.
        if eventFrame then
            eventFrame:SetScript("OnUpdate", nil)
        end
        updateLoopActive = false
        pendingUpdate = false
        if ns.ReportError then
            ns.ReportError("Update loop stopped", err)
        elseif ns.AddError then
            ns.AddError("Update loop stopped after error: " .. tostring(err))
        end
    end
end

-- Install/remove the fallback poll depending on mode and activity.
function DH:SyncUpdateLoop()
    local enabled = DH.db and DH.db.enabled ~= false
    -- Zero-impact: the scheduler is always event-driven (idle out of combat).
    local mode = "events"
    local want
    if not enabled then
        want = false
    elseif mode == "poll" then
        want = true
    else
        want = ns.inCombat or pendingUpdate or UnitExists("target") or (ns.IsTestGlow and ns.IsTestGlow())
    end
    if want and not updateLoopActive then
        updateElapsed = 0
        eventFrame:SetScript("OnUpdate", OnUpdateTick)
        updateLoopActive = true
    elseif not want and updateLoopActive then
        eventFrame:SetScript("OnUpdate", nil)
        updateLoopActive = false
    end
end

-- Status tab: is the update loop currently installed?
function DH:IsUpdateActive()
    return updateLoopActive
end

-- Event-driven update request. Coalesces bursts and never runs more often than
-- UPDATE_THROTTLE. force=true bypasses the throttle (user-initiated changes).
function DH:RequestUpdate(force)
    local now = GetTime()
    if force or (now - lastUpdateAt) >= UPDATE_THROTTLE then
        RunUpdate()
        return
    end
    pendingUpdate = true
    if not updateLoopActive then
        DH:SyncUpdateLoop()
    end
end

-- Run a function once on the next frame. 3.3.5a has no C_Timer, so a throwaway
-- frame's one-shot OnUpdate provides the deferral (used to read talent data
-- after the talent event has fully resolved).
local deferFrame
local deferQueue = {}
local function DeferNextFrame(fn)
    if type(fn) ~= "function" then
        return
    end
    deferQueue[#deferQueue + 1] = fn
    if not deferFrame then
        deferFrame = CreateFrame("Frame")
        deferFrame:Show() -- OnUpdate only fires on a shown frame
    end
    deferFrame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local queue = deferQueue
        deferQueue = {}
        for i = 1, #queue do
            local ok, err = pcall(queue[i])
            if not ok and ns.AddError then
                ns.AddError("Deferred task failed: " .. tostring(err))
            end
        end
    end)
end

-- Event handler
local function DispatchEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "RotationCore" then
            DH:OnInitialize()
            DH:OnEnable()
        elseif name == "DBM-Core" or name == "DBM" or name == "BigWigs" or name == "BigWigs_Core" then
            -- Boss mod loaded after us: (re)register the timeline callbacks.
            if ns.InitTimeline then
                ns.InitTimeline()
            end
        end
    elseif event == "PLAYER_LOGIN" then
        -- Rotation module (LoadOnDemand) + build from talents
        DH:MarkStateDirty("all")
        DH:LoadClassModule()
        DH:AutoDetectMode()
        DH:MaybeShowFirstRunWizard()
    elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- Talents changed: always drop the stale caches (cheap, safe), then
        -- rebuild the rotation - optionally deferred to the next frame so we
        -- never read talent data mid-event.
        DH:MarkStateDirty("talents")
        DH:InvalidateKnownSpells()
        if DH:GetSetting("auto_reload_on_talent_change") ~= false then
            DeferNextFrame(function()
                DH:ReloadRotation()
            end)
        else
            DH:AutoDetectMode()
            DH:NotifyOptions()
        end
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" then
        -- New spells learned: the "known abilities" cache is stale
        DH:MarkStateDirty("talents")
        DH:MarkStateDirty("glyphs")
        DH:InvalidateKnownSpells()
    elseif event == "GLYPH_ADDED" or event == "GLYPH_REMOVED" or event == "GLYPH_UPDATED" then
        DH:MarkStateDirty("glyphs")
        DH:RequestUpdate()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.inCombat = true
        ns.combatStart = GetTime()
        DH:MarkStateDirty("auras")
        -- Prompt 2: start a fight for analytics even outside a boss encounter
        -- (training dummy), unless an encounter already started one.
        if not ns.fight.active then
            DH:StartFight()
        end
        DH:ShowUI()
        DH:SyncUpdateLoop()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.inCombat = false
        DH:MarkStateDirty("auras")
        -- Prompt 2: finalize the fight and (optionally) print the report.
        DH:EndFight()
        if DH.HandleBossCombatEnd then
            DH:HandleBossCombatEnd()
        end
        if not UnitExists("target") then
            DH:HideUI()
        end
        if ns.MaybeShowFeedbackPrompt then
            ns.MaybeShowFeedbackPrompt()
        end
        DH:SyncUpdateLoop()
    elseif event == "PLAYER_LOGOUT" then
        if ns.FeedbackOnLogout then
            ns.FeedbackOnLogout()
        end
    elseif event == "PLAYER_DEAD" then
        ns.playerDead = true
        DH:MarkStateDirty("auras")
        if ns.ClearGlows then
            ns.ClearGlows()
        end
        if ns.HideAllWindows then
            ns.HideAllWindows()
        elseif ns.HideUI then
            ns.HideUI()
        end
        DH:SyncUpdateLoop()
    elseif event == "PLAYER_ALIVE" then
        ns.playerDead = false
        DH:MarkStateDirty("auras")
        DH:RequestUpdate(true)
        DH:SyncUpdateLoop()
    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        DH:OnEncounterStart(encounterID, encounterName)
    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, raidSize, endStatus = ...
        DH:OnEncounterEnd(encounterID, encounterName, difficultyID, raidSize, endStatus)
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" or unit == "target" then
            DH:MarkStateDirty("auras")
            DH:RequestUpdate()
        end
    elseif
        event == "UNIT_MANA"
        or event == "UNIT_RAGE"
        or event == "UNIT_ENERGY"
        or event == "UNIT_FOCUS"
        or event == "UNIT_RUNIC_POWER"
    then
        -- 3.3.5a fires per-resource events (UNIT_POWER is 4.0+)
        local unit = ...
        if unit == "player" then
            DH:MarkStateDirty("resources")
            DH:RequestUpdate()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        DH:MarkStateDirty("cooldowns")
        DH:RequestUpdate()
    elseif
        event == "PLAYER_STATS"
        or event == "COMBAT_RATING_UPDATE"
        or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "UNIT_INVENTORY_CHANGED"
    then
        local unit = ...
        if event ~= "UNIT_INVENTORY_CHANGED" or unit == "player" then
            DH:MarkStateDirty("stats")
            -- phase-3 #1: equipment changes invalidate the cached item level.
            if event == "PLAYER_EQUIPMENT_CHANGED" and DH.State and DH.State.InvalidateItemLevel then
                DH.State:InvalidateItemLevel()
            end
            DH:RequestUpdate()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if DH.HandleBossTarget then
            DH:HandleBossTarget()
        end
        DH:MarkStateDirty("auras")
        DH:MarkStateDirty("cooldowns")
        if DH.State and DH.State.ForceEnemyScan then
            DH.State:ForceEnemyScan()
        end
        DH:RequestUpdate()
        DH:SyncUpdateLoop()
        if UnitExists("target") and UnitCanAttack("player", "target") then
            DH:ShowUI()
        elseif not ns.inCombat then
            DH:HideUI()
        end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        DH:MarkStateDirty("auras")
        DH:RequestUpdate()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        DH:OnCombatLogEvent(...)
    end
end

-- Every event runs through pcall so a single malformed payload cannot abort the
-- handler (and, for ADDON_LOADED, leave the addon half-initialised).
local function OnEvent(self, event, ...)
    local ok, err = pcall(DispatchEvent, self, event, ...)
    if not ok and ns.AddError then
        ns.AddError("Event " .. tostring(event) .. " failed: " .. tostring(err))
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_STATS")
eventFrame:RegisterEvent("COMBAT_RATING_UPDATE")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
