-- Diagnostics.lua
-- Rate-limited error reporting, copyable bug reports and the GitHub issue
-- helper. Split out of RotationCore.lua so the core stays focused on the
-- rotation engine.

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

local REPORT_COOLDOWN = 30
ns._lastReport = ns._lastReport or {}

-- Log every error, but only print one chat line per context every 30 seconds.
-- The full history still reaches /rc errors and the export window.
function ns.ReportError(context, err)
    local msg = tostring(context or "Error") .. ": " .. tostring(err)
    if ns.AddError then
        ns.AddError(msg)
    end
    local now = (type(GetTime) == "function" and GetTime()) or 0
    local key = tostring(context or "error")
    local last = ns._lastReport[key] or 0
    if now - last >= REPORT_COOLDOWN then
        ns._lastReport[key] = now
        if DH.Print then
            DH:Print(L("RotationCore error: ") .. msg)
        end
    end
end

-- ---------------------------------------------------------------------------
-- TEXT WINDOW
-- WoW 3.3.5a has no clipboard API, so reports open in a focused, multi-line
-- EditBox. The player can press Ctrl+A / Ctrl+C and paste the whole block.
-- ---------------------------------------------------------------------------

local textFrame, textEdit, textTitle

local function EnsureTextWindow()
    if textFrame then
        return textFrame
    end

    local f = CreateFrame("Frame", "RotationCoreTextExport", UIParent)
    f:SetSize(620, 430)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end

    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -16)
    t:SetJustifyH("LEFT")
    textTitle = t

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", "RotationCoreTextScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -46)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 18)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(548)
    edit:SetHeight(340)
    edit:SetScript("OnEscapePressed", function()
        f:Hide()
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    scroll:SetScrollChild(edit)
    textEdit = edit

    f:Hide()
    textFrame = f
    return f
end

function ns.ShowTextWindow(title, text)
    local f = EnsureTextWindow()
    textTitle:SetText(tostring(title or "RotationCore"))
    textEdit:SetText(tostring(text or ""))
    textEdit:SetWidth(548)
    textEdit:SetCursorPosition(0)
    f:Show()
    f:Raise()
    textEdit:SetFocus()
    textEdit:HighlightText()
end

-- ---------------------------------------------------------------------------
-- REPORT CONTENT
-- ---------------------------------------------------------------------------

local function Safe(fn, default)
    if type(fn) ~= "function" then
        return default
    end
    local ok, value = pcall(fn)
    if ok and value ~= nil then
        return value
    end
    return default
end

local function InstanceLine()
    if type(IsInInstance) ~= "function" then
        return "unknown"
    end
    local ok, inInstance, kind = pcall(IsInInstance)
    if not ok then
        return "unknown"
    end
    if not inInstance then
        return "open world"
    end
    return tostring(kind or "instance")
end

function ns.BuildReportText()
    local lines = {}
    local function add(s)
        lines[#lines + 1] = tostring(s or "")
    end

    add("RotationCore bug report")
    add("Version: " .. tostring(DH.Version or "?"))
    add("Interface: " .. tostring(DH.Interface or 30300))
    add("Locale: " .. tostring(Safe(GetLocale, "?")))
    add("Profile: " .. tostring(Safe(function()
        return DH:GetCurrentProfileName()
    end, "?")))
    add("Spec: " .. tostring(Safe(function()
        return DH:GetActiveSpec()
    end, "?")))
    local mode = Safe(function()
        return DH:GetActiveMode()
    end, nil)
    add("Mode: " .. tostring(mode and (mode.key or mode.name) or "?"))
    add("Instance: " .. InstanceLine())
    add("Group: " .. tostring(Safe(function()
        return (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())
    end, false)))
    add("In combat: " .. tostring(ns.inCombat and true or false))
    add("")

    local log = ns.errorLog or {}
    add("Recent errors (" .. #log .. "):")
    if #log == 0 then
        add("  none")
    else
        local first = math.max(1, #log - 9)
        for i = first, #log do
            local e = log[i]
            if type(e) == "table" then
                local count = (e.count and e.count > 1) and (" (x" .. e.count .. ")") or ""
                add("  " .. tostring(e.msg or "?") .. count)
            end
        end
    end
    return table.concat(lines, "\n")
end

function ns.ShowReport()
    local text = ns.BuildReportText()
    ns.ShowTextWindow(L("RotationCore report"), text)
    if ns.PrintGitHubIssue then
        ns.PrintGitHubIssue(text)
    end
end

function ns.ShowErrorExport()
    local log = ns.errorLog or {}
    local lines = { ns.BuildReportText(), "", "Full error log:" }
    if #log == 0 then
        lines[#lines + 1] = "  none"
    else
        for i = 1, #log do
            local e = log[i]
            if type(e) == "table" then
                local count = (e.count and e.count > 1) and (" (x" .. e.count .. ")") or ""
                lines[#lines + 1] = "  " .. tostring(e.msg or "?") .. count
            end
        end
    end
    ns.ShowTextWindow(L("RotationCore error export"), table.concat(lines, "\n"))
end

-- ---------------------------------------------------------------------------
-- GITHUB ISSUE LINK
-- Chirp/URL length is limited, so the body stays short. The full report is
-- available in the copy window if the link is not enough.
-- ---------------------------------------------------------------------------

function ns.URLEncode(s)
    return (
        tostring(s or ""):gsub("([^%w%-%._~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
    )
end

function ns.PrintGitHubIssue(report)
    local title = "RotationCore " .. tostring(DH.Version or "?") .. " report"
    local body = tostring(report or ns.BuildReportText() or "")
    if #body > 1200 then
        body = body:sub(1, 1200) .. "\n..."
    end
    local url = "https://github.com/Hijackery/RotationCore/issues/new?title="
        .. ns.URLEncode(title)
        .. "&body="
        .. ns.URLEncode(body)
    if DH.Print then
        DH:Print(L("Open a GitHub issue:") .. " |Hurl:" .. url .. "|h[" .. L("click here") .. "]|h")
    end
end
