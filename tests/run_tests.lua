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
    world = { units = {}, quests = {}, combat = false, group = nil, chat = {}, now = 100 }
end
reset()

QUEST_MONSTERS_KILLED = "%2$d/%3$d %1$s slain"
function issecretvalue(v) return v == SECRET end
function UnitExists(u) return world.units[u] ~= nil end
function UnitCanAttack(_, u) return not world.units[u].friendly end
function UnitIsDead(u) return world.units[u].dead or false end
function UnitIsTapDenied(u) return world.units[u].tapped or false end
function UnitAffectingCombat(u) return world.units[u].fighting or false end
function UnitName(u) return world.units[u].name end
function UnitGUID(u) return world.units[u].guid or ("Creature-" .. u) end
function UnitIsUnit(u, other)
    return other == "target" and world.units[u].target or false
end
function InCombatLockdown() return world.combat end
function GetTime() return world.now end
function IsInRaid() return world.group == "raid" end
function IsInGroup() return world.group ~= nil end
C_ChatInfo = { SendChatMessage = function(msg, channel) world.chat[#world.chat + 1] = channel .. ": " .. msg end }
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

test("one ping step per mob not quiet, then a target-only step; all under the length cap", function()
    eq(QP.Steps({}, {}), nil)
    local steps = QP.Steps({ "nameplate8", "nameplate6", "nameplate7" }, { nameplate6 = true })
    eq(#steps, 3)
    eq(steps[1].ping, "nameplate8")
    eq(steps[2].ping, "nameplate7", "quiet mob skipped")
    eq(steps[3].ping, nil)
    local targeting = "/stopmacro [combat,@target,harm,nodead]\n"
        .. "/target [@nameplate8,harm,nodead][@nameplate6,harm,nodead][@nameplate7,harm,nodead]"
    eq(steps[1].text, "/cleartarget [dead]\n/ping [@nameplate8,harm,nodead] 1\n" .. targeting)
    eq(steps[3].text, "/cleartarget [dead]\n" .. targeting)

    local many = {}
    for i = 11, 40 do many[#many + 1] = "nameplate" .. i end
    steps = QP.Steps(many, {})
    eq(#steps, QP.MAX_PINGS + 1)
    for _, s in ipairs(steps) do
        assert(#s.text <= QP.MACRO_LIMIT, "length " .. #s.text)
        assert(s.text:find("/target [@nameplate11,", 1, true), "keeps the first plate")
    end
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
C_Timer = { NewTicker = function() end }
SlashCmdList = {}
UISpecialFrames = {}

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

-- A press: the secure snippet (which may set attributes in combat, like the real restricted environment),
-- then the macro it picked, then PostClick. Returns the mob the macro pinged, or nil.
local function press()
    local handle = { GetAttribute = function(_, k) return b.attrs[k] end,
        SetAttribute = function(_, k, v) b.attrs[k] = v end }
    b.pre(handle)
    local pinged = b.attrs.macrotext and b.attrs.macrotext:match("/ping %[@(nameplate%d+),")
    b.scripts.PostClick(b)
    return pinged
end

local function near(unit, fields)
    world.units[unit] = fields
    fire("NAME_PLATE_UNIT_ADDED", unit)
end

test("each press pings the next mob once, says it in party, then only targets", function()
    world.quests = { { id = 1, objectives = { kill("Skullsplitter Mystic", 0, 10) } } }
    world.group = "party"
    fire("QUEST_LOG_UPDATE")
    eq(b.shown, false, "nothing near")
    near("nameplate3", { name = "Skullsplitter Mystic" })
    near("nameplate5", { name = "Skullsplitter Mystic", fighting = true })
    near("nameplate7", { name = "Skullsplitter Mystic" })
    eq(b.shown, true)
    eq(arrow.parent and arrow.parent.unit, "nameplate3", "arrow over the next mob")

    eq(press(), "nameplate3")
    eq(arrow.parent.unit, "nameplate7")
    eq(press(), "nameplate7")
    eq(arrow.shown, false, "nothing left to ping")
    eq(press(), nil, "already pinged, and nameplate5 is fighting")
    eq(press(), nil)
    eq(table.concat(world.chat, "|"), "PARTY: {rt8} Skullsplitter Mystic here|PARTY: {rt8} Skullsplitter Mystic here")
    eq(b.Label.text, "Skullsplitter Mystic")
end)

test("spamming in combat walks the steps from the pull, then they catch up after", function()
    world.chat = {}
    world.group = "raid"
    near("nameplate9", { name = "Skullsplitter Mystic" })
    near("nameplate10", { name = "Skullsplitter Mystic" })
    world.combat = true
    eq(press(), "nameplate9")
    world.units.nameplate10.fighting = true -- pulled by someone else after the pull's steps were written
    eq(press(), "nameplate10", "the step was written before the pull")
    eq(press(), nil)
    eq(table.concat(world.chat, "|"), "RAID: {rt8} Skullsplitter Mystic here", "no call-out for a mob in a fight")

    world.units.nameplate10.fighting = false
    world.combat = false
    fire("PLAYER_REGEN_ENABLED")
    eq(press(), nil, "both counted as pinged")
end)

test("pings wear off, and a mob that leaves and comes back stays pinged", function()
    fire("NAME_PLATE_UNIT_REMOVED", "nameplate9")
    near("nameplate9", { name = "Skullsplitter Mystic" })
    eq(press(), nil)
    world.now = world.now + 601
    fire("PLAYER_TARGET_CHANGED")
    local again = press()
    assert(again ~= nil, "pinged again after it wore off")
end)

-- Takes every nameplate out of view, so a test starts with nothing near.
local function clearPlates()
    for unit in pairs(world.units) do
        world.units[unit] = nil
        fire("NAME_PLATE_UNIT_REMOVED", unit)
    end
end

test("the chat icon setting picks the raid icon, or none", function()
    clearPlates()
    world.chat = {}
    QuestPingDB.chatIcon = 1
    near("nameplate11", { name = "Skullsplitter Mystic" })
    eq(press(), "nameplate11")
    QuestPingDB.chatIcon = 0
    near("nameplate12", { name = "Skullsplitter Mystic" })
    eq(press(), "nameplate12")
    eq(table.concat(world.chat, "|"), "RAID: {rt1} Skullsplitter Mystic here|RAID: Skullsplitter Mystic here")
    QuestPingDB.chatIcon = nil
end)

test("the window lists the hunted quest with how many of its mobs are near", function()
    clearPlates()
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

test("finishing the objective hides the button", function()
    world.quests[1].objectives[1] = kill("Skullsplitter Mystic", 10, 10)
    fire("QUEST_LOG_UPDATE")
    eq(b.shown, false)
    eq(b.attrs.type, nil)
end)

print(("%d tests, %d failed"):format(count, failures))
os.exit(failures == 0 and 0 or 1)
