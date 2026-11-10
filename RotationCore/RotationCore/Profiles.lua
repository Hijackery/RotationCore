-- Profiles.lua
-- Settings and profiles. Split out of RotationCore.lua.

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
-- SETTINGS
-- ============================================================================

-- Core default settings (class-agnostic)
local coreDefaults = {
    enabled = true,
    paused = false, -- /rc pause: freeze recommendations but keep the addon on
    debug = false,
    show_debug_frame = false,
    -- Pick the build (arcane/fire/frost/...) from the player's talents
    auto_mode = true,
    display = {
        -- How many upcoming abilities are highlighted on the action bars.
        -- 1 = one at a time: the next ability lights up, after you press it
        -- the following one lights up.
        num_icons = 1,
        -- Glow border size relative to the action button
        glow_size = 1.5,
        -- Show the priority number (1/2/3) above each highlighted button
        show_numbers = false,
        -- Pulsing glow animation
        pulse = true,
        -- Only highlight abilities while in combat
        combat_only = false,
        -- MaxDps-style window showing the next ability icons
        show_spellframe = true,
        spellframe_scale = 1,
        -- How many icons the MaxDps-style window shows (independent of
        -- num_icons, which only controls the action-bar glow count)
        spellframe_icons = 3,
    },
    -- Position of the spell icon window (screen center offsets)
    spellFrame = { x = 0, y = -250 },

    -- Shared per-spec settings (part 1). Class modules register the SAME
    -- table (plus per-spec extras), so every class gets an identical
    -- options window; core keeps this copy as a fallback for profiles
    -- loaded before a class module registers.
    common = {
        menu_mode = "simple", -- "simple" / "advanced" options window
        dummy_ttd = 300,
        use_racial_cooldowns = true, -- offer racial cooldowns in the cooldown window
        enemy_count_enabled = true, -- show the enemy counter near the icon window
        resource_warning_enabled = true, -- warn before capping a resource
        dot_panel_enabled = false, -- optional DoT/debuff panel
        party_health_enabled = false, -- optional group health monitor
        party_health_position = { x = 250, y = -80 },
        heal_assist_enabled = false, -- healer assist window
        heal_assist_position = { x = -260, y = -120 },
        dot_panel_position = { x = 250, y = 80 },
        swing_timer_enabled = false, -- optional melee swing timer
        swing_timer_position = { x = 0, y = -330 },
        timeline_bars_enabled = true, -- draw bars in the timeline window
        auto_cooldowns = true,
        cooldown_order = "priority", -- "manual" skips cooldowns in the queue
        target_mode = "auto", -- "single" / "cleave" / "aoe" / "auto" (auto = 1/2-3/4+)
        activity_profile = "raid", -- selects which ttd_* applies
        ttd_raid = 300,
        ttd_dungeon = 60,
        ttd_solo = 15,
        ttd_pvp = 30,
        hold_cd_at_end = true,
        cd_hold_ttd = 30,
        aoe_threshold = 4, -- "auto" switches to AOE at this count
        cleave_threshold = 2, -- "auto" switches to cleave at this count
        update_mode = "events", -- "events" (event-driven) / "poll" (fixed-rate)
        poll_frequency = 5, -- Hz for the fallback poll / "poll" mode
        build_detect_mode = "talents_glyphs_stats", -- "talents" / "talents_glyphs" / "talents_glyphs_stats"
        -- Improvement 6: user-authored priority list (APL)
        custom_apl_enabled = false, -- use the parsed custom APL instead of the class rotation
        custom_apl = {}, -- parsed APL rules (see ns.ParseAPL)
        custom_apl_source = "", -- raw text the parsed rules came from
        use_glyphs = true,
        raid_buffs = true,
        display_count = 3, -- how many recs are shown
        sound_procs = false,
        sound_procs_file = "Sound\\Interface\\AlarmClockWarning3.wav",
        proc_flash = false,
        proc_flash_speed = 3.0,
        log_decisions = false,
        log_max_lines = 1000,
        icon_size = 36,
        icon_gap = 4,
        orientation = "horizontal", -- "horizontal" (row) / "vertical" (column)
        adaptive_queue = true, -- shorten the queue by estimated target HP
        glow_frequency = 1.0,
        glow_lines = 1,
        glow_thickness = 1.5,
        guide_marker = false,
        spellframe_font = "default",
        spellframe_font_size = 0,
        show_gcd_timer = true, -- show the global-cooldown sweep timer
        show_time = true, -- show the remaining-time text on icons
        show_background = true, -- draw the backdrop behind the queue window
        show_border = true, -- draw the border around the queue window
        show_title = true, -- show the window title text
        hide_out_of_combat = false, -- hide the queue window out of combat
        hide_no_target = false, -- hide the queue window with no target
        hide_when_idle = false, -- hide the queue window when nothing is recommended
        fade_when_idle = false, -- fade instead of hide when idle
        theme = "class", -- "class" / "custom" / "dark" / "light" / "contrast"
        theme_custom_color = { 1, 0.82, 0 }, -- accent tint for the "custom" theme
        show_resource_bar = false, -- reserved: options resource bar removed (kept for compatibility)
        paused_text = true, -- show a "paused" label when disabled
        glow_style = "pulse", -- pulse / static / flash / rainbow
        colorblind_mode = false, -- orange/blue/grey priority palette
        spellFrame_pos_per_spec = false,
        -- Phase 1 UX
        show_keybind = true, -- show the action-bar binding on each icon
        show_idle_reason = true, -- explain why nothing is recommended
        spellframe_combat_only = false, -- hide the icon window out of combat
        show_mode_indicator = true, -- S/A/Au target-mode indicator on the window title
        show_color_legend = true, -- priority color legend in the options window
        -- Phase 2 UX
        show_cooldowns_display = true, -- optional big-cooldowns window
        cooldowns_position = { x = -150, y = 0 },
        cooldowns_num_icons = 3, -- 2-3 icons
        cooldowns_min_cd = 60, -- only cooldowns this long or longer
        cooldowns_show_ready = true, -- include ready cooldowns (sorted first)
        cooldowns_hide_empty = false, -- hide the cooldowns window when nothing is ready
        cooldowns_scale = 1, -- size of the cooldowns window (resize grip / slider)
        show_interrupts_display = false, -- optional interrupt window
        interrupts_always_show = false, -- keep the interrupt window visible when idle
        interrupt_ready_sound = false, -- play a sound when the interrupt is ready again
        interrupts_position = { x = 170, y = -250 },
        interrupts_scale = 1, -- size of the interrupt window (resize grip)
        show_timeline_display = true, -- optional boss-timeline window (phase + timers)
        timeline_position = { x = 0, y = 200 },
        timeline_scale = 1, -- size of the timeline window
        -- Per-window opacity (config mode) and tint (auto = follow theme).
        opacity_primary = 1,
        opacity_cooldowns = 1,
        opacity_interrupts = 1,
        opacity_timeline = 1,
        tint_primary = "auto",
        tint_cooldowns = "auto",
        tint_interrupts = "auto",
        tint_timeline = "auto",
        -- Phase 2.2 / Phase 3
        show_tooltips = true, -- tooltips on options controls
        tooltip_delay = 0.3, -- seconds before the tooltip appears
        profile_export_enabled = true, -- show Export/Import in the Profiles tab
        spec_profiles_enabled = false, -- per-specialization settings
        -- Post-phase features
        auto_reload_on_talent_change = true, -- rebuild the rotation after talents change
        training_mode = false, -- ALT-SHIFT-L: recommend on a dummy out of combat
        training_chat_output = true, -- print the REC1 reason on change while training
        training_sound = false, -- play a sound on REC1 change while training
        heal_dps_mode = "auto", -- "auto" / "on" / "off": DPS rotation in healer specs
        pvp_mode_enabled = false, -- ALT-SHIFT-V: PvP priority branch
        pvp_burst_threshold = 50, -- burst when the target is below this HP %
        -- Post-phase features (prompt 2)
        boss_profiles_enabled = false, -- ENCOUNTER_START applies a stored boss profile
        boss_profiles = {}, -- [encounterID] = { override settings }
        stats_enabled = false, -- /rc stats: recommended/cast/missed per spell
        ideal_dps_enabled = false, -- /rc stats dps: compare against an ideal
        -- Prompt 3: colour palettes / animations / boss timeline / layouts
        color_palette = "default", -- default/protanopia/deuteranopia/tritanopia/high_contrast/custom
        animations_enabled = true, -- fade / crossfade transitions on the icon window
        animation_speed = 1.0, -- 0.5 - 2.0 (higher = faster)
        timeline_enabled = false, -- DBM / BigWigs boss-timeline hints
        timeline_show_burst = true, -- show the burst countdown text
        timeline_auto_phase = false, -- auto-switch rotation by boss phase
        timeline_burst_window = 15, -- seconds "before burst" that means Hold CD
        display_layout = "center", -- center / side / minimal / raid / custom
        -- v3.3.0 phase 2/3: coaching, adaptive rotation, learning stats
        dps_forecast_enabled = false, -- live DPS forecast above the icon window
        dps_forecast_show_actual = true, -- also show actual DPS + loss %
        dps_forecast_update_interval = 1.0,
        dps_forecast_position = "above_spellframe",
        dps_color = "auto", -- DPS forecast text colour (auto = default)
        class_pulse_enabled = true, -- colour indicator: how well you play
        class_pulse_position = "left_of_spellframe",
        pulse_color = "auto", -- class-pulse colour (auto = score based)
        exam_mode = false, -- no glow; measure accuracy
        exam_report_in_chat = true,
        mentor_mode = false, -- explain mistakes after N in a row
        mentor_error_threshold = 3,
        mentor_show_in_chat = true,
        adaptive_rotation = "auto", -- auto / simple / normal / complex
        ilvl_threshold_simple = 200,
        ilvl_threshold_complex = 245,
        learning_stats_enabled = true, -- persist per-fight learning sessions
        learning_stats_max_sessions = 100,
        -- v3.4.0 feature pack (12 improvements). All safe to toggle; values are
        -- merged into every profile by MigrationDefaults (no settings lost).
        battle_context_enabled = true, -- sim.battle_phase available to rotations
        phase_indicators = true, -- show the current phase on the icon window
        combat_forecast_enabled = false, -- "through Ns: <proc/cd> ready" lines
        forecast_window = 5, -- forecast horizon in seconds
        forecast_max_lines = 3, -- how many forecast lines to show
        group_awareness_enabled = true, -- scan party/raid for raid buffs
        -- NOTE: boss_profiles_enabled is declared once above (opt-in, default
        -- false). Do not redeclare it here - the last value in this table wins.
        boss_profile_autoload = true, -- apply the [boss][class][spec] profile automatically
        profile_advanced_ui = false, -- show advanced profile options (deep personalization)
        timeline_deep_enabled = true, -- BigWigs/DBM phase-message integration
        timeline_phase_auto = false, -- switch rotation on deep-phase messages
        timeline_phase_announce = false, -- print phase changes to chat
        wizard_window_size = { w = 780, h = 560 }, -- wizard window size
        wizard_require_all_answers = false, -- Next always enabled; every step is optional
        frames_movable_default = true, -- drag windows without /rc move
        frames_locked = false, -- /rc lock / option "Lock windows"
        spellframe_fixed_size = true, -- don't resize with the rec count
        spellframe_compact = false, -- icon-only window (no title/backdrop)
        bg_style = "default", -- default / matte
        ui_font = "default", -- unified font for all windows
        ui_font_large = false, -- larger/readable text mode
        ui_skin = "default", -- optional skin overlay (default = none)
        ui_opacity = 1, -- options window backdrop opacity (0.3 - 1)
        arena_mode = "auto", -- auto / 2v2 / 3v3 / 5v5
        auto_activity = true, -- auto-adjust activity (raid/dungeon/pvp/world)
    },
}

-- Single source of truth for the shared `common` defaults. Class addons
-- merge their extras onto this table instead of keeping a second copy.
ns.coreCommonDefaults = coreDefaults.common

-- Deep copy function for defaults
local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

-- Merge saved vars with defaults.
-- When `strict` is set (loading/importing saved data), a value whose type
-- disagrees with the default is treated as corrupt and replaced by the
-- default. Default-merging (strict off) never overrides a class value that
-- intentionally differs from the core default.
local function MergeDefaults(saved, default, strict)
    if type(default) ~= "table" then
        return saved or default
    end
    if type(saved) ~= "table" then
        saved = {}
    end

    for k, v in pairs(default) do
        if saved[k] == nil then
            saved[k] = DeepCopy(v)
        elseif type(v) == "table" then
            saved[k] = MergeDefaults(saved[k], v, strict)
        elseif strict and type(saved[k]) ~= type(v) then
            saved[k] = DeepCopy(v)
        end
    end
    return saved
end

-- Build full defaults by merging core + class-specific.
-- Class values win over core values for the same key (deep merge), so a
-- class-specific `common` (e.g. warlock aoe_threshold=2) overrides core.
local function BuildDefaults()
    local defaults = DeepCopy(coreDefaults)
    for k, v in pairs(ns.registered.defaults) do
        if type(v) == "table" and type(defaults[k]) == "table" then
            -- v (class) survives, core fills in only the missing keys
            defaults[k] = MergeDefaults(DeepCopy(v), defaults[k])
        else
            defaults[k] = DeepCopy(v)
        end
    end
    return defaults
end

-- ============================================================================
-- SAVED VARIABLES / PROFILES
-- Standard layout, same idea as most addons using saved variables:
--
--   RotationCoreDB = {
--       profiles    = { ["Default"] = { ...settings... }, ["Alt"] = {...} },
--       profileKeys = { ["Playername - Realmname"] = "Default" },
--       global      = { ...settings shared by every profile... },
--   }
--
-- DH.db always points at the ACTIVE profile table, so all code reading
-- DH.db.xxx keeps working unchanged.
--
-- IMPORTANT: the client loads the saved variables file AFTER all addon files
-- have been executed and BEFORE ADDON_LOADED fires. Nothing may touch
-- RotationCoreDB at file scope - only OnInitialize (ADDON_LOADED) reads it.
-- That was the reason settings were lost on restart in older versions.
-- ============================================================================

-- Saved-variable migration lives in Schema.lua (loaded after this file).
-- MigrateSaved is called from DoInitialize/OnInitialize, where ns.MigrateSaved
-- is guaranteed to exist.

local function GetProfileKey()
    local name = (UnitName and UnitName("player")) or "Unknown"
    local realm = (GetRealmName and GetRealmName()) or ""
    if realm ~= "" then
        return name .. " - " .. realm
    end
    return name
end

-- Load/refresh the active profile table (merges any new defaults into it)
function DH:LoadProfile(name)
    local root = self.dbRoot
    if not root then
        return nil
    end

    if not root.profiles[name] then
        root.profiles[name] = {}
    end

    self.db = MergeDefaults(root.profiles[name], BuildDefaults(), true)
    root.profiles[name] = self.db
    self.currentProfile = name
    root.profileKeys[self.profileKey] = name

    self:ApplyProfileDefaults()
    return self.db
end

-- Make sure the profile has a valid rotation mode selected
function DH:ApplyProfileDefaults()
    if not self.db then
        return
    end
    local modes = ns.registered.modes
    if not modes or #modes == 0 then
        return
    end

    local valid = false
    for _, mode in ipairs(modes) do
        if mode.key == self.db.mode then
            valid = true
            break
        end
    end
    if not valid then
        self.db.mode = modes[1].key
    end
end

-- Sorted list of profile names
function DH:GetProfileNames()
    local names = {}
    if self.dbRoot then
        for name in pairs(self.dbRoot.profiles) do
            if type(name) == "string" then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)
    return names
end

function DH:GetCurrentProfileName()
    return self.currentProfile or "Default"
end

-- Create a new profile. copyFrom = name to clone, or false for bare defaults
function DH:CreateProfile(name, copyFrom)
    if type(name) ~= "string" then
        return nil, "Enter a profile name"
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return nil, "Enter a profile name"
    end

    local root = self.dbRoot
    if not root then
        return nil, "Database not ready"
    end
    if root.profiles[name] then
        return nil, "Profile already exists"
    end

    local source = {}
    if copyFrom ~= false then
        local from = (type(copyFrom) == "string" and root.profiles[copyFrom])
            or root.profiles[self:GetCurrentProfileName()]
        if from then
            source = DeepCopy(from)
        end
    end
    root.profiles[name] = MergeDefaults(source, BuildDefaults(), true)
    return name
end

-- Apply decoded profile data from an import.
-- mode = "replace" writes over the current profile, "new" makes a fresh one.
function DH:ImportProfile(data, mode, name)
    if type(data) ~= "table" then
        return nil, "Invalid profile data"
    end
    local root = self.dbRoot
    if not root then
        return nil, "Database not ready"
    end

    if mode == "new" then
        name = (type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "")) or ""
        if name == "" then
            name = "Imported"
        end
        local base = name
        local i = 2
        while root.profiles[name] do
            name = base .. " " .. i
            i = i + 1
        end
        root.profiles[name] = MergeDefaults(data, BuildDefaults(), true)
        self:LoadProfile(name)
        self:RefreshAfterProfileChange()
        return name
    end

    name = name or self:GetCurrentProfileName()
    root.profiles[name] = MergeDefaults(data, BuildDefaults(), true)
    self:LoadProfile(name)
    self:RefreshAfterProfileChange()
    return name
end

-- Copy one profile's settings over another profile
function DH:CopyProfile(fromName, toName)
    local root = self.dbRoot
    if not root or not root.profiles[fromName] then
        return false, "Source profile not found"
    end
    if fromName == toName then
        return false, "Same profile"
    end

    root.profiles[toName] = MergeDefaults(DeepCopy(root.profiles[fromName]), BuildDefaults(), true)
    if toName == self.currentProfile then
        self.db = root.profiles[toName]
        self:ApplyProfileDefaults()
        self:RefreshAfterProfileChange()
    end
    return true
end

-- ============================================================================
-- PHASE 3.2: PROFILE IMPORT / EXPORT
-- Plain-text serialization with a safe table-literal parser (no loadstring).
-- ============================================================================

local function IsIdentifier(k)
    return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
end

local function SerializeValue(v, indent, seen)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            return "0"
        end
        return tostring(v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        if seen[v] then
            return "nil"
        end
        seen[v] = true
        local pad = string.rep("  ", indent)
        local pad2 = string.rep("  ", indent + 1)

        local n = #v
        local isArray = true
        for k in pairs(v) do
            if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
                isArray = false
                break
            end
        end

        local parts = {}
        if isArray and n > 0 then
            for i = 1, n do
                parts[#parts + 1] = pad2 .. SerializeValue(v[i], indent + 1, seen)
            end
        else
            local keys = {}
            for k in pairs(v) do
                keys[#keys + 1] = k
            end
            table.sort(keys, function(a, b)
                if type(a) == type(b) then
                    return tostring(a) < tostring(b)
                end
                return type(a) == "string"
            end)
            for _, k in ipairs(keys) do
                local val = v[k]
                local vt = type(val)
                if vt == "number" or vt == "string" or vt == "boolean" or vt == "table" then
                    local key
                    if IsIdentifier(k) then
                        key = k
                    elseif type(k) == "string" then
                        key = "[" .. string.format("%q", k) .. "]"
                    elseif type(k) == "number" then
                        key = "[" .. tostring(k) .. "]"
                    end
                    if key then
                        parts[#parts + 1] = pad2 .. key .. " = " .. SerializeValue(val, indent + 1, seen)
                    end
                end
            end
        end

        seen[v] = nil
        if #parts == 0 then
            return "{}"
        end
        return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. pad .. "}"
    end
    return "nil"
end

-- Serialize the active (or named) profile to a portable text blob
function DH:EncodeProfile(name)
    name = name or self:GetCurrentProfileName()
    local root = self.dbRoot
    if not root or not root.profiles[name] then
        return nil, "Profile not found"
    end
    local body = SerializeValue(root.profiles[name], 0, {})
    local stamp = "?"
    if type(date) == "function" then
        stamp = date("%Y-%m-%d %H:%M:%S")
    end
    local lines = {
        "-- RotationCore Profile Export",
        "-- Version: " .. tostring(self.Version or "?"),
        "-- Date: " .. stamp,
        "-- Profile: " .. name,
        "return " .. body,
    }
    return table.concat(lines, "\n")
end

local function DecodeParse(str)
    local pos = 1
    local len = #str

    local function skip()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            elseif c == "-" and str:sub(pos + 1, pos + 1) == "-" then
                local nl = str:find("\n", pos, true)
                if nl then
                    pos = nl + 1
                else
                    pos = len + 1
                end
            else
                break
            end
        end
    end

    local parseValue

    local function parseString()
        local quote = str:sub(pos, pos)
        pos = pos + 1
        local out = {}
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                if n == "n" then
                    out[#out + 1] = "\n"
                elseif n == "t" then
                    out[#out + 1] = "\t"
                elseif n == "r" then
                    out[#out + 1] = "\r"
                elseif n == "a" then
                    out[#out + 1] = "\a"
                elseif n == "b" then
                    out[#out + 1] = "\b"
                elseif n == "f" then
                    out[#out + 1] = "\f"
                elseif n == "v" then
                    out[#out + 1] = "\v"
                elseif n == "\\" then
                    out[#out + 1] = "\\"
                elseif n == '"' then
                    out[#out + 1] = '"'
                elseif n == "'" then
                    out[#out + 1] = "'"
                elseif n == "\n" then
                    out[#out + 1] = "\n"
                elseif n:match("%d") then
                    local num = n
                    for _ = 1, 2 do
                        local d = str:sub(pos + 1 + #num, pos + 1 + #num)
                        if d:match("%d") then
                            num = num .. d
                        else
                            break
                        end
                    end
                    out[#out + 1] = string.char(tonumber(num) or 63)
                    pos = pos + #num - 1
                else
                    out[#out + 1] = n
                end
                pos = pos + 2
            elseif c == quote then
                pos = pos + 1
                return table.concat(out)
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        error("unterminated string")
    end

    local function parseTable()
        pos = pos + 1 -- consume "{"
        local t = {}
        while true do
            skip()
            local c = str:sub(pos, pos)
            if c == "}" then
                pos = pos + 1
                break
            elseif c == "" then
                error("unterminated table")
            elseif c == "," or c == ";" then
                pos = pos + 1
            elseif c == "[" then
                pos = pos + 1
                local key = parseValue()
                skip()
                if str:sub(pos, pos) ~= "]" then
                    error("expected ]")
                end
                pos = pos + 1
                skip()
                if str:sub(pos, pos) ~= "=" then
                    error("expected =")
                end
                pos = pos + 1
                t[key] = parseValue()
            else
                local save = pos
                local name = str:match("^([%a_][%w_]*)", pos)
                if name then
                    local p = pos + #name
                    while p <= len and str:sub(p, p):match("%s") do
                        p = p + 1
                    end
                    if str:sub(p, p) == "=" then
                        pos = p + 1
                        t[name] = parseValue()
                    else
                        pos = save
                        t[#t + 1] = parseValue()
                    end
                else
                    t[#t + 1] = parseValue()
                end
            end
        end
        return t
    end

    parseValue = function()
        skip()
        local c = str:sub(pos, pos)
        if c == "{" then
            return parseTable()
        end
        if c == '"' or c == "'" then
            return parseString()
        end
        local rest = str:sub(pos)
        local num = rest:match("^%-?%d+%.?%d*[eE]?[%-+]?%d*")
        if num and num:match("^%-?%d") then
            pos = pos + #num
            return tonumber(num)
        end
        if rest:match("^true") then
            pos = pos + 4
            return true
        end
        if rest:match("^false") then
            pos = pos + 5
            return false
        end
        if rest:match("^nil") then
            pos = pos + 3
            return nil
        end
        error("unexpected token at " .. pos)
    end

    skip()
    if str:sub(pos, pos + 5) == "return" then
        pos = pos + 6
    end
    return parseValue()
end

-- Parse a text blob into a profile table (never executes input as code)
function DH:DecodeProfile(str)
    if type(str) ~= "string" then
        return nil, "Empty input"
    end
    str = str:gsub("^\239\187\191", "") -- strip UTF-8 BOM
    if str:match("^%s*$") then
        return nil, "Empty input"
    end

    local ok, result = pcall(DecodeParse, str)
    if not ok then
        return nil, "Parse error: " .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "Not a profile table"
    end
    return result
end

-- Delete a profile (never the last one left)
function DH:DeleteProfile(name)
    local root = self.dbRoot
    if not root or not root.profiles[name] then
        return false, "Profile not found"
    end

    local count = 0
    for _ in pairs(root.profiles) do
        count = count + 1
    end
    if count <= 1 then
        return false, "Cannot delete the last profile"
    end

    root.profiles[name] = nil

    -- Any character pointing at the deleted profile falls back to a live one:
    -- prefer "Default", otherwise any remaining profile.
    local fallback = root.profiles["Default"] and "Default" or nil
    if not fallback then
        fallback = next(root.profiles)
    end
    for key, profile in pairs(root.profileKeys) do
        if profile == name then
            root.profileKeys[key] = fallback
        end
    end

    if self.currentProfile == name then
        self:LoadProfile(fallback)
        self:RefreshAfterProfileChange()
    end
    return true
end

-- Switch to another profile
function DH:SetProfile(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local root = self.dbRoot
    if not root then
        return false
    end

    if not root.profiles[name] then
        root.profiles[name] = {}
    end

    self:LoadProfile(name)
    self:RefreshAfterProfileChange()
    self:Print(L("Profile: ") .. name)
    return true
end

-- Reset the current profile back to defaults
function DH:ResetProfile(name)
    local root = self.dbRoot
    name = name or self:GetCurrentProfileName()
    if not root or not root.profiles[name] then
        return false
    end

    root.profiles[name] = {}
    if name == self.currentProfile then
        self:LoadProfile(name)
    end
    self:RefreshAfterProfileChange()
    return true
end

-- Let the config/UI layers react to a profile switch
function DH:RefreshAfterProfileChange()
    if self.RefreshConfig then
        self:RefreshConfig()
    end
    if self.UpdateRecommendations then
        self:UpdateRecommendations()
    end
end

-- Debug print (console when debug mode is on).
function DH:Debug(msg, ...)
    local text = string.format(msg, ...)
    if self.db and self.db.debug then
        print("|cFF00FF00RotationCore:|r " .. text)
    end
end

-- Print message
function DH:Print(msg)
    print("|cFF00FF00RotationCore:|r " .. msg)
end

-- Helpers also used by the core module.
ns.DeepCopy = DeepCopy
ns.MergeDefaults = MergeDefaults
ns.BuildDefaults = BuildDefaults
ns.GetProfileKey = GetProfileKey
