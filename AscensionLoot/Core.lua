AscensionLoot = AscensionLoot or {}
local AL = AscensionLoot

AL.name = "Ascension Loot"
AL.version = "0.4.1"
AL.prefix = "|cff33ff99Ascension Loot:|r "

local chatQueue = {}
local chatFrame = CreateFrame("Frame")
local lastChatSentAt = 0
local CHAT_MESSAGE_INTERVAL = 0.85
local CHAT_MESSAGE_MAX_BYTES = 220

chatFrame:Hide()

local defaults = {
    settings = {
        --------------------------------------------------
        -- Rolls and announcements
        --------------------------------------------------

        announceRolls = true,
        announceAssignments = true,
        announceCompletedTrades = false,

        rollDuration = 30,
        confirmAwards = true,
        duplicateReservesGiveExtraRolls = true,

        --------------------------------------------------
        -- Master Loot
        --------------------------------------------------

        autoCollectTrackedLoot = true,

        -- More aggressive automation is disabled for
        -- new public-beta installations.
        autoMasterLootToSelf = false,
        autoConfirmMasterLootToSelf = false,

        lootHolderMode = "MASTER_LOOTER",
        lootHolderName = "",

        --------------------------------------------------
        -- Item tracking
        --------------------------------------------------

        minimumTrackedQuality = 4,
        trackRareBindOnPickup = true,
        trackEligibleBagLoot = true,

        --------------------------------------------------
        -- Trade assistance
        --------------------------------------------------

        autoOpenTrade = false,
        autoFillTrade = true,

        --------------------------------------------------
        -- Ordinary autoloot
        --------------------------------------------------

        autoLootCoins = true,
        autoLootPoor = true,
        autoLootCommon = true,
        protectReservedItems = true,

        --------------------------------------------------
        -- Interface
        --------------------------------------------------

        autoShowLoot = true,
        showMinimapButton = true,

        -- The compact player roll window always works in
        -- raids. Normal parties require explicit opt-in.
        showPlayerRollWindowInParty = false,
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
    minimapButton = {
        angle = 225
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

        playerRoll = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = -150,
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

function AL:GetAnnouncementItemText(item)
    if not item then
        return "[Unknown Item]"
    end

    local itemName =
        item.name
        or "Unknown Item"

    -- Demo links are manually constructed and do not
    -- necessarily match the real server-side item data.
    -- Sending them as hyperlinks may cause the entire
    -- raid-warning message to be rejected.
    if item.demo then
        return "[" .. itemName .. "]"
    end

    if type(item.link) == "string"
        and item.link:find(
            "|Hitem:",
            1,
            true
        )
    then
        return item.link
    end

    return "[" .. itemName .. "]"
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

    --------------------------------------------------
    -- Temporarily protect genuine item hyperlinks
    --------------------------------------------------

    local protectedLinks = {}

    local function protectLink(link)
        local index =
            #protectedLinks + 1

        protectedLinks[index] = link

        return "\001ALITEM"
            .. tostring(index)
            .. "\002"
    end

    -- Normal coloured item hyperlink:
    -- |cffa335ee|Hitem:123:...|h[Item]|h|r
    text = text:gsub(
        "|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h.-|h|r",
        protectLink
    )

    -- Also support an item hyperlink without a colour wrapper.
    text = text:gsub(
        "|Hitem:[^|]+|h.-|h",
        protectLink
    )

    --------------------------------------------------
    -- Remove unrelated formatting
    --------------------------------------------------

    -- Arbitrary colour codes in outgoing chat can cause
    -- rejection on some 3.3.5/private-server clients.
    -- The item-link colour codes are currently protected.
    text = text:gsub(
        "|c%x%x%x%x%x%x%x%x",
        ""
    )

    text = text:gsub("|r", "")

    -- Chat messages must remain on one line.
    text = text:gsub(
        "[\r\n]+",
        " "
    )

    --------------------------------------------------
    -- Restore protected item hyperlinks
    --------------------------------------------------

    text = text:gsub(
        "\001ALITEM(%d+)\002",
        function(index)
            return protectedLinks[
                tonumber(index)
            ] or ""
        end
    )

    return self:Trim(text)
end

local function addPlainTextTokens(
    tokens,
    text
)
    for word in tostring(text or ""):gmatch("%S+") do
        table.insert(tokens, word)
    end
end

local function tokenizeChatText(text)
    local tokens = {}
    local position = 1
    local textLength = #text

    while position <= textLength do
        local coloredStart,
            coloredEnd =
            text:find(
                "|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h.-|h|r",
                position
            )

        local plainStart,
            plainEnd =
            text:find(
                "|Hitem:[^|]+|h.-|h",
                position
            )

        local linkStart
        local linkEnd

        if coloredStart
            and (
                not plainStart
                or coloredStart <= plainStart
            )
        then
            linkStart = coloredStart
            linkEnd = coloredEnd

        elseif plainStart then
            linkStart = plainStart
            linkEnd = plainEnd
        end

        if not linkStart then
            addPlainTextTokens(
                tokens,
                text:sub(position)
            )

            break
        end

        if linkStart > position then
            addPlainTextTokens(
                tokens,
                text:sub(
                    position,
                    linkStart - 1
                )
            )
        end

        -- A complete item link is treated as one token,
        -- regardless of spaces inside the item name.
        table.insert(
            tokens,
            text:sub(
                linkStart,
                linkEnd
            )
        )

        position = linkEnd + 1
    end

    return tokens
end

local function splitChatText(text)
    local parts = {}
    local current = ""

    local tokens =
        tokenizeChatText(text)

    for _, token in ipairs(tokens) do
        local candidate

        if current == "" then
            candidate = token
        else
            candidate =
                current .. " " .. token
        end

        if #candidate
            <= CHAT_MESSAGE_MAX_BYTES
        then
            current = candidate
        else
            if current ~= "" then
                table.insert(
                    parts,
                    current
                )

                current = ""
            end

            -- Item links should never be divided.
            -- A normal item hyperlink is comfortably
            -- below the configured message limit.
            if token:find(
                "|Hitem:",
                1,
                true
            )
            then
                current = token

            else
                -- Safety fallback for an unusually long
                -- unbroken piece of ordinary text.
                while #token
                    > CHAT_MESSAGE_MAX_BYTES
                do
                    table.insert(
                        parts,
                        token:sub(
                            1,
                            CHAT_MESSAGE_MAX_BYTES
                        )
                    )

                    token = token:sub(
                        CHAT_MESSAGE_MAX_BYTES + 1
                    )
                end

                current = token
            end
        end
    end

    if current ~= "" then
        table.insert(
            parts,
            current
        )
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

function AL:AnnounceRoll(text)
    if type(text) ~= "string"
        or text == ""
    then
        return
    end

    if self.db
        and self.db.settings
        and self.db.settings
            .announceRolls == false
    then
        -- Keep the information visible to the
        -- addon user without sending group chat.
        self:Print(text)
        return
    end

    self:Announce(text)
end

function AL:AnnounceRollWarning(text)
    if type(text) ~= "string"
        or text == ""
    then
        return
    end

    --------------------------------------------------
    -- Respect the roll-announcement setting
    --------------------------------------------------

    if self.db
        and self.db.settings
        and self.db.settings
            .announceRolls == false
    then
        self:Print(text)
        return
    end

    --------------------------------------------------
    -- Raid
    --------------------------------------------------

    if self:IsInRaid() then
        if self:CanSendRaidWarning() then
            self:QueueChatMessage(
                text,
                "RAID_WARNING"
            )
        else
            -- WoW only permits leaders and assistants
            -- to send RAID_WARNING messages.
            self:QueueChatMessage(
                text,
                "RAID"
            )
        end

        return
    end

    --------------------------------------------------
    -- Party
    --------------------------------------------------

    if self:IsInParty() then
        self:QueueChatMessage(
            text,
            "PARTY"
        )

        return
    end

    --------------------------------------------------
    -- Solo testing
    --------------------------------------------------

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
