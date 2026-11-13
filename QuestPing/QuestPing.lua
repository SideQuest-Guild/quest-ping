-- QuestPing/QuestPing.lua
-- The button: shown while a quest mob you still need has a nameplate up (or always, or never: the "button"
-- setting). A press (a click, the key binding or "/click QuestPingButton") targets the next quest mob by name,
-- in view or too far for a nameplate, like Polestar's target button. Once it's your target QuestPing can see
-- whether it's free (not tapped, not in a fight, not pinged yet), and if so the next press marks and pings it.
-- A bouncing arrow sits over the nameplate of the mob you pinged, while it's your target.
--
-- TargetUnit and C_Ping.SendMacroPing are protected, so this is a SecureActionButton running macros the addon
-- writes (Logic.lua's QP.Steps): one per press, stored as qp-macro1..n. A secure snippet wrapped around the
-- click moves to the next one, so spamming works in combat too. The steps themselves, and Show/Hide, can only
-- change out of combat: in combat the button keeps the steps from the pull, and new ones go on at
-- PLAYER_REGEN_ENABLED. The button acts on the key's release (useOnKeyDown false, up clicks only) so each
-- press runs exactly once.

local _, ns = ...
local QP = ns.QP
local readable = QP.Readable

local TICK = 0.25 -- deaths, taps and pulls change without an event worth trusting; re-read the plates this often
local PINGED_FOR = 600 -- seconds a pinged mob stays pinged

-- Runs in the restricted environment before every click. In a fight with a live hostile target, put the next
-- fight macro in macrotext (QP.FightSteps: ping another mob and come back), wrapping around. Otherwise put
-- this press's step there and move on to the next, unless this is the last one, which repeats.
local FIGHTING = "[combat,harm,nodead]"
local NEXT_STEP = [[
    if self:GetAttribute("qp-fight1") and SecureCmdOptionParse("[combat,harm,nodead]") then
        local k = self:GetAttribute("qp-fstep") or 1
        if not self:GetAttribute("qp-fight" .. k) then
            k = 1
        end
        self:SetAttribute("macrotext", self:GetAttribute("qp-fight" .. k))
        self:SetAttribute("qp-fstep", k + 1)
    else
        local i = self:GetAttribute("qp-step") or 1
        self:SetAttribute("macrotext", self:GetAttribute("qp-macro" .. i))
        if self:GetAttribute("qp-macro" .. (i + 1)) then
            self:SetAttribute("qp-step", i + 1)
        end
    end
]]

local HUNT_EVERY = 8 -- ticks between quest log re-reads (a quest database can finish loading after us)

local plates = {} -- nameplate unit tokens in the order they came into view
local hunt, wanted, wantedDirty, ticks = {}, {}, true, 0
local pingedAt = {} -- GUID (or "plate:<unit>" when the GUID is secret) -> GetTime() of its ping
local pingByText = {} -- step macro -> the unit it pings
local stepDesc = {} -- step number -> what it does, for the button's label
local fightCount = 0
local stepCount = 0
local candidates = {} -- the units the steps were last worked out for

-- The tooltip check (QP.TooltipNeeds) per nameplate, kept a moment: reading a tooltip every tick is wasteful.
local TOOLTIP_FOR = 1 -- seconds
local tooltipAt, tooltipSays = {}, {}

local function partyNeeds(unit)
    local now = GetTime()
    if not tooltipAt[unit] or now - tooltipAt[unit] > TOOLTIP_FOR then
        tooltipAt[unit], tooltipSays[unit] = now, QP.TooltipNeeds(unit)
    end
    return tooltipSays[unit]
end
local appliedSig -- the units and pings the steps were written for
local shown = {} -- { name, quiet } per candidate, for the tooltip and the window
local button, arrow, secured

local BINDING = "CLICK QuestPingButton:LeftButton"
local BORDER, BORDER_HOVER = { 1, 0.82, 0, 0.45 }, { 1, 0.82, 0, 1 }

-- What the window (Window.lua) draws: the hunt (Logic.lua's QP.Hunt) and the candidates in view.
ns.state = { hunt = hunt, shown = shown }
ns.listeners = {}

local function say(msg)
    print("|cffffd200QuestPing|r: " .. msg)
end

local function enemyPlatesOn()
    return not (C_CVar and C_CVar.GetCVarBool) or C_CVar.GetCVarBool("nameplateShowEnemies")
end

local function pingKey(unit)
    return readable(UnitGUID(unit)) or ("plate:" .. unit)
end

local function removePlate(unit)
    for i = #plates, 1, -1 do
        if plates[i] == unit then
            table.remove(plates, i)
        end
    end
    pingedAt["plate:" .. unit] = nil
    tooltipAt[unit] = nil -- the token now belongs to another mob
end

-- The raid icon on a unit, if the game says (it can keep it secret).
local function iconOn(unit)
    local icon = GetRaidTargetIndex and readable(GetRaidTargetIndex(unit))
    return type(icon) == "number" and icon or nil
end

-- Raid icons on everyone in view now (nameplates, the target, the group): unit -> icon.
local function iconsInView()
    local icons = {}
    local function look(unit)
        if UnitExists(unit) then
            icons[unit] = iconOn(unit)
        end
    end
    for _, unit in ipairs(plates) do
        look(unit)
    end
    look("target")
    for i = 1, 4 do
        look("party" .. i)
    end
    return icons
end

-- Mobs not to ping: pinged already, or already fighting someone.
local function quietUnits(units)
    local now, quiet = GetTime(), {}
    for key, at in pairs(pingedAt) do
        if now - at > PINGED_FOR then
            pingedAt[key] = nil
        end
    end
    for _, unit in ipairs(units) do
        if pingedAt[pingKey(unit)] or not QP.Fresh(unit) then
            quiet[unit] = true
        end
    end
    return quiet
end

local function plateOf(unit)
    if not C_NamePlate.GetNamePlateForUnit then
        return nil
    end
    local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and type(p) == "table" and p or nil
end

-- Parents f to a nameplate (re-anchoring only when it's a different one) and shows it, or hides it.
local function attach(f, plate, point, relPoint, x, y)
    if not plate then
        f:Hide()
        f.plate = nil
        return
    end
    if f.plate ~= plate then
        f:SetParent(plate)
        f:ClearAllPoints()
        f:SetPoint(point, plate, relPoint, x, y)
        f.plate = plate
    end
    f:Show()
end

local function pointArrowAt(unit)
    attach(arrow, unit and QuestPingDB.arrow ~= false and plateOf(unit) or nil, "BOTTOM", "TOP", 0, 4)
end

local marks = {} -- quest icons on nameplates, reused

local function newMark()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(20, 20)
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(f)
    tex:SetAtlas("QuestObjective")
    return f
end

-- A quest icon beside the nameplate of every needed mob nobody has: not tapped (candidates never are) and not
-- in a fight. Pinged ones keep theirs; they're still free to take.
local function markFree(units)
    local n = 0
    if QuestPingDB.marks ~= false then
        for _, unit in ipairs(units) do
            local plate = QP.Fresh(unit) and plateOf(unit)
            if plate then
                n = n + 1
                marks[n] = marks[n] or newMark()
                attach(marks[n], plate, "RIGHT", "LEFT", 0, 0)
            end
        end
    end
    for i = n + 1, #marks do
        attach(marks[i], nil)
    end
end

local function applySteps(steps, near, fights)
    for i = 1, stepCount do
        button:SetAttribute("qp-macro" .. i, nil)
    end
    for i = 1, fightCount do
        button:SetAttribute("qp-fight" .. i, nil)
    end
    for text in pairs(pingByText) do
        pingByText[text] = nil
    end
    wipe(stepDesc)
    stepCount = steps and #steps or 0
    for i = 1, stepCount do
        button:SetAttribute("qp-macro" .. i, steps[i].text)
        stepDesc[i] = steps[i].desc
        if steps[i].ping then
            pingByText[steps[i].text] = steps[i].ping
        end
    end
    fightCount = fights and #fights or 0
    for i = 1, fightCount do
        button:SetAttribute("qp-fight" .. i, fights[i])
    end
    button:SetAttribute("qp-step", 1)
    button:SetAttribute("qp-fstep", 1)
    button:SetAttribute("type", (steps or fights) and "macro" or nil)
    button:SetAttribute("macrotext", steps and steps[1].text or nil)
    -- "near" (default): only while a mob is in view (the key also reaches far ones). "always": also idle,
    -- dimmed, so you can find, move and click it. "never": key binding only (a hidden button still takes its
    -- binding's clicks).
    local mode = QuestPingDB.button
    if mode == "always" or (mode ~= "never" and near) then
        button:Show()
    else
        button:Hide()
    end
end

local FAR_REACH = 300 -- yards: with a needed mob spawning this close, the button is up before any nameplate
-- Targeting presses through mobs of one name that aren't free: the name, the mobs (GUIDs) it has reached, and
-- whether it has come back around to one, so the next press tries the other names first (QP.Steps' moveOn).
local cycle = { name = nil, seen = {}, moveOn = false }

-- Your target's name when it's a mob you're hunting, in any state (tapped, pinged, fighting), or one only
-- your party still needs.
local function huntedTargetName()
    if not (UnitExists("target") and UnitCanAttack("player", "target")) then
        return nil
    end
    local name = readable((UnitName("target")))
    local party = QuestPingDB.party ~= false and partyNeeds("target")
    return name and (QP.Matches(wanted, name) or party) and name or nil
end

-- Whether someone in your group is on a quest (C_QuestLog.IsUnitOnQuest), kept a few seconds per quest.
local GROUP_FOR = 5 -- seconds
local groupAt, groupSays = {}, {}

local function groupOn(questID)
    if QuestPingDB.party == false or not (IsInGroup() and C_QuestLog.IsUnitOnQuest) then
        return false
    end
    local now = GetTime()
    if groupAt[questID] and now - groupAt[questID] <= GROUP_FOR then
        return groupSays[questID]
    end
    local on = false
    local raid = IsInRaid()
    for i = 1, raid and GetNumGroupMembers() or GetNumSubgroupMembers() do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) and not readable(UnitIsUnit(unit, "player")) then
            local ok, yes = pcall(C_QuestLog.IsUnitOnQuest, unit, questID)
            if ok and readable(yes) then
                on = true
                break
            end
        end
    end
    groupAt[questID], groupSays[questID] = now, on
    return on
end

local function refresh()
    if not secured then
        return
    end
    ticks = ticks + 1
    if wantedDirty or ticks >= HUNT_EVERY then
        hunt = QP.Hunt(QuestPingDB.sources ~= false, ns.PartyNeeds and ns.PartyNeeds() or nil)
        wanted, wantedDirty, ticks = QP.WantedNames(hunt), false, 0
    end
    local range = tonumber(QuestPingDB.range)
    local units, names = QP.Candidates(wanted, plates, range, QuestPingDB.party ~= false and partyNeeds or nil)
    candidates = units
    -- Your target first: a quest mob you have targeted is the one the next press pings. Farther mobs are
    -- looked for by name like Polestar's target button does, nearest known spawn first; with a Range set
    -- they're out of it by definition.
    local first = units[1]
    local onQuestMob = first and (first == "target" or readable(UnitIsUnit(first, "target"))) and true or false
    local far, close = {}, false
    if not range or range == 0 then
        local continent, px, py = ns.PlayerWorldPosition()
        far, close = QP.FarNames(hunt, continent, px, py, FAR_REACH, groupOn)
    end
    local targetName = huntedTargetName()
    local quiet = quietUnits(units)
    local icons = iconsInView()
    local raidMarks = QP.PickMarks(units, quiet, icons, tonumber(QuestPingDB.chatIcon) or 8)

    local nextUnit, nextName, pressedFor
    local sig = {}
    shown = {}
    for i, unit in ipairs(units) do
        shown[i] = { name = names[i], quiet = quiet[unit] }
        if not quiet[unit] and not nextUnit then
            nextUnit, nextName = unit, names[i]
        end
        sig[i] = unit .. (quiet[unit] and "*" or "") .. ":" .. (raidMarks[unit] or "")
    end
    -- The mob a press got: your target, if it's one you need and QuestPing pinged it.
    if onQuestMob and pingedAt[pingKey(first)] then
        pressedFor = first
    end
    local fallbackLabel = nextName or far[1] or names[1] or ""
    button.Count:SetText(#names > 1 and tostring(#names) or "")
    button.Icon:SetDesaturated(nextUnit == nil)
    button:SetAlpha(nextUnit and 1 or 0.5)
    pointArrowAt(pressedFor)
    markFree(units)
    ns.state.hunt, ns.state.shown = hunt, shown
    for _, fn in ipairs(ns.listeners) do
        fn()
    end

    -- Your mob, for the fight macros: any live hostile target, quest mob or not; and how many other free mobs
    -- of its name are in view.
    local fighting = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
        and readable((UnitName("target"))) or nil
    local pack = 0
    for i, unit in ipairs(units) do
        if names[i] == fighting and not quiet[unit] and not (onQuestMob and i == 1) then
            pack = pack + 1
        end
    end
    sig = (targetName or "") .. "/" .. (fighting or "") .. pack .. (onQuestMob and "T|" or "|")
        .. table.concat(sig, ",") .. "|" .. table.concat(far, ",") .. "|" .. tostring(cycle.moveOn) .. tostring(close)
    if sig ~= appliedSig and not InCombatLockdown() then
        local steps, chain = QP.Steps(units, quiet, raidMarks, names, far, onQuestMob, targetName, cycle.moveOn)
        applySteps(steps, #units > 0 or close, QP.FightSteps(fighting, pack, chain))
        appliedSig = sig
    end
    -- What the next press does: in a fight on a live mob, ping another and come back; else the next step.
    local label
    if fightCount > 0 and SecureCmdOptionParse(FIGHTING) then
        label = "Ping another, then back"
    else
        label = stepDesc[button:GetAttribute("qp-step") or 1]
    end
    button.Label:SetText(label or fallbackLabel)
end

--- Re-read everything now and rewrite the steps: a setting changed (Options.lua) or the window opened.
function ns.Refresh()
    wantedDirty, appliedSig = true, nil
    refresh()
end

-- After a press: whichever mob the macro got targeted counts as pinged (the ping goes to the target, and
-- /targetexact takes the nearest of a name, which may not be the one the step was written for). The game says
-- the ping in chat itself ("Attack: <mob>"), so QuestPing says nothing. A step that stopped (in combat, on
-- your own live target) leaves it for later.
local presses, lastRan, pressing = 0, nil, false -- for /questping status and ping errors
local running = {} -- the step this press runs: its text, and whether it pings

-- Before the click: read the step now, since targeting mid-macro rewrites the steps (PLAYER_TARGET_CHANGED).
local function beforeClick(self)
    pressing = true
    running.fight = fightCount > 0 and SecureCmdOptionParse(FIGHTING) and true or false
    local text
    if running.fight then
        local k = self:GetAttribute("qp-fstep") or 1
        text = self:GetAttribute("qp-fight" .. k) or self:GetAttribute("qp-fight1")
    else
        text = self:GetAttribute("qp-macro" .. (self:GetAttribute("qp-step") or 1))
    end
    running.text, running.pings = text, not running.fight and text and pingByText[text] ~= nil
end

local function afterClick()
    pressing = false
    presses, lastRan = presses + 1, running.text
    if running.fight then
        -- Pinged blind and back on your mob: nothing to note (the macros stay as they were at the pull).
        refresh()
        return
    end
    if running.pings then
        refresh() -- the candidates as they are now: a far mob the press found counts as "target" only now
        for _, unit in ipairs(candidates) do
            if UnitExists(unit) and readable(UnitIsUnit(unit, "target")) and not UnitIsDead(unit) then
                local key = pingKey(unit)
                pingedAt[key] = pingedAt[key] or GetTime()
                break
            end
        end
        -- Done with this one: the next press tries the other names first (the same name still comes last).
        wipe(cycle.seen)
        cycle.name, cycle.moveOn = huntedTargetName(), true
        local guid = cycle.name and readable(UnitGUID("target"))
        if guid then
            cycle.seen[guid] = true
        end
    else
        -- A targeting press: note where it landed, to tell when a name has come back around.
        local name = huntedTargetName()
        local guid = name and readable(UnitGUID("target"))
        if name ~= cycle.name then
            cycle.name, cycle.moveOn = name, false
            wipe(cycle.seen)
        end
        if name and guid then
            if cycle.seen[guid] then
                cycle.moveOn = true
            end
            cycle.seen[guid] = true
        end
    end
    refresh()
end

local dragging, stopOwed = false, false

-- Ends a shift-drag of the button and saves where it landed; in combat, once the fight ends.
local function stopDragging()
    if InCombatLockdown() then
        stopOwed = true
        return
    end
    stopOwed = false
    button:StopMovingOrSizing()
    local p, _, rp, x, y = button:GetPoint()
    QuestPingDB.point = { p, rp, x, y }
end

local function placeButton()
    local p = QuestPingDB.point
    button:ClearAllPoints()
    if p then
        button:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        button:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

local function createArrow()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(28, 28)
    f:Hide()
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(f)
    tex:SetAtlas("NPE_ArrowDown")
    local bounce = f:CreateAnimationGroup()
    bounce:SetLooping("BOUNCE")
    local move = bounce:CreateAnimation("Translation")
    move:SetOffset(0, 10)
    move:SetDuration(0.45)
    move:SetSmoothing("IN_OUT")
    bounce:Play()
    return f
end

local function paintBorder(b, color)
    for _, edge in ipairs(b.Border) do
        edge:SetColorTexture(color[1], color[2], color[3], color[4])
    end
end

-- The key bound to the button, short form ("S-F", "M4"), in its top-left corner like an action button.
local function refreshHotkey()
    local key = GetBindingKey and GetBindingKey(BINDING)
    button.Hotkey:SetText(key and (GetBindingText and GetBindingText(key, true) or key) or "")
end

-- Looks like Polestar's quest buttons: dark square, thin gold edge that lights on hover, the key in the
-- corner, how many are near in the other, and the next mob's name beside it.
local function createButton()
    local b = CreateFrame("Button", "QuestPingButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(36, 36)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:RegisterForDrag("LeftButton")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.85)

    b.Border = {}
    for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
        { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local edge = b:CreateTexture(nil, "BORDER")
        edge:SetPoint(side[1])
        edge:SetPoint(side[2])
        if i <= 2 then
            edge:SetHeight(1)
        else
            edge:SetWidth(1)
        end
        b.Border[i] = edge
    end
    paintBorder(b, BORDER)

    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetPoint("TOPLEFT", 2, -2)
    b.Icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.Icon:SetAtlas("Ping_Map_Whole_Attack")

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.Icon)
    hl:SetColorTexture(1, 1, 1, 0.12)

    local pushed = b:CreateTexture(nil, "OVERLAY")
    pushed:SetAllPoints(b.Icon)
    pushed:SetColorTexture(0, 0, 0, 0.35)
    b:SetPushedTexture(pushed)

    b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.Count:SetPoint("BOTTOMRIGHT", -2, 2)

    b.Hotkey = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.Hotkey:SetPoint("TOPLEFT", 3, -3)
    b.Hotkey:SetTextColor(0.75, 0.75, 0.75)

    b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.Label:SetPoint("LEFT", b, "RIGHT", 6, 0)
    b:SetScript("PreClick", beforeClick)
    b:SetScript("PostClick", afterClick)
    b:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" and ns.ToggleWindow then
            ns.ToggleWindow()
        end
    end)
    -- A drag without Shift never moved it, so there's nothing to stop; one that runs into a fight is let go
    -- when the fight ends (the game blocks moving the button in combat).
    b:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then
            dragging = true
            self:StartMoving()
        end
    end)
    b:SetScript("OnDragStop", function()
        if dragging then
            dragging = false
            stopDragging()
        end
    end)
    b:SetScript("OnEnter", function(self)
        paintBorder(self, BORDER_HOVER)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("QuestPing")
        for _, s in ipairs(shown) do
            if s.quiet then
                GameTooltip:AddLine(s.name .. " (pinged or fighting)", 0.6, 0.6, 0.6)
            else
                GameTooltip:AddLine(s.name, 1, 1, 1)
            end
        end
        if #shown == 0 then
            GameTooltip:AddLine("No quest mob near.", 1, 1, 1)
        end
        GameTooltip:AddLine("Click to target the next one, again to ping it. Right-click for the window. "
            .. "Shift-drag to move.",
            0.6, 0.6, 0.6, true)
        if self.Hotkey:GetText() == "" then
            GameTooltip:AddLine("Or bind a key: Options > AddOns > QuestPing.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        paintBorder(self, BORDER)
        GameTooltip:Hide()
    end)
    return b
end

-- The protected half: attributes, click registration and the step snippet. Out of combat only, so a /reload
-- mid-fight waits for the fight to end.
local function secure()
    if secured or InCombatLockdown() then
        return
    end
    button:RegisterForClicks("LeftButtonUp") -- right-click opens the window instead (OnMouseUp)
    button:SetAttribute("useOnKeyDown", false)
    local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    SecureHandlerWrapScript(button, "OnClick", header, NEXT_STEP)
    button:Hide()
    secured = true
    refresh()
end

local handlers = {}

function handlers.PLAYER_LOGIN()
    QuestPingDB = QuestPingDB or {}
    button = createButton()
    arrow = createArrow()
    placeButton()
    refreshHotkey()
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken
        if unit then
            removePlate(unit)
            plates[#plates + 1] = unit
        end
    end
    if not enemyPlatesOn() then
        say("enemy nameplates are off, so no quest mob counts as near. Type /questping plates to turn them on.")
    end
    -- The range items answer only once the game has their data (QP.InRange counts an unloaded one as in range).
    if C_Item and C_Item.RequestLoadItemDataByID then
        for _, item in pairs(QP.RANGE_ITEMS) do
            pcall(C_Item.RequestLoadItemDataByID, item)
        end
    end
    secure()
    C_Timer.NewTicker(TICK, refresh)
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
    removePlate(unit)
    plates[#plates + 1] = unit
    refresh()
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
    removePlate(unit)
    refresh()
end

function handlers.QUEST_LOG_UPDATE()
    wantedDirty = true
    refresh()
end

function handlers.UNIT_QUEST_LOG_CHANGED(unit)
    if unit == "player" then
        handlers.QUEST_LOG_UPDATE()
    end
end

-- Fires just before the game locks the button for the fight: a last chance to write the fight macros for the
-- mob you're on.
handlers.PLAYER_REGEN_DISABLED = refresh

function handlers.PLAYER_REGEN_ENABLED()
    if button then
        secure()
        if stopOwed then
            stopDragging()
        end
    end
    refresh()
end

function handlers.PLAYER_TARGET_CHANGED()
    tooltipAt.target = nil -- the "target" unit is someone else now
    refresh()
end
handlers.RAID_TARGET_UPDATE = refresh -- an icon went on or came off: the next mob gets the next free one

function handlers.UPDATE_BINDINGS()
    if button then
        refreshHotkey()
    end
end

-- The game says why a ping didn't go out (pings off, too many, out of range) only as a flash at the top of the
-- screen; for one of our presses, say it in chat too. It fires while the press's macro runs.
function handlers.PING_SYSTEM_ERROR(err)
    if pressing then
        say("the game didn't send the ping: " .. tostring(readable(err) or "no reason given") .. ".")
    end
end

local events = CreateFrame("Frame")
for event in pairs(handlers) do
    -- An event the client doesn't know throws on Forever instead of being ignored.
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

BINDING_HEADER_QUESTPING = "QuestPing"
_G["BINDING_NAME_CLICK QuestPingButton:LeftButton"] = "Target, then ping, the next quest mob"
BINDING_NAME_QUESTPING_WINDOW = "Show or hide the QuestPing window"

--- Put the button back where it starts (Options.lua's reset; the window resets itself).
function ns.ResetButton()
    if InCombatLockdown() then
        say("not in combat.")
        return
    end
    QuestPingDB.point = nil
    placeButton()
end

local function printStatus()
    ns.Refresh()
    local list = {}
    for name in pairs(wanted) do
        list[#list + 1] = name
    end
    table.sort(list)
    say("hunting " .. (#list > 0 and table.concat(list, ", ") or "nothing (no unfinished objectives with known mobs)")
        .. ".")
    local near = {}
    for _, s in ipairs(shown) do
        near[#near + 1] = s.name .. (s.quiet and " (pinged or fighting)" or "")
    end
    say(#near > 0 and ("near: " .. table.concat(near, ", ") .. ".") or "none near.")
    if not enemyPlatesOn() then
        say("enemy nameplates are off: /questping plates turns them on.")
    end
    -- What a press does and whether the game will ping, for "it didn't ping" reports.
    local key = GetBindingKey and GetBindingKey(BINDING)
    say("key: " .. (key or "none bound") .. "; presses since login: " .. presses .. ".")
    if lastRan then
        say("last press ran: " .. lastRan:gsub("\n", " | "))
    end
    local nextText
    if fightCount > 0 and SecureCmdOptionParse(FIGHTING) then
        nextText = button:GetAttribute("qp-fight" .. (button:GetAttribute("qp-fstep") or 1))
            or button:GetAttribute("qp-fight1")
    else
        nextText = button:GetAttribute("qp-macro" .. (button:GetAttribute("qp-step") or 1))
    end
    say("next press runs: " .. (nextText and nextText:gsub("\n", " | ") or "nothing (no quest mob to look for)"))
    local function cvar(name)
        return C_CVar and C_CVar.GetCVar and tostring(C_CVar.GetCVar(name)) or "?"
    end
    local system = C_Ping and C_Ping.IsPingSystemEnabled and tostring(C_Ping.IsPingSystemEnabled()) or "no C_Ping"
    say(("pings: system %s, enablePings %s, ping sounds %s, ping volume %s."):format(system, cvar("enablePings"),
        cvar("Sound_EnablePingSounds"), cvar("Sound_PingVolume")))
end

SLASH_QUESTPING1 = "/questping"
SlashCmdList.QUESTPING = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "plates" then
        if InCombatLockdown() then
            say("not in combat.")
        else
            C_CVar.SetCVar("nameplateShowEnemies", "1")
            say("enemy nameplates on.")
        end
    elseif msg == "options" or msg == "settings" or msg == "config" then
        if ns.OpenOptions then
            ns.OpenOptions()
        end
    elseif msg == "status" then
        printStatus()
    elseif msg == "reset" then
        ns.ResetButton()
        if ns.ResetWindow then
            ns.ResetWindow()
        end
    elseif msg == "" and ns.ToggleWindow then
        ns.ToggleWindow()
    else
        say("/questping opens the window; /questping options, status, plates, reset.")
    end
end
