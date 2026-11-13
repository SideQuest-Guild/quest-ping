-- QuestPing/Sources.lua
-- Quest databases QuestPing reads to know which mobs an objective is about and where they spawn (Logic.lua's
-- QP.Sources). Each is optional: without them QuestPing still hunts the mobs the quest log names, and the guide
-- arrow has nowhere to point. Polestar comes first, then Questie, then Polestar's Codex for spawns by name; the
-- first that answers wins.

local _, ns = ...
local QP = ns.QP
local readable = QP.Readable

local function xyOf(v)
    if type(v) ~= "table" and type(v) ~= "userdata" then
        return nil
    end
    local x, y = v.x, v.y
    if x == nil and v.GetXY then
        x, y = v:GetXY()
    end
    return readable(x), readable(y)
end

-- A spot on a zone map (uiMapID, x and y 0-100 as the world map shows them) in world yards.
local function mapToWorld(uiMapID, x, y)
    if not (uiMapID and x and y and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
        return nil
    end
    local continent, pos = C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(x / 100, y / 100))
    local wx, wy = xyOf(pos)
    if not (readable(continent) and wx) then
        return nil
    end
    return continent, wx, wy
end

---------------------------------------------------------------------------
-- Polestar (the load-on-demand Polestar_QuestDB)
---------------------------------------------------------------------------

-- Polestar loads it while any of its quest features is on (qol.questDB, on by default).
-- Q.GetObjectiveMobs(questID, index) gives an objective's mobs in the client's language: the kill target, or the
-- item's droppers best chance first. Q.GetQuest(questID).objectives[index] is { kind = "kill"|"item", id }, and
-- Q.GetNpc(id).spawns are { map, x, y, f } where f "e" marks coordinates in the Era map frame, which only
-- Polestar.Compat.MapToWorld converts. The index is the objective's place in the quest log, which matches the
-- database for nearly every quest (QuestDB.lua).
local function polestarDB()
    local Q = type(Polestar) == "table" and Polestar.QuestDB
    if type(Q) == "table" and Q.IsLoaded and Q.GetObjectiveMobs and Q.IsLoaded() then
        return Q
    end
    return nil
end

local function polestarNpcIds(Q, questID, index)
    local quest = Q.GetQuest and Q.GetQuest(questID)
    local o = quest and quest.objectives and quest.objectives[index]
    if not o then
        return nil
    end
    if o.kind == "kill" then
        return { o.id }
    elseif o.kind == "item" and Q.GetItemDroppers then
        local ids = {}
        for _, d in ipairs(Q.GetItemDroppers(o.id) or {}) do
            if #ids < QP.MAX_MOBS then
                ids[#ids + 1] = d.id
            end
        end
        return ids
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
    spawns = function(questID, index)
        local Q = polestarDB()
        local C = type(Polestar) == "table" and Polestar.Compat
        if not (Q and Q.GetNpc and C and C.MapToWorld) then
            return nil
        end
        local points = {}
        for _, id in ipairs(polestarNpcIds(Q, questID, index) or {}) do
            local npc = Q.GetNpc(id)
            for _, s in ipairs(npc and npc.spawns or {}) do
                local continent, wx, wy = C.MapToWorld(s.map, s.x, s.y, s.f)
                if continent then
                    points[#points + 1] = { name = npc.name, continent = continent, x = wx, y = wy }
                end
            end
        end
        return points
    end,
    status = function()
        if type(Polestar) ~= "table" then
            return nil -- not installed: say nothing
        end
        return polestarDB() and "Polestar database: on" or "Polestar database: not loaded"
    end,
})

---------------------------------------------------------------------------
-- Questie (v12+, Forever flavor)
---------------------------------------------------------------------------

-- Questie's QuestieDB module (QuestieLoader:ImportModule("QuestieDB"), data from the QuestieDB addon) once
-- Questie has started. QuestieDB.GetQuest(questID).ObjectiveData is keyed by the same index as the client's
-- C_QuestLog.GetQuestObjectives (Questie's own QuestieQuest:PopulateQuestLogInfo relies on it), each entry
-- { Type = "monster"|"killcredit"|"item"|..., Id, IdList }. Npc spawns are { [AreaID] = { { x, y }, ... } } in
-- 0-100 map percent; ZoneDB:GetUiMapIdByAreaId turns the area into a uiMapID.
local function questie()
    if type(Questie) ~= "table" or type(QuestieLoader) ~= "table" or not QuestieLoader.ImportModule then
        return nil
    end
    local ready = Questie.started or (type(Questie.API) == "table" and Questie.API.isReady)
    if not ready then
        return nil
    end
    local DB = QuestieLoader:ImportModule("QuestieDB")
    if type(DB) ~= "table" or not (DB.GetQuest and DB.QueryNPCSingle) then
        return nil
    end
    return DB
end

local function questieNpcIds(DB, questID, index)
    local quest = DB.GetQuest(questID)
    local o = quest and quest.ObjectiveData and quest.ObjectiveData[index]
    if type(o) ~= "table" then
        return nil
    end
    if o.Type == "monster" then
        return { o.Id }
    elseif o.Type == "killcredit" and type(o.IdList) == "table" then
        return o.IdList
    elseif o.Type == "item" and DB.QueryItemSingle then
        local ids = {}
        for _, id in ipairs(DB.QueryItemSingle(o.Id, "npcDrops") or {}) do
            if #ids < QP.MAX_MOBS then
                ids[#ids + 1] = id
            end
        end
        return ids
    end
    return nil
end

QP.AddSource({
    name = "questie",
    label = "Questie database",
    mobs = function(questID, index)
        local DB = questie()
        if not DB then
            return nil
        end
        local names = {}
        for _, id in ipairs(questieNpcIds(DB, questID, index) or {}) do
            local name = DB.QueryNPCSingle(id, "name")
            if type(name) == "string" and name ~= "" then
                names[#names + 1] = name
            end
        end
        return names
    end,
    spawns = function(questID, index)
        local DB = questie()
        local ZoneDB = DB and QuestieLoader:ImportModule("ZoneDB")
        if not (ZoneDB and ZoneDB.GetUiMapIdByAreaId) then
            return nil
        end
        local points = {}
        for _, id in ipairs(questieNpcIds(DB, questID, index) or {}) do
            local name = DB.QueryNPCSingle(id, "name")
            for areaID, coords in pairs(DB.QueryNPCSingle(id, "spawns") or {}) do
                local uiMapID = ZoneDB:GetUiMapIdByAreaId(areaID)
                for _, c in ipairs(coords) do
                    local continent, wx, wy = mapToWorld(uiMapID, c[1], c[2])
                    if continent then
                        points[#points + 1] = { name = name, continent = continent, x = wx, y = wy }
                    end
                end
            end
        end
        return points
    end,
    status = function()
        if type(Questie) ~= "table" then
            return nil
        end
        return questie() and "Questie database: on" or "Questie database: not ready"
    end,
})

---------------------------------------------------------------------------
-- Polestar's Codex (the load-on-demand Polestar_Codex): spawns by mob name
---------------------------------------------------------------------------

-- The quest databases above don't have Forever's own quests (Bats in the Belfry), so their mobs had no known
-- spawn: they sorted last among the names a press tries, fell off the end of its macro, and never brought the
-- button up. The Codex has every NPC with its spawns, Forever's too. Codex.Index(kind) is its name index, lines
-- "\2<folded name>\1<id>,...", folded as Polestar.Search.Fold minus its leading space; Codex.Npc(id).spawns
-- are { map, x, y, f } like the quest database's. The index is in English, so on another client's language a
-- name only matches where it's spelled the same.
local INDEX_KINDS = { "npc", "rare" }
local codexTried = false -- Codex.Load is tried once (out of combat): a missing pack stays missing
local codexIds = {} -- mob name -> { npc id, ... } (empty when the Codex has no such name)

local function codex()
    local P = type(Polestar) == "table" and Polestar or nil
    local X = P and P.Codex
    local S = P and P.Search
    if type(X) ~= "table" or not (X.IsLoaded and X.Index and X.Npc and S and S.Fold and P.Compat
        and P.Compat.MapToWorld) then
        return nil
    end
    if not X.IsLoaded() then
        -- Polestar loads it for its own lookups; load it here too, unless its Lookup is switched off.
        if codexTried or not X.Load or InCombatLockdown() or (P.Get and P.Get("lookup.enabled") == false) then
            return nil
        end
        codexTried = true
        local ok, loaded = pcall(X.Load)
        if not (ok and loaded) then
            return nil
        end
    end
    return X, S, P.Compat
end

local function codexNpcIds(X, S, name)
    if codexIds[name] then
        return codexIds[name]
    end
    local ids, seen = {}, {}
    local needle = "\2" .. S.Fold(name):sub(2) .. "\1"
    for _, kind in ipairs(INDEX_KINDS) do
        local blob = X.Index(kind)
        local at = 1
        while type(blob) == "string" do
            local _, e = blob:find(needle, at, true)
            if not e then
                break
            end
            local id = tonumber(blob:match("^(%d+)", e + 1))
            if id and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
            at = e + 1
        end
    end
    codexIds[name] = ids
    return ids
end

QP.AddSource({
    name = "codex",
    label = "Polestar codex",
    spawns = function(_, _, names)
        local X, S, C = codex()
        if not X then
            return nil
        end
        local points = {}
        for _, name in ipairs(names or {}) do
            for _, id in ipairs(codexNpcIds(X, S, name)) do
                local npc = X.Npc(id)
                for _, s in ipairs(npc and npc.spawns or {}) do
                    local continent, wx, wy = C.MapToWorld(s.map, s.x, s.y, s.f)
                    if continent then
                        points[#points + 1] = { name = name, continent = continent, x = wx, y = wy }
                    end
                end
            end
        end
        return points
    end,
    status = function()
        local X = type(Polestar) == "table" and Polestar.Codex
        if type(X) ~= "table" or not X.IsLoaded then
            return nil
        end
        return X.IsLoaded() and "Polestar codex: on" or "Polestar codex: not loaded"
    end,
})

--- Where the player stands in world yards: continent, x, y; nil where the game gives no position.
function ns.PlayerWorldPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
        return nil
    end
    local map = readable(C_Map.GetBestMapForUnit("player"))
    local x, y = xyOf(map and C_Map.GetPlayerMapPosition(map, "player"))
    if not x or (x == 0 and y == 0) then
        return nil
    end
    return mapToWorld(map, x * 100, y * 100)
end
