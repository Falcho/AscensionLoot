local AL = AscensionLoot

AL.ItemUtils = AL.ItemUtils or {}
local ItemUtils = AL.ItemUtils

local tooltip = CreateFrame(
    "GameTooltip",
    "AscensionLootScannerTooltip",
    UIParent,
    "GameTooltipTemplate"
)

tooltip:SetOwner(UIParent, "ANCHOR_NONE")

function ItemUtils:GetBindType(itemLink)
    if not itemLink then return nil end

    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)

    for index = 1, tooltip:NumLines() do
        local line = _G["AscensionLootScannerTooltipTextLeft" .. index]
        local text = line and line:GetText()

        if text then
            if ITEM_BIND_ON_PICKUP and text:find(ITEM_BIND_ON_PICKUP, 1, true) then
                return "BOP"
            end

            if ITEM_BIND_ON_EQUIP and text:find(ITEM_BIND_ON_EQUIP, 1, true) then
                return "BOE"
            end

            if ITEM_BIND_QUEST and text:find(ITEM_BIND_QUEST, 1, true) then
                return "QUEST"
            end
        end
    end

    return nil
end

function ItemUtils:ShouldTrack(item)
    if not item or not item.id then return false end

    local quality = tonumber(item.quality) or 0
    local minimum = tonumber(AL.db.settings.minimumTrackedQuality) or 4

    if quality >= minimum then
        return true
    end

    if quality == 3 and AL.db.settings.trackRareBindOnPickup then
        return item.bindType == "BOP"
    end

    return false
end

function ItemUtils:FromBagSlot(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then return nil end

    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
    local name, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(link)

    local item = {
        source = "bag",
        bag = bag,
        bagSlot = slot,
        id = AL:GetItemID(link),
        link = link,
        name = name or link,
        icon = texture or itemTexture,
        quantity = count or 1,
        quality = quality or itemQuality or 0,
        locked = locked,
    }

    item.bindType = self:GetBindType(link)
    item.key = AL:GetItemKey(item)

    return item
end