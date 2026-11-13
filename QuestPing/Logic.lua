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

-- Mobs pinged per round of presses, the longest mob name a step carries (it keeps the macro well under the
-- game's 255 characters), and mobs kept per objective (a database lists an item's droppers best chance first;
-- a common item can have dozens).
QP.MAX_PINGS = 10
QP.MAX_NAME = 80
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
-- { questID, title, level, objectives = { { index, text, have, need, done, finished, party, names, source } } }.
-- A kill objective names its mob in the log ("3/10 Skullsplitter Mystic slain"); with useSources, a quest
-- database adds the mobs a kill objective counts under another name ("Gnolls slain") and the mobs that drop a
-- collect objective's item ("2/6 Troll Tusk"). An objective with no known mob is left out, and so is a quest
-- left with none.
--
-- party (QP.PartyNeeds' shape, { [questID] = { [index] = { "Ana", ... } } }) names who in the group still needs
-- an objective: done is yours alone, finished is done with nobody in the party still needing it, and party
-- lists the ones who do.
function QP.Hunt(useSources, party)
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
                        local done = o.finished and true or false
                        local others = party and party[questID] and party[questID][index]
                        objectives[#objectives + 1] = {
                            index = index, text = readable(o.text) or "", have = o.numFulfilled or 0,
                            need = o.numRequired or 0, done = done, finished = done and not others,
                            party = others, names = names, source = source,
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

-- Party sync (Party.lua): hidden addon messages saying which objectives of which quests a player still needs,
-- by quest ID and objective index only, so every client language agrees. "1S|33:1.3;60:2" is a snapshot (it
-- replaces what's known of the sender: quest 33 objectives 1 and 3, quest 60 objective 2), "1R|..." a snapshot
-- that also asks for theirs, "1+|..." the rest of a snapshot too long for one message. "1S|" needs nothing.
QP.PARTY_VERSION = "1"
local MESSAGE_BYTES = 255

--- entries: { { q = questID, need = { index, ... } }, ... } -> the messages that carry them, in order.
function QP.EncodeNeeds(entries, asks)
    local first = QP.PARTY_VERSION .. (asks and "R|" or "S|")
    local out, parts, header = {}, {}, first
    local size = #header
    for _, e in ipairs(entries) do
        local piece = e.q .. ":" .. table.concat(e.need, ".")
        local extra = (#parts > 0 and 1 or 0) + #piece
        if #parts > 0 and size + extra > MESSAGE_BYTES then
            out[#out + 1] = header .. table.concat(parts, ";")
            parts, header = {}, QP.PARTY_VERSION .. "+|"
            size, extra = #header, #piece
        end
        parts[#parts + 1] = piece
        size = size + extra
    end
    out[#out + 1] = header .. table.concat(parts, ";")
    return out
end

--- A message -> kind ("S" snapshot, "R" snapshot asking for ours, "+" more of one) and { [q] = { [i] = true } };
-- nil for anything malformed or of another version.
function QP.DecodeNeeds(text)
    if type(text) ~= "string" then
        return nil
    end
    local kind, body = text:match("^" .. QP.PARTY_VERSION .. "([SR+])|(.*)$")
    if not kind then
        return nil
    end
    local needs = {}
    for piece in body:gmatch("[^;]+") do
        local q, list = piece:match("^(%d+):([%d%.]+)$")
        if not q then
            return nil
        end
        local set = {}
        for i in list:gmatch("%d+") do
            set[tonumber(i)] = true
        end
        needs[tonumber(q)] = set
    end
    return kind, needs
end

--- Whether a mob's name is wanted. An objective can name the mob in the plural ("Kobold Vermins slain").
function QP.Matches(wanted, name)
    return (wanted[name] or wanted[name .. "s"] or wanted[name .. "es"]) and true or false
end

-- Items whose use range tells how far a hostile unit is (C_Item.IsItemInRange works on hostile units, in combat
-- too). The yards and items are the ones DBM's range check calibrated on Forever (DBM-RangeCheck.lua).
QP.RANGE_ITEMS = { [8] = 8149, [13] = 17626, [23] = 17757, [28] = 13289, [33] = 17202, [38] = 18904, [48] = 221316 }

--- Whether unit is within yards (a key of QP.RANGE_ITEMS). No limit, an unknown limit, or an item the game
-- hasn't loaded yet all count as in range, so a mob is never dropped on a guess.
function QP.InRange(unit, yards)
    local item = yards and QP.RANGE_ITEMS[yards]
    if not (item and C_Item and C_Item.IsItemInRange) then
        return true
    end
    local ok, inRange = pcall(C_Item.IsItemInRange, item, unit)
    return not (ok and readable(inRange) == false)
end

--- Whether the game's own tooltip for a unit shows a quest count someone in your group hasn't finished: it
-- lists every party member on the quest with their count ("Aewie Booty  5/8 Tumbled Crystal"), drop items
-- included. False for no quest lines, all of them done, or a tooltip the game keeps secret.
function QP.TooltipNeeds(unit)
    local get = C_TooltipInfo and C_TooltipInfo.GetUnit
    if not get then
        return false
    end
    local ok, data = pcall(get, unit)
    if not (ok and type(data) == "table" and type(data.lines) == "table") then
        return false
    end
    local objective = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or 8
    for _, line in ipairs(data.lines) do
        if type(line) == "table" and readable(line.type) == objective then
            local done = readable(line.completed)
            if done == false then
                return true
            elseif done == nil then
                local have, need = tostring(readable(line.leftText) or ""):match("(%d+)%s*/%s*(%d+)")
                if have and tonumber(have) < tonumber(need) then
                    return true
                end
            end
        end
    end
    return false
end

--- The units worth targeting, in plates order with the current target first, and their names. A unit counts
-- when its name is wanted, or when needed(unit) says so (the tooltip check, for mobs only your party still
-- needs). range, if set, is the most yards away a mob may be (Options' "Range"). The target counts too when it
-- has no nameplate (a mob a press took by name beyond nameplate range), as the unit "target".
function QP.Candidates(wanted, plates, range, needed)
    local units, names = {}, {}
    if next(wanted) == nil and not needed then
        return units, names
    end
    local function take(unit, first)
        if UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit)
            and not UnitIsTapDenied(unit) and QP.InRange(unit, range) then
            local name = readable((UnitName(unit)))
            if name and (QP.Matches(wanted, name) or (needed and needed(unit))) then
                if first then
                    table.insert(units, 1, unit)
                    table.insert(names, 1, name)
                else
                    units[#units + 1] = unit
                    names[#names + 1] = name
                end
            end
        end
    end
    local targetPlated = false
    for _, unit in ipairs(plates) do
        local isTarget = UnitExists(unit) and readable(UnitIsUnit(unit, "target")) and true or false
        targetPlated = targetPlated or isTarget
        take(unit, isTarget)
    end
    if not targetPlated then
        take("target", true)
    end
    return units, names
end

--- Every name a press may look for beyond the nameplates, nearest known spawn first, and whether any of them
-- spawns within reach yards of the player (continent, px, py, world yards). /targetexact reaches every mob
-- the game has loaded around you, past the nameplates and out of sight, as Polestar's target button does; but
-- nothing tells QuestPing whether it's tapped or fighting until it's targeted. Names whose spawns no source
-- knows, or are on another continent, come last. Names with a nameplate up count too: a tapped one in view
-- doesn't mean a free one isn't farther out.
function QP.FarNames(hunt, continent, px, py, reach)
    local best, order = {}, {}
    local close = false
    local function add(name, dist)
        if not best[name] then
            order[#order + 1] = name
            best[name] = dist
        elseif dist < best[name] then
            best[name] = dist
        end
    end
    local reachSq = reach * reach
    for _, quest in ipairs(hunt) do
        for _, o in ipairs(quest.objectives) do
            if not o.finished then
                for _, p in ipairs(QP.SpawnPoints(quest.questID, o.index) or {}) do
                    if continent and p.continent == continent and p.name then
                        local dx, dy = p.x - px, p.y - py
                        local sq = dx * dx + dy * dy
                        close = close or sq <= reachSq
                        add(p.name, math.sqrt(sq))
                    end
                end
                for _, name in ipairs(o.names) do
                    add(name, math.huge)
                end
            end
        end
    end
    local rank = {}
    for i, name in ipairs(order) do
        rank[name] = i
    end
    table.sort(order, function(a, b)
        if best[a] ~= best[b] then
            return best[a] < best[b]
        end
        return rank[a] < rank[b]
    end)
    return order, close
end

--- Whether a mob is worth calling out: not already fighting you or anyone else. A secret answer counts as
-- fighting, so a mob is never called out on a guess.
function QP.Fresh(unit)
    return readable(UnitAffectingCombat(unit)) == false
end

--- What the next presses do, target first and ping second, like Polestar's target button plus a ping:
--
-- 1. When your target is a quest mob that's free to ping (onTarget: units[1] is the target, and it isn't in
--    quiet, which maps unit -> true for mobs pinged already or already in a fight), a press marks it and pings
--    it, without targeting anything.
-- 2. Otherwise a press targets the next mob: the unpinged ones in view (names, from QP.Candidates) first, then
--    the names that may be farther (far, from QP.FarNames), the first of them it finds by name. It pings
--    nothing: once the mob is your target QuestPing can see whether it's tapped or fighting, and only a free one
--    gets step 1 on the next press. When your target is a hunted mob that isn't free (targetName) and none is
--    free in view, the press goes on to the next mob of its name (/targetexact moves on from a target of the
--    same name); once that has come back around (moveOn), its name goes last and the others get their turn.
--
-- Returns { step 1?, step 2 } or nil for nothing to do. Each step is { text = macro, ping = unit or nil };
-- marks (QP.PickMarks) maps a unit to the raid icon step 1 puts on it. After step 1 the button falls through
-- to step 2, which repeats: out of combat the steps are rewritten after every press anyway, and in combat
-- (steps frozen at the pull) a press after a ping moves on to the next mob.
--
-- Why by name: Forever's /target and /ping do nothing with a nameplate unit (/target [@nameplate1] and /ping
-- [@nameplate3] 1 run silently in game), while /targetexact does work, as far as you can see a mob. It takes
-- the nearest mob of that name (with one of that name targeted, the next), so it can't pick which of several
-- same-named mobs it gets. "/tm ~8" marks only a mob with no raid icon yet, so a press never takes one off. In
-- combat while you have a live hostile target, step 2 stops before targeting, so spamming the key mid-fight
-- never pulls you off the mob you're hitting. A mob whose name a macro line can't carry is skipped.
local KEEP_TARGET = "/stopmacro [combat,harm,nodead]\n"
local PING_TARGET = "/ping [@target,harm,nodead] 1"
local MACRO_LIMIT = 255

local function usable(name)
    return type(name) == "string" and name ~= "" and #name <= QP.MAX_NAME and not name:find("[%c%[%];]")
end

-- Step 2: try each name until one is found. The target is dropped first so a name that isn't around can't
-- leave you on the old one; if the old one was a quest mob (targetName), it's taken back at the end
-- (/targetlasttarget) when none was found. Not dropped when the old one shares the first name: /targetexact
-- then moves on to the next of that name, which it can't do from no target.
local TAKE_BACK = "/targetlasttarget [noexists]"

local function targetStep(chain, targetName)
    local clears = chain[1] ~= targetName
    local head = "/cleartarget [dead]\n" .. KEEP_TARGET .. (clears and "/cleartarget\n" or "")
    local tail = (clears and targetName) and TAKE_BACK or ""
    local lines, size = {}, #head + #tail
    for _, name in ipairs(chain) do
        local line = "/targetexact " .. (#lines > 0 and "[noexists] " or "") .. name .. "\n/cleartarget [dead]\n"
        if size + #line > MACRO_LIMIT then
            break
        end
        lines[#lines + 1], size = line, size + #line
    end
    local text = head .. table.concat(lines) .. tail
    return { text = tail ~= "" and text or text:sub(1, -2) }
end

function QP.Steps(units, quiet, marks, names, far, onTarget, targetName, moveOn)
    marks, names = marks or {}, names or {}
    local steps = {}
    local target = onTarget and units[1] or nil
    if target and not quiet[target] then
        local mark = marks[target]
        steps[1] = { text = (mark and ("/tm [@target,harm,nodead] ~" .. mark .. "\n") or "") .. PING_TARGET,
            ping = target }
    end
    local chain, listed = {}, {}
    local function add(name)
        if usable(name) and not listed[name] then
            listed[name] = true
            chain[#chain + 1] = name
        end
    end
    for i, unit in ipairs(units) do
        if unit ~= target and not quiet[unit] then
            add(names[i])
        end
    end
    local free = #chain
    if free == 0 and targetName and not moveOn then
        add(targetName)
    end
    for _, name in ipairs(far or {}) do
        if not (moveOn and name == targetName) then
            add(name)
        end
    end
    if targetName and moveOn then
        add(targetName)
    end
    if #chain > 0 then
        steps[#steps + 1] = targetStep(chain, targetName)
    elseif #steps == 0 then
        -- Nothing new to take: keep a live target, or take back the first mob in view.
        for i in ipairs(units) do
            if usable(names[i]) then
                steps[1] = { text = "/cleartarget [dead]\n" .. KEEP_TARGET .. "/targetexact [noexists] " .. names[i] }
                break
            end
        end
    end
    return #steps > 0 and steps or nil
end

QP.MARK_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 } -- skull, cross, square, moon, triangle, diamond, circle, star

--- The raid icon each mob a press will ping gets: first, then the rest of QP.MARK_ORDER, skipping icons
-- already on someone in view (existing maps a unit to its icon). A mob that has an icon keeps it and takes
-- none. Nothing when first isn't an icon (1-8).
function QP.PickMarks(units, quiet, existing, first)
    local marks = {}
    if not (first and first >= 1 and first <= 8) then
        return marks
    end
    local used = {}
    for _, icon in pairs(existing) do
        used[icon] = true
    end
    local order = { first }
    for _, icon in ipairs(QP.MARK_ORDER) do
        if icon ~= first then
            order[#order + 1] = icon
        end
    end
    local free, count = 1, 0
    for _, unit in ipairs(units) do
        if not quiet[unit] and count < QP.MAX_PINGS then
            count = count + 1
            if not existing[unit] then
                while order[free] and used[order[free]] do
                    free = free + 1
                end
                if order[free] then
                    marks[unit] = order[free]
                    used[order[free]] = true
                end
            end
        end
    end
    return marks
end
