local AL = AscensionLoot

AL.SoftReserve = AL.SoftReserve or {}
local SR = AL.SoftReserve

SR.byItem = {}
SR.byPlayer = {}
SR.hardReserves = {}
SR.metadata = {}

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
    self:Rebuild(AL.db and AL.db.softres and AL.db.softres.raw or nil)
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
    return self.byItem[tonumber(itemID)]
end

function SR:GetReservers(itemID)
    local item = self:GetItem(itemID)
    return item and item.reservers or {}
end

function SR:IsReserved(itemID)
    return self.byItem[tonumber(itemID)] ~= nil
end

function SR:IsHardReserved(itemID)
    return self.hardReserves[tonumber(itemID)] ~= nil
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
