-- QuestPing/Logic.lua
-- What to target: the mobs your quest log still needs (from its kill lines, and from a quest database for drop
-- and group-name objectives), matched by name against the enemy nameplates in view. No frames here, so
-- tests/run_tests.lua runs it outside the game.
--
-- "Near" is "has a nameplate": enemy nameplates show out to nameplateMaxDistance (45 yards by default). A
-- plate is passed over when its mob is dead, can't be attacked, is tapped by someone else (the grey ones,
-- UnitIsTapDenied) or its name is a secret value.

local _, ns = ...

local QP = {}
ns.QP = QP

-- Nameplate clauses in the /target line, mobs pinged per round of presses, the macro's length cap (the one
-- Polestar's target button keeps), and mobs kept per objective (a database lists an item's droppers best
-- chance first; a common item can have dozens).
QP.MAX_UNITS = 8
QP.MAX_PINGS = 10
QP.MACRO_LIMIT = 255
QP.MAX_MOBS = 6

local function readable(v)
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    return v
end

QP.Readable = readable

--- Lua pattern for an objective line written with a format string such as QUEST_MONSTERS_KILLED: Forever's
-- enUS "%2$d/%3$d %1$s slain", or "%s slain: %d/%d" on older clients. The mob name is the one capture.
function QP.ObjectivePattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then
        return nil
    end
    local out, i = {}, 1
    while i <= #fmt do
        local _, e, spec = fmt:find("^%%%d*%$?([sd])", i)
        if spec then
            out[#out + 1] = spec == "s" and "(.-)" or "%d+"
            i = e + 1
        else
            local c = fmt:sub(i, i)
            if c:find("^[%^%$%(%)%.%[%]%*%+%-%?%%]$") then
                c = "%" .. c
            end
            out[#out + 1] = c
            i = i + 1
        end
    end
    return "^" .. table.concat(out) .. "$"
end

local killedPattern

--- The mob name in a kill objective's text ("3/10 Skullsplitter Mystic slain"), or nil.
function QP.ObjectiveName(text)
    text = readable(text)
    if type(text) ~= "string" then
        return nil
    end
    if killedPattern == nil then
        killedPattern = QP.ObjectivePattern(QUEST_MONSTERS_KILLED) or false
    end
    local name = killedPattern and text:match(killedPattern)
    if not name then
        -- A line the format doesn't fit: drop the counts on either side.
        name = text:gsub("^%s*%d+%s*/%s*%d+%s+", "")
        name = name:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    end
    name = name:match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
end

--- Quest databases that know which mobs an objective is about (Sources.lua registers them). Each is
-- { name, label, mobs = function(questID, index) -> { names } or nil, status = function() -> text, and
-- optionally spawns = function(questID, index) -> { { name, continent, x, y } } or nil }, where x and y are
-- world yards as C_Map.GetWorldPosFromMapPos gives them (x grows north, y grows west). The first source that
-- answers for an objective wins.
QP.Sources = {}

function QP.AddSource(source)
    QP.Sources[#QP.Sources + 1] = source
end

local function fromSources(questID, index)
    for _, source in ipairs(QP.Sources) do
        local ok, names = pcall(source.mobs, questID, index)
        if ok and type(names) == "table" and #names > 0 then
            return names, source.label
        end
    end
    return nil
end

local spawnCache = {} -- "questID:index" -> points; spawns never move. A miss isn't kept: a source can finish
-- loading later.

--- Where an objective's mobs spawn, from the first source that knows, as world points (see QP.Sources).
function QP.SpawnPoints(questID, index)
    local key = questID .. ":" .. index
    if spawnCache[key] then
        return spawnCache[key]
    end
    for _, source in ipairs(QP.Sources) do
        if source.spawns then
            local ok, points = pcall(source.spawns, questID, index)
            if ok and type(points) == "table" and #points > 0 then
                spawnCache[key] = points
                return points
            end
        end
    end
    return nil
end

--- The nearest point on the player's continent, and its distance in yards; nil when none is. Points that are
-- keys of skip (spawns found empty, see QP.MarkSeen) are passed over.
function QP.Nearest(points, continent, px, py, skip)
    local best, bestSq
    for _, p in ipairs(points) do
        if p.continent == continent and not (skip and skip[p]) then
            local dx, dy = p.x - px, p.y - py
            local sq = dx * dx + dy * dy
            if not bestSq or sq < bestSq then
                best, bestSq = p, sq
            end
        end
    end
    return best, best and math.sqrt(bestSq) or nil
end

--- Puts every point within range yards of the player in seen, at time now: the player has been there and no
-- mob it's for was in view, so the spawn is empty (killed, or taken by someone else) until it respawns.
function QP.MarkSeen(points, continent, px, py, range, seen, now)
    local rangeSq = range * range
    for _, p in ipairs(points) do
        if p.continent == continent then
            local dx, dy = p.x - px, p.y - py
            if dx * dx + dy * dy <= rangeSq then
                seen[p] = now
            end
        end
    end
end

--- The turn from where the player faces to the point, in radians counterclockwise, for Texture:SetRotation on
-- an arrow drawn pointing up. facing is GetPlayerFacing's: 0 is north, growing counterclockwise; world x grows
-- north and y west, so atan2(west, north) is the point's bearing on the same scale.
function QP.Bearing(px, py, tx, ty, facing)
    local angle = math.atan2(ty - py, tx - px) - facing
    local turn = 2 * math.pi
    return (angle + math.pi) % turn - math.pi
end

--- The quests in the log worth hunting, in log order:
-- { questID, title, level, objectives = { { index, text, have, need, finished, names, source } } }.
-- A kill objective names its mob in the log ("3/10 Skullsplitter Mystic slain"); with useSources, a quest
-- database adds the mobs a kill objective counts under another name ("Gnolls slain") and the mobs that drop a
-- collect objective's item ("2/6 Troll Tusk"). An objective with no known mob is left out, and so is a quest
-- left with none.
function QP.Hunt(useSources)
    local hunt, QL = {}, C_QuestLog
    if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.GetQuestObjectives) then
        return hunt
    end
    for i = 1, (QL.GetNumQuestLogEntries()) or 0 do
        local info = QL.GetInfo(i)
        local questID = info and not info.isHeader and not info.isHidden and readable(info.questID)
        if questID then
            local objectives = {}
            for index, o in ipairs(QL.GetQuestObjectives(questID) or {}) do
                if o.type == "monster" or o.type == "item" then
                    local names, source = {}, "Quest log"
                    local own = o.type == "monster" and QP.ObjectiveName(o.text) or nil
                    if own then
                        names[1] = own
                    end
                    local found, label = nil, nil
                    if useSources then
                        found, label = fromSources(questID, index)
                    end
                    for _, name in ipairs(found or {}) do
                        if name ~= own and #names < QP.MAX_MOBS then
                            names[#names + 1] = name
                            source = label
                        end
                    end
                    if #names > 0 then
                        objectives[#objectives + 1] = {
                            index = index, text = readable(o.text) or "", have = o.numFulfilled or 0,
                            need = o.numRequired or 0, finished = o.finished and true or false,
                            names = names, source = source,
                        }
                    end
                end
            end
            if #objectives > 0 then
                hunt[#hunt + 1] = {
                    questID = questID, title = readable(info.title) or ("Quest " .. questID), level = info.level,
                    objectives = objectives,
                }
            end
        end
    end
    return hunt
end

--- Set of mob names (name -> true) from every unfinished objective of a hunt.
function QP.WantedNames(hunt)
    local wanted = {}
    for _, quest in ipairs(hunt) do
        for _, o in ipairs(quest.objectives) do
            if not o.finished then
                for _, name in ipairs(o.names) do
                    wanted[name] = true
                end
            end
        end
    end
    return wanted
end

--- Whether a mob's name is wanted. An objective can name the mob in the plural ("Kobold Vermins slain").
function QP.Matches(wanted, name)
    return (wanted[name] or wanted[name .. "s"] or wanted[name .. "es"]) and true or false
end

--- The nameplate units worth targeting, in plates order with the current target first, and their names.
function QP.Candidates(wanted, plates)
    local units, names = {}, {}
    if next(wanted) == nil then
        return units, names
    end
    for _, unit in ipairs(plates) do
        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit)
            and not UnitIsTapDenied(unit) then
            local name = readable((UnitName(unit)))
            if name and QP.Matches(wanted, name) then
                if readable(UnitIsUnit(unit, "target")) then
                    table.insert(units, 1, unit)
                    table.insert(names, 1, name)
                else
                    units[#units + 1] = unit
                    names[#names + 1] = name
                end
            end
        end
    end
    return units, names
end

--- Whether a mob is worth calling out: not already fighting you or anyone else. A secret answer counts as
-- fighting, so a mob is never called out on a guess.
function QP.Fresh(unit)
    return readable(UnitAffectingCombat(unit)) == false
end

--- What each press of the button does, in order: one step per mob to ping (every unit not in quiet, which
-- maps unit -> true for mobs pinged already or already in a fight), then a last step that only targets
-- and repeats on every press after it. Nil for no units. Each step is { text = macro, ping = unit or nil }.
--
-- A step clears a dead target, pings its mob without targeting it, then targets the first unit still
-- hostile and alive, except in combat while you already have a live hostile target, so spamming the key
-- mid-fight never pulls you off the mob you're hitting. The conditions matter in combat, when the steps
-- can't be rewritten and a nameplate token may have moved to another mob.
function QP.Steps(units, quiet)
    if #units == 0 then
        return nil
    end
    local queue = {}
    for _, unit in ipairs(units) do
        if not quiet[unit] and #queue < QP.MAX_PINGS then
            queue[#queue + 1] = unit
        end
    end
    local longestPing = ""
    for _, unit in ipairs(queue) do
        local line = "/ping [@" .. unit .. ",harm,nodead] 1\n"
        if #line > #longestPing then
            longestPing = line
        end
    end
    local n = math.min(#units, QP.MAX_UNITS)
    local targeting
    while n > 0 do
        local clauses = {}
        for i = 1, n do
            clauses[i] = "[@" .. units[i] .. ",harm,nodead]"
        end
        targeting = "/stopmacro [combat,@target,harm,nodead]\n/target " .. table.concat(clauses)
        if #("/cleartarget [dead]\n" .. longestPing .. targeting) <= QP.MACRO_LIMIT then
            break
        end
        n = n - 1
    end
    local steps = {}
    for _, unit in ipairs(queue) do
        steps[#steps + 1] = {
            text = "/cleartarget [dead]\n/ping [@" .. unit .. ",harm,nodead] 1\n" .. targeting,
            ping = unit,
        }
    end
    steps[#steps + 1] = { text = "/cleartarget [dead]\n" .. targeting }
    return steps
end
