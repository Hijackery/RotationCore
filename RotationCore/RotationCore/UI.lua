-- UI.lua
-- Action bar glow display for RotationCore (3.3.5a, no dependencies)
--
-- The addon no longer draws its own icon frame. Recommendations are shown by
-- highlighting the matching ability icons directly on the player's action bars:
--   priority 1 = green (press now), 2 = yellow (next), 3 = blue (after that)

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
-- CONSTANTS
-- ============================================================================

local PRIORITY_STYLE = {
    [1] = { r = 0.15, g = 1.00, b = 0.15, base = 0.70, amp = 0.30, freq = 2.6 },
    [2] = { r = 1.00, g = 0.85, b = 0.10, base = 0.80, amp = 0.18, freq = 1.7 },
    [3] = { r = 0.25, g = 0.60, b = 1.00, base = 0.85, amp = 0.12, freq = 1.2 },
}
-- Shared with SpellFrame.lua (icon window colors)
ns.PRIORITY_STYLE = PRIORITY_STYLE

-- Prompt 3.1: accessibility palettes. Each maps the three priority slots
-- (1 = press now, 2 = next, 3 = after) to an RGB triple. Red/green colour
-- blindness keeps a blue-vs-yellow separation; tritanopia uses red/green/grey;
-- high contrast uses white/black/yellow.
ns.PALETTES = {
    default = {
        [1] = { r = 0.15, g = 1.00, b = 0.15 },
        [2] = { r = 1.00, g = 0.85, b = 0.10 },
        [3] = { r = 0.25, g = 0.60, b = 1.00 },
    },
    protanopia = {
        [1] = { r = 1.00, g = 0.55, b = 0.00 },
        [2] = { r = 1.00, g = 0.90, b = 0.10 },
        [3] = { r = 0.15, g = 0.45, b = 1.00 },
    },
    deuteranopia = {
        [1] = { r = 0.20, g = 0.45, b = 1.00 },
        [2] = { r = 1.00, g = 0.90, b = 0.10 },
        [3] = { r = 0.65, g = 0.25, b = 0.90 },
    },
    tritanopia = {
        [1] = { r = 1.00, g = 0.20, b = 0.20 },
        [2] = { r = 0.15, g = 0.80, b = 0.30 },
        [3] = { r = 0.60, g = 0.60, b = 0.60 },
    },
    high_contrast = {
        [1] = { r = 1.00, g = 1.00, b = 1.00 },
        [2] = { r = 0.05, g = 0.05, b = 0.05 },
        [3] = { r = 1.00, g = 1.00, b = 0.00 },
    },
}

-- Returns the active palette: the custom table when the setting is "custom"
-- and it holds three valid colours, otherwise the named preset (falling back
-- to "default" so a corrupt profile never yields invisible icons).
function ns.GetPalette()
    local name = (DH.GetSetting and DH:GetSetting("color_palette")) or "default"
    local custom = DH.GetSetting and DH:GetSetting("color_custom")
    if name == "custom" and type(custom) == "table" then
        local ok = true
        for i = 1, 3 do
            if type(custom[i]) ~= "table" then ok = false break end
        end
        if ok then return custom end
    end
    return ns.PALETTES[name] or ns.PALETTES.default
end

-- Copies the active palette into the shared PRIORITY_STYLE entries (keeping
-- the pulse base/amp/freq) so the action-bar glow and the icon window both
-- pick it up. Cheap: only runs from ns.UpdateUI.
function ns.ApplyPalette()
    local pal = ns.GetPalette()
    for i = 1, 3 do
        local style, c = PRIORITY_STYLE[i], pal[i]
        if style and c then
            style.r, style.g, style.b = c.r or 0, c.g or 0, c.b or 0
        end
    end
    -- Colour-blind friendly override: orange / blue / grey (deuteranopia-safe).
    if DH.GetSetting and DH:GetSetting("colorblind_mode") == true then
        local cb = { { 1.00, 0.55, 0.10 }, { 0.35, 0.70, 1.00 }, { 0.85, 0.85, 0.85 } }
        for i = 1, 3 do
            local style, c = PRIORITY_STYLE[i], cb[i]
            if style then style.r, style.g, style.b = c[1], c[2], c[3] end
        end
    end
end
local FLASH_RATE = 3.0    -- flashes per second for the "clip now" indicator

-- Convert hue (0..1) to RGB, used by glow_style = "rainbow"
local function HueToRGB(h)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local q, t = 1 - f, f
    local mod = i % 6
    if mod == 0 then return 1, t, 0 end
    if mod == 1 then return q, 1, 0 end
    if mod == 2 then return 0, 1, t end
    if mod == 3 then return 0, q, 1 end
    if mod == 4 then return t, 0, 1 end
    return 1, 0, q
end

local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"

-- Optional LibCustomGlow: used when the library is loaded, otherwise the
-- built-in renderer below is used. Never a hard dependency.
local LCG
do
    local ok, lib = pcall(function() return LibStub and LibStub("LibCustomGlow-1.0", true) end)
    if ok and type(lib) == "table" then LCG = lib end
end
function ns.HasGlowLib() return LCG ~= nil end

-- Optional LibSharedMedia-3.0: fonts and sounds. Never a hard dependency; when
-- absent the built-in defaults are used.
local LSM
do
    local ok, lib = pcall(function() return LibStub and LibStub("LibSharedMedia-3.0", true) end)
    if ok and type(lib) == "table" then LSM = lib end
end
function ns.HasLSM() return LSM ~= nil end

-- Named colour presets used by the class-pulse and DPS-forecast indicators.
ns.COLOR_PRESETS = {
    green  = { 0.20, 1.00, 0.20 },
    yellow = { 1.00, 0.85, 0.10 },
    red    = { 1.00, 0.25, 0.20 },
    blue   = { 0.35, 0.70, 1.00 },
    purple = { 0.70, 0.40, 1.00 },
    cyan   = { 0.30, 0.90, 0.90 },
    orange = { 1.00, 0.55, 0.15 },
    pink   = { 1.00, 0.50, 0.80 },
    white  = { 1.00, 1.00, 1.00 },
}
function ns.GetColorPreset(name)
    if not name or name == "auto" then return nil end
    return ns.COLOR_PRESETS[name]
end
function ns.ColorChoices()
    return {
        { value = "auto", text = "Auto" },
        { value = "green", text = "Green" },
        { value = "yellow", text = "Yellow" },
        { value = "red", text = "Red" },
        { value = "blue", text = "Blue" },
        { value = "purple", text = "Purple" },
        { value = "cyan", text = "Cyan" },
        { value = "orange", text = "Orange" },
        { value = "pink", text = "Pink" },
        { value = "white", text = "White" },
    }
end

-- ============================================================================
-- Shared window chrome / animation / grid (one look for every window)
-- ============================================================================

-- Applies the active theme to any frame with a backdrop + title, so all windows
-- (icon window, cooldowns, interrupts, timeline, DoT, swing, wizard, panels)
-- share one visual language. Cheap enough to call on theme change.
-- Background presets layered on top of the active theme/skin.
function ns.ApplyBgStyle(th)
    local st = DH.GetSetting and DH:GetSetting("bg_style") or "default"
    if not th or not st or st == "default" then return th end
    if st == "matte" then
        th.bg = "Interface\\Buttons\\WHITE8X8"
        th.edge = "Interface\\Buttons\\WHITE8X8"
        th.tile = false
        th.edgeSize = 1
        th.insets = { left = 1, right = 1, top = 1, bottom = 1 }
        th.matte = true
    end
    return th
end

function ns.ApplyWindowChrome(f)
    if not f then return end
    local th = DH.GetUITheme and DH:GetUITheme() or nil
    if not th then return end
    th = ns.ApplyBgStyle(th)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = th.bg, edgeFile = th.edge,
            tile = th.tile, tileSize = th.tileSize, edgeSize = th.edgeSize,
            insets = th.insets,
        })
    end
    if f.SetBackdropColor and th.backdrop then
        local b = th.backdrop
        f:SetBackdropColor(b[1], b[2], b[3], b[4] or 0.9)
    end
    if f.SetBackdropBorderColor and th.border then
        local b = th.border
        f:SetBackdropBorderColor(b[1], b[2], b[3], 1)
    end
    if f.title and f.title.SetTextColor and th.title then
        f.title:SetTextColor(th.title[1], th.title[2], th.title[3])
        if ns.ApplyFont then ns.ApplyFont(f.title) end
        if f.title.SetShadowOffset then f.title:SetShadowOffset(1, -1) end
        if f.title.SetShadowColor then f.title:SetShadowColor(0, 0, 0, 0.85) end
    end
    -- Soft drop shadow behind the window for depth.
    if not f.rcShadow then
        f.rcShadow = f:CreateTexture(nil, "BACKGROUND", nil, -6)
        f.rcShadow:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.rcShadow:SetVertexColor(0, 0, 0, 0.35)
    end
    f.rcShadow:ClearAllPoints()
    f.rcShadow:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 4)
    f.rcShadow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 4, -4)
    -- Title strip (subtle translucent bar behind the title) + a thin accent
    -- cap line at the very top: gives every window a finished, framed look.
    if not f.rcTitleBar then
        f.rcTitleBar = f:CreateTexture(nil, "BACKGROUND", nil, -2)
        f.rcTitleBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    local acc = th.title
    f.rcTitleBar:ClearAllPoints()
    f.rcTitleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    f.rcTitleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    f.rcTitleBar:SetHeight(22)
    f.rcTitleBar:SetVertexColor(acc[1], acc[2], acc[3], 0.10)
    if not f.rcAccent then
        f.rcAccent = f:CreateTexture(nil, "OVERLAY", nil, 2)
        f.rcAccent:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    f.rcAccent:ClearAllPoints()
    f.rcAccent:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
    f.rcAccent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    f.rcAccent:SetHeight(2)
    f.rcAccent:SetVertexColor(acc[1], acc[2], acc[3], 0.9)
    return th
end

-- Fade in / out with a tiny scale pop. Uses one shared driver so it never
-- clobbers a frame's own OnUpdate script.
ns._fades = ns._fades or {}
local fadeDriver = CreateFrame("Frame", "RotationCoreFadeDriver", UIParent)
fadeDriver:SetScript("OnUpdate", function(_, dt)
    for f, a in pairs(ns._fades) do
        a.t = a.t + dt
        local k = math.min(1, a.t / a.dur)
        local alpha = a.from + (a.to - a.from) * k
        f:SetAlpha(alpha)
        if a.scale then
            f:SetScale(a.s0 + (1 - a.s0) * k)
        end
        if k >= 1 then
            if a.hide then f:Hide() end
            if a.scale then f:SetScale(1) end
            ns._fades[f] = nil
        end
    end
end)

function ns.FadeShow(f, dur, target)
    if not f or ns._fades[f] then return end
    target = target or 1
    local shown = f:IsShown()
    if shown and (f:GetAlpha() or 1) >= target - 0.01 then return end
    if not shown then f:SetAlpha(0); f:Show() end
    ns._fades[f] = { t = 0, dur = dur or 0.14, from = f:GetAlpha(), to = target,
        scale = true, s0 = (f:GetScale() or 1) * 0.96 }
end

function ns.FadeHide(f, dur)
    if not f then return end
    if not f:IsShown() then return end
    ns._fades[f] = { t = 0, dur = dur or 0.12, from = f:GetAlpha(), to = 0, hide = true }
end

-- Snap a movable frame's centre to the config grid (32 px).
function ns.SnapToGrid(f, step)
    if not f or not f.GetCenter then return end
    step = step or 32
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then return end
    local ox = math.floor((cx - ux) / step + 0.5) * step
    local oy = math.floor((cy - uy) / step + 0.5) * step
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
end

-- Unified font + optional large/readable mode. Applied to the window titles
-- and labels so every window uses one font.
function ns.UIFontScale()
    return ((DH.GetSetting and DH:GetSetting("ui_font_large")) == true) and 1.18 or 1
end
function ns.ApplyFont(fs, baseSize)
    if not fs then return end
    local path = ns.ResolveFont and ns.ResolveFont(DH.GetSetting and DH:GetSetting("ui_font")) or nil
    local _, h, flags = fs:GetFont()
    local size = math.floor((baseSize or h or 12) * ns.UIFontScale() + 0.5)
    if path then
        fs:SetFont(path, size, flags or "")
    elseif ns.UIFontScale() ~= 1 and h then
        fs:SetFontObject(fs:GetFontObject())
        fs:SetFont(fs:GetFont() and select(1, fs:GetFont()) or STANDARD_TEXT_FONT, size, flags or "")
    end
end



-- Resolve a font setting value to a font path. Accepts an LSM media name, a
-- raw path, or "" / "default" (meaning: keep the client default font).
function ns.ResolveFont(name)
    if not name or name == "" or name == "default" then return nil end
    if name:find("\\") then return name end
    if LSM then
        local p = LSM:Fetch("font", name, true)
        if p and p ~= "" then return p end
    end
    return nil
end

-- Resolve a sound setting value to a sound file path (LSM name or raw path).
function ns.ResolveSound(name)
    if not name or name == "" or name == "default" then return nil end
    if name:find("\\") or name:find("/") then return name end
    if LSM then
        local p = LSM:Fetch("sound", name, true)
        if p and p ~= "" then return p end
    end
    return nil
end

function ns.ListFonts()
    local out = { { value = "default", text = "Default" } }
    if LSM then
        local list = LSM:List("font")
        if list then
            for _, n in ipairs(list) do out[#out + 1] = { value = n, text = n } end
        end
    end
    return out
end

function ns.ListSounds()
    local out = {
        { value = "default", text = "Default" },
        { value = "Sound\\Interface\\AlarmClockWarning3.wav", text = "Alarm" },
        { value = "Sound\\Interface\\ReadyCheck.wav", text = "Ready check" },
        { value = "Sound\\Interface\\MapPing.wav", text = "Map ping" },
        { value = "Sound\\Spells\\Raid_Heal_Spell.wav", text = "Raid heal" },
        { value = "Sound\\Interface\\PVPFlagTaken.wav", text = "Flag taken" },
        { value = "Sound\\Interface\\LevelUp.wav", text = "Level up" },
    }
    if LSM then
        local list = LSM:List("sound")
        if list then
            for _, n in ipairs(list) do out[#out + 1] = { value = n, text = n } end
        end
    end
    return out
end

-- Action bar button name prefixes (3.3.5a)
local BAR_PREFIXES = {
    "ActionButton", "BonusActionButton",
    "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarLeftButton", "MultiBarRightButton",
    "MultiBar5Button", "MultiBar6Button",
    "ShapeshiftButton", "StanceButton",
    "PetActionButton", "PossessButton",
    -- Shaman multi-cast (totem) bar
    "MultiCastSummonSpellButton", "MultiCastRecallSpellButton", "MultiCastActionSpellButton",
}

-- Frame names that may hold a shapeshift/stance button
local SHAPESHIFT_NAMES = { "ShapeshiftButton", "StanceButton" }

local MAX_INDEX = 60
local SCAN_INTERVAL = 0.5        -- refresh button/icon index this often
local FULL_SCAN_INTERVAL = 3.0   -- full EnumerateFrames pass this often
local TEST_DURATION = 5

-- ============================================================================
-- SCAN STATE
-- ============================================================================

local scan = {
    buttons = {},   -- list of candidate action bar buttons
    at = 0,
    fullAt = 0,
    dirty = true,   -- force a full rescan on next update
}

ns.glowVisible = true
local activeGlows = {}   -- buttons currently glowing (reset every update)
local warnedMissing = {} -- ability keys already reported as "not on a bar"
local testUntil = 0
local snapshot = {}
local snapshotAt = -1  -- scan.at generation represented by `snapshot` (M13)

-- ============================================================================
-- BUTTON DISCOVERY
-- ============================================================================

local function IsButton(btn)
    return type(btn) == "table" and btn.IsObjectType and btn:IsObjectType("Button")
end

-- Read a button attribute, also checking the "*key" wildcard form used by
-- the default 3.3.5a action buttons (SetAttribute("*type1", "action")).
local function GetAttr(btn, key)
    if not btn.GetAttribute then return nil end
    local v = btn:GetAttribute(key)
    if v == nil then
        v = btn:GetAttribute("*" .. key)
    end
    return v
end

local function GetButtonAction(btn)
    local action = rawget(btn, "action")
    if action then return action end
    return GetAttr(btn, "action1") or GetAttr(btn, "action")
end

local function HasPrefix(name, prefix)
    return name:sub(1, #prefix) == prefix
end

local function IsCandidate(btn)
    if not IsButton(btn) then return false end

    local name = btn.GetName and btn:GetName()
    if name then
        if name:find("Minimap", 1, true) then return false end
        for i = 1, #BAR_PREFIXES do
            if HasPrefix(name, BAR_PREFIXES[i]) then return true end
        end
    end

    if GetButtonAction(btn) then return true end
    if GetAttr(btn, "type1") == "spell" then return true end

    -- Third-party bars (Bartender, Dominos, ...) - button with an icon texture
    -- living inside a frame whose name mentions a bar.
    if name and name:find("Button", 1, true) and rawget(btn, "icon") then
        local parent = btn:GetParent()
        local pname = parent and parent.GetName and parent:GetName() or ""
        if name:find("Bar", 1, true) or pname:find("Bar", 1, true) then
            return true
        end
    end

    return false
end

local function CollectButtons(full)
    local list, seen = {}, {}

    local function add(btn)
        if btn and not seen[btn] and IsCandidate(btn) then
            seen[btn] = true
            list[#list + 1] = btn
        end
    end

    -- Known bar button names
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, MAX_INDEX do
            local btn = _G[prefix .. i]
            if not btn then break end
            add(btn)
        end
    end

    -- Shapeshift/stance buttons: remember the form name for matching
    local numForms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, numForms do
        local _, formName
        if GetShapeshiftFormInfo then
            _, formName = GetShapeshiftFormInfo(i)
        end
        for _, base in ipairs(SHAPESHIFT_NAMES) do
            local btn = _G[base .. i]
            if btn then
                add(btn)
                if formName then btn._phFormName = formName end
            end
        end
    end

    -- Full pass to catch everything else (third-party action bars, etc.)
    if full and EnumerateFrames then
        local frame = EnumerateFrames()
        while frame do
            if IsCandidate(frame) then add(frame) end
            frame = EnumerateFrames(frame)
        end
    end

    return list
end

local function Rescan(full)
    scan.buttons = CollectButtons(full or false)
    scan.at = GetTime()
    if full then scan.fullAt = scan.at end
    scan.dirty = false
end

local function EnsureScan()
    local now = GetTime()
    if (now - scan.fullAt) >= FULL_SCAN_INTERVAL then
        -- Full client-wide scan is expensive; rate-limit it even when events
        -- (macro drags, etc.) keep marking us dirty.
        Rescan(true)
    elseif scan.dirty or (now - scan.at >= SCAN_INTERVAL) then
        Rescan(false)
    end
end

-- Events that can change which buttons exist / what they show
local scanEvents = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_ENTERING_WORLD",
    "ACTIONBAR_SHOWSTATE",
    "ACTIONBAR_UPDATE_PAGE",
    "ACTIONBAR_SLOT_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM",
    "PET_BAR_SHOW",
    "PET_BAR_HIDE",
}) do
    scanEvents:RegisterEvent(event)
end
scanEvents:SetScript("OnEvent", function()
    scan.dirty = true
end)

-- ============================================================================
-- SNAPSHOT (one pass per update, then pure Lua matching)
-- ============================================================================

local function BuildSnapshot()
    -- The action bar only changes on events that trigger Rescan(); reuse the
    -- snapshot until the next rescan instead of rebuilding every update tick.
    if snapshotAt == scan.at then return snapshot end
    snapshotAt = scan.at
    wipe(snapshot)
    local buttons = scan.buttons

    for i = 1, #buttons do
        local btn = buttons[i]
        local action = GetButtonAction(btn)
        local tex, id

        if action then
            tex = GetActionTexture(action)
            local t
            t, id = GetActionInfo(action)
            if t ~= "spell" then id = nil end
        end

        local icon = rawget(btn, "icon")
        if (not tex or tex == "") and icon and icon.GetTexture then
            tex = icon:GetTexture()
        end
        if tex == "" then tex = nil end

        local attrSpell
        if GetAttr(btn, "type1") == "spell" then
            attrSpell = GetAttr(btn, "spell1")
        end

        local name
        if id and GetSpellInfo then name = GetSpellInfo(id) end

        snapshot[#snapshot + 1] = {
            btn = btn,
            tex = tex,
            id = id,
            name = name,
            spell = attrSpell,
            formName = rawget(btn, "_phFormName"),
        }
    end

    return snapshot
end

local function SnapMatches(s, tex, id, lowerName)
    if tex and s.tex and s.tex == tex then return true end
    if id and s.id and s.id == id then return true end
    if lowerName then
        if s.formName and s.formName:lower() == lowerName then return true end
        if s.spell and s.spell:lower() == lowerName then return true end
        if s.name and s.name:lower() == lowerName then return true end
    end
    return false
end

-- ============================================================================
-- GLOW WIDGETS
-- ============================================================================

local function PulseEnabled()
    local display = DH.db and DH.db.display
    return not display or display.pulse ~= false
end

-- Glow animation settings are read every frame by every glowing button. Cache
-- them and only refresh when a setting changes (DH:SetSetting bumps the token).
local MAX_GLOW_LINES = 6
local glowCache = { version = false, style = "pulse", flash = FLASH_RATE, pulse = true,
                    freq = 1.0, thickness = 1.5, lines = 1 }
local function RefreshGlowCache()
    local v = ns.glowCacheVersion
    if glowCache.version == v then return end
    glowCache.version = v
    glowCache.style = (DH.GetSetting and DH:GetSetting("glow_style")) or "pulse"
    glowCache.flash = (DH.GetSetting and DH:GetSetting("proc_flash_speed")) or FLASH_RATE
    glowCache.pulse = PulseEnabled()
    -- v3.4.0-hotfix6: glow_frequency / glow_thickness / glow_lines are honoured
    local f = tonumber(DH.GetSetting and DH:GetSetting("glow_frequency")) or 1.0
    local t = tonumber(DH.GetSetting and DH:GetSetting("glow_thickness")) or 1.5
    local l = tonumber(DH.GetSetting and DH:GetSetting("glow_lines")) or 1
    if f < 0.25 then f = 0.25 elseif f > 3 then f = 3 end
    if t < 0.8 then t = 0.8 elseif t > 2.5 then t = 2.5 end
    l = math.floor(l + 0.5)
    if l < 1 then l = 1 elseif l > MAX_GLOW_LINES then l = MAX_GLOW_LINES end
    glowCache.freq, glowCache.thickness, glowCache.lines = f, t, l
end

local function EnsureGlow(btn)
    local glow = rawget(btn, "_phGlow")
    if glow then return glow end

    glow = CreateFrame("Frame", nil, btn)
    glow:SetAllPoints(btn)
    glow:EnableMouse(false)
    glow:SetFrameStrata(btn:GetFrameStrata() or "MEDIUM")
    glow:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)

    -- Concentric border rings (glow_lines controls how many are shown).
    glow.rings = {}
    for i = 1, MAX_GLOW_LINES do
        local tex = glow:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(GLOW_TEXTURE)
        tex:SetBlendMode("ADD")
        tex:SetPoint("CENTER")
        tex:Hide()
        glow.rings[i] = tex
    end

    glow.flash = glow:CreateTexture(nil, "OVERLAY")
    glow.flash:SetTexture(GLOW_TEXTURE)
    glow.flash:SetBlendMode("ADD")
    glow.flash:SetPoint("CENTER")
    glow.flash:SetVertexColor(1, 1, 1)
    glow.flash:Hide()

    glow.label = glow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    glow.label:SetPoint("TOPRIGHT", glow, "TOPRIGHT", 3, 3)
    glow.label:SetTextColor(1, 1, 1)
    glow.label:SetShadowOffset(1, -1)

    -- Optional "next cast" guide marker (a bobbing chevron above the button).
    glow.arrow = glow:CreateTexture(nil, "OVERLAY", nil, 7)
    glow.arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    glow.arrow:SetSize(22, 18)
    glow.arrow:SetPoint("BOTTOM", glow, "TOP", 0, 0)
    glow.arrow:SetVertexColor(1, 0.82, 0)
    glow.arrow:Hide()

    glow.t = 0
    glow.prio = 1
    glow.flashOn = false
    glow.ringCount = 0

    glow:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        if self.arrow and self.arrow:IsShown() then
            self.arrow:SetPoint("BOTTOM", self, "TOP", 0, math.sin(self.t * 4) * 3)
        end
        RefreshGlowCache()
        local style = PRIORITY_STYLE[self.prio] or PRIORITY_STYLE[1]
        local gs = glowCache.style
        local freq = glowCache.freq
        local rings = self.ringCount
        local r, g, b = style.r, style.g, style.b
        local amp = style.amp or 0.5
        local base = style.base or 0.5
        local taper = not (gs == "chase" or gs == "wave" or gs == "shimmer" or gs == "rainbow")

        for i = 1, rings do
            local tex = self.rings[i]
            if tex then
                local a
                if gs == "static" then
                    a = 1
                elseif gs == "flash" then
                    a = (math.sin(self.t * (glowCache.flash or FLASH_RATE) * freq * 6.28318) > 0) and 1 or 0.15
                elseif gs == "rainbow" then
                    local rr, gg, bb = HueToRGB((self.t * 0.25 * freq + (i - 1) * 0.08) % 1)
                    tex:SetVertexColor(rr, gg, bb)
                    a = math.min(1, base + amp)
                elseif gs == "breathe" then
                    a = base + amp * 0.6 * math.sin(self.t * style.freq * freq * 0.35 * 6.28318)
                elseif gs == "chase" then
                    local head = (self.t * freq * 2.0) % math.max(1, rings)
                    local d = math.abs((i - 1) - head)
                    d = math.min(d, rings - d)
                    a = 0.15 + 0.85 * (1 - math.min(1, d / 2))
                elseif gs == "wave" then
                    a = 0.2 + 0.8 * math.abs(math.sin(self.t * freq * 1.5 + (i - 1) * 0.9))
                elseif gs == "shimmer" then
                    a = 0.3 + 0.7 * math.abs(math.sin(self.t * freq * 6.0 + i * 12.9898))
                else
                    if glowCache.pulse then
                        a = base + amp * math.sin(self.t * style.freq * freq * 6.28318)
                    else
                        a = math.min(1, base + amp)
                    end
                end
                if taper then a = a - (i - 1) * 0.12 end
                if a < 0.05 then a = 0.05 elseif a > 1 then a = 1 end
                if gs ~= "rainbow" then tex:SetVertexColor(r, g, b) end
                tex:SetAlpha(a)
            end
        end

        if self.flashOn then
            local rate = glowCache.flash
            local a = math.sin(self.t * rate * 6.28318)
            self.flash:SetAlpha(a > 0 and 0.95 or 0.2)
        end
    end)

    btn._phGlow = glow
    return glow
end

local function ShowGlow(btn, prio, flash)
    local display = DH.db and DH.db.display or {}

    local style = PRIORITY_STYLE[prio] or PRIORITY_STYLE[1]
    local glow = EnsureGlow(btn)

    glow.prio = prio
    glow:SetFrameStrata(btn:GetFrameStrata() or "MEDIUM")
    glow:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
    glow:ClearAllPoints()
    glow:SetAllPoints(btn)

    local width = btn:GetWidth() or 36
    if width < 8 then width = 36 end
    local lines = glowCache.lines or 1
    local thickness = glowCache.thickness or (display.glow_size or 1.5)
    local size = width * thickness

    if LCG and LCG.PixelGlow_Start then
        -- Library renderer: hide our rings and let LibCustomGlow draw.
        for i = 1, MAX_GLOW_LINES do
            if glow.rings[i] then glow.rings[i]:Hide() end
        end
        glow.ringCount = 0
        LCG.PixelGlow_Start(btn, { style.r, style.g, style.b, 1 }, lines, glowCache.freq, nil, thickness * 8)
    else
        glow.ringCount = lines
        for i = 1, MAX_GLOW_LINES do
            local tex = glow.rings[i]
            if tex then
                if i <= lines then
                    local ringSize = size + (i - 1) * width * 0.12
                    tex:SetSize(ringSize, ringSize)
                    tex:SetVertexColor(style.r, style.g, style.b)
                    tex:Show()
                else
                    tex:Hide()
                end
            end
        end
    end
    glow.flash:SetSize(size, size)

    if display.show_numbers ~= false then
        glow.label:SetText(prio)
        glow.label:SetTextColor(style.r, style.g, style.b)
    else
        glow.label:SetText("")
    end

    -- REC1 extra flash while proc_flash is enabled (rate = proc_flash_speed)
    local procFlash = prio == 1 and DH.GetSetting and DH:GetSetting("proc_flash")
    glow.flashOn = (flash or procFlash) and true or false
    if glow.flashOn then
        glow.flash:Show()
    else
        glow.flash:Hide()
    end

    if glow.arrow then
        if prio == 1 and (DH.GetSetting and DH:GetSetting("guide_marker")) then
            glow.arrow:SetVertexColor(style.r, style.g, style.b)
            glow.arrow:Show()
        else
            glow.arrow:Hide()
        end
    end

    glow:Show()
    activeGlows[#activeGlows + 1] = btn
end

local function HideGlow(btn)
    local glow = rawget(btn, "_phGlow")
    if glow then
        glow.flashOn = false
        glow.flash:Hide()
        glow.label:SetText("")
        if glow.arrow then glow.arrow:Hide() end
        if glow.rings then
            for i = 1, MAX_GLOW_LINES do
                if glow.rings[i] then glow.rings[i]:Hide() end
            end
        end
        glow.ringCount = 0
        if LCG and LCG.PixelGlow_Stop then LCG.PixelGlow_Stop(btn) end
        glow:Hide()
    end
end

function ns.ClearGlows()
    for i = 1, #activeGlows do
        HideGlow(activeGlows[i])
    end
    wipe(activeGlows)
end

-- ============================================================================
-- UPDATE
-- ============================================================================

function ns.InitializeUI(addon)
    if ns.UI.initialized then return end
    ns.UI.initialized = true
    ns.UI.MainFrame = nil      -- no separate icon frame anymore
    ns.UI.Buttons = {}         -- legacy, kept so old code does not break
    scan.dirty = true
end

function ns.ShowTestGlow()
    Rescan(true)
    testUntil = GetTime() + TEST_DURATION
    DH:Print(string.format(L("Action buttons found: %d (test glow for %ds)"), #scan.buttons, TEST_DURATION))
    if #scan.buttons == 0 then
        DH:Print(L("No action bars detected"))
    end
    ns.UpdateUI(DH)
end

-- True while the "glow test" is active. The main update loop checks this so
-- the test keeps working even with no target / out of combat (it would
-- otherwise be cancelled by HideUI before ever reaching UpdateUI).
function ns.IsTestGlow()
    return GetTime() < testUntil
end

function ns.GetScanCount()
    return #scan.buttons
end

function ns.UpdateUI(addon)
    addon = addon or DH
    if not ns.UI.initialized then
        ns.InitializeUI(addon)
    end

    EnsureScan()
    if ns.ApplyPalette then ns.ApplyPalette() end
    ns.ClearGlows()

    -- Optional cooldown / interrupt / timeline windows update every tick
    if ns.UpdateCooldownsFrame then ns.UpdateCooldownsFrame() end
    if ns.UpdateInterruptsFrame then ns.UpdateInterruptsFrame() end
    if ns.UpdateTimelineFrame then ns.UpdateTimelineFrame() end

    local function ShowWindow(recs)
        if ns.UpdateSpellFrame then
            ns.UpdateSpellFrame(recs or {})
        end
    end

    -- Test mode: glow the first few detected buttons. Checked BEFORE the
    -- enabled/target gates so the test always shows something.
    if GetTime() < testUntil then
        for i = 1, math.min(3, #scan.buttons) do
            ShowGlow(scan.buttons[i], i, false)
        end
        ShowWindow(ns.recommendations)
        ns.UpdateDebugFrame()
        return
    end

    if not addon.db or not addon.db.enabled then
        ShowWindow({})
        ns.UpdateDebugFrame()
        return
    end

    local now = GetTime()

    if not ns.glowVisible then
        ShowWindow({})
        ns.UpdateDebugFrame()
        return
    end

    local display = addon.db.display or {}

    -- Optional: only highlight while in combat
    if display.combat_only and not ns.inCombat then
        ShowWindow({})
        ns.UpdateDebugFrame()
        return
    end

    local recs = ns.recommendations or {}
    if #recs == 0 then
        ShowWindow({})
        ns.UpdateDebugFrame()
        return
    end

    local maxShow = display.num_icons or 1
    local classes = addon.Class and addon.Class.abilities or {}

    local snap = BuildSnapshot()
    local assigned = {}

    -- v3.3.0 exam mode: never highlight the action bars, so the player has to
    -- recognise the ability from the icon window alone.
    local examMode = DH.GetSetting and DH:GetSetting("exam_mode")
    if not examMode then
        for prio = 1, math.min(maxShow, #recs) do
            local rec = recs[prio]
            local ability = classes[rec.ability]
            local tex = (ability and ability.texture) or rec.texture
            local id = ability and ability.id
            -- Prefer the localized spell name from the client (GetSpellInfo)
            -- over the module's English name so RU clients match RU buttons
            local dispName = (id and GetSpellInfo and GetSpellInfo(id))
                or (ability and ability.name) or rec.name or ""
            local lowerName = dispName ~= "" and dispName:lower() or nil

            local found = false
            for i = 1, #snap do
                local s = snap[i]
                if not assigned[s.btn] and SnapMatches(s, tex, id, lowerName) then
                    assigned[s.btn] = prio
                    ShowGlow(s.btn, prio, ns.glowButtons and ns.glowButtons[prio])
                    found = true
                end
            end

            -- Warn once if the recommended ability is not on any action bar
            if not found and prio == 1 and #snap > 0 and rec.ability and not warnedMissing[rec.ability] then
                warnedMissing[rec.ability] = true
                local abilityName = dispName ~= "" and dispName or rec.ability
                DH:Print(string.format(L("'%s' is not on your action bars - place it on a bar to see its glow."), abilityName))
            end
        end
    end

    -- Icon window shows the same picks
    local shown = {}
    for i = 1, math.min(maxShow, #recs) do
        shown[i] = recs[i]
    end
    ShowWindow(shown)

    ns.UpdateDebugFrame()
end

-- ============================================================================
-- SHOW / HIDE
-- ============================================================================

function ns.ShowUI()
    if ns.playerDead then return end
    ns.glowVisible = true
end

function ns.HideUI()
    ns.glowVisible = false
    ns.ClearGlows()
end

-- ============================================================================
-- DEBUG FRAME (live state, toggled with /rc live)
-- ============================================================================

local function CreateDebugFrame()
    if ns.DebugFrame then return ns.DebugFrame end

    local frame = CreateFrame("Frame", "RotationCoreDebugFrame", UIParent)
    frame:SetSize(260, 130)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -200)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetTexture(0, 0, 0, 0.8)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.text:SetPoint("TOPLEFT", 5, -5)
    frame.text:SetPoint("BOTTOMRIGHT", -5, 5)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")

    frame:Hide()
    ns.DebugFrame = frame
    return frame
end

-- Update debug frame - class modules can override this
function ns.UpdateDebugFrame()
    if not DH.db or not DH.db.show_debug_frame then
        if ns.DebugFrame then ns.DebugFrame:Hide() end
        return
    end
    if not ns.DebugFrame then CreateDebugFrame() end

    local function AppendEmptyHint()
        -- Empty queue with buttons on the bar = everything was filtered as
        -- unknown (spellbook scan failed / abilities moved) - say so instead
        -- of a bare "Rec: none > none > none"
        if #ns.recommendations == 0 and #scan.buttons > 0 and ns.DebugFrame.text then
            local cur = ns.DebugFrame.text:GetText()
            ns.DebugFrame.text:SetText((cur or "") .. "\n|cFFFF6060No recs (all unknown?)|r")
        end
    end

    -- Use class-registered debug frame updater if available
    if ns.registered.debugFrameUpdater then
        ns.registered.debugFrameUpdater()
        AppendEmptyHint()
        return
    end

    -- Generic fallback
    local recs = ns.recommendations
    local rec1 = recs[1] and recs[1].ability or "none"
    local rec2 = recs[2] and recs[2].ability or "none"
    local rec3 = recs[3] and recs[3].ability or "none"

    local tgt = "none"
    if UnitExists and UnitExists("target") then
        tgt = UnitName and UnitName("target") or "?"
    end

    local lines = {
        "|cFFFFFF00=== Live Debug ===|r",
        string.format("Addon: %s", (DH.db.enabled and "enabled") or "|cFFFF5050disabled|r"),
        string.format("Spec: %s", DH:GetActiveSpec()),
        string.format("Target: %s", tgt),
    }
    if #recs == 0 then
        local reason = (DH.GetIdleReason and DH:GetIdleReason()) or "no valid recommendation"
        lines[#lines + 1] = string.format("|cFFFFFF00Rec: none|r  (%s)", reason)
    else
        lines[#lines + 1] = string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3)
    end
    lines[#lines + 1] = string.format("Bars: %d buttons", #scan.buttons)

    ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
    AppendEmptyHint()
    ns.DebugFrame:Show()
end
