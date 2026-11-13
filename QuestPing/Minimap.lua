-- QuestPing/Minimap.lua
-- Ways in from the minimap: QuestPing's entry in the game's addon compartment (the minimap's addon list, through
-- the .toc's AddonCompartmentFunc), and a button on the minimap rim drawn by LibDBIcon-1.0 from a LibDataBroker
-- launcher, so minimap button collectors and broker bars list it as "QuestPing". Left-click opens the hunt
-- window, right-click the settings. The rim button can be hidden in the settings.

local _, ns = ...

local NAME = "QuestPing"
local ICON = "Interface\\Icons\\Ability_Hunter_SniperShot"

local function click(mouseButton)
    if mouseButton == "RightButton" then
        if ns.OpenOptions then
            ns.OpenOptions()
        end
    else
        ns.ToggleWindow()
    end
end

function QuestPing_OnAddonCompartmentClick(_, mouseButton)
    click(mouseButton)
end

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
if not (LDB and DBIcon) then
    return -- headless tests
end

local launcher = LDB:NewDataObject(NAME, {
    type = "launcher",
    label = NAME,
    icon = ICON,
    OnClick = function(_, mouseButton)
        click(mouseButton)
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine(NAME)
        tooltip:AddLine("Click for the hunt window, right-click for settings.", 1, 1, 1)
        tooltip:AddLine("Drag to move it round the minimap.", 0.7, 0.7, 0.7)
    end,
})

--- Show or hide the rim button (Options.lua) and remember it.
function ns.SetMinimapShown(shown)
    QuestPingDB.minimap.hide = not shown
    DBIcon:Refresh(NAME, QuestPingDB.minimap)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    QuestPingDB = QuestPingDB or {}
    QuestPingDB.minimap = QuestPingDB.minimap or {}
    DBIcon:Register(NAME, launcher, QuestPingDB.minimap)
end)
