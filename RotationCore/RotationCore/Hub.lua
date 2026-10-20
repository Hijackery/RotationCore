-- Hub.lua
-- Coach layer: public API, per-fight analytics, fight breakdown, cooldown plan,
-- Details/Recount DPS, APL import and training lessons. 3.3.5a, no deps.

local DH = RotationCore
if not DH then return end
local ns = DH.ns

local function L(s)
    local t = DH.L
    if t and type(s) == "string" then return t[s] end
    return s
end
local function Get(k) return DH.GetSetting and DH:GetSetting(k) end

-- Accent colour shared with every other window (follows the Theme setting:
-- class / custom / dark / light / contrast).
local function Accent()
    local th = DH.GetUITheme and DH:GetUITheme()
    local a = th and th.accent
    if a then return a[1], a[2], a[3] end
    return 1, 0.82, 0
end

-- ============================================================================
-- PUBLIC API (for WeakAuras / other addons): read recommendations + callbacks
-- ============================================================================

function DH:GetRecommendations()
    return ns.recommendations or {}
end

function DH:SetRecommendationCallback(fn)
    if type(fn) ~= "function" then return end
    ns.recCallbacks = ns.recCallbacks or {}
    ns.recCallbacks[#ns.recCallbacks + 1] = fn
end

local _updateRecs = DH.UpdateRecommendations
if type(_updateRecs) == "function" then
    function DH:UpdateRecommendations()
        local recs = _updateRecs(self)
        if ns.recCallbacks then
            for _, cb in ipairs(ns.recCallbacks) do pcall(cb, recs) end
        end
        return recs
    end
end

-- ============================================================================
-- GRADE
-- ============================================================================

function ns.GetGrade(score)
    score = tonumber(score) or 0
    if score <= 0 then return nil end
    if score >= 95 then return "S", 0.4, 1, 0.4 end
    if score >= 88 then return "A", 0.5, 0.9, 0.4 end
    if score >= 75 then return "B", 1, 0.85, 0.2 end
    if score >= 60 then return "C", 1, 0.6, 0.2 end
    return "D", 1, 0.35, 0.3
end

-- ============================================================================
-- ANALYTICS STORE (persisted to RotationCoreAnalytics)
-- ============================================================================

ns.analytics = ns.analytics or { fights = {} }

local function RecordFight()
    local f = ns.lastFight
    if not f or (f.duration or 0) < 5 then return end
    local a = ns.analytics
    if type(a) ~= "table" then a = {}; ns.analytics = a end
    if type(a.fights) ~= "table" then a.fights = {} end
    local spec = (DH.GetActiveSpec and DH:GetActiveSpec()) or "?"
    local boss = (DH.State and DH.State.encounter_name) or f.bossName or L("Trash")
    local p = ns.pulse or {}
    a.fights[#a.fights + 1] = {
        boss = boss, spec = spec,
        dps = math.floor((f.actual_dps or ((f.damage or 0) / (f.duration or 1))) + 0.5),
        acc = math.floor((p.accuracy or 0) + 0.5),
        up = p.dot_uptime and math.floor(p.dot_uptime + 0.5) or nil,
        dur = math.floor(f.duration or 0),
        date = (date and date("%m-%d %H:%M")) or "?",
    }
    while #a.fights > 200 do table.remove(a.fights, 1) end
    ns.AnalyticsDirty = true
end

if DH.RegisterHook then
    DH:RegisterHook("EndFight", function()
        RecordFight()
        if ns.CheckLessons then ns.CheckLessons() end
    end)
end

local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(_, _, name)
    if name ~= "RotationCore" then return end
    if type(RotationCoreAnalytics) == "table" then
        ns.analytics = RotationCoreAnalytics
        if type(ns.analytics.fights) ~= "table" then ns.analytics.fights = {} end
    else
        ns.analytics = { fights = {} }
    end
    RotationCoreAnalytics = ns.analytics
end)

-- ============================================================================
-- Details / Recount DPS (best-effort, fully guarded)
-- ============================================================================

function ns.GetExternalDPS()
    local g = _G
    if g.Details and g.Details.GetCurrentCombat then
        local ok, v = pcall(function()
            local c = g.Details:GetCurrentCombat()
            if not c then return nil end
            local total = g.Details:GetTotal(c)
            return total and total.dps or (total and total.Dps) or nil
        end)
        if ok and tonumber(v) then return math.floor(tonumber(v)) end
    end
    if g.Recount and g.Recount.GetTotalDPS then
        local ok, v = pcall(function() return g.Recount:GetTotalDPS() end)
        if ok and tonumber(v) then return math.floor(tonumber(v)) end
    end
    if g.Recount and g.Recount.MainWindow and g.Recount.MainWindow.GetValue then
        local ok, v = pcall(function() return g.Recount.MainWindow:GetValue(g.Recount.MainWindow) end)
        if ok and tonumber(v) then return math.floor(tonumber(v)) end
    end
    return nil
end

-- ============================================================================
-- APL import
-- ============================================================================

function ns.ShowAPLImport()
    if not ns.APLImportFrame then
        local f = CreateFrame("Frame", "RotationCoreAPLImport", UIParent)
        f:SetFrameStrata("DIALOG")
        f:SetSize(420, 260)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
        if ns.ApplyWindowChrome then ns.ApplyWindowChrome(f) end
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", f, "TOP", 0, -8)
        f.title:SetText(L("Import APL"))
        f.title:SetTextColor(Accent())
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() f:Hide() end)
        local sb = CreateFrame("ScrollFrame", "RotationCoreAPLScroll", f, "UIPanelScrollFrameTemplate")
        sb:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
        sb:SetSize(376, 180)
        local eb = CreateFrame("EditBox", nil, sb)
        eb:SetMultiLine(true)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetWidth(360)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sb:SetScrollChild(eb)
        f.edit = eb
        local apply = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        apply:SetSize(140, 26)
        apply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
        apply:SetText(L("Import"))
        apply:SetScript("OnClick", function()
            local text = eb:GetText() or ""
            if ns.SetCustomAPL and DH.db then
                local n = ns.SetCustomAPL(DH, text)
                DH:SetSetting("custom_apl_enabled", true)
                DH:Print(string.format(L("APL imported: %d rules."), tonumber(n) or 0))
                if DH.UpdateUI then DH:UpdateUI() end
            end
            f:Hide()
        end)
        ns.APLImportFrame = f
    end
    ns.APLImportFrame:Show()
end

-- ============================================================================
-- LESSONS (basic scenarios evaluated at the end of a fight)
-- ============================================================================

ns.lessons = ns.lessons or {}
local LESSONS = {
    { id = "acc80", text = "Keep rotation accuracy at 80% or higher.", chk = function(p) return (p.accuracy or 0) >= 80 end },
    { id = "acc95", text = "Reach 95% rotation accuracy.", chk = function(p) return (p.accuracy or 0) >= 95 end },
    { id = "dot",   text = "Keep DoT uptime at 90% or higher.", chk = function(p) return (p.dot_uptime or 0) >= 90 end },
    { id = "cd",    text = "Use your major cooldowns (CD usage 80%+).", chk = function(p) return (p.cd_usage or 0) >= 80 end },
}
function ns.CheckLessons()
    local p = ns.pulse or {}
    for _, l in ipairs(LESSONS) do
        if not ns.lessons[l.id] and l.chk(p) then
            ns.lessons[l.id] = true
            if DH.Print then DH:Print(L("Lesson complete: ") .. L(l.text)) end
        end
    end
end
function ns.GetLessons() return LESSONS end

-- ============================================================================
-- HUB WINDOW
-- ============================================================================

local hub
local function EnsureHub()
    if hub then return hub end
    local f = CreateFrame("Frame", "RotationCoreHub", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetSize(360, 480)
    f:SetPoint("CENTER", UIParent, "CENTER", 380, 0)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    if ns.ApplyWindowChrome then ns.ApplyWindowChrome(f) end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -8)
    f.title:SetText(L("Coach hub"))
    f.title:SetTextColor(Accent())
    if ns.ApplyFont then ns.ApplyFont(f.title) end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
    body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -30)
    body:SetJustifyH("LEFT")
    body:SetSpacing(2)
    f.body = body

    local function mkBtn(text, x, w, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(w, 26)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 10)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    mkBtn(L("Fight breakdown"), 10, 110, function() ns.ShowFightBreakdown() end)
    mkBtn(L("Import APL"), 126, 90, function() ns.ShowAPLImport() end)
    mkBtn(L("Clear history"), 222, 110, function()
        ns.analytics = { fights = {} }
        RotationCoreAnalytics = ns.analytics
        DH:Print(L("History cleared."))
    end)

    f:SetScript("OnShow", function() f._t = 0 end)
    f:SetScript("OnUpdate", function(self, dt)
        self._t = (self._t or 0) + dt
        if self._t < 0.5 then return end
        self._t = 0
        ns.RefreshHub()
    end)
    hub = f
    return f
end

function ns.RefreshHub()
    if not hub or not hub:IsShown() then return end
    local lines = {}
    local p = ns.pulse or {}
    local spec = (DH.GetActiveSpec and DH:GetActiveSpec()) or "?"
    local mode = DH.db and DH.db.mode or "?"

    local grade = ns.GetGrade(p.score)
    lines[#lines + 1] = "|cFFFFD100" .. L("Status") .. "|r"
    lines[#lines + 1] = L("Spec: ") .. tostring(spec) .. "   " .. L("Rotation: ") .. tostring(mode)
    if grade then
        lines[#lines + 1] = L("Grade: ") .. "|cFF33FF33" .. grade .. "|r   " ..
            L("Score: ") .. string.format("%d", math.floor((p.score or 0) + 0.5))
    else
        lines[#lines + 1] = L("Grade: ") .. "-"
    end
    lines[#lines + 1] = string.format(L("Rotation accuracy: %d%%"), math.floor((p.accuracy or 0) + 0.5))
    if p.dot_uptime then lines[#lines + 1] = string.format(L("DoT uptime: %d%%"), math.floor(p.dot_uptime + 0.5)) end
    if p.cd_usage then lines[#lines + 1] = string.format(L("CD usage: %d%%"), math.floor(p.cd_usage + 0.5)) end
    local ext = ns.GetExternalDPS()
    if ext then lines[#lines + 1] = L("DPS (Details/Recount): ") .. tostring(ext) end
    if ns.lastFight then lines[#lines + 1] = L("Last fight DPS: ") .. tostring(math.floor(ns.lastFight.actual_dps or 0)) end

    -- Cooldown plan from the boss timeline.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cFFFFD100" .. L("Cooldown plan") .. "|r"
    local tl = ns.GetBossTimeline and ns.GetBossTimeline()
    if tl and tl.timers and #tl.timers > 0 then
        local now = GetTime()
        local upcoming = {}
        for _, t in ipairs(tl.timers) do
            if t.expires and t.expires > now then upcoming[#upcoming + 1] = t end
        end
        table.sort(upcoming, function(a, b) return a.expires < b.expires end)
        for i = 1, math.min(5, #upcoming) do
            local t = upcoming[i]
            lines[#lines + 1] = string.format("  %s  %ds", tostring(t.text or "?"), math.max(0, math.floor(t.expires - now + 0.5)))
        end
        if #upcoming > 0 then lines[#lines + 1] = "  " .. L("Hold big cooldowns for the burst window.") end
    else
        lines[#lines + 1] = "  " .. L("No boss timers right now.")
    end

    -- History (recent fights).
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cFFFFD100" .. L("History") .. "|r"
    local fights = (type(ns.analytics) == "table" and type(ns.analytics.fights) == "table") and ns.analytics.fights or {}
    if #fights == 0 then
        lines[#lines + 1] = "  " .. L("No fights recorded yet.")
    else
        for i = math.max(1, #fights - 4), #fights do
            local r = fights[i]
            if type(r) == "table" then
                lines[#lines + 1] = string.format("  %s %s  %d dps  %d%%", tostring(r.boss or "?"), tostring(r.spec or ""), r.dps or 0, r.acc or 0)
            end
        end
    end

    -- Lessons.
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cFFFFD100" .. L("Lessons") .. "|r"
    for _, l in ipairs(ns.GetLessons()) do
        lines[#lines + 1] = (ns.lessons[l.id] and "  |cFF33FF33[x]|r " or "  [ ] ") .. L(l.text)
    end

    hub.body:SetText(table.concat(lines, "\n"))
end

function ns.ShowHub()
    EnsureHub():Show()
    ns.RefreshHub()
end

-- ============================================================================
-- FIGHT BREAKDOWN (coach window for the last fight)
-- ============================================================================

function ns.ShowFightBreakdown()
    local f = ns.lastFight
    if not f then DH:Print(L("No fight recorded yet.")) return end
    local p = ns.pulse or {}
    local lines = {}
    lines[#lines + 1] = L("Spec: ") .. tostring((DH.GetActiveSpec and DH:GetActiveSpec()) or "?")
    lines[#lines + 1] = string.format(L("Duration: %.0f s"), f.duration or 0)
    lines[#lines + 1] = string.format(L("Damage: %s"), tostring(math.floor(f.damage or 0)))
    lines[#lines + 1] = string.format(L("DPS: %.0f"), f.actual_dps or 0)
    lines[#lines + 1] = string.format(L("Rotation accuracy: %d%%"), math.floor((p.accuracy or 0) + 0.5))
    if p.dot_uptime then lines[#lines + 1] = string.format(L("DoT uptime: %d%%"), math.floor(p.dot_uptime + 0.5)) end
    if p.cd_usage then lines[#lines + 1] = string.format(L("CD usage: %d%%"), math.floor(p.cd_usage + 0.5)) end
    local grade = ns.GetGrade(p.score)
    if grade then lines[#lines + 1] = L("Grade: ") .. grade end
    local misses = {}
    for _, s in pairs(ns.skillStats or {}) do
        if (s.missed or 0) > 0 then misses[#misses + 1] = s end
    end
    table.sort(misses, function(a, b) return (a.missed or 0) > (b.missed or 0) end)
    if #misses > 0 then
        lines[#lines + 1] = L("Top misses:")
        for i = 1, math.min(5, #misses) do
            lines[#lines + 1] = string.format("  %s x%d", tostring(misses[i].name or "?"), misses[i].missed or 0)
        end
    end

    if not ns.BreakdownFrame then
        local bf = CreateFrame("Frame", "RotationCoreBreakdown", UIParent)
        bf:SetFrameStrata("DIALOG")
        bf:SetSize(320, 300)
        bf:SetPoint("CENTER", UIParent, "CENTER", -420, 0)
        bf:EnableMouse(true)
        bf:SetMovable(true)
        bf:RegisterForDrag("LeftButton")
        bf:SetScript("OnDragStart", function(s) s:StartMoving() end)
        bf:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
        if ns.ApplyWindowChrome then ns.ApplyWindowChrome(bf) end
        bf.title = bf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bf.title:SetPoint("TOP", bf, "TOP", 0, -8)
        bf.title:SetText(L("Fight breakdown"))
        bf.title:SetTextColor(Accent())
        local close = CreateFrame("Button", nil, bf, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() bf:Hide() end)
        bf.body = bf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bf.body:SetPoint("TOPLEFT", bf, "TOPLEFT", 12, -30)
        bf.body:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -12, -30)
        bf.body:SetJustifyH("LEFT")
        ns.BreakdownFrame = bf
    end
    ns.BreakdownFrame.body:SetText(table.concat(lines, "\n"))
    ns.BreakdownFrame:Show()
end

-- ============================================================================
-- SLASH + OPTIONS hook
-- ============================================================================

DH:RegisterSlashCommand("hub", function()
    ns.ShowHub()
end, "hub - coach / analytics window")

DH:RegisterSlashCommand("analyze", function()
    ns.ShowFightBreakdown()
end, "analyze - fight breakdown of the last fight")

-- ============================================================================
-- ROTATION SIMULATOR (light): DPS estimate + upcoming cast sequence
-- ============================================================================

local function SimpleWindow(name, title, w, h, x, y)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetSize(w, h)
    f:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 0)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    if ns.ApplyWindowChrome then ns.ApplyWindowChrome(f) end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f, "TOP", 0, -8)
    f.title:SetText(L(title))
    f.title:SetTextColor(Accent())
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() f:Hide() end)
    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
    f.body:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -30)
    f.body:SetJustifyH("LEFT")
    return f
end

ns._simWindow = ns._simWindow or 8

function ns.RefreshSimulator()
    local f = ns.SimFrame
    if not f or not f:IsShown() then return end
    local lines = {}
    local pred = ns.GetDPSForecastText and ns.GetDPSForecastText(DH)
    lines[#lines + 1] = L("DPS forecast: ") .. (pred and tostring(pred) or "-")
    if ns.lastFight then lines[#lines + 1] = string.format(L("Last fight DPS: %d"), math.floor(ns.lastFight.actual_dps or 0)) end
    local ext = ns.GetExternalDPS()
    if ext then lines[#lines + 1] = L("DPS (Details/Recount): ") .. tostring(ext) end
    local enemies = (DH.State and DH.State.active_enemies) or 1
    local profile = (DH.GetSetting and DH:GetSetting("activity_profile")) or "?"
    lines[#lines + 1] = L("Targets: ") .. tostring(enemies) .. "   " .. L("Activity: ") .. tostring(profile)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cFFFFD100" .. L("Next casts") .. " (" .. tostring(ns._simWindow) .. L("s)") .. "|r"
    if DH.ForecastNext then
        local ok, seq = pcall(DH.ForecastNext, DH, ns._simWindow)
        if ok and type(seq) == "table" and #seq > 0 then
            for i = 1, math.min(10, #seq) do lines[#lines + 1] = "  " .. i .. ". " .. tostring(seq[i]) end
        else
            lines[#lines + 1] = "  " .. L("No forecast available.")
        end
    end
    f.body:SetText(table.concat(lines, "\n"))
end

function ns.ShowSimulator()
    if not ns.SimFrame then
        local f = SimpleWindow("RotationCoreSim", "Rotation simulator", 300, 320, -420, 0)
        local function winBtn(text, x, delta)
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(48, 20)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 8)
            b:SetText(text)
            b:SetScript("OnClick", function()
                ns._simWindow = math.max(3, math.min(60, ns._simWindow + delta))
                ns.RefreshSimulator()
            end)
        end
        winBtn("-5", 12, -5); winBtn("+5", 66, 5); winBtn("+10", 120, 10)
        f:SetScript("OnShow", function() f._t = 0 end)
        f:SetScript("OnUpdate", function(self, dt)
            self._t = (self._t or 0) + dt
            if self._t < 1 then return end
            self._t = 0
            ns.RefreshSimulator()
        end)
        ns.SimFrame = f
    end
    ns.SimFrame:Show()
    ns.RefreshSimulator()
end

-- ============================================================================
-- APL EDITOR (list-based): move / delete / add rules, then save
-- ============================================================================

local function AplLines()
    local src = (DH.GetSetting and DH:GetSetting("custom_apl_source")) or ""
    local out = {}
    for l in (src .. "\n"):gmatch("(.-)\n") do
        local t = l:gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" then out[#out + 1] = t end
    end
    return out
end

function ns.RefreshAPLEditor()
    local f = ns.APLEditorFrame
    if not f then return end
    for _, r in ipairs(f.rows) do r:Hide() end
    local lines = AplLines()
    f._lines = lines
    local y = -6
    for i = 1, math.min(#lines, 14) do
        local r = f.rows[i]
        if not r then
            r = CreateFrame("Frame", nil, f.scrollChild)
            r:SetSize(360, 18)
            r.fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.fs:SetPoint("LEFT", r, "LEFT", 2, 0)
            r.fs:SetWidth(210); r.fs:SetJustifyH("LEFT")
            local function btn(txt, x, onClick)
                local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
                b:SetSize(30, 16); b:SetPoint("LEFT", r, "LEFT", x, 0); b:SetText(txt)
                b:SetScript("OnClick", onClick); return b
            end
            r.up = btn("^", 216, function() ns._aplMove(i, -1) end)
            r.dn = btn("v", 250, function() ns._aplMove(i, 1) end)
            r.del = btn("x", 284, function() ns._aplDelete(i) end)
            f.rows[i] = r
        end
        r.fs:SetText(i .. ". " .. lines[i])
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", f.scrollChild, "TOPLEFT", 0, y)
        r:Show()
        y = y - 20
    end
    f.scrollChild:SetHeight(math.max(20, #lines * 20 + 20))
end

local function AplSave()
    local f = ns.APLEditorFrame
    local src = table.concat(f._lines or {}, "\n")
    if ns.SetCustomAPL then
        ns.SetCustomAPL(DH, src)
        DH:SetSetting("custom_apl_enabled", #(f._lines or {}) > 0)
        DH:Print(L("APL saved."))
        if DH.UpdateUI then DH:UpdateUI() end
    end
end

function ns._aplDelete(i)
    local f = ns.APLEditorFrame; if not f then return end
    table.remove(f._lines, i); AplSave(); ns.RefreshAPLEditor()
end
function ns._aplMove(i, d)
    local f = ns.APLEditorFrame; if not f then return end
    local j = i + d
    if j < 1 or j > #f._lines then return end
    f._lines[i], f._lines[j] = f._lines[j], f._lines[i]
    AplSave(); ns.RefreshAPLEditor()
end

function ns.ShowAPLEditor()
    if not ns.APLEditorFrame then
        local f = SimpleWindow("RotationCoreAPLEditor", "Rotation editor (APL)", 380, 340, -420, 0)
        local sf = CreateFrame("ScrollFrame", "RotationCoreAPLEditScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
        sf:SetSize(356, 240)
        local child = CreateFrame("Frame", nil, sf)
        child:SetSize(340, 20)
        sf:SetScrollChild(child)
        f.scrollChild = child
        f.rows = {}
        local eb = CreateFrame("EditBox", nil, f)
        eb:SetSize(240, 20)
        eb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 34)
        eb:SetAutoFocus(false)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetTextInsets(4, 4, 0, 0)
        f.add = eb
        local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        addBtn:SetSize(60, 20); addBtn:SetPoint("LEFT", eb, "RIGHT", 6, 0); addBtn:SetText(L("Add"))
        addBtn:SetScript("OnClick", function()
            local t = eb:GetText() or ""
            t = t:gsub("^%s+", ""):gsub("%s+$", "")
            if t ~= "" then
                local lines = AplLines(); lines[#lines + 1] = t
                ns.SetCustomAPL(DH, table.concat(lines, "\n"))
                eb:SetText(""); ns.RefreshAPLEditor()
            end
        end)
        ns.APLEditorFrame = f
    end
    ns.APLEditorFrame:Show()
    ns.RefreshAPLEditor()
end

-- ============================================================================
-- TALENT / GLYPH CHECK
-- ============================================================================

function ns.ShowTalentCheck()
    local lines = {}
    lines[#lines + 1] = L("Spec: ") .. tostring((DH.GetActiveSpec and DH:GetActiveSpec()) or "?")
    lines[#lines + 1] = L("Rotation: ") .. tostring((DH.db and DH.db.mode) or "?")
    local classes = DH.Class and DH.Class.abilities or {}
    local baseCDs = (ns.lastCdConfig and ns.lastCdConfig.baseCDs) or {}
    local unknown = {}
    for k in pairs(baseCDs) do
        local ab = classes[k]
        if ab and ab.id and DH.IsAbilityKnown and not DH:IsAbilityKnown(k) then
            unknown[#unknown + 1] = tostring(ab.name or k)
        end
    end
    table.sort(unknown)
    lines[#lines + 1] = ""
    if #unknown == 0 then
        lines[#lines + 1] = L("All key rotation abilities are known.")
    else
        lines[#lines + 1] = L("Not learned (consider these talents):")
        for i = 1, math.min(12, #unknown) do lines[#lines + 1] = "  - " .. unknown[i] end
    end
    if not ns.TalentFrame then
        ns.TalentFrame = SimpleWindow("RotationCoreTalents", "Talent check", 300, 300, -420, 0)
    end
    ns.TalentFrame.body:SetText(table.concat(lines, "\n"))
    ns.TalentFrame:Show()
end

DH:RegisterSlashCommand("sim", function() ns.ShowSimulator() end, "sim - rotation simulator / forecast")
DH:RegisterSlashCommand("apl", function(cmd)
    if cmd and cmd:match("apl%s+edit") then ns.ShowAPLEditor() else ns.ShowAPLImport() end
end, "apl [edit] - APL import / editor")
DH:RegisterSlashCommand("talents", function() ns.ShowTalentCheck() end, "talents - talent check")
