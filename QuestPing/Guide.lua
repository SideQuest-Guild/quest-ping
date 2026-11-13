-- QuestPing/Guide.lua
-- The guide arrow: when no mob you still need is in view, an arrow near the top of the screen turns to point at
-- the nearest place one spawns (Polestar's or Questie's database), with its name and distance. It steps aside
-- once a needed mob's nameplate is up (the bouncing arrow over the nameplate takes over), in instances, and
-- where the game gives no position or facing. Shift-drag moves it; Options > AddOns > QuestPing turns it off.

local _, ns = ...
local QP = ns.QP
local readable = QP.Readable

local ARROW = "Interface\\AddOns\\QuestPing\\Media\\arrow"
local TURN_EVERY = 0.05 -- seconds between arrow turns
local PICK_EVERY = 1 -- seconds between choosing the nearest spawn
local CLOSE = 30 -- yards: close enough that its nameplate should be up

local guide
local target -- { name, continent, x, y }
local sinceTurn, sincePick = 0, PICK_EVERY

local function anyInView()
    for _, s in ipairs(ns.state.shown) do
        if not s.quiet then
            return true
        end
    end
    return false
end

-- The nearest spawn of any mob an unfinished objective still needs, with its distance.
local function pick(continent, px, py)
    local best, bestDist
    for _, quest in ipairs(ns.state.hunt) do
        for _, o in ipairs(quest.objectives) do
            if not o.finished then
                local points = QP.SpawnPoints(quest.questID, o.index)
                if points then
                    local p, dist = QP.Nearest(points, continent, px, py)
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
    if QuestPingDB.guide == false or (IsInInstance and IsInInstance()) or anyInView() then
        return hide()
    end
    local continent, px, py = ns.PlayerWorldPosition()
    if not continent then
        return hide()
    end
    local p, dist = pick(continent, px, py)
    if not p or dist < CLOSE then
        return hide()
    end
    target = p
    guide.Text:SetText(("%s  |cffffffff%d yd|r"):format(p.name or "", math.floor(dist)))
    guide:Show()
end

local function turn()
    if not target then
        return
    end
    local facing = readable(GetPlayerFacing and GetPlayerFacing())
    local continent, px, py = ns.PlayerWorldPosition()
    if not (facing and continent == target.continent) then
        guide.Arrow:Hide()
        return
    end
    guide.Arrow:SetRotation(QP.Bearing(px, py, target.x, target.y, facing))
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
        choose()
        turn()
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
    sincePick, sinceTurn = sincePick + elapsed, sinceTurn + elapsed
    if sincePick >= PICK_EVERY then
        sincePick = 0
        choose()
    end
    if sinceTurn >= TURN_EVERY then
        sinceTurn = 0
        turn()
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    QuestPingDB = QuestPingDB or {}
    create()
end)
