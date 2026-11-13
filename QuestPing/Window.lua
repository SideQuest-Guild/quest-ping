-- QuestPing/Window.lua
-- The hunt window, laid out like Attune's: the game's portrait frame, the quests you're hunting in a list on the
-- left, the picked quest's objectives on the right with a progress bar, which mobs count and how many are near,
-- and a status line with Settings and Close buttons along the bottom. /questping, the key binding or a
-- right-click on the ping button opens it. It only reads (ns.state, from QuestPing.lua); pinging stays on the
-- ping button.

local _, ns = ...
local QP = ns.QP

local WIDTH, HEIGHT = 660, 440
local LIST_WIDTH = 230
local ROW = 22
local MAX_OBJECTIVES = 6 -- what fits under the bar; quests rarely have more
local OBJECTIVE_GAP = 40
local PORTRAIT = "Interface\\Icons\\Ability_Hunter_SniperShot"
local ICON_TODO = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local ATLAS_DONE = "common-icon-checkmark"
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local GREEN, GREY = "|cff40ff40", "|cff9d9d9d"

local window, selected -- the picked quest's ID
local rows, objectiveRows = {}, {}

-- How many mobs in view (state.shown) count for an objective.
local function nearFor(objective, shown)
    local names, count = {}, 0
    for _, name in ipairs(objective.names) do
        names[name] = true
    end
    for _, s in ipairs(shown) do
        if QP.Matches(names, s.name) then
            count = count + 1
        end
    end
    return count
end

local function questNear(quest, shown)
    local count = 0
    for _, o in ipairs(quest.objectives) do
        if not o.finished then
            count = count + nearFor(o, shown)
        end
    end
    return count
end

local function progress(quest)
    local have, need = 0, 0
    for _, o in ipairs(quest.objectives) do
        have, need = have + math.min(o.have, o.need), need + o.need
    end
    return have, need
end

local function savePosition()
    local p, _, rp, x, y = window:GetPoint()
    QuestPingDB.windowPoint = { p, rp, x, y }
end

local function place()
    local p = QuestPingDB.windowPoint
    window:ClearAllPoints()
    if p then
        window:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

local function listRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW)

    r.Selected = r:CreateTexture(nil, "BACKGROUND")
    r.Selected:SetTexture(HIGHLIGHT)
    r.Selected:SetBlendMode("ADD")
    r.Selected:SetAllPoints(r)
    r.Selected:Hide()
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(HIGHLIGHT)
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(r)

    r.Right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.Right:SetPoint("RIGHT", -4, 0)
    r.Title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.Title:SetPoint("LEFT", 6, 0)
    r.Title:SetPoint("RIGHT", r.Right, "LEFT", -6, 0)
    r.Title:SetJustifyH("LEFT")
    r.Title:SetWordWrap(false)

    r:SetScript("OnClick", function(self)
        selected = self.questID
        ns.UpdateWindow()
    end)
    return r
end

local function objectiveRow(parent, i)
    local o = CreateFrame("Frame", nil, parent)
    o:SetHeight(OBJECTIVE_GAP)
    o:SetPoint("TOPLEFT", parent.Bar, "BOTTOMLEFT", 0, -14 - (i - 1) * OBJECTIVE_GAP)
    o:SetPoint("RIGHT", parent, "RIGHT", -14, 0)
    o.Icon = o:CreateTexture(nil, "ARTWORK")
    o.Icon:SetSize(16, 16)
    o.Icon:SetPoint("TOPLEFT", 0, 0)
    o.Near = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    o.Near:SetPoint("TOPRIGHT", 0, -2)
    o.Text = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    o.Text:SetPoint("TOPLEFT", o.Icon, "TOPRIGHT", 6, -1)
    o.Text:SetPoint("RIGHT", o.Near, "LEFT", -8, 0)
    o.Text:SetJustifyH("LEFT")
    o.Text:SetWordWrap(false)
    o.Mobs = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    o.Mobs:SetPoint("TOPLEFT", o.Text, "BOTTOMLEFT", 0, -3)
    o.Mobs:SetPoint("RIGHT", o, "RIGHT", 0, 0)
    o.Mobs:SetJustifyH("LEFT")
    o.Mobs:SetWordWrap(false)
    return o
end

local function create()
    local w = CreateFrame("Frame", "QuestPingWindow", UIParent, "PortraitFrameTemplate")
    w:SetSize(WIDTH, HEIGHT)
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:SetMovable(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:Hide()
    w:SetTitle("QuestPing")
    if w.SetPortraitToAsset then
        w:SetPortraitToAsset(PORTRAIT)
    end
    local drag = w.TitleContainer or w
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function() w:StartMoving() end)
    drag:SetScript("OnMouseUp", function()
        w:StopMovingOrSizing()
        savePosition()
    end)
    table.insert(UISpecialFrames, "QuestPingWindow") -- Escape closes it
    w:SetScript("OnShow", function()
        ns.Refresh()
        ns.UpdateWindow()
    end)

    -- Left: the quests.
    local list = CreateFrame("Frame", nil, w, "InsetFrameTemplate")
    list:SetPoint("TOPLEFT", 12, -62)
    list:SetPoint("BOTTOMLEFT", 12, 36)
    list:SetWidth(LIST_WIDTH)
    local shade = list:CreateTexture(nil, "BACKGROUND", nil, 1)
    shade:SetAllPoints(list)
    shade:SetColorTexture(0, 0, 0, 0.35)
    local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local listChild = CreateFrame("Frame", nil, scroll)
    listChild:SetSize(LIST_WIDTH - 32, 1)
    scroll:SetScrollChild(listChild)
    w.ListChild = listChild

    -- Right: the picked quest.
    local detail = CreateFrame("Frame", nil, w, "InsetFrameTemplate")
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
    detail:SetPoint("BOTTOMRIGHT", -12, 36)
    local dshade = detail:CreateTexture(nil, "BACKGROUND", nil, 1)
    dshade:SetAllPoints(detail)
    dshade:SetColorTexture(0, 0, 0, 0.2)
    w.Detail = detail

    detail.Title = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detail.Title:SetPoint("TOPLEFT", 14, -14)
    detail.Title:SetPoint("RIGHT", -14, 0)
    detail.Title:SetJustifyH("LEFT")
    detail.Sub = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.Sub:SetPoint("TOPLEFT", detail.Title, "BOTTOMLEFT", 0, -4)
    detail.Sub:SetJustifyH("LEFT")

    local bar = CreateFrame("StatusBar", nil, detail)
    bar:SetHeight(18)
    bar:SetPoint("TOPLEFT", detail.Sub, "BOTTOMLEFT", 0, -10)
    bar:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.25, 0.75, 0.25)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints(bar)
    barBg:SetColorTexture(0, 0, 0, 0.5)
    bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.Text:SetPoint("CENTER")
    detail.Bar = bar

    detail.Empty = detail:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    detail.Empty:SetPoint("CENTER")
    detail.Empty:SetWidth(320)
    detail.Empty:SetText("No quest in your log has mobs to hunt. Kill quests show here, and drop quests too "
        .. "when Polestar's quest database is loaded.")

    -- Bottom: status and buttons.
    w.Status = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.Status:SetPoint("BOTTOMLEFT", 18, 14)
    w.Status:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    close:SetSize(80, 22)
    close:SetPoint("BOTTOMRIGHT", -12, 8)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() w:Hide() end)
    local settings = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    settings:SetSize(80, 22)
    settings:SetPoint("RIGHT", close, "LEFT", -4, 0)
    settings:SetText(SETTINGS or "Settings")
    settings:SetScript("OnClick", function()
        if ns.OpenOptions then
            ns.OpenOptions()
        end
    end)
    w.Status:SetPoint("RIGHT", settings, "LEFT", -8, 0)

    window = w
    place()
end

local function sourceLabels(quest)
    local seen, out = {}, {}
    for _, o in ipairs(quest.objectives) do
        if not seen[o.source] then
            seen[o.source] = true
            out[#out + 1] = o.source
        end
    end
    return table.concat(out, ", ")
end

local function updateDetail(quest, shown)
    local d = window.Detail
    d.Empty:SetShown(quest == nil)
    d.Title:SetShown(quest ~= nil)
    d.Sub:SetShown(quest ~= nil)
    d.Bar:SetShown(quest ~= nil)
    for i = 1, MAX_OBJECTIVES do
        local o = quest and quest.objectives[i]
        local row = objectiveRows[i]
        if o and not row then
            row = objectiveRow(d, i)
            objectiveRows[i] = row
        end
        if row then
            row:SetShown(o ~= nil)
        end
        if o then
            if o.finished then
                row.Icon:SetAtlas(ATLAS_DONE)
            else
                row.Icon:SetTexture(ICON_TODO)
            end
            row.Text:SetText(o.finished and (GREY .. o.text .. "|r") or o.text)
            local near = o.finished and 0 or nearFor(o, shown)
            row.Near:SetText(near > 0 and (GREEN .. near .. " near|r") or "")
            local own = #o.names == 1 and o.text:find(o.names[1], 1, true)
            row.Mobs:SetText(own and "" or (table.concat(o.names, ", ") .. "  (" .. o.source .. ")"))
        end
    end
    if not quest then
        return
    end
    d.Title:SetText(quest.title)
    local sub = quest.level and ("Level " .. quest.level) or ""
    local sources = sourceLabels(quest)
    d.Sub:SetText(sub ~= "" and (sub .. "  ·  " .. sources) or sources)
    local have, need = progress(quest)
    d.Bar:SetMinMaxValues(0, math.max(need, 1))
    d.Bar:SetValue(have)
    d.Bar.Text:SetText(have .. " / " .. need)
end

local function updateStatus(hunt, shown)
    local parts = { #hunt .. (#hunt == 1 and " quest" or " quests") }
    local near = 0
    for _, s in ipairs(shown) do
        if not s.quiet then
            near = near + 1
        end
    end
    parts[#parts + 1] = (near > 0 and GREEN or "") .. near .. " to ping near" .. (near > 0 and "|r" or "")
    for _, source in ipairs(QP.Sources) do
        local text = source.status and source.status()
        if text then
            parts[#parts + 1] = text
        end
    end
    if C_CVar and C_CVar.GetCVarBool and not C_CVar.GetCVarBool("nameplateShowEnemies") then
        parts[#parts + 1] = "|cffff4040Enemy nameplates off|r"
    end
    window.Status:SetText(table.concat(parts, "  ·  "))
end

--- Redraw the window from ns.state; does nothing while it's closed.
function ns.UpdateWindow()
    if not (window and window:IsShown()) then
        return
    end
    local hunt, shown = ns.state.hunt, ns.state.shown
    local current
    for i, quest in ipairs(hunt) do
        local r = rows[i] or listRow(window.ListChild, i)
        rows[i] = r
        r.questID = quest.questID
        r.Title:SetText(quest.title)
        local near = questNear(quest, shown)
        local have, need = progress(quest)
        r.Right:SetText(near > 0 and (GREEN .. near .. " near|r") or (GREY .. have .. "/" .. need .. "|r"))
        r:Show()
        if quest.questID == selected then
            current = quest
        end
    end
    for i = #hunt + 1, #rows do
        rows[i]:Hide()
    end
    window.ListChild:SetHeight(math.max(#hunt * ROW, 1))
    if not current then
        current = hunt[1]
        selected = current and current.questID or nil
    end
    for i = 1, #hunt do
        rows[i].Selected:SetShown(rows[i].questID == selected)
    end
    updateDetail(current, shown)
    updateStatus(hunt, shown)
end

table.insert(ns.listeners, ns.UpdateWindow)

function ns.ToggleWindow()
    if not window then
        create()
    end
    window:SetShown(not window:IsShown())
end

function ns.ResetWindow()
    QuestPingDB.windowPoint = nil
    if window then
        place()
    end
end

-- The QUESTPING_WINDOW key binding (Bindings.xml).
function QuestPing_ToggleWindow()
    ns.ToggleWindow()
end
