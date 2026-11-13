std = "lua51"
max_line_length = 120
unused_args = false -- WoW handler signatures are fixed

globals = {
    "QuestPingDB", "SLASH_QUESTPING1", "BINDING_HEADER_QUESTPING", "BINDING_NAME_QUESTPING_WINDOW",
    "QuestPing_ToggleWindow", "QuestPing_OnAddonCompartmentClick",
}

-- The WoW client API the addon reads.
local client = {
    "C_CVar", "C_ChatInfo", "C_NamePlate", "C_QuestLog", "C_Timer", "CreateFrame", "GameTooltip", "GetTime",
    "InCombatLockdown", "IsInGroup", "IsInRaid", "IsShiftKeyDown", "QUEST_MONSTERS_KILLED",
    "SecureHandlerWrapScript", "UIParent", "UnitAffectingCombat", "UnitCanAttack", "UnitExists", "UnitGUID",
    "UnitIsDead", "UnitIsTapDenied", "UnitIsUnit", "UnitName", "issecretvalue",
    "Settings", "SettingsPanel", "CreateSettingsButtonInitializer", "CreateKeybindingEntryInitializer",
    "GetNumBindings", "GetBinding", "GetBindingKey", "GetBindingText", "CLOSE", "SETTINGS", "C_Ping", "C_Item",
    "LibStub",
    "Polestar", "Questie", "QuestieLoader", -- optional quest databases (Sources.lua)
    "C_Map", "CreateVector2D", "GetPlayerFacing", "IsInInstance",
}

read_globals = {
    -- Blizzard-owned: set our own key only; assigning the table itself taints every Blizzard read of it.
    SlashCmdList = { fields = { QUESTPING = { read_only = false } } },
    UISpecialFrames = { read_only = false, other_fields = true },
    _G = { other_fields = true, read_only = false },
}
for _, name in ipairs(client) do
    table.insert(read_globals, name)
end

-- The WoW client has no `os` or `io`.
files["QuestPing/"] = { not_globals = { "os", "io" } }
-- Third-party libraries, kept exactly as their authors ship them.
exclude_files = { "QuestPing/Libs/" }
-- The tests define the fake client.
files["tests/"] = { globals = client }
files["tests/"].globals[#client + 1] = "SlashCmdList"
files["tests/"].globals[#client + 2] = "UISpecialFrames"
