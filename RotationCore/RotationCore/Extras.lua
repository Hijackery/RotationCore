-- Extras.lua
-- Optional helpers: DoT/debuff panel, swing timer, resource-cap warnings,
-- enemy counter, racial cooldowns and the end-of-fight session report.
-- 3.3.5a only, no dependencies.

local DH = RotationCore
if not DH then return end

local ns = DH.ns

local function L(s)
    local tbl = DH.L
    if tbl and type(s) == "string" then return tbl[s] end
    return s
end
local function Get(k) return DH.GetSetting and DH:GetSetting(k) end

-- Key-binding names (shown in Key Bindings > RotationCore). The actions live
-- in Bindings.xml.
BINDING_HEADER_ROTATIONCORE = "RotationCore"
BINDING_NAME_ROTATIONCORE_OPTIONS = L("Open settings")
BINDING_NAME_ROTATIONCORE_PANELCONFIG = L("Panel configuration")

-- ============================================================================
-- RACIAL COOLDOWNS
-- ============================================================================

local RACIAL_CDS = {
    Orc        = { 33697, 20572 },  -- Blood Fury (spell power / attack power)
    Troll      = { 26297 },         -- Berserking
    BloodElf   = { 25046 },         -- Arcane Torrent
    Undead     = { 7744 },          -- Will of the Forsaken
    Tauren     = { 20549 },         -- War Stomp
    Draenei    = { 28880 },         -- Gift of the Naaru
    Dwarf      = { 20594 },         -- Stoneform
    Gnome      = { 4511 },          -- Escape Artist
    NightElf   = { 58984 },         -- Shadowmeld
}

function ns.GetRacialCooldownIds()
    local race = DH.playerRace
    if not race then return {} end
    local list = RACIAL_CDS[race]
    if not list then return {} end
    local out = {}
    for _, id in ipairs(list) do
        if GetSpellInfo(id) then out[#out + 1] = id end
    end
    return out
end

-- ============================================================================
-- Generic movable window helpers
-- ============================================================================

local function ApplyPos(f)
    local p = DH:GetSetting(f.posKey)
    f:ClearAllPoints()
    if type(p) == "table" and p.x and p.y then
        f:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", f.defX or 0, f.defY or 0)
    end
end

local function SavePos(f)
    local p = DH:GetSetting(f.posKey)
    if type(p) ~= "table" then return end
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if cx and ux and cy and uy then
        p.x = cx - ux
        p.y = cy - uy
        if DH.SetSetting then DH:SetSetting("display_layout", "custom") end
    end
end

local function MakeWindow(name, title, posKey, defX, defY, scaleKey)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f.posKey, f.defX, f.defY, f.scaleKey = posKey, defX, defY, scaleKey
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.configMode and ns.SnapToGrid then ns.SnapToGrid(self) end
        SavePos(self)
    end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOP", f, "TOP", 0, -5)
    f.title:SetText(L(title))
    if ns.ApplyWindowChrome then ns.ApplyWindowChrome(f) end
    if ns.ApplyFont then ns.ApplyFont(f.title) end
    ApplyPos(f)
    return f
end

-- ============================================================================
-- DoT / debuff panel (your own debuffs on the target)
-- ============================================================================

local dotFrame
local DOT_ROWS = 8

-- Key DoTs per class (3.3.5a) so the panel can mark the important ones.
local CLASS_DOT_IDS = {
    MAGE = { 44457, 12654, 55360 },
    WARLOCK = { 47813, 47864, 47843, 47811, 59164, 48181 },
    PRIEST = { 48125, 48160, 48300 },
    DRUID = { 48463, 48465, 5570, 49800, 48574, 48568 },
    ROGUE = { 48672, 48676, 57970 },
    WARRIOR = { 47465, 12721 },
    DEATHKNIGHT = { 55078, 55095 },
    SHAMAN = { 49233, 25457 },
    HUNTER = { 49001, 63672, 27016 },
    PALADIN = { 31803 },
}
local dotNames
local function ClassDotNames()
    if dotNames then return dotNames end
    dotNames = {}
    local list = CLASS_DOT_IDS[DH.playerClass]
    if list then
        for _, id in ipairs(list) do
            local nm = GetSpellInfo(id)
            if nm then dotNames[nm] = true end
        end
    end
    return dotNames
end

function ns.UpdateDotFrame()
    if ns.playerDead then
        if dotFrame then dotFrame:Hide() end
        return
    end
    local show = Get("dot_panel_enabled") == true
    if not (DH.db and DH.db.enabled and show) then
        if dotFrame then if ns.FadeHide then ns.FadeHide(dotFrame) else dotFrame:Hide() end end
        return
    end
    if not dotFrame then
        dotFrame = MakeWindow("RotationCoreDotPanel", "DoTs", "dot_panel_position", 250, 80, "dot_panel_scale")
        dotFrame.rows = {}
        for i = 1, DOT_ROWS do
            local fs = dotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", dotFrame, "TOPLEFT", 10, -22 - (i - 1) * 15)
            fs:SetJustifyH("LEFT")
            fs:SetWidth(180)
            dotFrame.rows[i] = fs
        end
    end
    local f = dotFrame
    local names = ClassDotNames()
    local list = {}
    if UnitExists("target") then
        for i = 1, 40 do
            local name, _, _, count, _, dur, exp, caster = UnitDebuff("target", i)
            if not name then break end
            if caster == "player" and dur and dur > 0 then
                list[#list + 1] = { name = name, exp = exp, dur = dur, count = count, key = names[name] }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.key ~= b.key then return a.key end
        return (a.exp or 0) < (b.exp or 0)
    end)
    local now = GetTime()
    local n = math.min(#list, DOT_ROWS)
    for i = 1, DOT_ROWS do
        local fs = f.rows[i]
        local it = list[i]
        if it then
            local rem = math.max(0, (it.exp or now) - now)
            local tag = (it.count and it.count > 1) and (" x" .. it.count) or ""
            local star = it.key and "* " or ""
            fs:SetText(string.format("%s%s  %.1fs%s", star, tostring(it.name), rem, tag))
            if rem < 3 then
                fs:SetTextColor(1, 0.3, 0.3)
            elseif it.key then
                fs:SetTextColor(1, 0.82, 0)
            else
                fs:SetTextColor(0.85, 0.85, 0.85)
            end
            fs:Show()
        else
            fs:SetText("")
            fs:Hide()
        end
    end
    if n == 0 then
        f.rows[1]:SetText(L("No DoTs on the target."))
        f.rows[1]:SetTextColor(0.6, 0.6, 0.6)
        f.rows[1]:Show()
        n = 1
    end
    if not f.isMoving then
        f:SetSize(200, 24 + n * 15 + 4)
    end
    if ns.FadeShow then ns.FadeShow(f) else f:Show() end
end

-- ============================================================================
-- Swing timer (melee auto-attack)
-- ============================================================================

local swingFrame, swingStart, swingShow
local function SwingMain()
    if type(UnitAttackSpeed) ~= "function" then return 0 end
    local main = select(1, UnitAttackSpeed("player"))
    return tonumber(main) or 0
end

function ns.UpdateSwingTimer()
    local enabled = Get("swing_timer_enabled") == true
    local speed = SwingMain()
    local inCombat = type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")
    if not (DH.db and DH.db.enabled and enabled and speed > 0 and inCombat) then
        if swingFrame then swingFrame:Hide() end
        swingShow = nil
        return
    end
    if not swingFrame then
        local f = MakeWindow("RotationCoreSwingTimer", "Swing", "swing_timer_position", 0, -330, "swing_timer_scale")
        f:SetSize(160, 20)
        f.bar = f:CreateTexture(nil, "ARTWORK")
        f.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.bar:SetVertexColor(0.9, 0.7, 0.2)
        f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)
        f.bar:SetHeight(8)
        f.title:SetPoint("TOP", f, "TOP", 0, -4)
        swingFrame = f
    end
    local f = swingFrame
    if ns.FadeShow then ns.FadeShow(f) else f:Show() end
    f.speed = speed
    local elapsed = GetTime() - (swingStart or GetTime())
    local prog = math.min(1, elapsed / (speed > 0 and speed or 1))
    f.bar:SetWidth(math.max(2, 152 * prog))
end

-- Capture our own melee swings from the combat log to restart the bar.
if DH.RegisterCombatLogHandler then
    DH:RegisterCombatLogHandler(function(subevent, srcGUID)
        if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
            if srcGUID == UnitGUID("player") then
                swingStart = GetTime()
            end
        end
    end)
end

-- ============================================================================
-- Enemy counter + resource-cap warnings (labels on the icon window)
-- ============================================================================

local function PrimaryFrame()
    return _G.RotationCoreSpellFrame
end

local function EnsurePrimaryLabels()
    local p = PrimaryFrame()
    if not p then return nil end
    if not p.rcEnemyLabel then
        p.rcEnemyLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        p.rcEnemyLabel:SetPoint("TOP", p, "BOTTOM", 0, -16)
        p.rcEnemyLabel:SetTextColor(1, 0.82, 0)
        p.rcEnemyLabel:SetShadowOffset(1, -1)
        p.rcResourceLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        p.rcResourceLabel:SetPoint("TOP", p.rcEnemyLabel, "BOTTOM", 0, -2)
        p.rcResourceLabel:SetTextColor(1, 0.35, 0.3)
        p.rcResourceLabel:SetShadowOffset(1, -1)
    end
    return p
end

local function ResourceWarning()
    local _, ptype = UnitPowerType("player")
    local cur = UnitPower("player", ptype)
    if not cur then return nil end
    local maxp = (type(UnitPowerMax) == "function") and UnitPowerMax("player", ptype) or nil
    if ptype == 4 then
        if cur >= 5 then return L("Combo points capped!") end
        return nil
    end
    if ptype == 3 then
        if cur >= 95 then return L("Energy capped!") end
        return nil
    end
    if ptype == 1 then
        if cur >= 95 then return L("Rage capped!") end
        return nil
    end
    if ptype == 6 then
        if cur >= 90 then return L("Runic power capped!") end
        return nil
    end
    if ptype == 0 and maxp and maxp > 0 then
        if cur / maxp >= 0.97 then return L("Mana full!") end
    end
    return nil
end

function ns.UpdateCombatLabels()
    local p = EnsurePrimaryLabels()
    if not p then return end
    if not (DH.db and DH.db.enabled) then
        p.rcEnemyLabel:Hide()
        p.rcResourceLabel:Hide()
        return
    end
    local inCombat = type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")
    if Get("enemy_count_enabled") ~= false and inCombat then
        local n = (DH.State and DH.State.active_enemies) or 1
        if n and n > 1 then
            p.rcEnemyLabel:SetText(string.format(L("%d enemies"), n))
            p.rcEnemyLabel:Show()
        else
            p.rcEnemyLabel:Hide()
        end
    else
        p.rcEnemyLabel:Hide()
    end
    if Get("resource_warning_enabled") ~= false and inCombat then
        local w = ResourceWarning()
        if w then
            p.rcResourceLabel:SetText(w)
            p.rcResourceLabel:Show()
        else
            p.rcResourceLabel:Hide()
        end
    else
        p.rcResourceLabel:Hide()
    end
end

-- ============================================================================
-- Party / raid health monitor (healer foundation)
-- ============================================================================

local partyFrame
local PARTY_ROWS = 10

local function PartyUnits()
    local out = {}
    if type(IsInRaid) == "function" and IsInRaid() and type(GetNumRaidMembers) == "function" then
        for i = 1, GetNumRaidMembers() do out[#out + 1] = "raid" .. i end
    elseif type(IsInGroup) == "function" and IsInGroup() and type(GetNumPartyMembers) == "function" then
        out[#out + 1] = "player"
        for i = 1, GetNumPartyMembers() do out[#out + 1] = "party" .. i end
    else
        out[#out + 1] = "player"
    end
    return out
end

function ns.UpdatePartyHealth()
    if ns.playerDead then
        if partyFrame then partyFrame:Hide() end
        return
    end
    local show = Get("party_health_enabled") == true
    if not (DH.db and DH.db.enabled and show) then
        if partyFrame then if ns.FadeHide then ns.FadeHide(partyFrame) else partyFrame:Hide() end end
        return
    end
    if not partyFrame then
        partyFrame = MakeWindow("RotationCorePartyHealth", "Group health", "party_health_position", 250, -80, nil)
        partyFrame.rows = {}
        for i = 1, PARTY_ROWS do
            local fs = partyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", partyFrame, "TOPLEFT", 10, -22 - (i - 1) * 15)
            fs:SetJustifyH("LEFT")
            fs:SetWidth(180)
            partyFrame.rows[i] = fs
        end
    end
    local f = partyFrame
    local list = {}
    for _, unit in ipairs(PartyUnits()) do
        if UnitExists(unit) then
            local maxh = UnitHealthMax(unit)
            if maxh and maxh > 0 then
                local pct = UnitHealth(unit) / maxh * 100
                list[#list + 1] = { unit = unit, name = UnitName(unit) or "?", pct = pct }
            end
        end
    end
    table.sort(list, function(a, b) return a.pct < b.pct end)
    local n = math.min(#list, PARTY_ROWS)
    for i = 1, PARTY_ROWS do
        local fs = f.rows[i]
        local it = list[i]
        if it then
            fs:SetText(string.format("%s  %d%%", tostring(it.name), math.floor(it.pct + 0.5)))
            if it.pct < 35 then
                fs:SetTextColor(1, 0.3, 0.3)
            elseif it.pct < 70 then
                fs:SetTextColor(1, 0.82, 0.2)
            else
                fs:SetTextColor(0.4, 1, 0.4)
            end
            fs:Show()
        else
            fs:SetText("")
            fs:Hide()
        end
    end
    if n == 0 then
        f.rows[1]:SetText(L("No group members."))
        f.rows[1]:SetTextColor(0.6, 0.6, 0.6)
        f.rows[1]:Show()
        n = 1
    end
    if not f.isMoving then f:SetSize(200, 24 + n * 15 + 4) end
    if ns.FadeShow then ns.FadeShow(f) else f:Show() end
end

-- ============================================================================
-- Driver
-- ============================================================================

local driver = CreateFrame("Frame", "RotationCoreExtras", UIParent)
driver.acc = 0

local function AnyExtraActive()
    if Get("dot_panel_enabled") == true or Get("swing_timer_enabled") == true
        or Get("party_health_enabled") == true or Get("heal_assist_enabled") == true then return true end
    local inCombat = type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")
    if inCombat and (Get("enemy_count_enabled") ~= false or Get("resource_warning_enabled") ~= false) then
        return true
    end
    return false
end

local function ExtrasTick(self, dt)
    if not AnyExtraActive() then
        -- One idle pass to hide anything still shown, then stay dormant.
        if not self._idle then
            self._idle = true
            if ns.UpdateDotFrame then ns.UpdateDotFrame() end
            if ns.UpdateSwingTimer then ns.UpdateSwingTimer() end
            if ns.UpdateCombatLabels then ns.UpdateCombatLabels() end
            if ns.UpdatePartyHealth then ns.UpdatePartyHealth() end
            if ns.UpdateHealAssist then ns.UpdateHealAssist() end
        end
        return
    end
    self._idle = false
    self.acc = self.acc + dt
    if self.acc < 0.2 then return end
    self.acc = 0
    if ns.UpdateDotFrame then ns.UpdateDotFrame() end
    if ns.UpdateSwingTimer then ns.UpdateSwingTimer() end
    if ns.UpdateCombatLabels then ns.UpdateCombatLabels() end
    if ns.UpdatePartyHealth then ns.UpdatePartyHealth() end
    if ns.UpdateHealAssist then ns.UpdateHealAssist() end
end

driver:SetScript("OnUpdate", function(self, dt)
    local ok, err = pcall(ExtrasTick, self, dt)
    if not ok then
        driver:SetScript("OnUpdate", nil)
        if ns.AddError then
            ns.AddError("Extras update stopped after error: " .. tostring(err))
        end
    end
end)

