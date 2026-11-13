-- luajit tests/run_tests.lua (from the repo root)
-- Runs QuestPing outside the game against a small fake of the WoW API.

local failures, count = 0, 0
local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if not ok then
        failures = failures + 1
        print("FAIL " .. name .. "\n  " .. tostring(err))
    end
end
local function eq(got, want, what)
    if got ~= want then
        error((what or "value") .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
    end
end

---------------------------------------------------------------------------
-- Fake client
---------------------------------------------------------------------------

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
-- units: token -> { name, dead, tapped, friendly, target, fighting, guid }
local world

local function reset()
    world = { units = {}, quests = {}, combat = false, group = nil, chat = {}, addon = {}, now = 100 }
end
reset()

QUEST_MONSTERS_KILLED = "%2$d/%3$d %1$s slain"
function issecretvalue(v) return v == SECRET end
-- A unit by token; "target" is whichever unit has target set (a nameplate, or a far one with no nameplate).
local function U(u)
    if u == "target" then
        for key, v in pairs(world.units) do
            if v.target then return v, key end
        end
        return nil
    end
    return world.units[u], u
end
function UnitExists(u) return U(u) ~= nil end
function UnitCanAttack(_, u) return not U(u).friendly end
function UnitIsDead(u) return U(u).dead or false end
function UnitIsTapDenied(u) return U(u).tapped or false end
function UnitAffectingCombat(u) return U(u).fighting or false end
function UnitName(u) return U(u).name end
function UnitGUID(u)
    local v, key = U(u)
    return v.guid or ("Creature-" .. key)
end
function UnitIsUnit(u, other)
    return other == "target" and U(u).target or false
end
function InCombatLockdown() return world.combat end
function GetTime() return world.now end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function IsInRaid() return world.group == "raid" end
function IsInGroup() return world.group ~= nil end
function IsShiftKeyDown() return world.shift end
function GetRaidTargetIndex(u) return world.units[u] and world.units[u].icon end
C_ChatInfo = {
    SendChatMessage = function(msg, channel) world.chat[#world.chat + 1] = channel .. ": " .. msg end,
    SendAddonMessage = function(prefix, msg, channel)
        world.addon[#world.addon + 1] = channel .. " " .. prefix .. " " .. msg
    end,
    RegisterAddonMessagePrefix = function() end,
}
function Ambiguate(name) return name end
UNKNOWNOBJECT = "Unknown"
-- Party members are party1..partyN in world.units, like the client's tokens.
function GetNumSubgroupMembers()
    local n = 0
    while world.units["party" .. (n + 1)] do n = n + 1 end
    return n
end
function GetNumGroupMembers() return GetNumSubgroupMembers() + 1 end
C_QuestLog = {
    GetNumQuestLogEntries = function() return #world.quests, #world.quests end,
    GetInfo = function(i)
        local q = world.quests[i]
        return { questID = q.id, isHeader = q.header or false }
    end,
    GetQuestObjectives = function(id)
        for _, q in ipairs(world.quests) do
            if q.id == id then return q.objectives end
        end
    end,
}

local function kill(name, have, need)
    return { text = have .. "/" .. need .. " " .. name .. " slain", type = "monster", finished = have >= need,
        numFulfilled = have, numRequired = need }
end

local ns = {}
assert(loadfile("QuestPing/Logic.lua"))("QuestPing", ns)
assert(loadfile("QuestPing/Sources.lua"))("QuestPing", ns)
local QP = ns.QP

---------------------------------------------------------------------------
-- Logic
---------------------------------------------------------------------------

test("objective name from Forever's and older clients' kill lines", function()
    eq(QP.ObjectiveName("3/10 Skullsplitter Mystic slain"), "Skullsplitter Mystic")
    eq(QP.ObjectiveName("Kobold Vermin: 3/10"), "Kobold Vermin", "a line the format doesn't fit")
    eq(QP.ObjectiveName("0/1 "), nil, "counts alone")
    eq(QP.ObjectiveName(SECRET), nil)
    local older = QP.ObjectivePattern("%s slain: %d/%d")
    eq(("Kobold Vermin slain: 3/10"):match(older), "Kobold Vermin")
    eq(("Mo (Elite) slain: 0/1"):match(older), "Mo (Elite)", "magic characters in the name")
end)

test("wanted names come only from unfinished kill objectives", function()
    reset()
    world.quests = {
        { id = 0, header = true, objectives = {} },
        { id = 1, objectives = { kill("Skullsplitter Mystic", 3, 10), kill("Skullsplitter Axe Thrower", 8, 8) } },
        { id = 2, objectives = { { text = "2/6 Troll Tusk", type = "item", finished = false } } },
    }
    local wanted = QP.WantedNames(QP.Hunt(true))
    eq(wanted["Skullsplitter Mystic"], true)
    eq(wanted["Skullsplitter Axe Thrower"], nil, "finished objective")
    eq(wanted["Troll Tusk"], nil, "item objective without a database")
end)

test("Polestar's database adds droppers and group members, only while loaded and switched on", function()
    reset()
    world.quests = {
        { id = 7, objectives = {
            { text = "0/6 Troll Tusk", type = "item", finished = false, numFulfilled = 0, numRequired = 6 },
            kill("Gnolls", 2, 8),
            { text = "Talk to Brann", type = "event", finished = false },
        } },
    }
    local loaded = true
    Polestar = { QuestDB = {
        IsLoaded = function() return loaded end,
        GetObjectiveMobs = function(questID, index)
            assert(questID == 7)
            return ({ { "Skullsplitter Mystic", "Skullsplitter Hunter" }, { "Riverpaw Brute" }, { "Brann" } })[index]
        end,
    } }
    local hunt = QP.Hunt(true)
    eq(#hunt, 1)
    eq(#hunt[1].objectives, 2, "the event objective is not hunted")
    eq(hunt[1].objectives[1].source, "Polestar database")
    local wanted = QP.WantedNames(hunt)
    eq(wanted["Skullsplitter Hunter"], true, "an item's dropper")
    eq(wanted["Riverpaw Brute"], true, "a mob counting for a group-name kill line")
    eq(wanted["Gnolls"], true, "the log's own name stays")
    eq(wanted["Brann"], nil)

    eq(QP.WantedNames(QP.Hunt(false))["Riverpaw Brute"], nil, "databases switched off")
    loaded = false
    eq(QP.WantedNames(QP.Hunt(true))["Skullsplitter Hunter"], nil, "database not loaded yet")
    Polestar = nil
end)

-- A Questie that has started, with one quest: objective 1 kills npc 100, objective 2 is any of npcs 101 and 102
-- (kill credit), objective 3 collects item 500 dropped by npc 103. Npc 100 spawns at 50,60 and 50,30 on area 10
-- (uiMap 1).
local function fakeQuestie()
    local npcs = {
        [100] = { name = "Skullsplitter Mystic", spawns = { [10] = { { 50, 60 }, { 50, 30 } } } },
        [101] = { name = "Riverpaw Brute" }, [102] = { name = "Riverpaw Mongrel" }, [103] = { name = "Gnoll Pup" },
    }
    local modules = {
        QuestieDB = {
            GetQuest = function(id)
                return id == 1 and { ObjectiveData = {
                    { Type = "monster", Id = 100 },
                    { Type = "killcredit", IdList = { 101, 102 } },
                    { Type = "item", Id = 500 },
                } } or nil
            end,
            QueryNPCSingle = function(id, field) return npcs[id] and npcs[id][field] end,
            QueryItemSingle = function(id, field) return id == 500 and field == "npcDrops" and { 103 } or nil end,
        },
        ZoneDB = { GetUiMapIdByAreaId = function(_, area) return area == 10 and 1 or nil end },
    }
    Questie = { started = true }
    QuestieLoader = { ImportModule = function(_, name) return modules[name] end }
end

-- One zone map (uiMap 1) on continent 1, 1000 yards on a side; world x and y are the map's x and y in yards.
function CreateVector2D(x, y) return { x = x, y = y } end
C_Map = {
    GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function() return { x = world.px or 0.5, y = world.py or 0.5 } end,
    GetWorldPosFromMapPos = function(map, v) return map == 1 and 1 or nil, { x = v.x * 1000, y = v.y * 1000 } end,
}

test("Questie's database names the mobs by the quest log's objective index, and where they spawn", function()
    reset()
    world.quests = { { id = 1, objectives = {
        kill("Skullsplitter Mystic", 0, 10), kill("Gnolls", 0, 8),
        { text = "0/5 Gnoll Paw", type = "item", finished = false, numFulfilled = 0, numRequired = 5 },
    } } }
    Questie = { started = false }
    QuestieLoader = { ImportModule = function() error("not ready yet") end }
    eq(QP.WantedNames(QP.Hunt(true))["Riverpaw Brute"], nil, "Questie not started")

    fakeQuestie()
    local wanted = QP.WantedNames(QP.Hunt(true))
    eq(wanted["Riverpaw Mongrel"], true, "kill credit mobs")
    eq(wanted["Gnoll Pup"], true, "item droppers")
    local points = QP.SpawnPoints(1, 1)
    eq(#points, 2)
    eq(points[1].continent, 1)
    eq(points[1].x, 500)
    eq(points[1].y, 600)
    Questie, QuestieLoader = nil, nil
end)

test("far names: spawns within reach, nearest first; names with no known spawns after them", function()
    local hunt = {
        { questID = 1, objectives = { { index = 1, names = { "Skullsplitter Mystic" } } } }, -- spawns at y 600, 300
        { questID = 99, objectives = { { index = 1, names = { "Somewhere Mob" } } } }, -- no known spawns
    }
    local far, close = QP.FarNames(hunt, 1, 500, 500, 200)
    eq(table.concat(far, ","), "Skullsplitter Mystic,Somewhere Mob")
    eq(close, true, "a known spawn 100 yards off")
    far, close = QP.FarNames(hunt, 1, 500, 1000, 200)
    eq(table.concat(far, ","), "Somewhere Mob", "known spawns, none within reach: left out")
    eq(close, false)
    eq(#QP.FarNames(hunt, 2, 500, 500, 200), 1, "another continent")
end)

test("the nearest spawn is on the player's continent, and the bearing turns the right way", function()
    local here = { name = "here", continent = 1, x = 0, y = 30 }
    local far = { name = "far", continent = 1, x = 0, y = 90 }
    local elsewhere = { name = "other continent", continent = 2, x = 0, y = 1 }
    local p, dist = QP.Nearest({ far, elsewhere, here }, 1, 0, 0)
    eq(p.name, "here")
    eq(dist, 30)
    eq(QP.Nearest({ elsewhere }, 1, 0, 0), nil)
    local seen = {}
    QP.MarkSeen({ far, elsewhere, here }, 1, 0, 25, 40, seen, 7)
    eq(seen[here], 7, "5 yards away: been there")
    eq(seen[far], nil, "65 yards away")
    eq(seen[elsewhere], nil, "1 yard away, but on another continent")
    eq(QP.Nearest({ far, here }, 1, 0, 0, seen), far, "an emptied spawn is skipped")
    local function near(a, b) return math.abs(a - b) < 1e-9 end
    assert(near(QP.Bearing(0, 0, 10, 0, 0), 0), "due north while facing north: straight ahead")
    assert(near(QP.Bearing(0, 0, 0, 10, 0), math.pi / 2), "due west while facing north: to the left")
    assert(near(QP.Bearing(0, 0, 10, 0, math.pi / 2), -math.pi / 2), "north while facing west: to the right")
    assert(near(math.abs(QP.Bearing(0, 0, -10, 0, 0)), math.pi), "behind")
    local wrapped = QP.Bearing(0, 0, 0, -10, 3)
    assert(wrapped > -math.pi and wrapped <= math.pi, "kept within one turn, got " .. wrapped)
end)

test("candidates skip dead, tapped, friendly, secret and unwanted mobs; the target goes first", function()
    reset()
    local wanted = { ["Skullsplitter Mystic"] = true, ["Kobold Vermins"] = true }
    world.units = {
        nameplate1 = { name = "Skullsplitter Mystic", dead = true },
        nameplate2 = { name = "Skullsplitter Mystic", tapped = true },
        nameplate3 = { name = "Skullsplitter Mystic", friendly = true },
        nameplate4 = { name = SECRET },
        nameplate5 = { name = "Jungle Stalker" },
        nameplate6 = { name = "Skullsplitter Mystic" },
        nameplate7 = { name = "Kobold Vermin" },
        nameplate8 = { name = "Skullsplitter Mystic", target = true },
    }
    local plates = { "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5", "nameplate6",
        "nameplate7", "nameplate8", "nameplate9" }
    local units, names = QP.Candidates(wanted, plates)
    eq(table.concat(units, ","), "nameplate8,nameplate6,nameplate7")
    eq(names[3], "Kobold Vermin", "plural objective name")
end)

test("a mob in a fight, or whose combat state is secret, isn't fresh", function()
    reset()
    world.units = { nameplate1 = {}, nameplate2 = { fighting = true }, nameplate3 = { fighting = SECRET } }
    eq(QP.Fresh("nameplate1"), true)
    eq(QP.Fresh("nameplate2"), false)
    eq(QP.Fresh("nameplate3"), false)
end)

test("a press pings your target if it's free, and otherwise targets the next mob by name", function()
    eq(QP.Steps({}, {}), nil)
    local units = { "nameplate8", "nameplate6", "nameplate7" }
    local names = { "Skullsplitter Mystic", "Skullsplitter Mystic", "Venture Co. Geologist" }
    local keep = "/cleartarget [dead]\n/stopmacro [combat,harm,nodead]\n"

    local steps = QP.Steps(units, { nameplate6 = true }, {}, names, { "Far Mob" }, false)
    eq(#steps, 1, "no quest mob targeted: only a targeting step")
    eq(steps[1].ping, nil, "it pings nothing")
    eq(steps[1].text, keep .. "/cleartarget\n/targetexact Skullsplitter Mystic\n/cleartarget [dead]\n"
        .. "/targetexact [noexists] Venture Co. Geologist\n/cleartarget [dead]\n"
        .. "/targetexact [noexists] Far Mob\n/cleartarget [dead]",
        "in view first, skipping the quiet one's turn, then the far ones")

    steps = QP.Steps(units, {}, { nameplate8 = 8 }, names, {}, true, "Skullsplitter Mystic")
    eq(#steps, 2)
    eq(steps[1].ping, "nameplate8")
    eq(steps[1].text, "/tm [@target,harm,nodead] ~8\n/ping [@target,harm,nodead] 1", "mark and ping, no retarget")
    eq(steps[2].text, keep .. "/targetexact Skullsplitter Mystic\n/cleartarget [dead]\n"
        .. "/targetexact [noexists] Venture Co. Geologist\n/cleartarget [dead]",
        "then the next: the target isn't dropped when the next shares its name, so /targetexact moves on")

    steps = QP.Steps(units, { nameplate8 = true, nameplate6 = true, nameplate7 = true }, {}, names, {}, true)
    eq(#steps, 1)
    eq(steps[1].text, keep .. "/targetexact [noexists] Skullsplitter Mystic", "all pinged: keep a live target")

    local odd = QP.Steps({ "nameplate1", "nameplate2" }, {}, {}, { "Bad;Name", string.rep("x", 200) })
    eq(odd, nil, "a name a macro line can't carry gets no step")

    local many, manyNames = {}, {}
    for i = 11, 40 do
        many[#many + 1] = "nameplate" .. i
        manyNames[#manyNames + 1] = string.rep("y", QP.MAX_NAME - 2) .. i
    end
    steps = QP.Steps(many, {}, {}, manyNames)
    assert(#steps[1].text <= 255, "length " .. #steps[1].text)
end)

test("raid icons: your first choice, then the next free one; a marked mob keeps its own", function()
    local units = { "nameplate1", "nameplate2", "nameplate3", "nameplate4" }
    local marks = QP.PickMarks(units, { nameplate4 = true }, { nameplate2 = 8, party1 = 7 }, 8)
    eq(marks.nameplate1, 6, "skull on nameplate2 and cross on a party member: square")
    eq(marks.nameplate2, nil, "already wears the skull")
    eq(marks.nameplate3, 5)
    eq(marks.nameplate4, nil, "quiet: no press will ping it")
    eq(QP.PickMarks(units, {}, {}, 1).nameplate2, 8, "star first, then skull")
    eq(next(QP.PickMarks(units, {}, {}, 0)), nil, "no icon: no marks")
    local step = QP.Steps({ "nameplate1" }, {}, { nameplate1 = 8 }, { "Skullsplitter Mystic" }, {}, true)[1]
    assert(step.text:find("/tm [@target,harm,nodead] ~8\n/ping", 1, true), step.text)
end)

test("party needs travel as quest IDs and objective indexes, split under the message limit", function()
    eq(QP.EncodeNeeds({}, false)[1], "1S|", "needs nothing")
    local msgs = QP.EncodeNeeds({ { q = 33, need = { 1, 3 } }, { q = 60, need = { 2 } } }, true)
    eq(#msgs, 1)
    eq(msgs[1], "1R|33:1.3;60:2")
    local kind, needs = QP.DecodeNeeds(msgs[1])
    eq(kind, "R")
    eq(needs[33][1] and needs[33][3] and not needs[33][2], true)
    eq(needs[60][2], true)

    local many = {}
    for q = 10001, 10040 do many[#many + 1] = { q = q, need = { 1, 2, 3 } } end
    msgs = QP.EncodeNeeds(many, false)
    assert(#msgs > 1, "40 quests don't fit in one message")
    local seen = 0
    for i, m in ipairs(msgs) do
        assert(#m <= 255, "message " .. i .. " is " .. #m .. " bytes")
        local k, n = QP.DecodeNeeds(m)
        eq(k, i == 1 and "S" or "+")
        for _ in pairs(n) do seen = seen + 1 end
    end
    eq(seen, 40, "every quest arrives once")

    eq(QP.DecodeNeeds("2S|33:1"), nil, "another version")
    eq(QP.DecodeNeeds("1S|33:x"), nil, "malformed")
    eq(QP.DecodeNeeds("hello"), nil)
end)

---------------------------------------------------------------------------
-- The button, end to end through events and presses
---------------------------------------------------------------------------

local created = {}
-- Any field is another stub you can call or index, so Blizzard templates' pieces (TitleContainer, ...) and
-- methods the tests don't care about just work.
local newObject
newObject = function()
    return setmetatable({}, {
        __index = function(t, k)
            local v = newObject()
            rawset(t, k, v)
            return v
        end,
        __call = function() return newObject() end,
    })
end
function CreateFrame(_, name)
    local f = newObject()
    f.attrs, f.scripts, f.shown, f.events = {}, {}, true, {}
    f.SetAttribute = function(self, k, v)
        assert(not world.combat, "SetAttribute in combat")
        self.attrs[k] = v
    end
    f.GetAttribute = function(self, k) return self.attrs[k] end
    -- Only the secure button is protected; the arrow shows and hides at any time.
    f.Show = function(self)
        assert(not world.combat or self ~= created.QuestPingButton, "Show in combat")
        self.shown = true
    end
    f.Hide = function(self)
        assert(not world.combat or self ~= created.QuestPingButton, "Hide in combat")
        self.shown = false
    end
    f.IsShown = function(self) return self.shown end
    f.SetShown = function(self, v)
        if v then self:Show() else self:Hide() end
    end
    f.SetParent = function(self, p) self.parent = p end
    f.SetScript = function(self, k, fn) self.scripts[k] = fn end
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.CreateTexture = function()
        local t = newObject()
        t.SetRotation = function(self, r) self.rotation = r end
        return t
    end
    f.CreateFontString = function()
        local fs = newObject()
        fs.SetText = function(self, t) self.text = t end
        fs.SetShown = function(self, v) self.shown = v end
        return fs
    end
    created[#created + 1] = f
    if name then created[name] = f end
    return f
end
function SecureHandlerWrapScript(frame, script, _, pre)
    assert(script == "OnClick")
    frame.pre = assert(loadstring("local self = ...\n" .. pre))
end
UIParent = newObject()
local plateFrames = {}
C_NamePlate = {
    GetNamePlates = function() return {} end,
    GetNamePlateForUnit = function(u)
        if not world.units[u] then return nil end
        plateFrames[u] = plateFrames[u] or { unit = u }
        return plateFrames[u]
    end,
}
C_CVar = { GetCVarBool = function() return true end }
C_Timer = { NewTicker = function() end, After = function(_, fn) fn() end }
SlashCmdList = {}
UISpecialFrames = {}
function GetPlayerFacing() return 0 end
function IsInInstance() return false end

reset()
assert(loadfile("QuestPing/QuestPing.lua"))("QuestPing", ns)
local events = created[#created]
local function fire(event, ...) events.scripts.OnEvent(events, event, ...) end
assert(loadfile("QuestPing/Window.lua"))("QuestPing", ns)
assert(loadfile("QuestPing/Options.lua"))("QuestPing", ns) -- returns at once: no Settings API here
assert(loadfile("QuestPing/Minimap.lua"))("QuestPing", ns) -- returns at once: no LibDBIcon here

fire("PLAYER_LOGIN")
local b, arrow = created.QuestPingButton, nil
for _, f in ipairs(created) do
    if f ~= b and f ~= events and f.scripts.OnEvent == nil and not arrow then arrow = f end
end

-- The guide arrow (Guide.lua): its always-running clock frame and its own login.
assert(loadfile("QuestPing/Guide.lua"))("QuestPing", ns)
local guideClock, guideEvents = created[#created - 1], created[#created]
guideEvents.scripts.OnEvent(guideEvents, "PLAYER_LOGIN")

-- Party sync (Party.lua): its event frame and its own login.
assert(loadfile("QuestPing/Party.lua"))("QuestPing", ns)
local partyEvents = created[#created]
local function partyFire(event, ...) partyEvents.scripts.OnEvent(partyEvents, event, ...) end
partyFire("PLAYER_LOGIN")

-- A press: PreClick, the secure snippet (which may set attributes in combat, like the real restricted
-- environment), the macro it picked run line by line the way the game does, then PostClick. Returns the mob
-- the macro pinged, or nil. As seen in game: /ping pings only @target, and /target [@nameplateN] does nothing.
-- /targetexact Name takes the nearest unit of that name, dead ones too (here: the lowest nameplate number, then
-- units with no nameplate, the far ones); assumed, like the game's other target-by-name commands: with one of
-- that name already targeted, the next.
local function currentTarget()
    for unit, u in pairs(world.units) do
        if u.target then return unit end
    end
end

local function liveHostile(unit)
    local u = unit and world.units[unit]
    return u and not u.dead and not u.friendly
end

local function setTarget(unit)
    local target = currentTarget()
    if target == unit then return end
    if target then
        world.units[target].target = nil
        world.lastTarget = target
    end
    if unit then world.units[unit].target = true end
end

local function nearness(unit)
    local n = tonumber(unit:match("%d+")) or 0
    return unit:match("^nameplate") and n or 1000 + n
end

local function targetExact(name, target)
    local named = {}
    for unit, u in pairs(world.units) do
        if u.name == name then named[#named + 1] = unit end
    end
    table.sort(named, function(x, y) return nearness(x) < nearness(y) end)
    for i, unit in ipairs(named) do
        if unit == target then return named[i % #named + 1] end
    end
    return named[1]
end

local function runMacro(text)
    for line in text:gmatch("[^\n]+") do
        local target = currentTarget()
        if line == "/cleartarget [dead]" then
            if target and world.units[target].dead then setTarget(nil) end
        elseif line == "/cleartarget" then
            setTarget(nil)
        elseif line == "/targetlasttarget [noexists]" then
            if not target and world.lastTarget and world.units[world.lastTarget] then setTarget(world.lastTarget) end
        elseif line == "/stopmacro [combat,harm,nodead]" then
            if world.combat and liveHostile(target) then return nil end
        elseif line:match("^/targetexact ") then
            local noexists, name = line:match("^/targetexact (%[noexists%] )(.+)$")
            name = name or line:match("^/targetexact (.+)$")
            if not (noexists and target) then
                local unit = targetExact(name, target)
                if unit then setTarget(unit) end
            end
        elseif line:match("^/tm %[@target,harm,nodead%] ~%d$") then
            -- "~": only a mob with no icon; an icon is on one unit at a time, so it moves off any other.
            local icon = tonumber(line:match("(%d)$"))
            if liveHostile(target) and not world.units[target].icon then
                for _, u in pairs(world.units) do
                    if u.icon == icon then u.icon = nil end
                end
                world.units[target].icon = icon
                fire("RAID_TARGET_UPDATE")
            end
        elseif line == "/ping [@target,harm,nodead] 1" then
            if liveHostile(target) then return target end
        end
    end
end

local function press()
    local handle = { GetAttribute = function(_, k) return b.attrs[k] end,
        SetAttribute = function(_, k, v) b.attrs[k] = v end }
    b.scripts.PreClick(b)
    b.pre(handle)
    local pinged = b.attrs.macrotext and runMacro(b.attrs.macrotext)
    b.scripts.PostClick(b)
    return pinged
end

local function near(unit, fields)
    world.units[unit] = fields
    fire("NAME_PLATE_UNIT_ADDED", unit)
end

-- Takes every nameplate out of view and drops the target, so a test starts with nothing near.
local function clearPlates()
    for unit in pairs(world.units) do
        world.units[unit] = nil
        fire("NAME_PLATE_UNIT_REMOVED", unit)
    end
end

local MYSTIC, HUNTER, THROWER = "Skullsplitter Mystic", "Skullsplitter Hunter", "Skullsplitter Axe Thrower"

test("a press targets the next mob by name, the next marks and pings it", function()
    world.quests = { { id = 5, objectives = { kill(MYSTIC, 0, 10), kill(HUNTER, 0, 10), kill(THROWER, 0, 10) } } }
    world.group = "party"
    fire("QUEST_LOG_UPDATE")
    eq(b.shown, false, "nothing near")
    near("nameplate3", { name = MYSTIC })
    near("nameplate5", { name = HUNTER, fighting = true })
    near("nameplate7", { name = THROWER })
    eq(b.shown, true)
    eq(arrow.shown, false, "no arrow before a press marks a mob")

    eq(press(), nil, "the first press only targets")
    eq(currentTarget(), "nameplate3")
    eq(world.units.nameplate3.icon, nil, "not marked yet")
    eq(press(), "nameplate3", "the next marks and pings it")
    eq(arrow.parent.unit, "nameplate3", "arrow over the mob the press marked")
    eq(press(), nil)
    eq(currentTarget(), "nameplate7", "then on to the next free one, past the one fighting")
    eq(press(), "nameplate7")
    eq(arrow.parent.unit, "nameplate7", "the arrow follows your target")
    eq(press(), nil, "already pinged, and nameplate5 is fighting")
    eq(press(), nil, "presses go on cycling targets but never ping them again")
    eq(press(), nil)
    eq(#world.chat, 0, "the game says the ping in chat itself; QuestPing says nothing")
    eq(world.units.nameplate3.icon, 8, "skull on the first")
    eq(world.units.nameplate7.icon, 7, "cross on the next")
    eq(world.units.nameplate5.icon, nil, "a mob in a fight isn't marked")
end)

test("several mobs of one name: each target press takes the next of that name", function()
    clearPlates()
    near("nameplate14", { name = MYSTIC })
    near("nameplate15", { name = MYSTIC })
    eq(press(), nil)
    eq(press(), "nameplate14", "the nearest first")
    eq(press(), nil)
    eq(press(), "nameplate15", "then the next of that name")
    eq(press(), nil, "both pinged: a press goes on cycling them but never pings again")
    eq(press(), nil)
end)

test("in combat a press only targets and never pulls you off a live target; pings wait for the fight to end",
    function()
    clearPlates()
    world.group = "raid"
    near("nameplate9", { name = MYSTIC })
    near("nameplate10", { name = THROWER })
    world.combat = true
    eq(press(), nil, "no live target yet: it targets")
    eq(currentTarget(), "nameplate9")
    eq(press(), nil, "on a live target now: the press stops there")
    eq(currentTarget(), "nameplate9")
    eq(world.units.nameplate9.icon, nil)

    world.combat = false
    fire("PLAYER_REGEN_ENABLED")
    eq(press(), "nameplate9", "after the fight your target gets its ping")
    eq(press(), nil)
    eq(press(), "nameplate10")
    eq(press(), nil, "both pinged")
end)

test("pings wear off, and a mob that leaves and comes back stays pinged", function()
    fire("NAME_PLATE_UNIT_REMOVED", "nameplate9")
    near("nameplate9", { name = MYSTIC })
    eq(press(), nil)
    world.now = world.now + 601
    fire("PLAYER_TARGET_CHANGED")
    local again = press()
    assert(again ~= nil, "pinged again after it wore off")
end)

test("a mob too far for a nameplate: a press finds it by name and pings it", function()
    clearPlates()
    world.quests = { { id = 5, objectives = { kill(MYSTIC, 0, 10), kill(HUNTER, 0, 10) } } }
    fire("QUEST_LOG_UPDATE")
    world.units.far1 = { name = HUNTER } -- in sight, but past nameplate range: no NAME_PLATE_UNIT_ADDED
    fire("PLAYER_TARGET_CHANGED")
    eq(b.shown, false, "nothing in view, so no button; the key still works")
    eq(press(), nil, "found by name and targeted")
    eq(currentTarget(), "far1")
    eq(press(), "far1", "then pinged")
    eq(press(), nil, "pinged already: the press looks for the next and finds nothing")
    eq(currentTarget(), "far1", "so you keep the one you had")

    world.units.far5 = { name = MYSTIC, tapped = true }
    eq(press(), nil)
    eq(currentTarget(), "far5", "a tapped one can be found by name...")
    eq(press(), nil, "...but never pinged")
    world.units.far5 = nil

    near("nameplate30", { name = HUNTER, tapped = true })
    world.units.far6 = { name = HUNTER }
    local got
    for _ = 1, 6 do
        got = press()
        if got then break end
    end
    eq(got, "far6", "a tapped one in view doesn't hide a free one farther out")
    clearPlates()
    world.units.far1 = { name = HUNTER, target = true }

    near("nameplate4", { name = MYSTIC })
    eq(press(), nil)
    eq(press(), "nameplate4", "a mob in view comes first")

    clearPlates()
    world.units.far2 = { name = MYSTIC, target = true } -- you clicked it yourself
    fire("PLAYER_TARGET_CHANGED")
    assert(not b.attrs["qp-macro1"]:find("targetexact", 1, true), "your own target is pinged as it is")
    eq(press(), "far2")

    clearPlates()
    QuestPingDB.range = 28
    world.units.far3 = { name = HUNTER }
    ns.Refresh()
    eq(press(), nil, "with a Range set, far mobs are out of it")
    QuestPingDB.range = nil
    clearPlates()
    world.quests = { { id = 5, objectives = { kill(MYSTIC, 0, 10), kill(HUNTER, 0, 10), kill(THROWER, 0, 10) } } }
    fire("QUEST_LOG_UPDATE")
end)

test("the raid icon setting picks the icon, or none", function()
    clearPlates()
    QuestPingDB.chatIcon = 1
    near("nameplate11", { name = MYSTIC })
    eq(press(), nil)
    eq(press(), "nameplate11")
    eq(world.units.nameplate11.icon, 1)
    QuestPingDB.chatIcon = 0
    ns.Refresh()
    near("nameplate12", { name = THROWER })
    eq(press(), nil)
    eq(press(), "nameplate12")
    eq(world.units.nameplate12.icon, nil, "no icon: no mark")
    QuestPingDB.chatIcon = nil
end)

test("the button shows, dimmed, while a needed mob spawns within reach, nameplate or not", function()
    clearPlates()
    world.quests = { { id = 1, objectives = { kill(MYSTIC, 0, 10) } } } -- spawns 100 and 200 yards off
    fire("QUEST_LOG_UPDATE")
    eq(b.shown, true, "like Polestar's target button: there to click before any nameplate is up")
    world.py = 0.9 -- 300 yards from the nearest spawn
    fire("QUEST_LOG_UPDATE")
    eq(b.shown, false, "nowhere near")
    world.py = nil
    clearPlates()
end)

test("the window lists the hunted quest with how many of its mobs are near", function()
    clearPlates()
    world.quests = { { id = 1, objectives = { kill(MYSTIC, 0, 10) } } }
    fire("QUEST_LOG_UPDATE")
    near("nameplate13", { name = "Skullsplitter Mystic" })
    ns.ToggleWindow()
    local w = created.QuestPingWindow
    eq(w.shown, true)
    fire("PLAYER_TARGET_CHANGED")
    local row
    for _, f in ipairs(created) do
        if rawget(f, "Right") and rawget(f, "Title") then row = f end
    end
    assert(row, "a quest row")
    eq(row.Title.text, "Quest 1")
    assert(row.Right.text:find("1 near", 1, true), "near count, got " .. tostring(row.Right.text))
    assert(w.Status.text:find("1 quest", 1, true), w.Status.text)
    eq(w.Detail.Bar.Text.text, "0 / 10")
    ns.ToggleWindow()
    eq(w.shown, false)
end)

test("the guide arrow points at the nearest spawn until a needed mob is in view", function()
    clearPlates()
    fakeQuestie()
    world.quests = { { id = 1, objectives = { kill("Skullsplitter Mystic", 0, 10) } } }
    fire("QUEST_LOG_UPDATE")
    local g = created.QuestPingGuide
    guideClock.scripts.OnUpdate(guideClock, 1)
    eq(g.shown, false, "off unless turned on: a spawn is only a guess")
    QuestPingDB.spawnArrow = true
    guideClock.scripts.OnUpdate(guideClock, 1)
    eq(g.shown, true)
    assert(g.Text.text:find("Skullsplitter Mystic", 1, true) and g.Text.text:find("100 yd", 1, true), g.Text.text)
    assert(math.abs(g.Arrow.rotation - math.pi / 2) < 1e-9, "spawn is due west: arrow turns left")

    world.py = 0.55
    guideClock.scripts.OnUpdate(guideClock, 0.1)
    assert(g.Text.text:find("50 yd", 1, true), "the distance follows the player between picks: " .. g.Text.text)

    world.py = 0.59
    guideClock.scripts.OnUpdate(guideClock, 1)
    assert(g.Text.text:find("290 yd", 1, true), "an empty spawn sends it to the next: " .. g.Text.text)
    assert(math.abs(math.abs(g.Arrow.rotation) - math.pi / 2) < 1e-9, "the other spawn is due east")
    world.py = 0.5
    world.now = world.now + 301
    guideClock.scripts.OnUpdate(guideClock, 1)
    assert(g.Text.text:find("100 yd", 1, true), "back once it has respawned: " .. g.Text.text)

    near("nameplate20", { name = "Skullsplitter Mystic" })
    guideClock.scripts.OnUpdate(guideClock, 1)
    eq(g.shown, false, "the nameplate arrow takes over")

    clearPlates()
    QuestPingDB.spawnArrow = false
    guideClock.scripts.OnUpdate(guideClock, 1)
    eq(g.shown, false, "switched off")
    QuestPingDB.spawnArrow = nil
    Questie, QuestieLoader = nil, nil
end)

test("free quest mobs get a quest icon on their nameplate; ones in a fight don't", function()
    clearPlates()
    near("nameplate21", { name = "Skullsplitter Mystic" })
    near("nameplate22", { name = "Skullsplitter Mystic", fighting = true })
    local function marked()
        local list = {}
        for _, f in ipairs(created) do
            local plate = rawget(f, "plate")
            if f ~= arrow and plate and f.shown then
                list[#list + 1] = plate.unit
            end
        end
        table.sort(list)
        return table.concat(list, ",")
    end
    eq(marked(), "nameplate21")
    QuestPingDB.marks = false
    ns.Refresh()
    eq(marked(), "", "switched off")
    QuestPingDB.marks = nil
    clearPlates()
    ns.Refresh()
    eq(marked(), "", "gone with the plates")
end)

test("the range setting drops mobs farther than it; a range item the game hasn't loaded drops nothing", function()
    clearPlates()
    local yardsOf = {}
    for yards, item in pairs(QP.RANGE_ITEMS) do yardsOf[item] = yards end
    C_Item = { IsItemInRange = function(item, unit)
        local yards = world.units[unit].yards
        if yards == nil then return nil end
        return yards <= yardsOf[item]
    end }
    near("nameplate30", { name = "Skullsplitter Mystic", yards = 20 })
    near("nameplate31", { name = "Skullsplitter Mystic", yards = 40 })
    QuestPingDB.range = 28
    ns.Refresh()
    eq(#ns.state.shown, 1, "only the one within 28 yards")
    QuestPingDB.range = 0
    ns.Refresh()
    eq(#ns.state.shown, 2, "max: every nameplate")
    QuestPingDB.range = 28
    world.units.nameplate31.yards = nil
    ns.Refresh()
    eq(#ns.state.shown, 2, "no answer counts as in range")
    QuestPingDB.range, C_Item = nil, nil
    clearPlates()
end)

test("a mob you're done with stays hunted while a party member still needs it", function()
    clearPlates()
    world.quests = { { id = 1, objectives = { kill("Skullsplitter Mystic", 10, 10) } } }
    world.group = "party"
    world.addon = {}
    world.units.party1 = { name = "Ana", friendly = true }
    partyFire("GROUP_ROSTER_UPDATE")
    eq(world.addon[#world.addon], "PARTY QuestPing 1R|", "someone joined: ours (nothing) and a request for theirs")
    fire("QUEST_LOG_UPDATE")
    near("nameplate40", { name = "Skullsplitter Mystic" })
    eq(b.shown, false, "done, and nobody said they need it")

    partyFire("CHAT_MSG_ADDON", "QuestPing", "1S|1:1", "PARTY", "Ana")
    eq(b.shown, true, "Ana still needs objective 1")
    eq(ns.state.hunt[1].objectives[1].done, true, "done for you")
    eq(ns.state.hunt[1].objectives[1].party[1], "Ana")
    eq(press(), nil)
    eq(press(), "nameplate40")

    partyFire("CHAT_MSG_ADDON", "QuestPing", "1S|", "PARTY", "Ana")
    eq(b.shown, false, "Ana's done too")
    partyFire("CHAT_MSG_ADDON", "QuestPing", "1S|1:1", "PARTY", "Stranger")
    eq(b.shown, false, "only the group counts")

    partyFire("CHAT_MSG_ADDON", "QuestPing", "1S|1:1", "PARTY", "Ana")
    eq(b.shown, true)
    world.units.party1 = nil
    partyFire("GROUP_ROSTER_UPDATE")
    eq(b.shown, false, "Ana left: her needs go with her")
    world.group = nil
    clearPlates()
end)

test("a mob whose tooltip shows someone in the group short on its quest counts, drop items included", function()
    clearPlates()
    world.quests = { { id = 1, objectives = { kill(MYSTIC, 10, 10) } } }
    fire("QUEST_LOG_UPDATE")
    -- The game's own unit tooltip: quest title, then each player on it with their count (type 8 lines).
    C_TooltipInfo = { GetUnit = function(unit)
        local lines = world.units[unit] and world.units[unit].tooltip
        if lines == SECRET then return SECRET end
        return lines and { lines = lines } or nil
    end }
    local function objective(text, completed) return { type = 8, leftText = text, completed = completed } end
    near("nameplate50", { name = "Venture Co. Geologist", tooltip = {
        { type = 17, leftText = "Hostile Takeover" }, { type = 18, leftText = "Legs Behindhead" },
        objective("8/8 Tumbled Crystal", true), { type = 18, leftText = "Aewie Booty" },
        objective("5/8 Tumbled Crystal") } })
    near("nameplate51", { name = "Venture Co. Geologist", tooltip = { objective("8/8 Tumbled Crystal", true) } })
    near("nameplate52", { name = "Venture Co. Geologist", tooltip = SECRET })
    eq(#ns.state.shown, 1, "only the one a party member still needs (5/8, read from the count)")
    eq(press(), nil)
    eq(press(), "nameplate50", "and a press takes it")
    QuestPingDB.party = false
    ns.Refresh()
    eq(#ns.state.shown, 0, "Hunt for your party too: off")
    QuestPingDB.party, C_TooltipInfo = nil, nil
    clearPlates()
end)

test("dragging the button never lets it go in combat, and a drag without Shift never moved it", function()
    local stops, moves = 0, 0
    b.StartMoving = function() moves = moves + 1 end
    b.StopMovingOrSizing = function()
        assert(not world.combat, "StopMovingOrSizing in combat")
        stops = stops + 1
    end
    b.GetPoint = function() return "CENTER", nil, "CENTER", 10, 20 end
    world.combat = true
    b.scripts.OnDragStart(b)
    b.scripts.OnDragStop(b)
    eq(moves + stops, 0, "a drag in combat (with or without Shift) touches nothing")
    world.combat, world.shift = false, false
    b.scripts.OnDragStart(b)
    b.scripts.OnDragStop(b)
    eq(moves + stops, 0, "without Shift there's nothing to stop")
    world.shift = true
    b.scripts.OnDragStart(b)
    world.combat = true -- the fight starts mid-drag
    b.scripts.OnDragStop(b)
    eq(stops, 0)
    world.combat = false
    fire("PLAYER_REGEN_ENABLED")
    eq(stops, 1, "let go once the fight ends")
    eq(QuestPingDB.point[3], 10)
    world.shift, QuestPingDB.point = nil, nil
end)

test("finishing the objective hides the button", function()
    world.quests[1].objectives[1] = kill("Skullsplitter Mystic", 10, 10)
    fire("QUEST_LOG_UPDATE")
    eq(b.shown, false)
    eq(b.attrs.type, nil)
end)

test("the button setting: always keeps it up idle, never hides it but the key still works", function()
    QuestPingDB.button = "always"
    ns.Refresh()
    eq(b.shown, true, "idle but on screen to click and move")
    eq(b.attrs.type, nil, "a click with nothing near does nothing")

    world.quests[1].objectives[1] = kill("Skullsplitter Mystic", 0, 10)
    clearPlates()
    QuestPingDB.button = "never"
    world.combat = true
    ns.Refresh() -- changed mid-fight: nothing protected moves until it ends
    eq(b.shown, true)
    world.combat = false
    near("nameplate20", { name = "Skullsplitter Mystic" })
    fire("PLAYER_REGEN_ENABLED")
    eq(b.shown, false, "never shown")
    eq(press(), nil)
    eq(press(), "nameplate20", "the key binding's clicks still target and ping")

    QuestPingDB.button = nil
    ns.Refresh()
    eq(b.shown, true, "default: shown while a mob is near")
end)

print(("%d tests, %d failed"):format(count, failures))
os.exit(failures == 0 and 0 or 1)
