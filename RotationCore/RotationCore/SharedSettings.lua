-- SharedSettings.lua
-- Shared settings API. Split out of RotationCore.lua.

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
-- SHARED SETTINGS API
-- Settings live either in the active spec table (db[mode.key]) or in the
-- shared db.common table. Missing fields return nil - callers use
-- `or <default>` so old profiles keep working (part 9 of the spec).
-- ============================================================================

-- Phase 3.3: are per-specialization setting overrides active?
function DH:IsSpecProfilesEnabled()
    return (self.db and self.db.common and self.db.common.spec_profiles_enabled == true) or false
end

-- Are the draggable windows locked? Single source of truth: frames_locked.
-- Default: movable (no /rc move needed).
function DH:WindowsLocked()
    return (self.GetSetting and self:GetSetting("frames_locked")) == true
end

function DH:GetSetting(key)
    if not self.db or key == nil then
        return nil
    end
    local mode = self.GetActiveMode and self:GetActiveMode()
    local mt = mode and self.db[mode.key]
    if type(mt) == "table" and mt[key] ~= nil then
        return mt[key]
    end
    -- Per-spec override wins over the shared common table
    if self:IsSpecProfilesEnabled() then
        local spec = self.GetActiveSpec and self:GetActiveSpec() or nil
        local profs = self.db.spec_profiles
        local sp = (spec and type(profs) == "table") and profs[spec] or nil
        if type(sp) == "table" and sp[key] ~= nil then
            return sp[key]
        end
    end
    if type(self.db.common) == "table" and self.db.common[key] ~= nil then
        return self.db.common[key]
    end
    return nil
end

local function SetSettingRaw(self, key, value)
    if not self.db or key == nil then
        return false
    end
    -- Bump a version token so UI caches (e.g. the glow animation) can refresh
    -- lazily instead of reading settings every frame.
    ns.glowCacheVersion = (ns.glowCacheVersion or 0) + 1
    -- The toggle itself always lives in the shared table
    if key == "spec_profiles_enabled" then
        if type(self.db.common) ~= "table" then
            self.db.common = {}
        end
        self.db.common[key] = value
        return true
    end

    local mode = self.GetActiveMode and self:GetActiveMode()
    local mt = mode and self.db[mode.key]
    if type(mt) == "table" and mt[key] ~= nil then
        mt[key] = value
        return true
    end
    -- Target the active spec's override table when enabled
    if self:IsSpecProfilesEnabled() then
        local spec = self.GetActiveSpec and self:GetActiveSpec() or nil
        if spec and spec ~= "" and spec ~= "unknown" then
            if type(self.db.spec_profiles) ~= "table" then
                self.db.spec_profiles = {}
            end
            local sp = self.db.spec_profiles[spec]
            if type(sp) ~= "table" then
                sp = {}
                self.db.spec_profiles[spec] = sp
            end
            sp[key] = value
            return true
        end
    end
    if type(self.db.common) ~= "table" then
        self.db.common = {}
    end
    self.db.common[key] = value
    return true
end

-- Public setter: mirrors SetSettingRaw and re-evaluates the update scheduler
-- when a scheduling-related setting changes.
function DH:SetSetting(key, value)
    local ok = SetSettingRaw(self, key, value)
    if ok and (key == "update_mode" or key == "poll_frequency") and self.SyncUpdateLoop then
        self:SyncUpdateLoop()
    end
    return ok
end

-- Shared UI palette (part 10). Every window reads its colors from here so the
-- whole addon switches together when the theme setting changes.
function DH:GetUITheme()
    local name = (self.GetSetting and self:GetSetting("theme")) or "class"
    -- 1) Explicit skin wins (ui_skin), keeping the optional skin feature.
    local skin = self.GetUISkin and self:GetUISkin()
    if skin and skin.theme and skin.name ~= "default" then
        local t = skin.theme
        return {
            backdrop = t.backdrop,
            border = t.border,
            title = t.title,
            accent = t.accent or { 1, 0.82, 0 },
            text = t.text or { 0.92, 0.92, 0.92 },
            bg = skin.bg or ns.DEFAULT_BG,
            edge = skin.edge or ns.DEFAULT_EDGE,
            edgeSize = skin.edgeSize or 16,
            tile = skin.tile ~= false,
            tileSize = skin.tileSize or 16,
            insets = skin.insets or { left = 4, right = 4, top = 4, bottom = 4 },
        }
    end
    -- 2) Otherwise use the window style resolved by the active UI shell.
    local style, shell
    if self.GetUIStyle then
        style, shell = self:GetUIStyle()
    else
        style = nil
        shell = "blizzard"
    end
    local t = (style and style.theme)
        or { backdrop = { 0.10, 0.10, 0.10, 0.88 }, border = { 0.85, 0.70, 0.45, 0.95 }, title = { 1, 0.90, 0.55 } }
    if shell == "elvui" and ns.SHELL_THEMES and ns.SHELL_THEMES.elvui then
        t = ns.SHELL_THEMES.elvui
    elseif shell == "bartender4" or shell == "dominos" then
        t = { backdrop = { 0.10, 0.10, 0.10, 0.88 }, border = { 0.85, 0.70, 0.45, 0.95 }, title = { 1, 0.90, 0.55 } }
    end
    -- 3) The legacy "theme" setting (dark/light/class/contrast) tints the window.
    local light = (name == "light")
    local function tinted(rgb)
        return {
            backdrop = { 0.06, 0.06, 0.07, 0.92 },
            border = { rgb[1], rgb[2], rgb[3], 1 },
            title = { rgb[1], rgb[2], rgb[3] },
            accent = { rgb[1], rgb[2], rgb[3] },
            text = { 0.92, 0.92, 0.92 },
        }
    end
    if name == "class" then
        local cr, cg, cb = self:GetClassColor()
        t = tinted({ cr, cg, cb })
    elseif name == "custom" then
        local c = (self.GetSetting and self:GetSetting("theme_custom_color")) or { 1, 0.82, 0 }
        t = tinted({ c[1] or 1, c[2] or 0.82, c[3] or 0 })
    elseif name == "contrast" then
        t = {
            backdrop = { 0, 0, 0, 0.96 },
            border = { 1, 1, 1, 1 },
            title = { 1, 1, 1 },
            accent = { 1, 0.85, 0.2 },
            text = { 1, 1, 1 },
        }
    elseif light then
        t = {
            backdrop = { 0.86, 0.84, 0.78, 0.97 },
            border = { 0.42, 0.35, 0.20, 0.95 },
            title = { 0.32, 0.24, 0.05 },
            accent = { 0.62, 0.42, 0.02 },
            text = { 0.12, 0.12, 0.12 },
        }
    end
    -- The light theme paints its own solid plate (WHITE8X8) so the light tint
    -- reads correctly instead of muddling the dark stone texture.
    local bg = (light and "Interface\\Buttons\\WHITE8X8") or (skin and skin.bg) or ns.DEFAULT_BG
    local edge = (light and "Interface\\Tooltips\\UI-Tooltip-Border") or (skin and skin.edge) or ns.DEFAULT_EDGE
    return {
        backdrop = t.backdrop,
        border = t.border,
        title = t.title,
        accent = t.accent or { 1, 0.82, 0 },
        text = t.text or { 0.92, 0.92, 0.92 },
        bg = bg,
        edge = edge,
        edgeSize = (light and 8) or (skin and skin.edgeSize) or 16,
        tile = light or not skin or skin.tile ~= false,
        tileSize = (skin and skin.tileSize) or 16,
        insets = (light and { left = 2, right = 2, top = 2, bottom = 2 })
            or (skin and skin.insets)
            or { left = 4, right = 4, top = 4, bottom = 4 },
        light = light,
    }
end

-- Nil-safe wrapper used by class rotations instead of calling sim:ready directly.
function DH:Ready(sim, key)
    return type(sim) == "table" and type(sim.ready) == "function" and sim:ready(key) == true
end

-- Central gate for every major cooldown recommended from getPriority.
-- Missing settings return nil and block (the defaults are merged into the
-- profile via MergeDefaults, so this only bites unregistered keys).
function DH:CanUseCooldown(sim, spellKey, settingKey)
    if type(sim) ~= "table" or type(sim.ready) ~= "function" then
        return false
    end
    -- phase-3 #1: a "simple" adaptive rotation keeps long cooldowns out of the
    -- recommendation queue.
    if self.GetRotationComplexity and self:GetRotationComplexity() == "simple" then
        local base = sim.baseCDs and sim.baseCDs[spellKey]
        if type(base) == "number" and base >= 60 then
            return false
        end
    end
    if settingKey and not self:GetSetting(settingKey) then
        return false
    end
    if not self:GetSetting("auto_cooldowns") then
        return false
    end
    -- cooldown_order "manual": cooldowns stay out of the recommendation queue
    if self:GetSetting("cooldown_order") == "manual" then
        return false
    end
    if not self:IsAbilityKnown(spellKey) then
        return false
    end
    if not sim:ready(spellKey) then
        return false
    end
    if sim.gcd_remains and sim.gcd_remains > 0.05 then
        return false
    end
    if sim.cast_remains and sim.cast_remains > 0.05 then
        return false
    end
    if self:IsSnoozed(spellKey) then
        return false
    end
    -- Не жать длинный кулдаун в конце боя (part 3.1 / 5.4)
    if self:GetSetting("hold_cd_at_end") and sim.ttd and sim.ttd < (self:GetSetting("cd_hold_ttd") or 30) then
        local base = sim.baseCDs and sim.baseCDs[spellKey]
        if base and base > 60 then
            return false
        end
    end
    return true
end

-- Time-to-die estimate for the active activity profile (raid/dungeon/solo/pvp)
function DH:GetTTD()
    if not self.db then
        return 300
    end
    local profile = self:GetSetting("activity_profile") or "raid"
    return self:GetSetting("ttd_" .. profile) or 300
end

-- Resolve target_mode against the sim's enemy count.
-- "single" / "cleave" / "aoe" are returned verbatim; "auto" picks single for
-- one enemy, the 2-3 target cleave band, or aoe at/above aoe_threshold.
-- ("auto_cleave" is accepted as a legacy alias for the same 3-way split.)
function DH:ResolveTargetMode(sim)
    local mode = self:GetSetting("target_mode") or "single"
    -- Improvement 5: optional phase-driven override (phase 2 -> aoe, 3 -> single)
    if self.GetSetting and self:GetSetting("timeline_auto_phase") and ns.GetPhaseTargetMode then
        local pm = ns.GetPhaseTargetMode()
        if pm then
            mode = pm
        end
    end
    local count = (type(sim) == "table" and sim.active_enemies) or (self.State and self.State.active_enemies) or 1
    if mode == "auto" or mode == "auto_cleave" then
        local aoeThreshold = self:GetSetting("aoe_threshold") or 4
        if count >= aoeThreshold then
            return "aoe"
        end
        local cleaveThreshold = self:GetSetting("cleave_threshold") or 2
        if count >= cleaveThreshold then
            return "cleave"
        end
        return "single"
    end
    return mode
end

-- True when the resolved mode is any multi-target mode (cleave or aoe).
-- Class rotations use this so a cleave simply reuses their multi-target list.
function DH:IsMultiTarget(sim)
    if not self.ResolveTargetMode then
        return false
    end
    local m = self:ResolveTargetMode(sim)
    return m == "aoe" or m == "cleave"
end

-- True when the resolved mode is specifically the 2-3 target cleave band.
function DH:IsCleave(sim)
    if not self.ResolveTargetMode then
        return false
    end
    return self:ResolveTargetMode(sim) == "cleave"
end

-- Explain why there is nothing to recommend right now (Phase 1.2).
-- Returns nil when a recommendation is expected (so the caller keeps the
-- normal UI), otherwise a short human-readable reason. Strings go through
-- DH.L so RU clients get a translation (phase 2.4 collects the keys).
function DH:GetIdleReason()
    local tbl = self.L
    local function T(s)
        if tbl then
            return tbl[s]
        end
        return s
    end

    if not self.db then
        return T("Settings not loaded")
    end
    if not self.db.enabled then
        return T("Addon disabled")
    end
    if self.db.paused then
        -- paused_text=false suppresses the "Paused" label (window just hides).
        if self:GetSetting("paused_text") == false then
            return nil
        end
        return T("Paused")
    end

    -- A cast/channel in progress: the next press may be blocked
    if UnitCastingInfo and UnitCastingInfo("player") then
        return T("Casting")
    end
    if UnitChannelInfo and UnitChannelInfo("player") then
        return T("Channeling")
    end

    local st = self.State
    if st and st.gcd_remains and st.gcd_remains > 0.05 then
        return T("Global cooldown")
    end

    if not UnitExists("target") then
        return T("No target")
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then
        return T("Target is dead")
    end
    if st and st.target and st.target.canAttack == false then
        return T("Target is not attackable")
    end
    if
        st
        and st.target
        and st.target.exists
        and st.target.inRange == false
        and not (self.Class and next(self.Class.meleeAbilities or {}))
    then
        return T("Target out of range")
    end

    local level = UnitLevel("player") or 0
    if level > 0 and level < 10 then
        return T("Level too low")
    end

    if st and st.mana and st.mana.max > 0 and st.mana.pct < 1 then
        return T("No mana")
    end

    return T("No recommendation")
end

-- Self-test: reports what the rotation would do right now without touching
-- keybinds or the action bars. /rc test rotation
function DH:RunRotationSelfTest()
    if self.UpdateState then
        self:UpdateState()
    end
    if self.UpdateRecommendations then
        self:UpdateRecommendations()
    end
    local recs = ns.recommendations or {}
    self:Print(L("--- Rotation self-test ---"))
    self:Print(
        L("Spec: ")
            .. tostring(self:GetActiveSpec())
            .. L(", build: ")
            .. (self.db.auto_mode and L("auto") or tostring(self.db.mode))
    )
    self:Print(
        L("Target: ")
            .. tostring(UnitExists("target"))
            .. L(", CanAttack: ")
            .. tostring(UnitCanAttack("player", "target"))
    )
    self:Print(L("Active enemies: ") .. tostring(self.State and self.State.active_enemies))
    if #recs > 0 then
        self:Print(L("Result: ") .. #recs .. L(" recommendation(s), top = ") .. tostring(recs[1].ability))
    else
        self:Print(L("Result: empty (reason: ") .. tostring(self:GetIdleReason()) .. ")")
    end
    return #recs
end
