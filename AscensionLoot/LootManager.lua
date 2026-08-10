local AL = AscensionLoot

AL.Loot = AL.Loot or {}
local Loot = AL.Loot

local function isDemoItem(item)
    if not item then
        return false
    end

    if item.demo == true
        or item.source == "demo"
        or item.registrationSource == "demo"
    then
        return true
    end

    local name =
        item.name
        or item.itemName

    if type(name) == "string"
        and string.find(
            name,
            "^Demo:"
        )
    then
        return true
    end

    local link =
        item.link
        or item.itemLink

    if type(link) == "string"
        and string.find(
            link,
            "%[Demo:"
        )
    then
        return true
    end

    return false
end

Loot.items = {}
Loot.pendingAward = nil
Loot.confirmData = nil
Loot.autoQueue = {}
Loot.collectionQueue = {}
Loot.pendingCollection = nil
Loot.pendingMasterLoot = nil

-- Tracked Master Loot items waiting to be physically
-- confirmed in this client's bags before auto-opening
-- the loot window.
Loot.pendingAutoShows = {}

Loot.autoLooting = false
Loot.nextAutoAction = 0
Loot.isOpen = false

local function lootSlotItem(slot)
    local icon, name, quantity, quality, locked =
        GetLootSlotInfo(slot)

    local link = GetLootSlotLink(slot)

    if not link then
        return nil
    end

    local item = {
        source = "loot",
        slot = slot,
        id = AL:GetItemID(link),
        link = link,
        name = name or link,
        icon = icon,
        quantity = quantity or 1,
        quality = quality or 0,
        locked = locked,
    }

    item.bindType = AL.ItemUtils:GetBindType(link)
    item.key = AL:GetItemKey(item)

    return item
end

function Loot:IsMasterLooter()
    local method, partyMaster, raidMaster = GetLootMethod()
    if method ~= "master" then return false end

    if AL:IsInRaid() then
        if UnitInRaid then
            local playerIndex = UnitInRaid("player")
            if playerIndex and raidMaster then return playerIndex == raidMaster end
        end
        return raidMaster == nil or raidMaster == 0
    end

    return partyMaster == 0 or partyMaster == nil
end

function Loot:GetHolderName()
    if AL.db.settings.lootHolderMode == "NAMED" then
        local configured = AL:Trim(AL.db.settings.lootHolderName)
        if configured ~= "" then
            return configured
        end
    end

    return UnitName("player")
end

function Loot:Refresh()
    if not self.isOpen and not self.demo then return end
    if self.demo then
        if AL.UI then AL.UI:RefreshLoot() end
        return
    end

    local oldBySlot = {}
    for _, item in ipairs(self.items) do oldBySlot[item.slot] = item end

    local refreshed = {}
    for slot = 1, GetNumLootItems() do
        local item = lootSlotItem(slot)
        if item then
            local old = oldBySlot[slot]
            if old and old.id == item.id then
                item.skipped = old.skipped
            end
            table.insert(refreshed, item)
        end
    end
    self.items = refreshed
    if AL.UI then AL.UI:RefreshLoot() end
end

function Loot:OnOpened(autoLoot)
    if self.demo then
        AL.SoftReserve:LoadFromDatabase()
    end

    self.demo = false
    self.isOpen = true

    self.autoLooting =
        autoLoot == 1
        or autoLoot == true

    self.pendingAward = nil
    self.pendingCollection = nil
    self.pendingMasterLoot = nil

    self:Refresh()
    self:BuildCollectionQueue()
    self:BuildAutoQueue()
end

function Loot:OnClosed()
    self.isOpen = false
    self.autoLooting = false

    self.autoQueue = {}
    self.collectionQueue = {}

    self.pendingCollection = nil
    self.pendingMasterLoot = nil

    if not self.demo then
        self.items = {}
    end

    if AL.UI then
        AL.UI:RefreshLoot()
    end
end

function Loot:GetItemBySlot(slot)
    for _, item in ipairs(self.items) do
        if item.slot == slot then return item end
    end
end

function Loot:FindCandidateIndex(slot, playerName)
    local wanted = AL:NormalizeName(playerName)
    if not wanted then return nil end

    for index = 1, 40 do
        local candidate = GetMasterLootCandidate(slot, index)
        if not candidate then
            if index > 1 then break end
        elseif AL:NormalizeName(candidate) == wanted then
            return index
        end
    end
    return nil
end

function Loot:ValidateItemSlot(item)
    if not item or item.demo then return false, "Demo items cannot be awarded." end
    if not self.isOpen then return false, "The loot window is not open." end
    if not item.slot then return false, "The item has no active loot slot." end

    local currentLink = GetLootSlotLink(item.slot)
    if not currentLink then return false, "That loot slot is no longer available." end
    if AL:GetItemID(currentLink) ~= item.id then
        return false, "The loot slot changed. Refresh the loot window before awarding."
    end
    return true
end

function Loot:Award(item, playerName, reason)
    local valid, errorMessage = self:ValidateItemSlot(item)
    if not valid then AL:Print(errorMessage, 1, 0.3, 0.3) return end
    if not self:IsMasterLooter() then
        AL:Print("You are not the master looter.", 1, 0.3, 0.3)
        return
    end
    if not playerName or AL:Trim(playerName) == "" then
        AL:Print("No winner is selected.", 1, 0.3, 0.3)
        return
    end

    local candidateIndex = self:FindCandidateIndex(item.slot, playerName)
    if not candidateIndex then
        AL:Print(playerName .. " is not an eligible master-loot candidate for this item.", 1, 0.3, 0.3)
        return
    end

    self.confirmData = {
        item = item,
        playerName = playerName,
        reason = reason or (AL.Roll.active and AL.Roll.active.label) or "Manual",
        candidateIndex = candidateIndex,
    }

    if AL.db.settings.confirmAwards then
        StaticPopup_Show("ASCENSIONLOOT_CONFIRM_AWARD", item.link or item.name, playerName)
    else
        self:ConfirmAward()
    end
end

function Loot:ConfirmAward()
    local data = self.confirmData
    self.confirmData = nil
    if not data then return end

    local valid, errorMessage = self:ValidateItemSlot(data.item)
    if not valid then AL:Print(errorMessage, 1, 0.3, 0.3) return end

    local candidateIndex = self:FindCandidateIndex(data.item.slot, data.playerName)
    if not candidateIndex then
        AL:Print(data.playerName .. " is no longer a loot candidate.", 1, 0.3, 0.3)
        return
    end

    self.pendingAward = {
        slot = data.item.slot,
        itemID = data.item.id,
        itemLink = data.item.link,
        playerName = data.playerName,
        reason = data.reason,
        winningRoll = AL.Roll.active and AL.Roll.active.winningRoll or nil,
    }

    GiveMasterLoot(data.item.slot, candidateIndex)
end

function Loot:OnSlotCleared(slot)
    --------------------------------------------------
    -- Item collected for later distribution
    --------------------------------------------------

    if self.pendingCollection
        and self.pendingCollection.slot
            == slot
    then
        local collection =
            self.pendingCollection

        self.pendingCollection =
            nil

        if collection.holderIsPlayer
            and AL.BagHooks
            and AL.BagHooks
                .ExpectMasterLoot
        then
            --------------------------------------------------
            -- Do NOT create the LootSession entry here.
            --
            -- LOOT_SLOT_CLEARED only proves that the corpse
            -- slot was processed. BagHooks will create the
            -- exact number of entries when the actual bag
            -- count increases.
            --------------------------------------------------

            AL:Print(string.format(
                "Collected %s. Waiting for bag confirmation.",
                collection.item.link
                    or collection.item.name
                    or "tracked item"
            ))

        else
            --------------------------------------------------
            -- A different configured player is the holder.
            -- We cannot inspect that player's bags from this
            -- client, so LOOT_SLOT_CLEARED remains the best
            -- available confirmation.
            --------------------------------------------------

            local copies =
                tonumber(
                    collection.item.quantity
                )
                or 1

            AL.LootSession:
                AddCollectedCopies(
                    collection.item,
                    collection.holder,
                    copies
                )

            AL:Print(string.format(
                "Collected %d %s of %s for %s.",
                copies,
                copies == 1
                    and "copy"
                    or "copies",
                collection.item.link
                    or collection.item.name
                    or "tracked item",
                collection.holder
                    or "Unknown"
            ))

            if AL.db.settings.autoShowLoot
                and AL.UI
            then
                AL.UI:ShowLoot()
            end
        end
    end

    --------------------------------------------------
    -- Untracked item assigned directly to the holder
    --------------------------------------------------

    if self.pendingMasterLoot
        and self.pendingMasterLoot.slot == slot
    then
        self.pendingMasterLoot = nil
    end

    --------------------------------------------------
    -- Item awarded directly from the loot window
    --------------------------------------------------

    if self.pendingAward
        and self.pendingAward.slot == slot
    then
        local award =
            self.pendingAward

        self.pendingAward = nil

        AL:AddHistory({
            itemID = award.itemID,
            itemLink = award.itemLink,
            winner = award.playerName,
            reason = award.reason,
            winningRoll = award.winningRoll,
            masterLooter = UnitName("player"),
        })

        AL:Print(string.format(
            "Awarded %s to %s.",
            award.itemLink or "item",
            award.playerName or "Unknown"
        ))

        if AL.Roll
            and AL.Roll.active
            and AL.Roll.active.item
            and AL.Roll.active.item.slot == slot
        then
            AL.Roll.active = nil
        end
    end

    self:Refresh()
end

function Loot:OnBindConfirm(slot)
    if AL.db.settings
        .autoConfirmMasterLootToSelf == false
    then
        return
    end

    local pending =
        self.pendingCollection
        or self.pendingMasterLoot

    if not pending then
        return
    end

    if pending.slot ~= slot then
        return
    end

    ConfirmLootSlot(slot)
end

function Loot:AssignHeldItem(item, playerName, reason)
    if not item or not playerName then return end

    local holder = UnitName("player")

    local sessionEntry =
        item.sessionID and item
        or AL.LootSession:FindFirstUnassigned(item.id, holder)

    if not sessionEntry then
        sessionEntry = AL.LootSession:AddCollected(item, holder)
    end

    AL.LootSession:Assign(
        sessionEntry,
        playerName,
        reason,
        AL.Roll.active and AL.Roll.active.winningRoll
    )

    if AL.Roll.active
        and AL:GetItemKey(AL.Roll.active.item) == AL:GetItemKey(item)
    then
        AL.Roll.active = nil
    end
end

function Loot:AwardActiveWinners(item)
    local active = AL.Roll.active

    if not active then
        AL:Print(
            "There is no active roll.",
            1,
            0.5,
            0.2
        )

        return
    end

    if active.state ~= "finished" then
        AL:Print(
            "Finish the roll before awarding.",
            1,
            0.5,
            0.2
        )

        return
    end

    if AL:GetItemKey(active.item)
        ~= AL:GetItemKey(item)
    then
        AL:Print(
            "The active roll belongs to a different item.",
            1,
            0.5,
            0.2
        )

        return
    end

    local winners =
        AL.Roll:GetWinners()

    if #winners == 0 then
        AL:Print(
            "There are no proposed winners.",
            1,
            0.5,
            0.2
        )

        return
    end

    local copies = {}

    if AL.LootSession
        and AL.LootSession.GetUnassignedCopies
    then
        copies =
            AL.LootSession:GetUnassignedCopies(
                item.id,
                UnitName("player")
            )
    end

    if #copies == 0 then
        -- This fallback preserves direct awarding
        -- from a currently open loot window.
        if item.source == "loot"
            and winners[1]
        then
            self:Award(
                item,
                winners[1].name,
                winners[1].categoryLabel
            )

            return
        end

        AL:Print(
            "No unassigned copies of this item "
                .. "were found in the loot session.",
            1,
            0.3,
            0.3
        )

        return
    end

    local awardCount =
        math.min(#copies, #winners)

    for index = 1, awardCount do
        local entry = copies[index]
        local winner = winners[index]

        AL.LootSession:Assign(
            entry,
            winner.name,
            winner.categoryLabel,
            winner.roll,
            true
        )
    end

    AL:Print(string.format(
        "Assigned %d %s of %s.",
        awardCount,
        awardCount == 1
            and "copy"
            or "copies",
        item.link or item.name
    ))

    AL.Roll.active = nil

    if AL.UI then
        AL.UI:RefreshAll()
    end

    -- All assignments are now recorded.
    -- Start the first pending trade.
    if AL.Trade
        and AL.db.settings.autoOpenTrade
    then
        AL.Trade:TryStart()
    end
end

-- Compatibility wrapper for old UI references.
function Loot:AwardActiveWinner(item)
    self:AwardActiveWinners(item)
end

function Loot:DirectAward(item)
    if not item then return end

    local reservers = AL.SoftReserve:GetReservers(item.id)

    if #reservers == 0 then
        AL:Print(
            "This item has no soft reserver. Start a roll instead.",
            1,
            0.5,
            0.2
        )
        return
    end

    if #reservers > 1 then
        AL:Print(
            "This item has multiple soft reservers. Start an SR roll.",
            1,
            0.5,
            0.2
        )
        return
    end

    local winner = reservers[1].name

    if item.source == "loot" then
        self:Award(item, winner, "Solo Soft Reserve")
    else
        self:AssignHeldItem(item, winner, "Solo Soft Reserve")
    end
end

function Loot:ShouldAutoLoot(item)
    if not item or not item.id then return false end
    if AL.db.settings.protectReservedItems and (AL.SoftReserve:IsReserved(item.id) or AL.SoftReserve:IsHardReserved(item.id)) then
        return false
    end
    if item.quality == 0 and AL.db.settings.autoLootPoor then return true end
    if item.quality == 1 and AL.db.settings.autoLootCommon then return true end
    return false
end

function Loot:BuildCollectionQueue()
    self.collectionQueue = {}

    if not self:IsMasterLooter() then
        return
    end

    local settings = AL.db.settings

    local assignEverythingToSelf =
        self.autoLooting
        and settings.autoMasterLootToSelf

    local collectTrackedLoot =
        settings.autoCollectTrackedLoot

    if not assignEverythingToSelf
        and not collectTrackedLoot
    then
        return
    end

    for slot = GetNumLootItems(), 1, -1 do
        local item =
            lootSlotItem(slot)

        if item then
            local shouldTrack =
                AL.ItemUtils:ShouldTrack(item)

            local shouldQueue =
                assignEverythingToSelf
                or (
                    collectTrackedLoot
                    and shouldTrack
                )

            if shouldQueue then
                local holder

                if assignEverythingToSelf then
                    holder = UnitName("player")
                else
                    holder = self:GetHolderName()
                end

                table.insert(
                    self.collectionQueue,
                    {
                        slot = slot,
                        item = item,
                        holder = holder,
                        trackInSession = shouldTrack,
                    }
                )
            end
        end
    end
end

function Loot:BuildAutoQueue()
    self.autoQueue = {}
    self.nextAutoAction =
        GetTime() + 0.25

    local masterLootHandlesAllItems =
        self.autoLooting
        and self:IsMasterLooter()
        and AL.db.settings.autoMasterLootToSelf

    for slot = GetNumLootItems(), 1, -1 do
        local link =
            GetLootSlotLink(slot)

        if link then
            -- During Master Looter auto-loot, every item
            -- is already handled by collectionQueue.
            if not masterLootHandlesAllItems then
                local item =
                    lootSlotItem(slot)

                if self:ShouldAutoLoot(item) then
                    table.insert(
                        self.autoQueue,
                        {
                            kind = "item",
                            slot = slot,
                            itemID = item.id,
                        }
                    )
                end
            end

        elseif AL.db.settings.autoLootCoins then
            local _, name =
                GetLootSlotInfo(slot)

            if name then
                table.insert(
                    self.autoQueue,
                    {
                        kind = "coin",
                        slot = slot,
                    }
                )
            end
        end
    end
end

--------------------------------------------------
-- Resolve current corpse slots dynamically
--------------------------------------------------

function Loot:FindCurrentItemSlot(
    itemID,
    preferredSlot
)
    local wantedItemID =
        tonumber(
            itemID
        )

    if not wantedItemID then
        return nil
    end

    --------------------------------------------------
    -- Fast path: the original slot is still valid.
    --------------------------------------------------

    if preferredSlot then
        local link =
            GetLootSlotLink(
                preferredSlot
            )

        if link
            and tonumber(
                AL:GetItemID(link)
            ) == wantedItemID
        then
            return preferredSlot
        end
    end

    --------------------------------------------------
    -- Fallback: loot slots may have changed while
    -- previous entries were collected.
    --------------------------------------------------

    for slot = 1,
        GetNumLootItems()
    do
        local link =
            GetLootSlotLink(
                slot
            )

        if link
            and tonumber(
                AL:GetItemID(link)
            ) == wantedItemID
        then
            return slot
        end
    end

    return nil
end

function Loot:FindCurrentCoinSlot(
    preferredSlot
)
    if preferredSlot
        and not GetLootSlotLink(
            preferredSlot
        )
    then
        local _,
            name =
                GetLootSlotInfo(
                    preferredSlot
                )

        if name then
            return preferredSlot
        end
    end

    for slot = 1,
        GetNumLootItems()
    do
        if not GetLootSlotLink(slot) then
            local _,
                name =
                    GetLootSlotInfo(
                        slot
                    )

            if name then
                return slot
            end
        end
    end

    return nil
end

function Loot:ProcessAutoQueue()
    if not self.isOpen then
        return
    end

    --------------------------------------------------
    -- Either queue may contain work.
    --------------------------------------------------

    if #self.collectionQueue == 0
        and #self.autoQueue == 0
    then
        return
    end

    if GetTime()
        < self.nextAutoAction
    then
        return
    end

    self.nextAutoAction =
        GetTime() + 0.25

    --------------------------------------------------
    -- Wait for the previous Master Loot operation to
    -- be confirmed before starting another one.
    --------------------------------------------------

    if self.pendingCollection
        or self.pendingMasterLoot
    then
        return
    end

    --------------------------------------------------
    -- Master Loot collection always has priority.
    --------------------------------------------------

    if #self.collectionQueue > 0 then
        local action =
            self.collectionQueue[1]

        local currentSlot =
            self:
                FindCurrentItemSlot(
                    action.item.id,
                    action.slot
                )

        if not currentSlot then
            table.remove(
                self.collectionQueue,
                1
            )

            AL:Print(
                "Could not find "
                .. tostring(
                    action.item.link
                    or action.item.name
                    or "tracked item"
                )
                .. " on the current corpse.",
                1,
                0.4,
                0.2
            )

            return
        end

        --------------------------------------------------
        -- We have successfully resolved this action, so
        -- remove it from the queue.
        --------------------------------------------------

        table.remove(
            self.collectionQueue,
            1
        )

        action.slot =
            currentSlot

        action.item.slot =
            currentSlot

        local holder =
            action.holder
            or self:GetHolderName()

        local candidateIndex =
            self:
                FindCandidateIndex(
                    currentSlot,
                    holder
                )

        if not candidateIndex then
            AL:Print(
                tostring(holder)
                .. " is not eligible to receive "
                .. tostring(
                    action.item.link
                    or action.item.name
                )
                .. ".",
                1,
                0.3,
                0.3
            )

            return
        end

        local holderIsPlayer =
            AL:NormalizeName(
                holder
            )
            == AL:NormalizeName(
                UnitName("player")
            )

        --------------------------------------------------
        -- Tell BagHooks what we expect BEFORE calling
        -- GiveMasterLoot().
        --------------------------------------------------

        if action.trackInSession
            and holderIsPlayer
            and AL.BagHooks
            and AL.BagHooks
                .ExpectMasterLoot
        then
            AL.BagHooks:
                ExpectMasterLoot(
                    action.item,
                    action.item.quantity
                        or 1
                )
        end

        if action.trackInSession then
            self.pendingCollection = {
                slot =
                    currentSlot,

                item =
                    action.item,

                holder =
                    holder,

                holderIsPlayer =
                    holderIsPlayer,
            }
        else
            self.pendingMasterLoot = {
                slot =
                    currentSlot,

                itemID =
                    action.item.id,

                itemLink =
                    action.item.link,

                holder =
                    holder,
            }
        end

        GiveMasterLoot(
            currentSlot,
            candidateIndex
        )

        return
    end

    --------------------------------------------------
    -- Ordinary auto-loot queue
    --------------------------------------------------

    local action =
        table.remove(
            self.autoQueue,
            1
        )

    if not action then
        return
    end

    if action.kind == "coin" then
        local coinSlot =
            self:
                FindCurrentCoinSlot(
                    action.slot
                )

        if coinSlot then
            LootSlot(
                coinSlot
            )
        end

        return
    end

    --------------------------------------------------
    -- Item slots are resolved again because earlier
    -- Master Loot operations may have changed the
    -- corpse state.
    --------------------------------------------------

    local currentSlot =
        self:
            FindCurrentItemSlot(
                action.itemID,
                action.slot
            )

    if not currentSlot then
        return
    end

    local currentItem =
        lootSlotItem(
            currentSlot
        )

    if not self:
        ShouldAutoLoot(
            currentItem
        )
    then
        return
    end

    local method =
        GetLootMethod()

    if method == "master" then
        if not self:IsMasterLooter() then
            return
        end

        local me =
            UnitName("player")

        local candidateIndex =
            self:
                FindCandidateIndex(
                    currentSlot,
                    me
                )

        if candidateIndex then
            GiveMasterLoot(
                currentSlot,
                candidateIndex
            )
        end
    else
        LootSlot(
            currentSlot
        )
    end
end

function Loot:OnUpdate()
    self:ProcessAutoQueue()
end

function Loot:LoadDemo()
    -- Remove remnants from an earlier demo before
    -- creating another set.
    self:ClearDemo(true)

    AL.SoftReserve:LoadDemo()

    self.demo = true
    self.isOpen = false

    self.items = {
        {
            source = "demo",
            demo = true,
            slot = 1,
            id = 12504,

            link =
                "|cffa335ee"
                .. "|Hitem:12504:0:0:0:0:0:0:0"
                .. "|h[Demo: Shared Soft Reserve]"
                .. "|h|r",

            name =
                "Demo: Shared Soft Reserve",

            icon =
                "Interface\\Icons\\"
                .. "INV_Misc_QuestionMark",

            quality = 4,
            quantity = 1,
        },

        {
            source = "demo",
            demo = true,
            slot = 2,
            id = 19857,

            link =
                "|cffa335ee"
                .. "|Hitem:19857:0:0:0:0:0:0:0"
                .. "|h[Demo: Double Reserve]"
                .. "|h|r",

            name =
                "Demo: Double Reserve",

            icon =
                "Interface\\Icons\\"
                .. "INV_Misc_QuestionMark",

            quality = 4,
            quantity = 1,
        },

        {
            source = "demo",
            demo = true,
            slot = 3,
            id = 999999,

            link =
                "|cff0070dd"
                .. "|Hitem:999999:0:0:0:0:0:0:0"
                .. "|h[Demo: Open Roll Item]"
                .. "|h|r",

            name =
                "Demo: Open Roll Item",

            icon =
                "Interface\\Icons\\"
                .. "INV_Misc_QuestionMark",

            quality = 3,
            quantity = 1,
        },
    }

    if AL.UI then
        AL.UI:Show("loot")
        AL.UI:RefreshAll()
    end
end

function Loot:ClearDemo(silent)
    local visibleRemoved = 0
    local sessionRemoved = 0
    local historyRemoved = 0

    --------------------------------------------------
    -- Remove visible demo loot
    --------------------------------------------------

    for index =
        #(self.items or {}),
        1,
        -1
    do
        local item =
            self.items[index]

        if isDemoItem(item) then
            table.remove(
                self.items,
                index
            )

            visibleRemoved =
                visibleRemoved + 1
        end
    end

    --------------------------------------------------
    -- Remove persistent demo-session entries
    --------------------------------------------------

    if AL.db
        and AL.db.lootSession
        and AL.db.lootSession.items
    then
        for index =
            #AL.db.lootSession.items,
            1,
            -1
        do
            local entry =
                AL.db.lootSession.items[
                    index
                ]

            if isDemoItem(entry) then
                table.remove(
                    AL.db.lootSession.items,
                    index
                )

                sessionRemoved =
                    sessionRemoved + 1
            end
        end
    end

    --------------------------------------------------
    -- Remove demo history entries
    --------------------------------------------------

    if AL.db
        and AL.db.history
    then
        for index =
            #AL.db.history,
            1,
            -1
        do
            local historyEntry =
                AL.db.history[index]

            if isDemoItem(
                historyEntry
            ) then
                table.remove(
                    AL.db.history,
                    index
                )

                historyRemoved =
                    historyRemoved + 1
            end
        end
    end

    --------------------------------------------------
    -- Cancel an active demo roll
    --------------------------------------------------

    if AL.Roll
        and AL.Roll.active
        and isDemoItem(
            AL.Roll.active.item
        )
    then
        AL.Roll.active = nil
    end

    --------------------------------------------------
    -- Clear pending demo loot operations
    --------------------------------------------------

    if self.confirmData
        and isDemoItem(
            self.confirmData.item
        )
    then
        self.confirmData = nil
    end

    if self.pendingCollection
        and isDemoItem(
            self.pendingCollection.item
        )
    then
        self.pendingCollection = nil
    end

    if self.pendingMasterLoot
        and isDemoItem({
            link =
                self.pendingMasterLoot
                    .itemLink,
        })
    then
        self.pendingMasterLoot = nil
    end

    if self.pendingAward
        and isDemoItem({
            link =
                self.pendingAward
                    .itemLink,
        })
    then
        self.pendingAward = nil
    end

    --------------------------------------------------
    -- Remove demo references from trade assistance
    --------------------------------------------------

    if AL.Trade then
        if isDemoItem(
            AL.Trade.requestedEntry
        )
        then
            AL.Trade.requestedEntry =
                nil

            AL.Trade.requestedWinner =
                nil

            AL.Trade.tradeTarget =
                nil
        end

        for index =
            #(AL.Trade.filledEntries or {}),
            1,
            -1
        do
            local value =
                AL.Trade.filledEntries[
                    index
                ]

            if value
                and isDemoItem(
                    value.entry
                )
            then
                table.remove(
                    AL.Trade.filledEntries,
                    index
                )
            end
        end

        for index =
            #(AL.Trade.pendingVerification or {}),
            1,
            -1
        do
            local value =
                AL.Trade.pendingVerification[
                    index
                ]

            if value
                and isDemoItem(
                    value.entry
                )
            then
                table.remove(
                    AL.Trade.pendingVerification,
                    index
                )
            end
        end
    end

    --------------------------------------------------
    -- Leave demo mode and restore real reserves
    --------------------------------------------------

    self.demo = false

    if AL.SoftReserve
        and AL.SoftReserve
            .LoadFromDatabase
    then
        AL.SoftReserve:
            LoadFromDatabase()
    end

    --------------------------------------------------
    -- Refresh the interface
    --------------------------------------------------

    if AL.UI then
        AL.UI:RefreshAll()
    end

    if not silent then
        local totalRemoved =
            visibleRemoved
            + sessionRemoved

        if totalRemoved == 0
            and historyRemoved == 0
        then
            AL:Print(
                "No UI demo data was found."
            )
        else
            AL:Print(string.format(
                "Cleared %d demo item %s and %d demo history %s.",
                totalRemoved,
                totalRemoved == 1
                    and "entry"
                    or "entries",
                historyRemoved,
                historyRemoved == 1
                    and "entry"
                    or "entries"
            ))
        end
    end
end
