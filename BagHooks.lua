local AL = AscensionLoot

AL.BagHooks = AL.BagHooks or {}
local BagHooks = AL.BagHooks

BagHooks.initialized = false
BagHooks.snapshotReady = false
BagHooks.bagSnapshot = {}
BagHooks.scanPending = false
BagHooks.scanAt = 0

local BAG_SCAN_DELAY = 0.50

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
-- Automatic Group Loot registration
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

    -- Automatic bag registration is intended for
    -- group content. Alt-click remains available
    -- as a fallback while solo.
    if not AL:IsInRaid()
        and not AL:IsInParty()
    then
        return false
    end

    local lootMethod =
        GetLootMethod and GetLootMethod()

    -- Master Loot already registers collected items
    -- through LootManager:OnSlotCleared(). Registering
    -- them here as well would create duplicates.
    if lootMethod == "master" then
        return false
    end

    return true
end

function BagHooks:GetRepresentativeItem(
    bucket
)
    if not bucket
        or not bucket.slots
    then
        return nil
    end

    for _, location in ipairs(
        bucket.slots
    ) do
        local item =
            AL.ItemUtils:FromBagSlot(
                location.bag,
                location.slot
            )

        if item then
            return item
        end
    end

    return nil
end

function BagHooks:RegisterNewCopies(
    bucket,
    newCopyCount
)
    local representative =
        self:GetRepresentativeItem(
            bucket
        )

    if not representative then
        return 0
    end

    if not AL.ItemUtils:ShouldTrack(
        representative
    ) then
        return 0
    end

    local holder =
        UnitName("player")

    local added = 0
    local locations =
        bucket.slots or {}

    for index = 1, newCopyCount do
        local item =
            AL:ShallowCopy(
                representative
            )

        -- Each session entry represents one copy,
        -- even if an item type can stack.
        item.quantity = 1
        item.source = "bag"
        item.registrationSource =
            "bag_update"

        if #locations > 0 then
            local location =
                locations[
                    (
                        (index - 1)
                        % #locations
                    ) + 1
                ]

            item.bag = location.bag
            item.bagSlot = location.slot
        end

        AL.LootSession:AddCollected(
            item,
            holder
        )

        added = added + 1
    end

    if added > 0 then
        AL:Print(string.format(
            "Added %d %s of %s "
                .. "to the loot session.",
            added,
            added == 1
                and "copy"
                or "copies",
            representative.link
                or representative.name
                or "item"
        ))

        if AL.db.settings.autoShowLoot
            and AL.UI
        then
            AL.UI:ShowLoot()
        end
    end

    return added
end

function BagHooks:ScanForNewEligibleItems()
    local currentSnapshot =
        self:BuildBagSnapshot()

    if not self.snapshotReady then
        self.bagSnapshot =
            currentSnapshot

        self.snapshotReady = true
        return
    end

    if self:ShouldAutomaticallyRegister() then
        for key, currentBucket in pairs(
            currentSnapshot
        ) do
            local previousBucket =
                self.bagSnapshot[key]

            local previousCount =
                previousBucket
                and previousBucket.count
                or 0

            local currentCount =
                currentBucket.count or 0

            local difference =
                currentCount
                - previousCount

            if difference > 0 then
                self:RegisterNewCopies(
                    currentBucket,
                    difference
                )
            end
        end
    end

    -- Always update the baseline, including while
    -- Master Loot is active. This prevents old changes
    -- being detected later after changing loot method.
    self.bagSnapshot =
        currentSnapshot
end

function BagHooks:OnBagUpdate()
    if not self.initialized then
        return
    end

    -- BAG_UPDATE can fire several times for one loot
    -- operation. Debouncing waits until the bags settle.
    self.scanPending = true
    self.scanAt =
        GetTime() + BAG_SCAN_DELAY
end

function BagHooks:OnUpdate()
    if not self.scanPending then
        return
    end

    if GetTime() < self.scanAt then
        return
    end

    self.scanPending = false
    self:ScanForNewEligibleItems()
end

--------------------------------------------------
-- Alt-click registration fallback
--------------------------------------------------

function BagHooks:EnsureBagItemRegistered(
    item
)
    if not item or not item.id then
        return nil,
            "The bag item could not be identified."
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
    if mouseButton ~= "LeftButton" then
        return
    end

    if not IsAltKeyDown() then
        return
    end

    local bag, slot =
        self:GetBagAndSlot(button)

    if bag == nil then
        return
    end

    local bagItem =
        AL.ItemUtils:FromBagSlot(
            bag,
            slot
        )

    if not bagItem then
        return
    end

    local targetItem = bagItem

    -- Eligible items should be represented by a
    -- persistent session entry before rolling.
    if AL.ItemUtils:ShouldTrack(
        bagItem
    ) then
        local errorMessage

        targetItem,
            errorMessage =
            self:EnsureBagItemRegistered(
                bagItem
            )

        if not targetItem then
            AL:Print(
                errorMessage
                    or "The item could not be registered.",
                1,
                0.5,
                0.2
            )

            return
        end
    end

    if IsShiftKeyDown() then
        AL.Loot:DirectAward(
            targetItem
        )
    else
        AL.Roll:StartForItem(
            targetItem
        )

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