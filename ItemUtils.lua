local AL = AscensionLoot

AL.ItemUtils = AL.ItemUtils or {}
local ItemUtils = AL.ItemUtils

--------------------------------------------------
-- Temporary raid-trade tooltip scanner
--------------------------------------------------

local TRADE_SCAN_TOOLTIP_NAME =
    "AscensionLootTradeScanTooltip"

local tradeScanTooltip =
    CreateFrame(
        "GameTooltip",
        TRADE_SCAN_TOOLTIP_NAME,
        UIParent,
        "GameTooltipTemplate"
    )

tradeScanTooltip:SetOwner(
    UIParent,
    "ANCHOR_NONE"
)

tradeScanTooltip:Hide()

local tradeTimerPattern = nil

local function escapeLuaPattern(value)
    return (
        tostring(value or ""):gsub(
            "([%(%)%.%%%+%-%*%?%[%]%^%$])",
            "%%%1"
        )
    )
end

local function getTradeTimerPattern()
    if tradeTimerPattern ~= nil then
        return tradeTimerPattern
    end

    local template =
        _G.BIND_TRADE_TIME_REMAINING

    if type(template) ~= "string"
        or template == ""
    then
        tradeTimerPattern = false
        return nil
    end

    local placeholder = "\001"

    -- Support both ordinary and positional
    -- format placeholders.
    template = template:gsub(
        "%%%d+%$[sd]",
        placeholder
    )

    template = template:gsub(
        "%%[sd]",
        placeholder
    )

    template =
        escapeLuaPattern(template)

    template = template:gsub(
        placeholder,
        ".+"
    )

    tradeTimerPattern = template

    return tradeTimerPattern
end

local function containsTradeTimer(text)
    if type(text) ~= "string"
        or text == ""
    then
        return false
    end

    local pattern =
        getTradeTimerPattern()

    if pattern
        and text:find(pattern)
    then
        return true
    end

    -- English fallback for customised clients where
    -- BIND_TRADE_TIME_REMAINING is unavailable.
    local lowerText =
        string.lower(text)

    if lowerText:find(
        "you may trade this item",
        1,
        true
    ) then
        return true
    end

    return false
end

function ItemUtils:IsBagItemTradeable(
    bag,
    slot
)
    if bag == nil or slot == nil then
        return false
    end

    if not GetContainerItemLink(
        bag,
        slot
    ) then
        return false
    end

    tradeScanTooltip:Hide()
    tradeScanTooltip:ClearLines()

    tradeScanTooltip:SetOwner(
        UIParent,
        "ANCHOR_NONE"
    )

    tradeScanTooltip:SetBagItem(
        bag,
        slot
    )

    local tooltipName =
        tradeScanTooltip:GetName()

    local lineCount =
        tradeScanTooltip:NumLines() or 0

    for lineIndex = 1, lineCount do
        local leftLine =
            _G[
                tooltipName
                .. "TextLeft"
                .. lineIndex
            ]

        local rightLine =
            _G[
                tooltipName
                .. "TextRight"
                .. lineIndex
            ]

        local leftText =
            leftLine
            and leftLine:GetText()

        local rightText =
            rightLine
            and rightLine:GetText()

        if containsTradeTimer(leftText)
            or containsTradeTimer(rightText)
        then
            tradeScanTooltip:Hide()
            return true
        end
    end

    tradeScanTooltip:Hide()

    return false
end

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