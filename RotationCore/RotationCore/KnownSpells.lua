-- KnownSpells.lua
-- Learned abilities. Split out of RotationCore.lua.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

-- ============================================================================
-- LEARNED ABILITIES (level / talent filtering)
-- The rotation must only offer abilities the player has actually learned.
-- A level 20 mage has no Frostbolt rank he never trained, no talent abilities
-- he has no points for, so those can never be recommended.
--
-- IsSpellKnown(spellID) exists in 3.3.5a. The result is cached and the cache
-- is dropped whenever the spell book, talents or level change.
-- ============================================================================

ns.knownSpells = nil -- { [spellId] = bool }, nil = needs a rebuild
ns.knownByName = nil -- { [localized name] = known spell id }, nil = rebuild

-- Drop the cache (spell book / talents / level changed)
function DH:InvalidateKnownSpells()
    ns.knownSpells = {}
    ns.knownByName = nil
    ns.resolvedId = {}
    ns._gcdSpellResolved = nil
    ns.knownSpellsVersion = (ns.knownSpellsVersion or 0) + 1
end

-- Scan the spell book for the spells the player has actually learned and map
-- every spell name to its current-rank id.
--
-- Abilities are registered with their MAX-rank ids (Frostbolt 42842, ...).
-- A character who has not trained the max rank has IsSpellKnown(42842) == false,
-- so without this map every ranked ability would be filtered out as "unknown"
-- and the queue would fall back to single-rank cooldowns only. 3.3.5a has no
-- "known by name" API, so the spell book is the only source of truth.
local function BuildKnownByName()
    -- Guard every spell book call: private 3.3.5a servers do not all ship the
    -- same helpers (GetSpellBookItemInfo is missing on some). Wrap the whole
    -- scan so a missing/broken API can never abort the rotation.
    local ok, map = pcall(function()
        local out = {}
        if type(GetNumSpellTabs) ~= "function" or type(GetSpellTabInfo) ~= "function" then
            return out
        end
        local bookType = BOOKTYPE_SPELL or "spell"
        for tab = 1, (tonumber(GetNumSpellTabs()) or 0) do
            local _, _, offset, numSpells = GetSpellTabInfo(tab)
            if offset and numSpells then
                for i = offset + 1, offset + numSpells do
                    local name, id
                    if type(GetSpellBookItemName) == "function" then
                        name = GetSpellBookItemName(i, bookType)
                    end
                    if type(GetSpellBookItemInfo) == "function" then
                        local _, spellId = GetSpellBookItemInfo(i, bookType)
                        if type(spellId) == "number" then
                            id = spellId
                        end
                    end
                    if not id and type(GetSpellLink) == "function" then
                        local link = GetSpellLink(i, bookType)
                        if type(link) == "string" then
                            local lid = tonumber(link:match("spell:(%d+)"))
                            local lname = link:match("%[(.-)%]")
                            if not name then
                                name = lname
                            end
                            -- trust the link id only when it agrees with the name
                            if lid and (not lname or not name or name == lname) then
                                id = lid
                            end
                        end
                    end
                    if name and name ~= "" then
                        out[name] = id or true -- id preferred, name alone is enough
                    end
                end
            end
        end
        return out
    end)
    if ok and type(map) == "table" then
        return map
    end
    return {}
end

-- Is a single spell id known to the player?
function DH:IsSpellKnownId(spellId)
    if not spellId then
        return true
    end
    if not IsSpellKnown then
        return true
    end -- old client: never filter

    local cache = ns.knownSpells
    if not cache then
        cache = {}
        ns.knownSpells = cache
    end

    local known = cache[spellId]
    if known == nil then
        known = IsSpellKnown(spellId) and true or false
        if not known and GetSpellInfo then
            -- Registered id is a higher rank than the player currently knows
            -- (or no rank at all): accept it if any rank of the same spell is
            -- in the spell book.
            local name = GetSpellInfo(spellId)
            if name then
                if not ns.knownByName then
                    ns.knownByName = BuildKnownByName()
                end
                if ns.knownByName[name] then
                    known = true
                end
            end
        end
        cache[spellId] = known
    end
    return known
end

-- The spell id the player actually knows for this ability's spell name: the
-- registered id when it is the known rank, otherwise the known rank's id.
-- Used for cooldown / GCD tracking (GetSpellCooldown is rank-specific).
function DH:ResolveKnownSpellId(spellId)
    if not spellId then
        return nil
    end
    if not IsSpellKnown then
        return spellId
    end
    if IsSpellKnown(spellId) then
        return spellId
    end
    -- Memoize: this runs for every registered cooldown on every state tick.
    if not ns.resolvedId then
        ns.resolvedId = {}
    end
    local cached = ns.resolvedId[spellId]
    if cached then
        return cached
    end
    local resolved = spellId
    if GetSpellInfo then
        local name = GetSpellInfo(spellId)
        if name then
            if not ns.knownByName then
                ns.knownByName = BuildKnownByName()
            end
            local knownId = ns.knownByName[name]
            if type(knownId) == "number" then
                resolved = knownId
            end
        end
    end
    ns.resolvedId[spellId] = resolved
    return resolved
end

-- Is an ability key (from DH.Class.abilities) learned?
-- Abilities without a spell id (auto attack, shoot, ...) are always allowed.
function DH:IsAbilityKnown(key)
    local ability = self.Class and self.Class.abilities and self.Class.abilities[key]
    if not ability or not ability.id then
        return true
    end
    return self:IsSpellKnownId(ability.id)
end

-- Drop unlearned abilities from a recommendation list
function DH:FilterKnown(recs)
    if not recs then
        return {}
    end
    local out = {}
    for i = 1, #recs do
        if self:IsAbilityKnown(recs[i].ability) then
            out[#out + 1] = recs[i]
        end
    end
    return out
end

-- First known basic ability from the class-registered fallback list (nil if
-- nothing fits). Called by UpdateRecommendations when FilterKnown emptied the
-- queue. The list is populated by class modules via RegisterFallbackAbilities.
function DH:FirstKnownFallback()
    local abilities = self.Class and self.Class.abilities
    if not abilities then
        return nil
    end
    for _, key in ipairs(ns.registered.fallbackAbilities) do
        if abilities[key] and self:IsAbilityKnown(key) then
            return key
        end
    end
    return nil
end
