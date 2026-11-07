-- OptionsIO.lua
-- Profile, boss-profile, layout and APL import/export windows. Split out of
-- Options.lua so the tab builders stay focused on settings widgets.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

local pendingImport = nil

local function L(s)
    local tbl = DH.L
    if tbl and type(s) == "string" then
        return tbl[s]
    end
    return s
end

local function ApplyImportedProfile(mode)
    local data = pendingImport
    pendingImport = nil
    if not data then
        return
    end
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
        OnAccept = function()
            ApplyImportedProfile("replace")
        end,
        OnCancel = function()
            ApplyImportedProfile("new")
        end,
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
            if ReloadUI then
                ReloadUI()
            end
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
    if profileTextWindow then
        return profileTextWindow
    end

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
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    w:SetBackdropColor(0, 0, 0, 0.9)
    w:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    if UISpecialFrames then
        table.insert(UISpecialFrames, "RotationCoreProfileTextWindow")
    end

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
        tile = true,
        tileSize = 8,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    sb:SetBackdropColor(0, 0, 0, 0.6)
    sb:EnableMouseWheel(true)
    sb:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll() - delta * 34
        local maxS = self:GetVerticalScrollRange() or 0
        if cur < 0 then
            cur = 0
        elseif cur > maxS then
            cur = maxS
        end
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
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
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
    closeBtn:SetScript("OnClick", function()
        w:Hide()
    end)

    w:Hide()
    profileTextWindow = w
    return w
end

function ns.ShowProfileExportWindow()
    if not DH.db then
        return
    end
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
    if not DH.db then
        return
    end
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
    if not DH.db then
        return
    end
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
    if not DH.db then
        return
    end
    local w = CreateProfileTextWindow()
    w.title:SetText(L("Import boss profiles"))
    w.hint:SetText(L("Paste text, then click Import."))
    w.edit:SetText("")
    w.okBtn:SetText(L("Import"))
    w.okBtn:SetScript("OnClick", function()
        local n = DH:ImportBossProfiles(w.edit:GetText())
        DH:Print(L("Boss profiles imported: ") .. n)
        if DH.NotifyOptions then
            DH:NotifyOptions()
        end
        w:Hide()
    end)
    w:Show()
    w.edit:SetFocus()
end

-- Prompt 3.4: display-layout export / import (safe text, separate from the
-- profile export; positions only).
function ns.ShowLayoutExportWindow()
    if not DH.db then
        return
    end
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
    if not DH.db then
        return
    end
    local w = CreateProfileTextWindow()
    w.title:SetText(L("Import layout"))
    w.hint:SetText(L("Paste text, then click Import."))
    w.edit:SetText("")
    w.okBtn:SetText(L("Import"))
    w.okBtn:SetScript("OnClick", function()
        local n = ns.ImportLayout and ns.ImportLayout(w.edit:GetText()) or 0
        DH:Print(L("Layout imported: ") .. n)
        if DH.NotifyOptions then
            DH:NotifyOptions()
        end
        w:Hide()
    end)
    w:Show()
    w.edit:SetFocus()
end

-- Improvement 6: custom APL import / export windows (reuse the safe text
-- window; the text is parsed by hand - no code is ever executed).
function ns.ShowAPLImportWindow()
    if not DH.db then
        return
    end
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
            if DH.NotifyOptions then
                DH:NotifyOptions()
            end
            w:Hide()
        else
            DH:Print(L("APL error: ") .. tostring(err))
        end
    end)
    w:Show()
    w.edit:SetFocus()
end

function ns.ShowAPLExportWindow()
    if not DH.db then
        return
    end
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
