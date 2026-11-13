-- QuestPing/Options.lua
-- QuestPing's page under the game menu's Options > AddOns (Settings.RegisterAddOnCategory), the same API
-- SideQuest's options use on Forever. Every row reads and writes the QuestPingDB field QuestPing.lua reads;
-- an unset field means the default. /questping options and the window's Settings button open it.

local _, ns = ...

if not Settings then
    return -- no modern Settings API (headless tests)
end

local category

local ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local function checkbox(key, name, default, tooltip)
    local variable = "QUESTPING_" .. key:upper()
    local setting = Settings.RegisterAddOnSetting(category, variable, key, QuestPingDB, Settings.VarType.Boolean,
        name, default)
    Settings.CreateCheckbox(category, setting, tooltip)
    Settings.SetOnValueChangedCallback(variable, ns.Refresh)
end

local function header(name)
    SettingsPanel:GetLayout(category):AddInitializer(
        Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name = name }))
end

local function button(name, text, onClick, tooltip)
    local initializer = CreateSettingsButtonInitializer(name, text, onClick, tooltip, true)
    SettingsPanel:GetLayout(category):AddInitializer(initializer)
end

-- QuestPing's key bindings (Bindings.xml), as the same rows Options > Key Bindings draws
-- (CreateKeybindingEntryInitializer, Blizzard_Keybindings.lua). Setting a key there saves it at once.
local BINDINGS = { "CLICK QuestPingButton:LeftButton", "QUESTPING_WINDOW" }

local function bindingRows()
    if not (CreateKeybindingEntryInitializer and GetNumBindings and GetBinding) then
        return
    end
    local index = {}
    for i = 1, GetNumBindings() do
        index[GetBinding(i)] = i
    end
    local layout = SettingsPanel:GetLayout(category)
    for _, action in ipairs(BINDINGS) do
        if index[action] then
            local ok, initializer = pcall(CreateKeybindingEntryInitializer, index[action], true)
            if ok and initializer then
                layout:AddInitializer(initializer)
            end
        end
    end
end

local function register()
    QuestPingDB = QuestPingDB or {}
    category = Settings.RegisterVerticalLayoutCategory("QuestPing")
    Settings.RegisterAddOnCategory(category)

    header("Pinging")
    local iconSetting = Settings.RegisterAddOnSetting(category, "QUESTPING_CHATICON", "chatIcon", QuestPingDB,
        Settings.VarType.Number, "Raid icon", 8)
    Settings.CreateDropdown(category, iconSetting, function()
        local options = Settings.CreateControlTextContainer()
        for i = 8, 1, -1 do
            options:Add(i, "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":0|t " .. ICON_NAMES[i])
        end
        options:Add(0, "No icon")
        return options:GetData()
    end, "The raid icon a press puts on the mob, so everyone sees which one: this one first, then the next free one "
        .. "(skull, cross, square...) for each other mob. Never takes an icon off a mob. In a raid only the leader "
        .. "and assistants can mark. No icon: no marking.")
    Settings.SetOnValueChangedCallback("QUESTPING_CHATICON", ns.Refresh)
    checkbox("arrow", "Arrow over the next mob", true,
        "A bouncing arrow over the nameplate of the mob the next press will ping.")
    checkbox("marks", "Mark free quest mobs", true,
        "A quest icon beside the nameplate of every mob you still need that nobody has: not tapped by someone "
            .. "else and not in a fight.")
    checkbox("guide", "Guide arrow", true,
        "When no mob you still need is in view, an arrow near the top of the screen points at the nearest place one "
            .. "spawns, with its distance. Needs Polestar's or Questie's quest database. Shift-drag to move it.")
    Settings.SetOnValueChangedCallback("QUESTPING_GUIDE", function()
        if ns.UpdateGuide then
            ns.UpdateGuide()
        end
    end)

    header("Finding mobs")
    local rangeSetting = Settings.RegisterAddOnSetting(category, "QUESTPING_RANGE", "range", QuestPingDB,
        Settings.VarType.Number, "Range", 0)
    Settings.CreateDropdown(category, rangeSetting, function()
        local options = Settings.CreateControlTextContainer()
        options:Add(0, "Any nameplate (max)")
        for _, yards in ipairs({ 48, 38, 33, 28, 23, 13, 8 }) do
            options:Add(yards, yards .. " yards")
        end
        return options:GetData()
    end, "How far away a quest mob may be and still count as near. Max is as far as the game shows enemy "
        .. "nameplates. Closer keeps the button and pings on mobs you can reach soon.")
    Settings.SetOnValueChangedCallback("QUESTPING_RANGE", ns.Refresh)
    checkbox("party", "Hunt for your party too", true,
        "Keep hunting a mob you're done with while someone in your group still needs it. Party members running "
            .. "QuestPing share what they still need (hidden addon messages, party or raid only); so do ones "
            .. "running Polestar with its party sharing on.")
    Settings.SetOnValueChangedCallback("QUESTPING_PARTY", function()
        if ns.UpdateParty then
            ns.UpdateParty()
        end
    end)
    checkbox("sources", "Use quest databases", true,
        "Read Polestar's or Questie's quest database, when one is installed, to also hunt the mobs that drop quest "
            .. "items (\"2/6 Troll Tusk\") and kill objectives named for a group (\"Gnolls slain\"), and to give the "
            .. "guide arrow its spawn places. Off: only mobs the quest log names.")
    local plates = Settings.RegisterProxySetting(category, "QUESTPING_ENEMY_PLATES", Settings.VarType.Boolean,
        "Enemy nameplates", false,
        function() return C_CVar.GetCVarBool("nameplateShowEnemies") end,
        function(on)
            if not InCombatLockdown() then
                C_CVar.SetCVar("nameplateShowEnemies", on and "1" or "0")
            end
            ns.Refresh()
        end)
    Settings.CreateCheckbox(category, plates,
        "The game's own setting. QuestPing only sees mobs with a nameplate up, so with this off nothing is ever "
            .. "near. Can't change in combat.")

    header("Key bindings")
    bindingRows()

    header("Window and button")
    local buttonSetting = Settings.RegisterAddOnSetting(category, "QUESTPING_BUTTON", "button", QuestPingDB,
        Settings.VarType.String, "Ping button", "near")
    Settings.CreateDropdown(category, buttonSetting, function()
        local options = Settings.CreateControlTextContainer()
        options:Add("near", "When a quest mob is near")
        options:Add("always", "Always")
        options:Add("never", "Never (key binding only)")
        return options:GetData()
    end, "The button you click to ping, if you'd rather not bind a key. \"Always\" keeps it on screen, dimmed "
        .. "while nothing is near, so you can find it and shift-drag it where you want. In combat the change waits "
        .. "for the fight to end.")
    Settings.SetOnValueChangedCallback("QUESTPING_BUTTON", ns.Refresh)
    button("Hunt window", "Open", ns.ToggleWindow,
        "The quests you're hunting, their mobs and how many are near. Also /questping, or right-click the ping button.")
    local minimap = Settings.RegisterProxySetting(category, "QUESTPING_MINIMAP", Settings.VarType.Boolean,
        "Minimap button", true,
        function() return not (QuestPingDB.minimap and QuestPingDB.minimap.hide) end,
        function(shown)
            if ns.SetMinimapShown then
                ns.SetMinimapShown(shown)
            end
        end)
    Settings.CreateCheckbox(category, minimap,
        "QuestPing's button on the minimap rim: click for the hunt window, right-click for these settings. "
            .. "QuestPing is also in the minimap's addon list either way.")
    button("Positions", "Reset", function()
        ns.ResetButton()
        ns.ResetWindow()
        ns.ResetGuide()
    end, "Put the ping button, the window and the guide arrow back where they start.")
end

function ns.OpenOptions()
    if category then
        Settings.OpenToCategory(category:GetID())
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", register)
