-- BossTimeline.lua
-- Boss timeline. Split out of RotationCore.lua.

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
-- PROMPT 3.3: BOSS TIMELINE (DBM / BigWigs, optional, safe without them)
-- Collects boss cast/aura events and DBM/BigWigs timer callbacks into
-- State.boss_timeline, then exposes a short "Hold CD / Prepare / BURST" hint
-- for the icon window. Everything is pcall-guarded: no DBM or BigWigs simply
-- means no hints, never an error.
-- ============================================================================

-- Words that mark a boss timer as "a burst window is about to open".
local TIMELINE_BURST_WORDS = {
    "burst",
    "bloodlust",
    "heroism",
    "time warp",
    "avatar",
    "wings",
    "trinket",
    "potion",
    "berserk",
    "empower",
}

local function TimelineMatchesBurst(text)
    if type(text) ~= "string" or text == "" then
        return false
    end
    text = text:lower()
    for i = 1, #TIMELINE_BURST_WORDS do
        if text:find(TIMELINE_BURST_WORDS[i], 1, true) then
            return true
        end
    end
    return false
end

function ns.GetBossTimeline()
    local st = DH.State
    if not st then
        return nil
    end
    if not st.boss_timeline then
        st.boss_timeline = {
            timers = {},
            next_burst = nil,
            burst_active = false,
            events = {},
            phase = 1,
        }
    end
    return st.boss_timeline
end

-- Improvement 5: boss phase tracking (phase 1 = default). A phase is detected
-- from DBM/BigWigs text such as "Phase 2" or from a boss aura/cast name that
-- contains it. Phase overrides are optional and never fire unless the user
-- enables timeline_auto_phase.
function ns.SetTimelinePhase(phase)
    phase = tonumber(phase)
    if not phase or phase < 1 or phase > 5 then
        return
    end
    local tl = ns.GetBossTimeline()
    if not tl or tl.phase == phase then
        return
    end
    tl.phase = phase
    tl.phase_changed_at = GetTime()
    if DH.GetSetting and DH:GetSetting("timeline_auto_phase") then
        if DH.UpdateRecommendations then
            DH:UpdateRecommendations()
        end
    end
end

function ns.GetTimelinePhase()
    local tl = ns.GetBossTimeline()
    return tl and tl.phase or 1
end

-- Phase -> target mode used by ResolveTargetMode when timeline_auto_phase is on.
-- Phase 2 opens multi-target; phase 3 tightens back to single for execute.
function ns.GetPhaseTargetMode()
    local tl = ns.GetBossTimeline()
    if not tl then
        return nil
    end
    if tl.phase >= 3 then
        return "single"
    end
    if tl.phase == 2 then
        return "aoe"
    end
    return nil
end

-- True while the auto-phase system considers the fight to be in an execute
-- phase. Rotations may read this via DH:IsExecutePhase().
function DH:IsExecutePhase()
    if not (self.GetSetting and self:GetSetting("timeline_auto_phase")) then
        return false
    end
    return ns.GetTimelinePhase() >= 3
end

-- Detect a phase number in free text ("Phase 2", "Phase Two", "P3", "фаза 2").
local PHASE_WORDS = {
    ["one"] = 1,
    ["two"] = 2,
    ["three"] = 3,
    ["four"] = 4,
    ["five"] = 5,
    ["первая"] = 1,
    ["вторая"] = 2,
    ["третья"] = 3,
    ["четвёртая"] = 4,
    ["четвертая"] = 4,
    ["пятая"] = 5,
}
local function PhaseFromText(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local lower = text:lower()
    -- "phase 3", "фаза 2", "p2"
    local n = lower:match("phase%s*(%d)") or lower:match("фаза%s*(%d)") or lower:match("^%s*p(%d)")
    if n then
        return tonumber(n)
    end
    -- "phase two" / "вторая фаза"
    for word, num in pairs(PHASE_WORDS) do
        if lower:find(word, 1, true) then
            return num
        end
    end
    return nil
end

-- Record a timed event ("something in N seconds").
function ns.AddBossTimer(text, seconds, source)
    if type(seconds) ~= "number" or seconds <= 0 then
        return
    end
    local tl = ns.GetBossTimeline()
    if not tl then
        return
    end
    tl.timers[#tl.timers + 1] = {
        text = text,
        expires = GetTime() + seconds,
        duration = seconds,
        burst = TimelineMatchesBurst(text),
        source = source,
    }
    local p = PhaseFromText(text)
    if p then
        ns.SetTimelinePhase(p)
    end
end

function ns.AddBossEvent(eventType, destName)
    local tl = ns.GetBossTimeline()
    if not tl then
        return
    end
    tl.events[#tl.events + 1] = { event = eventType, name = destName, time = GetTime() }
    if #tl.events > 25 then
        table.remove(tl.events, 1)
    end
    local p = PhaseFromText(destName)
    if p then
        ns.SetTimelinePhase(p)
    end
end

-- Deep timeline: raw phase messages captured from DBM/BigWigs and boss casts.
ns.timelinePhaseEvents = ns.timelinePhaseEvents or {}
function ns.RecordPhaseEvent(text)
    if type(text) ~= "string" or text == "" then
        return
    end
    if not (DH.GetSetting and DH:GetSetting("timeline_deep_enabled")) then
        return
    end
    ns.timelinePhaseEvents[#ns.timelinePhaseEvents + 1] = { t = GetTime(), msg = text }
    if #ns.timelinePhaseEvents > 64 then
        table.remove(ns.timelinePhaseEvents, 1)
    end
    local p = PhaseFromText(text)
    if p and DH.GetSetting and DH:GetSetting("timeline_phase_auto") then
        ns.SetTimelinePhase(p)
    end
end

-- Newest deep-timeline message, if it is still fresh (used by the icon window).
function ns.GetLatestPhaseText(maxAge)
    if not (DH.GetSetting and DH:GetSetting("timeline_deep_enabled")) then
        return nil
    end
    local n = #ns.timelinePhaseEvents
    if n == 0 then
        return nil
    end
    local e = ns.timelinePhaseEvents[n]
    if not e or not e.t then
        return nil
    end
    if (GetTime() - e.t) > (maxAge or 8) then
        return nil
    end
    return e.msg
end

-- Prune expired timers and find the soonest classified burst timer.
local function UpdateBossTimeline()
    local tl = ns.GetBossTimeline()
    if not tl then
        return nil
    end
    local now = GetTime()
    for i = #tl.timers, 1, -1 do
        if tl.timers[i].expires <= now then
            table.remove(tl.timers, i)
        end
    end
    local nextBurst
    for i = 1, #tl.timers do
        local t = tl.timers[i]
        if t.burst and (not nextBurst or t.expires < nextBurst.expires) then
            nextBurst = t
        end
    end
    tl.next_burst = nextBurst and (nextBurst.expires - now) or nil
    return tl
end

-- Returns label, countdown text. Rules from the spec:
--   burst active (<= 2s)         -> "BURST"
--   burst within burst_window    -> "Hold CD"
--   burst within 2*burst_window  -> "Prepare"
--   otherwise                    -> nil
function ns.GetTimelineHint()
    -- timeline_show_burst = false hides only the burst countdown text.
    if DH.GetSetting and DH:GetSetting("timeline_show_burst") == false then
        return nil, nil
    end
    local tl = UpdateBossTimeline()
    if not tl or not tl.next_burst then
        return nil, nil
    end
    local secs = tl.next_burst
    local window = tonumber(DH.GetSetting and DH:GetSetting("timeline_burst_window")) or 15
    if window < 5 then
        window = 5
    end
    local detail = ("Burst in %ds"):format(math.max(0, math.floor(secs + 0.5)))
    if secs <= 2 then
        return (DH.L and DH.L["BURST"]) or "BURST", detail
    elseif secs < window then
        return (DH.L and DH.L["Hold CD"]) or "Hold CD", detail
    elseif secs <= window * 2 then
        return (DH.L and DH.L["Prepare"]) or "Prepare", detail
    end
    return nil, nil
end

-- Best-effort integration with DBM and BigWigs. Both APIs are optional and
-- differ between versions, so every registration is pcall-protected and the
-- callbacks accept any argument shape.
function ns.InitTimeline()
    local CBH = _G.LibStub and _G.LibStub("CallbackHandler-1.0", true)

    -- DBM (Deadly Boss Mods): its object is a CallbackHandler target. Boss mods
    -- may load after us, so registration is retried (InitTimeline runs again on
    -- ADDON_LOADED and on encounter start); each source is hooked only once.
    local dbm = _G.DBM or _G.DBMAPI
    if dbm and dbm.RegisterCallback and not ns._dbmHooked then
        ns._dbmHooked = true
        pcall(function()
            dbm:RegisterCallback("DBM_TimerStart", function(_, id, msg, timer)
                ns.AddBossTimer(msg, tonumber(timer), "DBM")
            end)
        end)
        pcall(function()
            dbm:RegisterCallback("DBM_Announce", function(_, msg)
                ns.AddBossEvent("announce", msg)
                ns.RecordPhaseEvent(msg)
                if TimelineMatchesBurst(msg) then
                    ns.AddBossTimer(msg, 0.1, "DBM")
                end
            end)
        end)
    end

    -- BigWigs: messages via BigWigsLoader or a shared CallbackHandler.
    local bw = _G.BigWigsLoader or _G.BigWigs
    if bw and not ns._bwHooked then
        if bw.RegisterMessage then
            ns._bwHooked = true
            pcall(function()
                bw.RegisterMessage(bw, "BigWigs_StartBar", function(_, _, text, duration)
                    ns.AddBossTimer(text, tonumber(duration), "BigWigs")
                    ns.RecordPhaseEvent(text)
                end)
            end)
            pcall(function()
                bw.RegisterMessage(bw, "BigWigs_Message", function(_, _, text)
                    ns.RecordPhaseEvent(text)
                end)
            end)
        elseif CBH then
            ns._bwHooked = true
            pcall(function()
                CBH:RegisterCallback("BigWigs_StartBar", function(_, _, _, text, duration)
                    ns.AddBossTimer(text, tonumber(duration), "BigWigs")
                    ns.RecordPhaseEvent(text)
                end, bw)
            end)
        end
    end

    -- Boss cast / debuff tracking (works without DBM/BigWigs). Register once.
    if not ns._timelineEventsReg then
        ns._timelineEventsReg = true
        local f = ns._timelineFrame or CreateFrame("Frame")
        ns._timelineFrame = f
        f:RegisterEvent("SPELL_CAST_START")
        f:RegisterEvent("SPELL_AURA_APPLIED")
        f:SetScript("OnEvent", function(_, event, unit, spellName)
            if event == "SPELL_CAST_START" then
                local name = (type(spellName) == "string" and spellName) or (type(unit) == "string" and unit) or nil
                ns.AddBossEvent("cast", name)
            elseif event == "SPELL_AURA_APPLIED" then
                ns.AddBossEvent("aura", spellName)
            end
        end)
    end
end
