AscensionLoot = AscensionLoot or {}
local AL = AscensionLoot

AL.name = "Ascension Loot"
AL.version = "0.2.0"
AL.prefix = "|cff33ff99Ascension Loot:|r "

local chatQueue = {}
local chatFrame = CreateFrame("Frame")
local lastChatSentAt = 0
local CHAT_MESSAGE_INTERVAL = 0.85
local CHAT_MESSAGE_MAX_BYTES = 220

chatFrame:Hide()

local defaults = {
    settings = {
        announceRolls = true,
        announceAssignments = true,
        rollDuration = 12,
        confirmAwards = true,
        duplicateReservesGiveExtraRolls = true,

        autoCollectTrackedLoot = true,
        lootHolderMode = "MASTER_LOOTER",
        lootHolderName = "",

        minimumTrackedQuality = 4,
        trackRareBindOnPickup = true,

        autoOpenTrade = true,
        autoFillTrade = true,

        autoLootCoins = true,
        autoLootPoor = true,
        autoLootCommon = true,
        protectReservedItems = true,
        autoShowLoot = true,
    },
    softres = {
        raw = nil,
        importedAt = nil,
    },
    history = {},
    lootSession = {
        nextID = 1,
        items = {},
    },
    windows = {
        loot = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = -220,
            y = 0,
            width = 700,
            height = 560,
            scale = 1,
        },

        settings = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 240,
            y = 0,
            width = 700,
            height = 560,
            scale = 1,
        },
    },
}

local function copyDefaults(source, target)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            copyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function AL:GetItemKey(item)
    if not item then return nil end

    if item.sessionID then
        return "session:" .. tostring(item.sessionID)
    end

    if item.source == "bag" then
        return string.format(
            "bag:%s:%s:%s",
            tostring(item.bag),
            tostring(item.bagSlot),
            tostring(item.id)
        )
    end

    if item.source == "loot" then
        return string.format(
            "loot:%s:%s",
            tostring(item.slot),
            tostring(item.id)
        )
    end

    return "item:" .. tostring(item.id)
end

function AL:InitializeDatabase()
    AscensionLootDB = AscensionLootDB or {}
    copyDefaults(defaults, AscensionLootDB)
    self.db = AscensionLootDB
end

function AL:Print(message, r, g, b)
    local text = self.prefix .. tostring(message or "")
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(text, r or 1, g or 1, b or 1)
    end
end

function AL:Trim(value)
    if value == nil then return "" end
    return (tostring(value):gsub("^%s+", ""):gsub("%s+$", ""))
end

function AL:NormalizeName(name)
    if not name then return nil end
    local short = tostring(name):match("^([^%-]+)") or tostring(name)
    return string.lower(self:Trim(short))
end

function AL:FormatCharacterName(name)
    local trimmed = self:Trim(name)

    if trimmed == "" then
        return trimmed
    end

    local characterName, realmSuffix =
        trimmed:match("^([^%-]+)(.*)$")

    if not characterName or characterName == "" then
        return trimmed
    end

    -- Fix only the first character's capitalization.
    -- cathyrina becomes Cathyrina.
    characterName =
        characterName:sub(1, 1):upper()
        .. characterName:sub(2)

    return characterName .. (realmSuffix or "")
end

function AL:GetGroupRosterNames()
    local result = {}
    local seen = {}

    local function addName(name)
        local normalized = self:NormalizeName(name)

        if not normalized
            or normalized == ""
            or seen[normalized]
        then
            return
        end

        seen[normalized] = true
        table.insert(result, name)
    end

    -- Include the addon user as well.
    addName(UnitName("player"))

    if self:IsInRaid() then
        for index = 1, GetNumRaidMembers() do
            addName(GetRaidRosterInfo(index))
        end

    elseif self:IsInParty() then
        for index = 1, GetNumPartyMembers() do
            addName(UnitName("party" .. index))
        end
    end

    return result
end

function AL:ResolveGroupMemberName(importedName)
    local importedNormalized =
        self:NormalizeName(importedName)

    if not importedNormalized
        or importedNormalized == ""
    then
        return nil, "invalid", {}
    end

    local rosterNames =
        self:GetGroupRosterNames()

    --------------------------------------------------
    -- First attempt: exact case-insensitive match
    --------------------------------------------------

    for _, rosterName in ipairs(rosterNames) do
        if self:NormalizeName(rosterName)
            == importedNormalized
        then
            return rosterName, "exact", {
                rosterName,
            }
        end
    end

    --------------------------------------------------
    -- Second attempt: unique prefix match
    --------------------------------------------------

    -- Do not perform prefix matching for one- or
    -- two-character names. Those are too ambiguous.
    if #importedNormalized < 3 then
        return nil, "too_short", {}
    end

    local matches = {}

    for _, rosterName in ipairs(rosterNames) do
        local rosterNormalized =
            self:NormalizeName(rosterName)

        if rosterNormalized
            and rosterNormalized:sub(
                1,
                #importedNormalized
            ) == importedNormalized
        then
            table.insert(matches, rosterName)
        end
    end

    if #matches == 1 then
        return matches[1], "prefix", matches
    end

    if #matches > 1 then
        return nil, "ambiguous", matches
    end

    return nil, "not_found", matches
end

function AL:GetItemID(itemLinkOrID)
    if type(itemLinkOrID) == "number" then return itemLinkOrID end
    if type(itemLinkOrID) ~= "string" then return nil end
    return tonumber(itemLinkOrID:match("item:(%-?%d+)")) or tonumber(itemLinkOrID)
end

function AL:TableCount(tbl)
    local count = 0
    for _ in pairs(tbl or {}) do count = count + 1 end
    return count
end

function AL:ShallowCopy(tbl)
    local result = {}
    for key, value in pairs(tbl or {}) do result[key] = value end
    return result
end

function AL:IsInRaid()
    local raidCount =
        GetNumRaidMembers
        and GetNumRaidMembers()
        or 0

    return raidCount > 0
end

function AL:IsInParty()
    local partyCount =
        GetNumPartyMembers
        and GetNumPartyMembers()
        or 0

    return partyCount > 0
end

function AL:GetGroupChannel()
    if self:IsInRaid() then
        return "RAID"
    end

    if self:IsInParty() then
        return "PARTY"
    end

    return nil
end

function AL:CanSendRaidWarning()
    if not self:IsInRaid() then
        return false
    end

    local isLeader =
        IsRaidLeader
        and IsRaidLeader()

    local isAssistant =
        IsRaidOfficer
        and IsRaidOfficer()

    return isLeader or isAssistant
end

function AL:SanitizeChatText(text)
    if type(text) ~= "string" then
        return ""
    end

    -- Convert a full WoW hyperlink into only its visible label.
    -- Example: |Hitem:123|h[Item]|h becomes [Item].
    text = text:gsub("|H.-|h(.-)|h", "%1")

    -- Remove color escape sequences which are useful locally but can
    -- cause server chat messages to be rejected on some 3.3.5 clients.
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")

    -- Chat messages must stay on one line.
    text = text:gsub("[\r\n]+", " ")

    return self:Trim(text)
end

local function splitChatText(text)
    local parts = {}

    while #text > CHAT_MESSAGE_MAX_BYTES do
        local cut = CHAT_MESSAGE_MAX_BYTES

        while cut > 1 and text:sub(cut, cut) ~= " " do
            cut = cut - 1
        end

        if cut <= 1 then
            cut = CHAT_MESSAGE_MAX_BYTES
        end

        local part = AL:Trim(text:sub(1, cut))

        if part ~= "" then
            table.insert(parts, part)
        end

        text = AL:Trim(text:sub(cut + 1))
    end

    if text ~= "" then
        table.insert(parts, text)
    end

    return parts
end

local function processChatQueue()
    if #chatQueue == 0 then
        chatFrame:Hide()
        return
    end

    local now = GetTime()

    if now - lastChatSentAt < CHAT_MESSAGE_INTERVAL then
        return
    end

    local entry = table.remove(chatQueue, 1)

    if entry and entry.text and entry.chatType then
        SendChatMessage(entry.text, entry.chatType)
        lastChatSentAt = now
    end

    if #chatQueue == 0 then
        chatFrame:Hide()
    end
end

chatFrame:SetScript("OnUpdate", processChatQueue)

function AL:QueueChatMessage(text, chatType)
    local safeText = self:SanitizeChatText(text)

    if safeText == "" or not chatType then
        return
    end

    for _, part in ipairs(splitChatText(safeText)) do
        table.insert(chatQueue, {
            text = part,
            chatType = chatType,
        })
    end

    chatFrame:Show()
    processChatQueue()
end

function AL:Announce(text)
    if type(text) ~= "string" or text == "" then
        return
    end

    if self:IsInRaid() then
        local chatType = "RAID"

        if self:CanSendRaidWarning() then
            chatType = "RAID_WARNING"
        end

        self:QueueChatMessage(text, chatType)
        return
    end

    if self:IsInParty() then
        self:QueueChatMessage(text, "PARTY")
        return
    end

    -- Keep hyperlinks clickable in local test output.
    self:Print(text)
end

function AL:AnnounceTrade(text)
    if type(text) ~= "string" or text == "" then
        return
    end

    if self:IsInRaid() then
        self:QueueChatMessage(text, "RAID")
        return
    end

    if self:IsInParty() then
        self:QueueChatMessage(text, "PARTY")
        return
    end

    self:Print(text)
end

function AL:IsGroupMember(name)
    local normalized = self:NormalizeName(name)
    if not normalized then return false end

    if normalized == self:NormalizeName(UnitName("player")) then
        return true
    end

    if self:IsInRaid() then
        for index = 1, GetNumRaidMembers() do
            local raidName = GetRaidRosterInfo(index)
            if normalized == self:NormalizeName(raidName) then return true end
        end
        return false
    end

    if self:IsInParty() then
        for index = 1, GetNumPartyMembers() do
            if normalized == self:NormalizeName(UnitName("party" .. index)) then return true end
        end
        return false
    end

    return false
end

function AL:FormatTimestamp(timestamp)
    if date then return date("%Y-%m-%d %H:%M:%S", timestamp or time()) end
    return tostring(timestamp or "")
end

function AL:AddHistory(entry)
    if not self.db then return end
    entry = entry or {}
    entry.timestamp = entry.timestamp or time()
    table.insert(self.db.history, 1, entry)
    while #self.db.history > 200 do
        table.remove(self.db.history)
    end
    if self.UI then self.UI:RefreshHistory() end
end
