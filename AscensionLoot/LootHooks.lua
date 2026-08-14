local AL = AscensionLoot

AL.LootHooks =
    AL.LootHooks
    or {}

local LootHooks =
    AL.LootHooks

LootHooks.initialized =
    false

LootHooks.originalClickScripts =
    LootHooks.originalClickScripts
    or {}

--------------------------------------------------
-- Modifier detection
--------------------------------------------------

function LootHooks:IsRollClick(
    mouseButton
)
    if mouseButton
        ~= "LeftButton"
    then
        return false
    end

    if not IsAltKeyDown() then
        return false
    end

    --------------------------------------------------
    -- Plain Alt only.
    --
    -- Preserve other modified-click behaviour from
    -- WoW / Ascension.
    --------------------------------------------------

    if IsControlKeyDown()
        or IsShiftKeyDown()
    then
        return false
    end

    return true
end

--------------------------------------------------
-- Live loot Alt-click
--------------------------------------------------

function LootHooks:HandleLootClick(
    button,
    mouseButton
)
    if not self:
        IsRollClick(
            mouseButton
        )
    then
        return false
    end

    if not AL.Loot
        or not AL.Loot.isOpen
    then
        return false
    end

    local slot =
        button
        and button.slot

    if not slot then
        return false
    end

    --------------------------------------------------
    -- Only intercept actual item slots.
    --------------------------------------------------

    if LootSlotIsItem
        and not LootSlotIsItem(
            slot
        )
    then
        return false
    end

    if not GetLootSlotLink(
        slot
    )
    then
        return false
    end

    --------------------------------------------------
    -- Never replace an existing active roll by
    -- accidentally Alt-clicking another boss item.
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

        return true
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

        --------------------------------------------------
        -- This was still an intentional Alt-click.
        -- Do not fall through into Blizzard's normal
        -- modified-click handler.
        --------------------------------------------------

        return true
    end

    local started =
        AL.Roll:
            StartForItem(
                item
            )

    if not started then
        return true
    end

    if AL.UI then
        AL.UI:ShowLoot()
    end

    return true
end

function LootHooks:EnsureHooks()
    local buttonCount =
        LOOTFRAME_NUMBUTTONS
        or 4

    local installed =
        0

    for index = 1,
        buttonCount
    do
        local button =
            _G[
                "LootButton"
                .. tostring(index)
            ]

        if button
            and button.GetScript
            and button.SetScript
        then
            local currentScript =
                button:GetScript(
                    "OnClick"
                )

            local currentWrapper =
                self.buttonWrappers[
                    button
                ]

            --------------------------------------------------
            -- Our current wrapper is still installed.
            --------------------------------------------------

            if currentScript
                == currentWrapper
            then
                installed =
                    installed + 1

            else
                --------------------------------------------------
                -- Something else owns the button right now.
                --
                -- Preserve its current behaviour and place our
                -- live-roll interception in front of it.
                --------------------------------------------------

                local originalScript =
                    currentScript

                local wrapper

                wrapper =
                    function(
                        clickedButton,
                        mouseButton
                    )
                        if LootHooks:
                            HandleLootClick(
                                clickedButton,
                                mouseButton
                            )
                        then
                            return
                        end

                        if originalScript then
                            return originalScript(
                                clickedButton,
                                mouseButton
                            )
                        end
                    end

                self.buttonWrappers[
                    button
                ] =
                    wrapper

                button:SetScript(
                    "OnClick",
                    wrapper
                )

                installed =
                    installed + 1
            end
        end
    end

    return installed
end

function LootHooks:Initialize()
    if self.initialized then
        return
    end

    self.initialized =
        true

    local installed =
        self:EnsureHooks()

    if installed == 0 then
        AL:Print(
            "Could not install the live "
                .. "loot Alt-click hooks.",
            1,
            0.4,
            0.2
        )
    end
end