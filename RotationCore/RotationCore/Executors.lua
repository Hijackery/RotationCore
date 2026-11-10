-- Executors.lua
-- Level-aware execute/finisher layer shared by every class rotation.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

ns.executors = ns.executors or {}

local function ActiveModeKey(self)
    local mode = self.GetActiveMode and self:GetActiveMode()
    return mode and mode.key or nil
end

local function TargetPct(sim)
    if type(sim) == "table" and tonumber(sim.target_pct) then
        return tonumber(sim.target_pct)
    end
    local st = DH.State
    return st and st.target and st.target.health and tonumber(st.target.health.pct) or nil
end

local function TargetHealth(sim)
    if type(sim) == "table" and tonumber(sim.target_health) then
        return tonumber(sim.target_health)
    end
    local st = DH.State
    return st and st.target and st.target.health and tonumber(st.target.health.current) or nil
end

function DH:RegisterExecutors(specKey, list)
    if type(specKey) ~= "string" or type(list) ~= "table" then
        return
    end
    ns.executors[specKey] = list
    local abilities = self.Class and self.Class.abilities
    for i = 1, #list do
        local def = list[i]
        local ability = abilities and def and def.key and abilities[def.key]
        if ability then
            ability.execute = true
            ability.executeBelow = def.below
        end
    end
end

local function AbilityDamage(self, key)
    local ability = self.Class and self.Class.abilities and self.Class.abilities[key]
    local id = ability and ability.id
    local stats = id and ns.skillStats and ns.skillStats[id]
    if stats and stats.cast and stats.cast > 0 and stats.damage and stats.damage > 0 then
        return stats.damage / stats.cast
    end

    -- Max-rank spell damage is only trustworthy at level 80. Below that the
    -- observed combat-log average is the only level-correct source.
    local level = (self.State and self.State.level) or 0
    if level < 80 then
        return nil
    end
    local dmg = self.GetSpellDamage and self:GetSpellDamage(key)
    if not dmg then
        return nil
    end
    local st = self.State
    local sp = (st and st.stat and st.stat.spell_power) or 0
    local ap = (st and st.stat and st.stat.attack_power) or 0
    local crit = (st and st.stat and st.stat.crit) or 0
    local base = ((dmg.min or 0) + (dmg.max or 0)) / 2
    local scale = dmg.ap and ap or sp
    local hit = base + (dmg.coeff or 0) * scale
    return hit * (1 + crit / 100)
end

function DH:EstimateAbilityDamage(key)
    return AbilityDamage(self, key)
end

function DH:ExecutorConditionsMet(sim, def)
    if type(def) ~= "table" or not def.key then
        return false
    end
    if self.IsAbilityKnown and not self:IsAbilityKnown(def.key) then
        return false
    end
    if def.setting and self.GetSetting and self:GetSetting(def.setting) == false then
        return false
    end
    if type(def.require) == "function" then
        local ok, allowed = pcall(def.require, sim, self)
        if not ok or not allowed then
            return false
        end
    end

    local proc = def.proc and type(sim) == "table" and sim[def.proc] == true
    local pct = TargetPct(sim)
    local below = pct ~= nil and pct <= (tonumber(def.below) or 20)
    local finish = false
    if def.finish then
        local hp = TargetHealth(sim)
        local dmg = AbilityDamage(self, def.key)
        if hp and dmg and dmg > 0 then
            finish = hp <= dmg * (tonumber(def.finish_margin) or 1.10)
        end
    end
    if def.kill_only then
        return finish == true
    end
    return below == true or finish == true or proc == true
end

function DH:PickExecutor(sim, specKey)
    specKey = specKey or ActiveModeKey(self)
    local list = specKey and ns.executors[specKey]
    if not list then
        return nil
    end
    local queued = type(sim) == "table" and type(sim._queued) == "table" and sim._queued or nil
    for i = 1, #list do
        local def = list[i]
        if not (queued and queued[def.key]) and self:ExecutorConditionsMet(sim, def) and DH:Ready(sim, def.key) then
            return def.key
        end
    end
    return nil
end

function DH:IsExecutorActive(sim, key, specKey)
    if type(key) ~= "string" then
        return false
    end
    local lists
    if specKey then
        lists = { ns.executors[specKey] }
    else
        lists = {}
        for _, list in pairs(ns.executors) do
            lists[#lists + 1] = list
        end
    end
    for i = 1, #lists do
        local list = lists[i]
        for j = 1, #(list or {}) do
            local def = list[j]
            if def.key == key and self:ExecutorConditionsMet(sim, def) then
                return true
            end
        end
    end
    return false
end
