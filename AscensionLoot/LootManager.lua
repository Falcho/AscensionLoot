local AL = AscensionLoot

AL.Loot = AL.Loot or {}
local Loot = AL.Loot

Loot.items = {}
Loot.pendingAward = nil
Loot.confirmData = nil
Loot.autoQueue = {}
Loot.collectionQueue = {}
Loot.pendingCollection = nil
Loot.pendingMasterLoot = nil

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

    if AL.db.settings.autoShowLoot
        and AL.UI
    then
        AL.UI:ShowLoot()
    end
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
        and self.pendingCollection.slot == slot
    then
        local collection =
            self.pendingCollection

        self.pendingCollection = nil

        AL.LootSession:AddCollected(
            collection.item,
            collection.holder
        )

        AL:Print(string.format(
            "Collected %s for later distribution. Holder: %s.",
            collection.item.link
                or collection.item.name,
            collection.holder
        ))
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

function Loot:ProcessAutoQueue()
    if not self.isOpen or #self.autoQueue == 0 or GetTime() < self.nextAutoAction then return end
    self.nextAutoAction = GetTime() + 0.25

    if self.pendingCollection
        or self.pendingMasterLoot
    then
        return
    end

    if #self.collectionQueue > 0 then
        local action = table.remove(self.collectionQueue, 1)
        local currentLink = GetLootSlotLink(action.slot)

        if not currentLink
            or AL:GetItemID(currentLink) ~= action.item.id
        then
            return
        end

        local holder =
            action.holder
            or self:GetHolderName()

        local candidateIndex =
            self:FindCandidateIndex(
                action.slot,
                holder
            )

        if not candidateIndex then
            AL:Print(
                holder .. " is not eligible to receive " ..
                tostring(action.item.link) .. ".",
                1,
                0.3,
                0.3
            )
            return
        end

        if action.trackInSession then
            self.pendingCollection = {
                slot = action.slot,
                item = action.item,
                holder = holder,
            }
        else
            self.pendingMasterLoot = {
                slot = action.slot,
                itemID = action.item.id,
                itemLink = action.item.link,
                holder = holder,
            }
        end

        GiveMasterLoot(
            action.slot,
            candidateIndex
        )

        return
    end

    local action = table.remove(self.autoQueue, 1)
    if action.kind == "coin" then
        if not GetLootSlotLink(action.slot) then
            LootSlot(action.slot)
        end
        return
    end

    local currentLink = GetLootSlotLink(action.slot)
    if not currentLink or AL:GetItemID(currentLink) ~= action.itemID then return end
    local currentItem = lootSlotItem(action.slot)
    if not self:ShouldAutoLoot(currentItem) then return end

    local method = GetLootMethod()
    if method == "master" then
        if not self:IsMasterLooter() then return end
        local me = UnitName("player")
        local candidateIndex = self:FindCandidateIndex(action.slot, me)
        if candidateIndex then GiveMasterLoot(action.slot, candidateIndex) end
    else
        LootSlot(action.slot)
    end
end

function Loot:OnUpdate()
    self:ProcessAutoQueue()
end

function Loot:LoadDemo()
    AL.SoftReserve:LoadDemo()
    self.demo = true
    self.isOpen = false
    self.items = {
        { slot = 1, id = 12504, link = "|cffa335ee|Hitem:12504:0:0:0:0:0:0:0|h[Demo: Shared Soft Reserve]|h|r", name = "Demo: Shared Soft Reserve", icon = "Interface\\Icons\\INV_Misc_QuestionMark", quality = 4, quantity = 1, demo = true },
        { slot = 2, id = 19857, link = "|cffa335ee|Hitem:19857:0:0:0:0:0:0:0|h[Demo: Double Reserve]|h|r", name = "Demo: Double Reserve", icon = "Interface\\Icons\\INV_Misc_QuestionMark", quality = 4, quantity = 1, demo = true },
        { slot = 3, id = 999999, link = "|cff0070dd|Hitem:999999:0:0:0:0:0:0:0|h[Demo: Open Roll Item]|h|r", name = "Demo: Open Roll Item", icon = "Interface\\Icons\\INV_Misc_QuestionMark", quality = 3, quantity = 1, demo = true },
    }
    if AL.UI then AL.UI:Show("loot") AL.UI:RefreshAll() end
end
