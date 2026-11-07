-- Schema.lua
-- SavedVariables schema version and migrations. Split out of RotationCore.lua
-- so the profile/schema rules are isolated from the event and rotation engine.

local DH = RotationCore
if not DH then
    return
end

local ns = DH.ns

-- SavedVariables schema version. Bump this when a migration changes the
-- stored shape, and add the corresponding step in MigrateSaved below.
ns.SCHEMA_VERSION = 3

-- Settings that only existed in the old flat (<= 2.x) layout
local LEGACY_TOP_KEYS = { "locked", "scale", "alpha", "x", "y" }
local LEGACY_DISPLAY_KEYS = { "iconSize", "scale", "alpha", "x", "y", "showGCD", "showRange" }

-- Give the saved variable its standard structure (migrating the old flat one)
-- v3.4.0-hotfix6: rename legacy camelCase settings to snake_case and copy
-- old values forward so existing profiles keep working after the rename.
local KEY_ALIASES = {
    { "autoMode", "auto_mode" },
    { "numIcons", "num_icons" },
    { "spellFrameIcons", "spellframe_icons" },
    { "spellFrameScale", "spellframe_scale" },
    { "showNumbers", "show_numbers" },
    { "glowSize", "glow_thickness" }, -- legacy thickness -> canonical
    { "combatOnly", "combat_only" },
    { "showSpellFrame", "show_spellframe" },
    { "showDebugFrame", "show_debug_frame" },
}
local function ApplyKeyAliases(t)
    if type(t) ~= "table" then
        return
    end
    for i = 1, #KEY_ALIASES do
        local old, new = KEY_ALIASES[i][1], KEY_ALIASES[i][2]
        if t[old] ~= nil and t[new] == nil then
            t[new] = t[old]
        end
    end
end
local function MigrateKeyAliases(profile)
    if type(profile) ~= "table" then
        return
    end
    ApplyKeyAliases(profile)
    if type(profile.display) == "table" then
        ApplyKeyAliases(profile.display)
    end
    if type(profile.common) == "table" then
        ApplyKeyAliases(profile.common)
    end
end

function ns.MigrateSaved(saved)
    if type(saved) ~= "table" then
        return {
            schema_version = ns.SCHEMA_VERSION,
            profiles = { Default = {} },
            profileKeys = {},
            global = {},
        }
    end

    local schema = tonumber(saved.schema_version) or 0

    -- Already in profile form
    if type(saved.profiles) == "table" then
        if type(saved.profileKeys) ~= "table" then
            saved.profileKeys = {}
        end
        if type(saved.global) ~= "table" then
            saved.global = {}
        end
        if not next(saved.profiles) then
            saved.profiles.Default = {}
        end
        for _, prof in pairs(saved.profiles) do
            MigrateKeyAliases(prof)
        end
        -- Schema 3: profile container introduced / normalized. Older versions
        -- were already promoted above, so only stamp the version here.
        if schema < ns.SCHEMA_VERSION then
            saved.schema_version = ns.SCHEMA_VERSION
        else
            saved.schema_version = schema
        end
        return saved
    end

    -- Old flat database: the whole table becomes the "Default" profile
    local flat = saved
    for _, key in ipairs(LEGACY_TOP_KEYS) do
        flat[key] = nil
    end
    if type(flat.display) == "table" then
        for _, key in ipairs(LEGACY_DISPLAY_KEYS) do
            flat.display[key] = nil
        end
    end

    MigrateKeyAliases(flat)
    return {
        schema_version = ns.SCHEMA_VERSION,
        profiles = { Default = flat },
        profileKeys = {},
        global = {},
    }
end
