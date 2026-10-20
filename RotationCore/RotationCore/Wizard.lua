-- Wizard.lua
-- Comprehensive setup wizard (v3.4.0-hotfix5): 10 steps, one answer per
-- question, validation, progress bar, Blizzard-styled. After the last step a
-- beginner should not need the options window. Re-runnable via /rc wizard.

local DH = RotationCore
if not DH then return end

local ns = DH.ns

local function L(s)
    if type(s) ~= "string" then return s end
    local tbl = rawget(DH, "L")
    if tbl and tbl[s] then return tbl[s] end
    return s
end

ns.Wizard = ns.Wizard or {}
local W = ns.Wizard

W.step = 1
W.answers = {}

local function GetModeOptions()
    local out = {}
    local modes = ns.registered and ns.registered.modes or {}
    for _, mode in ipairs(modes) do
        out[#out + 1] = { value = mode.key, text = mode.name or mode.key }
    end
    return out
end

local function ActiveMode()
    if DH.db and DH.db.mode then return DH.db.mode end
    local d = DH.GetActiveMode and DH:GetActiveMode()
    return d and d.key or nil
end

local YES_NO = {
    { value = "yes", text = "Yes" },
    { value = "no", text = "No" },
}
local function YN(v) return (v and v ~= "no") and "yes" or "no" end

local ROLE_OPTS = {
    { value = "dps", text = "DPS", desc = "Maximum damage output; the rotation is tuned for your damage." },
    { value = "tank", text = "Tank", desc = "Threat and survivability come first." },
    { value = "healer", text = "Healer", desc = "For classes with a healing specialization." },
}
local ACTIVITY_OPTS = {
    { value = "auto", text = "Auto", desc = "Detects the content (raid / dungeon / arena / world) and adjusts on the fly." },
    { value = "raid", text = "Raid", desc = "Long boss fights (~5 min). Keeps long cooldowns for burst windows." },
    { value = "dungeon", text = "Dungeon", desc = "Short fights (~1-3 min). Uses cooldowns more freely." },
    { value = "solo", text = "Solo", desc = "Fast kills (~15 s). Favours instant damage, skips long setup." },
    { value = "pvp", text = "PvP", desc = "Short burst windows; holds cooldowns for kills." },
    { value = "arena", text = "Arena", desc = "2v2/3v3/5v5 burst play; very short windows." },
}
local TARGET_OPTS = {
    { value = "single", text = "Single target", desc = "Always the single-target rotation." },
    { value = "cleave", text = "Cleave", desc = "The main target plus nearby adds." },
    { value = "aoe", text = "AOE", desc = "Always area damage." },
    { value = "auto", text = "Auto", desc = "Switches by the number of enemies around you." },
}
local CD_OPTS = {
    { value = "all", text = "Yes, all", desc = "Cooldowns woven into the normal priority." },
    { value = "none", text = "No", desc = "You press cooldowns yourself." },
    { value = "major", text = "Major only", desc = "Long (30 s+) cooldowns first when ready." },
}
local ICON_OPTS = {
    { value = 2, text = "2", desc = "Show the two next actions." },
    { value = 3, text = "3", desc = "Show the three next actions." },
    { value = 4, text = "4", desc = "Show the four next actions." },
    { value = 5, text = "5", desc = "Show the five next actions." },
}
local ICONSIZE_OPTS = {
    { value = 28, text = "Small", desc = "Compact icons." },
    { value = 36, text = "Medium", desc = "Default icon size." },
    { value = 44, text = "Large", desc = "Bigger icons, easier to read." },
}
local COMPLEXITY_OPTS = {
    { value = "auto", text = "Auto (by ilvl)", desc = "Picks the level of detail from your average item level." },
    { value = "simple", text = "Simple", desc = "Only the most important abilities." },
    { value = "normal", text = "Normal", desc = "Balanced; good for most players." },
    { value = "complex", text = "Complex", desc = "Every situational ability in the priority." },
}

local MENU_OPTS = {
    { value = "simple", text = "Simple", desc = "Only the main tabs; fewer settings." },
    { value = "advanced", text = "Advanced", desc = "All tabs and fine-tuning options." },
}
local HEAL_DPS_OPTS = {
    { value = "auto", text = "Auto (solo only)", desc = "Use the DPS rotation only when playing solo." },
    { value = "on", text = "Always", desc = "Always borrow the DPS rotation while healing." },
    { value = "off", text = "Off", desc = "Never use the DPS rotation." },
}
local function IsAdvancedCtx()
    local m = W.answers["menu@1"] or (DH.GetSetting and DH:GetSetting("menu_mode")) or "simple"
    return m == "advanced"
end
local function IsHealerCtx()
    return (ns.IsHealerClass and ns.IsHealerClass()) and true or false
end

local STEPS = {
    [1] = { id = "welcome", title = "Welcome to RotationCore!",
        text = "Set up the rotation, targets, displays and cooldowns in a few "
            .. "short questions. Everything is saved to the current profile - you "
            .. "will not need to open the settings after this.",
        checkbox = { id = "welcome", label = "Show the wizard on the next launch" } },
    [2] = { id = "menu", title = "Menu style",
        text = "How much of the addon do you want to see?",
        groups = { { question = "Menu mode", options = MENU_OPTS } } },
    [3] = { id = "spec", title = "Class and specialization",
        text = "Everything correct?",
        info = true,
        groups = { { question = "Choose a specialization", options = {} } } },
    [4] = { id = "role", title = "Your role",
        text = "What do you play on this character?",
        groups = { { question = "Role", options = ROLE_OPTS } } },
    [5] = { id = "healer", title = "Healing",
        text = "Healer helpers for your spec.",
        ctx = IsHealerCtx,
        groups = {
            { question = "Suggest a heal for the lowest-health member?", options = YES_NO },
            { question = "Show the group health monitor?", options = YES_NO },
            { question = "Heal-spec DPS rotation?", options = HEAL_DPS_OPTS },
        } },
    [6] = { id = "activity", title = "Main activity",
        text = "Where do you spend most of your time?",
        groups = { { question = "Activity", options = ACTIVITY_OPTS } } },
    [7] = { id = "target", title = "Target mode",
        text = "How should the rotation pick its targets?",
        groups = { { question = "Target mode", options = TARGET_OPTS } } },
    [8] = { id = "display", title = "Recommendation display",
        text = "How should the queue look?",
        groups = {
            { question = "How many icons?", options = ICON_OPTS },
            { question = "Icon size?", options = ICONSIZE_OPTS },
            { question = "Orientation?", options = {
                { value = "horizontal", text = "Row" }, { value = "vertical", text = "Column" } } },
            { question = "Compact window (icons only, no frame)?", options = YES_NO },
        } },
    [9] = { id = "display2", title = "Queue details",
        text = "A few extras for the recommendation queue.",
        ctx = IsAdvancedCtx,
        info2 = "GCD (global cooldown) is the shared ~1.5 s wait after pressing most instant abilities before the next one can be used. Casts with a cast bar are not limited by it, and haste shortens it (down to about 1.0 s). The GCD timer on the queue shows how long is left, so you know the exact moment the next ability is ready.",
        groups = {
            { question = "Show the key binding?", options = YES_NO },
            { question = "Show the GCD timer?", options = YES_NO },
            { question = "Show priority numbers (1/2/3)?", options = YES_NO },
        } },
    [10] = { id = "cd", title = "Cooldowns and procs",
        text = "A few behaviour choices for cooldowns and alerts.",
        groups = {
            { question = "Should the rotation recommend cooldowns?", options = CD_OPTS },
            { question = "Play a sound when a proc lands?", options = YES_NO },
            { question = "Flash the buttons on a proc?", options = YES_NO },
            { question = "Enable training mode?", options = YES_NO },
        } },
    [11] = { id = "extra", title = "Advanced behaviour",
        text = "A few extras that usually work best on their defaults.",
        ctx = IsAdvancedCtx,
        groups = {
            { question = "Rotation complexity", options = COMPLEXITY_OPTS },
            { question = "Battle phase indicator?", options = YES_NO },
            { question = "Raid-buff awareness?", options = YES_NO },
            { question = "Combat forecast?", options = YES_NO },
        } },
    [12] = { id = "extras", title = "Extras",
        text = "Optional helpers - you can change all of these later.",
        ctx = IsAdvancedCtx,
        groups = {
            { question = "Enemy counter near the queue?", options = YES_NO },
            { question = "Resource-cap warnings?", options = YES_NO },
            { question = "DoT / debuff panel?", options = YES_NO },
            { question = "Melee swing timer?", options = YES_NO },
            { question = "Timeline progress bars?", options = YES_NO },
            { question = "Colourblind-friendly palette?", options = YES_NO },
        } },
    [13] = { id = "done", title = "Done",
        text = "Everything looks good. Here is what will be applied.",
        summary = true,
        checkbox = { id = "test", label = "Run a highlight test now" } },
}
W.totalSteps = #STEPS

local required = { role = true, activity = true, target = true, display = true,
                   display2 = true, cd = true, extra = true, spec = true }

-- One answer per question: key "<stepId>@<groupIndex>".
local function GKey(stepId, gi)
    return stepId .. "@" .. gi
end

local function PrefillAnswers()
    local a = W.answers
    local function def(k, v)
        if a[k] == nil and v ~= nil then a[k] = v end
    end
    def("spec@1", ActiveMode())
    def("role@1", (DH.GetSetting and DH:GetSetting("role")))
    def("activity@1", (DH.GetSetting and DH:GetSetting("auto_activity")) ~= false and "auto"
        or ((DH.GetSetting and DH:GetSetting("activity_profile")) or "raid"))
    def("target@1", (DH.GetSetting and DH:GetSetting("target_mode")) or "auto")
    def("display@1", (DH.GetSetting and DH:GetSetting("num_icons")) or 3)
    def("display@2", (DH.GetSetting and DH:GetSetting("icon_size")) or 36)
    def("display@3", (DH.GetSetting and DH:GetSetting("orientation")) or "horizontal")
    def("display2@1", YN((DH.GetSetting and DH:GetSetting("show_keybind")) ~= false))
    def("display2@2", YN((DH.GetSetting and DH:GetSetting("show_gcd_timer")) ~= false))
    def("display2@3", YN((DH.GetSetting and DH:GetSetting("show_priority_numbers")) or
        (DH.GetSetting and DH:GetSetting("show_numbers")) or false))
    local autoCd = (DH.GetSetting and DH:GetSetting("auto_cooldowns")) ~= false
    local order = (DH.GetSetting and DH:GetSetting("cooldown_order")) or "priority"
    def("cd@1", autoCd and (order == "burst" and "major" or "all") or "none")
    def("cd@2", YN((DH.GetSetting and DH:GetSetting("sound_procs")) == true))
    def("cd@3", YN((DH.GetSetting and DH:GetSetting("proc_flash")) == true))
    def("cd@4", YN((DH.GetSetting and DH:GetSetting("training_mode")) == true))
    def("extra@1", (DH.GetSetting and DH:GetSetting("adaptive_rotation")) or "auto")
    def("extra@2", YN((DH.GetSetting and DH:GetSetting("phase_indicators")) ~= false))
    def("extra@3", YN((DH.GetSetting and DH:GetSetting("group_awareness_enabled")) ~= false))
    def("extra@4", YN((DH.GetSetting and DH:GetSetting("combat_forecast_enabled")) == true))
    def("menu@1", (DH.GetSetting and DH:GetSetting("menu_mode")) or "simple")
    def("healer@1", YN((DH.GetSetting and DH:GetSetting("heal_assist_enabled")) == true))
    def("healer@2", YN((DH.GetSetting and DH:GetSetting("party_health_enabled")) == true))
    def("healer@3", (DH.GetSetting and DH:GetSetting("heal_dps_mode")) or "auto")
    def("display@4", YN((DH.GetSetting and DH:GetSetting("spellframe_compact")) == true))
    def("extras@1", YN((DH.GetSetting and DH:GetSetting("enemy_count_enabled")) ~= false))
    def("extras@2", YN((DH.GetSetting and DH:GetSetting("resource_warning_enabled")) ~= false))
    def("extras@3", YN((DH.GetSetting and DH:GetSetting("dot_panel_enabled")) == true))
    def("extras@4", YN((DH.GetSetting and DH:GetSetting("swing_timer_enabled")) == true))
    def("extras@5", YN((DH.GetSetting and DH:GetSetting("timeline_bars_enabled")) ~= false))
    def("extras@6", YN((DH.GetSetting and DH:GetSetting("colorblind_mode")) == true))
end

local function ApplyAnswers()
    local a = W.answers
    if not DH.db then return end
    local function v(stepId, gi) return a[GKey(stepId, gi)] end

    local spec = v("spec", 1)
    if spec and spec ~= ActiveMode() then DH:SetMode(spec) end
    if v("role", 1) then DH:SetSetting("role", v("role", 1)) end
    if v("activity", 1) then
        if v("activity", 1) == "auto" then
            DH:SetSetting("auto_activity", true)
            if DH.RefreshAutoActivity then DH:RefreshAutoActivity() end
        else
            DH:SetSetting("auto_activity", false)
            DH:SetSetting("activity_profile", v("activity", 1))
        end
    end
    if v("target", 1) then DH:SetSetting("target_mode", v("target", 1)) end

    local icons = tonumber(v("display", 1)) or 3
    if v("display", 1) then
        DH:SetSetting("num_icons", icons)
        if DH.db and DH.db.display then DH.db.display.spellframe_icons = icons end
    end
    if v("display", 2) then DH:SetSetting("icon_size", tonumber(v("display", 2))) end
    if v("display", 3) then DH:SetSetting("orientation", v("display", 3)) end
    if v("display2", 1) then DH:SetSetting("show_keybind", v("display2", 1) == "yes") end
    if v("display2", 2) then DH:SetSetting("show_gcd_timer", v("display2", 2) == "yes") end
    if v("display2", 3) then
        local on = v("display2", 3) == "yes"
        DH:SetSetting("show_priority_numbers", on)
        if DH.db and DH.db.display then DH.db.display.show_numbers = on end
    end

    if v("cd", 1) then
        if v("cd", 1) == "none" then
            DH:SetSetting("auto_cooldowns", false)
        else
            DH:SetSetting("auto_cooldowns", true)
            DH:SetSetting("cooldown_order", (v("cd", 1) == "major") and "burst" or "priority")
        end
    end
    if v("cd", 2) then DH:SetSetting("sound_procs", v("cd", 2) == "yes") end
    if v("cd", 3) then DH:SetSetting("proc_flash", v("cd", 3) == "yes") end
    if v("cd", 4) then DH:SetSetting("training_mode", v("cd", 4) == "yes") end

    if v("extra", 1) then DH:SetSetting("adaptive_rotation", v("extra", 1)) end
    if v("extra", 2) then DH:SetSetting("phase_indicators", v("extra", 2) == "yes") end
    if v("extra", 3) then DH:SetSetting("group_awareness_enabled", v("extra", 3) == "yes") end
    if v("extra", 4) then DH:SetSetting("combat_forecast_enabled", v("extra", 4) == "yes") end

    if v("menu", 1) then DH:SetSetting("menu_mode", v("menu", 1)) end
    if v("healer", 1) then DH:SetSetting("heal_assist_enabled", v("healer", 1) == "yes") end
    if v("healer", 2) then DH:SetSetting("party_health_enabled", v("healer", 2) == "yes") end
    if v("healer", 3) then DH:SetSetting("heal_dps_mode", v("healer", 3)) end
    if v("display", 4) then DH:SetSetting("spellframe_compact", v("display", 4) == "yes") end
    if v("extras", 1) then DH:SetSetting("enemy_count_enabled", v("extras", 1) == "yes") end
    if v("extras", 2) then DH:SetSetting("resource_warning_enabled", v("extras", 2) == "yes") end
    if v("extras", 3) then DH:SetSetting("dot_panel_enabled", v("extras", 3) == "yes") end
    if v("extras", 4) then DH:SetSetting("swing_timer_enabled", v("extras", 4) == "yes") end
    if v("extras", 5) then DH:SetSetting("timeline_bars_enabled", v("extras", 5) == "yes") end
    if v("extras", 6) then DH:SetSetting("colorblind_mode", v("extras", 6) == "yes") end

    if a["welcome"] == "yes" and DH.db then DH.db.wizardShown = false end
    if a["test"] == "yes" and ns.ShowTestGlow then ns.ShowTestGlow() end

    if DH.ApplyShellStyle then DH:ApplyShellStyle() end
    if DH.NotifyOptions then DH:NotifyOptions() end
    if DH.UpdateUI then DH:UpdateUI() end
    if DH.Print then DH:Print(L("Setup Wizard: settings saved.")) end
end

local function PlayerInfoLines()
    local _, cls = UnitClass("player")
    local spec = DH.GetActiveSpec and DH:GetActiveSpec() or nil
    if not spec and DH.GetActiveMode then
        local m = DH:GetActiveMode()
        spec = m and m.name
    end
    local level = UnitLevel and UnitLevel("player") or nil
    local ilvl = DH.GetItemLevel and DH:GetItemLevel() or nil
    return string.format("Class: %s | Spec: %s | Level: %s | iLvl: %s",
        tostring(cls or "?"), tostring(spec or "?"),
        tostring(level or "?"), tostring(ilvl or "?"))
end

local function SummaryLines()
    local a = W.answers
    local function v(stepId, gi) return a[GKey(stepId, gi)] end
    local cdTxt = "Yes, all"
    if v("cd", 1) == "none" then cdTxt = "No"
    elseif v("cd", 1) == "major" then cdTxt = "Major only" end
    return {
        string.format("Spec: %s", tostring(v("spec", 1) or "?")),
        string.format("Role: %s | Activity: %s", tostring(v("role", 1) or "?"),
            tostring(v("activity", 1) or "?")),
        string.format("Target mode: %s", tostring(v("target", 1) or "?")),
        string.format("Display: %s icons, %s, size %s", tostring(v("display", 1) or "?"),
            tostring(v("display", 3) or "?"), tostring(v("display", 2) or "?")),
        string.format("Cooldowns: %s | Proc sound: %s", cdTxt, tostring(v("cd", 2) or "?")),
        string.format("Complexity: %s", tostring(v("extra", 1) or "?")),
        string.format("Menu: %s | Compact window: %s", tostring(v("menu", 1) or "?"),
            tostring(v("display", 4) or "?")),
    }
end

local frame
local titleFs, textFs, progressFs, info2Fs
local checkBox
local groupRows = {}
local optionButtons = {}
local infoFs, summaryFs, msgFs
local backButton, nextButton, cancelButton, skipButton, openAdvancedButton, startOverButton

local function SetButtonText(btn, text)
    if not btn then return end
    text = L(text)
    local fs
    local name = btn.GetName and btn:GetName()
    if name then fs = _G[name .. "Text"] end
    if not fs and btn.GetFontString then fs = btn:GetFontString() end
    if fs and fs.SetText then fs:SetText(text) elseif btn.SetText then btn:SetText(text) end
end

local function SetCheckboxLabel(cb, text)
    local name = cb.GetName and cb:GetName()
    local fs = name and _G[name .. "Text"]
    if fs and fs.SetText then fs:SetText(L(text)) end
end

local function SelFunc(step, gi, value)
    return W.answers[GKey(step.id, gi)] == value
end

local function ValidateStep()
    local step = STEPS[W.step]
    if not step or not step.groups then return true end
    if (DH.GetSetting and DH:GetSetting("wizard_require_all_answers")) == false then return true end
    if not required[step.id] then return true end
    for gi = 1, #(step.groups or {}) do
        if W.answers[GKey(step.id, gi)] == nil then return false end
    end
    return true
end

local function RebuildBody()
    local step = STEPS[W.step]
    for _, r in ipairs(groupRows) do r:Hide() end
    for _, b in ipairs(optionButtons) do b:Hide() end
    if infoFs then infoFs:Hide() end
    if info2Fs then info2Fs:Hide() end
    if summaryFs then summaryFs:Hide() end
    if checkBox then checkBox:Hide() end

    if titleFs then titleFs:SetText(L(step.title)) end
    if textFs then textFs:SetText(L(step.text)) end
    if progressFs then progressFs:SetText(string.format("%d / %d", W.step, W.totalSteps)) end
    if frame.segs then
        local cr, cg, cb = 1, 0.82, 0
        if DH.GetClassColor then cr, cg, cb = DH:GetClassColor() end
        local fw = (frame and frame:GetWidth()) or 700
        local total = fw - 64
        local gap = 4
        local n = #frame.segs
        local sw = math.max(6, (total - (n - 1) * gap) / n)
        local reached = math.ceil(W.step / W.totalSteps * n)
        for i = 1, n do
            local t = frame.segs[i]
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", frame, "TOPLEFT", 22 + (i - 1) * (sw + gap), -34)
            t:SetSize(sw, 8)
            if i <= reached then
                t:SetVertexColor(cr, cg, cb, 1)
            else
                t:SetVertexColor(0.22, 0.22, 0.22, 0.95)
            end
        end
    end

    local cy = -108

    if step.info then
        if not infoFs then
            infoFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            infoFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, 0)
            infoFs:SetJustifyH("LEFT")
            infoFs:SetTextColor(0.6, 0.9, 0.6)
        end
        infoFs:SetText(PlayerInfoLines())
        infoFs:ClearAllPoints()
        infoFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, cy)
        infoFs:Show()
        cy = cy - (infoFs:GetStringHeight() or 14) - 8
    end
    if step.info2 then
        if not info2Fs then
            info2Fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            info2Fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, 0)
            info2Fs:SetJustifyH("LEFT")
            info2Fs:SetWidth((frame and frame:GetWidth() or 700) - 52)
            info2Fs:SetTextColor(0.65, 0.65, 0.65)
        end
        info2Fs:SetText(L(step.info2))
        info2Fs:ClearAllPoints()
        info2Fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, cy)
        info2Fs:Show()
        cy = cy - (info2Fs:GetStringHeight() or 14) - 10
    end

    if step.summary then
        if not summaryFs then
            summaryFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            summaryFs:SetJustifyH("LEFT")
            summaryFs:SetWidth((frame and frame:GetWidth() or 700) - 52)
            summaryFs:SetTextColor(0.85, 0.85, 0.85)
        end
        local buff = {}
        local lines = SummaryLines()
        for i, line in ipairs(lines) do
            buff[#buff + 1] = ((i == 1) and ("|cFFFFD100" .. line .. "|r")) or ("  " .. line)
        end
        summaryFs:SetText(table.concat(buff, "\n"))
        summaryFs:ClearAllPoints()
        summaryFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, cy)
        summaryFs:Show()
        cy = cy - 26 - 17 * #lines
    else
        local slot = 0
        local groups = step.groups or {}
        for gi, g in ipairs(groups) do
            if g.question and #(g.options or {}) > 0 then
                local q = groupRows[gi]
                if not q then
                    q = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    groupRows[gi] = q
                end
                q:ClearAllPoints()
                q:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, cy)
                q:SetText(L(g.question))
                q:Show()
                cy = cy - 22
                local n = #g.options
                -- 2 options (Yes/No, single choice) sit side by side in two
                -- columns; 3+ use a 3-wide grid. One-column stacking made the
                -- Extras step overflow the window.
                local nCols
                if n >= 3 then nCols = 3 elseif n == 2 then nCols = 2 else nCols = 1 end
                nCols = math.min(nCols, n)
                local bw = 210
                local total = nCols * bw + (nCols - 1) * 12
                local ww = (frame and frame:GetWidth()) or w
                local bx = 26 + math.max(0, (ww - 26 - total) / 2)
                local rowsNeeded = math.ceil(n / nCols)
                for oi = 1, n do
                    slot = slot + 1
                    local b = optionButtons[slot]
                    if not b then
                        b = CreateFrame("Button", "RotationCoreWizardOpt" .. slot, frame, "UIPanelButtonTemplate")
                        b:SetScript("OnEnter", function(self)
                            if not GameTooltip then return end
                            local st = STEPS[W.step]
                            local gr = st and st.groups and st.groups[gi]
                            local opt = gr and gr.options and gr.options[oi]
                            -- Options without a description (Yes/No buttons, sizes)
                            -- get no tooltip at all - only the name was shown anyway.
                            if not opt or not opt.desc then return end
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetText(L(opt.text), 1, 1, 1)
                            GameTooltip:AddLine(L(opt.desc), 0.78, 0.78, 0.78, true)
                            GameTooltip:Show()
                        end)
                        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                        optionButtons[slot] = b
                    end
                    local opt = g.options[oi]
                    local col = (oi - 1) % nCols
                    local row = math.floor((oi - 1) / nCols)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", frame, "TOPLEFT", bx + col * (bw + 12), cy - row * 28)
                    b:SetSize(bw, 26)
                    local sel = SelFunc(step, gi, opt.value)
                    SetButtonText(b, (sel and ("|cFFFFD100> " .. L(opt.text) .. "|r") or L(opt.text)))
                    b:SetScript("OnClick", function()
                        W.answers[GKey(step.id, gi)] = opt.value
                        RebuildBody()
                    end)
                    b:Show()
                end
                cy = cy - rowsNeeded * 28 - 6
            end
        end
    end

    if step.checkbox then
        SetCheckboxLabel(checkBox, step.checkbox.label)
        checkBox:SetChecked(W.answers[step.checkbox.id] == "yes")
        checkBox:ClearAllPoints()
        checkBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, cy - 6)
        checkBox:Show()
    end
end

local function StepVisible(step)
    if not step then return false end
    if not step.ctx then return true end
    local ok, res = pcall(step.ctx)
    return (ok and res) and true or false
end
local function NextVisible(i, dir)
    local j = i + dir
    while j >= 1 and j <= #STEPS do
        if StepVisible(STEPS[j]) then return j end
        j = j + dir
    end
    return nil
end

local function UpdateFooter()
    local ok = ValidateStep()
    local nxt = NextVisible(W.step, 1)
    if backButton then
        SetButtonText(backButton, "Back")
        if NextVisible(W.step, -1) then backButton:Show() else backButton:Hide() end
    end
    if nextButton then
        SetButtonText(nextButton, nxt and "Next" or "Finish")
        if ok then nextButton:Enable() else nextButton:Disable() end
        nextButton:Show()
    end
    if skipButton then
        if nxt then skipButton:Show() else skipButton:Hide() end
    end
    if openAdvancedButton then
        if not nxt then openAdvancedButton:Show() else openAdvancedButton:Hide() end
    end
    if startOverButton then
        if not nxt then startOverButton:Show() else startOverButton:Hide() end
    end
    if msgFs then msgFs:SetText("") end
    if not ok and msgFs then msgFs:SetText(L("Answer every question first.")) end
end

local function UpdateStep()
    W.totalSteps = #STEPS
    -- The spec list only exists once the class modules have registered their
    -- modes (they load after this file), so (re)build it on every show/step.
    local specGroup
    for _, st in ipairs(STEPS) do
        if st.id == "spec" and st.groups and st.groups[1] then specGroup = st.groups[1]; break end
    end
    if specGroup then specGroup.options = GetModeOptions() end
    PrefillAnswers()
    RebuildBody()
    UpdateFooter()
end

local function EnsureFrameRaw()
    if frame then return frame end

    local size = (DH.GetSetting and DH:GetSetting("wizard_window_size")) or nil
    local w = (size and size.w) or 780
    local h = (size and size.h) or 560

    frame = CreateFrame("Frame", "RotationCoreWizard", UIParent)
    frame:SetSize(w, h)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    local th = (DH.GetUITheme and DH:GetUITheme()) or { backdrop = { 0, 0, 0, 0.95 }, border = { 0.4, 0.4, 0.4 }, title = { 1, 0.9, 0.5 } }
    frame:SetBackdropColor(th.backdrop[1], th.backdrop[2], th.backdrop[3], 0.92)
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3]) end
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    -- Resizable: drag the corner grip or scroll the wheel. The 7:5 aspect ratio
    -- is preserved and the size is persisted (wizard_window_size).
    local baseW, baseH = w, h
    local function ApplyWizardSize(nw, nh)
        nw = math.max(520, math.min(1200, nw))
        nh = math.max(360, math.min(900, nh))
        frame:SetSize(nw, nh)
        if DH.SetSetting then
            DH:SetSetting("wizard_window_size", { w = math.floor(nw + 0.5), h = math.floor(nh + 0.5) })
        end
        if RebuildBody then RebuildBody() end
        if UpdateStep then UpdateStep() end
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    local drag
    local function GripUpdate()
        if not drag then return end
        local x, y = GetCursorPosition()
        local s = UIParent:GetScale() or 1
        x, y = x / s, y / s
        -- Screen Y grows upward: dragging the bottom-right grip DOWN must grow
        -- the window, hence the minus sign on the vertical delta.
        local scale = math.max((drag.w + (x - drag.x)) / baseW, (drag.h - (y - drag.y)) / baseH)
        scale = math.max(0.55, math.min(1.9, scale))
        ApplyWizardSize(baseW * scale, baseH * scale)
    end
    grip:SetScript("OnMouseDown", function()
        local x, y = GetCursorPosition()
        local s = UIParent:GetScale() or 1
        drag = { x = x / s, y = y / s, w = frame:GetWidth(), h = frame:GetHeight() }
        grip:SetScript("OnUpdate", GripUpdate)
    end)
    grip:SetScript("OnMouseUp", function()
        drag = nil
        grip:SetScript("OnUpdate", nil)
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local scl = delta > 0 and 1.08 or 0.92
        ApplyWizardSize(frame:GetWidth() * scl, frame:GetHeight() * scl)
    end)

    titleFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -16)
    titleFs:SetTextColor(th.title[1], th.title[2], th.title[3])
    frame.title = titleFs
    if ns.ApplyWindowChrome then ns.ApplyWindowChrome(frame) end

    progressFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressFs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -18)
    progressFs:SetTextColor(0.7, 0.7, 0.7)

    local track = frame:CreateTexture(nil, "ARTWORK")
    track:SetHeight(8)
    track:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -34)
    track:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -42, -34)
    track:SetTexture(0.1, 0.1, 0.1, 0.9)

    -- Segmented progress: one cell per step (class-coloured when reached).
    local SEG = 10
    frame.segs = {}
    for i = 1, SEG do
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetHeight(8)
        t:SetTexture(1, 1, 1)
        t:SetVertexColor(0.22, 0.22, 0.22, 0.95)
        frame.segs[i] = t
    end

    textFs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    textFs:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -54)
    textFs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -22, -54)
    textFs:SetJustifyH("LEFT")
    textFs:SetTextColor(0.92, 0.92, 0.92)
    textFs:SetWordWrap(true)

    checkBox = CreateFrame("CheckButton", "RotationCoreWizardCheck", frame, "UICheckButtonTemplate")
    checkBox:SetScript("OnClick", function(self)
        local step = STEPS[W.step]
        if not (step and step.checkbox) then return end
        W.answers[step.checkbox.id] = self:GetChecked() and "yes" or "no"
    end)

    local close = CreateFrame("Button", "RotationCoreWizardClose", frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Bottom bar: one chain right-to-left so buttons can never overlap,
    -- regardless of which of them are hidden for the current step.
    local bw, gap = 110, 8

    nextButton = CreateFrame("Button", "RotationCoreWizardNext", frame, "UIPanelButtonTemplate")
    nextButton:SetSize(bw, 26)
    nextButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 16)
    SetButtonText(nextButton, "Next")
    nextButton:SetScript("OnClick", function()
        local j = NextVisible(W.step, 1)
        if j then W.step = j; UpdateStep() else W.Finish() end
    end)

    backButton = CreateFrame("Button", "RotationCoreWizardBack", frame, "UIPanelButtonTemplate")
    backButton:SetSize(bw, 26)
    backButton:SetPoint("RIGHT", nextButton, "LEFT", -gap, 0)
    SetButtonText(backButton, "Back")
    backButton:SetScript("OnClick", function()
        local j = NextVisible(W.step, -1)
        if j then W.step = j; UpdateStep() end
    end)

    skipButton = CreateFrame("Button", "RotationCoreWizardSkip", frame, "UIPanelButtonTemplate")
    skipButton:SetSize(bw, 26)
    skipButton:SetPoint("RIGHT", backButton, "LEFT", -gap, 0)
    SetButtonText(skipButton, "Skip")
    skipButton:SetScript("OnClick", function()
        local j = #STEPS
        while j >= 1 and not StepVisible(STEPS[j]) do j = j - 1 end
        if j > 0 then W.step = j; UpdateStep() end
    end)

    cancelButton = CreateFrame("Button", "RotationCoreWizardCancel", frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(bw, 26)
    cancelButton:SetPoint("RIGHT", skipButton, "LEFT", -gap, 0)
    SetButtonText(cancelButton, "Cancel")
    cancelButton:SetScript("OnClick", function() frame:Hide() end)

    openAdvancedButton = CreateFrame("Button", "RotationCoreWizardOpenAdvanced", frame, "UIPanelButtonTemplate")
    openAdvancedButton:SetSize(190, 26)
    openAdvancedButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 48)
    SetButtonText(openAdvancedButton, "Open advanced settings")
    openAdvancedButton:SetScript("OnClick", function()
        frame:Hide()
        if DH.OpenOptionsTab then DH:OpenOptionsTab("advanced") elseif DH.OpenOptions then DH:OpenOptions() end
    end)

    startOverButton = CreateFrame("Button", "RotationCoreWizardRestart", frame, "UIPanelButtonTemplate")
    startOverButton:SetSize(140, 26)
    startOverButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 22, 48)
    SetButtonText(startOverButton, "Start over")
    startOverButton:SetScript("OnClick", function()
        for k in pairs(W.answers) do W.answers[k] = nil end
        W.step = 1
        PrefillAnswers()
        UpdateStep()
    end)

    msgFs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgFs:SetPoint("CENTER", frame, "CENTER", 0, 12)
    msgFs:SetTextColor(0.9, 0.2, 0.2)

    return frame
end

local function EnsureFrame()
    if frame then return frame end
    local ok, err = pcall(EnsureFrameRaw)
    if not ok then
        frame = nil
        error(tostring(err), 0)
    end
    return frame
end

function W.Show()
    PrefillAnswers()
    EnsureFrame()
    local th = (DH.GetUITheme and DH:GetUITheme()) or { backdrop = { 0, 0, 0, 0.95 }, border = { 0.4, 0.4, 0.4 }, title = { 1, 0.9, 0.5 } }
    if frame.SetBackdropColor then frame:SetBackdropColor(th.backdrop[1], th.backdrop[2], th.backdrop[3], 0.92) end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3]) end
    if titleFs then titleFs:SetTextColor(th.title[1], th.title[2], th.title[3]) end
    W.step = 1
    UpdateStep()
    frame:Show()
    frame:Raise()
end

function W.Hide()
    if frame then frame:Hide() end
end

function W.GoTo(step)
    W.step = math.max(1, math.min(W.totalSteps, step or 1))
    if frame and frame:IsShown() then UpdateStep() end
end

function W.Answer(id, value)
    W.answers[id] = value
    if frame and frame:IsShown() then UpdateStep() end
end

function W.Finish()
    ApplyAnswers()
    if frame then frame:Hide() end
end

W.EnsureFrame = EnsureFrame
W.RebuildBody = RebuildBody
W.UpdateStep = UpdateStep