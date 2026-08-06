local AL = AscensionLoot

AL.SoftReserve = AL.SoftReserve or {}
local SR = AL.SoftReserve

local ASCENSION_ITEM_OFFSET =
    300000

local function addUniqueID(
    result,
    seen,
    itemID
)
    itemID =
        tonumber(itemID)

    if not itemID
        or itemID <= 0
        or seen[itemID]
    then
        return
    end

    seen[itemID] = true

    table.insert(
        result,
        itemID
    )
end

SR.byItem = {}
SR.byPlayer = {}
SR.hardReserves = {}
SR.metadata = {}
SR.pendingItemInfo =
    SR.pendingItemInfo or {}
SR.nextItemInfoCheck = 0

local function addPlayerReserve(playerName, itemID, quality)
    local displayName =
        AL:FormatCharacterName(playerName)

    local normalized =
        AL:NormalizeName(displayName)
    if not normalized or normalized == "" or not itemID then return end

    SR.byItem[itemID] = SR.byItem[itemID] or {
        itemID = itemID,
        quality = quality,
        reservers = {},
    }

    local itemEntry = SR.byItem[itemID]
    local reserver
    for _, existing in ipairs(itemEntry.reservers) do
        if existing.normalizedName == normalized then
            reserver = existing
            break
        end
    end

    if not reserver then
        reserver = {
            name = displayName,
            normalizedName = normalized,
            count = 0,
        }
        table.insert(itemEntry.reservers, reserver)
    end
    reserver.count = reserver.count + 1

    SR.byPlayer[normalized] = SR.byPlayer[normalized] or {
        name = displayName,
        items = {},
    }
    local playerEntry = SR.byPlayer[normalized]
    playerEntry.items[itemID] = playerEntry.items[itemID] or {
        itemID = itemID,
        quality = quality,
        count = 0,
    }
    playerEntry.items[itemID].count = playerEntry.items[itemID].count + 1
end

function SR:GetItemIDCandidates(itemID)
    itemID =
        tonumber(itemID)

    local result = {}
    local seen = {}

    addUniqueID(
        result,
        seen,
        itemID
    )

    if not itemID then
        return result
    end

    --------------------------------------------------
    -- BisBeard/Ascension variant ID to base ID
    --------------------------------------------------

    if itemID >= ASCENSION_ITEM_OFFSET
        and itemID
            < ASCENSION_ITEM_OFFSET
                + 100000
    then
        addUniqueID(
            result,
            seen,
            itemID
                - ASCENSION_ITEM_OFFSET
        )

    --------------------------------------------------
    -- Base ID to possible Ascension variant ID
    --------------------------------------------------

    elseif itemID < 100000 then
        addUniqueID(
            result,
            seen,
            itemID
                + ASCENSION_ITEM_OFFSET
        )
    end

    return result
end

function SR:QueueItemInfoRequest(itemID)
    local now =
        GetTime()

    for _, candidateID in ipairs(
        self:GetItemIDCandidates(
            itemID
        )
    ) do
        -- Calling GetItemInfo initiates the cache
        -- request when the item is not yet cached.
        GetItemInfo(candidateID)

        self.pendingItemInfo[
            candidateID
        ] =
            now + 12
    end
end

function SR:GetDisplayItemInfo(itemID)
    local candidates =
        self:GetItemIDCandidates(
            itemID
        )

    --------------------------------------------------
    -- Prefer the exact imported item ID
    --------------------------------------------------

    for _, candidateID in ipairs(
        candidates
    ) do
        local itemName,
            itemLink,
            quality,
            itemLevel,
            requiredLevel,
            itemType,
            itemSubType,
            stackCount,
            equipLocation,
            texture =
                GetItemInfo(
                    candidateID
                )

        if itemName or itemLink then
            return {
                requestedID =
                    tonumber(itemID),

                resolvedID =
                    candidateID,

                name =
                    itemName,

                link =
                    itemLink,

                quality =
                    quality,

                texture =
                    texture,
            }
        end
    end

    --------------------------------------------------
    -- Neither ID is cached yet
    --------------------------------------------------

    self:QueueItemInfoRequest(
        itemID
    )

    return {
        requestedID =
            tonumber(itemID),

        resolvedID =
            nil,

        name =
            nil,

        link =
            nil,

        quality =
            nil,

        texture =
            nil,
    }
end

function SR:Rebuild(rawData)
    self.byItem = {}
    self.byPlayer = {}
    self.hardReserves = {}
    self.metadata = rawData and rawData.metadata or {}

    if type(rawData) ~= "table" then return end

    for _, playerReserve in ipairs(rawData.softreserves or {}) do
        local playerName = AL:Trim(playerReserve.name)
        for _, item in ipairs(playerReserve.items or {}) do
            addPlayerReserve(playerName, tonumber(item.id), tonumber(item.quality))
        end
    end

    for _, item in ipairs(rawData.hardreserves or {}) do
        local itemID = tonumber(item.id)
        if itemID then
            self.hardReserves[itemID] = {
                itemID = itemID,
                quality = tonumber(item.quality),
            }
        end
    end

    for _, itemEntry in pairs(self.byItem) do
        table.sort(itemEntry.reservers, function(left, right)
            return string.lower(left.name) < string.lower(right.name)
        end)
    end
end

function SR:LoadFromDatabase()
    self:Rebuild(
        AL.db
        and AL.db.softres
        and AL.db.softres.raw
        or nil
    )

    for itemID in pairs(
        self.byItem
    ) do
        self:QueueItemInfoRequest(
            itemID
        )
    end
end

function SR:Validate(data)
    if type(data) ~= "table" then return false, "Decoded data is not a JSON object." end
    if type(data.softreserves) ~= "table" then return false, "The export has no softreserves array." end

    for index, playerReserve in ipairs(data.softreserves) do
        if type(playerReserve) ~= "table" then
            return false, "Soft-reserve entry " .. index .. " is invalid."
        end
        if AL:Trim(playerReserve.name) == "" then
            return false, "Soft-reserve entry " .. index .. " has no player name."
        end
        if type(playerReserve.items) ~= "table" then
            return false, "Soft-reserve entry for " .. tostring(playerReserve.name) .. " has no items array."
        end
        for _, item in ipairs(playerReserve.items) do
            if not tonumber(item.id) then
                return false, "A reserve for " .. tostring(playerReserve.name) .. " has no valid item ID."
            end
        end
    end

    return true
end

function SR:Import(encoded)
    local decoded, base64Error = AL.Base64.Decode(encoded)
    if not decoded then return false, base64Error end

    local firstByte, secondByte = decoded:byte(1, 2)
    if firstByte == 0x78 and (secondByte == 0x01 or secondByte == 0x5E or secondByte == 0x9C or secondByte == 0xDA) then
        return false, "This export is zlib-compressed. Use BisBeard's RollFor export, which is plain Base64 JSON."
    end

    local data, jsonError = AL.Json.Decode(decoded)
    if not data then return false, "JSON error: " .. tostring(jsonError) end

    local valid, validationError = self:Validate(data)
    if not valid then return false, validationError end

    AL.db.softres.raw = data
    AL.db.softres.importedAt = time()
    self:Rebuild(data)

    for itemID in pairs(
        self.byItem
    ) do
        self:QueueItemInfoRequest(
            itemID
        )
    end

    if AL.UI then AL.UI:RefreshAll() end
    return true, self:GetSummaryText()
end

function SR:Clear()
    AL.db.softres.raw = nil
    AL.db.softres.importedAt = nil
    self:Rebuild(nil)
    if AL.UI then AL.UI:RefreshAll() end
end

function SR:GetItem(itemID)
    for _, candidateID in ipairs(
        self:GetItemIDCandidates(
            itemID
        )
    ) do
        local item =
            self.byItem[candidateID]

        if item then
            return item
        end
    end

    return nil
end

function SR:GetReservers(itemID)
    local item = self:GetItem(itemID)
    return item and item.reservers or {}
end

function SR:IsReserved(itemID)
    return self:GetItem(itemID)
        ~= nil
end

function SR:IsHardReserved(itemID)
    for _, candidateID in ipairs(
        self:GetItemIDCandidates(
            itemID
        )
    ) do
        if self.hardReserves[
            candidateID
        ]
        then
            return true
        end
    end

    return false
end

function SR:GetSummary()
    local players = AL:TableCount(self.byPlayer)
    local uniqueItems = AL:TableCount(self.byItem)
    local hardReserves = AL:TableCount(self.hardReserves)
    local selections = 0

    for _, item in pairs(self.byItem) do
        for _, reserver in ipairs(item.reservers) do
            selections = selections + reserver.count
        end
    end

    local instanceName = "Unknown raid"
    if self.metadata and type(self.metadata.instances) == "table" and self.metadata.instances[1] then
        instanceName = tostring(self.metadata.instances[1])
    end

    return {
        raidID = self.metadata and self.metadata.id or nil,
        instanceName = instanceName,
        players = players,
        selections = selections,
        uniqueItems = uniqueItems,
        hardReserves = hardReserves,
    }
end

function SR:GetSummaryText()
    local summary = self:GetSummary()
    local raid = summary.instanceName
    if summary.raidID then raid = raid .. " — " .. tostring(summary.raidID) end
    return string.format("%s: %d players, %d selections, %d unique items, %d hard reserves.",
        raid, summary.players, summary.selections, summary.uniqueItems, summary.hardReserves)
end

function SR:GetSortedPlayers()
    local players = {}
    for _, player in pairs(self.byPlayer) do table.insert(players, player) end
    table.sort(players, function(left, right)
        return string.lower(left.name) < string.lower(right.name)
    end)
    return players
end

function SR:OnUpdate()
    if not next(
        self.pendingItemInfo
    ) then
        return
    end

    local now =
        GetTime()

    if now
        < (
            self.nextItemInfoCheck
            or 0
        )
    then
        return
    end

    self.nextItemInfoCheck =
        now + 0.5

    local informationLoaded =
        false

    for itemID,
        expiresAt in pairs(
            self.pendingItemInfo
        )
    do
        local itemName,
            itemLink =
                GetItemInfo(
                    itemID
                )

        if itemName or itemLink then
            self.pendingItemInfo[
                itemID
            ] = nil

            informationLoaded =
                true

        elseif now >= expiresAt then
            -- Stop retrying IDs that the server does
            -- not recognize.
            self.pendingItemInfo[
                itemID
            ] = nil
        end
    end

    if informationLoaded
        and AL.UI
        and AL.UI.RefreshReserves
    then
        AL.UI:RefreshReserves()
    end
end

function SR:LoadDemo()
    local data = {
        metadata = { id = "demo", instances = { "Zul'Gurub" }, origin = "raidres" },
        softreserves = {
            { name = "Thrall", items = { { id = 12504, quality = 4 }, { id = 12473, quality = 4 } } },
            { name = "Sylvannas", items = { { id = 12504, quality = 4 }, { id = 19912, quality = 4 } } },
            { name = "Wrynn", items = { { id = 19857, quality = 4 }, { id = 19857, quality = 4 } } },
            { name = "Magni", items = { { id = 19925, quality = 4 }, { id = 22722, quality = 4 } } },
        },
        hardreserves = {},
    }
    self:Rebuild(data)
end
