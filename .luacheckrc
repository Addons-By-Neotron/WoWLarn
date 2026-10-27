-- Luacheck configuration for World of Warcraft addons
std = "lua51"
max_line_length = 140
self = false

globals = {
    "WoWLarnDB",
}

read_globals = {
    -- Lua extensions
    "format", "strtrim", "tinsert", "wipe", "unpack",

    -- Frames / widgets
    "CreateFrame", "UIParent", "GameTooltip", "GameTooltip_Hide", "UISpecialFrames", "BackdropTemplateMixin",
    "ChatFontNormal", "UnitClass", "UnitName", "UnitSex", "LOCALIZED_CLASS_NAMES_MALE", "GameFontNormal", "IsShiftKeyDown", "MouseIsOver", "geterrorhandler",

    -- Functions
    "InCombatLockdown", "C_Timer", "GetBuildInfo", "hooksecurefunc", "issecretvalue",

    -- Libraries
    "LibStub",
}

exclude_files = {
    "Libs/**",
}

ignore = {
    "212", -- Unused argument
    "213", -- Unused loop variable
}
