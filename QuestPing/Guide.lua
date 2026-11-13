-- QuestPing/Guide.lua
-- The spawn guide arrow (off unless turned on): when no mob you still need is in view, an arrow near the top of
-- the screen turns to point at the nearest place one spawns (Polestar's or Questie's database), with its name and
-- distance. It steps aside once a needed mob is in view, in instances, and where the game gives no position or
-- facing. Shift-drag moves it; Options > AddOns > QuestPing turns it on.
--
-- A spawn you've been to with none of its mobs alive in view (you killed them, or someone else has them) is
-- empty, so the arrow skips it until it respawns and points at the next one instead.

local _, ns = ...
local QP = ns.QP
local readable = QP.Readable

local ARROW = "Interface\\AddOns\\QuestPing\\Media\\arrow"
local POS_EVERY = 0.1 -- seconds between reading the player's position; the arrow follows facing every frame
local PICK_EVERY = 1 -- seconds between choosing the nearest spawn
local SEEN_RANGE = 40 -- yards: a spawn this close shows its mobs' nameplates (the game draws them to 45)
local RESPAWN = 300 -- seconds an empty spawn is skipped

local guide
local target -- { name, continent, x, y }
local pos = {} -- the player's continent, x, y as of the last read
local seen = {} -- spawn point -> GetTime() it was found empty
local sincePos, sincePick = POS_EVERY, PICK_EVERY
local shownYards

-- Any mob you still need in view, even one already pinged or in a fight: you're where the arrow would lead.
local function anyInView()
    return #ns.state.shown > 0
end

local function showDistance(yards)
    yards = math.floor(yards)
    if yards ~= shownYards then
        shownYards = yards
        guide.Text:SetText(("%s  |cffffffff%d yd|r"):format(target.name or "", yards))
    end
end

-- The nearest spawn not found empty of any mob an unfinished objective still needs, with its distance. Only
-- runs with no needed mob in view, so the spawns around the player are empty.
local function pick(continent, px, py)
    local now = GetTime()
    for p, at in pairs(seen) do
        if now - at > RESPAWN then
            seen[p] = nil
        end
    end
    local best, bestDist
    for _, quest in ipairs(ns.state.hunt) do
        for _, o in ipairs(quest.objectives) do
            if not o.finished then
                local points = QP.SpawnPoints(quest.questID, o.index)
                if points then
                    QP.MarkSeen(points, continent, px, py, SEEN_RANGE, seen, now)
                    local p, dist = QP.Nearest(points, continent, px, py, seen)
                    if p and (not bestDist or dist < bestDist) then
                        best, bestDist = p, dist
                    end
                end
            end
        end
    end
    return best, bestDist
end

local function hide()
    target = nil
    guide:Hide()
end

-- Every PICK_EVERY: decide whether the arrow shows, and at what.
local function choose()
    if QuestPingDB.spawnArrow ~= true or (IsInInstance and IsInInstance()) or anyInView() then
        return hide()
    end
    if not pos.continent then
        return hide()
    end
    local p, dist = pick(pos.continent, pos.x, pos.y)
    if not p then
        return hide()
    end
    if p ~= target then
        target, shownYards = p, nil
    end
    showDistance(dist)
    guide:Show()
end

-- Every POS_EVERY: where the player is, and the distance under the arrow.
local function readPosition()
    pos.continent, pos.x, pos.y = ns.PlayerWorldPosition()
    if target and pos.continent == target.continent then
        local dx, dy = target.x - pos.x, target.y - pos.y
        showDistance(math.sqrt(dx * dx + dy * dy))
    end
end

-- Every frame while there's a target: point the arrow, so it turns as smoothly as the camera does.
local function turn()
    local facing = readable(GetPlayerFacing and GetPlayerFacing())
    if not (facing and pos.continent == target.continent) then
        guide.Arrow:Hide()
        return
    end
    guide.Arrow:SetRotation(QP.Bearing(pos.x, pos.y, target.x, target.y, facing))
    guide.Arrow:Show()
end

local function place()
    local p = QuestPingDB.guidePoint
    guide:ClearAllPoints()
    if p then
        guide:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        guide:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
end

local function create()
    local g = CreateFrame("Frame", "QuestPingGuide", UIParent)
    g:SetSize(56, 56)
    g:SetFrameStrata("MEDIUM")
    g:SetMovable(true)
    g:SetClampedToScreen(true)
    g:EnableMouse(true)
    g:RegisterForDrag("LeftButton")
    g:Hide()
    g.Arrow = g:CreateTexture(nil, "ARTWORK")
    g.Arrow:SetTexture(ARROW)
    g.Arrow:SetAllPoints(g)
    g.Text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g.Text:SetPoint("TOP", g, "BOTTOM", 0, -2)
    g:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    g:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        QuestPingDB.guidePoint = { p, rp, x, y }
    end)
    g:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("QuestPing guide")
        GameTooltip:AddLine("Points at the nearest place a mob you still need spawns.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift-drag to move.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    guide = g
    place()
end

--- Choose again now: a setting changed (Options.lua).
function ns.UpdateGuide()
    if guide then
        readPosition()
        choose()
        if target then
            turn()
        end
    end
end

function ns.ResetGuide()
    QuestPingDB.guidePoint = nil
    if guide then
        place()
    end
end

-- Runs while hidden too (a hidden frame gets no OnUpdate), so the arrow can come back on its own.
local clock = CreateFrame("Frame")
clock:SetScript("OnUpdate", function(_, elapsed)
    if not guide then
        return
    end
    sincePos, sincePick = sincePos + elapsed, sincePick + elapsed
    if sincePos >= POS_EVERY then
        sincePos = 0
        readPosition()
    end
    if sincePick >= PICK_EVERY then
        sincePick = 0
        choose()
    end
    if target then
        turn()
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    QuestPingDB = QuestPingDB or {}
    create()
end)
