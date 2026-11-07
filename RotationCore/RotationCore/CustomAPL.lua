-- CustomAPL.lua
-- Custom APL. Split out of RotationCore.lua.

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
-- IMPROVEMENT 6: CUSTOM APL (a small, player-friendly priority language)
-- ============================================================================
-- Format:
--   priority:
--   - Icy Veins if cooldown_ready and not buff_active
--   - Deep Freeze if target_has_debuff("Fingers of Frost")
--   - Ice Lance if buff_active("Fingers of Frost")
--   - Frostbolt
--
-- Conditions: cooldown_ready, buff_active(x), buff_remaining(x[, n]),
-- target_has_debuff(x), target_hp <op> n, player_hp <op> n, mana_pct <op> n,
-- combo_points <op> n, always. "and" combines clauses; "not" negates one.
-- Parsing is pure string work (never loadstring) and every evaluation is
-- pcall-guarded, so a broken APL can only ever produce no recommendations.

local function APLNormalize(s)
    if type(s) ~= "string" then
        return ""
    end
    s = s:lower()
    s = s:gsub("[%p%c]", " ")
    s = s:gsub("%s+", " ")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function APLKey(s)
    return (APLNormalize(s):gsub(" ", "_"))
end

-- Resolve a spell/ability name (key, EN name or localized name) to a class key.
local function APLResolveAbility(self, name)
    if not name or name == "" then
        return nil
    end
    local cls = self.Class and self.Class.abilities
    if type(cls) ~= "table" then
        return nil
    end
    local key = APLKey(name)
    if cls[key] then
        return key
    end
    local norm = APLNormalize(name)
    for k, a in pairs(cls) do
        if APLNormalize(k) == norm then
            return k
        end
        if a and a.name and APLNormalize(a.name) == norm then
            return k
        end
        if a and a.id and GetSpellInfo then
            local loc = GetSpellInfo(a.id)
            if loc and APLNormalize(loc) == norm then
                return k
            end
        end
    end
    return nil
end

-- Resolve an aura display name to a state buff/debuff key.
local function APLResolveAura(st, name, wantDebuff)
    if not st or not name or name == "" then
        return nil
    end
    local key = APLKey(name)
    local tbl = wantDebuff and st.debuff or st.buff
    if tbl and tbl[key] then
        return key
    end
    local list = wantDebuff and ns.registered.debuffs or ns.registered.buffs
    local norm = APLNormalize(name)
    if type(list) == "table" then
        for i = 1, #list do
            if APLNormalize(list[i]) == norm then
                return list[i]
            end
        end
    end
    -- Strict: target_has_debuff only matches debuffs and buff_active only
    -- matches buffs, so a player buff never satisfies a target-debuff test.
    return nil
end

local function APLParseCondition(token)
    token = token:gsub("^%s+", ""):gsub("%s+$", "")
    if token == "" then
        return nil
    end
    local cond = { negate = false }
    if token:match("^not%s+") then
        cond.negate = true
        token = token:gsub("^not%s+", "")
    end
    local name = token:match("^([%a_][%w_]*)")
    if not name then
        return nil
    end
    cond.name = name
    local rest = token:sub(#name + 1)
    local openParen = rest:find("%(")
    if openParen then
        local closeParen = rest:find("%)", openParen)
        if closeParen then
            local argsStr = rest:sub(openParen + 1, closeParen - 1)
            local args = {}
            for part in (argsStr .. ","):gmatch("(.-),") do
                local a = part:gsub("^%s+", ""):gsub("%s+$", "")
                a = a:gsub('^"(.*)"$', "%1")
                args[#args + 1] = a
            end
            cond.arg = args[1]
            cond.arg2 = args[2] and (tonumber(args[2]) or args[2]) or nil
            rest = rest:sub(closeParen + 1)
        end
    end
    local op, val = rest:match("^%s*(<=|>=|==|~=|<>|<|>)%s*(%-?%d+%.?%d*)")
    if op then
        cond.op = op
        cond.value = tonumber(val)
    end
    return cond
end

-- Parse text into rules. Returns rules, error (rules is always a table).
function ns.ParseAPL(text)
    local rules = {}
    if type(text) ~= "string" then
        return rules, "no text"
    end
    for raw in (text .. "\n"):gmatch("(.-)\n") do
        local line = raw:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if
            line ~= ""
            and not line:match("^#")
            and not line:match("^%-%-")
            and not line:match("^priority%s*:?%s*$")
            and not line:match("^actions%s*:?%s*$")
        then
            line = line:gsub("^[%-%*%+]%s*", "")
            local ability, condText = line:match("^(.-)%s+[Ii][Ff]%s+(.+)$")
            if not ability then
                ability = line
                condText = nil
            end
            ability = ability:gsub("^%s+", ""):gsub("%s+$", "")
            local rule = { ability = ability, conditions = {} }
            if condText then
                local normalized = condText:gsub("%s+[Aa][Nn][Dd]%s+", "\1")
                for clause in (normalized .. "\1"):gmatch("(.-)\1") do
                    local c = APLParseCondition(clause)
                    if c then
                        rule.conditions[#rule.conditions + 1] = c
                    end
                end
            end
            if ability ~= "" then
                rules[#rules + 1] = rule
            end
        end
    end
    return rules, nil
end

local function APLAuraActive(st, key)
    if not key then
        return false
    end
    local b = (st.buff and st.buff[key]) or (st.debuff and st.debuff[key])
    if not b then
        return false
    end
    local now = st.now or 0
    if b.expires and b.expires > 0 and b.expires <= now then
        return false
    end
    return true
end

local function APLEvalCondition(self, st, cond, abilityId)
    local name = cond.name
    local result
    if name == "always" then
        result = true
    elseif name == "cooldown_ready" then
        if abilityId and type(GetSpellCooldown) == "function" then
            local start, dur = GetSpellCooldown(abilityId)
            result = (not start) or not dur or dur == 0 or ((start + dur) - GetTime()) <= 0
        else
            result = true
        end
    elseif name == "buff_active" then
        result = APLAuraActive(st, APLResolveAura(st, cond.arg or "", false))
    elseif name == "debuff_active" then
        result = APLAuraActive(st, APLResolveAura(st, cond.arg or "", true))
    elseif name == "buff_remaining" then
        local key = APLResolveAura(st, cond.arg or "", false)
        local b = key and st.buff and st.buff[key]
        result = (b and b.expires and math.max(0, b.expires - (st.now or 0))) or 0
    elseif name == "target_has_debuff" then
        result = APLAuraActive(st, APLResolveAura(st, cond.arg or "", true))
    elseif name == "target_hp" then
        result = (st.target and st.target.health and st.target.health.pct) or 100
    elseif name == "player_hp" then
        result = (st.health and st.health.pct) or 100
    elseif name == "mana_pct" then
        result = (st.mana and st.mana.pct) or 100
    elseif name == "combo_points" then
        result = (st.combo_points and st.combo_points.current) or 0
    else
        result = false
    end

    if cond.op and type(result) == "number" and cond.value then
        local v = cond.value
        if cond.op == "<" then
            result = result < v
        elseif cond.op == "<=" then
            result = result <= v
        elseif cond.op == ">" then
            result = result > v
        elseif cond.op == ">=" then
            result = result >= v
        elseif cond.op == "==" then
            result = result == v
        else
            result = result ~= v
        end
    elseif type(result) == "number" then
        result = result > 0
    else
        result = result and true or false
    end

    if cond.negate then
        result = not result
    end
    return result
end

-- Evaluate the stored APL. Returns recs, valid. valid is false when there is
-- no APL to run, so the caller can fall back to the class rotation.
function ns.EvaluateAPL(self)
    local rules = self.GetSetting and self:GetSetting("custom_apl")
    if type(rules) ~= "table" or #rules == 0 then
        return {}, false
    end
    local st = self.State
    if not st then
        return {}, false
    end
    local maxRecs = tonumber(self:GetSetting("display_count")) or 3
    if maxRecs < 1 then
        maxRecs = 1
    end
    local cap = maxRecs + 2
    local recs = {}
    for i = 1, #rules do
        local rule = rules[i]
        local abilityKey = APLResolveAbility(self, rule.ability)
        local passes = true
        local conds = rule.conditions
        if conds then
            for j = 1, #conds do
                local ok = false
                pcall(function()
                    local id = abilityKey and self.Class.abilities[abilityKey] and self.Class.abilities[abilityKey].id
                        or nil
                    ok = APLEvalCondition(self, st, conds[j], id)
                end)
                if not ok then
                    passes = false
                    break
                end
            end
        end
        if passes and abilityKey then
            recs[#recs + 1] = {
                ability = abilityKey,
                priority = #recs + 1,
                text = rule.ability,
            }
            if #recs >= cap then
                break
            end
        end
    end
    return recs, true
end

-- Store parsed rules + the raw source. Returns rule count, error.
function ns.SetCustomAPL(self, text)
    local rules, err = ns.ParseAPL(text)
    if not rules or #rules == 0 then
        return 0, err or "empty"
    end
    self:SetSetting("custom_apl", rules)
    self:SetSetting("custom_apl_source", text or "")
    return #rules, nil
end

-- Export the current APL as text. Round-trips the stored source when present,
-- otherwise emits a starter template from the class ability list.
function ns.ExportAPL(self)
    local src = self.GetSetting and self:GetSetting("custom_apl_source")
    if type(src) == "string" and src ~= "" then
        return src
    end
    local cls = (self.Class and self.Class.abilities) or {}
    local keys = {}
    for k in pairs(cls) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local out = { "priority:" }
    for i = 1, #keys do
        local a = cls[keys[i]]
        out[#out + 1] = "- " .. tostring((a and a.name) or keys[i])
    end
    return table.concat(out, "\n")
end

-- A single-line shareable form of the APL (newlines become "\n").
function ns.ExportAPLShare(self)
    local src = ns.ExportAPL(self)
    local one = src:gsub("\r", ""):gsub("\n", "\\n")
    return "RCAPL1:" .. one
end

-- Decode a share string back to plain APL text.
function ns.DecodeAPLShare(text)
    if type(text) ~= "string" then
        return text
    end
    local body = text:match("^%s*RCAPL1:(.*)$")
    if not body then
        return text
    end
    return (body:gsub("\\n", "\n"))
end
