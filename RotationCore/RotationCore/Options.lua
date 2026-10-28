-- Options.lua
-- In-game settings window + profile management (3.3.5a, no dependencies)
--
-- Opened with /rc options. Categories on the left:
--   General   - enable/disable, target mode, activity, theme, Setup Wizard
--   Display   - spell queue, glow, colours, animations, layout, behaviour
--   Class     - per-spec ability switches (advanced menu mode only)
--   Profiles  - create/switch/reset/delete/import/export, boss profiles
--   Advanced  - scanner, windows, timeline, APL, coaching, debug
--   Help      - quick start, commands, hotkeys, FAQ
-- Simple menu mode shows General / Display / Profiles / Help; "advanced"
-- additionally shows Class / Advanced. Toggling "Menu mode" re-runs
-- BuildContent() so the tabs appear / disappear without a reload.
--
-- The window is created lazily (only when opened) and rebuilt whenever a
-- setting changes (DH:RefreshOptions). Widgets never read the database at
-- file scope - that was the bug that used to lose settings on restart.

local DH = RotationCore
if not DH then return end

local ns = DH.ns

local FRAME_NAME = "RotationCoreOptions"
local CONTENT_WIDTH = 400

-- Menu sections. The old single "General" tab was split into General
-- (core), Interface (icon-window look) and Advanced (glow / scanner /
-- debug). Categories flagged `advanced = true` are only listed when the
-- "Menu mode" setting is "advanced"; the wizard stays reachable through a
-- button inside General.
local CATEGORIES = {
    { key = "general", label = "General", icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { key = "display", label = "Display", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
    { key = "training", label = "Training", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "healer", label = "Healer", healerOnly = true, icon = "Interface\\Icons\\Spell_Holy_HolyBolt" },
    { key = "class", label = "Class", advanced = true, sepBefore = true, icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
    { key = "coaching", label = "Coaching", advanced = true, icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "timeline", label = "Timeline", advanced = true, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    { key = "system", label = "System", advanced = true, icon = "Interface\\Icons\\Trade_Engineering" },
    { key = "advanced", label = "Advanced", advanced = true, icon = "Interface\\Icons\\INV_Misc_Wrench_01" },
    { key = "status", label = "Status", advanced = true, icon = "Interface\\Icons\\INV_Misc_Note_05" },
    { key = "profiles", label = "Profiles", sepBefore = true, icon = "Interface\\Icons\\INV_Misc_Book_06" },
    { key = "help", label = "Help", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
}

-- "Menu mode" dependency (General > Menu mode): "simple" hides the advanced
-- categories, "advanced" lists everything. Anything unresolved falls back to
-- "simple" so the window is never empty.
local function MenuMode()
    local v = DH.GetSetting and DH:GetSetting("menu_mode")
    if v == "advanced" then return "advanced" end
    return "simple"
end

-- Returns the list of categories that are visible for the current menu mode.
local function VisibleCategories()
    local out = {}
    local adv = (MenuMode() == "advanced")
    for _, cat in ipairs(CATEGORIES) do
        local ok = (not cat.advanced) or adv
        if ok then out[#out + 1] = cat end
    end
    return out
end

-- True when the given category key is currently listed.
local function IsCategoryVisible(key)
    for _, cat in ipairs(VisibleCategories()) do
        if cat.key == key then return true end
    end
    return false
end

-- Phase 3.2: decoded profile waiting for the replace/create-new choice
local pendingImport = nil

-- Localization helper (Locale.lua fills DH.L; missing keys return themselves
-- so the EN client always shows the original strings - part G)
local function L(s)
    if type(s) ~= "string" then return s end
    local tbl = rawget(DH, "L")
    if tbl and tbl[s] then return tbl[s] end
    return s
end

-- Top-level keys that belong to the core, not to a class module
local CORE_KEYS = {
    enabled = true,
    debug = true,
    show_debug_frame = true,
    auto_mode = true,
    display = true,
    spellFrame = true,
    minimap = true,
    mode = true,
}

local frame, content, scroll
local resizeStart
local catButtons = {}         -- keyed by category key (see CATEGORIES)
local rows = {}       -- widgets of the current build (for rebuilding)
local cursor = -12     -- y offset inside the scroll child
local currentCat = "general"
local uid = 0
local LayoutCatButtons        -- forward declaration (position/show visible tabs)
local BuildContent            -- forward declaration (cat-button OnClick captures this local)

local function NewName()
    uid = uid + 1
    return "PHOpt" .. uid
end

local function Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Creates a fontstring in the content scroll child and applies the unified
-- font + large-text scale, so the "Large / readable text" toggle affects the
-- body text of every tab (not just the window titles).
local function ContentFS(olayer, template)
    local fs = content:CreateFontString(nil, olayer or "OVERLAY", template or "GameFontNormal")
    if ns and ns.ApplyFont then ns.ApplyFont(fs) end
    return fs
end

-- ============================================================================
-- v3.4.0 DESIGN TOKENS. 8px grid; colours come from the active theme
-- (DH:GetUITheme) so "dark"/"light" work everywhere. Widget spacing uses
-- these constants so the layout stays modular.
-- ============================================================================

local S = {
    pad = 16,             -- content padding from the frame edge
    sectionGap = 24,      -- between two sections
    elemGap = 8,          -- between sibling widgets
    headToContent = 12,   -- section title -> first widget
    hdr = 30,             -- section header row height
}

-- Per-theme content colours. Rebuilt on every BuildContent() so switching
-- dark/light repaints every label immediately, without a reload.
local PAL = {
    header = { 1, 0.82, 0 },
    text = { 0.95, 0.95, 0.95 },
    info = { 0.75, 0.75, 0.75 },
    note = { 0.62, 0.62, 0.62 },
}
local function UpdatePalette()
    local light = (DH.GetSetting and DH:GetSetting("theme") == "light")
    if light then
        PAL.header = { 0.45, 0.30, 0 }
        PAL.text = { 0.12, 0.12, 0.12 }
        PAL.info = { 0.28, 0.28, 0.28 }
        PAL.note = { 0.38, 0.38, 0.38 }
    else
        PAL.header = { 1, 0.82, 0 }
        PAL.text = { 0.95, 0.95, 0.95 }
        PAL.info = { 0.75, 0.75, 0.75 }
        PAL.note = { 0.62, 0.62, 0.62 }
    end
end

-- Dependency helper: every Add* accepts an optional `cond` parameter (a
-- function). When it returns false the widget is skipped, so toggling a
-- parent (e.g. use_cooldowns) makes its children appear/disappear without a
-- reload. BuildContent() re-evaluates all conditions on every rebuild.
local function Passes(cond)
    if type(cond) == "function" then return not not cond() end
    return true
end

-- String settings with a known set of values are rendered as dropdowns;
-- any other string falls back to AddInfo (part 1, string -> AddInfo)
local STRING_CHOICES = {
    target_mode = {
        { value = "single", text = "Single target" },
        { value = "cleave", text = "Cleave" },
        { value = "aoe", text = "AOE" },
        { value = "auto", text = "Auto (single/cleave/aoe)" },
    },
    build_detect_mode = {
        { value = "off", text = "Off (use spec only)" },
        { value = "talents", text = "Talents" },
        { value = "talents_glyphs", text = "Talents + Glyphs" },
        { value = "talents_glyphs_stats", text = "Talents + Glyphs + Stats" },
    },
    cooldown_order = {
        { value = "priority", text = "Priority (default)" },
        { value = "burst", text = "Burst (cooldowns first)" },
        { value = "manual", text = "Manual (no cooldowns)" },
    },
    activity_profile = {
        { value = "auto", text = "Auto" },
        { value = "raid", text = "Raid" },
        { value = "dungeon", text = "Dungeon" },
        { value = "solo", text = "Solo" },
        { value = "pvp", text = "PvP" },
    },
    glow_style = {
        { value = "pulse", text = "Pulse" },
        { value = "static", text = "Static" },
        { value = "flash", text = "Flash" },
        { value = "rainbow", text = "Rainbow" },
        { value = "breathe", text = "Breathe" },
        { value = "chase", text = "Chase" },
        { value = "wave", text = "Wave" },
        { value = "shimmer", text = "Shimmer" },
    },
    menu_mode = {
        { value = "simple", text = "Simple" },
        { value = "advanced", text = "Advanced" },
    },
    theme = {
        { value = "class", text = "Class color" },
        { value = "custom", text = "Custom" },
        { value = "dark", text = "Dark" },
        { value = "light", text = "Light" },
        { value = "contrast", text = "High contrast" },
    },
    heal_dps_mode = {
        { value = "auto", text = "Auto (solo only)" },
        { value = "on", text = "Always" },
        { value = "off", text = "Off" },
    },
    color_palette = {
        { value = "default", text = "Default (green/yellow/blue)" },
        { value = "protanopia", text = "Protanopia (orange/yellow/blue)" },
        { value = "deuteranopia", text = "Deuteranopia (blue/yellow/purple)" },
        { value = "tritanopia", text = "Tritanopia (red/green/grey)" },
        { value = "high_contrast", text = "High contrast (white/black/yellow)" },
    },
    display_layout = {
        { value = "center", text = "Center" },
        { value = "side", text = "Side" },
        { value = "minimal", text = "Minimal" },
        { value = "raid", text = "Raid" },
        { value = "custom", text = "Custom" },
    },
    adaptive_rotation = {
        { value = "auto", text = "Auto (by item level)" },
        { value = "simple", text = "Simple" },
        { value = "normal", text = "Normal" },
        { value = "complex", text = "Complex" },
    },
    aux_position = {
        { value = "above_spellframe", text = "Above the icon window" },
        { value = "below_spellframe", text = "Below the icon window" },
        { value = "left_of_spellframe", text = "Left of the icon window" },
        { value = "right_of_spellframe", text = "Right of the icon window" },
    },
    ui_skin = {
        { value = "default", text = "Default" },
        { value = "elvui", text = "ElvUI" },
        { value = "minimal", text = "Minimal" },
        { value = "classic", text = "Classic" },
        { value = "fel", text = "Fel (green)" },
        { value = "frost", text = "Frost (blue)" },
        { value = "void", text = "Void (purple)" },
        { value = "blood", text = "Blood (red)" },
        { value = "jade", text = "Jade (teal)" },
        { value = "gold", text = "Gold (amber)" },
        { value = "ember", text = "Ember (orange)" },
    },
    arena_mode = {
        { value = "auto", text = "Auto (by zone)" },
        { value = "2v2", text = "2v2" },
        { value = "3v3", text = "3v3" },
        { value = "5v5", text = "5v5" },
    },
}

local function GetPath(path)
    local t = DH.db
    for seg in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[seg]
    end
    if type(t) == "table" then return nil end
    return t
end

local function SetPath(path, value)
    local t = DH.db
    if type(t) ~= "table" then return end
    local segs = {}
    for seg in path:gmatch("[^%.]+") do
        segs[#segs + 1] = seg
    end
    for i = 1, #segs - 1 do
        if type(t[segs[i]]) ~= "table" then
            t[segs[i]] = {}
        end
        t = t[segs[i]]
    end
    t[segs[#segs]] = value
end

-- ============================================================================
-- ROW BUILDERS (all widgets are created inside the scroll child)
-- ============================================================================

local function AddRow(height)
    local y = cursor
    cursor = cursor - height
    return y
end

local function AddHeader(text, cond)
    if not Passes(cond) then return end
    cursor = cursor - 14           -- extra gap above a section title
    local y = AddRow(46)
    local fs = ContentFS("OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y - 5)
    fs:SetText(L(text))
    fs:SetTextColor(PAL.header[1], PAL.header[2], PAL.header[3])
    rows[#rows + 1] = fs
    -- Section divider: a small accent pip followed by a hairline that fades
    -- out towards the right edge, placed clearly below the title.
    local pip = content:CreateTexture(nil, "ARTWORK")
    pip:SetSize(6, 6)
    pip:SetPoint("LEFT", content, "TOPLEFT", 17, y - 28)
    pip:SetTexture(1, 1, 1)
    pip:SetVertexColor(PAL.header[1], PAL.header[2], PAL.header[3], 0.9)
    rows[#rows + 1] = pip
    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", content, "TOPLEFT", 27, y - 28)
    line:SetPoint("RIGHT", content, "TOPRIGHT", -14, y - 28)
    line:SetTexture(1, 1, 1)
    if line.SetGradientAlpha then
        line:SetGradientAlpha("HORIZONTAL",
            PAL.header[1], PAL.header[2], PAL.header[3], 0.6,
            PAL.header[1], PAL.header[2], PAL.header[3], 0)
    else
        line:SetVertexColor(PAL.header[1], PAL.header[2], PAL.header[3], 0.3)
    end
    rows[#rows + 1] = line
    -- Optional hover description for the section (locale: section_<slug>_desc).
    if fs and fs.EnableMouse then
        local sk = tostring(text):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
        local dkey = "section_" .. sk .. "_desc"
        local desc = DH.L and DH.L[dkey]
        if desc and desc ~= dkey then
            fs:EnableMouse(true)
            fs:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L(text), 1, 1, 1)
                GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            fs:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
    end
end

local function AddInfo(text, cond)
    if not Passes(cond) then return end
    local baseH = 16
    local y = AddRow(baseH + 4)
    local fs = ContentFS("OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 14, y - 4)
    fs:SetWidth(CONTENT_WIDTH - 34)
    fs:SetJustifyH("LEFT")
    fs:SetText(L(text))
    fs:SetTextColor(PAL.info[1], PAL.info[2], PAL.info[3])
    local realH = (fs.GetStringHeight and fs:GetStringHeight()) or baseH
    if realH > baseH then
        cursor = cursor - (realH - baseH)
    end
    rows[#rows + 1] = fs
end

-- A short line in a chosen color (priority legend, phase 1.6)
local function AddColorInfo(text, r, g, b, cond)
    if not Passes(cond) then return end
    local y = AddRow(22)
    local fs = ContentFS("OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 20, y - 4)
    fs:SetText(L(text))
    fs:SetTextColor(r or 1, g or 1, b or 1)
    rows[#rows + 1] = fs
end

-- A small grey explanation line that wraps onto as many lines as needed
local function AddNote(text, cond)
    if not Passes(cond) then return end
    local baseH = 16
    local y = AddRow(baseH + 2)
    local fs = ContentFS("OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 30, y - 1)
    fs:SetWidth(CONTENT_WIDTH - 48)
    fs:SetJustifyH("LEFT")
    fs:SetText(L(text))
    fs:SetTextColor(PAL.note[1], PAL.note[2], PAL.note[3])
    local realH = (fs.GetStringHeight and fs:GetStringHeight()) or baseH
    if realH > baseH then
        cursor = cursor - (realH - baseH)
    end
    rows[#rows + 1] = fs
end

-- Live status rows (Status tab). BuildStatus registers a function per row; a
-- lightweight ticker (see EnsureFrameRaw) refreshes just their text while the
-- Status tab is open, so the values stay current without a full rebuild.
local statusLive = {}

local function AddLiveInfo(fn, cond)
    if not Passes(cond) then return end
    local baseH = 16
    local y = AddRow(baseH + 4)
    local fs = ContentFS("OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 14, y - 4)
    fs:SetWidth(CONTENT_WIDTH - 34)
    fs:SetJustifyH("LEFT")
    fs:SetText(L(fn()) or "")
    fs:SetTextColor(PAL.info[1], PAL.info[2], PAL.info[3])
    local realH = (fs.GetStringHeight and fs:GetStringHeight()) or baseH
    if realH > baseH then
        cursor = cursor - (realH - baseH)
    end
    rows[#rows + 1] = fs
    statusLive[#statusLive + 1] = { fs = fs, fn = fn }
end

local function RefreshStatusLive()
    for i = 1, #statusLive do
        local e = statusLive[i]
        if e.fs and e.fn then
            e.fs:SetText(L(e.fn()) or "")
        end
    end
end

-- Metric tiles for the Status tab: a small framed block with a big value and
-- a label. Three per row.
local tileCol, tileRowY = 0, 0
local function AddTile(label, fn, cond)
    if not Passes(cond) then return end
    local tw, th, gap = 170, 26, 8
    local cols = 2
    if tileCol == 0 then tileRowY = AddRow(th + 8) end
    local t = CreateFrame("Frame", nil, content)
    t:SetSize(tw, th)
    t:SetPoint("TOPLEFT", content, "TOPLEFT", 16 + tileCol * (tw + gap), tileRowY)
    t:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local th2 = DH.GetUITheme and DH:GetUITheme() or nil
    if th2 then
        t:SetBackdropColor(th2.backdrop[1], th2.backdrop[2], th2.backdrop[3], 0.45)
        t:SetBackdropBorderColor(th2.border[1], th2.border[2], th2.border[3], 0.8)
    end
    local v = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    v:SetPoint("RIGHT", t, "RIGHT", -8, 0)
    v:SetJustifyH("RIGHT")
    v:SetTextColor(PAL.header[1], PAL.header[2], PAL.header[3])
    local l = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("LEFT", t, "LEFT", 8, 0)
    l:SetText(L(label))
    l:SetTextColor(PAL.info[1], PAL.info[2], PAL.info[3])
    rows[#rows + 1] = t
    statusLive[#statusLive + 1] = { fs = v, fn = fn }
    tileCol = (tileCol + 1) % cols
end

-- ============================================================================
-- PHASE 3.1: OPTION TOOLTIPS
-- Tooltip text lives in Locale.lua under:
--   tooltip_<slug>_title / _desc / _default / _affects
-- where <slug> is the option label lowercased with non-alphanumerics -> "_".
-- Shown after tooltip_delay seconds, gated by show_tooltips.
-- ============================================================================

local function Slug(text)
    local s = tostring(text):lower()
    s = s:gsub("[^%w]+", "_")
    s = s:gsub("^_+", ""):gsub("_+$", "")
    return s
end

local function GetTooltipLines(key)
    local tbl = DH.L
    if not tbl then return nil end
    -- DH.L.__index returns the key itself for missing entries, so a real
    -- translation is one whose value differs from the key. Otherwise the raw
    -- key (e.g. tooltip_priority_2_g_title) would be shown as the tooltip text.
    local function real(k)
        local v = tbl[k]
        if v == nil or v == k then return nil end
        return v
    end
    local title = real("tooltip_" .. key .. "_title")
    if not title then return nil end
    return {
        title = title,
        desc = real("tooltip_" .. key .. "_desc"),
        default = real("tooltip_" .. key .. "_default"),
        affects = real("tooltip_" .. key .. "_affects"),
    }
end

local optionTooltip = CreateFrame("GameTooltip", "RotationCoreOptionTooltip", UIParent, "GameTooltipTemplate")
optionTooltip:SetOwner(UIParent, "ANCHOR_NONE")

-- One shared timer frame for delayed tooltips (M28). `tooltipPending` holds the
-- Show closure of the widget currently under the cursor; OnLeave clears it.
local tooltipTimer = CreateFrame("Frame")
local tooltipPending
local function TooltipTimerUpdate(f, dt)
    f.acc = f.acc + dt
    if f.acc >= f.delay then
        f:SetScript("OnUpdate", nil)
        local fn = tooltipPending
        tooltipPending = nil
        if fn then fn() end
    end
end

local function AttachTooltip(widget, key, fallback)
    if not widget or not key then return end
    widget:HookScript("OnEnter", function(self)
        if DH.GetSetting and DH:GetSetting("show_tooltips") == false then return end
        local lines = GetTooltipLines(key)
        if not lines then
            if not fallback then return end
            lines = { title = L(fallback) }
        end
        local delay = (DH.GetSetting and DH:GetSetting("tooltip_delay")) or 0.3
        self.rcTooltipKey = key

        local function Show()
            if self.rcTooltipKey ~= key then return end
            local t = optionTooltip
            t:SetOwner(self, "ANCHOR_RIGHT")
            t:ClearLines()
            t:AddLine(lines.title, 1, 1, 1, true)
            if lines.desc then
                t:AddLine(lines.desc, 0.75, 0.75, 0.75, true)
            end
            t:Show()
        end

        if delay and delay > 0 then
            tooltipTimer.acc = 0
            tooltipTimer.delay = delay
            tooltipPending = Show
            tooltipTimer:SetScript("OnUpdate", TooltipTimerUpdate)
        else
            Show()
        end
    end)
    widget:HookScript("OnLeave", function(self)
        self.rcTooltipKey = nil
        tooltipPending = nil
        tooltipTimer:SetScript("OnUpdate", nil)
        optionTooltip:Hide()
    end)
end

local function AddCheckbox(label, get, set, cond)
    if not Passes(cond) then return end
    local y = AddRow(38)
    local cb = CreateFrame("CheckButton", NewName(), content, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", content, "TOPLEFT", 10, y - 4)
    local text = _G[cb:GetName() .. "Text"]
    if text then
        if text.SetWordWrap then text:SetWordWrap(false) end
        text:SetText(L(label))
        text:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
        if text.GetStringWidth and text:GetStringWidth() > (CONTENT_WIDTH - 48) then
            text:SetWidth(CONTENT_WIDTH - 48)
        end
    end
    cb:SetChecked(not not get())
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    AttachTooltip(cb, Slug(label))
    rows[#rows + 1] = cb
end

local function AddSlider(label, minV, maxV, stepV, get, set, cond, tooltipKey)
    if not Passes(cond) then return end
    local tooltipKey = tooltipKey or Slug(label)
    local y = AddRow(54)
    local name = NewName()
    local slider = CreateFrame("Slider", name, content, "OptionsSliderTemplate")
    slider:SetWidth(300)
    slider:SetPoint("TOPLEFT", content, "TOPLEFT", 8, y - 16)
    slider:SetMinMaxValues(minV, maxV)
    if slider.SetValueStep then
        slider:SetValueStep(stepV)
    end

    local function Round(v)
        local r = math.floor(v / stepV + 0.5) * stepV
        return math.floor(r * 100 + 0.5) / 100
    end

    local title = _G[name .. "Text"]
    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    -- Anchor the label above and the min/max below the slider explicitly so
    -- the row can never overlap its neighbours regardless of the template.
    if title then
        title:ClearAllPoints()
        title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 2)
        title:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    end
    if low then
        low:ClearAllPoints()
        low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
        low:SetText(minV)
    end
    if high then
        high:ClearAllPoints()
        high:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
        high:SetText(maxV)
    end
    label = L(label)

    local function UpdateTitle(v)
        if not title then return end
        if stepV < 1 then
            title:SetText(string.format("%s: %.2f", label, v))
        else
            title:SetText(string.format("%s: %d", label, v))
        end
    end

    local cur = get()
    if cur == nil then cur = minV end
    slider.cur = Round(cur)
    slider:SetValue(slider.cur)
    UpdateTitle(slider.cur)

    slider:SetScript("OnValueChanged", function(self, value)
        local v = Round(value)
        if self.cur and math.abs(v - self.cur) < 0.001 then
            return
        end
        self.cur = v
        UpdateTitle(v)
        set(v)
    end)
    AttachTooltip(slider, tooltipKey)
    rows[#rows + 1] = slider
end

-- options = { { value = ..., text = ..., icon = ... }, ... }
local function AddDropdown(label, options, get, set, cond)
    if not Passes(cond) then return end
    local y = AddRow(64)

    local labelFs = ContentFS("OVERLAY", "GameFontNormal")
    labelFs:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y - 3)
    labelFs:SetText(L(label))
    labelFs:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    rows[#rows + 1] = labelFs

    local name = NewName()
    local dd = CreateFrame("Frame", name, content, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y - 22)
    UIDropDownMenu_SetWidth(dd, 260)
    dd.options = options
    dd.get = get
    dd.set = set

    UIDropDownMenu_Initialize(dd, function(self, level)
        local cur = self.get()
        for _, opt in ipairs(self.options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = L(opt.text)
            info.icon = opt.icon
            info.checked = (opt.value == cur)
            info.func = function()
                -- Update the closed label immediately; set() may rebuild the
                -- window, so do it first while the frame still exists
                UIDropDownMenu_SetText(self, L(opt.text))
                self.set(opt.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local curText = tostring(get() or "")
    for _, opt in ipairs(options) do
        if opt.value == get() then
            curText = L(opt.text)
            break
        end
    end
    UIDropDownMenu_SetText(dd, curText)

    AttachTooltip(dd, Slug(label))
    rows[#rows + 1] = dd
end

-- Colour swatch row backed by the built-in ColorPickerFrame (3.3.5a).
local function AddColorRow(label, get, set, cond, onCommit)
    if not Passes(cond) then return end
    cursor = cursor - 4
    local y = AddRow(38)
    local b = CreateFrame("Button", NewName(), content)
    b:SetSize(220, 26)
    b:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y - 3)
    local plate = b:CreateTexture(nil, "BACKGROUND")
    plate:SetAllPoints()
    plate:SetTexture(1, 1, 1, 0.05)
    local sw = b:CreateTexture(nil, "ARTWORK")
    sw:SetSize(20, 20)
    sw:SetPoint("LEFT", b, "LEFT", 6, 0)
    local fs = ContentFS("OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    fs:SetText(L(label))
    fs:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")
    local function paint()
        local r, g, bb = get()
        sw:SetTexture(r, g, bb)
    end
    b:SetScript("OnClick", function()
        if not ColorPickerFrame then return end
        local r, g, bb = get()
        local prev = { r, g, bb }
        ColorPickerFrame:SetColorRGB(r, g, bb)
        ColorPickerFrame.func = function()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            set(nr, ng, nb)
            if onCommit then onCommit() end
            paint()
        end
        ColorPickerFrame.cancelFunc = function()
            set(prev[1], prev[2], prev[3])
            paint()
        end
        -- Rebuild the window once the picker closes so its own chrome picks up
        -- the new accent; live-drag updates are handled by func without a rebuild.
        ColorPickerFrame:SetScript("OnHide", function()
            if DH.NotifyOptions then DH:NotifyOptions() end
        end)
        ColorPickerFrame:Show()
    end)
    paint()
    AttachTooltip(b, Slug(label))
    rows[#rows + 1] = b
    rows[#rows + 1] = fs
end

-- Clipped single-select list (used for the proc-sound and window-font pickers
-- so a long LibSharedMedia list does not become one giant dropdown).
local function AddScrollList(label, items, get, set, cond)
    if not Passes(cond) then return end
    local y = AddRow(172)
    local labelFs = ContentFS("OVERLAY", "GameFontNormal")
    labelFs:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y - 3)
    labelFs:SetText(L(label))
    labelFs:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    rows[#rows + 1] = labelFs

    -- Clipped faux-list. A ScrollFrame's scroll-child buttons stay clickable
    -- even when scrolled out of view (they leak mouse over the widgets below),
    -- so the list is drawn manually: only the rows that fit are shown, the
    -- rest are hidden and therefore never receive mouse input.
    local VIEW_H, ROW_H = 126, 18
    local box = CreateFrame("Frame", nil, content, "BackdropTemplate")
    box:SetSize(300, VIEW_H)
    box:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y - 24)
    box:EnableMouseWheel(true)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local th2 = DH.GetUITheme and DH:GetUITheme() or nil
    if th2 then
        box:SetBackdropColor(th2.backdrop[1], th2.backdrop[2], th2.backdrop[3], 0.55)
        box:SetBackdropBorderColor(th2.border[1], th2.border[2], th2.border[3], 0.85)
    else
        box:SetBackdropColor(0.05, 0.05, 0.05, 0.55)
        box:SetBackdropBorderColor(PAL.info[1], PAL.info[2], PAL.info[3], 0.85)
    end
    rows[#rows + 1] = box

    local count = #items
    local maxOff = math.max(0, count * ROW_H - VIEW_H)
    local offset = 0

    local entry = {}
    local function layout()
        if maxOff <= 0 then offset = 0 end
        if offset < 0 then offset = 0 elseif offset > maxOff then offset = maxOff end
        for i = 1, #entry do
            local e = entry[i]
            local top = (i - 1) * ROW_H - offset
            e.btn:ClearAllPoints()
            e.btn:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -top)
            if top >= 0 and top <= VIEW_H - ROW_H then e.btn:Show() else e.btn:Hide() end
        end
    end
    local function refresh()
        local cur = get()
        for _, e in ipairs(entry) do
            if e.value == cur then
                e.fs:SetTextColor(PAL.header[1], PAL.header[2], PAL.header[3])
                e.btn.sel:Show()
            else
                e.fs:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
                e.btn.sel:Hide()
            end
        end
    end
    for i, opt in ipairs(items) do
        local b = CreateFrame("Button", nil, box)
        b:SetSize(282, 16)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.sel:SetTexture(1, 1, 1, 0.12)
        b.sel:Hide()
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", b, "LEFT", 6, 0)
        fs:SetText(L(opt.text))
        fs:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
        b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")
        b:SetScript("OnClick", function() set(opt.value); refresh() end)
        entry[#entry + 1] = { value = opt.value, fs = fs, btn = b }
    end
    box:SetScript("OnMouseWheel", function(self, delta)
        offset = offset - delta * ROW_H
        layout()
    end)
    refresh()
    layout()
    AttachTooltip(box, Slug(label))
end

-- Returns the button so callers can disable it
local function AddButton(label, onClick, width, enabled, cond, tooltipKey)
    if not Passes(cond) then return end
    cursor = cursor - 4
    local y = AddRow(38)
    local name = NewName()
    local b = CreateFrame("Button", name, content, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y - 3)
    local text = _G[name .. "Text"]
    local w = width or 180
    local maxW = (CONTENT_WIDTH or 430) - 12
    if text then
        if text.SetWordWrap then text:SetWordWrap(false) end
        local lbl = L(label)
        text:SetText(lbl)
        local tw = (text.GetStringWidth and text:GetStringWidth()) or 0
        if tw + 26 > w then w = tw + 26 end
        if w > maxW then
            w = maxW
            -- Label too long even for the full width: trim with an ellipsis.
            if tw > (w - 26) then
                local s = lbl
                while #s > 1 do
                    s = s:sub(1, #s - 1)
                    text:SetText(s .. "\226\128\166")
                    if ((text.GetStringWidth and text:GetStringWidth()) or 0) <= (w - 26) then
                        break
                    end
                end
            end
        end
    end
    b:SetSize(w, 26)
    if enabled == false then
        b:Disable()
    end
    b:SetScript("OnClick", onClick)
    AttachTooltip(b, tooltipKey or Slug(label), label)
    rows[#rows + 1] = b
    return b
end

-- Free-text option row (e.g. the proc sound file path).
local function AddEditBox(label, get, set, cond)
    if not Passes(cond) then return end
    cursor = cursor - 4
    local y = AddRow(34)
    local labelFs = ContentFS("OVERLAY", "GameFontNormal")
    labelFs:SetPoint("TOPLEFT", content, "TOPLEFT", 14, y - 4)
    labelFs:SetText(L(label))
    labelFs:SetTextColor(PAL.text[1], PAL.text[2], PAL.text[3])
    rows[#rows + 1] = labelFs

    local eb = CreateFrame("EditBox", NewName(), content, "InputBoxTemplate")
    eb:SetWidth(220)
    eb:SetPoint("TOPLEFT", content, "TOPLEFT", 190, y)
    eb:SetFontObject("GameFontHighlight")
    eb:SetAutoFocus(false)
    eb:SetText(tostring(get() or ""))
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        set(self:GetText())
    end)
    eb:SetScript("OnEditFocusLost", function(self) set(self:GetText()) end)
    AttachTooltip(eb, Slug(label), label)
    rows[#rows + 1] = eb
    return eb
end

-- ============================================================================
-- BUILD OPTIONS
-- ============================================================================

local function GetModeOptions()
    local opts = { { value = "__auto", text = L("Auto-detect (from talents)") } }
    local modes = ns.registered and ns.registered.modes or {}
    for _, mode in ipairs(modes) do
        opts[#opts + 1] = {
            value = mode.key,
            text = mode.name or mode.key,
            icon = mode.icon,
        }
    end
    return opts
end

-- Human-readable name of the mode currently in effect (shown in General).
local function CurrentModeText()
    local mode = DH.GetActiveMode and DH:GetActiveMode()
    if not mode then
        return L("Current mode:") .. " " .. L("none")
    end
    return L("Current mode:") .. " " .. (mode.name or mode.key)
end

local function BuildGeneral()
    AddNote(L("Core setup: enable the addon, targets, activity, cooldowns and alerts."))

    AddHeader("Base")
    AddCheckbox("Enable rotation highlight", function()
        return DH.db.enabled
    end, function(v)
        DH:SetEnabled(v)
    end)
    AddCheckbox("Auto-detect build from talents", function()
        return DH.db.auto_mode
    end, function(v)
        DH.db.auto_mode = v
        if v then
            DH:AutoDetectMode()
        end
        DH:NotifyOptions()
    end)
    AddDropdown("Build", GetModeOptions(), function()
        if DH.db.auto_mode then
            return "__auto"
        end
        return DH.db.mode
    end, function(v)
        if v == "__auto" then
            DH.db.auto_mode = true
            DH:AutoDetectMode()
            DH:NotifyOptions()
            return true
        end
        local ok = DH:SetMode(v)
        if ok then
            DH:NotifyOptions()
        end
        return ok
    end, function()
        return not (DH.db and DH.db.auto_mode)
    end)
    AddInfo(CurrentModeText())

    AddHeader("Targets")
    AddDropdown("Build detection", STRING_CHOICES.build_detect_mode, function()
        return (DH.GetSetting and DH:GetSetting("build_detect_mode")) or "talents_glyphs_stats"
    end, function(v)
        DH:SetSetting("build_detect_mode", v)
        DH:NotifyOptions()
    end)
    AddCheckbox("Show option tooltips", function()
        return DH.GetSetting and DH:GetSetting("show_tooltips") ~= false
    end, function(v)
        DH:SetSetting("show_tooltips", v)
    end)

    AddHeader("Targets")
    AddDropdown("Target mode", STRING_CHOICES.target_mode, function()
        return (DH.GetSetting and DH:GetSetting("target_mode")) or "single"
    end, function(v)
        DH:SetSetting("target_mode", v)
        DH:NotifyOptions()
    end)
    AddSlider("AOE threshold (enemies)", 2, 10, 1, function()
        return (DH.GetSetting and DH:GetSetting("aoe_threshold")) or 4
    end, function(v)
        DH:SetSetting("aoe_threshold", v)
        DH:NotifyOptions()
    end, function()
        local m = (DH.GetSetting and DH:GetSetting("target_mode")) or "single"
        return m == "auto" or m == "aoe"
    end)
    AddSlider("Cleave threshold (enemies)", 2, 6, 1, function()
        return (DH.GetSetting and DH:GetSetting("cleave_threshold")) or 2
    end, function(v)
        DH:SetSetting("cleave_threshold", v)
        DH:NotifyOptions()
    end, function()
        local m = (DH.GetSetting and DH:GetSetting("target_mode")) or "single"
        return m == "auto" or m == "cleave"
    end)

    AddHeader("Activity")
    AddDropdown("Activity profile", STRING_CHOICES.activity_profile, function()
        if (DH.GetSetting and DH:GetSetting("auto_activity")) ~= false then return "auto" end
        return (DH.GetSetting and DH:GetSetting("activity_profile")) or "raid"
    end, function(v)
        if v == "auto" then
            DH:SetSetting("auto_activity", true)
            if DH.RefreshAutoActivity then DH:RefreshAutoActivity() end
        else
            DH:SetSetting("auto_activity", false)
            DH:SetSetting("activity_profile", v)
        end
        DH:NotifyOptions()
    end)
    AddInfo("Auto switches raid / dungeon / arena / world by your current content and encounters.", function()
        return (DH.GetSetting and DH:GetSetting("auto_activity")) ~= false
    end)

    AddHeader("Cooldowns")
    AddCheckbox("Use cooldowns", function()
        return (DH.GetSetting and DH:GetSetting("auto_cooldowns")) ~= false
    end, function(v)
        DH:SetSetting("auto_cooldowns", v)
        DH:NotifyOptions()
    end)
    AddDropdown("Cooldown order", STRING_CHOICES.cooldown_order, function()
        return (DH.GetSetting and DH:GetSetting("cooldown_order")) or "priority"
    end, function(v)
        DH:SetSetting("cooldown_order", v)
        DH:NotifyOptions()
    end, function()
        return (DH.GetSetting and DH:GetSetting("auto_cooldowns")) ~= false
    end)


    AddHeader("Alerts")
    AddCheckbox("Play a sound when a proc lands", function()
        return DH.GetSetting and DH:GetSetting("sound_procs") == true
    end, function(v)
        DH:SetSetting("sound_procs", v)
    end)
    AddButton("Test sound", function()
        local file = (DH.GetSetting and DH:GetSetting("sound_procs_file")) or "default"
        if ns.ResolveSound then file = ns.ResolveSound(file) or file end
        if file == "default" then file = "Sound\\Interface\\ReadyCheck.wav" end
        if type(PlaySoundFile) == "function" then
            pcall(PlaySoundFile, file)
        elseif type(PlaySound) == "function" then
            PlaySound("igMainMenuOptionCheckBoxOn")
        end
    end, 150)
    AddScrollList("Proc alert sound", ns.ListSounds and ns.ListSounds() or { { value = "default", text = "Default" } }, function()
        return (DH.GetSetting and DH:GetSetting("sound_procs_file")) or "default"
    end, function(v)
        DH:SetSetting("sound_procs_file", v)
    end)
    AddInfo("The sound plays when a proc is detected while the option above is on.")

    AddHeader("Status")
    local st = (DH.GetAddonState and DH:GetAddonState()) or {}
    AddInfo("v" .. tostring(DH.Version or "?") .. " | " .. tostring(st.spec or "?")
        .. " (" .. tostring(st.specRole or "?") .. ") | " .. tostring(st.mode or "?"))
    AddInfo("Profile: " .. tostring(st.profile or "?") .. " | Errors: "
        .. tostring(st.errors or 0))
    cursor = cursor - 4
    AddButton("Open full status", function()
        if DH.OpenOptionsTab then DH:OpenOptionsTab("status") end
    end, 200, nil, function()
        return MenuMode() == "advanced"
    end)

    cursor = cursor - 6
    AddHeader("Quick actions")
    cursor = cursor - 4
    AddButton("Open Setup Wizard", function()
        if ns.Wizard and ns.Wizard.Show then
            ns.Wizard:Show()
        else
            DH:Print(L("Setup Wizard is not loaded."))
        end
    end, 220)
    cursor = cursor - 6
    AddButton("Open coach hub", function()
        if ns.ShowHub then ns.ShowHub() end
    end, 220)
    cursor = cursor - 8

    AddHeader("Interface")
    AddCheckbox("Show minimap button", function()
        return not (DH.db.minimap and DH.db.minimap.hide)
    end, function(v)
        if DH.db.minimap then
            DH.db.minimap.hide = not v
        end
        if DH.RefreshConfig then
            DH:RefreshConfig()
        end
    end)
    AddInfo("Left-click toggles the rotation, right-click opens options.")
    AddDropdown("Menu mode", STRING_CHOICES.menu_mode, function()
        return DH.GetSetting and DH:GetSetting("menu_mode") or "simple"
    end, function(v)
        DH:SetSetting("menu_mode", v)
        DH:NotifyOptions()
    end)
    AddDropdown("Theme", STRING_CHOICES.theme, function()
        return (DH.GetSetting and DH:GetSetting("theme")) or "class"
    end, function(v)
        DH:SetSetting("theme", v)
        DH:NotifyOptions()
    end)
    AddColorRow("Accent color", function()
        local c = (DH.GetSetting and DH:GetSetting("theme_custom_color")) or { 1, 0.82, 0 }
        return c[1] or 1, c[2] or 0.82, c[3] or 0
    end, function(r, g, b)
        DH:SetSetting("theme_custom_color", { r, g, b })
    end, nil, function()
        DH:SetSetting("theme", "custom")
    end)
    AddInfo(L("Editing a colour switches the palette to Custom."))
end

local function BuildSpellQueue()
    AddHeader("Spell queue")

    AddDropdown("Orientation", {
        { value = "horizontal", text = "Row (horizontal)" },
        { value = "vertical", text = "Column (vertical)" },
    }, function()
        return (DH.GetSetting and DH:GetSetting("orientation")) or "horizontal"
    end, function(v)
        DH:SetSetting("orientation", v)
    end)

    AddSlider("Number of icons", 1, 10, 1, function()
        return (DH.db and DH.db.display and DH.db.display.spellframe_icons) or 3
    end, function(v)
        if DH.db and DH.db.display then
            DH.db.display.spellframe_icons = v
        end
        if DH.UpdateUI then DH:UpdateUI() end
    end)

    AddSlider("Icon size", 24, 64, 2, function()
        return (DH.GetSetting and DH:GetSetting("icon_size")) or 36
    end, function(v)
        DH:SetSetting("icon_size", v)
    end)

    AddSlider("Icon gap", 0, 12, 1, function()
        return (DH.GetSetting and DH:GetSetting("icon_gap")) or 4
    end, function(v)
        DH:SetSetting("icon_gap", v)
    end)

    AddCheckbox("Show keybind", function()
        return (DH.GetSetting and DH:GetSetting("show_keybind")) ~= false
    end, function(v)
        DH:SetSetting("show_keybind", v)
    end)

    AddCheckbox("Show GCD timer", function()
        return (DH.GetSetting and DH:GetSetting("show_gcd_timer")) ~= false
    end, function(v)
        DH:SetSetting("show_gcd_timer", v)
    end, function()
        return (DH.GetSetting and DH:GetSetting("num_icons")) ~= 0
    end)

    AddCheckbox("Show remaining time", function()
        return (DH.GetSetting and DH:GetSetting("show_time")) ~= false
    end, function(v)
        DH:SetSetting("show_time", v)
    end)

    AddCheckbox("Show priority numbers", function()
        return (DH.db and DH.db.display and DH.db.display.show_numbers) == true
    end, function(v)
        if DH.db and DH.db.display then
            DH.db.display.show_numbers = v
        end
        if DH.UpdateUI then DH:UpdateUI() end
    end)
end

-- Window appearance and visibility behaviour. Kept separate from the core
-- queue controls so the primary settings lead and the fine-tuning sits lower.
local function BuildDisplayWindow()
    AddHeader("Window")

    AddCheckbox("Show background", function()
        return (DH.GetSetting and DH:GetSetting("show_background")) ~= false
    end, function(v)
        DH:SetSetting("show_background", v)
    end)
    AddCheckbox("Show border", function()
        return (DH.GetSetting and DH:GetSetting("show_border")) ~= false
    end, function(v)
        DH:SetSetting("show_border", v)
    end)
    AddCheckbox("Show title", function()
        return (DH.GetSetting and DH:GetSetting("show_title")) ~= false
    end, function(v)
        DH:SetSetting("show_title", v)
    end)
    AddCheckbox("Paused label", function()
        return (DH.GetSetting and DH:GetSetting("paused_text")) ~= false
    end, function(v)
        DH:SetSetting("paused_text", v)
    end)

    AddCheckbox("Hide out of combat", function()
        return (DH.GetSetting and DH:GetSetting("hide_out_of_combat")) == true
    end, function(v)
        DH:SetSetting("hide_out_of_combat", v)
    end)

    AddCheckbox("Hide with no target", function()
        return (DH.GetSetting and DH:GetSetting("hide_no_target")) == true
    end, function(v)
        DH:SetSetting("hide_no_target", v)
    end)

    AddCheckbox("Hide when idle", function()
        return (DH.GetSetting and DH:GetSetting("hide_when_idle")) == true
    end, function(v)
        DH:SetSetting("hide_when_idle", v)
    end)

    AddCheckbox("Fade when idle", function()
        return (DH.GetSetting and DH:GetSetting("fade_when_idle")) == true
    end, function(v)
        DH:SetSetting("fade_when_idle", v)
    end)

    AddCheckbox("Drag windows by default (no /rc move)", function()
        return (DH.GetSetting and DH:GetSetting("frames_movable_default")) ~= false
    end, function(v)
        DH:SetSetting("frames_movable_default", v)
    end)
    AddCheckbox("Lock windows", function()
        return (DH.GetSetting and DH:GetSetting("frames_locked")) == true
    end, function(v)
        DH:SetSetting("frames_locked", v)
        if DH.UpdateUI then DH:UpdateUI() end
    end)
    AddInfo("Hold the left button over any empty part of a window to drag it; click an icon to cast.")
end

-- Prompt 3.1: colour palettes (improvement 1).
local function BuildColors()
    AddHeader("Colors")
    AddDropdown("Color palette", STRING_CHOICES.color_palette, function()
        return (DH.GetSetting and DH:GetSetting("color_palette")) or "default"
    end, function(v)
        DH:SetSetting("color_palette", v)
        DH:UpdateUI()
        DH:NotifyOptions()
    end)
    AddInfo("Colour set used for the priority highlights and the legend.")
    AddInfo("Includes colour-blind friendly palettes.")
end

-- Prompt 3.2: transitions (improvement 2).
local function BuildAnimations()
    AddHeader("Animations")
    AddCheckbox("Enable animations", function()
        return (DH.GetSetting and DH:GetSetting("animations_enabled")) ~= false
    end, function(v)
        DH:SetSetting("animations_enabled", v)
        DH:UpdateUI()
    end)
    AddInfo("Icons fade in (0.2s), crossfade on change (0.15s), fade out (0.15s).")
    AddInfo("Skipped automatically under load or when icons change very fast.")
end

-- Prompt 3.4: display layout presets (improvement 4).
local function BuildLayout()
    AddHeader("Layout")
    AddDropdown("Display layout", STRING_CHOICES.display_layout, function()
        return (DH.GetSetting and DH:GetSetting("display_layout")) or "center"
    end, function(v)
        if v ~= "custom" and ns.ApplyLayout then
            ns.ApplyLayout(v)
        else
            DH:SetSetting("display_layout", v)
        end
        DH:NotifyOptions()
    end)
    AddInfo("A preset arranges the primary, cooldowns and interrupt displays.")
    AddInfo("Minimal shows only the primary window; Custom keeps your own positions.")
    AddButton("Apply layout preset", function()
        local name = (DH.GetSetting and DH:GetSetting("display_layout")) or "center"
        if name == "custom" then name = "center" end
        if ns.ApplyLayout then ns.ApplyLayout(name) end
        DH:Print(L("Layout applied: ") .. name)
        DH:NotifyOptions()
    end, 220)
    AddButton("Export layout", function()
        if ns.ShowLayoutExportWindow then ns.ShowLayoutExportWindow() end
    end, 150)
    AddButton("Import layout", function()
        if ns.ShowLayoutImportWindow then ns.ShowLayoutImportWindow() end
    end, 150)
    AddButton("Configure panels", function()
        if ns.SetConfigMode then ns.SetConfigMode(true) end
    end, 220)
    AddInfo("Opens the panel settings (size, scale, opacity, colour) over the game.")
end


local function BuildIconWindow()
    AddHeader("Icon window options")
    AddCheckbox("Show icon window", function()
        return DH.db.display.show_spellframe ~= false
    end, function(v)
        DH.db.display.show_spellframe = v
        DH:UpdateUI()
    end)
    AddCheckbox("Compact (icons only, no frame)", function()
        return (DH.GetSetting and DH:GetSetting("spellframe_compact")) == true
    end, function(v)
        DH:SetSetting("spellframe_compact", v)
        DH:UpdateUI()
    end)

    AddSlider("Icon window icons", 1, 10, 1, function()
        return DH.db.display.spellframe_icons or 3
    end, function(v)
        DH.db.display.spellframe_icons = v
        DH:UpdateUI()
    end)

    AddCheckbox("Hide icon window out of combat", function()
        return (DH.GetSetting and DH:GetSetting("spellframe_combat_only")) == true
    end, function(v)
        DH:SetSetting("spellframe_combat_only", v)
        DH:UpdateUI()
    end)

    AddSlider("Icon window scale", 0.5, 2.5, 0.1, function()
        return DH.db.display.spellframe_scale or 1
    end, function(v)
        DH.db.display.spellframe_scale = v
        DH:UpdateUI()
    end)

    AddDropdown("Font", ns.ListFonts and ns.ListFonts() or { { value = "default", text = "Default" } }, function()
        return (DH.GetSetting and DH:GetSetting("spellframe_font")) or "default"
    end, function(v)
        DH:SetSetting("spellframe_font", v)
        DH:UpdateUI()
    end)
    AddSlider("Font size", 8, 24, 1, function()
        local s = DH.GetSetting and DH:GetSetting("spellframe_font_size")
        if not s or s < 8 then return 12 end
        return s
    end, function(v)
        DH:SetSetting("spellframe_font_size", v)
        DH:UpdateUI()
    end)
    AddInfo("Fonts come from LibSharedMedia when it is installed.")

    AddButton("Reset icon window position", function()
        if DH.db.spellFrame then
            DH.db.spellFrame.x = 0
            DH.db.spellFrame.y = -250
        end
        if ns.RefreshSpellFrame then
            ns.RefreshSpellFrame()
        end
        DH:Print(L("Icon window position reset."))
    end, 220)

    AddInfo("Drag the window to move it - the position is saved per profile.")


    AddHeader("Icon window text")
    AddCheckbox("Show idle reason when nothing to do", function()
        return (DH.GetSetting and DH:GetSetting("show_idle_reason")) ~= false
    end, function(v)
        DH:SetSetting("show_idle_reason", v)
        DH:UpdateUI()
    end)

    AddCheckbox("Show target-mode indicator (S/A/Au)", function()
        return (DH.GetSetting and DH:GetSetting("show_mode_indicator")) ~= false
    end, function(v)
        DH:SetSetting("show_mode_indicator", v)
        DH:UpdateUI()
    end)

    AddCheckbox("Show priority color legend", function()
        return (DH.GetSetting and DH:GetSetting("show_color_legend")) ~= false
    end, function(v)
        DH:SetSetting("show_color_legend", v)
        DH:NotifyOptions()
    end)

    if (DH.GetSetting and DH:GetSetting("show_color_legend")) ~= false then
        AddColorInfo("1 - press now", 0.15, 1.0, 0.15)
        AddColorInfo("2 - next", 1.0, 0.85, 0.10)
        AddColorInfo("3 - after that", 0.25, 0.60, 1.0)
    end
end

local function BuildAdvanced()
    AddNote(L("Action-bar scanner, extras and animation timers."))
    AddHeader("Extras")
    AddCheckbox("Enemy counter", function()
        return (DH.GetSetting and DH:GetSetting("enemy_count_enabled")) ~= false
    end, function(v)
        DH:SetSetting("enemy_count_enabled", v)
    end)
    AddCheckbox("Resource-cap warnings", function()
        return (DH.GetSetting and DH:GetSetting("resource_warning_enabled")) ~= false
    end, function(v)
        DH:SetSetting("resource_warning_enabled", v)
    end)
    AddCheckbox("Use racial cooldowns", function()
        return (DH.GetSetting and DH:GetSetting("use_racial_cooldowns")) ~= false
    end, function(v)
        DH:SetSetting("use_racial_cooldowns", v)
        DH:UpdateUI()
    end)
    AddCheckbox("Timeline bars", function()
        return (DH.GetSetting and DH:GetSetting("timeline_bars_enabled")) ~= false
    end, function(v)
        DH:SetSetting("timeline_bars_enabled", v)
    end)
    AddCheckbox("DoT / debuff panel", function()
        return (DH.GetSetting and DH:GetSetting("dot_panel_enabled")) == true
    end, function(v)
        DH:SetSetting("dot_panel_enabled", v)
    end)
    AddCheckbox("Swing timer", function()
        return (DH.GetSetting and DH:GetSetting("swing_timer_enabled")) == true
    end, function(v)
        DH:SetSetting("swing_timer_enabled", v)
    end)
    AddInfo("DoT panel and swing timer can be moved by dragging them.")

    AddHeader("Timers and animations")
    AddSlider("Tooltip delay", 0, 1, 0.1, function()
        return (DH.GetSetting and DH:GetSetting("tooltip_delay")) or 0.3
    end, function(v)
        DH:SetSetting("tooltip_delay", v)
    end, function()
        return (DH.GetSetting and DH:GetSetting("show_tooltips")) ~= false
    end)
    AddSlider("Animation speed", 0.5, 2.0, 0.1, function()
        return (DH.GetSetting and DH:GetSetting("animation_speed")) or 1.0
    end, function(v)
        DH:SetSetting("animation_speed", v)
    end)
    AddInfo("These fine-tuning sliders were moved here to keep General/Display simple.")

    AddHeader("Action bar scanner")
    AddButton("Test glow on action bars", function()
        if ns.ShowTestGlow then
            ns.ShowTestGlow()
        end
    end, 220)
end

local function BuildCoaching()
    AddNote(L("Custom priority lists, DPS forecast and the class pulse."))
    AddHeader("Priorities (APL)")
    AddCheckbox("Use custom APL", function()
        return DH.GetSetting and DH:GetSetting("custom_apl_enabled") == true
    end, function(v)
        DH:SetSetting("custom_apl_enabled", v)
        DH:UpdateUI()
        DH:NotifyOptions()
    end)
    AddInfo("A plain-text priority list replaces the class rotation.")
    AddButton("Import APL", function()
        if ns.ShowAPLImportWindow then ns.ShowAPLImportWindow() end
    end, 150, nil, function()
        return DH.GetSetting and DH:GetSetting("custom_apl_enabled") == true
    end)
    AddButton("Export APL", function()
        if ns.ShowAPLExportWindow then ns.ShowAPLExportWindow() end
    end, 150, nil, function()
        return DH.GetSetting and DH:GetSetting("custom_apl_enabled") == true
    end)
    AddButton("Share APL", function()
        if DH.Print and ns.ExportAPLShare then DH:Print(ns.ExportAPLShare(DH)) end
    end, 150, nil, function()
        return DH.GetSetting and DH:GetSetting("custom_apl_enabled") == true
    end)


    AddHeader("Coaching")
    AddCheckbox("DPS forecast", function()
        return DH.GetSetting and DH:GetSetting("dps_forecast_enabled") == true
    end, function(v)
        DH:SetSetting("dps_forecast_enabled", v)
        DH:UpdateUI()
    end)
    AddCheckbox("Show actual DPS and loss", function()
        return (DH.GetSetting and DH:GetSetting("dps_forecast_show_actual")) ~= false
    end, function(v)
        DH:SetSetting("dps_forecast_show_actual", v)
        DH:UpdateUI()
    end, function()
        return DH.GetSetting and DH:GetSetting("dps_forecast_enabled") == true
    end)
    AddDropdown("DPS forecast position", STRING_CHOICES.aux_position, function()
        return (DH.GetSetting and DH:GetSetting("dps_forecast_position")) or "above_spellframe"
    end, function(v)
        DH:SetSetting("dps_forecast_position", v)
        DH:UpdateUI()
    end, function()
        return DH.GetSetting and DH:GetSetting("dps_forecast_enabled") == true
    end)
    AddDropdown("DPS forecast color", ns.ColorChoices(), function()
        return (DH.GetSetting and DH:GetSetting("dps_color")) or "auto"
    end, function(v)
        DH:SetSetting("dps_color", v)
        DH:UpdateUI()
    end, function()
        return DH.GetSetting and DH:GetSetting("dps_forecast_enabled") == true
    end)
    AddCheckbox("Class pulse", function()
        return (DH.GetSetting and DH:GetSetting("class_pulse_enabled")) ~= false
    end, function(v)
        DH:SetSetting("class_pulse_enabled", v)
        DH:UpdateUI()
    end)
    AddDropdown("Class pulse position", STRING_CHOICES.aux_position, function()
        return (DH.GetSetting and DH:GetSetting("class_pulse_position")) or "left_of_spellframe"
    end, function(v)
        DH:SetSetting("class_pulse_position", v)
        DH:UpdateUI()
    end, function()
        return (DH.GetSetting and DH:GetSetting("class_pulse_enabled")) ~= false
    end)
    AddDropdown("Class pulse color", ns.ColorChoices(), function()
        return (DH.GetSetting and DH:GetSetting("pulse_color")) or "auto"
    end, function(v)
        DH:SetSetting("pulse_color", v)
        DH:UpdateUI()
    end, function()
        return (DH.GetSetting and DH:GetSetting("class_pulse_enabled")) ~= false
    end)
end

local function BuildTraining()
    AddNote(L("Practice modes and learning feedback."))
    AddHeader("Training")
    AddCheckbox("Training mode", function()
        return (DH.GetSetting and DH:GetSetting("training_mode") == true)
    end, function(v)
        DH:SetSetting("training_mode", v)
        DH:UpdateRecommendations()
    end)
    AddCheckbox("Training: print the reason in chat", function()
        return (DH.GetSetting and DH:GetSetting("training_chat_output")) ~= false
    end, function(v)
        DH:SetSetting("training_chat_output", v)
    end, function()
        return (DH.GetSetting and DH:GetSetting("training_mode")) == true
    end)
    AddCheckbox("Training: play a sound on change", function()
        return (DH.GetSetting and DH:GetSetting("training_sound")) == true
    end, function(v)
        DH:SetSetting("training_sound", v)
    end, function()
        return (DH.GetSetting and DH:GetSetting("training_mode")) == true
    end)
    AddNote("Training keeps recommending on a live target out of combat (e.g. a dummy). Toggle with /rc train or ALT-SHIFT-L.")

    AddHeader("Exam and mentor")
    AddCheckbox("Exam mode (ALT-SHIFT-E)", function()
        return DH.GetSetting and DH:GetSetting("exam_mode") == true
    end, function(v)
        DH:SetSetting("exam_mode", v)
        if ns.ResetAnalytics then ns.ResetAnalytics() end
        DH:UpdateUI()
        DH:NotifyOptions()
    end)
    AddCheckbox("Mentor mode (ALT-SHIFT-M)", function()
        return DH.GetSetting and DH:GetSetting("mentor_mode") == true
    end, function(v)
        DH:SetSetting("mentor_mode", v)
        DH:UpdateUI()
        DH:NotifyOptions()
    end)
    AddSlider("Mentor error threshold", 1, 10, 1, function()
        return (DH.GetSetting and DH:GetSetting("mentor_error_threshold")) or 3
    end, function(v)
        DH:SetSetting("mentor_error_threshold", v)
    end, function()
        return DH.GetSetting and DH:GetSetting("mentor_mode") == true
    end)

    AddHeader("Learning")
    AddCheckbox("Learning stats", function()
        return (DH.GetSetting and DH:GetSetting("learning_stats_enabled")) ~= false
    end, function(v)
        DH:SetSetting("learning_stats_enabled", v)
    end)
    AddInfo("/rc learning - summary; graph, export, clear.")
end

local function BuildTimeline()
    AddNote(L("Boss timeline window and DBM/BigWigs phases and timers."))
    AddHeader("Boss timeline")
    AddCheckbox("Enable boss timeline", function()
        return DH.GetSetting and DH:GetSetting("timeline_enabled") == true
    end, function(v)
        DH:SetSetting("timeline_enabled", v)
        DH:UpdateUI()
    end)
    AddInfo("Reads timers from DBM / BigWigs; works from the combat log alone.")
    AddCheckbox("Show boss timeline window", function()
        return DH.GetSetting and DH:GetSetting("show_timeline_display") == true
    end, function(v)
        DH:SetSetting("show_timeline_display", v)
        DH:UpdateUI()
    end)
    AddCheckbox("Show burst countdown", function()
        return (DH.GetSetting and DH:GetSetting("timeline_show_burst")) ~= false
    end, function(v)
        DH:SetSetting("timeline_show_burst", v)
        DH:UpdateUI()
    end)
    AddCheckbox("Auto-switch rotation by boss phase", function()
        return DH.GetSetting and DH:GetSetting("timeline_auto_phase") == true
    end, function(v)
        DH:SetSetting("timeline_auto_phase", v)
        DH:UpdateUI()
        DH:NotifyOptions()
    end)
    AddInfo("Phase 2 switches to AOE, phase 3 to single-target execute.")
    AddSlider("Burst warning window (s)", 5, 30, 1, function()
        return (DH.GetSetting and DH:GetSetting("timeline_burst_window")) or 15
    end, function(v)
        DH:SetSetting("timeline_burst_window", v)
    end)
    AddSlider("Timeline window size", 0.5, 2.5, 0.1, function()
        return (DH.GetSetting and DH:GetSetting("timeline_scale")) or 1
    end, function(v)
        DH:SetSetting("timeline_scale", v)
        DH:UpdateUI()
    end)

    AddHeader("Timeline (deep)")
    AddCheckbox("Deep BigWigs/DBM integration", function()
        return DH.GetSetting and DH:GetSetting("timeline_deep_enabled") == true
    end, function(v)
        DH:SetSetting("timeline_deep_enabled", v)
        if DH.NotifyOptions then DH:NotifyOptions() end
    end)
    AddInfo("Feeds DBM / BigWigs phase messages into the timeline and the window.")
    AddCheckbox("Auto-switch rotation by deep phase", function()
        return DH.GetSetting and DH:GetSetting("timeline_phase_auto") == true
    end, function(v)
        DH:SetSetting("timeline_phase_auto", v)
    end)
    AddCheckbox("Announce phase changes in chat", function()
        return (DH.GetSetting and DH:GetSetting("timeline_phase_announce")) ~= false
    end, function(v)
        DH:SetSetting("timeline_phase_announce", v)
    end)
end

local function BuildSystem()
    AddNote(L("Arena helpers and interface style."))
    AddHeader("Arena")
    AddDropdown("Arena mode", STRING_CHOICES.arena_mode, function()
        return (DH.GetSetting and DH:GetSetting("arena_mode")) or "auto"
    end, function(v)
        DH:SetSetting("arena_mode", v)
    end)
    AddInfo("Auto detects 2v2 / 3v3 / 5v5 from the arena zone.", function()
        return ((DH.GetSetting and DH:GetSetting("arena_mode")) or "auto") == "auto"
    end)


    AddHeader("Interface style")
    AddInfo("RotationCore adapts to ElvUI / Bartender4 / Dominos automatically.")
    AddScrollList("Window font", ns.ListFonts and ns.ListFonts() or { { value = "default", text = "Default" } }, function()
        return (DH.GetSetting and DH.GetSetting("ui_font")) or "default"
    end, function(v)
        DH:SetSetting("ui_font", v)
        if DH.UpdateUI then DH:UpdateUI() end
        if DH.NotifyOptions then DH:NotifyOptions() end
    end)
    AddDropdown("Background style", {
        { value = "default", text = "Default" },

        { value = "matte", text = "Matte" },
    }, function()
        return (DH.GetSetting and DH:GetSetting("bg_style")) or "default"
    end, function(v)
        DH:SetSetting("bg_style", v)
        if DH.ApplyShellStyle then DH:ApplyShellStyle() end
        DH:NotifyOptions()
    end)
    AddCheckbox("Large / readable text", function()
        return (DH.GetSetting and DH:GetSetting("ui_font_large")) == true
    end, function(v)
        DH:SetSetting("ui_font_large", v)
        if DH.UpdateUI then DH:UpdateUI() end
        if DH.NotifyOptions then DH:NotifyOptions() end
    end)
    AddDropdown("UI skin", STRING_CHOICES.ui_skin, function()
        return (DH.GetSetting and DH:GetSetting("ui_skin")) or "default"
    end, function(v)
        DH:SetSetting("ui_skin", v)
        if DH.ApplyShellStyle then DH:ApplyShellStyle() end
        if DH.NotifyOptions then DH:NotifyOptions() end
        -- Some frames cache their backdrop at creation; offer a reload so the
        -- new skin is applied everywhere.
        if StaticPopup_Show then
            StaticPopup_Show("ROTATIONCORE_RELOAD_UI_SKIN")
        end
    end)
    AddSlider("Options window opacity", 0.2, 1, 0.01, function()
        return tonumber(DH.GetSetting and DH:GetSetting("ui_opacity")) or 1
    end, function(v)
        DH:SetSetting("ui_opacity", v)
        if frame and frame.SetAlpha then frame:SetAlpha(1) end
        if ns.ApplyOptionsTheme then ns.ApplyOptionsTheme() end
    end)


end

local bossSelId = nil

-- Prompt 2: Boss Profiles section (list / capture / apply / presets).
local function BuildBossProfiles()
    AddHeader("Boss Profiles")
    AddCheckbox("Enable boss profiles", function()
        return DH.GetSetting and DH:GetSetting("boss_profiles_enabled") == true
    end, function(v)
        DH:SetSetting("boss_profiles_enabled", v)
        DH:NotifyOptions()
    end)
    AddInfo("A saved profile is applied automatically for that boss, then your own settings come back.")
    AddInfo("Presets are detected from the boss you are fighting and applied automatically.")

    local enc = DH.State and DH.State.encounter_id
    AddInfo(L("Current boss: ") .. (DH.State.encounter_name and tostring(DH.State.encounter_name) or L("none")))

    -- Known bosses seen this session (populated by ENCOUNTER_START).
    local known = ns.knownBosses or {}
    local knownNames = {}
    for id, nm in pairs(known) do
        knownNames[#knownNames + 1] = tostring(nm)
    end
    if #knownNames > 0 then
        table.sort(knownNames)
        AddInfo(L("Seen this session: ") .. table.concat(knownNames, ", "))
    end

    local profiles = DH.GetBossProfiles and DH:GetBossProfiles() or {}
    local ids = {}
    for id in pairs(profiles) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids == 0 then
        AddInfo(L("No boss profiles yet."))
    else
        if not (bossSelId and profiles[bossSelId]) then bossSelId = ids[1] end
        local opts = {}
        for _, id in ipairs(ids) do
            local nm = profiles[id].name or ""
            opts[#opts + 1] = {
                value = id,
                text = (nm ~= "" and nm or tostring(id)),
            }
        end
        AddDropdown("Boss profile", opts, function()
            return bossSelId
        end, function(v)
            bossSelId = v
        end, function()
            return DH.GetSetting and DH:GetSetting("boss_profiles_enabled") == true
        end)
        AddButton("Apply now", function()
            if bossSelId then DH:ApplyBossProfile(bossSelId) end
        end, 130, nil, function()
            return DH.GetSetting and DH:GetSetting("boss_profiles_enabled") == true
        end)
        AddButton("Save current settings", function()
            if not bossSelId then return end
            local data = {}
            for _, k in ipairs(ns.bossOverrideKeys) do
                local v = DH:GetSetting(k)
                if v ~= nil then data[k] = v end
            end
            data.name = profiles[bossSelId] and profiles[bossSelId].name
                or ("Boss " .. tostring(bossSelId))
            DH:SetBossProfile(bossSelId, data)
            DH:Print(L("Boss profile saved: ") .. tostring(bossSelId))
            DH:NotifyOptions()
        end, 200)
        AddButton("Delete", function()
            if bossSelId then
                DH:DeleteBossProfile(bossSelId)
                bossSelId = nil
                DH:NotifyOptions()
            end
        end, 100)
    end
    AddButton("Capture current encounter", function()
        local id = DH.State and DH.State.encounter_id
        if not id then
            DH:Print(L("No boss profile for this encounter."))
            return
        end
        local data = {}
        for _, k in ipairs(ns.bossOverrideKeys) do
            local v = DH:GetSetting(k)
            if v ~= nil then data[k] = v end
        end
        data.name = (DH.State and DH.State.encounter_name) or tostring(id)
        DH:SetBossProfile(id, data)
        DH:Print(L("Boss profile saved: ") .. tostring(id))
        DH:NotifyOptions()
    end, 300)

    if ns.ShowBossProfileExportWindow then
        AddButton("Export boss profiles", function()
            ns.ShowBossProfileExportWindow()
        end, 200)
    end
    if ns.ShowBossImportWindow then
        AddButton("Import boss profiles", function()
            ns.ShowBossImportWindow()
        end, 200)
    end

    AddCheckbox("Auto-load class profile on ENCOUNTER_START", function()
        return (DH.GetSetting and DH:GetSetting("boss_profile_autoload")) ~= false
    end, function(v)
        DH:SetSetting("boss_profile_autoload", v)
    end, function()
        return DH.GetSetting and DH:GetSetting("boss_profiles_enabled") == true
    end)
    local bcls, bspec = DH.CurrentClassSpec and DH:CurrentClassSpec() or "?", "?"
    AddInfo("Current: " .. tostring(bcls) .. " / " .. tostring(bspec))
    local root = DH.db and DH.db.common and DH.db.common.bossClassProfiles
    local shown = 0
    if root then
        for bid, cmap in pairs(root) do
            if type(cmap) == "table" then
                for ck, smap in pairs(cmap) do
                    if type(smap) == "table" then
                        for sk in pairs(smap) do
                            if shown < 15 then
                                AddNote(tostring(bid) .. " - " .. tostring(ck) .. " / " .. tostring(sk))
                                shown = shown + 1
                            end
                        end
                    end
                end
            end
        end
    end
    if shown == 0 then
        AddInfo("No boss class profiles yet.")
    end
    AddButton("Save current settings here", function()
        local id = DH.State and DH.State.encounter_id
        if not id then
            DH:Print(L("No boss profile for this encounter."))
            return
        end
        local data = {}
        for _, k in ipairs(ns.bossOverrideKeys or {}) do
            local v = DH:GetSetting(k)
            if v ~= nil then data[k] = v end
        end
        local c, sp = DH:CurrentClassSpec()
        DH:SetBossClassProfile(id, c, sp, data)
        DH:Print(L("Boss class profile saved: ") .. tostring(id) .. " (" .. c .. "/" .. sp .. ")")
        DH:NotifyOptions()
    end, 210)
    AddButton("Apply stored for this boss", function()
        local id = DH.State and DH.State.encounter_id
        if not id then
            DH:Print(L("No boss profile for this encounter."))
            return
        end
        if DH:ApplyEncounterBossClassProfile(id) then
            DH:Print(L("Boss class profile applied."))
        else
            DH:Print(L("No stored class profile for this boss."))
        end
    end, 210)
end

local function BuildProfiles()
    AddNote(L("Switch or create profiles, import/export and boss presets."))
    AddInfo(L("Current profile: ") .. DH:GetCurrentProfileName())

    local names = DH:GetProfileNames()
    local opts = {}
    for _, name in ipairs(names) do
        opts[#opts + 1] = { value = name, text = name }
    end
    AddDropdown("Switch profile", opts, function()
        return DH:GetCurrentProfileName()
    end, function(v)
        return DH:SetProfile(v)
    end)

    -- Create a new profile (copy of the current one)
    local y = AddRow(32)
    local labelFs = ContentFS("OVERLAY", "GameFontNormal")
    labelFs:SetPoint("TOPLEFT", content, "TOPLEFT", 14, y - 4)
    labelFs:SetText(L("New profile:"))
    rows[#rows + 1] = labelFs

    local eb = CreateFrame("EditBox", NewName(), content, "InputBoxTemplate")
    eb:SetWidth(180)
    eb:SetPoint("TOPLEFT", content, "TOPLEFT", 110, y)
    eb:SetFontObject("GameFontHighlight")
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    rows[#rows + 1] = eb

    local bName = NewName()
    local createBtn = CreateFrame("Button", bName, content, "UIPanelButtonTemplate")
    createBtn:SetSize(90, 22)
    createBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 300, y - 1)
    local bText = _G[bName .. "Text"]
    if bText then
        bText:SetText(L("Create"))
    end
    createBtn:SetScript("OnClick", function()
        local name = Trim(eb:GetText())
        if name == "" then
            DH:Print(L("Enter a profile name."))
            return
        end
        local created, err = DH:CreateProfile(name, DH:GetCurrentProfileName())
        if created then
            eb:SetText("")
            eb:ClearFocus()
            DH:SetProfile(created)
        else
            DH:Print(err or L("Could not create profile."))
        end
    end)
    rows[#rows + 1] = createBtn

    AddInfo("Copies all settings of the current profile.")

    AddButton("Reset current profile to defaults", function()
        if DH:ResetProfile() then
            DH:Print(L("Profile reset to defaults."))
        end
    end, 240)

    AddButton("Delete current profile", function()
        if StaticPopup_Show then
            StaticPopup_Show("ROTATIONCORE_DELETE_PROFILE", DH:GetCurrentProfileName())
        end
    end, 240, #names > 1)

    AddInfo("Each character remembers the last profile it used.")
    AddInfo("Switch every character to one profile to share settings.")

    AddHeader("Profile options")
    local adv = function()
        return DH.GetSetting and DH:GetSetting("profile_advanced_ui") == true
    end
    AddCheckbox("Show advanced profile options", adv, function(v)
        DH:SetSetting("profile_advanced_ui", v)
        DH:NotifyOptions()
    end)
    AddInfo("Deep customization: import/export, per-spec and boss profiles.")

    if adv() then

    -- Phase 3.2: import / export. The old inline multiline EditBoxes broke
    -- the row layout, so both now open a dedicated popup window instead.
    if not (DH.GetSetting and DH:GetSetting("profile_export_enabled") == false) then
        AddHeader("Import / Export")
        AddInfo("Export and import open a separate window with a text box.")
        AddButton("Export current profile", function()
            if ns.ShowProfileExportWindow then ns.ShowProfileExportWindow() end
        end, 240)
        AddButton("Import from text", function()
            if ns.ShowProfileImportWindow then ns.ShowProfileImportWindow() end
        end, 240)
    end

    -- Phase 3.3: per-specialization settings
    AddHeader("Per-specialization settings")
    AddCheckbox("Per-specialization settings", function()
        return DH.IsSpecProfilesEnabled and DH:IsSpecProfilesEnabled()
    end, function(v)
        DH:SetSetting("spec_profiles_enabled", v)
        if v then
            DH:SaveSpecProfile()
        end
        DH:LoadSpecProfile()
        DH:NotifyOptions()
    end)
    AddInfo("When on, option changes apply only to the active spec.")
    AddButton("Save settings for this spec", function()
        local ok, err = DH:SaveSpecProfile()
        if ok then
            DH:Print(L("Saved settings for this spec."))
        else
            DH:Print(err or L("Could not save spec settings."))
        end
    end, 220, nil, function()
        return DH.IsSpecProfilesEnabled and DH:IsSpecProfilesEnabled()
    end)
    AddButton("Clear this spec's settings", function()
        DH:ClearSpecProfile()
        DH:LoadSpecProfile()
        DH:Print(L("Cleared this spec's settings."))
        DH:NotifyOptions()
    end, 220, nil, function()
        return DH.IsSpecProfilesEnabled and DH:IsSpecProfilesEnabled()
    end)
    AddInfo("Active spec: " .. tostring(DH.GetActiveSpec and DH:GetActiveSpec() or "unknown"), function()
        return DH.IsSpecProfilesEnabled and DH:IsSpecProfilesEnabled()
    end)

    -- Prompt 2: boss profiles below the per-spec section
    BuildBossProfiles()
    end
end


-- Friendly wording for the Class tab. Ability switches ("use_icy_veins") are
-- resolved to the real (localized) spell name from the class module, so on a
-- Russian client you see the Russian spell name, not the internal key.
local KEY_LABEL = {
    auto_cooldowns  = "Use cooldowns automatically",
    target_mode     = "Targets",
    activity_profile = "Activity",
    hold_cd_at_end  = "Hold cooldowns at the end of the fight",
    enabled         = "Turn this build on",
    role            = "Role",
}

-- Short, plain-language explanations shown under the matching control.

local function Humanize(key)
    local s = tostring(key):gsub("^use_", "")
    s = s:gsub("_", " ")
    s = s:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
    return s
end

-- Localized, player-friendly name for a switch: prefer the real spell name
-- from the class module (GetSpellInfo returns the client language).
local function FriendlyName(key)
    if KEY_LABEL[key] then return KEY_LABEL[key] end

    local abilityKey = key:match("^use_(.+)$")
    local ability = abilityKey and DH.Class and DH.Class.abilities and DH.Class.abilities[abilityKey]
    if ability then
        if ability.id then
            local spellName = GetSpellInfo(ability.id)
            if spellName and spellName ~= "" then return spellName end
        end
        if ability.name and ability.name ~= "" then return ability.name end
    end
    return Humanize(key)
end

-- Friendly display name for a registered rotation mode ("frost_mage" -> "Frost")
local function ModeName(key)
    local modes = ns.registered and ns.registered.modes or {}
    for _, mode in ipairs(modes) do
        if mode.key == key then
            return ((mode.name or key):gsub("%s*%b()$", ""))
        end
    end
    return Humanize(key)
end

-- One friendly control for a known setting (boolean switch or dropdown).
local function RenderFriendly(key, path, def)
    local choices = STRING_CHOICES[key]
    if type(def) == "boolean" then
        AddCheckbox(FriendlyName(key), function()
            local cur = GetPath(path)
            if cur == nil then return def end
            return cur
        end, function(val)
            SetPath(path, val)
            DH:NotifyOptions()
        end)
        return true
    elseif type(def) == "string" and choices then
        AddDropdown(FriendlyName(key), choices, function()
            local cur = GetPath(path)
            if cur == nil then return def end
            return cur
        end, function(val)
            SetPath(path, val)
            DH:NotifyOptions()
        end)
        return true
    end
    return false
end

-- One spec section: every ability switch, sorted, with friendly names.
local function RenderSpec(path, spec)
    local keys = {}
    for k, v in pairs(spec) do
        if type(k) == "string" and type(v) == "boolean" then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)

    if #keys == 0 then
        AddInfo("Nothing to configure here.")
        return
    end

    for _, k in ipairs(keys) do
        RenderFriendly(k, path .. "." .. k, spec[k])
    end
end

local function BuildClass()
    AddNote(L("Per-spec ability switches for your class rotation."))
    AddHeader("Class settings")
    AddInfo("Turn individual abilities of the rotation on or off.")
    AddInfo("Changes are saved to the current profile automatically.")

    local defaults = ns.registered and ns.registered.defaults or {}
    local specKeys = {}
    local common
    for k, v in pairs(defaults) do
        if type(k) == "string" and type(v) == "table" and not CORE_KEYS[k] then
            if k == "common" then
                common = v
            else
                specKeys[#specKeys + 1] = k
            end
        end
    end

    if #specKeys == 0 and not common then
        AddInfo("No class module loaded for your character.")
        AddInfo("Install and enable RotationCore_<Class> in the addon list.")
        return
    end

    -- One section per specialization
    table.sort(specKeys)
    for _, k in ipairs(specKeys) do
        local title = ModeName(k)
        if DH.db and DH.db.mode == k then
            title = title .. " (" .. L("active") .. ")"
        end
        AddHeader(title)
        RenderSpec(k, defaults[k])
    end

    -- Adaptive rotation (item-level driven). Lives on the Class tab; the
    -- thresholds only apply when the mode is not a fixed "simple".
    AddHeader("Rotation complexity")
    AddDropdown("Rotation complexity", STRING_CHOICES.adaptive_rotation, function()
        return (DH.GetSetting and DH:GetSetting("adaptive_rotation")) or "auto"
    end, function(v)
        DH:SetSetting("adaptive_rotation", v)
        DH:UpdateUI()
        DH:NotifyOptions()
    end)
    AddSlider("Simple below ilvl", 100, 300, 5, function()
        return (DH.GetSetting and DH:GetSetting("ilvl_threshold_simple")) or 200
    end, function(v)
        DH:SetSetting("ilvl_threshold_simple", v)
    end, function()
        local m = (DH.GetSetting and DH:GetSetting("adaptive_rotation")) or "auto"
        return m ~= "simple"
    end)
    AddSlider("Complex at/above ilvl", 150, 400, 5, function()
        return (DH.GetSetting and DH:GetSetting("ilvl_threshold_complex")) or 245
    end, function(v)
        DH:SetSetting("ilvl_threshold_complex", v)
    end, function()
        local m = (DH.GetSetting and DH:GetSetting("adaptive_rotation")) or "auto"
        return m ~= "simple"
    end)
end

-- ============================================================================
-- HELP TAB (sections A-J)
-- ============================================================================

local function BuildHelp()
    AddHeader("A. Quick start")
    AddInfo("1. Pick your spec in the Wizard or let auto-detect choose it.")
    AddInfo("2. Enable rotation highlight in General.")
    AddInfo("3. Follow the highlighted action button or the icon window.")
    AddNote("The addon only suggests abilities you have actually learned.")
    AddNote("It works out of the box: spec, build and boss presets are detected automatically.")

    AddHeader("B. Tabs overview")
    AddInfo("Menu mode (General) picks Simple (main tabs) or Advanced (all tabs).")
    AddInfo("General - enable, build, targets, activity, cooldowns, alerts, interface.")
    AddInfo("Display - queue, icon window, highlight, colours, animations and layout.")
    AddInfo("Training - training mode, exam and mentor, learning stats.")
    AddInfo("Healer - heal assist, group health and heal-DPS (visible to all; editable by healer classes).")
    AddInfo("Class - per-class rotation options and rotation complexity.")
    AddInfo("Coaching - custom priorities (APL), DPS forecast, class pulse.")
    AddInfo("Timeline - boss timeline window, deep DBM/BigWigs phases, burst countdown.")
    AddInfo("System - arena and interface style.")
    AddInfo("Advanced - action-bar scanner, extras, timers and fine-tuning.")
    AddInfo("Status - version, live addon state, integrations, conflicts, diagnostics.")
    AddInfo("Profiles - switch or create a profile; advanced options add import/export, per-spec and boss profiles.")
    AddInfo("Help - this page.")

    AddHeader("C. Reading the highlight / priority legend")
    AddColorInfo("1 - Next ability (highest priority)", 1, 0.2, 0.2)
    AddColorInfo("2 - Cast next", 1, 0.82, 0)
    AddColorInfo("3 - Soon", 0.3, 1, 0.3)
    AddNote("The same colors are used on the action buttons and in the icon window.")
    AddNote("Glow styles: Pulse, Static, Flash, Rainbow, Breathe, Chase, Wave and Shimmer.")
    AddNote("Adjust thickness, number of rings and speed in Display > Highlight.")
    AddNote("Optional guide marker points at the next ability.")

    AddHeader("D. Windows")
    AddInfo("Icon window - top recommendations as icons (click the title for S/A/Au).")
    AddInfo("Cooldowns window - your major cooldowns, ready ones first.")
    AddInfo("Interrupt window - appears when your target starts casting.")
    AddInfo("Combat forecast - previews the abilities coming up next.")
    AddInfo("DPS forecast and class pulse - live performance hints next to the icon window.")
    AddInfo("Boss timeline window - current phase and upcoming timers.")
    AddInfo("Optional: phase indicator, group-aware raid buffs, resource bar.")
    AddNote("Enable and fine-tune them in Display > Cooldowns and interrupt windows.")
    AddInfo("Extras (Advanced): enemy counter, resource warnings, DoT panel, swing timer, group health.")
    AddInfo("Coach hub: status, cooldown plan, fight breakdown, history and lessons (General > Quick actions).")
    AddInfo("Panel configuration - a grid with a highlight on every window.")
    AddNote("Right-click a window for its settings: enable, size, scale, opacity and tint.")
    AddNote("Open it from Display > Configure panels, or type /rc config.")

    AddHeader("E. Modes")
    AddInfo("Training - recommends on a live target out of combat (e.g. a dummy).")
    AddInfo("Exam - quizzes you on the next ability; Mentor - shows full explanations.")
    AddInfo("PvP - priority interrupt > control > burst > survival.")
    AddInfo("Healer DPS - borrows your class DPS rotation while you heal.")

    AddHeader("F. Activity and profiles")
    AddInfo("Activity (General) sets the assumed fight length: raid, dungeon, solo, PvP.")
    AddInfo("Auto (General) follows your current content and encounters automatically.")
    AddInfo("Profiles tab: switch or create a profile in one click.")
    AddInfo("Advanced options: import/export, per-spec settings and boss profiles.")
    AddInfo("Boss profiles: a stored profile is applied automatically on the encounter.")
    AddNote("Profile import is parsed safely - no code is executed from the text.")

    AddHeader("G. Look and feel")
    AddInfo("Theme presets: Class color, Dark, Light, High contrast (General > Theme).")
    AddInfo("Custom palette: choose any accent colour applied to all windows (General > Interface).")
    AddInfo("Compact icon window and a unified window font (Advanced / System).")
    AddInfo("Colourblind-friendly priority palette (Display > Highlight).")
    AddInfo("Background style presets (default / matte) in System > Interface style.")
    AddInfo("Per-window colour: use the Tint button in panel configuration.")
    AddInfo("Interface style (System): UI skins and an options-window opacity slider.")
    AddInfo("RotationCore adapts to ElvUI / Bartender4 / Dominos automatically.")
    AddInfo("Fonts and sounds come from LibSharedMedia when it is installed.")
    AddNote("After changing the UI skin, confirm the reload prompt to apply it fully.")

    AddHeader("H. Diagnostics")
    AddInfo("Status shows the live state and the last errors; /rc log shows decisions.")
    AddInfo("The conflicts button opens the addon report.")

    AddHeader("I. Indicators and forecasts")
    AddInfo("GCD - the global cooldown (~1.5 s) shared by most abilities; the queue waits for it.")
    AddInfo("Combat forecast - previews the abilities and procs coming up in the next few seconds.")
    AddInfo("DPS forecast - predicts your DPS from the current rotation (optional, in Coaching).")
    AddInfo("Class pulse - a colour score of how well you follow the rotation (green / yellow / red).")

    AddHeader("Hotkeys")
    AddInfo("ALT-SHIFT-L - training mode")
    AddInfo("ALT-SHIFT-V - PvP mode")
    AddInfo("ALT-SHIFT-E - exam mode   ALT-SHIFT-M - mentor mode")
    AddNote("Open settings and Panel configuration can also be bound in Key Bindings > RotationCore.")

    AddHeader("Slash commands")
    AddInfo("/rc - open the options window")
    AddInfo("/rc help - this help   /rc help full - full wizard")
    AddInfo("/rc train | /rc pvp - training / PvP mode")
    AddInfo("/rc spec <name> - pick a build (no name lists them)")
    AddInfo("/rc pause - freeze recommendations (toggle)")
    AddInfo("/rc config - panel settings (size, scale, opacity, colour)")
    AddInfo("/rc move | /rc lock - move / lock the windows")
    AddInfo("/rc boss - boss profiles (/rc boss list|save|apply)")
    AddInfo("/rc hub - coach hub   /rc analyze - last fight breakdown")
    AddInfo("/rc sim - simulator   /rc talents - talent check   /rc apl edit - rotation editor")
    AddInfo("/rc status | /rc mem - live state / memory")
    AddInfo("/rc test rotation - self-test the current rotation")
    AddInfo("/rc errors [clear|file] - view the error log")

    AddHeader("Troubleshooting")
    AddInfo("/rc options - this window   /rc toggle - on/off   /rc status")
    AddInfo("/rc profile <name> - switch profile   /rc frame - icon window")
    AddInfo("Type /rc help for a full list of commands.")
end

-- Display tab = queue + highlight + colours + animations + layout. The glow
-- controls used to be duplicated in Advanced; they live here (and only here).
local function BuildDisplayGlow()
    AddHeader("Highlight")
    AddDropdown("Glow style", STRING_CHOICES.glow_style, function()
        return (DH.GetSetting and DH:GetSetting("glow_style")) or "pulse"
    end, function(v)
        DH:SetSetting("glow_style", v)
        DH:UpdateUI()
    end)
    AddCheckbox("Pulse glow", function()
        return DH.db.display.pulse ~= false
    end, function(v)
        DH.db.display.pulse = v
        DH:UpdateUI()
    end)
    AddCheckbox("Guide marker on the next ability", function()
        return DH.GetSetting and DH:GetSetting("guide_marker") == true
    end, function(v)
        DH:SetSetting("guide_marker", v)
        DH:UpdateUI()
    end)
    AddCheckbox("Highlight only while in combat", function()
        return DH.db.display.combat_only
    end, function(v)
        DH.db.display.combat_only = v
        DH:UpdateUI()
    end)
    AddCheckbox("Colourblind-friendly palette", function()
        return (DH.GetSetting and DH:GetSetting("colorblind_mode")) == true
    end, function(v)
        DH:SetSetting("colorblind_mode", v)
        if ns.ApplyPalette then ns.ApplyPalette() end
        DH:UpdateUI()
    end)
    AddSlider("Glow border thickness", 0.8, 2.5, 0.1, function()
        return (DH.GetSetting and DH:GetSetting("glow_thickness")) or 1.5
    end, function(v)
        DH:SetSetting("glow_thickness", v)
        DH:UpdateUI()
    end)
    AddSlider("Glow lines", 1, 6, 1, function()
        return (DH.GetSetting and DH:GetSetting("glow_lines")) or 1
    end, function(v)
        DH:SetSetting("glow_lines", v)
        DH:UpdateUI()
    end)
    AddSlider("Glow frequency", 0.25, 3, 0.25, function()
        return (DH.GetSetting and DH:GetSetting("glow_frequency")) or 1.0
    end, function(v)
        DH:SetSetting("glow_frequency", v)
        DH:UpdateUI()
    end)
end

local function BuildDisplayExtras()
    AddHeader("Battle indicators")
    AddCheckbox("Show battle phase indicator", function()
        return (DH.GetSetting and DH:GetSetting("phase_indicators")) ~= false
    end, function(v)
        DH:SetSetting("phase_indicators", v)
        if DH.UpdateUI then DH:UpdateUI() end
    end, function()
        return (DH.GetSetting and DH:GetSetting("battle_context_enabled")) ~= false
    end)
    AddCheckbox("Group awareness (raid buffs)", function()
        return (DH.GetSetting and DH:GetSetting("group_awareness_enabled")) ~= false
    end, function(v)
        DH:SetSetting("group_awareness_enabled", v)
    end)
    AddCheckbox("Resource bar", function()
        return (DH.GetSetting and DH:GetSetting("show_resource_bar")) == true
    end, function(v)
        DH:SetSetting("show_resource_bar", v)
        if DH.UpdateUI then DH:UpdateUI() end
    end)

    AddHeader("Cooldowns and interrupt windows")
    AddCheckbox("Show cooldowns window", function()
        return (DH.GetSetting and DH:GetSetting("show_cooldowns_display")) == true
    end, function(v)
        DH:SetSetting("show_cooldowns_display", v)
        DH:UpdateUI()
    end)
    AddCheckbox("Show interrupt window", function()
        return (DH.GetSetting and DH:GetSetting("show_interrupts_display")) == true
    end, function(v)
        DH:SetSetting("show_interrupts_display", v)
        DH:UpdateUI()
    end)
    AddInfo("Icons, sizes and positions: Display > Cooldowns and interrupt windows.")

    AddInfo("Enable/disable the windows on the Display tab.")
    AddSlider("Cooldowns window icons", 1, 10, 1, function()
        return (DH.GetSetting and DH:GetSetting("cooldowns_num_icons")) or 3
    end, function(v)
        DH:SetSetting("cooldowns_num_icons", v)
        DH:UpdateUI()
    end)

    AddSlider("Cooldowns: minimum CD (s)", 30, 300, 10, function()
        return (DH.GetSetting and DH:GetSetting("cooldowns_min_cd")) or 60
    end, function(v)
        DH:SetSetting("cooldowns_min_cd", v)
        DH:UpdateUI()
    end)

    AddCheckbox("Cooldowns: list ready ones first", function()
        return (DH.GetSetting and DH:GetSetting("cooldowns_show_ready")) ~= false
    end, function(v)
        DH:SetSetting("cooldowns_show_ready", v)
        DH:UpdateUI()
    end)

    AddCheckbox("Cooldowns: hide the window when nothing is ready", function()
        return (DH.GetSetting and DH:GetSetting("cooldowns_hide_empty")) == true
    end, function(v)
        DH:SetSetting("cooldowns_hide_empty", v)
        DH:UpdateUI()
    end)

    AddSlider("Cooldowns window size", 0.5, 2.5, 0.1, function()
        return (DH.GetSetting and DH:GetSetting("cooldowns_scale")) or 1
    end, function(v)
        DH:SetSetting("cooldowns_scale", v)
        DH:UpdateUI()
    end)

    AddCheckbox("Interrupt window: keep it visible when idle", function()
        return (DH.GetSetting and DH:GetSetting("interrupts_always_show")) == true
    end, function(v)
        DH:SetSetting("interrupts_always_show", v)
        DH:UpdateUI()
    end)
    AddCheckbox("Play a sound when the interrupt is ready", function()
        return (DH.GetSetting and DH:GetSetting("interrupt_ready_sound")) == true
    end, function(v)
        DH:SetSetting("interrupt_ready_sound", v)
    end)

    AddSlider("Interrupt window size", 0.5, 2.5, 0.1, function()
        return (DH.GetSetting and DH:GetSetting("interrupts_scale")) or 1
    end, function(v)
        DH:SetSetting("interrupts_scale", v)
        DH:UpdateUI()
    end)

    AddButton("Reset optional window positions", function()
        if DH.db and DH.db.common then
            DH.db.common.cooldowns_position = { x = -170, y = -250 }
            DH.db.common.interrupts_position = { x = 170, y = -250 }
        end
        if ns.RefreshExtraFrames then ns.RefreshExtraFrames() end
        DH:UpdateUI()
        DH:Print(L("Optional window positions reset."))
    end, 260)

    AddHeader("Combat forecast")
    AddCheckbox("Show combat forecast", function()
        return DH.GetSetting and DH:GetSetting("combat_forecast_enabled") == true
    end, function(v)
        DH:SetSetting("combat_forecast_enabled", v)
        if DH.UpdateUI then DH:UpdateUI() end
    end)
    AddSlider("Forecast window (s)", 2, 15, 1, function()
        return (DH.GetSetting and DH:GetSetting("forecast_window")) or 5
    end, function(v)
        DH:SetSetting("forecast_window", v)
        if DH.UpdateUI then DH:UpdateUI() end
    end, function()
        return DH.GetSetting and DH:GetSetting("combat_forecast_enabled") == true
    end)
    AddSlider("Forecast lines", 1, 5, 1, function()
        return (DH.GetSetting and DH:GetSetting("forecast_max_lines")) or 3
    end, function(v)
        DH:SetSetting("forecast_max_lines", v)
    end, function()
        return DH.GetSetting and DH:GetSetting("combat_forecast_enabled") == true
    end)
end

local function BuildDisplay()
    AddNote(L("How the recommendations look: queue, highlight, colours, animations, layout and windows."))
    BuildSpellQueue()
    BuildDisplayGlow()
    BuildLayout()
    BuildDisplayWindow()
    BuildColors()
    BuildAnimations()
    BuildDisplayExtras()
end

local function BuildStatus()
    AddNote(L("Version, live addon state, integrations, conflicts and diagnostics."))
    AddHeader("Version and build")
    local function st() return (DH.GetAddonState and DH:GetAddonState()) or {} end
    AddTile("Version", function() return "v" .. tostring((ns.BUILD and ns.BUILD.version) or (DH.Version or "?")) end)
    AddTile("Spec", function() return tostring(st().spec or "?") end)
    AddTile("Memory", function() return string.format("%.1f MB", st().memoryMB or 0) end)
    AddTile("CPU", function() return st().cpu and string.format("%.3f", st().cpu) or "n/a" end)
    AddTile("Errors", function() return tostring(st().errors or 0) end)
    AddTile("Priority", function() return tostring(#(ns.recommendations or {})) end)
    AddInfo(L("Interface: ") .. tostring((ns.BUILD and ns.BUILD.interface) or 30300) .. " (Wrath 3.3.5a)")
    AddInfo(L("Author: ") .. tostring((ns.BUILD and ns.BUILD.author) or "Custom"))
    AddInfo(L("Build date: ") .. tostring((ns.BUILD and ns.BUILD.date) or "?"))
    AddInfo(L("Lua files: ") .. tostring((ns.BUILD and ns.BUILD.files) or "?")
        .. " | LOC: " .. tostring((ns.BUILD and ns.BUILD.loc) or "?"))

    AddHeader("Addon state")
    local function state() return (DH.GetAddonState and DH:GetAddonState()) or {} end
    AddLiveInfo(function()
        local st = state()
        return L("Enabled: ") .. (st.enabled and ("|cFF33FF33" .. L("YES") .. "|r")
            or ("|cFFE04040" .. L("NO") .. "|r"))
    end)
    AddLiveInfo(function()
        local st = state()
        return L("Spec: ") .. tostring(st.spec or "?") .. " (" .. tostring(st.specRole or "?") .. ")"
    end)
    AddLiveInfo(function()
        local st = state()
        return L("Mode: ") .. tostring(st.mode or "?") .. " | " .. L("Profile: ") .. tostring(st.profile or "?")
    end)
    AddLiveInfo(function()
        local act = (DH.GetSetting and DH:GetSetting("activity_profile")) or "?"
        local tm = (DH.GetSetting and DH:GetSetting("target_mode")) or "?"
        return L("Activity: ") .. tostring(act) .. " | " .. L("Target mode: ") .. tostring(tm)
    end)
    AddLiveInfo(function()
        local n = #(ns.recommendations or {})
        local ph = (ns.GetTimelinePhase and ns.GetTimelinePhase()) or 1
        return L("Priority: ") .. tostring(n) .. " | " .. L("Timeline phase: ") .. tostring(ph)
    end)
    AddLiveInfo(function()
        local st = state()
        return L("SpellFrame: ") .. (st.spellframe and L("shown") or L("hidden"))
            .. " | " .. L("OnUpdate: ") .. (st.updateActive and L("active") or L("idle"))
    end)
    AddLiveInfo(function()
        local st = state()
        return string.format(L("Memory: %.1f MB | Uptime: %d s"), st.memoryMB or 0, math.floor(st.uptime or 0))
    end)
    AddLiveInfo(function()
        local st = state()
        return L("CPU: ") .. (st.cpu and string.format("%.3f", st.cpu) or "n/a")
            .. L(" | Errors: ") .. tostring(st.errors or 0)
    end)
    AddLiveInfo(function()
        local spec = DH.GetActiveSpec and DH:GetActiveSpec()
        local det = DH.MatchModeKey and DH:MatchModeKey(spec)
        local cur = DH.db and DH.db.mode
        if det and cur and det ~= cur then
            return "|cFFFF4040" .. L("Build mismatch:") .. "|r "
                .. tostring(cur) .. " != " .. tostring(det)
        end
        return "|cFF33FF33" .. L("Build matches the talents.") .. "|r"
    end)
    AddButton("Refresh", function()
        if DH.NotifyOptions then DH:NotifyOptions() end
    end, 120)

    AddHeader("Integrations")
    local ints = (DH.ScanIntegrations and DH:ScanIntegrations()) or {}
    for _, r in ipairs(ints) do
        local name = r.found and ("|cFF33FF33" .. tostring(r.addon) .. "|r")
            or ("|cFF777777" .. tostring(r.addon) .. "|r")
        AddInfo(name .. "  -  " .. L(tostring(r.what or "")))
    end

    AddHeader("Conflicts")
    if not StaticPopupDialogs["ROTATIONCORE_CONFLICTS"] then
        StaticPopupDialogs["ROTATIONCORE_CONFLICTS"] = {
            text = "",
            button1 = L("Close"),
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
    end
    local conflicts = (DH.ScanConflicts and DH:ScanConflicts()) or {}
    if #conflicts == 0 then
        AddNote(L("No addon conflicts detected."))
    else
        AddNote(string.format(L("%d potential conflict(s) detected. Open the report for details."), #conflicts))
    end
    AddButton("Show addon conflicts", function()
        local cs = (DH.ScanConflicts and DH:ScanConflicts()) or {}
        local lines = {}
        if #cs == 0 then
            lines[#lines + 1] = L("No addon conflicts detected.")
        else
            for _, c in ipairs(cs) do
                lines[#lines + 1] = "|cFFFFD100" .. table.concat(c.addons, ", ") .. "|r"
                lines[#lines + 1] = "  " .. L(c.reason)
                if c.suggest then lines[#lines + 1] = "  " .. L(c.suggest) end
            end
        end
        StaticPopupDialogs["ROTATIONCORE_CONFLICTS"].text = table.concat(lines, "\n")
        StaticPopup_Show("ROTATIONCORE_CONFLICTS")
    end, 240)

    AddHeader("Diagnostics")
    AddInfo("/rc errors - last errors    /rc log - decisions")
    AddInfo("/rc status - text status    /rc mem - memory")
    AddInfo("/rc loadtime - load time")
    if DH.GetLastErrors then
        local errs = DH:GetLastErrors(3)
        for _, e in ipairs(errs) do
            AddNote(e)
        end
    end
    AddButton("Copy diagnostics", function()
        if DH.StatusReport and DH.Print then
            local r = DH:StatusReport()
            DH:Print(L("--- RotationCore diagnostics ---"))
            for _, line in ipairs({ strsplit("\n", r) }) do
                DH:Print(line)
            end
            DH:Print(L("--- end ---"))
            DH:Print(L("Copy the lines above into a bug report."))
        end
    end, 200)

end

local function BuildHealer()
    -- The tab is listed for every class so the feature is discoverable, but
    -- only healer classes (Priest / Druid / Shaman / Paladin) can tune it.
    if not (ns.IsHealerClass and ns.IsHealerClass()) then
        AddNote(L("Healer tools apply to Priest, Druid, Shaman and Paladin. Your class uses the normal DPS rotation."))
        return
    end
    AddNote(L("Healer's rotation, heal assist and group health."))
    AddHeader("Rotation")
    AddDropdown("Heal-spec DPS rotation", STRING_CHOICES.heal_dps_mode, function()
        return (DH.GetSetting and DH:GetSetting("heal_dps_mode")) or "auto"
    end, function(v)
        DH:SetSetting("heal_dps_mode", v)
        DH:UpdateRecommendations()
    end)
    AddInfo("Borrows your class DPS rotation while you heal.")

    AddHeader("Heal assist")
    AddCheckbox("Heal assist window", function()
        return (DH.GetSetting and DH:GetSetting("heal_assist_enabled")) == true
    end, function(v)
        DH:SetSetting("heal_assist_enabled", v)
    end)
    AddInfo("Suggests a heal for the lowest-health group member.")

    AddHeader("Group")
    AddCheckbox("Group health monitor", function()
        return (DH.GetSetting and DH:GetSetting("party_health_enabled")) == true
    end, function(v)
        DH:SetSetting("party_health_enabled", v)
    end)
end

local BUILDERS = {
    general = BuildGeneral,
    display = BuildDisplay,
    class = BuildClass,
    profiles = BuildProfiles,
    advanced = BuildAdvanced,
    coaching = BuildCoaching,
    training = BuildTraining,
    healer = BuildHealer,
    timeline = BuildTimeline,
    system = BuildSystem,
    status = BuildStatus,
    help = BuildHelp,
}

-- ============================================================================
-- WINDOW
-- ============================================================================

local function SaveFramePos()
    if not frame then return end
    local g = DH.dbRoot and DH.dbRoot.global
    if type(g) ~= "table" then return end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    g.optionsPos = { x = cx - ux, y = cy - uy }
end

local function SaveFrameSize()
    if not frame then return end
    local g = DH.dbRoot and DH.dbRoot.global
    if type(g) ~= "table" then return end
    g.optionsSize = { w = frame:GetWidth(), h = frame:GetHeight() }
end

local function ApplyFramePos()
    local g = DH.dbRoot and DH.dbRoot.global
    local pos = type(g) == "table" and g.optionsPos or nil
    local size = type(g) == "table" and g.optionsSize or nil
    if size and size.w and size.h then
        frame:SetSize(math.max(660, size.w), math.max(460, size.h))
    end
    frame:ClearAllPoints()
    if pos and pos.x and pos.y then
        frame:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function ApplyTheme()
    if not frame then return end
    UpdatePalette()
    local th = (DH.GetUITheme and DH:GetUITheme()) or { backdrop = { 0, 0, 0, 0.95 }, border = { 0.4, 0.4, 0.4 }, title = { 1, 0.82, 0 } }
    -- Skins carry their own backdrop textures, so re-apply the full backdrop
    -- here: switching the skin must repaint the whole window, not just its
    -- tint (otherwise skins look identical).
    if ns.ApplyBgStyle then th = ns.ApplyBgStyle(th) end
    if th.bg and frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = th.bg, edgeFile = th.edge or th.bg,
            tile = th.tile, tileSize = th.tileSize or 16,
            edgeSize = th.edgeSize or 16,
            insets = th.insets or { left = 4, right = 4, top = 4, bottom = 4 },
        })
    end
    if frame.SetBackdropColor then
        local op = tonumber(DH.GetSetting and DH:GetSetting("ui_opacity")) or 1
        if op < 0.2 then op = 0.2 elseif op > 1 then op = 1 end
        frame:SetBackdropColor(th.backdrop[1], th.backdrop[2], th.backdrop[3], op)
    end
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3])
    end
    if frame.title then
        frame.title:SetTextColor(th.title[1], th.title[2], th.title[3])
    end
    -- Sidebar buttons share the window plate so skins stay consistent.
    do
        local op = tonumber(DH.GetSetting and DH:GetSetting("ui_opacity")) or 1
        if op < 0.2 then op = 0.2 elseif op > 1 then op = 1 end
        for _, b in pairs(catButtons) do
            if b and b.SetBackdropColor then
                b:SetBackdropColor(th.backdrop[1], th.backdrop[2], th.backdrop[3],
                    math.min(1, op * 0.96))
            end
        end
    end
    if frame.seps and th.border then
        for _, sep in ipairs(frame.seps) do
            if sep.SetVertexColor then
                sep:SetVertexColor(th.border[1], th.border[2], th.border[3], 0.6)
            end
        end
    end
end
ns.ApplyOptionsTheme = ApplyTheme

-- Position the visible category buttons and hide the rest. Called on every
-- rebuild so toggling "Menu mode" (Simple / Advanced) takes effect at once.
LayoutCatButtons = function()
    if not frame then return end
    for _, cat in ipairs(CATEGORIES) do
        local b = catButtons[cat.key]
        if b then b:Hide() end
    end
    local vis = VisibleCategories()
    local BTN_STEP = 42
    local SEP_GAP = 18
    local y = -54
    local sepIndex = 0
    for i, cat in ipairs(vis) do
        if cat.sepBefore and i > 1 then
            y = y - SEP_GAP
            sepIndex = sepIndex + 1
            local sep = frame.seps and frame.seps[sepIndex]
            if sep then
                sep:ClearAllPoints()
                sep:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y + SEP_GAP * 0.5)
                sep:SetPoint("TOPRIGHT", frame, "TOPLEFT", 184, y + SEP_GAP * 0.5)
                sep:Show()
            end
        end
        local b = catButtons[cat.key]
        if b then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, y)
            b:Show()
            local active = (cat.key == currentCat)
            local cr, cg, cb = 1, 0.82, 0
            if DH.GetClassColor then cr, cg, cb = DH:GetClassColor() end
            if b.fs then
                if active then
                    b.fs:SetTextColor(cr, cg, cb)
                else
                    b.fs:SetTextColor(PAL.info[1], PAL.info[2], PAL.info[3])
                end
            end
            if b.icon then
                if active then b.icon:SetVertexColor(cr, cg, cb) else b.icon:SetVertexColor(PAL.info[1], PAL.info[2], PAL.info[3]) end
            end
            if b.accent then b.accent:Hide() end
            if active and frame.accentBar then
                frame.accentTargetY = y
                if not frame._accentInit then frame.accentCurY = y; frame._accentInit = true end
                frame.accentBar:SetVertexColor(cr, cg, cb, 1)
                frame.accentBar:Show()
            end
            if b.SetBackdropColor then
                if active then b:SetBackdropColor(0.15, 0.15, 0.15, 0.96) else b:SetBackdropColor(0.07, 0.07, 0.07, 0.92) end
            end
            if b.SetBackdropBorderColor then
                if active then
                    b:SetBackdropBorderColor(cr, cg, cb, 1)
                else
                    b:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
                end
            end
        end
        y = y - BTN_STEP
    end
    if frame.seps then
        for j = sepIndex + 1, #frame.seps do
            frame.seps[j]:Hide()
        end
    end
end

local function CatButtonFactory(cat)
    local b = CreateFrame("Button", NewName(), frame)
    b:SetSize(184, 34)
    b:SetNormalTexture("Interface\\Buttons\\UI-Button-Background")
    b:SetPushedTexture("Interface\\Buttons\\UI-Button-Background")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Button-Background")
    if b.GetNormalTexture then
        local t = b:GetNormalTexture()
        if t and t.SetVertexColor then t:SetVertexColor(0.12, 0.12, 0.12, 1) end
    end
    if b.GetPushedTexture then
        local t = b:GetPushedTexture()
        if t and t.SetVertexColor then t:SetVertexColor(0.05, 0.05, 0.05, 1) end
    end
    if b.GetHighlightTexture then
        local t = b:GetHighlightTexture()
        if t and t.SetVertexColor then t:SetVertexColor(1, 0.82, 0, 0.22) end
    end
    b:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        bgFile = "Interface\\Buttons\\UI-Button-Background",
        tile = true, tileSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if b.SetBackdropColor then b:SetBackdropColor(0.07, 0.07, 0.07, 0.92) end
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER")
    fs:SetText(L(cat.label))
    if cat.icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
        b.icon:SetTexture(cat.icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        fs:SetJustifyH("LEFT")
    end
    b.accent = b:CreateTexture(nil, "OVERLAY")
    b.accent:SetSize(3, 26)
    b.accent:SetPoint("LEFT", b, "LEFT", 2, 0)
    b.accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.accent:Hide()
    b.fs = fs
    b.catKey = cat.key
    b:SetScript("OnClick", function(self)
        currentCat = self.catKey
        BuildContent()
    end)
    return b
end

local contentFade = 0
local contentFadeStart = 0
local function StartContentFade()
    if not content or content.SetAlpha == nil then return end
    if ns.inCombat then
        content:SetAlpha(1)
        return
    end
    if (DH.GetSetting and DH:GetSetting("animations_enabled")) == false then
        content:SetAlpha(1)
        return
    end
    content:SetAlpha(0)
    contentFade = 0
    contentFadeStart = GetTime()
    content:SetScript("OnUpdate", function(self, elapsed)
        contentFade = contentFade + elapsed
        local k = math.min(1, contentFade / 0.22)
        local a = 1 - (1 - k) * (1 - k)
        self:SetAlpha(a)
        if a >= 1 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

BuildContent = function()
    if not content then
        if DH.Print then DH:Print(L("Options window is not ready yet.")) end
        return
    end
    ApplyTheme()
    -- Keep the scroll position across rebuilds (the widgets change, the
    -- category usually does not)
    local keepScroll = (scroll and scroll:GetVerticalScroll()) or 0

    -- SetParent(nil) is illegal for fonts and textures in 3.3.5a
    -- ("Cannot set a 'nil' parent for fonts or textures"), so only frames
    -- are detached - everything else just drops its anchor points.
    for i = #rows, 1, -1 do
        local r = rows[i]
        r:Hide()
        if r.IsObjectType and r:IsObjectType("Frame") then
            r:SetParent(nil)
        else
            r:ClearAllPoints()
        end
        rows[i] = nil
    end
    cursor = -12
    statusLive = {}   -- rebuilt below by the active builder

    -- Fall back to General when the key is unknown or hidden by the menu
    -- mode (e.g. the Advanced tab is hidden while "Simple" is selected).
    if (not BUILDERS[currentCat]) or (not IsCategoryVisible(currentCat)) then
        currentCat = "general"
    end

    LayoutCatButtons()

    local builder = BUILDERS[currentCat]
    if builder then
        local okb, errb = pcall(builder)
        if not okb then
            AddInfo("|cFFE04040" .. L("Options error:") .. "|r " .. tostring(errb))
            if DH.Print then DH:Print(string.format(L("RotationCore options error: %s"), tostring(errb))) end
        end
    end

    content:SetHeight(math.max(1, -cursor + 24))
    if scroll then
        local range = scroll:GetVerticalScrollRange()
        if keepScroll > range then keepScroll = range end
        if keepScroll < 0 then keepScroll = 0 end
        scroll:SetVerticalScroll(keepScroll)
    end

    for _, cat in ipairs(CATEGORIES) do
        local b = catButtons[cat.key]
        if b and b.fs then
            if cat.key == currentCat then
                b.fs:SetTextColor(PAL.header[1], PAL.header[2], PAL.header[3])
            else
                b.fs:SetTextColor(PAL.info[1], PAL.info[2], PAL.info[3])
            end
        end
    end
    StartContentFade()
end

local function EnsureFrameRaw()
    if frame then return frame end

    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetSize(640, 560)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    local th = (DH.GetUITheme and DH:GetUITheme()) or {
        backdrop = { 0, 0, 0, 0.95 }, border = { 0.4, 0.4, 0.4 }, title = { 1, 0.82, 0 },
        bg = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edge = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16, tile = true, tileSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    }
    frame:SetBackdrop({
        bgFile = th.bg, edgeFile = th.edge,
        tile = th.tile, tileSize = th.tileSize,
        edgeSize = th.edgeSize, insets = th.insets,
    })
    frame:SetBackdropColor(th.backdrop[1], th.backdrop[2], th.backdrop[3], th.backdrop[4])
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3])
    end

    -- Custom resize grip (3.3.5a has no Frame:SetResizable).
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetScript("OnMouseDown", function()
        local sx, sy = GetCursorPosition()
        resizeStart = { w = frame:GetWidth(), h = frame:GetHeight(), x = sx, y = sy, scale = UIParent:GetScale() }
    end)
    grip:SetScript("OnMouseUp", function()
        resizeStart = nil
        SaveFrameSize()
    end)
    grip:SetScript("OnUpdate", function()
        if not resizeStart then return end
        local cx, cy = GetCursorPosition()
        local w = resizeStart.w + (cx - resizeStart.x) / resizeStart.scale
        local h = resizeStart.h - (cy - resizeStart.y) / resizeStart.scale
        w = math.max(660, math.min(1000, w))
        h = math.max(460, math.min(900, h))
        frame:SetSize(w, h)
    end)

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePos()
    end)

    -- Live refresh for the Status tab: repaint only the registered dynamic rows
    -- every 0.5 s while the window is open on that tab (no full rebuild, so the
    -- scroll position and the content fade are left alone).
    frame.statusTick = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        if frame.accentBar and frame.accentTargetY and frame.accentCurY then
            local d = frame.accentTargetY - frame.accentCurY
            if math.abs(d) < 0.5 then
                frame.accentCurY = frame.accentTargetY
            else
                frame.accentCurY = frame.accentCurY + d * math.min(1, elapsed * 14)
                frame.accentBar:ClearAllPoints()
                frame.accentBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, frame.accentCurY)
            end
        end
        if not frame:IsShown() or currentCat ~= "status" then return end
        frame.statusTick = frame.statusTick + elapsed
        if frame.statusTick < 0.5 then return end
        frame.statusTick = 0
        if #statusLive > 0 then RefreshStatusLive() end
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 52, -14)
    title:SetText(L("RotationCore Settings"))
    title:SetTextColor(th.title[1], th.title[2], th.title[3])
    frame.title = title

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\RotationCore\\icon")
    logo:SetSize(28, 28)
    logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -9)
    frame.logo = logo

    local close = CreateFrame("Button", NewName(), frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Sidebar: fixed 160px-wide buttons plus group separators (dynamic).
    for _, cat in ipairs(CATEGORIES) do
        catButtons[cat.key] = CatButtonFactory(cat)
    end
    frame.seps = {}
    for i = 1, 3 do
        local sep = frame:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetTexture(1, 1, 1)
        sep:SetVertexColor(0.3, 0.3, 0.3, 0.6)
        sep:Hide()
        frame.seps[i] = sep
    end
    frame.accentBar = frame:CreateTexture(nil, "OVERLAY")
    frame.accentBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.accentBar:SetSize(3, 30)
    frame.accentBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -56)
    frame.accentBar:Hide()
    frame.accentCurY = -56
    frame.accentTargetY = -56
    LayoutCatButtons()

    scroll = CreateFrame("ScrollFrame", NewName(), frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + 180 + 8, -46)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 16)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = self:GetVerticalScroll() - (delta * 40)
        local range = self:GetVerticalScrollRange()
        if v < 0 then v = 0 end
        if v > range then v = range end
        self:SetVerticalScroll(v)
    end)

    content = CreateFrame("Frame", NewName(), scroll)
    content:SetWidth(CONTENT_WIDTH)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = FRAME_NAME
    end

    return frame
end

-- Transactional wrapper: if the one-time build fails, drop the partial frame
-- so the next open retries from scratch (prevents an empty window forever).
local function EnsureFrame()
    if frame then return frame end
    local ok, err = pcall(EnsureFrameRaw)
    if not ok then
        frame = nil
        error(tostring(err), 0)
    end
    return frame
end

-- ============================================================================
-- PUBLIC API (called from the slash commands and from the core)
-- ============================================================================

function DH:OpenOptions()
    if not self.db then
        self:Print(L("Settings are not ready yet."))
        return
    end
    EnsureFrame()
    ApplyFramePos()
    BuildContent()
    frame:Show()
    frame:Raise()
end

-- Open the window on a specific category (used by the Setup Wizard)
function DH:OpenOptionsTab(key)
    if not self.db then
        self:Print(L("Settings are not ready yet."))
        return
    end
    EnsureFrame()
    if key == "wizard" then key = "general" end   -- wizard button lives in General
    for _, cat in ipairs(CATEGORIES) do
        if cat.key == key then
            currentCat = key
            break
        end
    end
    ApplyFramePos()
    BuildContent()
    frame:Show()
    frame:Raise()
end

function DH:CloseOptions()
    if frame then
        frame:Hide()
    end
end

-- Rebuild the open window (no-op when it is closed)
function DH:RefreshOptions()
    if not frame or not frame:IsShown() then return end
    BuildContent()
end

-- ============================================================================
-- DELETE PROFILE CONFIRMATION
-- ============================================================================

-- Phase 3.2: apply a decoded import once the player picks a target
local function ApplyImportedProfile(mode)
    local data = pendingImport
    pendingImport = nil
    if not data then return end
    local name, err = DH:ImportProfile(data, mode)
    if name then
        DH:Print(L("Imported profile: ") .. name)
    else
        DH:Print(err or L("Import failed"))
    end
    DH:NotifyOptions()
end

if StaticPopupDialogs then
    StaticPopupDialogs["ROTATIONCORE_IMPORT_PROFILE"] = {
        text = L("Import this profile?"),
        button1 = L("Replace current"),
        button2 = L("Create new"),
        OnAccept = function() ApplyImportedProfile("replace") end,
        OnCancel = function() ApplyImportedProfile("new") end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
    }

    StaticPopupDialogs["ROTATIONCORE_DELETE_PROFILE"] = {
        text = L("Delete profile '%s'?\nThis cannot be undone."),
        button1 = (_G.YES or "Yes"),
        button2 = (_G.NO or "No"),
        OnAccept = function()
            local name = DH:GetCurrentProfileName()
            local ok, err = DH:DeleteProfile(name)
            if ok then
                DH:Print(L("Deleted profile: ") .. name)
            elseif err then
                DH:Print(err)
            end
            DH:NotifyOptions()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["ROTATIONCORE_RELOAD_UI_SKIN"] = {
        text = L("Skin changed. Reload the UI now to apply it everywhere?"),
        button1 = L("Reload UI"),
        button2 = (_G.CANCEL or "Cancel"),
        OnAccept = function()
            if ReloadUI then ReloadUI() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

-- ============================================================================
-- PROFILE IMPORT / EXPORT POPUP WINDOW
-- A dedicated, movable window with a large scrolling text box. The old inline
-- EditBoxes lived inside the scrolling options list and broke the row layout.
-- ============================================================================

local profileTextWindow

local function CreateProfileTextWindow()
    if profileTextWindow then return profileTextWindow end

    local w = CreateFrame("Frame", "RotationCoreProfileTextWindow", UIParent)
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetClampedToScreen(true)
    w:SetSize(560, 380)
    w:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    w:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    w:SetBackdropColor(0, 0, 0, 0.9)
    w:SetScript("OnDragStart", function(self) self:StartMoving() end)
    w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "RotationCoreProfileTextWindow") end

    local title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", w, "TOP", 0, -14)
    title:SetTextColor(1, 0.82, 0)
    w.title = title

    local hint = w:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetTextColor(0.75, 0.75, 0.75)
    w.hint = hint

    local sb = CreateFrame("ScrollFrame", "RotationCoreProfileTextScroll", w)
    sb:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -60)
    sb:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -16, 52)
    sb:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    sb:SetBackdropColor(0, 0, 0, 0.6)
    sb:EnableMouseWheel(true)
    sb:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll() - delta * 34
        local maxS = self:GetVerticalScrollRange() or 0
        if cur < 0 then cur = 0 elseif cur > maxS then cur = maxS end
        self:SetVerticalScroll(cur)
    end)
    w.scroll = sb

    local edit = CreateFrame("EditBox", "RotationCoreProfileTextEdit", sb)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(0)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(516)
    edit:SetHeight(300)
    edit:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
    edit:SetTextInsets(6, 6, 6, 6)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        local _, fontSize = self:GetFont()
        fontSize = fontSize or 12
        local perLine = math.max(1, math.floor(self:GetWidth() / (fontSize * 0.5)))
        local lines = 0
        local probe = text .. "\n"
        for line in probe:gmatch("(.-)\n") do
            lines = lines + math.max(1, math.ceil(#line / perLine))
        end
        self:SetHeight(math.max(140, lines * (fontSize + 4) + 12))
    end)
    sb:SetScrollChild(edit)
    w.edit = edit

    local okBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    okBtn:SetSize(160, 24)
    okBtn:SetPoint("BOTTOMRIGHT", w, "BOTTOM", -8, 16)
    w.okBtn = okBtn

    local closeBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    closeBtn:SetSize(160, 24)
    closeBtn:SetPoint("BOTTOMLEFT", w, "BOTTOM", 8, 16)
    closeBtn:SetText(_G.CLOSE or "Close")
    closeBtn:SetScript("OnClick", function() w:Hide() end)

    w:Hide()
    profileTextWindow = w
    return w
end

function ns.ShowProfileExportWindow()
    if not DH.db then return end
    local w = CreateProfileTextWindow()
    local s, err = DH:EncodeProfile()
    w.title:SetText(L("Export profile"))
    w.hint:SetText(L("Select all, then press Ctrl+C to copy."))
    w.edit:SetText(s or (err or L("Export failed")))
    w.okBtn:SetText(L("Copy"))
    w.okBtn:SetScript("OnClick", function()
        w.edit:SetFocus()
        w.edit:HighlightText()
        DH:Print(L("Profile exported - press Ctrl+C to copy the text."))
    end)
    w:Show()
    w.edit:SetFocus()
    w.edit:HighlightText()
end

function ns.ShowProfileImportWindow()
    if not DH.db then return end
    local w = CreateProfileTextWindow()
    w.title:SetText(L("Import profile"))
    w.hint:SetText(L("Paste text, then click Import."))
    w.edit:SetText("")
    w.okBtn:SetText(L("Import"))
    w.okBtn:SetScript("OnClick", function()
        local data, err = DH:DecodeProfile(w.edit:GetText())
        if not data then
            DH:Print(err or L("Import failed"))
            return
        end
        pendingImport = data
        if StaticPopup_Show then
            StaticPopup_Show("ROTATIONCORE_IMPORT_PROFILE")
        else
            ApplyImportedProfile("replace")
        end
    end)
    w:Show()
    w.edit:SetFocus()
end

-- Prompt 2: boss-profile export / import (safe text, no code execution)
function ns.ShowBossProfileExportWindow()
    if not DH.db then return end
    local w = CreateProfileTextWindow()
    w.title:SetText(L("Export boss profiles"))
    w.hint:SetText(L("Select all, then press Ctrl+C to copy."))
    w.edit:SetText(DH:ExportBossProfiles())
    w.okBtn:SetText(L("Copy"))
    w.okBtn:SetScript("OnClick", function()
        w.edit:SetFocus()
        w.edit:HighlightText()
        DH:Print(L("Boss profiles exported - press Ctrl+C."))
    end)
    w:Show()
    w.edit:SetFocus()
    w.edit:HighlightText()
end

function ns.ShowBossImportWindow()
    if not DH.db then return end
    local w = CreateProfileTextWindow()
    w.title:SetText(L("Import boss profiles"))
    w.hint:SetText(L("Paste text, then click Import."))
    w.edit:SetText("")
    w.okBtn:SetText(L("Import"))
    w.okBtn:SetScript("OnClick", function()
        local n = DH:ImportBossProfiles(w.edit:GetText())
        DH:Print(L("Boss profiles imported: ") .. n)
        if DH.NotifyOptions then DH:NotifyOptions() end
        w:Hide()
    end)
    w:Show()
    w.edit:SetFocus()
end

-- Prompt 3.4: display-layout export / import (safe text, separate from the
-- profile export; positions only).
function ns.ShowLayoutExportWindow()
    if not DH.db then return end
    local w = CreateProfileTextWindow()
    w.title:SetText(L("Export layout"))
    w.hint:SetText(L("Select all, then press Ctrl+C to copy."))
    w.edit:SetText(ns.ExportLayout and ns.ExportLayout() or "")
    w.okBtn:SetText(L("Copy"))
    w.okBtn:SetScript("OnClick", function()
        w.edit:SetFocus()
        w.edit:HighlightText()
        DH:Print(L("Layout exported - press Ctrl+C."))
    end)
    w:Show()
    w.edit:SetFocus()
    w.edit:HighlightText()
end

function ns.ShowLayoutImportWindow()
    if not DH.db then return end
    local w = CreateProfileTextWindow()
    w.title:SetText(L("Import layout"))
    w.hint:SetText(L("Paste text, then click Import."))
    w.edit:SetText("")
    w.okBtn:SetText(L("Import"))
    w.okBtn:SetScript("OnClick", function()
        local n = ns.ImportLayout and ns.ImportLayout(w.edit:GetText()) or 0
        DH:Print(L("Layout imported: ") .. n)
        if DH.NotifyOptions then DH:NotifyOptions() end
        w:Hide()
    end)
    w:Show()
    w.edit:SetFocus()
end

-- Improvement 6: custom APL import / export windows (reuse the safe text
-- window; the text is parsed by hand - no code is ever executed).
function ns.ShowAPLImportWindow()
    if not DH.db then return end
    local w = CreateProfileTextWindow()
    w.title:SetText(L("Import APL"))
    w.hint:SetText(L("Paste a priority list, then click Import."))
    w.edit:SetText("")
    w.okBtn:SetText(L("Import"))
    w.okBtn:SetScript("OnClick", function()
        local n, err = ns.SetCustomAPL(DH, ns.DecodeAPLShare(w.edit:GetText() or ""))
        if n and n > 0 then
            DH:SetSetting("custom_apl_enabled", true)
            DH:Print(L("APL imported: ") .. n .. " " .. L("rules"))
            if DH.NotifyOptions then DH:NotifyOptions() end
            w:Hide()
        else
            DH:Print(L("APL error: ") .. tostring(err))
        end
    end)
    w:Show()
    w.edit:SetFocus()
end

function ns.ShowAPLExportWindow()
    if not DH.db then return end
    local w = CreateProfileTextWindow()
    w.title:SetText(L("Export APL"))
    w.hint:SetText(L("Select all, then press Ctrl+C to copy."))
    w.edit:SetText(ns.ExportAPL(DH))
    w.okBtn:SetText(L("Copy"))
    w.okBtn:SetScript("OnClick", function()
        w.edit:SetFocus()
        w.edit:HighlightText()
        DH:Print(L("APL exported - press Ctrl+C."))
    end)
    w:Show()
    w.edit:SetFocus()
    w.edit:HighlightText()
end

-- Fallbacks so a load order without Options.lua still works
if not DH.RefreshConfig then
    function DH:RefreshConfig() end
end

-- ============================================================================
-- BLIZZARD INTERFACE OPTIONS PANEL
-- Adds a RotationCore entry to Esc > Interface > AddOns so the addon is found
-- where players look for it. The panel itself only links to the real window.
-- ============================================================================
local blizzPanel
local function EnsureBlizzardPanel()
    if blizzPanel then return end
    if type(InterfaceOptions_AddCategory) ~= "function" then return end
    local p = CreateFrame("Frame", "RotationCoreInterfaceOptions",
        InterfaceOptionsFramePanelContainer)
    p.name = L("RotationCore")

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L("RotationCore"))

    local sub = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    sub:SetWidth(520)
    sub:SetJustifyH("LEFT")
    sub:SetText(L("Highlight-based rotation helper. All settings live in the RotationCore window."))

    local btn = CreateFrame("Button", "RotationCoreBlizzOpenBtn", p, "UIPanelButtonTemplate")
    btn:SetSize(220, 24)
    btn:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    btn:SetText(L("Open RotationCore settings"))
    btn:SetScript("OnClick", function()
        if DH.OpenOptions then DH:OpenOptions() end
    end)

    local note = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -14)
    note:SetText(L("You can also type /rc at any time."))

    InterfaceOptions_AddCategory(p)
    blizzPanel = p
end

local optReg = CreateFrame("Frame")
if optReg and optReg.RegisterEvent then
    optReg:RegisterEvent("PLAYER_LOGIN")
    optReg:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        EnsureBlizzardPanel()
    end)
end
if IsLoggedIn and IsLoggedIn() then EnsureBlizzardPanel() end
