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
Loot.hideBindPopupOnUpdate = false

-- Tracked Master Loot items waiting to be physically
-- confirmed in this client's bags before auto-opening
-- the loot window.
Loot.pendingAutoShows = {}

Loot.autoLooting = false
Loot.nextAutoAction = 0
Loot.isOpen = false

--------------------------------------------------
-- Master Looter handout reliability
--------------------------------------------------

local MASTER_LOOT_HANDOUT_TIMEOUT =
    1.5

local MASTER_LOOT_RETRY_DELAY =
    0.5

local MASTER_LOOT_MAX_ATTEMPTS =
    3

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
    local method,
        lootMaster =
            GetLootMethod()

    if method ~= "master" then
        return false
    end

    --------------------------------------------------
    -- WoW 3.3.5 uses 0 for the local player.
    --
    -- This is also how Blizzard's own PlayerFrame
    -- determines whether the player is Master Looter.
    --------------------------------------------------

    return lootMaster == 0
end

function Loot:IsMasterLootControlled(
    item
)
    if not item then
        return false
    end

    if not GetLootThreshold then
        return true
    end

    local threshold =
        tonumber(
            GetLootThreshold()
        )

    local quality =
        tonumber(
            item.quality
        )

    --------------------------------------------------
    -- If the client gives us incomplete information,
    -- preserve the safer Master Looter path.
    --------------------------------------------------

    if threshold == nil
        or quality == nil
    then
        return true
    end

    return quality
        >= threshold
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
        --------------------------------------------------
    -- Cancel expectations belonging to actions that
    -- never successfully left the corpse.
    --
    -- Successful actions have already been removed
    -- from collectionQueue and their BagHooks
    -- expectations must remain alive long enough for
    -- bag reconciliation.
    --------------------------------------------------

    for _, action in ipairs(
        self.collectionQueue
        or {}
    ) do
        self:
            CancelCollectionActionExpectation(
                action
            )
    end
    self.isOpen = false
    self.autoLooting = false

    self.autoQueue = {}
    self.collectionQueue = {}

    self.pendingCollection = nil
    self.pendingMasterLoot = nil
    self.hideBindPopupOnUpdate = false

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

--------------------------------------------------
-- Live loot-window item access
--------------------------------------------------

function Loot:GetLiveItemBySlot(
    slot
)
    if not self.isOpen
        or not slot
    then
        return nil
    end

    local item =
        lootSlotItem(
            slot
        )

    if not item then
        return nil
    end

    item.registrationSource =
        "live_loot"

    return item
end

--------------------------------------------------
-- Reserve a live corpse item for an AscensionLoot
-- roll instead of automatic collection.
--------------------------------------------------

function Loot:PrepareLiveRollItem(
    slot
)
    if not self.isOpen then
        return nil,
            "The loot window is not open."
    end

    if not self:IsMasterLooter() then
        return nil,
            "You must be the Master Looter "
            .. "to roll an item directly from "
            .. "the boss loot window."
    end
    if AL.db.settings
        .autoMasterLootToSelf
    then
        return nil,
            "Live boss-loot rolls are disabled while "
            .. "\"Assign all loot to me\" is enabled."
    end

    local item =
        self:
            GetLiveItemBySlot(
                slot
            )

    if not item then
        return nil,
            "The clicked loot item could not "
            .. "be identified."
    end

    --------------------------------------------------
    -- Only items controlled by the Master Looter can
    -- be distributed to the winner of a live roll.
    --
    -- Below-threshold loot cannot use GiveMasterLoot.
    --------------------------------------------------

    if not self:
        IsMasterLootControlled(
            item
        )
    then
        return nil,
            "This item is below the Master Loot "
            .. "threshold and cannot be awarded "
            .. "through an AscensionLoot roll."
    end

    if self:
        IsLootSlotLocked(
            slot
        )
    then
        return nil,
            "That loot item is currently locked."
    end

    --------------------------------------------------
    -- If GiveMasterLoot has already been attempted for
    -- this exact slot, it is too late to safely turn it
    -- into a live roll.
    --------------------------------------------------

    local pending =
        self.pendingCollection
        or self.pendingMasterLoot

    if pending
        and pending.slot == slot
        and pending.item
        and tonumber(
            pending.item.id
        ) == tonumber(
            item.id
        )
    then
        return nil,
            "AscensionLoot has already started "
            .. "assigning this item."
    end

    if self.pendingAward
        and self.pendingAward.slot
            == slot
    then
        return nil,
            "This item is already being awarded."
    end

    --------------------------------------------------
    -- Remove this physical item from the automatic
    -- Master Looter collection queue.
    --------------------------------------------------

    for index =
        #(
            self.collectionQueue
            or {}
        ),
        1,
        -1
    do
        local action =
            self.collectionQueue[
                index
            ]

        if action
            and action.item
            and tonumber(
                action.item.id
            ) == tonumber(
                item.id
            )
            and tonumber(
                action.slot
            ) == tonumber(
                slot
            )
        then
            self:
                CancelCollectionActionExpectation(
                    action
                )

            table.remove(
                self.collectionQueue,
                index
            )
        end
    end

    --------------------------------------------------
    -- It may also exist in the ordinary autoloot
    -- queue. Remove that action as well.
    --------------------------------------------------

    for index =
        #(
            self.autoQueue
            or {}
        ),
        1,
        -1
    do
        local action =
            self.autoQueue[
                index
            ]

        if action
            and action.kind
                == "item"
            and tonumber(
                action.itemID
            ) == tonumber(
                item.id
            )
            and tonumber(
                action.slot
            ) == tonumber(
                slot
            )
        then
            table.remove(
                self.autoQueue,
                index
            )
        end
    end

    item.liveLootRoll =
        true

    item.registrationSource =
        "live_loot_roll"

    return item
end

function Loot:FindCandidateIndex(
    slot,
    playerName
)
    local wanted =
        AL:NormalizeName(
            playerName
        )

    if not wanted then
        return nil
    end

    local maximumCandidates =
        40

    local raidCount =
        GetNumRaidMembers
        and GetNumRaidMembers()
        or 0

    if raidCount > 0 then
        maximumCandidates =
            raidCount
    else
        local partyCount =
            GetNumPartyMembers
            and GetNumPartyMembers()
            or 0

        maximumCandidates =
            math.max(
                1,
                partyCount + 1
            )
    end

    --------------------------------------------------
    -- Candidate indexes may contain gaps.
    --
    -- A nil candidate must NOT terminate the scan.
    --------------------------------------------------

    for index = 1,
        maximumCandidates
    do
        local candidate =
            GetMasterLootCandidate(
                slot,
                index
            )

        if candidate
            and AL:NormalizeName(
                candidate
            ) == wanted
        then
            return index
        end
    end

    return nil
end

function Loot:ValidateItemSlot(
    item
)
    if not item
        or item.demo
    then
        return false,
            "Demo items cannot be awarded."
    end

    if not self.isOpen then
        return false,
            "The loot window is not open."
    end

    if not item.slot then
        return false,
            "The item has no active loot slot."
    end

    --------------------------------------------------
    -- Live loot slots may move while other corpse
    -- items are collected during a roll.
    --------------------------------------------------

    if item.source == "loot"
        and self.FindCurrentItemSlot
    then
        local currentSlot = self:FindCurrentItemSlot(item.id, item.slot)
        if not currentSlot then return false, "That item is no longer available in the loot window." end
        item.slot = currentSlot
    end

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
    -- Automatic Master Looter handout
    --------------------------------------------------

    local pendingHandout =
        self.pendingCollection
        or self.pendingMasterLoot

    if pendingHandout
        and pendingHandout.slot
            == slot
    then
        self:
            CompletePendingHandout(
                pendingHandout
            )
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

function Loot:OnBindConfirm(
    slot
)
    if not AL.db.settings
        .autoConfirmMasterLootToSelf
    then
        return
    end

    local pending =
        self.pendingCollection
        or self.pendingMasterLoot

    local awardToSelf =
        self.pendingAward
        and self.pendingAward.slot
            == slot
        and AL:NormalizeName(
            self.pendingAward.playerName
        )
            == AL:NormalizeName(
                UnitName("player")
            )

    if not pending
        and not awardToSelf
    then
        return
    end

    if pending then
        if pending.slot ~= slot then
            return
        end

        --------------------------------------------------
        -- Never confirm somebody else's automatic
        -- collection warning.
        --------------------------------------------------

        if not pending.holderIsPlayer then
            return
        end
    end

    --------------------------------------------------
    -- Accept the server-side Bind-on-Pickup warning.
    --------------------------------------------------

    ConfirmLootSlot(
        slot
    )

    --------------------------------------------------
    -- Automatic collection uses the B handout timeout.
    -- Give it a fresh window after confirmation.
    --------------------------------------------------

    if pending then
        pending.bindConfirmedAt =
            GetTime()

        pending.startedAt =
            GetTime()
    end

    --------------------------------------------------
    -- UIParent handles the same LOOT_BIND_CONFIRM
    -- event and may create LOOT_BIND after us.
    --------------------------------------------------

    if StaticPopup_Hide then
        StaticPopup_Hide(
            "LOOT_BIND"
        )
    end

    self.hideBindPopupOnUpdate =
        true
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

--------------------------------------------------
-- Record a winner for an untracked bag item
--------------------------------------------------

function Loot:RecordUntrackedAssignment(
    item,
    winner,
    reason,
    winningRoll
)
    if not item
        or not winner
    then
        return false
    end

    local holder =
        UnitName("player")

    local winnerIsHolder =
        AL:NormalizeName(
            winner
        )
        == AL:NormalizeName(
            holder
        )

    local assignmentReason =
        reason
        or "Manual Roll"

    --------------------------------------------------
    -- This item deliberately does NOT enter the
    -- persistent LootSession.
    --
    -- Manual rolls on ordinary bag items are
    -- temporary distribution decisions only.
    --------------------------------------------------

    AL:AddHistory({
        itemID =
            item.id,

        itemLink =
            item.link,

        winner =
            winner,

        reason =
            assignmentReason,

        winningRoll =
            winningRoll,

        masterLooter =
            holder,

        status =
            winnerIsHolder
            and "kept"
            or "untracked_assigned",
    })

    --------------------------------------------------
    -- Announce the result normally.
    --------------------------------------------------

    if AL.db.settings
        .announceAssignments
    then
        if winnerIsHolder then
            AL:Announce(
                string.format(
                    "%s assigned to %s. "
                        .. "No trade required.",
                    item.link
                        or item.name
                        or "Item",
                    winner
                )
            )
        else
            AL:Announce(
                string.format(
                    "%s assigned to %s.",
                    item.link
                        or item.name
                        or "Item",
                    winner
                )
            )
        end
    end

    --------------------------------------------------
    -- Since the item is intentionally untracked,
    -- AscensionLoot cannot put it into the persistent
    -- automated trade queue.
    --------------------------------------------------

    if winnerIsHolder then
        AL:Print(
            string.format(
                "%s is being kept by %s.",
                item.link
                    or item.name
                    or "Item",
                winner
            )
        )
    else
        AL:Print(
            string.format(
                "%s won %s. "
                    .. "This item is not tracked; "
                    .. "trade it manually.",
                winner,
                item.link
                    or item.name
                    or "the item"
            ),
            1,
            0.82,
            0
        )
    end

    if AL.UI then
        AL.UI:RefreshAll()
    end

    return true
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

    --------------------------------------------------
    -- Live boss-loot rolls must always award the
    -- physical corpse item.
    --
    -- Do this BEFORE looking in LootSession. An older
    -- unassigned copy of the same item may already be
    -- in our bags and must not steal this assignment.
    --------------------------------------------------

    if item.source == "loot" then
        local winner =
            winners[1]

        self:Award(
            item,
            winner.name,
            winner.categoryLabel
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

        --------------------------------------------------
        -- An ordinary bag item may have been manually
        -- Alt-clicked for a temporary roll without ever
        -- entering the persistent LootSession.
        --------------------------------------------------

        if item.source == "bag"
            and winners[1]
        then
            local winner =
                winners[1]

            self:RecordUntrackedAssignment(
                item,
                winner.name,
                winner.categoryLabel,
                winner.roll
            )

            AL.Roll.active =
                nil

            if AL.UI then
                AL.UI:RefreshAll()
            end

            return
        end

        --------------------------------------------------
        -- Anything else indicates an actual mismatch:
        -- something that should have been tracked has
        -- disappeared from the LootSession.
        --------------------------------------------------

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

    --------------------------------------------------
    -- Binary Master Looter workflow:
    --
    -- ON:
    --   Assign every item to ourselves.
    --
    -- OFF:
    --   Leave every item on the corpse so it can be
    --   rolled / distributed directly from the live
    --   loot window.
    --------------------------------------------------

    if not AL.db.settings
        .autoMasterLootToSelf
    then
        return
    end

    local holder =
        UnitName("player")

    for slot =
        GetNumLootItems(),
        1,
        -1
    do
        local item =
            lootSlotItem(
                slot
            )

        if item then
            table.insert(
                self.collectionQueue,
                {
                    slot =
                        slot,

                    item =
                        item,

                    holder =
                        holder,

                    trackInSession =
                        AL.ItemUtils:
                            ShouldTrack(
                                item
                            ),
                }
            )
        end
    end
end

function Loot:BuildAutoQueue()
    self.autoQueue = {}

    self.nextAutoAction =
        GetTime() + 0.25

    local isMasterLooter =
        self:IsMasterLooter()

    local assignAllToSelf =
        isMasterLooter
        and AL.db.settings
            .autoMasterLootToSelf

    local liveLootMode =
        isMasterLooter
        and not AL.db.settings
            .autoMasterLootToSelf

    for slot = GetNumLootItems(), 1, -1 do
        local link =
            GetLootSlotLink(slot)

        if link then
            --------------------------------------------------
            -- Master Looter live-roll mode:
            --
            -- Leave ALL items on the corpse.
            --------------------------------------------------

            if not assignAllToSelf
                and not liveLootMode
            then
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

--------------------------------------------------
-- Master Looter collection-state helpers
--------------------------------------------------

function Loot:IsLootSlotLocked(
    slot
)
    if not slot then
        return true
    end

    local _,
        _,
        _,
        _,
        locked =
            GetLootSlotInfo(
                slot
            )

    return locked == true
        or locked == 1
end

function Loot:RemoveCollectionAction(
    action
)
    if not action then
        return false
    end

    for index,
        current in ipairs(
            self.collectionQueue
            or {}
        )
    do
        if current == action then
            table.remove(
                self.collectionQueue,
                index
            )

            return true
        end
    end

    return false
end

function Loot:ClearPendingHandout(
    pending
)
    if self.pendingCollection
        == pending
    then
        self.pendingCollection =
            nil
    end

    if self.pendingMasterLoot
        == pending
    then
        self.pendingMasterLoot =
            nil
    end
end

function Loot:CancelCollectionActionExpectation(
    action
)
    if not action
        or not action.expectationCreated
    then
        return
    end

    local holder =
        action.holder
        or self:GetHolderName()

    local holderIsPlayer =
        AL:NormalizeName(
            holder
        )
        == AL:NormalizeName(
            UnitName("player")
        )

    if holderIsPlayer
        and AL.BagHooks
        and AL.BagHooks
            .ConsumeMasterLootExpectation
    then
        AL.BagHooks:
            ConsumeMasterLootExpectation(
                action.item.id,
                action.item.quantity
                    or 1
            )
    end

    action.expectationCreated =
        nil
end

function Loot:CancelCollectionExpectation(
    pending
)
    if not pending
        or not pending.action
    then
        return
    end

    self:
        CancelCollectionActionExpectation(
            pending.action
        )
end

function Loot:CompletePendingHandout(
    pending
)
    if not pending then
        return
    end

    local action =
        pending.action

    self:
        ClearPendingHandout(
            pending
        )

    if action then
        self:
            RemoveCollectionAction(
                action
            )
    end

    --------------------------------------------------
    -- Untracked auto-loot requires no LootSession
    -- entry. Successful slot clearing is enough.
    --------------------------------------------------

    if not action
        or not action.trackInSession
    then
        return
    end

    --------------------------------------------------
    -- Local holder:
    --
    -- BagHooks owns the physical confirmation. Do not
    -- create a LootSession entry merely because the
    -- corpse slot disappeared.
    --------------------------------------------------

    if pending.holderIsPlayer
        and AL.BagHooks
        and AL.BagHooks
            .ExpectMasterLoot
    then
        AL:Print(
            string.format(
                "Collected %s. "
                    .. "Waiting for bag confirmation.",
                action.item.link
                    or action.item.name
                    or "tracked item"
            )
        )

        return
    end

    --------------------------------------------------
    -- Remote configured holder:
    --
    -- We cannot inspect their bags, so successful
    -- Master Loot slot clearing remains our best
    -- confirmation.
    --------------------------------------------------

    local copies =
        tonumber(
            action.item.quantity
        )
        or 1

    AL.LootSession:
        AddCollectedCopies(
            action.item,
            pending.holder,
            copies
        )

    AL:Print(
        string.format(
            "Collected %d %s of %s for %s.",
            copies,
            copies == 1
                and "copy"
                or "copies",
            action.item.link
                or action.item.name
                or "tracked item",
            pending.holder
                or "Unknown"
        )
    )

    if AL.db.settings
            .autoShowLoot
        and AL.UI
    then
        AL.UI:ShowLoot()
    end
end

function Loot:CheckPendingHandoutTimeout()
    local pending =
        self.pendingCollection
        or self.pendingMasterLoot

    if not pending
        or not pending.startedAt
    then
        return
    end

    --------------------------------------------------
    -- If manual BoP confirmation is required, don't
    -- repeatedly call GiveMasterLoot while the user
    -- is still looking at the confirmation popup.
    --------------------------------------------------

    if AL.db.settings
            .autoConfirmMasterLootToSelf
            == false
        and StaticPopup_Visible
        and StaticPopup_Visible(
            "LOOT_BIND"
        )
    then
        return
    end

    if GetTime()
        - pending.startedAt
        < MASTER_LOOT_HANDOUT_TIMEOUT
    then
        return
    end

    local currentLink =
        GetLootSlotLink(
            pending.slot
        )

    local slotStillContainsItem =
        currentLink
        and tonumber(
            AL:GetItemID(
                currentLink
            )
        )
            == tonumber(
                pending.item.id
            )

    --------------------------------------------------
    -- The slot disappeared even though we never saw
    -- LOOT_SLOT_CLEARED.
    --
    -- Treat that as success rather than handing out a
    -- second copy.
    --------------------------------------------------

    if not slotStillContainsItem then
        self:
            CompletePendingHandout(
                pending
            )

        self:Refresh()

        return
    end

    local action =
        pending.action

    local attempts =
        action
        and tonumber(
            action.attempts
        )
        or 0

    --------------------------------------------------
    -- Give the client another opportunity.
    --------------------------------------------------

    if action
        and attempts
            < MASTER_LOOT_MAX_ATTEMPTS
    then
        self:
            ClearPendingHandout(
                pending
            )

        action.nextAttemptAt =
            GetTime()
            + MASTER_LOOT_RETRY_DELAY

        return
    end

    --------------------------------------------------
    -- Repeated silent failure. Leave the item on the
    -- corpse for manual handling rather than creating
    -- an infinite GiveMasterLoot loop.
    --------------------------------------------------

    self:
        ClearPendingHandout(
            pending
        )

    self:
        CancelCollectionExpectation(
            pending
        )

    self:
        RemoveCollectionAction(
            action
        )

    AL:Print(
        "Could not automatically assign "
            .. tostring(
                pending.item.link
                or pending.item.name
                or "the item"
            )
            .. " after "
            .. tostring(
                MASTER_LOOT_MAX_ATTEMPTS
            )
            .. " attempts. "
            .. "Please handle it manually.",
        1,
        0.3,
        0.3
    )
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

        --------------------------------------------------
        -- A previous attempt may have asked us to wait
        -- briefly before trying again.
        --------------------------------------------------

        if action.nextAttemptAt
            and GetTime()
                < action.nextAttemptAt
        then
            return
        end

        local currentSlot =
            self:
                FindCurrentItemSlot(
                    action.item.id,
                    action.slot
                )

        if not currentSlot then
            local previousAttempts =
                tonumber(
                    action.attempts
                )
                or 0

            --------------------------------------------------
            -- Below-threshold loot may already have been
            -- consumed by WoW's own autoloot system.
            --------------------------------------------------

            if previousAttempts == 0
                and not self:
                    IsMasterLootControlled(
                        action.item
                    )
            then
                self:
                    CancelCollectionActionExpectation(
                        action
                    )

                self:
                    RemoveCollectionAction(
                        action
                    )

                return
            end

            --------------------------------------------------
            -- If we already attempted GiveMasterLoot, the
            -- disappearing slot most likely means that the
            -- previous handout completed late.
            --------------------------------------------------

            if previousAttempts > 0 then
                local holder =
                    action.holder
                    or self:GetHolderName()

                local lateSuccess = {
                    action =
                        action,

                    slot =
                        action.slot,

                    item =
                        action.item,

                    holder =
                        holder,

                    holderIsPlayer =
                        AL:NormalizeName(
                            holder
                        )
                        == AL:NormalizeName(
                            UnitName("player")
                        ),
                }

                self:
                    CompletePendingHandout(
                        lateSuccess
                    )

                self:Refresh()

                return
            end

            --------------------------------------------------
            -- No GiveMasterLoot attempt was ever made.
            -- Something else removed the item.
            --------------------------------------------------

            self:
                CancelCollectionActionExpectation(
                    action
                )

            self:
                RemoveCollectionAction(
                    action
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

        action.slot =
            currentSlot

        action.item.slot =
            currentSlot

        --------------------------------------------------
        -- Gargul's important lesson:
        --
        -- Never attempt to distribute a locked loot slot.
        --------------------------------------------------

        if self:
            IsLootSlotLocked(
                currentSlot
            )
        then
            return
        end
        local holder =
            action.holder
            or self:GetHolderName()

        local holderIsPlayer =
            AL:NormalizeName(
                holder
            )
            == AL:NormalizeName(
                UnitName("player")
            )

        local useMasterLoot =
            self:
                IsMasterLootControlled(
                    action.item
                )

        local candidateIndex =
            nil

        --------------------------------------------------
        -- Items at or above the loot threshold must use
        -- the Master Looter candidate system.
        --------------------------------------------------

        if useMasterLoot then
            candidateIndex =
                self:
                    FindCandidateIndex(
                        currentSlot,
                        holder
                    )

            --------------------------------------------------
            -- Candidate data may not be populated immediately.
            --------------------------------------------------

            if not candidateIndex then
                action.candidateMisses =
                    (
                        action.candidateMisses
                        or 0
                    )
                    + 1

                if action.candidateMisses
                    >= 6
                then
                    self:
                        CancelCollectionActionExpectation(
                            action
                        )

                    self:
                        RemoveCollectionAction(
                            action
                        )

                    AL:Print(
                        tostring(holder)
                            .. " did not become eligible to receive "
                            .. tostring(
                                action.item.link
                                or action.item.name
                            )
                            .. ". Please handle it manually.",
                        1,
                        0.3,
                        0.3
                    )

                    return
                end

                action.nextAttemptAt =
                    GetTime()
                    + MASTER_LOOT_RETRY_DELAY

                return
            end

            action.candidateMisses =
                nil

        --------------------------------------------------
        -- Items BELOW the Master Looter threshold are
        -- ordinary loot. They cannot be GiveMasterLoot'ed.
        --------------------------------------------------

        elseif not holderIsPlayer then
            --------------------------------------------------
            -- Ordinary below-threshold loot cannot be directly
            -- assigned to another configured loot holder.
            --------------------------------------------------

            self:
                CancelCollectionActionExpectation(
                    action
                )

            self:
                RemoveCollectionAction(
                    action
                )

            AL:Print(
                tostring(
                    action.item.link
                    or action.item.name
                    or "The item"
                )
                    .. " is below the Master Looter threshold "
                    .. "and cannot be directly assigned to "
                    .. tostring(holder)
                    .. ".",
                1,
                0.5,
                0.2
            )

            return
        end

        --------------------------------------------------
        -- Create the bag expectation ONCE.
        --------------------------------------------------

        if action.trackInSession
            and holderIsPlayer
            and not action.expectationCreated
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

            action.expectationCreated =
                true
        end

        action.attempts =
            (
                action.attempts
                or 0
            )
            + 1

        action.nextAttemptAt =
            nil

        local pending = {
            action =
                action,

            slot =
                currentSlot,

            item =
                action.item,

            holder =
                holder,

            holderIsPlayer =
                holderIsPlayer,

            startedAt =
                GetTime(),
        }

        if action.trackInSession then
            self.pendingCollection =
                pending
        else
            self.pendingMasterLoot =
                pending
        end

        --------------------------------------------------
        -- Use the correct WoW mechanism.
        --------------------------------------------------

        if useMasterLoot then
            GiveMasterLoot(
                currentSlot,
                candidateIndex
            )
        else
            LootSlot(
                currentSlot
            )

            --------------------------------------------------
            -- Gargul uses the same approach for ordinary
            -- below-threshold loot.
            --------------------------------------------------

            if AL.db.settings
                    .autoConfirmMasterLootToSelf
                and ConfirmLootSlot
            then
                ConfirmLootSlot(
                    currentSlot
                )
            end
        end

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
    --------------------------------------------------
    -- UIParent may create LOOT_BIND later during the
    -- same LOOT_BIND_CONFIRM event dispatch.
    --------------------------------------------------

    if self.hideBindPopupOnUpdate then
        self.hideBindPopupOnUpdate =
            false

        if StaticPopup_Hide then
            StaticPopup_Hide(
                "LOOT_BIND"
            )
        end
    end
    self:CheckPendingHandoutTimeout()
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
