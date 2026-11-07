-- Analytics.lua
-- Analytics, learning and DPS forecast. Split out of RotationCore.lua.

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
-- v3.3.0 PHASE 2/3: ANALYTICS
-- Live DPS forecast, class pulse, exam mode, mentor mode, adaptive rotation
-- and persistent learning statistics. Everything here is additive and gated
-- behind opt-in settings, so existing rotations are unaffected.
-- ============================================================================

ns.dpsForecast = { predicted = 0, actual = 0, loss_pct = 0, lastUpdate = 0 }
ns.pulse = {
    correct = 0,
    total = 0,
    dotSamples = 0,
    dotActive = 0,
    cdSeen = 0,
    cdCast = 0,
    lastTopCd = nil,
    score = 0,
    accuracy = 0,
    dot_uptime = nil,
    cd_usage = nil,
}
ns.exam = { correct = 0, wrong = 0, missed = 0 }
ns.mentorErrors = 0
ns.mentorCorrect = 0

-- ---- DPS FORECAST (Improvement 1) -----------------------------------------

-- Optional per-spell damage data. Classes (or users) may register
-- { [key or spellId] = { min=, max=, coeff=, ap=, cast= } }. Without data the
-- forecast self-calibrates from observed combat-log damage and finally falls
-- back to a stat-based estimate.
ns.spellDamage = ns.spellDamage or {}
function DH:RegisterSpellDamage(map)
    if type(map) ~= "table" then
        return
    end
    for k, v in pairs(map) do
        ns.spellDamage[k] = v
    end
end

function DH:GetSpellDamage(key)
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    return ns.spellDamage[key] or (ab and ab.id and ns.spellDamage[ab.id]) or nil
end

local function AbilityAvgDamage(self, key)
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    local id = ab and ab.id
    -- 1) observed average (self-calibrating once the spell has landed)
    if id then
        local s = ns.skillStats[id]
        if s and s.cast and s.cast > 0 and s.damage and s.damage > 0 then
            return s.damage / s.cast
        end
    end
    local st = self.State
    local sp = (st and st.stat and st.stat.spell_power) or 0
    local ap = (st and st.stat and st.stat.attack_power) or 0
    local crit = (st and st.stat and st.stat.crit) or 0
    -- 2) registered coefficient
    local dmg = self:GetSpellDamage(key)
    if dmg then
        local base = ((dmg.min or 0) + (dmg.max or 0)) / 2
        local scale = dmg.ap and ap or sp
        local hit = base + (dmg.coeff or 0) * scale
        return hit * (1 + crit / 100)
    end
    -- 3) generic stat estimate
    if sp > 0 then
        return (200 + sp * 0.9) * (1 + crit / 100)
    end
    if ap > 0 then
        return (150 + ap * 0.35) * (1 + crit / 100)
    end
    return 0
end

local function AbilityGCD(self, key)
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    local st = self.State
    local haste = (st and st.stat and st.stat.spell_haste) or 1
    if haste <= 0 then
        haste = 1
    end
    local cast = ab and ab.cast
    -- Fall back to the registered damage table's cast time when the ability
    -- table does not carry one.
    if (not cast or cast <= 0) and ns.spellDamage then
        local dmg = ns.spellDamage[key]
        if dmg and dmg.cast then
            cast = dmg.cast
        end
    end
    if cast and cast > 0 then
        return math.max(0.5, cast / haste)
    end
    return 1.5 / haste
end

function ns.UpdateDPSForecast(self, now)
    local interval = tonumber(self:GetSetting("dps_forecast_update_interval")) or 1.0
    if interval < 0.2 then
        interval = 0.2
    end
    now = now or GetTime()
    local d = ns.dpsForecast
    if d.lastUpdate and (now - d.lastUpdate) < interval then
        return
    end
    d.lastUpdate = now

    local recs = ns.recommendations or {}
    local predicted = 0
    if #recs > 0 then
        local count = math.min(#recs, 3)
        local totalDmg, totalTime = 0, 0
        for i = 1, count do
            local w = 1 / i
            totalDmg = totalDmg + AbilityAvgDamage(self, recs[i].ability) * w
            totalTime = totalTime + AbilityGCD(self, recs[i].ability) * w
        end
        if totalTime > 0 then
            predicted = totalDmg / totalTime
        end
    end
    d.predicted = predicted

    local f = ns.fight
    if f and f.active then
        local dur = math.max(0.1, now - (f.startTime or now))
        d.actual = (f.damage or 0) / dur
    else
        d.actual = 0
    end
    d.loss_pct = (predicted > 0) and ((1 - d.actual / predicted) * 100) or 0
end

-- Text for the icon window (nil when disabled or no data).
function ns.GetDPSForecastText(self)
    if not (self.GetSetting and self:GetSetting("dps_forecast_enabled")) then
        return nil
    end
    local d = ns.dpsForecast
    if (d.predicted or 0) <= 0 then
        return nil
    end
    local txt = string.format("~%d DPS", math.floor(d.predicted + 0.5))
    if self:GetSetting("dps_forecast_show_actual") ~= false and (d.actual or 0) > 0 then
        txt = txt .. string.format("   %d (%+d%%)", math.floor(d.actual + 0.5), -math.floor(d.loss_pct + 0.5))
    end
    return txt
end

-- ---- CLASS PULSE (Improvement 2) ------------------------------------------

function ns.SamplePulse(self)
    local p = ns.pulse
    local debuffs = ns.registered.debuffs
    if type(debuffs) ~= "table" or #debuffs == 0 then
        return
    end
    local st = self.State
    local now = (st and st.now) or GetTime()
    local active = false
    if st and st.debuff then
        for i = 1, #debuffs do
            local d = st.debuff[debuffs[i]]
            if d and d.expires and d.expires > now then
                active = true
                break
            end
        end
    end
    p.dotSamples = p.dotSamples + 1
    if active then
        p.dotActive = p.dotActive + 1
    end
end

function ns.IsBigCooldown(self, key)
    if not key then
        return false
    end
    local cfg = ns.lastCdConfig
    local base = cfg and cfg.baseCDs and cfg.baseCDs[key]
    if type(base) == "number" then
        return base >= 60
    end
    local ab = self.Class and self.Class.abilities and self.Class.abilities[key]
    local cd = ab and ab.cooldown
    return (type(cd) == "number" and cd >= 60) or false
end

function ns.UpdatePulse(self)
    local p = ns.pulse
    p.accuracy = (p.total > 0) and (p.correct / p.total * 100) or 0
    p.dot_uptime = (p.dotSamples > 0) and (p.dotActive / p.dotSamples * 100) or nil
    p.cd_usage = (p.cdSeen > 0) and (p.cdCast / p.cdSeen * 100) or nil
    local wsum, vsum = 0.6, 0.6 * p.accuracy
    if p.dot_uptime then
        wsum = wsum + 0.2
        vsum = vsum + 0.2 * p.dot_uptime
    end
    if p.cd_usage then
        wsum = wsum + 0.2
        vsum = vsum + 0.2 * p.cd_usage
    end
    p.score = (wsum > 0) and (vsum / wsum) or 0
end

function ns.PulseColor(score)
    score = score or 0
    if score >= 90 then
        return 0.2, 1.0, 0.2
    end
    if score >= 70 then
        return 1.0, 0.85, 0.1
    end
    return 1.0, 0.25, 0.2
end

-- Returns text + r,g,b for the icon-window indicator (nil when disabled).
function ns.GetPulseInfo(self)
    if not (self.GetSetting and self:GetSetting("class_pulse_enabled")) then
        return nil
    end
    local p = ns.pulse
    if (p.total or 0) == 0 and (p.dotSamples or 0) == 0 then
        return nil
    end
    ns.UpdatePulse(self)
    local r, g, b = ns.PulseColor(p.score)
    local c = ns.GetColorPreset and ns.GetColorPreset(DH:GetSetting("pulse_color"))
    if c then
        r, g, b = c[1], c[2], c[3]
    end
    return string.format("%d%%", math.floor(p.score + 0.5)), r, g, b
end

-- ---- PER-CAST HOOK (exam / mentor / pulse accuracy) -----------------------

function ns.OnPlayerCast(self, castKey, spellId)
    local top = ns.recommendations and ns.recommendations[1]
    local topKey = top and top.ability
    local followed = (topKey ~= nil and castKey ~= nil and topKey == castKey)

    -- Pulse accuracy
    local p = ns.pulse
    if topKey then
        p.total = p.total + 1
        if followed then
            p.correct = p.correct + 1
        end
    end
    -- Pulse cooldown usage
    if ns.IsBigCooldown(self, castKey) then
        p.cdCast = p.cdCast + 1
    end

    -- Exam counters
    if self:GetSetting("exam_mode") then
        if followed then
            ns.exam.correct = ns.exam.correct + 1
        else
            ns.exam.wrong = ns.exam.wrong + 1
        end
    end

    -- Mentor: count consecutive mistakes and explain after the threshold.
    if self:GetSetting("mentor_mode") then
        if followed then
            ns.mentorErrors = 0
            ns.mentorCorrect = ns.mentorCorrect + 1
        else
            ns.mentorErrors = ns.mentorErrors + 1
            ns.mentorCorrect = 0
            local threshold = tonumber(self:GetSetting("mentor_error_threshold")) or 3
            if threshold < 1 then
                threshold = 1
            end
            if ns.mentorErrors >= threshold then
                if ns.MentorExplain then
                    ns.MentorExplain(self, castKey)
                end
                ns.mentorErrors = 0
            end
        end
    end
end

local MENTOR_EXPLAIN = {
    proc_active = "A proc is up - use it now.",
    dot_expiring = "Your DoT is about to fall off - refresh it.",
    execute_phase = "The target is in execute range.",
    cooldown_ready = "A big cooldown is ready.",
}

function ns.MentorExplain(self, castKey)
    local top = ns.recommendations and ns.recommendations[1]
    if not top then
        return
    end
    local rk = top.reason_key
    local why
    if rk and MENTOR_EXPLAIN[rk] then
        why = L(MENTOR_EXPLAIN[rk])
    else
        why = L("Follow the highlighted ability.")
    end
    local classes = self.Class and self.Class.abilities or {}
    local castName = castKey and ((classes[castKey] and classes[castKey].name) or castKey)
    local recName = top.name or (classes[top.ability] and classes[top.ability].name) or top.ability
    local msg = string.format(
        L("You used %s, but %s was recommended. %s"),
        tostring(castName or "?"),
        tostring(recName or "?"),
        why
    )
    if self:GetSetting("mentor_show_in_chat") ~= false then
        self:Print(msg)
    end
end

-- ---- EXAM REPORT + LEARNING STATS (Improvements 3 / phase-3 #2) -----------

local function ExamReport(self)
    if not self:GetSetting("exam_mode") then
        return
    end
    local e = ns.exam
    local total = (e.correct or 0) + (e.wrong or 0)
    local acc = (total > 0) and (e.correct / total * 100) or 0
    if self:GetSetting("exam_report_in_chat") ~= false then
        self:Print(
            string.format(
                L("Exam: %d%% accuracy (%d/%d). Average DPS %d"),
                math.floor(acc + 0.5),
                e.correct or 0,
                total,
                math.floor(((ns.lastFight and ns.lastFight.actual_dps) or 0))
            )
        )
    end
    e.correct, e.wrong, e.missed = 0, 0, 0
end

function ns.RecordLearningSession(self)
    if self:GetSetting("learning_stats_enabled") == false then
        return
    end
    if not self.db then
        return
    end
    if type(self.db.learning_stats) ~= "table" then
        self.db.learning_stats = { sessions = {} }
    end
    local ls = self.db.learning_stats
    if type(ls.sessions) ~= "table" then
        ls.sessions = {}
    end
    local f = ns.lastFight
    if not f then
        return
    end
    local p = ns.pulse
    local acc = (p.total > 0) and (p.correct / p.total * 100) or 0
    local dateStr = tostring(math.floor(GetTime()))
    if os and os.date then
        dateStr = os.date("%Y-%m-%d %H:%M")
    end
    ls.sessions[#ls.sessions + 1] = {
        date = dateStr,
        accuracy = math.floor(acc + 0.5),
        dps = math.floor(f.actual_dps or 0),
        loss = math.floor((f.loss_pct or 0) + 0.5),
        ilvl = (self.GetItemLevel and self:GetItemLevel()) or 0,
        spec = (self.GetActiveSpec and self:GetActiveSpec()) or "?",
    }
    local maxS = tonumber(self:GetSetting("learning_stats_max_sessions")) or 100
    if maxS < 1 then
        maxS = 1
    end
    while #ls.sessions > maxS do
        table.remove(ls.sessions, 1)
    end
end

function DH:PrintLearning()
    local ls = self.db and self.db.learning_stats
    local sessions = ls and ls.sessions or {}
    if #sessions == 0 then
        self:Print(L("No learning sessions recorded."))
        return
    end
    local last = sessions[#sessions]
    local prev = sessions[#sessions - 1]
    self:Print(
        string.format(L("Learning: accuracy %d%%, DPS %d, sessions %d"), last.accuracy or 0, last.dps or 0, #sessions)
    )
    if prev and prev.accuracy then
        self:Print(string.format(L("Improvement: %+d%%"), (last.accuracy or 0) - (prev.accuracy or 0)))
    end
end

function DH:PrintLearningGraph()
    local ls = self.db and self.db.learning_stats
    local sessions = ls and ls.sessions or {}
    if #sessions == 0 then
        self:Print(L("No learning sessions recorded."))
        return
    end
    self:Print(L("Learning accuracy (last sessions):"))
    local start = math.max(1, #sessions - 19)
    for i = start, #sessions do
        local acc = math.max(0, math.min(100, sessions[i].accuracy or 0))
        local bars = math.floor(acc / 5 + 0.5)
        self:Print(string.format("%3d%% | %s", acc, string.rep("#", bars)))
    end
end

function DH:ClearLearning()
    if self.db then
        self.db.learning_stats = { sessions = {} }
    end
    self:Print(L("Learning stats cleared."))
end

-- Fight end: emit the exam report and persist a learning session.
function ns.FinalizeAnalytics(self)
    ExamReport(self)
    ns.RecordLearningSession(self)
end

-- Fight start: reset the per-fight pulse / exam counters.
function ns.ResetAnalytics()
    local p = ns.pulse
    p.correct, p.total = 0, 0
    p.dotSamples, p.dotActive = 0, 0
    p.cdSeen, p.cdCast = 0, 0
    p.score, p.accuracy, p.dot_uptime, p.cd_usage = 0, 0, nil, nil
    p.lastTopCd = nil
    local e = ns.exam
    e.correct, e.wrong, e.missed = 0, 0, 0
end

-- ---- ADAPTIVE ROTATION (phase-3 #1) ---------------------------------------

function DH:GetItemLevel()
    if self.State and self.State.GetItemLevel then
        return self.State:GetItemLevel()
    end
    return 0
end

function DH:GetRotationComplexity()
    local setting = (self.GetSetting and self:GetSetting("adaptive_rotation")) or "auto"
    if setting == "simple" or setting == "normal" or setting == "complex" then
        return setting
    end
    local ilvl = self:GetItemLevel()
    local simpleT = tonumber(self:GetSetting("ilvl_threshold_simple")) or 200
    local complexT = tonumber(self:GetSetting("ilvl_threshold_complex")) or 245
    -- Cache the "auto" result: it only changes when the item level or one of
    -- the thresholds changes (both covered by the signature below), and this
    -- is read once per ability from CanUseCooldown.
    local sig = tostring(ilvl) .. "|" .. tostring(simpleT) .. "|" .. tostring(complexT)
    if ns._complexitySig == sig then
        return ns._complexityRank
    end
    local rank = "normal"
    if ilvl > 0 and ilvl < simpleT then
        rank = "simple"
    elseif ilvl >= complexT then
        rank = "complex"
    end
    ns._complexitySig, ns._complexityRank = sig, rank
    return rank
end

function DH:IsSimpleRotation()
    return self:GetRotationComplexity() == "simple"
end

function DH:IsComplexRotation()
    return self:GetRotationComplexity() == "complex"
end
