local AL = AscensionLoot

AL.PlayerRollUI =
    AL.PlayerRollUI or {}

local PlayerUI =
    AL.PlayerRollUI

PlayerUI.frame =
    nil

PlayerUI.currentRollID =
    nil

PlayerUI.dismissedRollID =
    nil

PlayerUI.timerAccumulator =
    0

local FRAME_WIDTH =
    340

local FRAME_HEIGHT =
    250

local ROLL_AREA_HEIGHT =
    108

local ROLL_LINE_HEIGHT =
    16

local CATEGORY_PRIORITY = {
    SR = 1,
    MS = 2,
    OS = 3,
}

--------------------------------------------------
-- Helpers
--------------------------------------------------

local function createButton(
    parent,
    text,
    width
)
    local button =
        CreateFrame(
            "Button",
            nil,
            parent,
            "UIPanelButtonTemplate"
        )

    button:SetWidth(
        width
    )

    button:SetHeight(
        24
    )

    button:SetText(
        text
    )

    return button
end

local function getRemote()
    return AL.RollSync
        and AL.RollSync.remote
        or nil
end

--------------------------------------------------
-- Position
--------------------------------------------------

function PlayerUI:RestorePosition()
    if not self.frame
        or not AL.db
    then
        return
    end

    local saved =
        AL.db.windows
        and AL.db.windows.playerRoll

    self.frame:
        ClearAllPoints()

    if saved then
        self.frame:SetPoint(
            saved.point
                or "CENTER",

            UIParent,

            saved.relativePoint
                or "CENTER",

            tonumber(saved.x)
                or 0,

            tonumber(saved.y)
                or -150
        )
    else
        self.frame:SetPoint(
            "CENTER",
            UIParent,
            "CENTER",
            0,
            -150
        )
    end
end

function PlayerUI:SavePosition()
    if not self.frame
        or not AL.db
    then
        return
    end

    AL.db.windows =
        AL.db.windows
        or {}

    AL.db.windows.playerRoll =
        AL.db.windows.playerRoll
        or {}

    local point,
        relativeTo,
        relativePoint,
        x,
        y =
            self.frame:
                GetPoint(1)

    local saved =
        AL.db.windows.playerRoll

    saved.point =
        point
        or "CENTER"

    saved.relativePoint =
        relativePoint
        or "CENTER"

    saved.x =
        x
        or 0

    saved.y =
        y
        or 0
end

--------------------------------------------------
-- Item tooltip
--------------------------------------------------

function PlayerUI:ShowItemTooltip()
    local remote =
        getRemote()

    if not remote then
        return
    end

    GameTooltip:SetOwner(
        self.frame.iconButton,
        "ANCHOR_RIGHT"
    )

    if remote.itemLink
        and remote.itemLink ~= ""
    then
        GameTooltip:SetHyperlink(
            remote.itemLink
        )

    elseif remote.itemID then
        GameTooltip:SetHyperlink(
            "item:"
                .. tostring(
                    remote.itemID
                )
                .. ":0:0:0:0:0:0:0"
        )
    end

    GameTooltip:Show()
end

--------------------------------------------------
-- Roll buttons
--------------------------------------------------

function PlayerUI:RollMain()
    local remote =
        getRemote()

    if not remote then
        return
    end

    if remote.state ~= "rolling"
        and remote.state ~= "tie"
    then
        return
    end

    RandomRoll(
        1,
        100
    )
end

function PlayerUI:RollOffSpec()
    local remote =
        getRemote()

    if not remote then
        return
    end

    if remote.state ~= "rolling"
        and remote.state ~= "tie"
    then
        return
    end

    RandomRoll(
        1,
        99
    )
end

function PlayerUI:Pass()
    local remote =
        getRemote()

    if remote then
        self.dismissedRollID =
            remote.id
    end

    if self.frame then
        self.frame:Hide()
    end
end

--------------------------------------------------
-- Roll display
--------------------------------------------------

function PlayerUI:GetRollDisplayEntries(
    remote
)
    local result = {}

    for _, roll in ipairs(
        remote.rolls or {}
    ) do
        table.insert(
            result,
            roll
        )
    end

    table.sort(
        result,
        function(left, right)
            local leftPriority =
                CATEGORY_PRIORITY[
                    left.category
                ] or 99

            local rightPriority =
                CATEGORY_PRIORITY[
                    right.category
                ] or 99

            if leftPriority
                ~= rightPriority
            then
                return leftPriority
                    < rightPriority
            end

            if tonumber(left.value)
                ~= tonumber(right.value)
            then
                return (
                    tonumber(
                        left.value
                    ) or 0
                )
                    > (
                        tonumber(
                            right.value
                        ) or 0
                    )
            end

            return string.lower(
                tostring(
                    left.playerName
                )
            )
                < string.lower(
                    tostring(
                        right.playerName
                    )
                )
        end
    )

    return result
end

function PlayerUI:RefreshRollLines(
    remote
)
    local frame =
        self.frame

    if not frame then
        return
    end

    local texts = {}

    local rolls =
        self:GetRollDisplayEntries(
            remote
        )

    for _, roll in ipairs(
        rolls
    ) do
        local extra = ""

        if tonumber(
            roll.rollIndex
        )
            and tonumber(
                roll.rollIndex
            ) > 1
        then
            extra =
                " #"
                .. tostring(
                    roll.rollIndex
                )
        end

        table.insert(
            texts,
            string.format(
                "%s   %d   %s%s",
                tostring(
                    roll.playerName
                        or "Unknown"
                ),
                tonumber(
                    roll.value
                ) or 0,
                tostring(
                    roll.category
                        or "?"
                ),
                extra
            )
        )
    end

    --------------------------------------------------
    -- Tie-break rolls
    --------------------------------------------------

    if #(remote.tieRolls or {})
        > 0
    then
        table.insert(
            texts,
            "|cffffcc00Tie-breaks:|r"
        )

        for _, roll in ipairs(
            remote.tieRolls
        ) do
            table.insert(
                texts,
                string.format(
                    "%s   %d   Tie",
                    tostring(
                        roll.playerName
                            or "Unknown"
                    ),
                    tonumber(
                        roll.value
                    ) or 0
                )
            )
        end
    end

    --------------------------------------------------
    -- Empty state
    --------------------------------------------------

    if #texts == 0 then
        if remote.state
            == "finished"
        then
            table.insert(
                texts,
                "No valid rolls."
            )
        else
            table.insert(
                texts,
                "Waiting for rolls..."
            )
        end
    end

    --------------------------------------------------
    -- Font-string pool
    --------------------------------------------------

    for index, text in ipairs(
        texts
    ) do
        local line =
            frame.rollLines[
                index
            ]

        if not line then
            line =
                frame.rollChild:
                    CreateFontString(
                        nil,
                        "OVERLAY",
                        "GameFontHighlightSmall"
                    )

            line:SetPoint(
                "TOPLEFT",
                frame.rollChild,
                "TOPLEFT",
                2,
                -(
                    (
                        index - 1
                    )
                    * ROLL_LINE_HEIGHT
                )
            )

            line:SetWidth(
                270
            )

            line:SetJustifyH(
                "LEFT"
            )

            frame.rollLines[
                index
            ] =
                line
        end

        line:SetText(
            text
        )

        line:Show()
    end

    for index =
        #texts + 1,
        #frame.rollLines
    do
        frame.rollLines[
            index
        ]:Hide()
    end

    frame.rollChild:
        SetHeight(
            math.max(
                ROLL_AREA_HEIGHT,
                #texts
                    * ROLL_LINE_HEIGHT
            )
        )
end

--------------------------------------------------
-- Timer
--------------------------------------------------

function PlayerUI:RefreshTimer()
    local frame =
        self.frame

    local remote =
        getRemote()

    if not frame
        or not remote
    then
        return
    end

    if remote.state == "rolling"
        or remote.state == "tie"
    then
        local remaining =
            math.max(
                0,
                math.ceil(
                    (
                        remote.endsAt
                        or GetTime()
                    )
                    - GetTime()
                )
            )

        frame.timer:SetText(
            tostring(
                remaining
            )
                .. "s"
        )

    elseif remote.state
        == "finished"
    then
        frame.timer:SetText(
            "Finished"
        )

    elseif remote.state
        == "cancelled"
    then
        frame.timer:SetText(
            "Cancelled"
        )

    else
        frame.timer:SetText(
            ""
        )
    end
end

--------------------------------------------------
-- Full refresh
--------------------------------------------------

function PlayerUI:Refresh()
    local frame =
        self.frame

    local remote =
        getRemote()

    if not frame
        or not remote
    then
        return
    end

    --------------------------------------------------
    -- Item
    --------------------------------------------------

    local itemText

    if remote.itemLink
        and remote.itemLink ~= ""
    then
        itemText =
            remote.itemLink

    elseif remote.itemName
        and remote.itemName ~= ""
    then
        itemText =
            "["
            .. tostring(
                remote.itemName
            )
            .. "]"

    else
        itemText =
            "Item #"
            .. tostring(
                remote.itemID
                    or "?"
            )
    end

    frame.item:SetText(
        itemText
    )

    local texture =
        remote.itemID
        and GetItemIcon(
            remote.itemID
        )
        or nil

    frame.icon:SetTexture(
        texture
        or "Interface\\Icons\\INV_Misc_QuestionMark"
    )

    --------------------------------------------------
    -- State
    --------------------------------------------------

    local statusText

    if remote.state
        == "rolling"
    then
        statusText =
            "Rolling"

        if tonumber(
            remote.copyCount
        )
            and tonumber(
                remote.copyCount
            ) > 1
        then
            statusText =
                statusText
                .. " — "
                .. tostring(
                    remote.copyCount
                )
                .. " copies"
        end

    elseif remote.state
        == "tie"
    then
        statusText =
            "Tie — reroll /roll "
            .. tostring(
                remote.expectedMaximum
                    or 100
            )

    elseif remote.state
        == "finished"
    then
        statusText =
            "Roll finished"

    elseif remote.state
        == "cancelled"
    then
        statusText =
            "Roll cancelled"

    else
        statusText =
            tostring(
                remote.state
                    or ""
            )
    end

    frame.status:SetText(
        statusText
    )

    --------------------------------------------------
    -- Buttons
    --------------------------------------------------

    if remote.state
        == "rolling"
    then
        frame.rollButton:Enable()
        frame.osButton:Enable()

    elseif remote.state
        == "tie"
    then
        --------------------------------------------------
        -- Only the correct tie-break roll type is useful.
        --------------------------------------------------

        if tonumber(
            remote.expectedMaximum
        ) == 99
        then
            frame.rollButton:Disable()
            frame.osButton:Enable()
        else
            frame.rollButton:Enable()
            frame.osButton:Disable()
        end

    else
        frame.rollButton:Disable()
        frame.osButton:Disable()
    end

    --------------------------------------------------
    -- Rolls and timer
    --------------------------------------------------

    self:RefreshRollLines(
        remote
    )

    self:RefreshTimer()
end

--------------------------------------------------
-- Sync callback
--------------------------------------------------

function PlayerUI:OnSyncChanged(
    remote
)
    if not remote then
        return
    end

    local isNewRoll =
        self.currentRollID
            ~= remote.id

    if isNewRoll then
        self.currentRollID =
            remote.id

        self.dismissedRollID =
            nil

        if self.frame
            and self.frame.rollScroll
        then
            self.frame.rollScroll:
                SetVerticalScroll(
                    0
                )
        end
    end

    self:Refresh()

    --------------------------------------------------
    -- Pass only dismisses the current roll.
    --
    -- Updates for the same roll must not reopen it.
    --------------------------------------------------

    if self.dismissedRollID
        == remote.id
    then
        return
    end

    if self.frame then
        self.frame:Show()
    end
end

--------------------------------------------------
-- OnUpdate
--------------------------------------------------

function PlayerUI:OnUpdate(
    elapsed
)
    self.timerAccumulator =
        (
            self.timerAccumulator
            or 0
        )
        + elapsed

    if self.timerAccumulator
        < 0.1
    then
        return
    end

    self.timerAccumulator =
        0

    self:RefreshTimer()
end

--------------------------------------------------
-- Create
--------------------------------------------------

function PlayerUI:Initialize()
    if self.frame then
        return
    end

    local frame =
        CreateFrame(
            "Frame",
            "AscensionLootPlayerRollFrame",
            UIParent
        )

    frame:SetWidth(
        FRAME_WIDTH
    )

    frame:SetHeight(
        FRAME_HEIGHT
    )

    frame:SetFrameStrata(
        "DIALOG"
    )

    frame:SetClampedToScreen(
        true
    )

    frame:SetMovable(
        true
    )

    frame:EnableMouse(
        true
    )

    frame:RegisterForDrag(
        "LeftButton"
    )

    frame:SetBackdrop({
        bgFile =
            "Interface\\DialogFrame\\UI-DialogBox-Background",

        edgeFile =
            "Interface\\DialogFrame\\UI-DialogBox-Border",

        tile =
            true,

        tileSize =
            32,

        edgeSize =
            32,

        insets = {
            left = 11,
            right = 12,
            top = 12,
            bottom = 11,
        },
    })

    frame:SetScript(
        "OnDragStart",
        function(self)
            self:StartMoving()
        end
    )

    frame:SetScript(
        "OnDragStop",
        function(self)
            self:
                StopMovingOrSizing()

            PlayerUI:
                SavePosition()
        end
    )

    frame:SetScript(
        "OnUpdate",
        function(
            self,
            elapsed
        )
            PlayerUI:
                OnUpdate(
                    elapsed
                )
        end
    )

    --------------------------------------------------
    -- Header
    --------------------------------------------------

    frame.title =
        frame:
            CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormal"
            )

    frame.title:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        16,
        -14
    )

    frame.title:SetText(
        "Ascension Loot — Roll"
    )

    frame.timer =
        frame:
            CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormalLarge"
            )

    frame.timer:SetPoint(
        "TOPRIGHT",
        frame,
        "TOPRIGHT",
        -18,
        -14
    )

    --------------------------------------------------
    -- Item icon
    --------------------------------------------------

    frame.iconButton =
        CreateFrame(
            "Button",
            nil,
            frame
        )

    frame.iconButton:SetWidth(
        40
    )

    frame.iconButton:SetHeight(
        40
    )

    frame.iconButton:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        16,
        -38
    )

    frame.icon =
        frame.iconButton:
            CreateTexture(
                nil,
                "ARTWORK"
            )

    frame.icon:SetAllPoints(
        frame.iconButton
    )

    frame.iconButton:SetScript(
        "OnEnter",
        function()
            PlayerUI:
                ShowItemTooltip()
        end
    )

    frame.iconButton:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    --------------------------------------------------
    -- Item name
    --------------------------------------------------

    frame.item =
        frame:
            CreateFontString(
                nil,
                "OVERLAY",
                "GameFontNormal"
            )

    frame.item:SetPoint(
        "TOPLEFT",
        frame.iconButton,
        "TOPRIGHT",
        8,
        -1
    )

    frame.item:SetWidth(
        245
    )

    frame.item:SetHeight(
        20
    )

    frame.item:SetJustifyH(
        "LEFT"
    )

    frame.status =
        frame:
            CreateFontString(
                nil,
                "OVERLAY",
                "GameFontHighlightSmall"
            )

    frame.status:SetPoint(
        "TOPLEFT",
        frame.iconButton,
        "TOPRIGHT",
        8,
        -24
    )

    frame.status:SetWidth(
        245
    )

    frame.status:SetJustifyH(
        "LEFT"
    )

    --------------------------------------------------
    -- Rolls
    --------------------------------------------------

    frame.rollScroll =
        CreateFrame(
            "ScrollFrame",
            "AscensionLootPlayerRollScrollFrame",
            frame,
            "UIPanelScrollFrameTemplate"
        )

    frame.rollScroll:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        16,
        -88
    )

    frame.rollScroll:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -34,
        48
    )

    frame.rollChild =
        CreateFrame(
            "Frame",
            nil,
            frame.rollScroll
        )

    frame.rollChild:SetWidth(
        280
    )

    frame.rollChild:SetHeight(
        ROLL_AREA_HEIGHT
    )

    frame.rollScroll:
        SetScrollChild(
            frame.rollChild
        )

    frame.rollLines =
        {}

    --------------------------------------------------
    -- Buttons
    --------------------------------------------------

    frame.rollButton =
        createButton(
            frame,
            "Roll",
            94
        )

    frame.rollButton:SetPoint(
        "BOTTOMLEFT",
        frame,
        "BOTTOMLEFT",
        16,
        16
    )

    frame.rollButton:SetScript(
        "OnClick",
        function()
            PlayerUI:
                RollMain()
        end
    )

    frame.osButton =
        createButton(
            frame,
            "OS",
            94
        )

    frame.osButton:SetPoint(
        "LEFT",
        frame.rollButton,
        "RIGHT",
        6,
        0
    )

    frame.osButton:SetScript(
        "OnClick",
        function()
            PlayerUI:
                RollOffSpec()
        end
    )

    frame.passButton =
        createButton(
            frame,
            "Pass",
            94
        )

    frame.passButton:SetPoint(
        "LEFT",
        frame.osButton,
        "RIGHT",
        6,
        0
    )

    frame.passButton:SetScript(
        "OnClick",
        function()
            PlayerUI:
                Pass()
        end
    )

    --------------------------------------------------
    -- Finish
    --------------------------------------------------

    self.frame =
        frame

    self:RestorePosition()

    frame:Hide()

    --------------------------------------------------
    -- Normally there is no remote roll during login,
    -- but this keeps initialization safe.
    --------------------------------------------------

    local remote =
        getRemote()

    if remote then
        self:OnSyncChanged(
            remote
        )
    end
end