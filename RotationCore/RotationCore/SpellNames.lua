-- SpellNames.lua
-- Official spell-name override for WotLK 3.3.5a clients.
--
-- The locale files hold hand-maintained translations for spell/ability
-- names. Those can drift from the client text. This module replaces them
-- with the name the running client itself reports (GetSpellInfo), so every
-- 3.3.5a locale shows the official in-game name. English clients are left
-- untouched (their base strings are already the official names).
--
-- Loaded by the .toc right after the Locale_* files.

local DH = RotationCore
if not DH or not DH.L then return end

local locale = GetLocale and GetLocale() or "enUS"
if locale == "enUS" or locale == "enGB" then return end
if not GetSpellInfo then return end

-- exact locale key -> { spellID, englishBase }
-- The english base is stripped to keep the surrounding label ("...: ", " up=").
local SPELLS = {
    ["Frost Fever: "]      = { 55095, "Frost Fever" },
    ["Blood Plague: "]     = { 55078, "Blood Plague" },
    ["Rake: "]             = { 1822,  "Rake" },
    ["Rake: up="]          = { 1822,  "Rake" },
    ["Rip: "]              = { 1079,  "Rip" },
    ["Rip: up="]           = { 1079,  "Rip" },
    ["Lacerate: "]         = { 33745, "Lacerate" },
    ["Rend: "]             = { 772,   "Rend" },
    ["Haunt: "]            = { 48181, "Haunt" },
    ["Bloodsurge: "]       = { 46916, "Bloodsurge" },
    ["Hot Streak: "]       = { 44445, "Hot Streak" },
    ["Missile Barrage: "]  = { 44401, "Missile Barrage" },
    ["Lock and Load: "]    = { 56453, "Lock and Load" },
    ["Vengeance"]          = { 20050, "Vengeance" },
    ["Black Arrow: "]      = { 3674,  "Black Arrow" },
    ["Serpent Sting: "]    = { 1978,  "Serpent Sting" },
    ["Corruption: "]       = { 172,   "Corruption" },
    ["Immolate: "]         = { 348,   "Immolate" },
    ["Flame Shock: "]      = { 8050,  "Flame Shock" },
    ["Clearcasting: "]     = { 16870, "Clearcasting" },
    ["Sudden Death: "]     = { 52437, "Sudden Death" },
    ["Sunder: "]           = { 7386,  "Sunder" },
    ["Rupture: "]          = { 1943,  "Rupture" },
    ["Mangle (Bear) CD: "] = { 33878, "Mangle (Bear)" },
    ["FF ready: "]         = { 16857, "FF" },
    ["TF ready: "]         = { 5217,  "TF" },
}

local L = DH.L
for key, entry in pairs(SPELLS) do
    local name = GetSpellInfo(entry[1])
    if name and name ~= "" then
        L[key] = name .. key:sub(#entry[2] + 1)
    end
end
