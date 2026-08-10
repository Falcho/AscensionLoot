local AL = AscensionLoot

AL.SoftReserve = AL.SoftReserve or {}
local SR = AL.SoftReserve

local ITEM_INFO_MAX_ATTEMPTS = 3
local ITEM_INFO_RETRY_INTERVAL = 15
local ITEM_INFO_POLL_INTERVAL = 0.5

--------------------------------------------------
-- Hidden tooltip used to force item-info requests
--------------------------------------------------

local ITEM_FETCH_TOOLTIP_NAME =
    "AscensionLootItemFetchTooltip"

local itemFetchTooltip =
    CreateFrame(
        "GameTooltip",
        ITEM_FETCH_TOOLTIP_NAME,
        UIParent,
        "GameTooltipTemplate"
    )

itemFetchTooltip:SetOwner(
    UIParent,
    "ANCHOR_NONE"
)

itemFetchTooltip:Hide()

SR.byItem = {}
SR.byPlayer = {}
SR.hardReserves = {}
SR.metadata = {}

SR.pendingItemInfo =
    SR.pendingItemInfo or {}

SR.failedItemInfo =
    SR.failedItemInfo or {}

SR.nextItemInfoCheck = 0

local function requestItemInfo(
    itemID
)
    itemID =
        tonumber(itemID)

    if not itemID then
        return false
    end

    --------------------------------------------------
    -- It may already have loaded since the last poll
    --------------------------------------------------

    local itemName,
        itemLink =
            GetItemInfo(
                itemID
            )

    if itemName or itemLink then
        return true
    end

    --------------------------------------------------
    -- Force Ascension to request the exact item ID
    --------------------------------------------------

    local hyperlink =
        string.format(
            "item:%d:0:0:0:0:0:0:0",
            itemID
        )

    itemFetchTooltip:Hide()
    itemFetchTooltip:ClearLines()

    itemFetchTooltip:SetOwner(
        UIParent,
        "ANCHOR_NONE"
    )

    -- Some custom/invalid item IDs can make
    -- SetHyperlink throw an error, so protect it.
    local success =
        pcall(
            itemFetchTooltip.SetHyperlink,
            itemFetchTooltip,
            hyperlink
        )

    itemFetchTooltip:Hide()

    --------------------------------------------------
    -- Ask again immediately in case SetHyperlink
    -- populated the cache synchronously.
    --------------------------------------------------

    GetItemInfo(
        itemID
    )

    return success
end

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

function SR:QueueItemInfoRequest(
    itemID
)
    itemID =
        tonumber(itemID)

    if not itemID then
        return false
    end

    --------------------------------------------------
    -- Already loaded
    --------------------------------------------------

    local itemName,
        itemLink =
            GetItemInfo(
                itemID
            )

    if itemName or itemLink then
        self.pendingItemInfo[
            itemID
        ] = nil

        self.failedItemInfo[
            itemID
        ] = nil

        return true
    end

    --------------------------------------------------
    -- Already being fetched
    --------------------------------------------------

    if self.pendingItemInfo[
        itemID
    ] then
        return false
    end

    --------------------------------------------------
    -- Already exhausted all attempts
    --------------------------------------------------

    if self.failedItemInfo[
        itemID
    ] then
        return false
    end

    --------------------------------------------------
    -- Attempt 1/3 immediately
    --------------------------------------------------

    local now =
        GetTime()

    self.pendingItemInfo[
        itemID
    ] = {
        attempts = 1,

        nextRetryAt =
            now
            + ITEM_INFO_RETRY_INTERVAL,
    }

    requestItemInfo(
        itemID
    )

    return false
end

function SR:GetDisplayItemInfo(
    itemID
)
    itemID =
        tonumber(itemID)

    if not itemID then
        return {
            requestedID = nil,
            resolvedID = nil,
            name = nil,
            link = nil,
            quality = nil,
            texture = nil,
            failed = true,
        }
    end

    --------------------------------------------------
    -- Use the exact imported Ascension item ID
    --------------------------------------------------

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
                itemID
            )

    if itemName or itemLink then
        self.pendingItemInfo[
            itemID
        ] = nil

        self.failedItemInfo[
            itemID
        ] = nil

        return {
            requestedID =
                itemID,

            resolvedID =
                itemID,

            name =
                itemName,

            link =
                itemLink,

            quality =
                quality,

            texture =
                texture,

            failed =
                false,
        }
    end

    --------------------------------------------------
    -- Queue a forced tooltip fetch if necessary
    --------------------------------------------------

    self:QueueItemInfoRequest(
        itemID
    )

    local pending =
        self.pendingItemInfo[
            itemID
        ]

    return {
        requestedID =
            itemID,

        resolvedID =
            nil,

        name =
            nil,

        link =
            nil,

        quality =
            nil,

        -- GetItemIcon often works before GetItemInfo
        -- on Ascension custom items.
        texture =
            GetItemIcon(
                itemID
            ),

        attempt =
            pending
            and pending.attempts
            or ITEM_INFO_MAX_ATTEMPTS,

        maxAttempts =
            ITEM_INFO_MAX_ATTEMPTS,

        failed =
            self.failedItemInfo[
                itemID
            ] == true,
    }
end

function SR:Rebuild(rawData)
    self.byItem = {}
    self.byPlayer = {}
    self.hardReserves = {}

    self.pendingItemInfo = {}
    self.failedItemInfo = {}
    self.nextItemInfoCheck = 0

    self.metadata =
        rawData
        and rawData.metadata
        or {}

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
    itemID =
        tonumber(itemID)

    if not itemID then
        return nil
    end

    return self.byItem[
        itemID
    ]
end

function SR:GetReservers(itemID)
    local item = self:GetItem(itemID)
    return item and item.reservers or {}
end

--------------------------------------------------
-- Effective tier-token reserves
--------------------------------------------------

function SR:GetEffectiveReservers(
    itemID
)
    itemID =
        tonumber(itemID)

    if not itemID then
        return {}
    end

    --------------------------------------------------
    -- Result is keyed by player so direct token
    -- reserves and tier-piece reserves can be merged.
    --------------------------------------------------

    local byPlayer = {}

    local function addReserver(
        reserver,
        sourceItemID,
        sourceType
    )
        if not reserver then
            return
        end

        local normalized =
            reserver.normalizedName
            or AL:NormalizeName(
                reserver.name
            )

        if not normalized then
            return
        end

        local existing =
            byPlayer[normalized]

        if not existing then
            existing = {
                name =
                    reserver.name,

                normalizedName =
                    normalized,

                count = 0,

                directCount = 0,
                mappedCount = 0,

                sources = {},
            }

            byPlayer[normalized] =
                existing
        end

        local reserveCount =
            math.max(
                1,
                tonumber(
                    reserver.count
                ) or 1
            )

        existing.count =
            existing.count
            + reserveCount

        if sourceType
            == "direct"
        then
            existing.directCount =
                existing.directCount
                + reserveCount
        else
            existing.mappedCount =
                existing.mappedCount
                + reserveCount
        end

        table.insert(
            existing.sources,
            {
                itemID =
                    tonumber(
                        sourceItemID
                    ),

                type =
                    sourceType,

                count =
                    reserveCount,
            }
        )
    end

    --------------------------------------------------
    -- 1. Direct reserve on the token/item itself.
    --------------------------------------------------

    for _, reserver in ipairs(
        self:GetReservers(
            itemID
        )
    ) do
        addReserver(
            reserver,
            itemID,
            "direct"
        )
    end

    --------------------------------------------------
    -- 2. If this item is a tier token, every reserve
    --    on one of the tier pieces redeemable from
    --    this exact token is also an effective SR.
    --------------------------------------------------

    if AL.TierTokens
        and AL.TierTokens:IsToken(
            itemID
        )
    then
        for _, pieceID in ipairs(
            AL.TierTokens:
                GetRewards(
                    itemID
                )
        ) do
            for _, reserver in ipairs(
                self:GetReservers(
                    pieceID
                )
            ) do
                addReserver(
                    reserver,
                    pieceID,
                    "tier_piece"
                )
            end
        end
    end

    --------------------------------------------------
    -- Convert keyed table back into the same style of
    -- array returned by GetReservers().
    --------------------------------------------------

    local result = {}

    for _, reserver in pairs(
        byPlayer
    ) do
        table.insert(
            result,
            reserver
        )
    end

    table.sort(
        result,
        function(left, right)
            return string.lower(
                left.name or ""
            )
                < string.lower(
                    right.name or ""
                )
        end
    )

    return result
end

function SR:IsReserved(itemID)
    return self:GetItem(itemID)
        ~= nil
end

function SR:IsHardReserved(
    itemID
)
    itemID =
        tonumber(itemID)

    if not itemID then
        return false
    end

    return self.hardReserves[
        itemID
    ] ~= nil
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
        now
        + ITEM_INFO_POLL_INTERVAL

    local refreshUI =
        false

    for itemID,
        state in pairs(
            self.pendingItemInfo
        )
    do
        --------------------------------------------------
        -- Has the server returned the item yet?
        --------------------------------------------------

        local itemName,
            itemLink =
                GetItemInfo(
                    itemID
                )

        if itemName or itemLink then
            self.pendingItemInfo[
                itemID
            ] = nil

            self.failedItemInfo[
                itemID
            ] = nil

            refreshUI =
                true

        --------------------------------------------------
        -- Time for another forced request
        --------------------------------------------------

        elseif now
            >= (
                state.nextRetryAt
                or 0
            )
        then
            local attempts =
                state.attempts
                or 1

            if attempts
                < ITEM_INFO_MAX_ATTEMPTS
            then
                --------------------------------------------------
                -- Attempt 2/3 or 3/3
                --------------------------------------------------

                attempts =
                    attempts + 1

                state.attempts =
                    attempts

                state.nextRetryAt =
                    now
                    + ITEM_INFO_RETRY_INTERVAL

                requestItemInfo(
                    itemID
                )

                refreshUI =
                    true

            else
                --------------------------------------------------
                -- All three requests were made.
                -- Give the third request one full retry interval
                -- to return before marking it unavailable.
                --------------------------------------------------

                self.pendingItemInfo[
                    itemID
                ] = nil

                self.failedItemInfo[
                    itemID
                ] = true

                refreshUI =
                    true
            end
        end
    end

    if refreshUI
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
