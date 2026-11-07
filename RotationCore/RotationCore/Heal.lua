-- Heal.lua
-- Healer assist: recommends a heal for the lowest-health group member based on
-- the health deficit, mana and which heals you actually know. 3.3.5a, no deps.

local DH = RotationCore
if not DH then return end
local ns = DH.ns

local function L(s)
    local t = DH.L
    if t and type(s) == "string" then return t[s] end
    return s
end
local function Get(k) return DH.GetSetting and DH:GetSetting(k) end

-- Heal sets per class (3.3.5a max ranks). tier: big / med / hot / inst / aoe.
-- Max-rank id first, base-rank id as a fallback (IsSpellKnown can match either).
local HEALS = {
    PRIEST = {
        { id = 48063, alt = 2060, tier = "big" },   -- Greater Heal (Rank 9)
        { id = 48071, alt = 2061, tier = "med" },   -- Flash Heal (Rank 11)
        { id = 48068, alt = 139,  tier = "hot" },   -- Renew (Rank 14)
        { id = 48066, alt = 17,   tier = "inst" },  -- Power Word: Shield (Rank 14)
        -- Circle of Healing (Rank 7) first so an instant holy raid heal is
        -- preferred over the cast-time party heal when both are known.
        { id = 48089, alt = 34861, tier = "aoe" },  -- Circle of Healing (Rank 7)
        { id = 48072, alt = 596,  tier = "aoe" },   -- Prayer of Healing (Rank 7)
    },
    DRUID = {
        { id = 48378, alt = 5185, tier = "big" },   -- Healing Touch (Rank 15)
        { id = 50464, alt = 50464, tier = "med" },  -- Nourish (Rank 1)
        { id = 48443, alt = 8936, tier = "med" },   -- Regrowth (Rank 12)
        { id = 48441, alt = 774,  tier = "hot" },   -- Rejuvenation (Rank 15)
        { id = 48451, alt = 33763, tier = "hot" },  -- Lifebloom (Rank 3)
        { id = 53251, alt = 48438, tier = "aoe" },  -- Wild Growth (Rank 4)
    },
    SHAMAN = {
        { id = 49273, alt = 331,  tier = "big" },   -- Healing Wave (Rank 14)
        { id = 49276, alt = 8004, tier = "med" },   -- Lesser Healing Wave (Rank 9)
        { id = 61301, alt = 61295, tier = "hot" },  -- Riptide (Rank 4)
        { id = 49284, alt = 974,  tier = "inst" },  -- Earth Shield (Rank 5)
        { id = 55459, alt = 1064, tier = "aoe" },   -- Chain Heal (Rank 7)
    },
    PALADIN = {
        { id = 48782, alt = 635,   tier = "big" },  -- Holy Light (Rank 13)
        { id = 48785, alt = 19750, tier = "med" },  -- Flash of Light (Rank 9)
        { id = 48825, alt = 20473, tier = "inst" }, -- Holy Shock (Rank 7)
        { id = 53601, alt = 53601, tier = "inst" }, -- Sacred Shield (Rank 1)
    },
}

local function KnownTier(list, tier)
    for _, h in ipairs(list) do
        if h.tier == tier and type(IsSpellKnown) == "function"
           and (IsSpellKnown(h.id) or (h.alt and IsSpellKnown(h.alt))) then
            return h
        end
    end
    return nil
end

-- Pick a heal for a unit. Returns spellId, tier, or nil.
function ns.GetHealSuggestion(unit, lowCount)
    local list = HEALS[DH.playerClass]
    if not list then return nil end
    if not UnitExists(unit) then return nil end
    local maxh = UnitHealthMax(unit)
    if not maxh or maxh <= 0 then return nil end
    local deficit = 100 - (UnitHealth(unit) / maxh * 100)
    local mana = UnitPower and UnitPower("player", 0) or 1
    local manamax = (type(UnitPowerMax) == "function") and UnitPowerMax("player", 0) or nil
    local lowMana = manamax and manamax > 0 and (mana / manamax) < 0.25

    local tier
    if (lowCount or 0) >= 3 then tier = "aoe"
    elseif deficit >= 55 then tier = "big"
    elseif deficit >= 25 then tier = "med"
    elseif deficit >= 10 then tier = "hot"
    else return nil end
    if lowMana and tier == "big" then tier = "med" end

    local h = KnownTier(list, tier)
    -- Fallbacks to cheaper/simpler heals when the preferred tier is unknown.
    if not h and tier == "big" then h = KnownTier(list, "med") end
    if not h and tier == "med" then h = KnownTier(list, "hot") or KnownTier(list, "inst") end
    -- A small deficit wants a cheap heal; an instant (Renew / Riptide) is
    -- nice but a Paladin has no HoT, so fall through to Flash of Light.
    if not h and tier == "hot" then h = KnownTier(list, "inst") or KnownTier(list, "med") end
    if not h and tier == "aoe" then h = KnownTier(list, "med") or KnownTier(list, "big") end
    if not h then return nil end
    return h.id, tier
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local healFrame
local HEAL_ROWS = 10

local function HealUnits()
    local out = {}
    if type(IsInRaid) == "function" and IsInRaid() and GetNumRaidMembers then
        for i = 1, GetNumRaidMembers() do out[#out + 1] = "raid" .. i end
    elseif type(IsInGroup) == "function" and IsInGroup() and GetNumPartyMembers then
        out[#out + 1] = "player"
        for i = 1, GetNumPartyMembers() do out[#out + 1] = "party" .. i end
    else
        out[#out + 1] = "player"
    end
    return out
end

local function MakeHealWindow()
    local f = CreateFrame("Frame", "RotationCoreHealAssist", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local pos = DH:GetSetting("heal_assist_position")
        if type(pos) == "table" then
            local cx, cy = s:GetCenter(); local ux, uy = UIParent:GetCenter()
            if cx and ux and cy and uy then pos.x, pos.y = cx - ux, cy - uy end
        end
    end)
    f:SetSize(210, 60)
    if ns.ApplyWindowChrome then ns.ApplyWindowChrome(f) end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOP", f, "TOP", 0, -5)
    f.title:SetText(L("Heal assist"))
    if ns.ApplyFont then ns.ApplyFont(f.title) end
    local pos = DH:GetSetting("heal_assist_position")
    if type(pos) == "table" and pos.x and pos.y then
        f:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -260, -120)
    end
    f.rows = {}
    for i = 1, HEAL_ROWS do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -22 - (i - 1) * 15)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(190)
        f.rows[i] = fs
    end
    return f
end

function ns.UpdateHealAssist()
    if ns.playerDead then
        if healFrame then healFrame:Hide() end
        return
    end
    local show = Get("heal_assist_enabled") == true
    if not (DH.db and DH.db.enabled and show) or not HEALS[DH.playerClass] then
        if healFrame then
            if ns.FadeHide then ns.FadeHide(healFrame) else healFrame:Hide() end
        end
        return
    end
    if not healFrame then healFrame = MakeHealWindow() end
    local f = healFrame

    local list = {}
    for _, unit in ipairs(HealUnits()) do
        if UnitExists(unit) then
            local maxh = UnitHealthMax(unit)
            if maxh and maxh > 0 then
                list[#list + 1] = { unit = unit, name = UnitName(unit) or "?", pct = UnitHealth(unit) / maxh * 100 }
            end
        end
    end
    table.sort(list, function(a, b) return a.pct < b.pct end)
    local lowCount = 0
    for _, e in ipairs(list) do if e.pct < 70 then lowCount = lowCount + 1 end end

    local n = math.min(#list, HEAL_ROWS)
    for i = 1, HEAL_ROWS do
        local fs = f.rows[i]
        local it = list[i]
        if it then
            local spellId = ns.GetHealSuggestion(it.unit, lowCount)
            local name = spellId and GetSpellInfo(spellId) or nil
            fs:SetText(string.format("%s  %d%%  %s", tostring(it.name), math.floor(it.pct + 0.5), name or "-"))
            if it.pct < 35 then fs:SetTextColor(1, 0.3, 0.3)
            elseif it.pct < 70 then fs:SetTextColor(1, 0.82, 0.2)
            else fs:SetTextColor(0.5, 0.9, 0.5) end
            fs:Show()
        else
            fs:SetText(""); fs:Hide()
        end
    end
    if n == 0 then
        f.rows[1]:SetText(L("No group members.")); f.rows[1]:SetTextColor(0.6, 0.6, 0.6); f.rows[1]:Show(); n = 1
    end
    if not f.isMoving then f:SetSize(220, 24 + n * 15 + 4) end
    if ns.FadeShow then ns.FadeShow(f) else f:Show() end
end

function ns.IsHealerClass()
    return HEALS[DH.playerClass] ~= nil
end

-- ============================================================================
-- SHARED HEAL ROTATION HELPERS
-- Used by the per-class heal modes. Deliberately independent from the DPS
-- simulation: these helpers only inspect group health, auras and cooldowns.
-- ============================================================================

local function abilityId(key)
    local a = DH.Class and DH.Class.abilities and DH.Class.abilities[key]
    return a and a.id or nil
end

function ns.GetManaPct()
    local maxp = UnitPowerMax and UnitPowerMax("player", 0) or nil
    if maxp and maxp > 0 then
        return (UnitPower("player", 0) / maxp) * 100
    end
    return 100
end

function ns.GetUnitHealthPct(unit)
    if not unit or type(UnitExists) ~= "function" or not UnitExists(unit) then
        return 0
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return 0 end
    local maxh = UnitHealthMax(unit)
    if not maxh or maxh <= 0 then return 0 end
    return (UnitHealth(unit) / maxh) * 100
end

function ns.IsHealableUnit(unit)
    if not unit or type(UnitExists) ~= "function" or not UnitExists(unit) then
        return false
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return false end
    if UnitIsConnected and UnitIsConnected(unit) == false then return false end
    if UnitCanAssist and UnitCanAssist("player", unit) == false then return false end
    return true
end

function ns.GetHealUnits()
    local units = {}
    local function add(unit)
        if ns.IsHealableUnit(unit) then units[#units + 1] = unit end
    end

    add("player")
    if type(IsInRaid) == "function" and IsInRaid() and type(GetNumRaidMembers) == "function" then
        for i = 1, GetNumRaidMembers() do add("raid" .. i) end
    elseif type(IsInGroup) == "function" and IsInGroup() and type(GetNumPartyMembers) == "function" then
        for i = 1, GetNumPartyMembers() do add("party" .. i) end
    end
    return units
end

function ns.IsTank(unit)
    if type(UnitGroupRolesAssigned) == "function" then
        local role = UnitGroupRolesAssigned(unit)
        if role == "TANK" then return true end
    end
    if unit and type(UnitIsUnit) == "function" then
        if UnitExists("target") and UnitIsUnit(unit, "target")
            and not (UnitCanAttack and UnitCanAttack("player", unit)) then
            return true
        end
        if UnitExists("focus") and UnitIsUnit(unit, "focus")
            and not (UnitCanAttack and UnitCanAttack("player", unit)) then
            return true
        end
    end
    return false
end

function ns.GetHealContext()
    local units = ns.GetHealUnits()
    local list, injured = {}, {}
    for _, unit in ipairs(units) do
        local maxh = UnitHealthMax(unit) or 0
        if maxh > 0 then
            local pct = ns.GetUnitHealthPct(unit)
            local entry = {
                unit = unit,
                name = UnitName(unit) or "?",
                pct = pct,
                deficit = 100 - pct,
                maxh = maxh,
                tank = ns.IsTank(unit),
            }
            list[#list + 1] = entry
            if pct < 100 then injured[#injured + 1] = entry end
        end
    end
    local function sortByHealth(a, b)
        if a.pct == b.pct then return a.maxh > b.maxh end
        return a.pct < b.pct
    end
    table.sort(list, sortByHealth)
    table.sort(injured, sortByHealth)

    local lowCount = 0
    for _, e in ipairs(list) do
        if e.pct < 70 then lowCount = lowCount + 1 end
    end

    return {
        units = units,
        list = list,
        injured = injured,
        lowCount = lowCount,
        injuredCount = #injured,
        manaPct = ns.GetManaPct(),
        grouped = (type(IsInGroup) == "function" and IsInGroup()) and true or false,
        raid = (type(IsInRaid) == "function" and IsInRaid()) and true or false,
    }
end

function ns.GetInjuredCount(ctx, pct)
    ctx = ctx or ns.GetHealContext()
    pct = pct or 80
    local n = 0
    for _, e in ipairs(ctx.list) do
        if e.pct < pct then n = n + 1 end
    end
    return n
end

function ns.GetHealTarget(ctx, opts)
    ctx = ctx or ns.GetHealContext()
    opts = opts or {}
    local below = opts.below or 100
    local minDeficit = opts.minDeficit or 0
    local exclude = opts.exclude

    local function usable(e)
        if e.pct >= below or e.deficit < minDeficit then return false end
        if exclude and exclude[e.unit] then return false end
        return true
    end

    if opts.preferTank then
        for _, e in ipairs(ctx.list) do
            if e.tank and usable(e) then return e end
        end
    end
    for _, e in ipairs(ctx.list) do
        if usable(e) then return e end
    end
    return nil
end

function ns.GetTankTarget(ctx)
    ctx = ctx or ns.GetHealContext()
    for _, e in ipairs(ctx.list) do
        if e.tank then return e end
    end
    -- Fall back to a friendly target/focus, then the highest-health group
    -- member (usually the tank when role information is unavailable).
    for _, e in ipairs(ctx.list) do
        if (UnitExists("target") and UnitIsUnit(e.unit, "target"))
            or (UnitExists("focus") and UnitIsUnit(e.unit, "focus")) then
            return e
        end
    end
    local best
    for _, e in ipairs(ctx.list) do
        if not best or e.maxh > best.maxh then best = e end
    end
    return best
end

function ns.GetUnitAuraInfo(unit, spellId, filter)
    if not unit or not spellId or type(UnitAura) ~= "function" then return nil end
    local wanted = GetSpellInfo and GetSpellInfo(spellId) or nil
    if not wanted then return nil end
    for i = 1, 40 do
        local name, _, _, count, debuffType, duration, expirationTime, source = UnitAura(unit, i, filter or "HELPFUL")
        if not name then break end
        if name == wanted then
            local remains = 0
            if expirationTime and expirationTime > 0 then
                remains = expirationTime - GetTime()
            end
            return {
                name = name,
                count = count or 0,
                duration = duration or 0,
                remains = math.max(0, remains),
                debuffType = debuffType,
                source = source,
            }
        end
    end
    return nil
end

function ns.GetAbilityAura(unit, key, filter)
    local id = abilityId(key)
    if not id then return nil end
    return ns.GetUnitAuraInfo(unit, id, filter)
end

function ns.HasAura(unit, spellId, filter)
    return ns.GetUnitAuraInfo(unit, spellId, filter) ~= nil
end

function ns.IsUnitInHealRange(unit, spellId)
    if not unit then return false end
    if type(IsSpellInRange) == "function" and spellId then
        local name = GetSpellInfo and GetSpellInfo(spellId) or nil
        local ok, result = pcall(IsSpellInRange, name or spellId, unit)
        if ok then
            if result == 1 then return true end
            if result == 0 then return false end
        end
    end
    if type(UnitInRange) == "function" then
        local ok, inRange = pcall(UnitInRange, unit)
        if ok and inRange ~= nil then return inRange end
    end
    return true
end

function ns.CanHeal(key, target)
    local ability = DH.Class and DH.Class.abilities and DH.Class.abilities[key]
    if not ability or not ability.id then return false end
    if not (DH.IsAbilityKnown and DH:IsAbilityKnown(key)) then return false end
    if not (DH.SpellReady and DH:SpellReady(ability.id)) then return false end
    local unit = type(target) == "table" and target.unit or target
    if unit and not ns.IsUnitInHealRange(unit, ability.id) then return false end
    return true
end

function ns.PushHeal(recs, key, target, reason)
    local ability = DH.Class and DH.Class.abilities and DH.Class.abilities[key]
    local unit = type(target) == "table" and target.unit or target
    if not ability or not unit then return false end
    for _, rec in ipairs(recs) do
        if rec.ability == key and rec.unit == unit then return false end
    end
    recs[#recs + 1] = {
        ability = key,
        unit = unit,
        targetName = UnitName(unit) or unit,
        priority = #recs + 1,
        reason = reason,
    }
    return true
end

function ns.FindDispelTarget(ctx, types)
    ctx = ctx or ns.GetHealContext()
    if type(UnitAura) ~= "function" then return nil end
    for _, e in ipairs(ctx.list) do
        for i = 1, 40 do
            local name, _, _, _, debuffType = UnitAura(e.unit, i, "HARMFUL")
            if not name then break end
            if debuffType and types[debuffType] then
                return e, name, debuffType
            end
        end
    end
    return nil
end

function ns.GetSubgroupInjuredCount(unit, ctx, pct)
    ctx = ctx or ns.GetHealContext()
    pct = pct or 80
    if not (type(IsInRaid) == "function" and IsInRaid() and type(GetNumRaidMembers) == "function") then
        return ns.GetInjuredCount(ctx, pct)
    end
    local wanted = UnitName(unit)
    local subgroup
    for i = 1, GetNumRaidMembers() do
        local name, _, sub = GetRaidRosterInfo(i)
        if name == wanted then subgroup = sub; break end
    end
    if not subgroup then return ns.GetInjuredCount(ctx, pct) end
    local n = 0
    for i = 1, GetNumRaidMembers() do
        local _, _, sub = GetRaidRosterInfo(i)
        if sub == subgroup and ns.GetUnitHealthPct("raid" .. i) < pct then
            n = n + 1
        end
    end
    return n
end
