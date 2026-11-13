-- QuestPing/Sources.lua
-- Quest databases QuestPing reads to know which mobs an objective is about (Logic.lua's QP.Sources). Each is
-- optional: without it, QuestPing still hunts the mobs the quest log names.

local _, ns = ...
local QP = ns.QP

-- Polestar's quest database (the load-on-demand Polestar_QuestDB). Polestar loads it while any of its quest
-- features is on (qol.questDB, on by default). Q.GetObjectiveMobs(questID, index) gives an objective's mobs in
-- the client's language: the kill target, or the item's droppers best chance first. Its index is the
-- objective's place in the quest log, which matches the database for nearly every quest (QuestDB.lua).
local function polestarDB()
    local Q = type(Polestar) == "table" and Polestar.QuestDB
    if type(Q) == "table" and Q.IsLoaded and Q.GetObjectiveMobs and Q.IsLoaded() then
        return Q
    end
    return nil
end

QP.AddSource({
    name = "polestar",
    label = "Polestar database",
    mobs = function(questID, index)
        local Q = polestarDB()
        return Q and Q.GetObjectiveMobs(questID, index) or nil
    end,
    status = function()
        if type(Polestar) ~= "table" then
            return nil -- not installed: say nothing
        end
        return polestarDB() and "Polestar database: on" or "Polestar database: not loaded"
    end,
})
