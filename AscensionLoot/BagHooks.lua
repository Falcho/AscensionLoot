local AL = AscensionLoot

AL.BagHooks = AL.BagHooks or {}
local BagHooks = AL.BagHooks

BagHooks.initialized = false
BagHooks.snapshotReady = false
BagHooks.bagSnapshot = {}
BagHooks.scanPending = false
BagHooks.scanAt = 0

--------------------------------------------------
-- Master Loot items expected to enter our bags.
--
-- These are registered before GiveMasterLoot()
-- happens and consumed when the bag-count delta
-- confirms that the item physically arrived.
--------------------------------------------------

BagHooks.masterLootExpectations =
    BagHooks.masterLootExpectations or {}

--------------------------------------------------
-- Positive bag deltas whose temporary trade
-- tooltip was not ready on the first scan.
--------------------------------------------------

BagHooks.retryUntil =
    BagHooks.retryUntil or {}

local BAG_SCAN_DELAY = 0.75
local BAG_RETRY_DELAY = 0.75
local BAG_RETRY_WINDOW = 5.0

local MASTER_LOOT_EXPECTATION_WINDOW =
    8.0

local function bagSlotKey(
    bag,
    slot
)
    return tostring(bag)
        .. ":"
        .. tostring(slot)
end

--------------------------------------------------
-- Bag-button handling
--------------------------------------------------

function BagHooks:GetBagAndSlot(button)
    if not button then
        return nil
    end

    local parent = button:GetParent()
    local bag = parent and parent:GetID()
    local slot = button:GetID()

    if bag == nil or slot == nil then
        return nil
    end

    return bag, slot
end

--------------------------------------------------
-- Bag snapshots
--------------------------------------------------

function BagHooks:BuildBagSnapshot()
    local snapshot = {}

    for bag = 0, 4 do
        local slotCount =
            GetContainerNumSlots(bag) or 0

        for slot = 1, slotCount do
            local link =
                GetContainerItemLink(
                    bag,
                    slot
                )

            if link then
                local itemID =
                    AL:GetItemID(link)

                if itemID then
                    local _, quantity =
                        GetContainerItemInfo(
                            bag,
                            slot
                        )

                    quantity =
                        tonumber(quantity) or 1

                    if quantity < 1 then
                        quantity = 1
                    end

                    local key =
                        tostring(itemID)

                    if not snapshot[key] then
                        snapshot[key] = {
                            itemID = itemID,
                            count = 0,
                            slots = {},
                        }
                    end

                    snapshot[key].count =
                        snapshot[key].count
                        + quantity

                    table.insert(
                        snapshot[key].slots,
                        {
                            bag = bag,
                            slot = slot,
                            link = link,
                            quantity = quantity,
                        }
                    )
                end
            end
        end
    end

    return snapshot
end

function BagHooks:GetCurrentBagCount(itemID)
    local snapshot =
        self:BuildBagSnapshot()

    local bucket =
        snapshot[tostring(itemID)]

    if not bucket then
        return 0
    end

    return bucket.count or 0
end

--------------------------------------------------
-- Automatic loot reconciliation
--------------------------------------------------

function BagHooks:ShouldAutomaticallyRegister()
    if not AL.db
        or not AL.db.settings
    then
        return false
    end

    if AL.db.settings
        .trackEligibleBagLoot == false
    then
        return false
    end

    if not AL:IsInRaid()
        and not AL:IsInParty()
    then
        return false
    end

    local lootMethod =
        GetLootMethod
        and GetLootMethod()

    --------------------------------------------------
    -- Unsolicited automatic registration is for
    -- Group Loot / non-Master-Loot modes.
    --
    -- Master Loot is handled by explicit expectations
    -- created by LootManager before GiveMasterLoot().
    --------------------------------------------------

    if lootMethod == "master" then
        return false
    end

    return true
end

--------------------------------------------------
-- Master Loot expectations
--------------------------------------------------

function BagHooks:ExpectMasterLoot(
    item,
    copyCount
)
    if not item
        or not item.id
    then
        return false
    end

    local key =
        tostring(
            item.id
        )

    local count =
        tonumber(copyCount)
        or tonumber(item.quantity)
        or 1

    count =
        math.max(
            1,
            math.floor(count)
        )

    local expectation =
        self.masterLootExpectations[
            key
        ]

    if not expectation then
        expectation = {
            item =
                AL:ShallowCopy(
                    item
                ),

            count = 0,
            expiresAt = 0,
        }

        self.masterLootExpectations[
            key
        ] =
            expectation
    end

    expectation.count =
        (
            tonumber(
                expectation.count
            ) or 0
        )
        + count

    expectation.expiresAt =
        GetTime()
        + MASTER_LOOT_EXPECTATION_WINDOW

    --------------------------------------------------
    -- Do not rely exclusively on BAG_UPDATE.
    -- Schedule a reconciliation as a fallback.
    --------------------------------------------------

    self.scanPending = true
    self.scanAt =
        GetTime()
        + BAG_SCAN_DELAY

    return true
end

function BagHooks:GetExpectedMasterLootCount(
    itemID
)
    local key =
        tostring(
            itemID
        )

    local expectation =
        self.masterLootExpectations[
            key
        ]

    if not expectation then
        return 0
    end

    if GetTime()
        >= (
            expectation.expiresAt
            or 0
        )
    then
        self.masterLootExpectations[
            key
        ] =
            nil

        return 0
    end

    return tonumber(
        expectation.count
    ) or 0
end

function BagHooks:ConsumeMasterLootExpectation(
    itemID,
    count
)
    local key =
        tostring(
            itemID
        )

    local expectation =
        self.masterLootExpectations[
            key
        ]

    if not expectation then
        return
    end

    expectation.count =
        math.max(
            0,
            (
                tonumber(
                    expectation.count
                ) or 0
            )
            - (
                tonumber(count)
                or 0
            )
        )

    if expectation.count <= 0 then
        self.masterLootExpectations[
            key
        ] =
            nil
    end
end

--------------------------------------------------
-- Bag-location helpers
--------------------------------------------------

function BagHooks:GetRepresentativeItem(
    bucket
)
    if not bucket then
        return nil
    end

    for _, location in ipairs(
        bucket.slots or {}
    ) do
        local item =
            AL.ItemUtils:
                FromBagSlot(
                    location.bag,
                    location.slot
                )

        if item then
            return item
        end
    end

    return nil
end

function BagHooks:FindUsableLocation(
    bucket,
    requireTradeable,
    previousBucket
)
    if not bucket then
        return nil
    end

    --------------------------------------------------
    -- Record how many copies existed in each physical
    -- bag slot before this bag delta.
    --------------------------------------------------

    local previousQuantities =
        {}

    if previousBucket then
        for _,
            location in ipairs(
                previousBucket.slots
                or {}
            )
        do
            previousQuantities[
                bagSlotKey(
                    location.bag,
                    location.slot
                )
            ] =
                tonumber(
                    location.quantity
                )
                or 1
        end
    end

    for _,
        location in ipairs(
            bucket.slots
            or {}
        )
    do
        local currentQuantity =
            tonumber(
                location.quantity
            )
            or 1

        local previousQuantity =
            previousQuantities[
                bagSlotKey(
                    location.bag,
                    location.slot
                )
            ]
            or 0

        --------------------------------------------------
        -- When comparing against an older snapshot,
        -- only inspect a slot whose quantity actually
        -- increased.
        --------------------------------------------------

        local newlyReceivedHere =
            not previousBucket
            or currentQuantity
                > previousQuantity

        if newlyReceivedHere then
            local tradeable =
                AL.ItemUtils:
                    HasRaidTradeTimer(
                        location.bag,
                        location.slot
                    )

            if not requireTradeable
                or tradeable
            then
                local item =
                    AL.ItemUtils:
                        FromBagSlot(
                            location.bag,
                            location.slot
                        )

                if item then
                    return item,
                        location,
                        tradeable
                end
            end
        end
    end

    return nil
end

--------------------------------------------------
-- Session registration
--------------------------------------------------

function BagHooks:RegisterCopiesFromBucket(
    bucket,
    copyCount,
    registrationSource,
    requireTradeable,
    previousBucket
)
    local count =
        tonumber(copyCount)
        or 0

    if count <= 0 then
        return 0
    end

    local item,
        location,
        tradeable =
            self:FindUsableLocation(
                bucket,
                requireTradeable,
                previousBucket
            )

    if not item
        or not location
    then
        return 0
    end

    --------------------------------------------------
    -- Group Loot still obeys the normal tracking
    -- quality rules.
    --
    -- Master Loot expectations were already filtered
    -- when LootManager built its collection queue.
    --------------------------------------------------

    if registrationSource
        == "bag_update"
        and not AL.ItemUtils:
            ShouldTrack(item)
    then
        return 0
    end

    local holder =
        UnitName("player")

    local added = 0

    for copyIndex = 1, count do
        local copy =
            AL:ShallowCopy(
                item
            )

        copy.quantity = 1
        copy.source = "bag"

        copy.registrationSource =
            registrationSource

        copy.bag =
            location.bag

        copy.bagSlot =
            location.slot

        copy.tradeableVerified =
            tradeable
            and true
            or false

        if tradeable then
            copy.tradeableVerifiedAt =
                time()
        end

        local entry =
            AL.LootSession:
                AddCollected(
                    copy,
                    holder
                )

        if entry then
            added =
                added + 1
        end
    end

    return added
end

--------------------------------------------------
-- Reconciliation
--------------------------------------------------

function BagHooks:ScanForNewEligibleItems()
    local currentSnapshot =
        self:BuildBagSnapshot()

    if not self.snapshotReady then
        self.bagSnapshot =
            currentSnapshot

        self.snapshotReady = true
        return
    end

    local lootMethod =
        GetLootMethod
        and GetLootMethod()

    local previousSnapshot =
        self.bagSnapshot
        or {}

    local nextSnapshot = {}

    local now =
        GetTime()

    local needsRetry =
        false

    local totalAdded =
        0

    local firstDisplayLink =
        nil

    --------------------------------------------------
    -- Process every item currently in the bags.
    --------------------------------------------------

    for key,
        currentBucket in pairs(
            currentSnapshot
        )
    do
        local previousBucket =
            previousSnapshot[
                key
            ]

        local previousCount =
            previousBucket
            and tonumber(
                previousBucket.count
            )
            or 0

        local currentCount =
            tonumber(
                currentBucket.count
            )
            or 0

        local difference =
            currentCount
            - previousCount

        local unresolved =
            0

        if difference > 0 then
            local remaining =
                difference

            --------------------------------------------------
            -- 1. Explicit Master Loot expectations
            --------------------------------------------------

            local expectedMasterLoot =
                self:
                    GetExpectedMasterLootCount(
                        currentBucket.itemID
                    )

            local expectedFromDelta =
                math.min(
                    remaining,
                    expectedMasterLoot
                )

            if expectedFromDelta > 0 then
                local added =
                    self:
                        RegisterCopiesFromBucket(
                            currentBucket,
                            expectedFromDelta,
                            "master_loot_bag",
                            true,
                            previousBucket
                        )

                if added > 0 then
                    self:
                        ConsumeMasterLootExpectation(
                            currentBucket.itemID,
                            added
                        )

                    totalAdded =
                        totalAdded
                        + added

                    local representative =
                        self:
                            GetRepresentativeItem(
                                currentBucket
                            )

                    if representative
                        and not firstDisplayLink
                    then
                        firstDisplayLink =
                            representative.link
                            or representative.name
                    end
                end

                if added
                    < expectedFromDelta
                then
                    unresolved =
                        unresolved
                        + (
                            expectedFromDelta
                            - added
                        )
                end

                remaining =
                    remaining
                    - expectedFromDelta
            end

            --------------------------------------------------
            -- 2. Group Loot / non-Master-Loot additions
            --------------------------------------------------

            if remaining > 0
                and self:
                    ShouldAutomaticallyRegister()
            then
                local representative =
                    self:
                        GetRepresentativeItem(
                            currentBucket
                        )

                if representative
                    and AL.ItemUtils:
                        ShouldTrack(
                            representative
                        )
                then
                    local added =
                        self:
                            RegisterCopiesFromBucket(
                                currentBucket,
                                remaining,
                                "bag_update",
                                true,
                                previousBucket
                            )

                    if added > 0 then
                        totalAdded =
                            totalAdded
                            + added

                        firstDisplayLink =
                            firstDisplayLink
                            or representative.link
                            or representative.name
                    end

                    --------------------------------------------------
                    -- If the temporary raid-trade tooltip is
                    -- late, don't permanently advance the
                    -- baseline yet.
                    --------------------------------------------------

                    if added
                        < remaining
                    then
                        unresolved =
                            unresolved
                            + (
                                remaining
                                - added
                            )
                    end
                end
            end
        end

        --------------------------------------------------
        -- Retry unresolved tracked deltas for a few
        -- seconds. This is important because Ascension's
        -- tooltip data can appear after BAG_UPDATE.
        --------------------------------------------------

        if unresolved > 0 then
            local retryDeadline =
                self.retryUntil[
                    key
                ]

            if not retryDeadline then
                retryDeadline =
                    now
                    + BAG_RETRY_WINDOW

                self.retryUntil[
                    key
                ] =
                    retryDeadline
            end

            if now < retryDeadline then
                needsRetry =
                    true

                nextSnapshot[
                    key
                ] = {
                    itemID =
                        currentBucket.itemID,

                    count =
                        math.max(
                            0,
                            currentCount
                            - unresolved
                        ),

                    slots =
                        currentBucket.slots,
                }

            else
                --------------------------------------------------
                -- The item exists in our bags, but no temporary
                -- raid-trade marker appeared before the eligibility
                -- window expired.
                --
                -- This is NOT a loot failure.
                --
                -- It simply means the item must not enter the
                -- persistent loot session.
                --------------------------------------------------

                self.retryUntil[
                    key
                ] =
                    nil

                nextSnapshot[
                    key
                ] =
                    currentBucket

                --------------------------------------------------
                -- Drop any explicit Master Loot expectation for
                -- the copies that failed the tradeability check.
                --------------------------------------------------

                self:
                    ConsumeMasterLootExpectation(
                        currentBucket.itemID,
                        unresolved
                    )
            end
        else
            self.retryUntil[
                key
            ] =
                nil

            nextSnapshot[
                key
            ] =
                currentBucket
        end
    end

    --------------------------------------------------
    -- Items that disappeared from the bags simply
    -- disappear from the new baseline.
    --------------------------------------------------

    self.bagSnapshot =
        nextSnapshot

    --------------------------------------------------
    -- Automatically retry without requiring another
    -- BAG_UPDATE event.
    --------------------------------------------------

    if needsRetry then
        self.scanPending =
            true

        self.scanAt =
            GetTime()
            + BAG_RETRY_DELAY
    end

    --------------------------------------------------
    -- Notify once for the complete reconciliation.
    --------------------------------------------------

    if totalAdded > 0 then
        AL:Print(string.format(
            "Added %d newly collected %s to the loot session.",
            totalAdded,
            totalAdded == 1
                and "item"
                or "items"
        ))

        if AL.db.settings.autoShowLoot
            and AL.UI
        then
            AL.UI:ShowLoot()
        end
    end
end

function BagHooks:OnBagUpdate()
    if not self.initialized then
        return
    end

    --------------------------------------------------
    -- BAG_UPDATE frequently fires several times during
    -- one loot operation. Wait for the bags to settle.
    --------------------------------------------------

    self.scanPending =
        true

    self.scanAt =
        GetTime()
        + BAG_SCAN_DELAY
end

function BagHooks:OnUpdate()
    if not self.scanPending then
        return
    end

    if GetTime()
        < self.scanAt
    then
        return
    end

    self.scanPending =
        false

    self:
        ScanForNewEligibleItems()
end

function BagHooks:EnsureBagItemRegistered(
    item
)
    if not item or not item.id then
        return nil,
            "The bag item could not be identified."
    end

    if item.bag == nil
        or item.bagSlot == nil
    then
        return nil,
            "The bag location could not be identified."
    end

    if not AL.ItemUtils:
        IsBagItemTradeable(
            item.bag,
            item.bagSlot
        )
    then
        return nil,
            "This item does not have an active "
            .. "raid-trade timer."
    end

    local holder =
        UnitName("player")

    local existing =
        AL.LootSession:
            FindFirstUnassigned(
                item.id,
                holder
            )

    if existing then
        -- Alt-clicking an intentionally hidden,
        -- unassigned item restores it to the window.
        existing.skipped = nil
        return existing
    end

    local physicalCopyCount =
        self:GetCurrentBagCount(
            item.id
        )

    local registeredCopyCount =
        AL.LootSession:
            CountHeldCopies(
                item.id,
                holder
            )

    if registeredCopyCount
        < physicalCopyCount
    then
        local copy =
            AL:ShallowCopy(item)

        copy.quantity = 1
        copy.registrationSource =
            "alt_click"

        return AL.LootSession:
            AddCollected(
                copy,
                holder
            )
    end

    return nil,
        "This item is already tracked "
        .. "and no unassigned copy is available."
end

function BagHooks:HandleModifiedClick(
    button,
    mouseButton
)
    --------------------------------------------------
    -- Only Alt + Left Click is ours.
    --------------------------------------------------

    if mouseButton ~= "LeftButton" then
        return
    end

    if not IsAltKeyDown() then
        return
    end

    --------------------------------------------------
    -- Ctrl + Alt is used by Ascension's transmog
    -- system. Never treat it as an AscensionLoot
    -- modified click.
    --------------------------------------------------

    if IsControlKeyDown() then
        return
    end

    --------------------------------------------------
    -- Resolve the clicked bag slot.
    --------------------------------------------------

    local bag,
        slot =
            self:GetBagAndSlot(
                button
            )

    if bag == nil
        or slot == nil
    then
        return
    end

    local bagItem =
        AL.ItemUtils:
            FromBagSlot(
                bag,
                slot
            )

    if not bagItem then
        return
    end

    --------------------------------------------------
    -- IMPORTANT:
    --
    -- Rolling and persistent loot tracking are two
    -- separate things.
    --
    -- Any bag item can be rolled.
    --
    -- Only raid-distributable items with an active
    -- temporary raid-trade timer are persistently
    -- registered.
    --------------------------------------------------

    local targetItem =
        bagItem

    local eligibleForTracking =
        AL.ItemUtils:
            ShouldTrack(
                bagItem
            )

    local hasRaidTradeTimer =
        false

    if eligibleForTracking then
        hasRaidTradeTimer =
            AL.ItemUtils:
                IsBagItemTradeable(
                    bag,
                    slot
                )
    end

    local canPersistentlyTrack =
        eligibleForTracking
        and hasRaidTradeTimer

    --------------------------------------------------
    -- Register only genuine raid-tradeable loot.
    --------------------------------------------------

    if canPersistentlyTrack then
        local registeredItem,
            errorMessage =
                self:
                    EnsureBagItemRegistered(
                        bagItem
                    )

        if registeredItem then
            targetItem =
                registeredItem
        else
            --------------------------------------------------
            -- Tracking failure must NEVER prevent a normal
            -- roll from starting.
            --------------------------------------------------

            AL:Print(
                (
                    errorMessage
                    or "The item could not be registered."
                )
                .. " Starting an untracked roll instead.",
                1,
                0.5,
                0.2
            )

            targetItem =
                bagItem
        end
    end

    --------------------------------------------------
    -- Shift + Alt = direct SR assignment.
    --
    -- Direct assignment creates persistent loot state,
    -- so only permit it for a verified raid-tradeable
    -- item.
    --------------------------------------------------

    if IsShiftKeyDown() then
        if not canPersistentlyTrack then
            AL:Print(
                "Direct assignment requires an active "
                .. "raid-trade timer. Use Alt-click "
                .. "for a normal roll.",
                1,
                0.5,
                0.2
            )

            return
        end

        AL.Loot:
            DirectAward(
                targetItem
            )

        return
    end

    --------------------------------------------------
    -- Plain Alt-click:
    --
    -- ALWAYS allow the roll, regardless of whether
    -- this item is persistently tracked.
    --------------------------------------------------

    AL.Roll:
        StartForItem(
            targetItem
        )

    if AL.UI then
        AL.UI:ShowLoot()
    end
end
--------------------------------------------------
-- Initialisation
--------------------------------------------------

function BagHooks:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true

    -- Existing bags become the initial baseline.
    -- They are not imported as freshly looted items.
    self.bagSnapshot =
        self:BuildBagSnapshot()

    self.snapshotReady = true

    if hooksecurefunc
        and ContainerFrameItemButton_OnModifiedClick
    then
        hooksecurefunc(
            "ContainerFrameItemButton_OnModifiedClick",
            function(button, mouseButton)
                BagHooks:HandleModifiedClick(
                    button,
                    mouseButton
                )
            end
        )
    else
        AL:Print(
            "Could not install the default "
                .. "bag Alt-click hook.",
            1,
            0.4,
            0.2
        )
    end
end