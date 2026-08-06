local AL = AscensionLoot

local function samePlayerName(left, right)
    if not left or not right then
        return false
    end

    return AL:NormalizeName(left)
        == AL:NormalizeName(right)
end

AL.LootSession = AL.LootSession or {}
local Session = AL.LootSession

function Session:GetItems()
    return AL.db.lootSession.items
end

function Session:CreateID()
    local id = AL.db.lootSession.nextID or 1
    AL.db.lootSession.nextID = id + 1
    return id
end

function Session:AddCollected(item, holderName)
    local entry = {
        sessionID = self:CreateID(),
        source = "session",

        id = item.id,
        itemID = item.id,
        link = item.link,
        name = item.name,
        icon = item.icon,
        quantity = item.quantity or 1,
        quality = item.quality or 0,
        bindType = item.bindType,

        -- Preserve the last known bag location. The trade
        -- manager still searches all bags if the item moves.
        bag = item.bag,
        bagSlot = item.bagSlot,

        -- Records whether this came from Master Loot,
        -- automatic bag detection or an Alt-click fallback.
        registrationSource =
            item.registrationSource
            or item.source,

        holder = holderName,
        collectedAt = time(),

        -- Locally estimated; the server is still authoritative.
        estimatedTradeExpiresAt = time() + (2 * 60 * 60),

        status = "unassigned",
        winner = nil,
        reason = nil,
        winningRoll = nil,
    }

    entry.key = AL:GetItemKey(entry)

    table.insert(AL.db.lootSession.items, entry)

    if AL.UI then
        AL.UI:RefreshAll()
    end

    return entry
end

function Session:GetUnassignedCopies(
    itemID,
    holderName
)
    local result = {}
    local wantedItemID =
        tonumber(itemID)

    local normalizedHolder =
        holderName
        and AL:NormalizeName(holderName)
        or nil

    for _, entry in ipairs(
        self:GetItems() or {}
    ) do
        local holderMatches =
            not normalizedHolder
            or AL:NormalizeName(entry.holder)
                == normalizedHolder

        if tonumber(entry.id)
                == wantedItemID
            and entry.status
                == "unassigned"
            and holderMatches
        then
            table.insert(result, entry)
        end
    end

    table.sort(result, function(left, right)
        return (left.collectedAt or 0)
            < (right.collectedAt or 0)
    end)

    return result
end

function Session:FindFirstUnassigned(
    itemID,
    holderName
)
    local wantedItemID =
        tonumber(itemID)

    local normalizedHolder =
        holderName
        and AL:NormalizeName(holderName)
        or nil

    for _, entry in ipairs(
        self:GetItems() or {}
    ) do
        local holderMatches =
            not normalizedHolder
            or AL:NormalizeName(entry.holder)
                == normalizedHolder

        if tonumber(entry.id) == wantedItemID
            and entry.status == "unassigned"
            and holderMatches
        then
            return entry
        end
    end

    return nil
end

function Session:CountHeldCopies(
    itemID,
    holderName
)
    local wantedItemID =
        tonumber(itemID)

    local normalizedHolder =
        holderName
        and AL:NormalizeName(holderName)
        or nil

    local count = 0

    for _, entry in ipairs(
        self:GetItems() or {}
    ) do
        local holderMatches =
            not normalizedHolder
            or AL:NormalizeName(entry.holder)
                == normalizedHolder

        -- Traded entries no longer represent items
        -- that should still be in the holder's bags.
        if tonumber(entry.id) == wantedItemID
            and entry.status ~= "traded"
            and holderMatches
        then
            count = count + 1
        end
    end

    return count
end

function Session:MarkKept(entry, holderName)
    if not entry then
        return false
    end

    local keptBy =
        holderName
        or entry.winner
        or entry.holder
        or UnitName("player")

    entry.status = "kept"
    entry.tradeStatus = "not_required"
    entry.keptAt = time()
    entry.keptBy = keptBy
    entry.tradeSlot = nil
    entry.tradeError = nil

    AL:Print(string.format(
        "%s is being kept by %s. No trade is required.",
        entry.link or entry.name or "Item",
        keptBy or "Unknown"
    ))

    if AL.UI then
        AL.UI:RefreshAll()
    end

    return true
end

function Session:Assign(
    entry,
    winner,
    reason,
    winningRoll,
    deferTradeStart
)
    if not entry or not winner then
        return false
    end

    local holderName =
        entry.holder
        or UnitName("player")

    local winnerIsHolder =
        samePlayerName(
            winner,
            holderName
        )

    entry.winner = winner
    entry.reason = reason or "Manual"
    entry.winningRoll = winningRoll
    entry.assignedAt = time()

    if winnerIsHolder then
        entry.status = "kept"
        entry.tradeStatus = "not_required"
        entry.keptAt = time()
        entry.keptBy = winner
        entry.tradeError = nil
        entry.tradeSlot = nil
    else
        entry.status = "awaiting_trade"
        entry.tradeStatus = "queued"
    end

    AL:AddHistory({
        itemID = entry.id,
        itemLink = entry.link,
        winner = winner,
        reason = entry.reason,
        winningRoll = winningRoll,
        masterLooter = UnitName("player"),

        status =
            winnerIsHolder
            and "kept"
            or "assigned",
    })

    if AL.db.settings.announceAssignments then
        if winnerIsHolder then
            AL:Announce(string.format(
                "%s assigned to %s. No trade required.",
                entry.link or entry.name,
                winner
            ))
        else
            AL:Announce(string.format(
                "%s assigned to %s. Trade pending.",
                entry.link or entry.name,
                winner
            ))
        end
    end

    if AL.UI then
        AL.UI:RefreshAll()
    end

    -- Only queue an actual trade when the winner
    -- is different from the item holder.
    if not winnerIsHolder
        and AL.Trade
    then
        AL.Trade:Queue(
            entry,
            deferTradeStart
        )
    end

    return true
end

function Session:MarkTraded(entry, recipient)
    if not entry then
        return false
    end

    entry.status = "traded"
    entry.tradeStatus = "completed"
    entry.tradedAt = time()
    entry.tradedTo = recipient or entry.winner
    entry.tradeSlot = nil

    local tradeMessage = string.format(
        "%s has been traded to %s.",
        entry.link or entry.name or "Item",
        entry.tradedTo or entry.winner or "Unknown"
    )

    if AL.db.settings
        .announceCompletedTrades
        and AL.AnnounceTrade
    then
        AL:AnnounceTrade(
            tradeMessage
        )
    else
        AL:Print(
            tradeMessage
        )
    end

    if AL.UI then
        AL.UI:RefreshAll()
    end

    return true
end

function Session:Clear()
    AL.db.lootSession.items = {}

    if AL.UI then
        AL.UI:RefreshAll()
    end
end

