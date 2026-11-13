-- QuestPing/QuestPing.lua
-- The button: shown while a quest mob you still need has a nameplate up. Each press (a click, the key binding
-- or "/click QuestPingButton") pings the next mob not pinged yet and says its name in party or raid chat; once
-- every one is pinged, presses only target. Mobs already in a fight (with you or anyone) are never pinged or
-- called out. A bouncing arrow sits over the nameplate of the next mob a press will ping.
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

-- Runs in the restricted environment before every click: put this press's step in macrotext, then move on to
-- the next unless this is the last one, which repeats.
local NEXT_STEP = [[
    local i = self:GetAttribute("qp-step") or 1
    self:SetAttribute("macrotext", self:GetAttribute("qp-macro" .. i))
    if self:GetAttribute("qp-macro" .. (i + 1)) then
        self:SetAttribute("qp-step", i + 1)
    end
]]

local HUNT_EVERY = 8 -- ticks between quest log re-reads (a quest database can finish loading after us)

local plates = {} -- nameplate unit tokens in the order they came into view
local hunt, wanted, wantedDirty, ticks = {}, {}, true, 0
local pingedAt = {} -- GUID (or "plate:<unit>" when the GUID is secret) -> GetTime() of its ping
local pingByText = {} -- step macro -> the unit it pings
local stepCount = 0
local appliedSig -- the units and pings the steps were written for
local shown = {} -- { name, quiet } per candidate, for the tooltip and the window
local button, arrow, secured

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
end

local function announce(name)
    if not name or QuestPingDB.chat == false then
        return
    end
    local channel = (IsInRaid() and "RAID") or (IsInGroup() and "PARTY") or nil
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage
    if channel and send then
        -- {rt1}..{rt8} are the raid icons (8 is the skull); every client draws them in chat
        -- (ICON_TAG_RAID_TARGET_SKULL1 and the like). 0 sends no icon.
        local icon = tonumber(QuestPingDB.chatIcon) or 8
        local prefix = (icon >= 1 and icon <= 8) and ("{rt" .. icon .. "} ") or ""
        pcall(send, prefix .. name .. " here", channel)
    end
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

local function pointArrowAt(unit)
    local plate
    if unit and QuestPingDB.arrow ~= false and C_NamePlate.GetNamePlateForUnit then
        local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        plate = ok and type(p) == "table" and p or nil
    end
    if not plate then
        arrow:Hide()
        arrow.plate = nil
        return
    end
    if arrow.plate ~= plate then
        arrow:SetParent(plate)
        arrow:ClearAllPoints()
        arrow:SetPoint("BOTTOM", plate, "TOP", 0, 4)
        arrow.plate = plate
    end
    arrow:Show()
end

local function applySteps(steps)
    for i = 1, stepCount do
        button:SetAttribute("qp-macro" .. i, nil)
    end
    for text in pairs(pingByText) do
        pingByText[text] = nil
    end
    stepCount = steps and #steps or 0
    for i = 1, stepCount do
        button:SetAttribute("qp-macro" .. i, steps[i].text)
        if steps[i].ping then
            pingByText[steps[i].text] = steps[i].ping
        end
    end
    button:SetAttribute("qp-step", 1)
    button:SetAttribute("type", steps and "macro" or nil)
    button:SetAttribute("macrotext", steps and steps[1].text or nil)
    if steps then
        button:Show()
    else
        button:Hide()
    end
end

local function refresh()
    if not secured then
        return
    end
    ticks = ticks + 1
    if wantedDirty or ticks >= HUNT_EVERY then
        hunt = QP.Hunt(QuestPingDB.sources ~= false)
        wanted, wantedDirty, ticks = QP.WantedNames(hunt), false, 0
    end
    local units, names = QP.Candidates(wanted, plates)
    local quiet = quietUnits(units)

    local nextUnit, nextName
    local sig = {}
    shown = {}
    for i, unit in ipairs(units) do
        shown[i] = { name = names[i], quiet = quiet[unit] }
        if not quiet[unit] and not nextUnit then
            nextUnit, nextName = unit, names[i]
        end
        sig[i] = unit .. (quiet[unit] and "*" or "")
    end
    button.Label:SetText(nextName or names[1] or "")
    button.Count:SetText(#names > 1 and tostring(#names) or "")
    button.Icon:SetDesaturated(nextUnit == nil)
    pointArrowAt(nextUnit)
    ns.state.hunt, ns.state.shown = hunt, shown
    for _, fn in ipairs(ns.listeners) do
        fn()
    end

    sig = table.concat(sig, ",")
    if sig == appliedSig or InCombatLockdown() then
        return
    end
    applySteps(QP.Steps(units, quiet))
    appliedSig = sig
end

--- Re-read everything now: a setting changed (Options.lua) or the window opened.
function ns.Refresh()
    wantedDirty = true
    refresh()
end

-- After a press: the step's mob, if it's still a live hostile one, counts as pinged; say so in chat unless
-- it's already in a fight.
local function afterClick(self)
    local unit = pingByText[self:GetAttribute("macrotext")]
    if unit and UnitExists(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) then
        local key = pingKey(unit)
        if not pingedAt[key] then
            pingedAt[key] = GetTime()
            if QP.Fresh(unit) then
                announce(readable((UnitName(unit))))
            end
        end
    end
    refresh()
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

local function createButton()
    local b = CreateFrame("Button", "QuestPingButton", UIParent, "SecureActionButtonTemplate")
    b:SetSize(36, 36)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true)
    b:SetClampedToScreen(true)
    b:RegisterForDrag("LeftButton")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0, 0, 0, 0.6)

    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetPoint("TOPLEFT", 3, -3)
    b.Icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.Icon:SetAtlas("Ping_Map_Whole_Attack")

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.12)

    b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.Count:SetPoint("BOTTOMRIGHT", -2, 2)

    b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.Label:SetPoint("LEFT", b, "RIGHT", 6, 0)

    b:SetScript("PostClick", afterClick)
    b:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "RightButton" and ns.ToggleWindow then
            ns.ToggleWindow()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() and not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        QuestPingDB.point = { p, rp, x, y }
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("QuestPing")
        for _, s in ipairs(shown) do
            if s.quiet then
                GameTooltip:AddLine(s.name .. " (pinged or fighting)", 0.6, 0.6, 0.6)
            else
                GameTooltip:AddLine(s.name, 1, 1, 1)
            end
        end
        GameTooltip:AddLine("Each press pings the next one. Right-click for the window. Shift-drag to move.",
            0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
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

function handlers.PLAYER_REGEN_ENABLED()
    if button then
        secure()
    end
    refresh()
end

handlers.PLAYER_TARGET_CHANGED = refresh

local events = CreateFrame("Frame")
for event in pairs(handlers) do
    -- An event the client doesn't know throws on Forever instead of being ignored.
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

BINDING_HEADER_QUESTPING = "QuestPing"
_G["BINDING_NAME_CLICK QuestPingButton:LeftButton"] = "Ping the next quest mob"
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
