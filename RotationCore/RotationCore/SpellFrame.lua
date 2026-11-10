-- SpellFrame.lua
-- MaxDps-style window with the next ability icons (3.3.5a, no dependencies)
--
-- Shows the same picks as the action bar glow:
--   priority 1 = green (press now), 2 = yellow (next), 3 = blue (after that)
-- The window is draggable, the position is saved per profile.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

local function L(s)
    if type(s) ~= "string" then
        return s
    end
    local tbl = DH.L
    if tbl and tbl[s] then
        return tbl[s]
    end
    return s
end

local MAX_SLOTS = 10
local BASE_ICON = 36
local GAP = 4
local TITLE_H = 24
local FRAME_PAD_X = 8
local FRAME_PAD_BOTTOM = 8
ns.FRAME_TITLE_H = TITLE_H
ns.FRAME_PAD_X = FRAME_PAD_X
ns.FRAME_PAD_BOTTOM = FRAME_PAD_BOTTOM
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"

local FALLBACK_STYLE = {
    [1] = { r = 0.15, g = 1.00, b = 0.15 },
    [2] = { r = 1.00, g = 0.85, b = 0.10 },
    [3] = { r = 0.25, g = 0.60, b = 1.00 },
}

-- Shared by the full render and the lightweight ticker below. The full render
-- still owns names/layout; the ticker only refreshes the countdown text so the
-- numbers move smoothly instead of jumping at the recommendation poll rate.
local function UpdateCooldownText(slot, index, spellId, showTime, showGCD)
    if not slot or not slot.cd then
        return
    end
    local id = spellId or slot.tipId
    if showTime == nil then
        showTime = (DH.GetSetting and DH:GetSetting("show_time")) ~= false
    end
    if showGCD == nil then
        showGCD = (DH.GetSetting and DH:GetSetting("show_gcd_timer")) ~= false
    end
    local remains = 0
    if showTime and id and type(GetSpellCooldown) == "function" then
        local start, duration = GetSpellCooldown(id)
        if start and duration and duration > 0 then
            remains = (start + duration) - GetTime()
            if remains < 0 then
                remains = 0
            end
        end
    end
    local gcdRem = 0
    if index == 1 and showGCD then
        local st = DH.State
        local start = st and st._gcd_start
        if start and start > 0 then
            gcdRem = math.max(0, start + (st.gcd or 1.5) - GetTime())
        end
    end
    if remains > 0.05 then
        if remains >= 10 then
            slot.cd:SetText(string.format("%d", math.ceil(remains)))
        else
            slot.cd:SetText(string.format("%.1f", remains))
        end
    elseif index == 1 and gcdRem > 0.05 then
        slot.cd:SetText(string.format("%.1f", gcdRem))
    else
        slot.cd:SetText("")
    end
end

-- Horizontal means one row, regardless of legacy icon_columns values. Vertical
-- means one column. Shared by the fixed-size and render paths.
function ns.GetQueueColumns(orientation, showCount)
    if orientation == "vertical" then
        return 1
    end
    return math.max(1, tonumber(showCount) or 1)
end

local frame
local slots = {}
ns.moveMode = false -- /rc move: show labelled boxes and live coordinates

-- ============================================================================
-- PROMPT 3.2: animated transitions (appear / crossfade / disappear).
-- Each slot keeps its own alpha; a temporary OnUpdate drives the tween and is
-- removed when the tween ends, so idle slots pay nothing. Transitions are
-- skipped when the setting is off, when the window is refreshed very often
-- (busy CPU) and when icons change faster than RAPID_CHANGE.
-- ============================================================================
local ANIM_IN, ANIM_CROSS, ANIM_OUT = 0.18, 0.12, 0.15
local ANIM_MOVE = 0.16
-- The rotation is polled at ~5 Hz by default (0.2 s). The old 0.30 s guard
-- treated every normal queue change as "rapid" and snapped the icon, which
-- looked jarring; only really fast (>16 Hz) churn skips the tween now.
local RAPID_CHANGE = 0.06

local function AnimEnabled()
    return (DH.GetSetting and DH:GetSetting("animations_enabled")) ~= false
end

local function AnimSpeed()
    local s = (DH.GetSetting and DH:GetSetting("animation_speed")) or 1.0
    if type(s) ~= "number" or s <= 0 then
        s = 1.0
    end
    if s < 0.5 then
        s = 0.5
    elseif s > 2.0 then
        s = 2.0
    end
    return s
end

-- True while the window is being refreshed more than ~25 times a second:
-- the transitions are skipped so a heavy fight cannot be made heavier.
-- Time-based only (no extra API calls).
local function UIUnderLoad()
    local rate = ns._spellFrameRate
    return type(rate) == "number" and rate > 25
end

local function StopSlotAnim(slot)
    if slot.animActive then
        slot:SetScript("OnUpdate", nil)
        slot.animActive = false
    end
end

local function SnapSlot(slot)
    StopSlotAnim(slot)
    slot.alpha = 1
    slot:SetAlpha(1)
    if slot.icon then
        slot.icon:SetAlpha(1)
    end
    if slot.iconPrev then
        slot.iconPrev:SetAlpha(0)
    end
    slot:Show()
end

local function UpdateSlotMove(slot, dt)
    if not slot.moveActive then
        return
    end
    slot.moveElapsed = (slot.moveElapsed or 0) + dt
    local dur = slot.moveDur or ANIM_MOVE
    local t = dur > 0 and (slot.moveElapsed / dur) or 1
    if t > 1 then
        t = 1
    end
    local ease = t * t * (3 - 2 * t)
    local x = slot.moveFromX + (slot.moveToX - slot.moveFromX) * ease
    local y = slot.moveFromY + (slot.moveToY - slot.moveFromY) * ease
    if frame then
        slot:SetPoint("BOTTOM", frame, "BOTTOM", x, y)
    end
    if t >= 1 then
        slot.moveActive = false
    end
end

local function UpdateSlotAnim(slot, elapsed)
    slot.animElapsed = (slot.animElapsed or 0) + elapsed
    local dur = slot.animDur or 0
    local t = dur > 0 and (slot.animElapsed / dur) or 1
    if t > 1 then
        t = 1
    end
    local from = slot.animFrom or 1
    local a = from + ((slot.animTarget or 1) - from) * t
    slot.alpha = a
    if slot.animCross then
        -- Crossfade: the new icon fades in on top of the outgoing one.
        if slot.icon then
            slot.icon:SetAlpha(a)
        end
        if slot.iconPrev then
            slot.iconPrev:SetAlpha(1 - a)
        end
        slot:SetAlpha(1)
    else
        slot:SetAlpha(a)
        if slot.icon then
            slot.icon:SetAlpha(1)
        end
        if slot.iconPrev then
            slot.iconPrev:SetAlpha(0)
        end
    end
    if t >= 1 then
        StopSlotAnim(slot)
        slot.alpha = slot.animTarget
        if slot.animTarget and slot.animTarget <= 0 then
            slot:Hide()
        end
    end
end

local function StartSlotAnim(slot, target, dur, cross)
    slot.animFrom = slot.alpha or 1
    slot.animTarget = target
    slot.animDur = dur
    slot.animElapsed = 0
    slot.animCross = cross and true or false
    if not slot.animActive then
        slot.animActive = true
        slot:SetScript("OnUpdate", UpdateSlotAnim)
    end
end

-- ============================================================================
-- KEYBIND OVERLAY (phase 1.1)
-- Map action-bar binding -> the spell on that slot, cached and rebuilt only
-- when the bars/bindings change (ACTIONBAR_SLOT_CHANGED, UPDATE_BINDINGS...).
-- ============================================================================

local keybindCache = {}
local keybindDirty = true

-- WotLK 3.3.5a action-bar slot -> binding name:
--   1-12   ACTIONBUTTON          (main bar)
--   13-24  MULTIACTIONBAR1BUTTON (bottom-left)
--   25-36  MULTIACTIONBAR2BUTTON (bottom-right)
--   37-48  MULTIACTIONBAR3BUTTON (right, first)
--   49-60  MULTIACTIONBAR4BUTTON (right, second)
--   61-72  BONUSACTIONBUTTON     (vehicle / possession)
--   >72    no rebindable key
local function KeybindActionName(slot)
    if slot <= 12 then
        return "ACTIONBUTTON" .. slot
    elseif slot <= 24 then
        return "MULTIACTIONBAR1BUTTON" .. (slot - 12)
    elseif slot <= 36 then
        return "MULTIACTIONBAR2BUTTON" .. (slot - 24)
    elseif slot <= 48 then
        return "MULTIACTIONBAR3BUTTON" .. (slot - 36)
    elseif slot <= 60 then
        return "MULTIACTIONBAR4BUTTON" .. (slot - 48)
    elseif slot <= 72 then
        return "BONUSACTIONBUTTON" .. (slot - 60)
    end
    return nil
end

-- "SHIFT-2" -> "S2", "CTRL-F" -> "CF", "ALT-BUTTON5" -> "A5"
local function FormatBinding(key)
    if not key or key == "" then
        return nil
    end
    key = key:gsub("CTRL%-", "C"):gsub("SHIFT%-", "S"):gsub("ALT%-", "A")
    key = key:gsub("NUMPAD", "N"):gsub("BUTTON", ""):gsub("%-", "")
    return key
end

local function BuildKeybindCache()
    keybindCache = {}
    keybindDirty = false
    if type(GetActionInfo) ~= "function" or type(GetBindingKey) ~= "function" then
        return
    end
    -- Only slots 1..72 have rebindable keys (see KeybindActionName); scanning
    -- further is wasted GetActionInfo/GetBindingKey work (L4).
    for slot = 1, 72 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id and not keybindCache[id] then
            keybindCache[id] = FormatBinding(GetBindingKey(KeybindActionName(slot)))
        end
    end
end

-- Returns the display string for a spell id (nil when unbound)
function ns.GetSpellKeybind(spellId)
    if not spellId then
        return nil
    end
    if keybindDirty then
        BuildKeybindCache()
    end
    return keybindCache[spellId]
end

function ns.InvalidateKeybinds()
    keybindDirty = true
end

local kbFrame = CreateFrame("Frame")
kbFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
kbFrame:RegisterEvent("UPDATE_BINDINGS")
kbFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
kbFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
kbFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
kbFrame:SetScript("OnEvent", function(self, event)
    ns.InvalidateKeybinds()
    if event == "PLAYER_REGEN_DISABLED" then
        ns.spellFrameDoubleHidden = false
    end
end)

local function GetStyle(prio)
    local styles = ns.PRIORITY_STYLE or FALLBACK_STYLE
    return styles[prio] or styles[1]
end

-- Position table for the window: shared, or per-spec when
-- spellFrame_pos_per_spec is enabled (created on demand)
local function GetPosTable()
    if not DH.db then
        return nil
    end
    if DH.GetSetting and DH:GetSetting("spellFrame_pos_per_spec") then
        if not DH.db.spellFrame_per_spec then
            DH.db.spellFrame_per_spec = {}
        end
        local mode = DH.GetActiveMode and DH:GetActiveMode()
        local key = mode and mode.key or "default"
        if not DH.db.spellFrame_per_spec[key] then
            local src = DH.db.spellFrame or { x = 0, y = -250 }
            DH.db.spellFrame_per_spec[key] = { x = src.x, y = src.y }
        end
        return DH.db.spellFrame_per_spec[key]
    end
    return DH.db.spellFrame
end

local function SavePosition()
    if not frame then
        return
    end
    local pos = GetPosTable()
    if not pos then
        return
    end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    pos.x = cx - ux
    pos.y = cy - uy
    -- Manually moving a window means the layout is no longer a preset.
    if DH.SetSetting then
        DH:SetSetting("display_layout", "custom")
    end
end

local function ApplyPosition()
    local db = GetPosTable()
    frame:ClearAllPoints()
    if db and db.x and db.y then
        frame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -250)
    end
end

-- Adds a small label at the bottom of a movable frame. While the frame is
-- being dragged it shows live coordinates; otherwise the caller-settable name.
local function AttachMoveOverlay(f, showCoords)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
    fs:SetJustifyH("CENTER")
    fs:SetTextColor(1, 0.82, 0)
    fs:SetShadowOffset(1, -1)
    fs:Hide()
    f.moveText = fs
    f.moveShowCoords = showCoords ~= false
    -- Installed only while dragging (OnDragStart/OnDragStop) so idle frames
    -- do not pay for a per-frame script (L2).
    f.moveUpdate = function(self, elapsed)
        if not self.moveText then
            return
        end
        self.moveTextElapsed = (self.moveTextElapsed or 0) + (elapsed or 0)
        if self.moveTextElapsed < 0.05 then
            return
        end
        self.moveTextElapsed = 0
        if not self.moveText:IsShown() then
            self.moveText:Show()
        end
        if self.moveShowCoords == false then
            self.moveText:SetText(self.moveLabel or "")
            return
        end
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux and cy and uy then
            self.moveText:SetText(
                string.format("%s   %d, %d", self.moveLabel or "", math.floor(cx - ux + 0.5), math.floor(cy - uy + 0.5))
            )
        end
    end
end

ns.AttachMoveOverlay = AttachMoveOverlay

-- ============================================================================
-- WINDOW CONTROLS: wheel = scale, double-click = hide, resize grip
-- ============================================================================

local EnsureFrame -- forward declaration (defined below)

local function ClampScale(v)
    if v < 0.5 then
        v = 0.5
    elseif v > 2.5 then
        v = 2.5
    end
    return math.floor(v * 10 + 0.5) / 10
end

-- Safe accessor for the profile-scoped display table: a corrupt or partially
-- migrated profile may lack it. Returns nil when the DB is not ready.
local function Display()
    if not DH.db then
        return nil
    end
    if not DH.db.display then
        DH.db.display = {}
    end
    return DH.db.display
end

EnsureFrame = function()
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", "RotationCoreSpellFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame.isMoving = false
    frame:Hide()

    -- Window controls: wheel = scale, double-click = hide
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        local d = Display()
        if not d then
            return
        end
        d.spellframe_scale = ClampScale((d.spellframe_scale or 1) + (delta > 0 and 0.1 or -0.1))
        DH:UpdateUI()
        DH:NotifyOptions()
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and not ns.configMode then
            local now = GetTime()
            if self.lastClick and (now - self.lastClick) < 0.35 then
                self.lastClick = nil
                ns.spellFrameDoubleHidden = true
                self:Hide()
            else
                self.lastClick = now
            end
        end
    end)

    -- v3.4.0: visible resize grip for the primary window (adjusts scale).
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    local grow = false
    local function GripUpdate()
        if not grow then
            return
        end
        local _, cy = GetCursorPosition()
        local d = Display()
        if not d then
            return
        end
        d.spellframe_scale = ClampScale((d.spellframe_scale or 1) + (grow.y - cy) / (grow.scale or 1) / 90)
        DH:UpdateUI()
        DH:NotifyOptions()
    end
    grip:SetScript("OnMouseDown", function()
        local _, cy = GetCursorPosition()
        grow = { y = cy, scale = UIParent:GetScale() or 1 }
        grip:SetScript("OnUpdate", GripUpdate)
    end)
    grip:SetScript("OnMouseUp", function()
        grow = nil
        grip:SetScript("OnUpdate", nil)
    end)
    frame.grip = grip

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    do
        local th = (DH.GetUITheme and DH:GetUITheme()) or { backdrop = { 0, 0, 0, 0.85 } }
        frame:SetBackdropColor(th.backdrop[1], th.backdrop[2], th.backdrop[3], th.backdrop[4] or 0.85)
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -5)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetText("RotationCore")
    if ns.ApplyWindowChrome then
        ns.ApplyWindowChrome(frame)
    end
    if ns.ApplyFont then
        ns.ApplyFont(frame.title)
    end

    -- Idle reason (phase 1.2): shown instead of the icons when nothing is
    -- recommended, so the player knows why the window is empty.
    frame.reason = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.reason:SetPoint("TOP", frame, "TOP", 0, -22)
    frame.reason:SetWidth(160)
    frame.reason:SetJustifyH("CENTER")
    frame.reason:SetTextColor(0.9, 0.9, 0.9)
    frame.reason:Hide()

    -- Boss timeline hint (prompt 3.3): "Hold CD / Prepare / BURST in Ns".
    frame.timeline = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.timeline:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -18)
    frame.timeline:SetJustifyH("RIGHT")
    frame.timeline:SetTextColor(1, 0.82, 0)
    frame.timeline:Hide()

    -- v3.3.0 phase 2: live DPS forecast above the window.
    frame.dpsForecast = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.dpsForecast:SetPoint("BOTTOM", frame, "TOP", 0, 4)
    frame.dpsForecast:SetJustifyH("CENTER")
    frame.dpsForecast:SetTextColor(0.85, 0.9, 1.0)
    frame.dpsForecast:Hide()

    -- v3.3.0 phase 2: class pulse indicator left of the window.
    frame.pulse = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.pulse:SetPoint("RIGHT", frame, "LEFT", -6, 0)
    frame.pulse:SetJustifyH("RIGHT")
    frame.pulse:Hide()

    -- v3.4.0: battle-phase + combat-forecast indicators below the window.
    frame.phase = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.phase:SetPoint("TOP", frame, "BOTTOM", 0, -16)
    frame.phase:SetJustifyH("CENTER")
    frame.phase:SetTextColor(1, 0.82, 0)
    frame.phase:Hide()

    frame.forecast = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.forecast:SetPoint("TOP", frame, "BOTTOM", 0, -32)
    frame.forecast:SetJustifyH("CENTER")
    frame.forecast:SetTextColor(0.85, 0.9, 1.0)
    frame.forecast:Hide()

    -- Target-mode indicator (phase 1.5): S / A / Au, click to cycle
    local modeBtn = CreateFrame("Button", nil, frame)
    modeBtn:SetSize(26, 14)
    modeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -4)
    modeBtn:SetFrameLevel(frame:GetFrameLevel() + 4)
    modeBtn.text = modeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeBtn.text:SetAllPoints()
    modeBtn.text:SetJustifyH("CENTER")
    modeBtn.text:SetTextColor(0.4, 1, 0.4)
    modeBtn:SetScript("OnClick", function()
        local cur = (DH.GetSetting and DH:GetSetting("target_mode")) or "auto"
        local nextMode = (cur == "single" and "aoe") or (cur == "aoe" and "auto") or "single"
        if DH.SetSetting then
            DH:SetSetting("target_mode", nextMode)
        end
        if DH.UpdateRecommendations then
            DH:UpdateRecommendations()
        end
    end)
    modeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L("Target mode"))
        GameTooltip:AddLine(L("Click to cycle Single / AOE / Auto"), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    modeBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame.modeButton = modeBtn

    for i = 1, MAX_SLOTS do
        local slot = CreateFrame("Frame", nil, frame)
        slot:SetFrameLevel(frame:GetFrameLevel() + 2)

        -- Outgoing texture used only for the crossfade animation (3.2). It is
        -- created before the main icon so the icon draws on top of it.
        slot.iconPrev = slot:CreateTexture(nil, "ARTWORK")
        slot.iconPrev:SetAllPoints()
        slot.iconPrev:SetAlpha(0)

        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetAllPoints()

        -- Soft priority backdrop behind the icon (subtle, priority-tinted).
        slot.bg = slot:CreateTexture(nil, "BACKGROUND")
        slot.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        slot.bg:SetPoint("TOPLEFT", slot, "TOPLEFT", -3, 3)
        slot.bg:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 3, -3)
        slot.bg:SetAlpha(0.22)
        slot.topline = slot:CreateTexture(nil, "OVERLAY", nil, 1)
        slot.topline:SetTexture("Interface\\Buttons\\WHITE8X8")
        slot.topline:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
        slot.topline:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)
        slot.topline:SetHeight(2)

        slot.border = slot:CreateTexture(nil, "OVERLAY")
        slot.border:SetTexture(GLOW_TEXTURE)
        slot.border:SetBlendMode("ADD")

        slot.num = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slot.num:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 4, 4)
        slot.num:SetTextColor(1, 1, 1)
        slot.num:SetShadowOffset(1, -1)

        -- Keybind overlay (phase 1.1): the action-bar binding for this spell
        slot.keybind = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slot.keybind:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
        slot.keybind:SetTextColor(1, 0.82, 0)
        slot.keybind:SetShadowOffset(1, -1)

        -- Cooldown countdown (shown on REC1 when the spell is on cooldown)
        slot.cd = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        slot.cd:SetPoint("CENTER")
        slot.cd:SetTextColor(1, 1, 1)
        slot.cd:SetShadowOffset(1, -1)

        slot:EnableMouse(true)
        -- Per-icon tooltip (name / reason / cooldown). Data is filled by
        -- UpdateSpellFrame (slot.tipName / tipId / tipReason).
        slot:SetScript("OnEnter", function(self)
            if not self.tipName and not self.tipId then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.tipId then
                GameTooltip:SetHyperlink("spell:" .. self.tipId)
            else
                GameTooltip:SetText(self.tipName or "", 1, 1, 1)
            end
            if self.tipReason then
                GameTooltip:AddLine(self.tipReason, 0.9, 0.9, 0.9, true)
            end
            if self.tipId and type(GetSpellCooldown) == "function" then
                local start, duration = GetSpellCooldown(self.tipId)
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
        slot:Hide()
        slots[i] = slot
    end

    -- Countdown ticker: parented to the window, so it only runs while the
    -- window is shown. 30 Hz is enough for a smooth tenths display and costs
    -- less than repainting the whole queue every frame.
    local cdTicker = CreateFrame("Frame", nil, frame)
    cdTicker:SetAllPoints(frame)
    cdTicker:Show()
    cdTicker.elapsed = 0
    cdTicker:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.03 then
            return
        end
        local step = self.elapsed
        self.elapsed = 0
        local showTime = (DH.GetSetting and DH:GetSetting("show_time")) ~= false
        local showGCD = (DH.GetSetting and DH:GetSetting("show_gcd_timer")) ~= false
        for i = 1, MAX_SLOTS do
            local slot = slots[i]
            if slot and slot:IsShown() then
                UpdateCooldownText(slot, i, nil, showTime, showGCD)
                UpdateSlotMove(slot, step)
            end
        end
    end)
    frame.cdTicker = cdTicker

    frame:SetScript("OnDragStart", function(self)
        -- v3.4.0-hotfix6: windows are movable by default; lock via /rc lock
        -- or the "Lock windows" option. Dragging over an icon slot is blocked
        -- (slots enable the mouse), so the click still casts.
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
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.isMoving = false
        if self.moveText then
            self.moveText:Hide()
        end
        if ns.configMode and ns.SnapToGrid then
            ns.SnapToGrid(self)
        end
        SavePosition()
        if SetCursor then
            SetCursor(nil)
        end
    end)

    frame:SetScript("OnEnter", function(self)
        -- No custom cursor here. On 3.3.5a SetCursor() treats an unknown string
        -- as a texture path; "UI_CURSOR_HAND" does not exist, and a non-existent
        -- path HIDES the cursor (WoWWiki API_SetCursor). Use the default arrow.
        if not self.lines or #self.lines == 0 then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for i = 1, #self.lines do
            if i == 1 then
                GameTooltip:AddLine(self.lines[i], 1, 1, 1)
            else
                GameTooltip:AddLine(i .. ". " .. self.lines[i], 0.9, 0.9, 0.9)
            end
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if SetCursor then
            SetCursor(nil)
        end
    end)
    frame:SetScript("OnHide", function()
        -- Safety: if the window is hidden (or move-mode ends) while the mouse is
        -- over it, OnLeave never fires; reset the cursor so it never sticks.
        if SetCursor then
            SetCursor(nil)
        end
    end)

    AttachMoveOverlay(frame)

    -- Apply the saved position immediately, even before the first show, so a
    -- window that was hidden when the player logged out reappears correctly.
    ApplyPosition()

    ns.SpellFrame = frame
    return frame
end

-- Phase 1.5: S / A / Au indicator on the window title
local function UpdateModeIndicator()
    if not frame or not frame.modeButton then
        return
    end
    if (DH.GetSetting and DH:GetSetting("show_mode_indicator")) == false then
        frame.modeButton:Hide()
        return
    end
    local tm = (DH.GetSetting and DH:GetSetting("target_mode")) or "auto"
    local label = (tm == "aoe" and "A") or (tm == "auto" and "Au") or "S"
    frame.modeButton.text:SetText(label)
    frame.modeButton:Show()
end

local function HideWindow()
    if frame then
        frame:Hide()
        frame.lines = {}
        if frame.reason then
            frame.reason:Hide()
        end
        if frame.timeline then
            frame.timeline:Hide()
        end
        if frame.dpsForecast then
            frame.dpsForecast:Hide()
        end
        if frame.pulse then
            frame.pulse:Hide()
        end
        for i = 1, MAX_SLOTS do
            if slots[i] then
                StopSlotAnim(slots[i])
            end
        end
    end
end

-- Public: force-hide the primary window (used when the addon is disabled)
function ns.HideSpellFrame()
    HideWindow()
end

-- Phase 1.2: show the icon window with a one-line reason instead of the icons
-- Fixed window size derived only from the configured icon count / size, so the
-- window keeps its size and proportions whether or not there are picks / a
-- target. Used by both the idle placeholder and the active render.
local function ComputeFixedFrameSize(shownCount)
    local scale = (DH.db and DH.db.display and DH.db.display.spellframe_scale) or 1
    local baseIcon = (DH.GetSetting and DH:GetSetting("icon_size")) or BASE_ICON
    local baseGap = (DH.GetSetting and DH:GetSetting("icon_gap")) or GAP
    local iconSize = math.max(16, math.floor(baseIcon * scale + 0.5))
    local gap = math.max(2, math.floor(baseGap * scale))
    local showCount = (DH.GetSpellFrameIconCount and DH:GetSpellFrameIconCount()) or 3
    showCount = math.max(1, math.min(showCount, MAX_SLOTS))
    local orientation = (DH.GetSetting and DH:GetSetting("orientation")) or "horizontal"
    local columns = ns.GetQueueColumns(orientation, showCount)
    local layoutCount = tonumber(shownCount) or showCount
    layoutCount = math.max(1, math.min(layoutCount, showCount, MAX_SLOTS))
    local rows = math.ceil(layoutCount / columns)
    local colCount = math.min(columns, layoutCount)
    -- Shared padding with the extras windows (cooldowns / interrupts / timeline).
    local w = colCount * iconSize + (colCount - 1) * gap + FRAME_PAD_X * 2
    local h = rows * iconSize + (rows - 1) * gap + TITLE_H + FRAME_PAD_BOTTOM
    local titleW = (frame and frame.title and frame.title.GetStringWidth and frame.title:GetStringWidth()) or 0
    local modeExtra = 0
    if frame and frame.modeButton and frame.modeButton:IsShown() then
        modeExtra = 30
    end
    w = math.max(w, titleW + 16 + modeExtra)
    h = math.max(h, TITLE_H + 30)
    return w, h
end

local function ShowIdle(reason)
    EnsureFrame()
    for i = 1, MAX_SLOTS do
        if slots[i] then
            StopSlotAnim(slots[i])
            slots[i]:Hide()
        end
    end
    frame.lines = {}
    frame.reason:SetText(reason or "")
    frame.reason:Show()
    if frame.timeline then
        frame.timeline:Hide()
    end
    if frame.dpsForecast then
        frame.dpsForecast:Hide()
    end
    if frame.pulse then
        frame.pulse:Hide()
    end
    UpdateModeIndicator()
    if not frame.isMoving then
        local fixedSize = (DH.GetSetting and DH:GetSetting("spellframe_fixed_size")) ~= false
        local w, h
        if fixedSize then
            w, h = ComputeFixedFrameSize(1)
        else
            w = math.max(frame.title:GetStringWidth() + 44, 150)
            h = TITLE_H + 30
        end
        frame.reason:SetWidth(w - FRAME_PAD_X * 2)
        frame:SetSize(w, h)
        ApplyPosition()
        frame:Show()
    end
end

-- Called from ns.UpdateUI() with the abilities that are currently shown
function ns.UpdateSpellFrame(recs)
    if ns.playerDead then
        if frame then
            frame:Hide()
        end
        return
    end
    -- v3.3.0: position the forecast / pulse labels around the window. Cached
    -- per label so we only re-point when the setting actually changes.
    local function AuxPoint(label, side)
        side = side or "above_spellframe"
        if label._side == side then
            return
        end
        label._side = side
        label:ClearAllPoints()
        if side == "below_spellframe" then
            label:SetPoint("TOP", frame, "BOTTOM", 0, -4)
        elseif side == "left_of_spellframe" then
            label:SetPoint("RIGHT", frame, "LEFT", -6, 0)
        elseif side == "right_of_spellframe" then
            label:SetPoint("LEFT", frame, "RIGHT", 6, 0)
        else
            label:SetPoint("BOTTOM", frame, "TOP", 0, 4)
        end
    end

    -- How often is the window refreshed? Used to skip the transitions under
    -- load (prompt 3.2). Time-based, so no extra API is touched.
    do
        local t = GetTime()
        ns._spellFrameCount = (ns._spellFrameCount or 0) + 1
        if not ns._spellFrameWindow or (t - ns._spellFrameWindow) >= 1 then
            ns._spellFrameWindow = t
            ns._spellFrameRate = ns._spellFrameCount
            ns._spellFrameCount = 0
        end
    end

    local db = DH.db
    if not db or not db.enabled or not db.display or not db.display.show_spellframe then
        HideWindow()
        return
    end

    -- Double-click temporarily hides the window; cleared at the next combat start
    if ns.spellFrameDoubleHidden and not ns.moveMode then
        HideWindow()
        return
    end

    -- Optional: hide the window out of combat (training mode still shows it)
    if
        (DH.GetSetting and DH:GetSetting("spellframe_combat_only"))
        and not (DH.GetSetting and DH:GetSetting("training_mode"))
        and UnitAffectingCombat
        and not UnitAffectingCombat("player")
    then
        HideWindow()
        return
    end

    -- New visibility toggles (parts 4/8): out of combat / no target.
    if
        (DH.GetSetting and DH:GetSetting("hide_out_of_combat"))
        and not (DH.GetSetting and DH:GetSetting("training_mode"))
        and UnitAffectingCombat
        and not UnitAffectingCombat("player")
    then
        HideWindow()
        return
    end
    if (DH.GetSetting and DH:GetSetting("hide_no_target")) and not UnitExists("target") then
        HideWindow()
        return
    end

    recs = recs or {}
    if #recs == 0 then
        -- /rc move: keep a labelled, positionable box even with no picks
        if ns.moveMode then
            frame.moveLabel = L("Primary")
            ShowIdle(L("Primary"))
            if frame.moveText then
                frame.moveText:SetText(L("Primary"))
                frame.moveText:Show()
            end
            return
        end
        -- Phase 1.2: explain the empty window instead of hiding it
        if DH.GetSetting and DH:GetSetting("hide_when_idle") then
            HideWindow()
            return
        end
        local showReason = (DH.GetSetting and DH:GetSetting("show_idle_reason")) ~= false
        local reason = showReason and DH.GetIdleReason and DH:GetIdleReason() or nil
        if not reason and not UnitExists("target") and not (DH.GetSetting and DH:GetSetting("hide_no_target")) then
            reason = L("No target")
        end
        if reason then
            ShowIdle(reason)
            if DH.GetSetting and DH:GetSetting("fade_when_idle") then
                frame:SetAlpha(0.4)
            else
                frame:SetAlpha(1)
            end
        else
            HideWindow()
        end
        return
    end

    EnsureFrame()
    if frame.SetAlpha then
        frame:SetAlpha(1)
    end
    -- Theme/chrome/font are relatively expensive frame calls; only apply them
    -- when one of the driving settings actually changes (was every tick).
    local chromeSig = (DH.GetSetting and DH:GetSetting("theme") or "")
        .. "|"
        .. tostring(DH.GetSetting and DH:GetSetting("show_background") ~= false)
        .. "|"
        .. tostring(DH.GetSetting and DH:GetSetting("show_border") ~= false)
        .. "|"
        .. tostring(DH.GetSetting and DH:GetSetting("show_title") ~= false)
        .. "|"
        .. tostring(DH.GetSetting and DH:GetSetting("spellframe_compact") == true)
        .. "|"
        .. (DH.GetSetting and DH:GetSetting("spellframe_font") or "")
    if frame._chromeSig ~= chromeSig then
        frame._chromeSig = chromeSig

        -- Theme (part 10): keep the title tint in sync with the setting.
        if DH.GetUITheme and frame.title and frame.title.SetTextColor then
            local th = DH:GetUITheme()
            frame.title:SetTextColor(th.title[1], th.title[2], th.title[3])
        end

        -- Queue-window chrome toggles: background / border / title.
        do
            local compact = (DH.GetSetting and DH:GetSetting("spellframe_compact")) == true
            local showBg = (not compact) and ((DH.GetSetting and DH:GetSetting("show_background")) ~= false)
            local showBorder = (not compact) and ((DH.GetSetting and DH:GetSetting("show_border")) ~= false)
            local showTitle = (not compact) and ((DH.GetSetting and DH:GetSetting("show_title")) ~= false)
            if frame.SetBackdropColor then
                local th = DH.GetUITheme and DH:GetUITheme() or nil
                local bg = th and th.backdrop or { 0, 0, 0, 0.85 }
                if showBg then
                    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.85)
                else
                    frame:SetBackdropColor(0, 0, 0, 0)
                end
            end
            if frame.SetBackdropBorderColor then
                local th = DH.GetUITheme and DH:GetUITheme() or nil
                local b = th and th.border or nil
                if showBorder and b then
                    frame:SetBackdropBorderColor(b[1], b[2], b[3], 1)
                else
                    frame:SetBackdropBorderColor(0, 0, 0, 0)
                end
            end
            if frame.title then
                if showTitle then
                    frame.title:Show()
                else
                    frame.title:Hide()
                end
            end
        end

        -- Apply the configured font (LSM name or raw path). The size setting,
        -- when set, overrides the template height.
        do
            local name = (DH.GetSetting and DH:GetSetting("spellframe_font"))
            local path = ns.ResolveFont and ns.ResolveFont(name) or nil
            if path then
                local _, h, flags = frame.title:GetFont()
                local size = tonumber(DH.GetSetting and DH:GetSetting("spellframe_font_size"))
                if not size or size < 6 then
                    size = h
                end
                frame.title:SetFont(path, size, flags)
                for i = 1, MAX_SLOTS do
                    if slots[i] then
                        slots[i].num:SetFont(path, size, flags)
                        slots[i].keybind:SetFont(path, size, flags)
                    end
                end
                frame.reason:SetFont(path, size, flags)
            end
        end
    end

    local scale = db.display.spellframe_scale or 1
    local baseIcon = (DH.GetSetting and DH:GetSetting("icon_size")) or BASE_ICON
    local baseGap = (DH.GetSetting and DH:GetSetting("icon_gap")) or GAP
    local iconSize = math.max(16, math.floor(baseIcon * scale + 0.5))
    local gap = math.max(2, math.floor(baseGap * scale))
    local borderSize = iconSize * math.min(2.0, math.max(1.0, db.display.glow_size or 1.5))

    -- v3.4.0-hotfix6: window width is fixed by the configured icon count so
    -- the frame does not jump when the number of recommendations changes.
    local showCount = (DH.GetSpellFrameIconCount and DH:GetSpellFrameIconCount()) or 3
    local maxShow = math.min(showCount, MAX_SLOTS, #recs)
    -- v3.3.0 exam mode: only REC1 is shown.
    if DH.GetSetting and DH:GetSetting("exam_mode") then
        maxShow = math.min(maxShow, 1)
    end
    local orientation = (DH.GetSetting and DH:GetSetting("orientation")) or "horizontal"
    local columns = ns.GetQueueColumns(orientation, showCount)
    local fixed = (DH.GetSetting and DH:GetSetting("spellframe_fixed_size")) ~= false
    -- Layout acts (width) vs draw (rows) counts.
    local layoutCount = fixed and math.max(1, math.min(showCount, MAX_SLOTS)) or maxShow
    local drawCount = math.max(1, math.min(maxShow, layoutCount))
    local rows = math.ceil(drawCount / columns)
    local totalH = rows * iconSize + (rows - 1) * gap
    local maxRowCols = math.min(columns, layoutCount)
    local maxRowW = maxRowCols * iconSize + (maxRowCols - 1) * gap

    frame.reason:Hide()
    UpdateModeIndicator()

    -- Boss timeline hint (prompt 3.3) / deep phase message: only when enabled.
    if frame.timeline then
        local hint, detail
        if (DH.GetSetting and DH:GetSetting("timeline_enabled")) and ns.GetTimelineHint then
            hint, detail = ns.GetTimelineHint()
        end
        if not hint and ns.GetLatestPhaseText then
            hint = ns.GetLatestPhaseText()
        end
        if hint then
            frame.timeline:SetText(detail and (hint .. "  " .. detail) or hint)
            frame.timeline:Show()
        else
            frame.timeline:Hide()
        end
    end

    -- v3.3.0 phase 2: live DPS forecast (above) + class pulse (left).
    if frame.dpsForecast then
        local txt = ns.GetDPSForecastText and ns.GetDPSForecastText(DH)
        if txt then
            AuxPoint(frame.dpsForecast, (DH.GetSetting and DH:GetSetting("dps_forecast_position")))
            local c = ns.GetColorPreset and ns.GetColorPreset(DH.GetSetting and DH:GetSetting("dps_color"))
            if c then
                frame.dpsForecast:SetTextColor(c[1], c[2], c[3])
            else
                frame.dpsForecast:SetTextColor(0.85, 0.9, 1.0)
            end
            frame.dpsForecast:SetText(txt)
            frame.dpsForecast:Show()
        else
            frame.dpsForecast:Hide()
        end
    end
    if frame.pulse then
        local ptxt, pr, pg, pb = ns.GetPulseInfo and ns.GetPulseInfo(DH)
        if ptxt then
            AuxPoint(frame.pulse, (DH.GetSetting and DH:GetSetting("class_pulse_position")))
            frame.pulse:SetText(ptxt)
            frame.pulse:SetTextColor(pr, pg, pb)
            frame.pulse:Show()
        else
            frame.pulse:Hide()
        end
    end

    -- v3.4.0: battle-phase indicator (below the window).
    if frame.phase then
        local show = (DH.GetSetting and DH:GetSetting("phase_indicators")) ~= false
            and (DH.GetSetting and DH:GetSetting("battle_context_enabled")) ~= false
        if show and DH.GetBattlePhase then
            local ph = DH:GetBattlePhase()
            if ph and ph ~= "idle" then
                frame.phase:SetText(ph:upper())
                frame.phase:Show()
            else
                frame.phase:Hide()
            end
        else
            frame.phase:Hide()
        end
    end

    -- v3.4.0: combat-forecast lines (procs / cooldowns coming up).
    if frame.forecast then
        local show = (DH.GetSetting and DH:GetSetting("combat_forecast_enabled")) == true
        if show and DH.ForecastNext then
            local window = tonumber(DH.GetSetting and DH:GetSetting("forecast_window")) or 5
            local max = tonumber(DH.GetSetting and DH:GetSetting("forecast_max_lines")) or 3
            local lines = DH:ForecastNext(window)
            if #lines > 0 then
                local buf = {}
                for i = 1, math.min(max, #lines) do
                    buf[#buf + 1] = lines[i]
                end
                frame.forecast:SetText(table.concat(buf, "\n"))
                frame.forecast:Show()
            else
                frame.forecast:Hide()
            end
        else
            frame.forecast:Hide()
        end
    end

    if frame.title then
        local exam = DH.GetSetting and DH:GetSetting("exam_mode")
        frame.title:SetText(exam and "RotationCore [EXAM]" or "RotationCore")
    end

    if not frame.isMoving then
        if fixed then
            local fw, fh = ComputeFixedFrameSize(drawCount)
            frame:SetSize(fw, fh)
        else
            -- Leave room for the title and the mode indicator on one line,
            -- but do not let a long title inflate the frame far past the
            -- icons (that used to leave a big empty gap around them).
            local w = math.max(maxRowW + 8, math.min(frame.title:GetStringWidth() + 40, maxRowW + 16))
            frame:SetSize(w, TITLE_H + totalH + FRAME_PAD_BOTTOM)
        end
        ApplyPosition()
    end

    local classes = DH.Class and DH.Class.abilities or {}
    local lines = {}
    frame.lines = lines

    for i = 1, MAX_SLOTS do
        local slot = slots[i]
        local rec = recs[i]
        if i <= maxShow and rec then
            local ability = classes[rec.ability]
            local tex = (ability and ability.texture) or rec.texture
            local style = (rec.execute and ns.EXECUTE_STYLE) or GetStyle(i)

            slot:SetSize(iconSize, iconSize)
            slot:ClearAllPoints()
            local row = math.ceil(i / columns)
            local col = ((i - 1) % columns) + 1
            local rowCols = math.min(columns, maxShow - (row - 1) * columns)
            local rowW = rowCols * iconSize + (rowCols - 1) * gap
            local x = -rowW / 2 + iconSize / 2 + (col - 1) * (iconSize + gap)
            local bottom = FRAME_PAD_BOTTOM + (rows - row) * (iconSize + gap)
            local wasShown = slot:IsShown()
            local oldX, oldY = slot.posX, slot.posY
            local canMove = AnimEnabled() and not UIUnderLoad() and wasShown and oldX and oldY
            local moved = canMove and (math.abs(oldX - x) > 0.5 or math.abs(oldY - bottom) > 0.5)
            if moved then
                slot:SetPoint("BOTTOM", frame, "BOTTOM", oldX, oldY)
                slot.moveFromX, slot.moveFromY = oldX, oldY
                slot.moveToX, slot.moveToY = x, bottom
                slot.moveElapsed = 0
                slot.moveDur = ANIM_MOVE / AnimSpeed()
                slot.moveActive = true
            else
                slot:SetPoint("BOTTOM", frame, "BOTTOM", x, bottom)
                slot.moveActive = false
            end
            slot.posX, slot.posY = x, bottom

            local key = tostring(rec.ability)
            local newTex = tex or "Interface\\Icons\\INV_Misc_QuestionMark"
            local changed = (slot.lastKey ~= nil) and (slot.lastKey ~= key)
            if changed and slot.iconPrev then
                -- stash the outgoing texture so it can fade out under the new one
                slot.iconPrev:SetTexture(slot.icon:GetTexture())
                slot.iconPrev:SetAlpha(1)
            end
            slot.icon:SetTexture(newTex)
            slot.lastChanged = changed
            slot.lastWasShown = wasShown
            slot.lastKey = key

            slot.border:SetSize(borderSize, borderSize)
            slot.border:ClearAllPoints()
            slot.border:SetPoint("CENTER")
            slot.border:SetVertexColor(style.r, style.g, style.b)
            if slot.bg then
                slot.bg:SetVertexColor(style.r, style.g, style.b)
            end
            if slot.topline then
                slot.topline:SetVertexColor(style.r, style.g, style.b, 0.85)
            end

            local showNumbers = DH.GetSetting and DH:GetSetting("show_priority_numbers")
            if showNumbers == nil then
                showNumbers = db.display.show_numbers
            end
            if showNumbers then
                slot.num:SetText(i)
                slot.num:SetTextColor(style.r, style.g, style.b)
            else
                slot.num:SetText("")
            end

            -- Phase 1.1: binding overlay (bottom-right)
            if (DH.GetSetting and DH:GetSetting("show_keybind")) ~= false then
                local kb = ability and ability.id and ns.GetSpellKeybind(ability.id)
                slot.keybind:SetText(kb or "")
            else
                slot.keybind:SetText("")
            end

            -- Cooldown countdown / GCD timer, each gated by its own setting.
            UpdateCooldownText(slot, i, ability and ability.id)

            -- Prompt 3.2: animated appear / crossfade, or a plain snap when
            -- animations are off, the CPU is busy, or icons change too fast.
            local nowT = GetTime()
            local canAnim = AnimEnabled() and not UIUnderLoad()
            local rapid = slot.lastAnimTime and (nowT - slot.lastAnimTime) < RAPID_CHANGE
            if (not canAnim) or rapid then
                SnapSlot(slot)
            elseif not slot.lastWasShown then
                slot:Show()
                slot.alpha = 0
                slot:SetAlpha(0)
                if slot.icon then
                    slot.icon:SetAlpha(1)
                end
                if slot.iconPrev then
                    slot.iconPrev:SetAlpha(0)
                end
                slot.lastAnimTime = nowT
                StartSlotAnim(slot, 1, ANIM_IN / AnimSpeed(), false)
            elseif slot.lastChanged then
                slot:Show()
                if slot.icon then
                    slot.icon:SetAlpha(0)
                end
                slot.lastAnimTime = nowT
                StartSlotAnim(slot, 1, ANIM_CROSS / AnimSpeed(), true)
            elseif not slot.animActive then
                SnapSlot(slot)
            end
            -- Localized client name first (RU spells on RU client)
            local dispName = (ability and ability.id and ns.CachedSpellInfo and ns.CachedSpellInfo(ability.id))
                or (ability and ability.name)
                or rec.name
                or tostring(rec.ability)
            -- Heal recommendations carry a target unit; show its name so the
            -- player knows who to heal without opening the tooltip.
            if rec.targetName and rec.unit and rec.unit ~= "player" then
                dispName = dispName .. " -> " .. rec.targetName
            end
            -- Training mode: append the reason to the icon tooltip line
            if rec.reason then
                dispName = dispName .. " \226\128\148 " .. rec.reason
            end
            lines[i] = dispName
            slot.tipName = (ability and ability.name) or rec.name or tostring(rec.ability)
            slot.tipId = (ability and ability.id) or nil
            slot.tipReason = rec.reason
        else
            slot.tipName, slot.tipId, slot.tipReason = nil, nil, nil
            slot.moveActive = false
            slot.posX, slot.posY = nil, nil
            -- Prompt 3.2: fade the outgoing icon, then hide it.
            if slot.animActive and slot.animTarget == 0 then
                -- already fading out: let it finish
            elseif slot:IsShown() and AnimEnabled() and not UIUnderLoad() then
                slot.lastKey = nil
                if slot.icon then
                    slot.icon:SetAlpha(1)
                end
                if slot.iconPrev then
                    slot.iconPrev:SetAlpha(0)
                end
                StartSlotAnim(slot, 0, ANIM_OUT / AnimSpeed(), false)
            else
                StopSlotAnim(slot)
                slot.lastKey = nil
                slot.alpha = 1
                slot:SetAlpha(1)
                slot:Hide()
            end
        end
    end

    if not frame.isMoving then
        frame:Show()
    end
    if ns.ApplyWinOpacity then
        ns.ApplyWinOpacity(frame, "primary")
    end
    if ns.ApplyWindowTint and ns.GetWindowTint("primary") then
        ns.ApplyWindowTint(frame, "primary")
    end
end

-- Reposition after a profile switch (called from DH:RefreshConfig)
function ns.RefreshSpellFrame()
    if frame and frame:IsShown() and not frame.isMoving then
        ApplyPosition()
    end
end

-- Extra displays (cooldowns, interrupts, timeline) live in SpellFrameExtras.lua.

-- ============================================================================
-- PANEL CONFIG MODE (Dominos-style). /rc config (or the Display button) shows a
-- top bar plus one settings panel per window with sliders (scale / size /
-- opacity) and a tint cycle button.
-- ============================================================================
ns.configMode = false
local configBar, configPanels = nil, {}

local function GetWinFrame(id)
    if id == "primary" then
        return frame
    end
    if id == "cooldowns" then
        return ns.cooldownsFrame
    end
    if id == "interrupts" then
        return ns.interruptFrame
    end
    if id == "timeline" then
        return ns.timelineFrame
    end
    return nil
end

ns.WINDOW_TINTS = {
    auto = nil,
    white = { 1, 1, 1 },
    gold = { 1, 0.82, 0 },
    green = { 0.3, 1, 0.3 },
    blue = { 0.4, 0.7, 1 },
    purple = { 0.7, 0.4, 1 },
    red = { 1, 0.3, 0.25 },
    cyan = { 0.3, 0.9, 0.9 },
}
function ns.GetWindowTint(id)
    local n = DH.GetSetting and DH:GetSetting("tint_" .. id)
    if not n or n == "auto" then
        return nil
    end
    return ns.WINDOW_TINTS[n]
end
function ns.ApplyWindowTint(f, id)
    if not f then
        return
    end
    local c = ns.GetWindowTint(id)
    if not c then
        return
    end
    if f.SetBackdropBorderColor then
        f:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end
    if f.title and f.title.SetTextColor then
        f.title:SetTextColor(c[1], c[2], c[3])
    end
end
function ns.ApplyWinOpacity(f, id)
    if not f then
        return
    end
    local op = tonumber(DH.GetSetting and DH:GetSetting("opacity_" .. id)) or 1
    if op < 0.15 then
        op = 0.15
    elseif op > 1 then
        op = 1
    end
    f:SetAlpha(op)
end

-- Which setting turns each window on/off (config-mode "Show window" checkbox).
local function GetWindowShown(id)
    if id == "primary" then
        return (DH.db and DH.db.display and DH.db.display.show_spellframe) ~= false
    elseif id == "cooldowns" then
        return (DH.GetSetting and DH:GetSetting("show_cooldowns_display")) == true
    elseif id == "interrupts" then
        return (DH.GetSetting and DH:GetSetting("show_interrupts_display")) == true
    elseif id == "timeline" then
        return (DH.GetSetting and DH:GetSetting("show_timeline_display")) == true
    end
    return false
end
local function SetWindowShown(id, v)
    if id == "primary" then
        if DH.db and DH.db.display then
            DH.db.display.show_spellframe = v
        end
        if ns.RefreshSpellFrame then
            ns.RefreshSpellFrame()
        end
    else
        DH:SetSetting("show_" .. id .. "_display", v)
        if id == "cooldowns" and ns.UpdateCooldownsFrame then
            ns.UpdateCooldownsFrame()
        end
        if id == "interrupts" and ns.UpdateInterruptsFrame then
            ns.UpdateInterruptsFrame()
        end
        if id == "timeline" and ns.UpdateTimelineFrame then
            ns.UpdateTimelineFrame()
        end
    end
    if DH.UpdateUI then
        DH:UpdateUI()
    end
    if ns.UpdateConfigOverlay then
        ns.UpdateConfigOverlay()
    end
end

-- ============================================================================
-- Config-mode grid + per-window highlight (Dominos-style). A faint grid is
-- drawn over the world and each window gets a coloured highlight that follows
-- it, so it is obvious what is being moved / configured.
-- ============================================================================
local configGrid, configHighlights, configSelected
local HL_ORDER = { "primary", "cooldowns", "interrupts", "timeline" }
local WIN_LABEL = {
    primary = "Icon window",
    cooldowns = "Cooldowns window",
    interrupts = "Interrupt window",
    timeline = "Boss timeline window",
}

local function EnsureConfigOverlay()
    if configGrid then
        return
    end
    local g = CreateFrame("Frame", "RotationCoreConfigGrid", UIParent)
    g:SetFrameStrata("BACKGROUND")
    g:SetAllPoints(UIParent)
    g.lines = {}
    for i = -20, 20 do
        local v = g:CreateTexture(nil, "BACKGROUND")
        v:SetTexture(1, 1, 1, 0.05)
        v:SetWidth(1)
        v:SetPoint("TOP", UIParent, "CENTER", i * 64, 0)
        v:SetPoint("BOTTOM", UIParent, "CENTER", i * 64, 0)
        g.lines[#g.lines + 1] = v
        local h = g:CreateTexture(nil, "BACKGROUND")
        h:SetTexture(1, 1, 1, 0.05)
        h:SetHeight(1)
        h:SetPoint("LEFT", UIParent, "CENTER", 0, i * 64)
        h:SetPoint("RIGHT", UIParent, "CENTER", 0, i * 64)
        g.lines[#g.lines + 1] = h
    end
    configGrid = g

    configHighlights = {}
    for _, id in ipairs(HL_ORDER) do
        local hl = CreateFrame("Frame", nil, UIParent)
        hl:SetFrameStrata("FULLSCREEN_DIALOG")
        hl:SetFrameLevel(2)
        hl.border = hl:CreateTexture(nil, "OVERLAY")
        hl.border:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl.border:SetAllPoints()
        hl.border:SetVertexColor(1, 0.82, 0)
        hl.fill = hl:CreateTexture(nil, "BACKGROUND")
        hl.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl.fill:SetAllPoints()
        hl.fill:SetVertexColor(1, 0.82, 0, 0.10)
        hl.label = hl:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hl.label:SetPoint("BOTTOMLEFT", hl, "TOPLEFT", 0, 2)
        hl.label:SetTextColor(1, 1, 1)
        hl.rcKey = id
        hl:Hide()
        configHighlights[id] = hl
    end
end

function ns.UpdateConfigOverlay()
    if not ns.configMode or not configGrid then
        return
    end
    for _, id in ipairs(HL_ORDER) do
        local hl = configHighlights[id]
        local w = GetWinFrame(id)
        local shown = w and w:IsShown()
        if hl and shown then
            local l = w:GetLeft() or 0
            local r = w:GetRight() or 0
            local t = w:GetTop() or 0
            local b = w:GetBottom() or 0
            hl:ClearAllPoints()
            hl:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l - 3, b - 3)
            hl:SetSize((r - l) + 6, (t - b) + 6)
            local enabled = GetWindowShown(id)
            local state = (configSelected == id) and 2 or (enabled and 1 or 0)
            if hl._state ~= state then
                hl._state = state
                if state == 2 then
                    hl.border:SetVertexColor(1, 0.82, 0)
                    hl.fill:SetVertexColor(1, 0.82, 0, 0.16)
                    hl.label:SetTextColor(1, 0.82, 0)
                elseif state == 1 then
                    hl.border:SetVertexColor(0.3, 0.9, 0.4)
                    hl.fill:SetVertexColor(0.3, 0.9, 0.4, 0.08)
                    hl.label:SetTextColor(0.7, 1, 0.7)
                else
                    hl.border:SetVertexColor(0.7, 0.7, 0.7)
                    hl.fill:SetVertexColor(0.5, 0.5, 0.5, 0.06)
                    hl.label:SetTextColor(0.75, 0.75, 0.75)
                end
            end
            local txt = L(WIN_LABEL[id] or id) .. (enabled and "" or (" (" .. L("off") .. ")"))
            if hl._txt ~= txt then
                hl._txt = txt
                hl.label:SetText(txt)
            end
            hl:Show()
        elseif hl then
            hl:Hide()
        end
    end
end

-- Clicking a window while configuring opens its settings panel. A plain click
-- (left or right, without dragging) works, so it always responds; dragging
-- still moves the window.
local function EnsureWindowRightClick(id)
    local w = GetWinFrame(id)
    if not w or w.rcConfigHooked then
        return
    end
    w.rcConfigHooked = true
    w:HookScript("OnMouseDown", function(self, button)
        if button == "LeftButton" or button == "RightButton" then
            local x, y = GetCursorPosition()
            self.rcDownX, self.rcDownY = x, y
            self.rcMoved = false
        end
    end)
    w:HookScript("OnMouseUp", function(self, button)
        if not ns.configMode then
            return
        end
        if button ~= "LeftButton" and button ~= "RightButton" then
            return
        end
        local x, y = GetCursorPosition()
        local moved = self.rcMoved
        if self.rcDownX and x and y then
            moved = moved or (math.abs(x - self.rcDownX) > 8) or (math.abs(y - self.rcDownY) > 8)
        end
        if not moved and ns.OpenWindowConfig then
            ns.OpenWindowConfig(id)
        end
    end)
end

local function ConfigSliders(id)
    if id == "primary" then
        return {
            {
                "Icon size",
                16,
                64,
                1,
                function()
                    return (DH.GetSetting and DH:GetSetting("icon_size")) or 36
                end,
                function(v)
                    DH:SetSetting("icon_size", v)
                    DH:UpdateUI()
                end,
            },
            {
                "Spacing",
                0,
                16,
                1,
                function()
                    return (DH.GetSetting and DH:GetSetting("icon_gap")) or 4
                end,
                function(v)
                    DH:SetSetting("icon_gap", v)
                    DH:UpdateUI()
                end,
            },
            {
                "Scale",
                0.5,
                2.5,
                0.1,
                function()
                    return (DH.db and DH.db.display and DH.db.display.spellframe_scale) or 1
                end,
                function(v)
                    DH.db.display.spellframe_scale = v
                    DH:UpdateUI()
                end,
            },
        }
    elseif id == "cooldowns" then
        return {
            {
                "Icons",
                1,
                10,
                1,
                function()
                    return (DH.GetSetting and DH:GetSetting("cooldowns_num_icons")) or 3
                end,
                function(v)
                    DH:SetSetting("cooldowns_num_icons", v)
                    DH:UpdateUI()
                end,
            },
            {
                "Scale",
                0.5,
                2.5,
                0.1,
                function()
                    return (DH.GetSetting and DH:GetSetting("cooldowns_scale")) or 1
                end,
                function(v)
                    DH:SetSetting("cooldowns_scale", v)
                    DH:UpdateUI()
                end,
            },
        }
    elseif id == "interrupts" then
        return {
            {
                "Scale",
                0.5,
                2.5,
                0.1,
                function()
                    return (DH.GetSetting and DH:GetSetting("interrupts_scale")) or 1
                end,
                function(v)
                    DH:SetSetting("interrupts_scale", v)
                    DH:UpdateUI()
                end,
            },
        }
    elseif id == "timeline" then
        return {
            {
                "Scale",
                0.5,
                2.5,
                0.1,
                function()
                    return (DH.GetSetting and DH:GetSetting("timeline_scale")) or 1
                end,
                function(v)
                    DH:SetSetting("timeline_scale", v)
                    DH:UpdateUI()
                end,
            },
        }
    end
    return {}
end

local function ConfigRow(panel, label, minv, maxv, stepv, get, set, y)
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y)
    fs:SetText(label)
    fs:SetTextColor(0.9, 0.9, 0.9)
    local slider = CreateFrame("Slider", nil, panel)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(140, 14)
    slider:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y - 15)
    slider:SetMinMaxValues(minv, maxv)
    slider:SetValueStep(stepv)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetSize(16, 16)
    slider:SetThumbTexture(thumb)
    local bg = slider:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
    bg:SetAllPoints()
    local val = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    val:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    val:SetTextColor(1, 0.82, 0)
    local function fmt(v)
        if stepv >= 1 then
            return tostring(math.floor(v + 0.5))
        end
        return string.format("%.1f", v)
    end
    slider:SetValue(tonumber(get()) or minv)
    val:SetText(fmt(tonumber(get()) or minv))
    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / stepv + 0.5) * stepv
        set(v)
        val:SetText(fmt(v))
    end)
    return y - 44
end

local function MakeConfigPanel(id, title, x, y)
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetSize(180, 80)
    p:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(0.03, 0.03, 0.03, 0.94)
    p:SetPoint("CENTER", UIParent, "CENTER", x, y)
    local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", p, "TOP", 0, -6)
    t:SetText(L(title))
    t:SetTextColor(1, 0.82, 0)
    p.title = t
    if ns.ApplyWindowChrome then
        ns.ApplyWindowChrome(p)
    end
    p:EnableMouse(true)
    p:SetScript("OnEnter", function()
        configSelected = id
        if ns.UpdateConfigOverlay then
            ns.UpdateConfigOverlay()
        end
    end)
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        p:Hide()
        if configSelected == id then
            configSelected = nil
        end
        if ns.UpdateConfigOverlay then
            ns.UpdateConfigOverlay()
        end
    end)
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -24)
    local cbl = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cbl:SetText(L("Show window"))
    cbl:SetTextColor(0.9, 0.9, 0.9)
    cb:SetChecked(GetWindowShown(id))
    cb:SetScript("OnClick", function(self)
        SetWindowShown(id, self:GetChecked() and true or false)
    end)
    p.showCheck = cb
    local cy = -50
    for _, spec in ipairs(ConfigSliders(id)) do
        cy = ConfigRow(p, L(spec[1]), spec[2], spec[3], spec[4], spec[5], spec[6], cy)
    end
    cy = ConfigRow(p, L("Opacity"), 0.2, 1, 0.05, function()
        return (DH.GetSetting and DH:GetSetting("opacity_" .. id)) or 1
    end, function(v)
        DH:SetSetting("opacity_" .. id, v)
        local w = GetWinFrame(id)
        if w and not (id == "primary") then
            w:SetAlpha(v)
        end
        if DH.UpdateUI then
            DH:UpdateUI()
        end
    end, cy)
    -- Colour swatches (replaces the old cycle button).
    local swatchLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    swatchLabel:SetPoint("TOPLEFT", p, "TOPLEFT", 10, cy + 4)
    swatchLabel:SetText(L("Tint"))
    swatchLabel:SetTextColor(0.9, 0.9, 0.9)
    local order = { "auto", "gold", "green", "blue", "purple", "red", "cyan", "white" }
    local swatches = {}
    local function applyTint(nxt)
        DH:SetSetting("tint_" .. id, nxt)
        local w = GetWinFrame(id)
        if w then
            if nxt == "auto" then
                local th = DH.GetUITheme and DH:GetUITheme() or nil
                if w.title and th and w.title.SetTextColor then
                    w.title:SetTextColor(th.title[1], th.title[2], th.title[3])
                end
                if w.SetBackdropBorderColor and th then
                    w:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3])
                end
            else
                ns.ApplyWindowTint(w, id)
            end
        end
        for k, sw in pairs(swatches) do
            if k == nxt then
                sw.sel:Show()
            else
                sw.sel:Hide()
            end
        end
    end
    for i, key in ipairs(order) do
        local sw = CreateFrame("Button", nil, p)
        sw:SetSize(16, 16)
        sw:SetPoint("TOPLEFT", p, "TOPLEFT", 10 + (i - 1) * 19, cy - 18)
        sw.sel = sw:CreateTexture(nil, "BACKGROUND")
        sw.sel:SetTexture("Interface\\Buttons\\WHITE8X8")
        sw.sel:SetPoint("TOPLEFT", sw, "TOPLEFT", -2, 2)
        sw.sel:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", 2, -2)
        sw.sel:SetVertexColor(1, 1, 1, 0.6)
        local tex = sw:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        local c = ns.WINDOW_TINTS[key]
        if c then
            tex:SetTexture(c[1], c[2], c[3])
        else
            local th = DH.GetUITheme and DH:GetUITheme() or nil
            local b = (th and th.border) or { 0.6, 0.6, 0.6 }
            tex:SetTexture(b[1], b[2], b[3])
        end
        sw:SetScript("OnClick", function()
            applyTint(key)
        end)
        swatches[key] = sw
    end
    applyTint((DH.GetSetting and DH:GetSetting("tint_" .. id)) or "auto")
    cy = cy - 40
    p:SetHeight(math.abs(cy) + 14)
    p:Show()
    return p
end

-- Opens (or focuses) the settings panel for one window, next to that window.
function ns.OpenWindowConfig(id)
    if not ns.configMode or not WIN_LABEL[id] then
        return
    end
    for k, other in pairs(configPanels) do
        if k ~= id then
            other:Hide()
        end
    end
    local p = configPanels[id]
    if not p then
        p = MakeConfigPanel(id, WIN_LABEL[id], 0, 0)
        configPanels[id] = p
    end
    local w = GetWinFrame(id)
    local ox, oy = 0, 0
    if w and UIParent then
        local cx, cy2 = w:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then
            ox = cx - ux
        end
        if cy2 and uy then
            oy = cy2 - uy
        end
    end
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel((configGrid and configGrid:GetFrameLevel() or 0) + 10)
    -- Place the panel beside the window, flipping to the other side near an edge.
    local half = (p:GetWidth() or 180) / 2
    local screenHalf = ((UIParent and UIParent:GetWidth()) or 1000) / 2
    local px = ox + 220
    if px + half > screenHalf - 12 then
        px = ox - 220
    end
    if px - half < -screenHalf + 12 then
        px = -screenHalf + 12 + half
    end
    p:ClearAllPoints()
    p:SetPoint("CENTER", UIParent, "CENTER", px, oy)
    p:SetClampedToScreen(true)
    p:Show()
    configSelected = id
    if ns.UpdateConfigOverlay then
        ns.UpdateConfigOverlay()
    end
end

local function EnsureConfigBar()
    if configBar then
        return configBar
    end
    local b = CreateFrame("Frame", "RotationCoreConfigBar", UIParent)
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:SetSize(520, 64)
    b:SetPoint("TOP", UIParent, "TOP", 0, -80)
    b:EnableMouse(true)
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    b:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    b:SetBackdropColor(0, 0, 0, 0.92)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", b, "TOP", 0, -8)
    t:SetText(L("Panel configuration"))
    t:SetTextColor(1, 0.82, 0)
    b.title = t
    if ns.ApplyWindowChrome then
        ns.ApplyWindowChrome(b)
    end
    local h = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOP", b, "TOP", 0, -28)
    h:SetJustifyH("CENTER")
    h:SetText(L("Right-click a window to open its settings. Drag to move; settings save automatically."))
    h:SetTextColor(0.75, 0.75, 0.75)
    local exit = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    exit:SetSize(100, 22)
    exit:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 6)
    exit:SetText(L("Exit"))
    exit:SetScript("OnClick", function()
        ns.SetConfigMode(false)
    end)
    local reset = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    reset:SetSize(150, 22)
    reset:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 6)
    reset:SetText(L("Reset positions"))
    reset:SetScript("OnClick", function()
        if ns.ResetWindowPositions then
            ns.ResetWindowPositions()
        end
    end)
    configBar = b
    return b
end

function ns.SetConfigMode(on)
    ns.configMode = on and true or false
    if ns.SetMoveMode then
        ns.SetMoveMode(ns.configMode)
    end
    if ns.configMode then
        EnsureConfigBar():Show()
        EnsureConfigOverlay()
        configSelected = nil
        if configGrid then
            configGrid:Show()
            -- Track the windows every frame so the highlight slides smoothly
            -- while a window is dragged (a throttled timer looked choppy).
            configGrid:SetScript("OnUpdate", function()
                if ns.UpdateConfigOverlay then
                    ns.UpdateConfigOverlay()
                end
            end)
        end
        for _, p in pairs(configPanels) do
            p:Hide()
        end
        -- Settings panels are opened per window with a right-click.
        for _, id in ipairs(HL_ORDER) do
            EnsureWindowRightClick(id)
        end
        if ns.UpdateConfigOverlay then
            ns.UpdateConfigOverlay()
        end
    else
        if configBar then
            configBar:Hide()
        end
        if configGrid then
            configGrid:SetScript("OnUpdate", nil)
            configGrid:Hide()
        end
        if configHighlights then
            for _, hl in pairs(configHighlights) do
                hl:Hide()
            end
        end
        configSelected = nil
        for _, p in pairs(configPanels) do
            p:Hide()
        end
        configPanels = {}
    end
end

function ns.IsConfigMode()
    return ns.configMode
end

-- Restore every window to its default position (config-mode "Reset positions").
function ns.ResetWindowPositions()
    local pos = GetPosTable()
    if pos then
        pos.x, pos.y = 0, -250
    end
    if DH.db and DH.db.spellFrame then
        DH.db.spellFrame.x, DH.db.spellFrame.y = 0, -250
    end
    if DH.db and DH.db.spellFrame_per_spec then
        for _, p in pairs(DH.db.spellFrame_per_spec) do
            p.x, p.y = 0, -250
        end
    end
    local function resetExtra(f)
        if not f or not f.posKey then
            return
        end
        if DH.SetSetting then
            DH:SetSetting(f.posKey, { x = f.defX or 0, y = f.defY or -250 })
        end
        ns.ApplyExtraPosition(f)
    end
    resetExtra(ns.cooldownsFrame)
    resetExtra(ns.interruptFrame)
    resetExtra(ns.timelineFrame)
    if frame then
        ApplyPosition()
    end
    if DH.SetSetting then
        DH:SetSetting("display_layout", "default")
    end
end

-- Reset the optional windows after a profile switch / position reset
function ns.HideAllWindows()
    if frame then
        frame:Hide()
    end
    if ns.cooldownsFrame then
        ns.cooldownsFrame:Hide()
    end
    if ns.interruptFrame then
        ns.interruptFrame:Hide()
    end
    if ns.timelineFrame then
        ns.timelineFrame:Hide()
    end
    if ns.DebugFrame then
        ns.DebugFrame:Hide()
    end
end

function ns.CooldownState()
    local count = #(ns.GetCooldownItems())
    local shown = ns.cooldownsFrame and ns.cooldownsFrame:IsShown() or false
    local alpha = ns.cooldownsFrame and ns.cooldownsFrame:GetAlpha() or 0
    local pos = { x = nil, y = nil }
    if ns.cooldownsFrame and ns.cooldownsFrame.GetCenter and UIParent and UIParent.GetCenter then
        local cx, cy = ns.cooldownsFrame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then
            pos.x = math.floor(cx - ux + 0.5)
        end
        if cy and uy then
            pos.y = math.floor(cy - uy + 0.5)
        end
    end
    return shown, count, alpha, pos
end

function ns.CleanupExtraFrames()
    if ns.cooldownsFrame then
        ns.cooldownsFrame:Hide()
        ns.cooldownsFrame = nil
    end
    if ns.interruptFrame then
        ns.interruptFrame:Hide()
        ns.interruptFrame = nil
    end
    if ns.timelineFrame then
        ns.timelineFrame:Hide()
        ns.timelineFrame = nil
    end
    if ns.RefreshExtraFrames then
        ns.RefreshExtraFrames()
    end
end

function ns.RefreshExtraFrames()
    if ns.cooldownsFrame and ns.cooldownsFrame:IsShown() and not ns.cooldownsFrame.isMoving then
        ns.ApplyExtraPosition(ns.cooldownsFrame)
    end
    if ns.interruptFrame and ns.interruptFrame:IsShown() and not ns.interruptFrame.isMoving then
        ns.ApplyExtraPosition(ns.interruptFrame)
    end
    if ns.timelineFrame and ns.timelineFrame:IsShown() and not ns.timelineFrame.isMoving then
        ns.ApplyExtraPosition(ns.timelineFrame)
    end
end

-- ============================================================================
-- PROMPT 3.4: display layout presets
-- A preset writes the primary / cooldowns / interrupts positions (and, for
-- "minimal", the scale and visibility). "custom" leaves the user's own
-- positions untouched - a manual drag switches the setting back to "custom".
-- ============================================================================
local LAYOUTS = {
    center = {
        primary = { x = 0, y = -250 },
        cooldowns = { x = -170, y = -250 },
        interrupts = { x = -170, y = -330 },
        scale = 1,
        show_cd = true,
        show_int = true,
    },
    side = {
        primary = { x = 230, y = -160 },
        cooldowns = { x = 230, y = -270 },
        interrupts = { x = 230, y = -350 },
        scale = 1,
        show_cd = true,
        show_int = true,
    },
    minimal = {
        primary = { x = 0, y = -250 },
        scale = 0.7,
        show_cd = false,
        show_int = false,
    },
    raid = {
        primary = { x = 0, y = -250 },
        cooldowns = { x = -230, y = -250 },
        interrupts = { x = 230, y = -250 },
        scale = 1,
        show_cd = true,
        show_int = true,
    },
}
ns.LAYOUT_PRESETS = LAYOUTS

function ns.ApplyLayout(name)
    if not DH.db then
        return
    end
    local preset = LAYOUTS[name]
    if not preset then
        return
    end -- "custom": keep the user's positions
    local common = DH.db.common
    if not common then
        return
    end

    if preset.primary and not (DH.GetSetting and DH:GetSetting("spellFrame_pos_per_spec")) then
        DH.db.spellFrame = { x = preset.primary.x, y = preset.primary.y }
    end
    if preset.cooldowns then
        common.cooldowns_position = { x = preset.cooldowns.x, y = preset.cooldowns.y }
    end
    if preset.interrupts then
        common.interrupts_position = { x = preset.interrupts.x, y = preset.interrupts.y }
    end
    if preset.scale then
        if DH.db.display then
            DH.db.display.spellframe_scale = preset.scale
        end
        common.cooldowns_scale = preset.scale
        common.interrupts_scale = preset.scale
    end
    if preset.show_cd ~= nil then
        DH:SetSetting("show_cooldowns_display", preset.show_cd)
    end
    if preset.show_int ~= nil then
        DH:SetSetting("show_interrupts_display", preset.show_int)
    end
    DH:SetSetting("display_layout", name)

    if ns.RefreshSpellFrame then
        ns.RefreshSpellFrame()
    end
    if ns.RefreshExtraFrames then
        ns.RefreshExtraFrames()
    end
    DH:UpdateUI()
end

-- Text form of the current positions (kept separate from the profile export).
function ns.ExportLayout()
    if not DH.db then
        return ""
    end
    local common = DH.db.common or {}
    local parts = {}
    local sf = DH.db.spellFrame
    if sf and sf.x and sf.y then
        parts[#parts + 1] = string.format("primary=%.0f,%.0f", sf.x, sf.y)
    end
    local cd = common.cooldowns_position
    if cd and cd.x and cd.y then
        parts[#parts + 1] = string.format("cooldowns=%.0f,%.0f", cd.x, cd.y)
    end
    local it = common.interrupts_position
    if it and it.x and it.y then
        parts[#parts + 1] = string.format("interrupts=%.0f,%.0f", it.x, it.y)
    end
    return table.concat(parts, ";")
end

-- Safe, hand-parsed import ("primary=x,y;cooldowns=x,y;interrupts=x,y").
function ns.ImportLayout(text)
    if not DH.db or type(text) ~= "string" then
        return 0
    end
    local common = DH.db.common
    if not common then
        return 0
    end
    local n = 0
    for key, x, y in text:gmatch("(%a+)=(%-?%d+)%s*,%s*(%-?%d+)") do
        x, y = tonumber(x), tonumber(y)
        if x and y then
            if key == "primary" then
                DH.db.spellFrame = { x = x, y = y }
            elseif key == "cooldowns" then
                common.cooldowns_position = { x = x, y = y }
            elseif key == "interrupts" then
                common.interrupts_position = { x = x, y = y }
            end
            n = n + 1
        end
    end
    DH:SetSetting("display_layout", "custom")
    if ns.RefreshSpellFrame then
        ns.RefreshSpellFrame()
    end
    if ns.RefreshExtraFrames then
        ns.RefreshExtraFrames()
    end
    DH:UpdateUI()
    return n
end

-- /rc move: show every display as a labelled box so it can be dragged.
-- /rc lock: hide the labels and restore the normal empty/queue behaviour.
function ns.SetMoveMode(on)
    ns.moveMode = on and true or false
    EnsureFrame()

    if ns.moveMode then
        frame.moveLabel = L("Primary")
        frame.reason:SetText(L("Primary"))
        frame.reason:SetWidth(140)
        frame.reason:Show()
        for i = 1, MAX_SLOTS do
            if slots[i] then
                slots[i]:Hide()
            end
        end
        frame.lines = {}
        if frame.moveText then
            frame.moveText:SetText(L("Primary"))
            frame.moveText:Show()
        end
        frame:SetSize(math.max((frame.title:GetStringWidth() or 60) + 66, 150), TITLE_H + 30)
        ApplyPosition()
        UpdateModeIndicator()
        frame:Show()
    else
        if frame.moveText then
            frame.moveText:Hide()
        end
        if not frame.lines or #frame.lines == 0 then
            frame.reason:Hide()
            frame:Hide()
        end
        -- Explicitly tear down the optional move boxes when their display is
        -- disabled, so no black square is left behind after /rc lock.
        if ns.cooldownsFrame then
            if ns.cooldownsFrame.moveText then
                ns.cooldownsFrame.moveText:Hide()
            end
            if (DH.GetSetting and DH:GetSetting("show_cooldowns_display")) ~= true then
                ns.cooldownsFrame:Hide()
            end
        end
        if ns.interruptFrame then
            if ns.interruptFrame.moveText then
                ns.interruptFrame.moveText:Hide()
            end
            if (DH.GetSetting and DH:GetSetting("show_interrupts_display")) ~= true then
                ns.interruptFrame:Hide()
            end
        end
        if ns.timelineFrame then
            if ns.timelineFrame.moveText then
                ns.timelineFrame.moveText:Hide()
            end
            if (DH.GetSetting and DH:GetSetting("show_timeline_display")) ~= true then
                ns.timelineFrame:Hide()
            end
        end
    end

    -- Cooldowns / Interrupts boxes (created lazily, kept visible in move mode)
    if ns.UpdateCooldownsFrame then
        ns.UpdateCooldownsFrame()
    end
    if ns.UpdateInterruptsFrame then
        ns.UpdateInterruptsFrame()
    end
    if ns.UpdateTimelineFrame then
        ns.UpdateTimelineFrame()
    end
end

function ns.IsMoveMode()
    return ns.moveMode
end

-- Debug: /rc queuediag prints the settings and the actual recommendation
-- list behind the icon window, so a one-icon report can be diagnosed quickly.
function ns.GetRenderedSlotCount()
    local n = 0
    for i = 1, MAX_SLOTS do
        local slot = slots[i]
        if slot and slot:IsShown() and slot.tipName then
            n = n + 1
        end
    end
    return n
end

DH:RegisterSlashCommand("queuediag", function()
    if DH.UpdateRecommendations then
        DH:UpdateRecommendations()
    end
    local recs = ns.recommendations or {}
    local display = DH.db and DH.db.display and DH.db.display.spellframe_icons
    local common = DH.GetSetting and DH:GetSetting("spellframe_icons")
    local explicit = DH.db and DH.db.display and DH.db.display.spellframe_icons_explicit
    local n = (DH.GetSpellFrameIconCount and DH:GetSpellFrameIconCount()) or 3
    local showPrimary = DH.db and DH.db.display and DH.db.display.show_spellframe ~= false
    local cooldownsShown = ns.cooldownsFrame and ns.cooldownsFrame:IsShown()
    DH:Print(string.format(
        "Queue: icons=%d (display=%s explicit=%s common=%s), recs=%d, rendered=%d, primary=%s shown=%s, cooldowns=%s, mode=%s",
        n,
        tostring(display),
        tostring(explicit),
        tostring(common),
        #recs,
        ns.GetRenderedSlotCount and ns.GetRenderedSlotCount() or -1,
        tostring(showPrimary),
        frame and tostring(frame:IsShown()) or "nil",
        tostring(cooldownsShown),
        tostring(DH.db and DH.db.mode)
    ))
    local parts = {}
    for i = 1, math.min(#recs, 10) do
        parts[#parts + 1] = i .. ":" .. tostring(recs[i].ability) .. (recs[i].execute and "!" or "")
    end
    DH:Print("Queue abilities: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
    local target = UnitExists and UnitExists("target") and true or false
    local combat = ns.inCombat or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    local paused = DH.db and DH.db.paused and true or false
    local enabled = DH.db and DH.db.enabled ~= false
    local idle = ns.GetIdleReason and ns.GetIdleReason() or nil
    DH:Print(string.format(
        "Queue state: target=%s combat=%s paused=%s enabled=%s exam=%s idle=%s",
        tostring(target),
        tostring(combat),
        tostring(paused),
        tostring(enabled),
        tostring(DH.GetSetting and DH:GetSetting("exam_mode") == true),
        tostring(idle)
    ))
    if #recs == 0 then
        DH:Print("Queue is empty (no attackable target / out of combat). The Cooldowns window is a separate window and still lists cooldowns.")
    end
end, "queuediag - show queue icon count and recommendations")
