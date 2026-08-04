AscensionLoot = AscensionLoot or {}
local AL = AscensionLoot

AL.name = "Ascension Loot"
AL.version = "0.2.0"
AL.prefix = "|cff33ff99Ascension Loot:|r "

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
    return GetNumRaidMembers and GetNumRaidMembers() > 0
end

function AL:IsInParty()
    return GetNumPartyMembers and GetNumPartyMembers() > 0
end

function AL:GetGroupChannel()
    if self:IsInRaid() then return "RAID" end
    if self:IsInParty() then return "PARTY" end
    return nil
end

function AL:Announce(message)
    if not self.db or not self.db.settings.announceRolls then
        self:Print(message)
        return
    end

    local channel = self:GetGroupChannel()
    if channel and SendChatMessage then
        SendChatMessage(message, channel)
    else
        self:Print(message)
    end
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
