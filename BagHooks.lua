local AL = AscensionLoot

AL.BagHooks = AL.BagHooks or {}
local BagHooks = AL.BagHooks

BagHooks.initialized = false

function BagHooks:GetBagAndSlot(button)
    if not button then return nil end

    local parent = button:GetParent()
    local bag = parent and parent:GetID()
    local slot = button:GetID()

    if bag == nil or slot == nil then
        return nil
    end

    return bag, slot
end

function BagHooks:HandleModifiedClick(button, mouseButton)
    if mouseButton ~= "LeftButton" then return end
    if not IsAltKeyDown() then return end

    local bag, slot = self:GetBagAndSlot(button)
    if bag == nil then return end

    local item = AL.ItemUtils:FromBagSlot(bag, slot)
    if not item then return end

    if IsShiftKeyDown() then
        AL.Loot:DirectAward(item)
    else
        AL.Roll:StartForItem(item)
        AL.UI:ShowLoot()
    end
end

function BagHooks:Initialize()
    if self.initialized then return end
    self.initialized = true

    if hooksecurefunc and ContainerFrameItemButton_OnModifiedClick then
        hooksecurefunc(
            "ContainerFrameItemButton_OnModifiedClick",
            function(button, mouseButton)
                BagHooks:HandleModifiedClick(button, mouseButton)
            end
        )
    else
        AL:Print(
            "Could not install the default bag Alt-click hook.",
            1,
            0.4,
            0.2
        )
    end
end