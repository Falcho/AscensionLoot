local AL = AscensionLoot

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

function Session:FindFirstUnassigned(itemID, holderName)
    local normalizedHolder = AL:NormalizeName(holderName)

    for _, entry in ipairs(self:GetItems()) do
        if entry.id == tonumber(itemID)
            and entry.status == "unassigned"
            and (
                not normalizedHolder
                or AL:NormalizeName(entry.holder) == normalizedHolder
            )
        then
            return entry
        end
    end

    return nil
end

function Session:Assign(entry, winner, reason, winningRoll)
    if not entry or not winner then return false end

    entry.status = "awaiting_trade"
    entry.winner = winner
    entry.reason = reason or "Manual"
    entry.winningRoll = winningRoll
    entry.assignedAt = time()

    AL:AddHistory({
        itemID = entry.id,
        itemLink = entry.link,
        winner = winner,
        reason = entry.reason,
        winningRoll = winningRoll,
        masterLooter = UnitName("player"),
        status = "assigned",
    })

    if AL.db.settings.announceAssignments then
        AL:Announce(string.format(
            "%s assigned to %s. Trade pending.",
            entry.link or entry.name,
            winner
        ))
    end

    if AL.UI then
        AL.UI:RefreshAll()
    end

    if AL.Trade then
        AL.Trade:Queue(entry)
    end

    return true
end

function Session:Clear()
    AL.db.lootSession.items = {}
    if AL.UI then AL.UI:RefreshAll() end
end