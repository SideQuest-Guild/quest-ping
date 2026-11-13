-- QuestPing/Party.lua
-- Who in your group still needs what, so a mob you're done with stays hunted while a party member needs it.
-- The game tells addons nothing of another player's quest progress, so this comes from two places:
--
-- * QuestPing itself: hidden addon messages (prefix "QuestPing", party or raid only, never chat) carrying the
--   objectives you still need by quest ID and index (Logic.lua's QP.EncodeNeeds). Sent a moment after your
--   quest log changes, and as a snapshot that asks for theirs whenever someone joins.
-- * Polestar's party sync, when you and they run Polestar with its party sharing on (Polestar.Party.Members:
--   quest -> { { have, need }, ... } per member).
--
-- Settings: QuestPingDB.party (default on) both shares yours and counts theirs.

local _, ns = ...
local QP = ns.QP
local readable = QP.Readable

local PREFIX = "QuestPing"
local DEBOUNCE = 2 -- seconds after a quest log change before sending
local REPLY_GAP = 3 -- seconds: answer a burst of requests once

local members = {} -- sender key -> { name, needs = { [questID] = { [index] = true } } }
local roster = {} -- key -> short name, of everyone in the group now (not you)
local lastSent -- the messages last sent, joined, so an unchanged log sends nothing
local sendPending, lastReply = false, nil

local function enabled()
    return QuestPingDB and QuestPingDB.party ~= false
end

local function channel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    elseif IsInGroup and IsInGroup() then
        return "PARTY"
    end
end

-- The key a group member's messages arrive under (Ambiguate(sender, "none")): the name, plus the realm without
-- spaces or hyphens when it isn't yours. Nil while the client keeps the name secret or doesn't know it yet.
local function unitKey(unit)
    local name, realm = UnitName(unit)
    name, realm = readable(name), readable(realm)
    if not name or name == "" or name == UNKNOWNOBJECT then
        return nil
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm:gsub("[%s%-]", ""), name
    end
    return name, name
end

--- What you still need, from your own quest log: { { q = questID, need = { index, ... } }, ... }.
local function myNeeds()
    local entries, QL = {}, C_QuestLog
    if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.GetQuestObjectives) then
        return entries
    end
    for i = 1, (QL.GetNumQuestLogEntries()) or 0 do
        local info = QL.GetInfo(i)
        local questID = info and not info.isHeader and not info.isHidden and readable(info.questID)
        if questID then
            local need = {}
            for index, o in ipairs(QL.GetQuestObjectives(questID) or {}) do
                if not o.finished then
                    need[#need + 1] = index
                end
            end
            if #need > 0 then
                entries[#entries + 1] = { q = questID, need = need }
            end
        end
    end
    return entries
end

local function send(asks, force)
    local chatType = channel()
    local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if not (enabled() and chatType and fn) then
        return
    end
    local msgs = QP.EncodeNeeds(myNeeds(), asks)
    local joined = table.concat(msgs, "\n")
    if joined == lastSent and not force then
        return
    end
    lastSent = joined
    for _, msg in ipairs(msgs) do
        pcall(fn, PREFIX, msg, chatType)
    end
end

local function sendSoon()
    if sendPending or not channel() then
        return
    end
    sendPending = true
    C_Timer.After(DEBOUNCE, function()
        sendPending = false
        send(false, false)
    end)
end

-- Re-reads who's in the group: forgets anyone who left, and asks anyone new for their needs (sending ours).
local function readRoster()
    local now, joined = {}, false
    if IsInGroup and IsInGroup() then
        local raid = IsInRaid and IsInRaid()
        local n = raid and (GetNumGroupMembers and GetNumGroupMembers() or 0)
            or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
        for i = 1, n do
            local unit = (raid and "raid" or "party") .. i
            if not (UnitIsUnit and readable(UnitIsUnit(unit, "player"))) then
                local key, short = unitKey(unit)
                if key then
                    now[key] = short
                    joined = joined or roster[key] == nil
                end
            end
        end
    end
    roster = now
    local dropped = false
    for key in pairs(members) do
        if not roster[key] then
            members[key], dropped = nil, true
        end
    end
    if not next(roster) then
        lastSent = nil
    elseif joined then
        send(true, true)
    end
    if dropped and ns.Refresh then
        ns.Refresh()
    end
end

local function onMessage(prefix, text, chatType, sender)
    if prefix ~= PREFIX or (chatType ~= "PARTY" and chatType ~= "RAID") or not enabled() then
        return
    end
    sender = readable(sender)
    if type(sender) ~= "string" then
        return
    end
    local key = Ambiguate and Ambiguate(sender, "none") or sender
    local short = roster[key]
    if not short then
        return -- you, or someone the roster hasn't caught up with yet
    end
    local kind, needs = QP.DecodeNeeds(text)
    if not kind then
        return
    end
    local m = members[key] or { name = short, needs = {} }
    members[key] = m
    if kind == "+" then
        for q, set in pairs(needs) do
            m.needs[q] = set
        end
    else
        m.needs = needs
    end
    if kind == "R" and not (lastReply and GetTime() - lastReply < REPLY_GAP) then
        lastReply = GetTime()
        send(false, true)
    end
    if ns.Refresh then
        ns.Refresh()
    end
end

-- Polestar's party sync, when it's running and has anyone's progress.
local function polestarMembers()
    local party = type(Polestar) == "table" and type(Polestar.Party) == "table" and Polestar.Party
    if not (party and party.Members) then
        return nil
    end
    local ok, list = pcall(party.Members)
    return ok and type(list) == "table" and list or nil
end

local function add(out, q, index, name)
    out[q] = out[q] or {}
    local names = out[q][index] or {}
    out[q][index] = names
    for _, have in ipairs(names) do
        if have == name then
            return
        end
    end
    names[#names + 1] = name
end

--- Who still needs what: { [questID] = { [index] = { name, ... } } }, names sorted; empty when solo or off.
function ns.PartyNeeds()
    local out = {}
    if not enabled() or not channel() then
        return out
    end
    for _, m in pairs(members) do
        for q, set in pairs(m.needs) do
            for index in pairs(set) do
                add(out, q, index, m.name)
            end
        end
    end
    for _, m in ipairs(polestarMembers() or {}) do
        if type(m.name) == "string" and type(m.quests) == "table" then
            for q, counts in pairs(m.quests) do
                for index, c in ipairs(type(counts) == "table" and counts or {}) do
                    if c[1] < c[2] then
                        add(out, q, index, m.name)
                    end
                end
            end
        end
    end
    for _, byIndex in pairs(out) do
        for _, names in pairs(byIndex) do
            table.sort(names)
        end
    end
    return out
end

--- The setting changed (Options.lua): share now, or let the party forget ours.
function ns.UpdateParty()
    if enabled() then
        send(true, true)
    else
        members, lastSent = {}, nil
        local chatType, fn = channel(), C_ChatInfo and C_ChatInfo.SendAddonMessage
        if chatType and fn then
            pcall(fn, PREFIX, QP.EncodeNeeds({}, false)[1], chatType) -- "needs nothing": they drop ours
        end
    end
    if ns.Refresh then
        ns.Refresh()
    end
end

local handlers = {}

function handlers.PLAYER_LOGIN()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    roster = {}
    readRoster() -- in a group after a login or reload: ask for everyone's needs
end

handlers.GROUP_ROSTER_UPDATE = readRoster
handlers.QUEST_LOG_UPDATE = sendSoon

function handlers.CHAT_MSG_ADDON(prefix, text, chatType, sender)
    onMessage(prefix, text, chatType, sender)
end

local events = CreateFrame("Frame")
for event in pairs(handlers) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)
