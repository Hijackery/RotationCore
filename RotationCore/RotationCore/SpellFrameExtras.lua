-- SpellFrameExtras.lua
-- Optional cooldown, interrupt and boss-timeline windows. Split out of
-- SpellFrame.lua; the main icon window stays in SpellFrame.lua.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

local MAX_SLOTS = 10
local BASE_ICON = 36
local GAP = 4
local TITLE_H = ns.FRAME_TITLE_H or 24
local EXTRA_PAD_X = ns.FRAME_PAD_X or 8
local EXTRA_TOP = ns.FRAME_TITLE_H or 24
local EXTRA_BOTTOM = ns.FRAME_PAD_BOTTOM or 8
local EXTRA_GLOW = 8
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"

local function L(s)
    local tbl = DH.L
    if tbl and type(s) == "string" then
        return tbl[s]
    end
    return s
end

-- ============================================================================
-- EXTRA DISPLAYS (phase 2.1 cooldowns, phase 2.3 interrupts)
-- Small optional windows next to the main icon window. They share the style,
-- are locked/unlocked together with the main window (/rc move) and each saves
-- its own position.
-- ============================================================================

local function GetExtraPos(f)
    if f.posKey and DH.GetSetting then
        local pos = DH:GetSetting(f.posKey)
        if type(pos) == "table" then
            return pos
        end
    end
    return nil
end

local function ApplyExtraPosition(f)
    f:ClearAllPoints()
    local pos = GetExtraPos(f)
    if pos and pos.x and pos.y then
        f:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", f.defX or 0, f.defY or -250)
    end
end

local function SaveExtraPosition(f)
    local pos = GetExtraPos(f)
    if not pos then
        return
    end
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    pos.x = cx - ux
    pos.y = cy - uy
    if DH.SetSetting then
        DH:SetSetting("display_layout", "custom")
    end
end

local function CreateExtraFrame(id, titleText, posKey, defX, defY, scaleKey)
    local f = CreateFrame("Frame", "RotationCore" .. id, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f.posKey, f.defX, f.defY, f.scaleKey = posKey, defX, defY, scaleKey
    f.kind = (id == "InterruptsFrame") and "interrupt" or "cooldowns"
    f:Hide()
    f:SetFrameLevel((UIParent and UIParent.GetFrameLevel and UIParent:GetFrameLevel() or 0) + 5)

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -5)
    f.title:SetJustifyH("LEFT")
    f.title:SetText(titleText)
    if ns.ApplyWindowChrome then
        ns.ApplyWindowChrome(f)
    end
    if ns.ApplyFont then
        ns.ApplyFont(f.title)
    end
    ns.AttachMoveOverlay(f, false)

    f.slots = {}
    for i = 1, MAX_SLOTS do
        local slot = CreateFrame("Frame", nil, f)
        slot:SetFrameLevel(f:GetFrameLevel() + 2)
        slot.topline = slot:CreateTexture(nil, "OVERLAY", nil, 1)
        slot.topline:SetTexture("Interface\\Buttons\\WHITE8X8")
        slot.topline:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
        slot.topline:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)
        slot.topline:SetHeight(2)
        slot.iconPrev = slot:CreateTexture(nil, "ARTWORK")
        slot.iconPrev:SetAllPoints()
        slot.iconPrev:SetAlpha(0)
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints()
        slot.border = slot:CreateTexture(nil, "OVERLAY")
        slot.border:SetTexture(GLOW_TEXTURE)
        slot.border:SetBlendMode("ADD")
        slot.cd = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slot.cd:SetPoint("CENTER")
        slot.cd:SetTextColor(1, 1, 1)
        slot.cd:SetShadowOffset(1, -1)
        slot:SetScript("OnEnter", function(self)
            if not self.spellId then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:" .. self.spellId)
            if self.kind == "interrupt" then
                local maxR = select(9, GetSpellInfo(self.spellId))
                if maxR and maxR > 0 then
                    GameTooltip:AddLine(string.format(L("Range: %s"), tostring(maxR)), 0.3, 1, 0.3, false)
                end
            elseif type(GetSpellCooldown) == "function" then
                local start, duration = GetSpellCooldown(self.spellId)
                local remains = (start and duration and duration > 0) and math.max(0, start + duration - GetTime()) or 0
                if remains <= 0 then
                    GameTooltip:AddLine(L("Ready"), 0.3, 1, 0.3, false)
                else
                    GameTooltip:AddLine(string.format(L("CD: %s"), string.format("%.1f", remains)), 1, 0.82, 0, false)
                end
            end
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        slot:EnableMouse(true)
        slot:Hide()
        f.slots[i] = slot
    end

    f:SetScript("OnDragStart", function(self)
        if DH.WindowsLocked and DH:WindowsLocked() then
            return
        end
        self.isMoving = true
        if self.moveText then
            self.moveLabel = self.title and self.title:GetText() or ""
            self.moveText:SetText(self.moveLabel)
            self.moveText:Show()
        end
        self:StartMoving()
        if self.moveUpdate then
            self:SetScript("OnUpdate", self.moveUpdate)
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.isMoving = false
        self:SetScript("OnUpdate", nil)
        if self.moveText then
            self.moveText:Hide()
        end
        if ns.configMode and ns.SnapToGrid then
            ns.SnapToGrid(self)
        end
        SaveExtraPosition(self)
        if SetCursor then
            SetCursor(nil)
        end
    end)
    -- No custom cursor: "UI_CURSOR_HAND" is not a valid 3.3.5a cursor path and
    -- hides the cursor (see the primary window). Always use the default arrow.
    f:SetScript("OnLeave", function()
        if SetCursor then
            SetCursor(nil)
        end
    end)
    f:SetScript("OnHide", function()
        if SetCursor then
            SetCursor(nil)
        end
    end)

    -- Custom resize grip (3.3.5a has no Frame:SetResizable). Dragging it
    -- scales the window; the scale is persisted under f.scaleKey and applied
    -- by RenderExtra. Only added when the frame opts into resizing.
    if scaleKey then
        local resize
        local function GripUpdate()
            if not resize then
                return
            end
            local _, cy = GetCursorPosition()
            local d = (resize.y - cy) / (resize.scale or 1)
            local s = resize.s + d / 90
            if s < 0.5 then
                s = 0.5
            end
            if s > 2.5 then
                s = 2.5
            end
            if DH.SetSetting then
                DH:SetSetting(scaleKey, s)
            end
            if f.refresh then
                f.refresh()
            end
        end
        local grip = CreateFrame("Button", nil, f)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetFrameLevel(f:GetFrameLevel() + 5)
        grip:SetScript("OnMouseDown", function()
            local _, cy = GetCursorPosition()
            resize = {
                s = (DH.GetSetting and DH:GetSetting(scaleKey)) or 1,
                y = cy,
                scale = UIParent:GetScale(),
            }
            grip:SetScript("OnUpdate", GripUpdate)
        end)
        grip:SetScript("OnMouseUp", function()
            resize = nil
            grip:SetScript("OnUpdate", nil)
        end)
        f.grip = grip

        -- Mouse wheel scales the window too (same feel as the primary window).
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", function(_, delta)
            local cur = (DH.GetSetting and DH:GetSetting(scaleKey)) or 1
            local s = cur + (delta > 0 and 0.1 or -0.1)
            if s < 0.5 then
                s = 0.5
            elseif s > 2.5 then
                s = 2.5
            end
            s = math.floor(s * 10 + 0.5) / 10
            if DH.SetSetting then
                DH:SetSetting(scaleKey, s)
            end
            if f.refresh then
                f.refresh()
            end
        end)
    end

    return f
end

-- items = { { id =, texture =, remaining =, ready = }, ... }
local function RenderExtra(f, items, showCount)
    if not f then
        return
    end
    local db = DH.db
    -- Per-window scale (resize grip) wins over the global icon-window scale.
    local scale
    if f.scaleKey and DH.GetSetting then
        scale = DH:GetSetting(f.scaleKey)
    end
    if not scale then
        scale = (db and db.display and db.display.spellframe_scale) or 1
    end
    local baseIcon = (DH.GetSetting and DH:GetSetting("icon_size")) or BASE_ICON
    local baseGap = (DH.GetSetting and DH:GetSetting("icon_gap")) or GAP
    local iconSize = math.max(16, math.floor(baseIcon * scale + 0.5))
    local gap = math.max(2, math.floor(baseGap * scale))

    -- The window is sized for the CONFIGURED icon count, so it keeps the same
    -- size whether or not abilities are ready / a target is selected.
    local configured = tonumber(showCount) or 1
    configured = math.max(1, math.min(configured, MAX_SLOTS))
    local function fixedWidth()
        local w = configured * iconSize + (configured - 1) * gap + EXTRA_PAD_X * 2
        local tw = (f.title and f.title:GetStringWidth() or 0) + EXTRA_PAD_X * 2
        return math.max(w, tw)
    end
    local function fixedHeight()
        return EXTRA_TOP + iconSize + EXTRA_BOTTOM
    end

    if not items or #items == 0 then
        if ns.moveMode or f.noItemsKeep then
            if not f.isMoving then
                f:SetSize(fixedWidth(), fixedHeight())
                ApplyExtraPosition(f)
            end
            for i = 1, MAX_SLOTS do
                f.slots[i]:Hide()
            end
            if not f:IsShown() then
                f:SetAlpha(0)
            end
            f:Show()
        else
            f:Hide()
        end
        return
    end

    local count = math.min(configured, #items)
    if count < 1 then
        count = 1
    end
    local spanW = count * iconSize + (count - 1) * gap

    if not f.isMoving then
        f:SetSize(fixedWidth(), fixedHeight())
        ApplyExtraPosition(f)
    end

    for i = 1, MAX_SLOTS do
        local slot = f.slots[i]
        local it = items[i]
        if i <= count and it then
            slot:SetSize(iconSize, iconSize)
            slot:ClearAllPoints()
            local x = -spanW / 2 + iconSize / 2 + (i - 1) * (iconSize + gap)
            slot:SetPoint("BOTTOM", f, "BOTTOM", x, EXTRA_BOTTOM)
            slot.icon:SetTexture(it.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            slot.border:SetSize(iconSize + EXTRA_GLOW, iconSize + EXTRA_GLOW)
            slot.border:ClearAllPoints()
            slot.border:SetPoint("CENTER")
            if it.ready then
                slot.border:SetVertexColor(0.15, 1, 0.15)
                if slot.topline then
                    slot.topline:SetVertexColor(0.15, 1, 0.15, 0.9)
                end
            else
                slot.border:SetVertexColor(1, 1, 1)
                if slot.topline then
                    slot.topline:SetVertexColor(1, 0.82, 0.2, 0.85)
                end
            end
            if it.remaining and it.remaining > 0.5 then
                slot.cd:SetText(math.ceil(it.remaining))
                if f.kind == "interrupt" then
                    slot.cd:SetTextColor(1, 0.3, 0.3)
                else
                    slot.cd:SetTextColor(1, 1, 1)
                end
            else
                slot.cd:SetText("")
            end
            slot.spellId = it.id
            slot.kind = f.kind
            slot:Show()
        else
            slot:Hide()
        end
    end

    if not f.isMoving then
        if not f:IsShown() then
            f:SetAlpha(0)
        end
        f:Show()
    end
end

-- Remaining cooldown seconds for a spell id (0 when ready)
local function GetSpellRemains(spellId)
    if not spellId or type(GetSpellCooldown) ~= "function" then
        return 0
    end
    local start, duration = GetSpellCooldown(spellId)
    if not start or not duration or duration <= 0 then
        return 0
    end
    local remains = (start + duration) - GetTime()
    if remains < 0 then
        remains = 0
    end
    return remains
end

-- Smooth countdown text for the cooldown / interrupt windows. RenderExtra
-- still decides which slots exist; this ticker only refreshes the number.
local function EnsureExtraTicker(f)
    if not f or f.cdTicker then
        return
    end
    local ticker = CreateFrame("Frame", nil, f)
    ticker:SetAllPoints(f)
    ticker:Show()
    ticker.elapsed = 0
    ticker:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.03 then
            return
        end
        self.elapsed = 0
        for i = 1, MAX_SLOTS do
            local slot = f.slots and f.slots[i]
            if slot and slot:IsShown() and slot.spellId then
                local remains = GetSpellRemains(slot.spellId)
                if remains > 0.05 then
                    if remains >= 10 then
                        slot.cd:SetText(string.format("%d", math.ceil(remains)))
                    else
                        slot.cd:SetText(string.format("%.1f", remains))
                    end
                    if f.kind == "interrupt" then
                        slot.cd:SetTextColor(1, 0.3, 0.3)
                    else
                        slot.cd:SetTextColor(1, 1, 1)
                    end
                else
                    slot.cd:SetText("")
                end
            end
        end
    end)
    f.cdTicker = ticker
end

ns.cooldownsFrame = nil
-- Candidate list for the cooldown display. It only depends on the active mode's
-- baseCDs, the class ability table, the min-CD filter and which spells are
-- known, so it is rebuilt only when one of those changes; the per-tick pass just
-- refreshes the remaining time on the reused entry tables (M15).
local cdCache = { base = nil, class = nil, minCD = nil, showReady = nil, known = nil, entries = {} }
local cdOut = {}
local function GetCooldownItems()
    local cfg = ns.lastCdConfig
    local base = cfg and cfg.baseCDs
    -- Fallback when no simulation has populated the CD map yet: scan the
    -- registered ability table with GetSpellCooldown directly.
    if not base then
        base = {}
        local ab = DH.Class and DH.Class.abilities or {}
        for key, a in pairs(ab) do
            if a and a.id then
                local start, dur = GetSpellCooldown(a.id)
                if dur and dur > 0 then
                    base[key] = dur
                end
            end
        end
        cfg = cfg or {}
        ns.lastCdConfig = cfg
        cfg.baseCDs = base
    end
    local classes = DH.Class and DH.Class.abilities or {}
    local minCD = (DH.GetSetting and DH:GetSetting("cooldowns_min_cd")) or 60
    local showReady = (DH.GetSetting and DH:GetSetting("cooldowns_show_ready")) ~= false
    local knownToken = ns.knownSpellsVersion

    local entries = cdCache.entries
    if
        cdCache.base ~= base
        or cdCache.class ~= classes
        or cdCache.minCD ~= minCD
        or cdCache.showReady ~= showReady
        or cdCache.known ~= knownToken
    then
        cdCache.base, cdCache.class = base, classes
        cdCache.minCD, cdCache.showReady, cdCache.known = minCD, showReady, knownToken
        wipe(entries)
        if base then
            for key, baseCD in pairs(base) do
                if type(baseCD) == "number" and baseCD >= minCD then
                    local ability = classes[key]
                    if ability and ability.id and DH:IsAbilityKnown(key) then
                        entries[#entries + 1] = {
                            id = ability.id,
                            texture = ability.texture,
                            remaining = 0,
                            ready = false,
                        }
                    end
                end
            end
        end
        -- Racial cooldowns (Blood Fury, Berserking, ...) join the class ones.
        if (not DH.GetSetting) or DH:GetSetting("use_racial_cooldowns") ~= false then
            if ns.GetRacialCooldownIds then
                for _, rid in ipairs(ns.GetRacialCooldownIds()) do
                    local rn, _, rtex = GetSpellInfo(rid)
                    if rn then
                        entries[#entries + 1] = { id = rid, texture = rtex, remaining = 0, ready = false }
                    end
                end
            end
        end
    end

    for i = 1, #entries do
        local it = entries[i]
        local remaining = GetSpellRemains(it.id)
        it.remaining = remaining
        it.ready = remaining <= 0
    end

    wipe(cdOut)
    for i = 1, #entries do
        local it = entries[i]
        if showReady or not it.ready then
            cdOut[#cdOut + 1] = it
        end
    end
    table.sort(cdOut, function(a, b)
        if a.ready ~= b.ready then
            return a.ready
        end
        return a.remaining < b.remaining
    end)
    return cdOut
end

function ns.UpdateCooldownsFrame()
    if ns.playerDead then
        if ns.cooldownsFrame then
            ns.cooldownsFrame:Hide()
        end
        return
    end
    local show = (DH.GetSetting and DH:GetSetting("show_cooldowns_display")) == true
    if not DH.db or not DH.db.enabled or (not show and not ns.moveMode) then
        if ns.cooldownsFrame then
            ns.cooldownsFrame:Hide()
        end
        return
    end
    if not ns.cooldownsFrame then
        local title = (DH.L and DH.L["Cooldowns"]) or "Cooldowns"
        ns.cooldownsFrame = CreateExtraFrame("CooldownsFrame", title, "cooldowns_position", -150, 0, "cooldowns_scale")
        ns.cooldownsFrame.refresh = ns.UpdateCooldownsFrame
        ns.cooldownsFrame.noItemsKeep = true
    end
    EnsureExtraTicker(ns.cooldownsFrame)
    if #GetCooldownItems() == 0 and ns.cooldownsFrame then
        local cdTitle = (DH.L and DH.L["No cooldowns"]) or "No cooldowns"
        if ns.cooldownsFrame.title and ns.cooldownsFrame.title.SetText then
            ns.cooldownsFrame.title:SetText(cdTitle)
        end
    end
    ns.cooldownsFrame.noItemsKeep = (DH.GetSetting and DH:GetSetting("cooldowns_hide_empty")) ~= true
    local n = (DH.GetSetting and DH:GetSetting("cooldowns_num_icons")) or 3
    RenderExtra(ns.cooldownsFrame, GetCooldownItems(), n)
    do
        local op = tonumber(DH.GetSetting and DH:GetSetting("opacity_cooldowns")) or 1
        if op < 0.15 then
            op = 0.15
        elseif op > 1 then
            op = 1
        end
        if not ns.cooldownsFrame.isMoving then
            if ns.FadeShow then
                ns.FadeShow(ns.cooldownsFrame, 0.16, op)
            else
                ns.cooldownsFrame:SetAlpha(op)
            end
        end
    end
    if ns.ApplyWindowTint and ns.GetWindowTint("cooldowns") then
        ns.ApplyWindowTint(ns.cooldownsFrame, "cooldowns")
    end
end

-- Interrupt spell per class (phase 2.3). Class modules may override with
-- ns.RegisterInterrupts(spellId); otherwise this fallback table is used.
-- 3.3.5a Paladin has no true interrupt (Rebuke is 4.0+).
local INTERRUPT_FALLBACK = {
    MAGE = 2139, -- Counterspell
    WARLOCK = 19647, -- Spell Lock (Felhunter)
    PRIEST = 15487, -- Silence
    ROGUE = 1766, -- Kick
    WARRIOR = 6552, -- Pummel
    DEATHKNIGHT = 47528, -- Mind Freeze
    SHAMAN = 57994, -- Wind Shear
    HUNTER = 34490, -- Silencing Shot
    DRUID = 8983, -- Bash
}

ns.interruptSpell = ns.interruptSpell or {}
function ns.RegisterInterrupts(spellId)
    ns.interruptSpell[DH.playerClass] = spellId
end

ns.interruptFrame = nil
local function GetInterruptItem()
    local casting = UnitCastingInfo and UnitCastingInfo("target")
    local channeling = (not casting) and UnitChannelInfo and UnitChannelInfo("target")
    if not casting and not channeling then
        return nil
    end
    local spellId = ns.interruptSpell[DH.playerClass] or INTERRUPT_FALLBACK[DH.playerClass]
    if not spellId then
        return nil
    end
    local name, _, texture = GetSpellInfo(spellId)
    local remaining = GetSpellRemains(spellId)
    return {
        {
            id = spellId,
            texture = texture,
            name = name,
            remaining = remaining,
            ready = remaining <= 0,
        },
    }
end

function ns.UpdateInterruptsFrame()
    if ns.playerDead then
        if ns.interruptFrame then
            ns.interruptFrame:Hide()
        end
        return
    end
    local show = (DH.GetSetting and DH:GetSetting("show_interrupts_display")) == true
    if not DH.db or not DH.db.enabled or (not show and not ns.moveMode) then
        if ns.interruptFrame then
            ns.interruptFrame:Hide()
        end
        return
    end
    if not ns.interruptFrame then
        local title = (DH.L and DH.L["Interrupt"]) or "Interrupt"
        ns.interruptFrame =
            CreateExtraFrame("InterruptsFrame", title, "interrupts_position", 170, -250, "interrupts_scale")
        ns.interruptFrame.refresh = ns.UpdateInterruptsFrame
    end
    EnsureExtraTicker(ns.interruptFrame)
    local items = GetInterruptItem()
    -- Interrupt-ready sound: play once when the kick comes off cooldown.
    do
        local spellId = ns.interruptSpell[DH.playerClass] or INTERRUPT_FALLBACK[DH.playerClass]
        if spellId then
            local rem = GetSpellRemains(spellId)
            if
                (DH.GetSetting and DH:GetSetting("interrupt_ready_sound")) == true
                and ns._interruptCdPrev
                and ns._interruptCdPrev > 0.2
                and rem <= 0
            then
                local file = ns.ResolveSound and ns.ResolveSound("default") or nil
                if type(PlaySoundFile) == "function" then
                    pcall(PlaySoundFile, file or "Sound\\Interface\\ReadyCheck.wav")
                end
            end
            ns._interruptCdPrev = rem
        end
    end
    -- Keep the window visible out of combat (and while configuring) so the
    -- interrupt spell is always visible and the tickbox takes visible effect.
    local always = (DH.GetSetting and DH:GetSetting("interrupts_always_show")) == true or show or ns.configMode
    if (not items or #items == 0) and always then
        -- Keep the window visible off-combat: show the interrupt spell idle/ready.
        local spellId = ns.interruptSpell[DH.playerClass] or INTERRUPT_FALLBACK[DH.playerClass]
        if spellId then
            local name, _, texture = GetSpellInfo(spellId)
            local remaining = GetSpellRemains(spellId)
            items = { { id = spellId, texture = texture, name = name, remaining = remaining, ready = remaining <= 0 } }
        end
    end
    ns.interruptFrame.noItemsKeep = always or nil
    RenderExtra(ns.interruptFrame, items, 1)
    do
        local op = tonumber(DH.GetSetting and DH:GetSetting("opacity_interrupts")) or 1
        if op < 0.15 then
            op = 0.15
        elseif op > 1 then
            op = 1
        end
        if not ns.interruptFrame.isMoving then
            if ns.FadeShow then
                ns.FadeShow(ns.interruptFrame, 0.16, op)
            else
                ns.interruptFrame:SetAlpha(op)
            end
        end
    end
    if ns.ApplyWindowTint and ns.GetWindowTint("interrupts") then
        ns.ApplyWindowTint(ns.interruptFrame, "interrupts")
    end
end

-- Boss-timeline window (phase + upcoming DBM/BigWigs timers). Text rows, so it
-- is built on top of CreateExtraFrame (which handles drag/position/scale) but
-- renders font strings instead of icon slots.
ns.timelineFrame = nil
local TL_ROWS = 8
local function CollectTimelineRows()
    local rows = {}
    local tl = ns.GetBossTimeline and ns.GetBossTimeline()
    if tl then
        rows[#rows + 1] = { text = string.format(L("Phase %d"), tonumber(tl.phase) or 1), r = 1, g = 0.82, b = 0 }
        local now = GetTime()
        local timers = {}
        for _, t in ipairs(tl.timers or {}) do
            if t.expires and t.expires > now then
                timers[#timers + 1] = t
            end
        end
        table.sort(timers, function(a, b)
            return a.expires < b.expires
        end)
        for _, t in ipairs(timers) do
            local secs = math.max(0, math.floor(t.expires - now + 0.5))
            rows[#rows + 1] = {
                text = string.format("%s  %ds", tostring(t.text or ""), secs),
                exp = t.expires,
                total = t.duration or 30,
                r = t.burst and 1 or 0.85,
                g = t.burst and 0.2 or 0.85,
                b = t.burst and 0.2 or 0.85,
            }
        end
    end
    local latest = ns.GetLatestPhaseText and ns.GetLatestPhaseText(12)
    if latest then
        rows[#rows + 1] = { text = latest, r = 0.6, g = 0.8, b = 1 }
    end
    return rows
end

function ns.UpdateTimelineFrame()
    if ns.playerDead then
        if ns.timelineFrame then
            ns.timelineFrame:Hide()
        end
        return
    end
    local show = (DH.GetSetting and DH:GetSetting("show_timeline_display")) == true
    if not DH.db or not DH.db.enabled or (not show and not ns.moveMode) then
        if ns.timelineFrame then
            ns.timelineFrame:Hide()
        end
        return
    end
    if not ns.timelineFrame then
        local title = (DH.L and DH.L["Boss timeline"]) or "Boss timeline"
        local f = CreateExtraFrame("TimelineFrame", title, "timeline_position", 0, 200, "timeline_scale")
        f.refresh = ns.UpdateTimelineFrame
        f.rows = {}
        f.bars = {}
        for i = 1, TL_ROWS do
            local bar = f:CreateTexture(nil, "BACKGROUND", nil, -1)
            bar:SetTexture("Interface\\Buttons\\WHITE8X8")
            bar:SetVertexColor(0.9, 0.65, 0.2, 0.35)
            bar:Hide()
            f.bars[i] = bar
            local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetJustifyH("LEFT")
            fs:SetShadowOffset(1, -1)
            f.rows[i] = fs
        end
        f.baseFont = select(1, f.rows[1]:GetFont())
        f.baseTitleFont = f.title and select(1, f.title:GetFont()) or nil
        ns.timelineFrame = f
    end
    local f = ns.timelineFrame
    local rows = CollectTimelineRows()
    if #rows == 0 and not ns.moveMode then
        f:Hide()
        return
    end
    if #rows == 0 then
        rows = { { text = L("Waiting for boss timers..."), r = 0.7, g = 0.7, b = 0.7 } }
    end

    -- Size is applied to the contents (not the frame) exactly like the cooldown
    -- and interrupt windows, so the timeline window stays a normal, freely
    -- draggable frame instead of a scaled one that "sticks" to the centre.
    local tscale = (DH.GetSetting and DH:GetSetting("timeline_scale")) or 1
    if tscale < 0.5 then
        tscale = 0.5
    elseif tscale > 2.5 then
        tscale = 2.5
    end
    local rowH = math.max(11, math.floor(14 * tscale + 0.5))
    local rowW = math.max(120, math.floor(240 * tscale + 0.5))
    local rowFont = math.max(8, math.floor(11 * tscale + 0.5))
    local titleH = math.max(12, math.floor(TITLE_H * tscale + 0.5))
    if f.baseTitleFont and f.title then
        f.title:SetFont(f.baseTitleFont, rowFont + 1, "")
    end

    local maxW = (f.title and f.title:GetStringWidth() or 60)
    local nrows = #rows
    local useBars = (DH.GetSetting and DH:GetSetting("timeline_bars_enabled")) ~= false
    local now = GetTime()
    for i = 1, TL_ROWS do
        local fs = f.rows[i]
        local bar = f.bars and f.bars[i]
        local row = rows[i]
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -titleH - 6 - (i - 1) * rowH)
        fs:SetWidth(rowW)
        if f.baseFont then
            fs:SetFont(f.baseFont, rowFont, "")
        end
        if row then
            fs:SetText(row.text)
            fs:SetTextColor(row.r or 1, row.g or 1, row.b or 1)
            fs:Show()
            local w = (fs:GetStringWidth() or 0)
            if w > maxW then
                maxW = w
            end
            if bar then
                if useBars and row.exp then
                    local frac = math.min(1, math.max(0, (row.exp - now) / (row.total or 30)))
                    bar:ClearAllPoints()
                    bar:SetPoint("TOPLEFT", fs, "TOPLEFT", 0, 2)
                    bar:SetSize(math.max(2, (rowW or 200) * frac), math.max(6, rowH - 4))
                    bar:Show()
                else
                    bar:Hide()
                end
            end
        else
            fs:SetText("")
            fs:Hide()
            if bar then
                bar:Hide()
            end
        end
    end
    if not f.isMoving then
        f:SetSize(math.max(maxW + 24, 150), titleH + nrows * rowH + 14)
        ApplyExtraPosition(f)
    end
    do
        local op = tonumber(DH.GetSetting and DH:GetSetting("opacity_timeline")) or 1
        if op < 0.15 then
            op = 0.15
        elseif op > 1 then
            op = 1
        end
        if not f.isMoving then
            if ns.FadeShow then
                ns.FadeShow(f, 0.16, op)
            else
                f:SetAlpha(op)
            end
        end
    end
    if ns.ApplyWindowTint and ns.GetWindowTint("timeline") then
        ns.ApplyWindowTint(f, "timeline")
    end
    f:Show()
end

-- Shared with SpellFrame.lua (reset / refresh / diagnostics).
ns.ApplyExtraPosition = ApplyExtraPosition
ns.GetCooldownItems = GetCooldownItems
