-- Feedback.lua
-- One unobtrusive feedback prompt plus the options/help entry point.
--
-- Rules:
--   * at most one prompt per install;
--   * only out of combat, outside dungeons/raids/battlegrounds/arenas;
--   * never while dead or in combat lockdown;
--   * shown after roughly 3 hours of addon use or 5 boss kills.

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

local HOURS = 3
local BOSSES = 5
local SECONDS = HOURS * 3600

local function FeedbackState()
    if not DH.dbRoot then
        return nil
    end
    DH.dbRoot.global = DH.dbRoot.global or {}
    local st = DH.dbRoot.global.feedback
    if type(st) ~= "table" then
        st = { seconds = 0, bosses = 0, prompted = false, dismissed = false }
        DH.dbRoot.global.feedback = st
    end
    return st
end

function ns.FeedbackOnEnable()
    ns.feedbackSessionStart = (type(time) == "function" and time()) or 0
end

function ns.FeedbackOnLogout()
    local st = FeedbackState()
    if not st or not ns.feedbackSessionStart or type(time) ~= "function" then
        return
    end
    local now = time()
    if now > ns.feedbackSessionStart then
        st.seconds = (st.seconds or 0) + (now - ns.feedbackSessionStart)
    end
    ns.feedbackSessionStart = now
end

function ns.RegisterFeedbackBossKill()
    local st = FeedbackState()
    if not st then
        return
    end
    st.bosses = (st.bosses or 0) + 1
end

local function SafeContext()
    if ns.inCombat then
        return false
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end
    if type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player") then
        return false
    end
    if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then
        return false
    end

    if type(IsInInstance) == "function" then
        local inInstance, kind = IsInInstance()
        if inInstance and (kind == "party" or kind == "raid" or kind == "pvp" or kind == "arena") then
            return false
        end
    end

    if type(GetBattlefieldStatus) == "function" then
        for i = 1, 3 do
            local ok, status = pcall(GetBattlefieldStatus, i)
            if ok and status and status ~= "none" then
                return false
            end
        end
    end
    return true
end

function ns.MaybeShowFeedbackPrompt()
    local st = FeedbackState()
    if not st or st.prompted or st.dismissed then
        return false
    end
    if not SafeContext() then
        return false
    end

    local total = tonumber(st.seconds) or 0
    if ns.feedbackSessionStart and type(time) == "function" then
        total = total + math.max(0, time() - ns.feedbackSessionStart)
    end
    if total < SECONDS and (tonumber(st.bosses) or 0) < BOSSES then
        return false
    end

    st.prompted = true
    if StaticPopup_Show then
        StaticPopup_Show("ROTATIONCORE_FEEDBACK")
    end
    return true
end

function DH:OpenFeedback()
    local text = ns.BuildReportText and ns.BuildReportText() or ""
    local body = L("Tell us what worked and what did not. Include the report below so we can reproduce the issue.")
        .. "\n\n"
        .. text
    if ns.ShowTextWindow then
        ns.ShowTextWindow(L("RotationCore feedback"), body)
    end
    if ns.PrintGitHubIssue then
        ns.PrintGitHubIssue(text)
    end
end

-- The popup is created lazily, but the dialog definition can be registered at
-- file scope. It is not shown until MaybeShowFeedbackPrompt succeeds.
StaticPopupDialogs["ROTATIONCORE_FEEDBACK"] = {
    text = "Enjoying RotationCore? Your feedback helps make the rotations better. Send it only when you are out of combat.",
    button1 = "Send feedback",
    button2 = "Not now",
    OnAccept = function()
        if DH.OpenFeedback then
            DH:OpenFeedback()
        end
    end,
    OnCancel = function()
        local st = FeedbackState()
        if st then
            st.dismissed = true
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
