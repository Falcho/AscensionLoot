local AL = AscensionLoot

AL.LootHooks =
    AL.LootHooks
    or {}

local LootHooks =
    AL.LootHooks

LootHooks.initialized =
    false

--------------------------------------------------
-- Modifier detection
--------------------------------------------------

function LootHooks:IsLiveRollModifier()
    if not IsAltKeyDown() then
        return false
    end

    --------------------------------------------------
    -- Plain Alt only.
    --
    -- Ctrl+Alt must remain available for Ascension's
    -- transmog handling.
    --
    -- Shift+Alt is reserved by AscensionLoot for
    -- direct assignment elsewhere.
    --------------------------------------------------

    if IsControlKeyDown()
        or IsShiftKeyDown()
    then
        return false
    end

    return true
end

--------------------------------------------------
-- Resolve the live corpse slot from the item link
--------------------------------------------------

function LootHooks:FindLiveLootSlot(
    itemLink
)
    if not AL.Loot
        or not AL.Loot.isOpen
        or not itemLink
    then
        return nil
    end

    local wantedID =
        AL:GetItemID(
            itemLink
        )

    if not wantedID then
        return nil
    end

    local focus =
        GetMouseFocus
        and GetMouseFocus()
        or nil

    local focusedSlot =
        focus
        and focus.slot
        or nil

    if focusedSlot then
        local focusedLink =
            GetLootSlotLink(
                focusedSlot
            )

        if focusedLink
            and AL:GetItemID(
                focusedLink
            ) == wantedID
        then
            return focusedSlot
        end
    end

    --------------------------------------------------
    -- Fallback:
    -- Scan the live loot window for the clicked item.
    --------------------------------------------------

    for slot = 1,
        GetNumLootItems()
    do
        local liveLink =
            GetLootSlotLink(
                slot
            )

        if liveLink
            and AL:GetItemID(
                liveLink
            ) == wantedID
        then
            return slot
        end
    end

    return nil
end

--------------------------------------------------
-- Global modified-item click handler
--------------------------------------------------

function LootHooks:HandleModifiedItemClick(
    itemLink,
    mouseButton
)
    if not self:
        IsLiveRollModifier()
    then
        return
    end

    if mouseButton
        and mouseButton
            ~= "LeftButton"
    then
        return
    end

    --------------------------------------------------
    -- Only turn this into a live boss-loot roll while
    -- an actual loot window is open.
    --
    -- BagHooks continues to own ordinary bag items.
    --------------------------------------------------

    if not AL.Loot
        or not AL.Loot.isOpen
    then
        return
    end

    local slot =
        self:
            FindLiveLootSlot(
                itemLink
            )

    if not slot then
        return
    end

    --------------------------------------------------
    -- Never overwrite an active roll.
    --------------------------------------------------

    if AL.Roll
        and AL.Roll.active
    then
        AL:Print(
            "Finish or cancel the current roll "
                .. "before starting another one.",
            1,
            0.5,
            0.2
        )

        return
    end

    local item,
        errorMessage =
            AL.Loot:
                PrepareLiveRollItem(
                    slot
                )

    if not item then
        AL:Print(
            errorMessage
                or "The live loot roll "
                    .. "could not be started.",
            1,
            0.4,
            0.2
        )

        return
    end

    local started =
        AL.Roll:
            StartForItem(
                item
            )

    if not started then
        return
    end

    if AL.UI then
        AL.UI:ShowLoot()
    end
end

--------------------------------------------------
-- Installation
--------------------------------------------------

function LootHooks:Initialize()
    if self.initialized then
        return
    end

    self.initialized =
        true

    if not HandleModifiedItemClick then
        AL:Print(
            "Could not hook modified item clicks.",
            1,
            0.4,
            0.2
        )

        return
    end

    if hooksecurefunc then
        hooksecurefunc(
            "HandleModifiedItemClick",
            function(itemLink)
                local mouseButton =
                    GetMouseButtonClicked
                    and GetMouseButtonClicked()
                    or "LeftButton"

                LootHooks:
                    HandleModifiedItemClick(
                        itemLink,
                        mouseButton
                    )
            end
        )

        return
    end

    local original =
        HandleModifiedItemClick

    HandleModifiedItemClick =
        function(itemLink, ...)
            if LootHooks:
                IsLiveRollModifier()
            then
                LootHooks:
                    HandleModifiedItemClick(
                        itemLink,
                        "LeftButton"
                    )

                if AL.Loot
                    and AL.Loot.isOpen
                    and LootHooks:
                        FindLiveLootSlot(
                            itemLink
                        )
                then
                    return true
                end
            end

            return original(
                itemLink,
                ...
            )
        end
end