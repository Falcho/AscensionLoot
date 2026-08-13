local AL = AscensionLoot

AL.Trade = AL.Trade or {}
local Trade = AL.Trade

Trade.requestedEntry = nil
Trade.requestedWinner = nil
Trade.requestedAt = nil

Trade.tradeTarget = nil
Trade.tradeOpen = false
Trade.tradeCompleted = false

Trade.filledEntries = {}
Trade.pendingVerification = nil

Trade.retryElapsed = 0
Trade.pendingFillTarget = nil

local AUTO_TRADE_RETRY_INTERVAL =
    0.75

local TRADE_REQUEST_TIMEOUT =
    3.0

local TRADE_FILL_DELAY =
    0.25

local function samePlayer(left, right)
    if not left or not right then
        return false
    end

    return AL:NormalizeName(left) == AL:NormalizeName(right)
end

local function clearArray(target)
    for index = #target, 1, -1 do
        target[index] = nil
    end
end

function Trade:FindUnitByName(playerName)
    if not playerName then
        return nil
    end

    if samePlayer(UnitName("player"), playerName) then
        return "player"
    end

    local raidCount =
        GetNumRaidMembers and GetNumRaidMembers() or 0

    if raidCount > 0 then
        for index = 1, raidCount do
            local unit = "raid" .. index

            if UnitExists(unit)
                and samePlayer(UnitName(unit), playerName)
            then
                return unit
            end
        end
    end

    local partyCount =
        GetNumPartyMembers and GetNumPartyMembers() or 0

    for index = 1, partyCount do
        local unit = "party" .. index

        if UnitExists(unit)
            and samePlayer(UnitName(unit), playerName)
        then
            return unit
        end
    end

    if UnitExists("target")
        and samePlayer(UnitName("target"), playerName)
    then
        return "target"
    end

    return nil
end

function Trade:IsUnitInTradeRange(unit)
    if not unit or not UnitExists(unit) then
        return false
    end

    if UnitIsDeadOrGhost(unit) then
        return false
    end

    if CheckInteractDistance then
        return CheckInteractDistance(unit, 2)
    end

    return true
end

function Trade:GetPendingEntriesForWinner(playerName)
    local result = {}

    if not AL.LootSession then
        return result
    end

    for _, entry in ipairs(
        AL.LootSession:GetItems() or {}
    ) do
        if entry.status == "awaiting_trade"
            and samePlayer(entry.winner, playerName)
        then
            table.insert(result, entry)
        end
    end

    table.sort(result, function(left, right)
        return (left.assignedAt or 0)
            < (right.assignedAt or 0)
    end)

    return result
end

function Trade:GetNextPendingEntry()
    if not AL.LootSession then
        return nil
    end

    for _, entry in ipairs(
        AL.LootSession:GetItems() or {}
    ) do
        if entry.status == "awaiting_trade"
            and entry.winner
        then
            return entry
        end
    end

    return nil
end

function Trade:Queue(entry, deferTradeStart)
    if not entry or not entry.winner then
        return
    end

    entry.status = "awaiting_trade"
    entry.tradeStatus = "queued"
    entry.tradeError = nil

    if AL.UI then
        AL.UI:RefreshAll()
    end

    if AL.db.settings.autoOpenTrade 
        and not deferTradeStart
    then
        self:TryStart(entry)
    end
end

function Trade:TryStart(entry)
    entry = entry or self:GetNextPendingEntry()

    if not entry then
        AL:Print("There are no items awaiting trade.")
        return false
    end

    if self.tradeOpen
        or (TradeFrame and TradeFrame:IsShown())
    then
        AL:Print("A trade is already open.", 1, 0.6, 0.2)
        return false
    end

    if InCombatLockdown and InCombatLockdown() then
        entry.tradeStatus = "waiting_for_combat"

        AL:Print(
            "Cannot start the trade while in combat.",
            1,
            0.5,
            0.2
        )

        return false
    end

    local unit = self:FindUnitByName(entry.winner)

    if not unit then
        entry.tradeStatus = "waiting_for_player"

        AL:Print(
            entry.winner
                .. " could not be found in the current group.",
            1,
            0.5,
            0.2
        )

        if AL.UI then
            AL.UI:RefreshAll()
        end

        return false
    end

    if unit == "player" then
        if AL.LootSession
            and AL.LootSession.MarkKept
        then
            AL.LootSession:MarkKept(
                entry,
                entry.winner
            )
        else
            entry.status = "kept"
            entry.tradeStatus = "not_required"
            entry.keptAt = time()
            entry.keptBy = entry.winner
            entry.tradeSlot = nil

            if AL.UI then
                AL.UI:RefreshAll()
            end
        end

        return true
    end

    if not self:IsUnitInTradeRange(unit) then
        entry.tradeStatus = "waiting_for_range"

        AL:Print(
            entry.winner
                .. " is not close enough to trade.",
            1,
            0.5,
            0.2
        )

        if AL.UI then
            AL.UI:RefreshAll()
        end

        return false
    end

    self.requestedEntry = entry
    self.requestedWinner = entry.winner
    self.requestedAt = GetTime()
    entry.tradeStatus = "trade_requested"
    entry.tradeError = nil
    InitiateTrade(unit)

    if AL.UI then
        AL.UI:RefreshAll()
    end

    return true
end

function Trade:GetTradeTarget()
    local target

    if TradeFrameRecipientNameText
        and TradeFrameRecipientNameText.GetText
    then
        target = TradeFrameRecipientNameText:GetText()
    end

    if target and target ~= "" then
        -- Some clients display cross-realm names as Name(*).
        target = string.gsub(target, "%(%*%)$", "")
        target = AL:Trim(target)

        return target
    end

    return self.requestedWinner
end

local function bagSlotKey(bag, slot)
    return tostring(bag) .. ":" .. tostring(slot)
end

function Trade:BagSlotMatches(
    entry,
    bag,
    slot
)
    local link =
        GetContainerItemLink(
            bag,
            slot
        )

    if not link then
        return false
    end

    if tonumber(AL:GetItemID(link))
        ~= tonumber(entry.id)
    then
        return false
    end

    -- Never insert an old, soulbound copy of the
    -- same item into the trade window.
    if AL.ItemUtils
        and AL.ItemUtils
            .IsBagItemTradeable
        and not AL.ItemUtils:
            IsBagItemTradeable(
                bag,
                slot
            )
    then
        return false
    end

    return true
end

function Trade:FindBagSlot(entry, usedSlots)
    if entry.bag ~= nil
        and entry.bagSlot ~= nil
        and not usedSlots[
            bagSlotKey(entry.bag, entry.bagSlot)
        ]
        and self:BagSlotMatches(
            entry,
            entry.bag,
            entry.bagSlot
        )
    then
        return entry.bag, entry.bagSlot
    end

    -- First pass: prefer an exact item-link match.
    for bag = 0, 4 do
        local slotCount = GetContainerNumSlots(bag)

        for slot = 1, slotCount do
            local key = bagSlotKey(bag, slot)
            local link = GetContainerItemLink(bag, slot)

            if not usedSlots[key]
                and link
                and entry.link
                and link == entry.link
                and self:BagSlotMatches(entry, bag, slot)
            then
                return bag, slot
            end
        end
    end

    -- Second pass: use the item ID.
    for bag = 0, 4 do
        local slotCount = GetContainerNumSlots(bag)

        for slot = 1, slotCount do
            local key = bagSlotKey(bag, slot)

            if not usedSlots[key]
                and self:BagSlotMatches(entry, bag, slot)
            then
                return bag, slot
            end
        end
    end

    return nil
end

function Trade:AddEntryToTradeSlot(
    entry,
    tradeSlot,
    usedSlots
)
    local bag, slot =
        self:FindBagSlot(entry, usedSlots)

    if bag == nil or slot == nil then
        entry.tradeStatus = "item_not_found"
        entry.tradeError = "Item could not be found in the bags."

        AL:Print(
            "Could not find "
                .. tostring(entry.link or entry.name)
                .. " in your bags.",
            1,
            0.3,
            0.3
        )

        return false
    end

    local key = bagSlotKey(bag, slot)
    usedSlots[key] = true

    ClearCursor()
    PickupContainerItem(bag, slot)

    if CursorHasItem and not CursorHasItem() then
        entry.tradeStatus = "pickup_failed"
        entry.tradeError = "The item could not be picked up."

        usedSlots[key] = nil

        return false
    end

    ClickTradeButton(tradeSlot)
    ClearCursor()

    entry.bag = bag
    entry.bagSlot = slot
    entry.tradeSlot = tradeSlot
    entry.status = "in_trade"
    entry.tradeStatus = "in_trade"

    table.insert(self.filledEntries, {
        entry = entry,
        bag = bag,
        bagSlot = slot,
        tradeSlot = tradeSlot,
    })

    return true
end

function Trade:FillTradeWindow(playerName)
    if not AL.db.settings.autoFillTrade then
        return
    end

    local entries =
        self:GetPendingEntriesForWinner(playerName)

    if #entries == 0 then
        return
    end

    clearArray(self.filledEntries)

    local usedSlots = {}
    local maximumItems = (MAX_TRADE_ITEMS or 7) - 1
    local tradeSlot = 1

    for _, entry in ipairs(entries) do
        if tradeSlot > maximumItems then
            break
        end

        if self:AddEntryToTradeSlot(
            entry,
            tradeSlot,
            usedSlots
        ) then
            tradeSlot = tradeSlot + 1
        end
    end

    if AL.UI then
        AL.UI:RefreshAll()
    end
end

--------------------------------------------------
-- Delayed trade-window filling
--------------------------------------------------

function Trade:ScheduleFillTradeWindow(
    playerName
)
    if not AL.db.settings
        .autoFillTrade
    then
        return
    end

    self.pendingFillTarget =
        playerName

    if not self.fillFrame then
        local frame =
            CreateFrame("Frame")

        frame:Hide()

        frame:SetScript(
            "OnUpdate",
            function(self, elapsed)
                self.elapsed =
                    (self.elapsed or 0)
                    + elapsed

                if self.elapsed
                    < TRADE_FILL_DELAY
                then
                    return
                end

                self.elapsed = 0
                self:Hide()

                local target =
                    Trade.pendingFillTarget

                Trade.pendingFillTarget =
                    nil

                if not target then
                    return
                end

                if not Trade.tradeOpen then
                    return
                end

                if TradeFrame
                    and not TradeFrame:
                        IsShown()
                then
                    return
                end

                Trade:
                    FillTradeWindow(
                        target
                    )
            end
        )

        self.fillFrame =
            frame
    end

    self.fillFrame.elapsed =
        0

    self.fillFrame:Show()
end

function Trade:OnTradeShow()
    self.tradeOpen = true
    self.tradeCompleted = false
    self.requestedAt = nil
    self.tradeTarget = self:GetTradeTarget()

    if not self.tradeTarget then
        AL:Print(
            "Could not determine the trade recipient.",
            1,
            0.3,
            0.3
        )

        return
    end

    if self.requestedWinner
        and not samePlayer(
            self.tradeTarget,
            self.requestedWinner
        )
    then
        AL:Print(
            "Trade opened with "
                .. tostring(self.tradeTarget)
                .. ", but the expected recipient was "
                .. tostring(self.requestedWinner)
                .. ". No items were inserted.",
            1,
            0.3,
            0.3
        )

        return
    end

    self:ScheduleFillTradeWindow(self.tradeTarget)
end

function Trade:OnUIInfoMessage(...)
    local tradeCompleteText =
        ERR_TRADE_COMPLETE or "Trade complete."

    for index = 1, select("#", ...) do
        local value = select(index, ...)

        if type(value) == "string"
            and value == tradeCompleteText
        then
            self.tradeCompleted = true
            return
        end
    end
end

function Trade:StartVerificationTimer()
    if not self.verifyFrame then
        local frame = CreateFrame("Frame")
        frame:Hide()

        frame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed

            if self.elapsed >= 1.0 then
                self.elapsed = 0
                self:Hide()

                Trade:VerifyClosedTrade()
            end
        end)

        self.verifyFrame = frame
    end

    self.verifyFrame.elapsed = 0
    self.verifyFrame:Show()
end

--------------------------------------------------
-- Continue automatic trade queue
--------------------------------------------------

function Trade:ScheduleNextTrade()
    if not AL.db
        or not AL.db.settings
        or not AL.db.settings
            .autoOpenTrade
    then
        return
    end

    --------------------------------------------------
    -- Reuse one tiny frame rather than creating a new
    -- frame after every completed trade.
    --------------------------------------------------

    if not self.nextTradeFrame then
        local frame =
            CreateFrame("Frame")

        frame:Hide()

        frame:SetScript(
            "OnUpdate",
            function(self, elapsed)
                self.elapsed =
                    (self.elapsed or 0)
                    + elapsed

                --------------------------------------------------
                -- Give the client a short moment to completely
                -- close the previous trade before requesting
                -- the next one.
                --------------------------------------------------

                if self.elapsed < 0.75 then
                    return
                end

                self.elapsed = 0
                self:Hide()

                if not AL.db
                    or not AL.db.settings
                    or not AL.db.settings
                        .autoOpenTrade
                then
                    return
                end

                --------------------------------------------------
                -- There may be no further winner, which is fine.
                --------------------------------------------------

                local nextEntry =
                    Trade:
                        GetNextPendingEntry()

                if nextEntry then
                    Trade:
                        TryStart(
                            nextEntry
                        )
                end
            end
        )

        self.nextTradeFrame =
            frame
    end

    self.nextTradeFrame.elapsed = 0
    self.nextTradeFrame:Show()
end

function Trade:OnTradeClosed()
    self.tradeOpen = false
    self.pendingFillTarget = nil

if self.fillFrame then
    self.fillFrame:Hide()
    self.fillFrame.elapsed = 0
end

    if #self.filledEntries == 0 then
        self.requestedEntry = nil
        self.requestedWinner = nil
        self.requestedAt = nil
        self.tradeTarget = nil
        return
    end

    self.pendingVerification = {}

    for _, value in ipairs(self.filledEntries) do
        table.insert(self.pendingVerification, value)
    end

    clearArray(self.filledEntries)

    self:StartVerificationTimer()
end

function Trade:VerifyClosedTrade()
    local verification = self.pendingVerification
    self.pendingVerification = nil

    if not verification then
        return
    end

    local tradeCompleted =
        self.tradeCompleted == true

    for _, value in ipairs(verification) do
        local entry = value.entry

        if tradeCompleted then
            if AL.LootSession
                and AL.LootSession.MarkTraded
            then
                AL.LootSession:MarkTraded(
                    entry,
                    self.tradeTarget
                )
            else
                entry.status = "traded"
                entry.tradeStatus = "completed"
                entry.tradedAt = time()
                entry.tradedTo =
                    self.tradeTarget or entry.winner
                entry.tradeSlot = nil
            end
        else
            -- Trade was cancelled, declined or closed
            -- without completing.
            entry.status = "awaiting_trade"
            entry.tradeStatus = "trade_cancelled"
            entry.tradeSlot = nil
        end
    end

    --------------------------------------------------
    -- Remember whether this trade actually completed
    -- before resetting transient state.
    --------------------------------------------------

    local shouldContinue =
        tradeCompleted
        and AL.db
        and AL.db.settings
        and AL.db.settings
            .autoOpenTrade

    self.tradeCompleted = false
    self.requestedEntry = nil
    self.requestedWinner = nil
    self.requestedAt = nil
    self.tradeTarget = nil

    if AL.UI then
        AL.UI:RefreshAll()
    end

    --------------------------------------------------
    -- A successfully completed trade advances to the
    -- next winner automatically.
    --
    -- Cancelled/declined trades deliberately do NOT
    -- auto-reopen and harass the same player.
    --------------------------------------------------

    if shouldContinue then
        self:ScheduleNextTrade()
    end
end

function Trade:OnCombatEnded()
    if not AL.db.settings.autoOpenTrade then
        return
    end

    local entry = self:GetNextPendingEntry()

    if entry
        and entry.tradeStatus == "waiting_for_combat"
    then
        self:TryStart(entry)
    end
end

--------------------------------------------------
-- Retry queued automatic trades
--------------------------------------------------

function Trade:OnUpdate(
    elapsed
)
    if not AL.db
        or not AL.db.settings
        or not AL.db.settings
            .autoOpenTrade
    then
        self.retryElapsed = 0
        return
    end

    --------------------------------------------------
    -- Never interfere with an active trade.
    --------------------------------------------------

    if self.tradeOpen
        or (
            TradeFrame
            and TradeFrame:
                IsShown()
        )
    then
        self.retryElapsed = 0
        return
    end

    --------------------------------------------------
    -- A trade request was sent but no TRADE_SHOW
    -- arrived.
    --
    -- Don't spam the winner with repeated requests.
    -- Mark it as failed and leave it for a manual
    -- retry.
    --------------------------------------------------

    if self.requestedEntry then
        local requestedAt =
            tonumber(
                self.requestedAt
            )
            or GetTime()

        if GetTime()
            - requestedAt
            < TRADE_REQUEST_TIMEOUT
        then
            return
        end

        self.requestedEntry
            .tradeStatus =
                "trade_request_failed"

        self.requestedEntry
            .tradeError =
                "The trade window did not open."

        self.requestedEntry =
            nil

        self.requestedWinner =
            nil

        self.requestedAt =
            nil

        if AL.UI then
            AL.UI:RefreshAll()
        end

        return
    end

    self.retryElapsed =
        (self.retryElapsed or 0)
        + (elapsed or 0)

    if self.retryElapsed
        < AUTO_TRADE_RETRY_INTERVAL
    then
        return
    end

    self.retryElapsed = 0

    local entry =
        self:GetNextPendingEntry()

    if not entry then
        return
    end

    --------------------------------------------------
    -- Only automatically retry states that simply
    -- mean "not ready yet".
    --
    -- A cancelled trade or actual item failure must
    -- not continually reopen a trade window.
    --------------------------------------------------

    local status =
        entry.tradeStatus

    if status ~= "queued"
        and status
            ~= "waiting_for_player"
        and status
            ~= "waiting_for_range"
        and status
            ~= "waiting_for_combat"
    then
        return
    end

    if InCombatLockdown
        and InCombatLockdown()
    then
        entry.tradeStatus =
            "waiting_for_combat"

        return
    end

    local unit =
        self:
            FindUnitByName(
                entry.winner
            )

    if not unit then
        entry.tradeStatus =
            "waiting_for_player"

        return
    end

    if unit ~= "player"
        and not self:
            IsUnitInTradeRange(
                unit
            )
    then
        entry.tradeStatus =
            "waiting_for_range"

        return
    end

    --------------------------------------------------
    -- The winner is now available and in range.
    --------------------------------------------------

    self:
        TryStart(
            entry
        )
end