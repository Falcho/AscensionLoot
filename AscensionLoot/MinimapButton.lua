local AL = AscensionLoot

AL.MinimapButton =
    AL.MinimapButton or {}

local MinimapButton =
    AL.MinimapButton

local DEFAULT_ANGLE = 225
local BUTTON_PADDING = 9

--------------------------------------------------
-- Math compatibility
--------------------------------------------------

local function atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end

    if x > 0 then
        return math.atan(y / x)
    end

    if x < 0 and y >= 0 then
        return math.atan(y / x)
            + math.pi
    end

    if x < 0 and y < 0 then
        return math.atan(y / x)
            - math.pi
    end

    if x == 0 and y > 0 then
        return math.pi / 2
    end

    if x == 0 and y < 0 then
        return -math.pi / 2
    end

    return 0
end

--------------------------------------------------
-- Saved position
--------------------------------------------------

function MinimapButton:GetSavedAngle()
    if not AL.db
        or not AL.db.minimapButton
    then
        return DEFAULT_ANGLE
    end

    return tonumber(
        AL.db.minimapButton.angle
    ) or DEFAULT_ANGLE
end

function MinimapButton:SaveAngle(angle)
    if not AL.db then
        return
    end

    AL.db.minimapButton =
        AL.db.minimapButton or {}

    AL.db.minimapButton.angle =
        angle
end

--------------------------------------------------
-- Positioning
--------------------------------------------------

function MinimapButton:UpdatePosition()
    if not self.button
        or not Minimap
    then
        return
    end

    local angle =
        math.rad(
            self:GetSavedAngle()
        )

    local directionX =
        math.cos(angle)

    local directionY =
        math.sin(angle)

    local minimapWidth =
        Minimap:GetWidth() or 140

    local minimapHeight =
        Minimap:GetHeight() or 140

    local halfWidth =
        (minimapWidth / 2)
        + BUTTON_PADDING

    local halfHeight =
        (minimapHeight / 2)
        + BUTTON_PADDING

    local absoluteX =
        math.abs(directionX)

    local absoluteY =
        math.abs(directionY)

    local distanceX

    if absoluteX > 0.0001 then
        distanceX =
            halfWidth / absoluteX
    else
        distanceX =
            math.huge
    end

    local distanceY

    if absoluteY > 0.0001 then
        distanceY =
            halfHeight / absoluteY
    else
        distanceY =
            math.huge
    end

    -- Place the button on the outside edge of the
    -- minimap's current rectangular bounds.
    --
    -- This works with round, square, resized and
    -- relocated minimaps.
    local distance =
        math.min(
            distanceX,
            distanceY
        )

    local offsetX =
        directionX * distance

    local offsetY =
        directionY * distance

    self.button:ClearAllPoints()

    self.button:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        offsetX,
        offsetY
    )
end

function MinimapButton:RefreshVisibility()
    if not self.button then
        return
    end

    local shouldShow =
        not AL.db
        or not AL.db.settings
        or AL.db.settings
            .showMinimapButton
            ~= false

    if shouldShow then
        self.button:Show()
        self:UpdatePosition()
    else
        self.button:Hide()
    end
end

function MinimapButton:UpdateFromCursor()
    if not Minimap then
        return
    end

    local minimapX,
        minimapY =
        Minimap:GetCenter()

    if not minimapX
        or not minimapY
    then
        return
    end

    local cursorX,
        cursorY =
        GetCursorPosition()

    local interfaceScale =
        UIParent:GetEffectiveScale()
        or 1

    cursorX =
        cursorX / interfaceScale

    cursorY =
        cursorY / interfaceScale

    local differenceX =
        cursorX - minimapX

    local differenceY =
        cursorY - minimapY

    local angle =
        math.deg(
            atan2(
                differenceY,
                differenceX
            )
        )

    if angle < 0 then
        angle =
            angle + 360
    end

    self:SaveAngle(angle)
    self:UpdatePosition()
end

--------------------------------------------------
-- Button creation
--------------------------------------------------

function MinimapButton:CreateButton()
    if self.button then
        return
    end

    local button =
        CreateFrame(
            "Button",
            "AscensionLootMinimapButton",
            Minimap
        )

    button:SetWidth(32)
    button:SetHeight(32)

    button:SetFrameStrata("MEDIUM")

    button:SetFrameLevel(
        (
            Minimap:GetFrameLevel()
            or 0
        ) + 8
    )

    button:SetClampedToScreen(true)

    button:RegisterForClicks(
        "LeftButtonUp",
        "RightButtonUp"
    )

    button:RegisterForDrag(
        "LeftButton"
    )

    --------------------------------------------------
    -- Background
    --------------------------------------------------

    local background =
        button:CreateTexture(
            nil,
            "BACKGROUND"
        )

    background:SetTexture(
        "Interface\\Minimap\\UI-Minimap-Background"
    )

    background:SetWidth(24)
    background:SetHeight(24)

    background:SetPoint(
        "CENTER",
        button,
        "CENTER",
        0,
        0
    )

    button.background =
        background

    --------------------------------------------------
    -- Icon
    --------------------------------------------------

    local icon =
        button:CreateTexture(
            nil,
            "ARTWORK"
        )

    icon:SetTexture(
        "Interface\\Icons\\INV_Misc_Dice_02"
    )

    icon:SetWidth(20)
    icon:SetHeight(20)

    icon:SetPoint(
        "CENTER",
        button,
        "CENTER",
        0,
        0
    )

    icon:SetTexCoord(
        0.08,
        0.92,
        0.08,
        0.92
    )

    button.icon =
        icon

    --------------------------------------------------
    -- Standard minimap-button border
    --------------------------------------------------

    local border =
        button:CreateTexture(
            nil,
            "OVERLAY"
        )

    border:SetTexture(
        "Interface\\Minimap\\MiniMap-TrackingBorder"
    )

    border:SetWidth(54)
    border:SetHeight(54)

    border:SetPoint(
        "TOPLEFT",
        button,
        "TOPLEFT",
        0,
        0
    )

    button.border =
        border

    --------------------------------------------------
    -- Mouse highlight
    --------------------------------------------------

    local highlight =
        button:CreateTexture(
            nil,
            "HIGHLIGHT"
        )

    highlight:SetTexture(
        "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
    )

    highlight:SetBlendMode("ADD")

    highlight:SetAllPoints(
        button
    )

    button.highlight =
        highlight

    --------------------------------------------------
    -- Tooltip
    --------------------------------------------------

    button:SetScript(
        "OnEnter",
        function(self)
            GameTooltip:SetOwner(
                self,
                "ANCHOR_LEFT"
            )

            GameTooltip:AddLine(
                AL.name or "Ascension Loot",
                0.2,
                1,
                0.6
            )

            GameTooltip:AddLine(
                "Left click: Open loot window",
                1,
                1,
                1
            )

            GameTooltip:AddLine(
                "Right click: Open SR import",
                1,
                1,
                1
            )

            GameTooltip:AddLine(
                "Drag: Move minimap button",
                0.7,
                0.7,
                0.7
            )

            GameTooltip:Show()
        end
    )

    button:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    --------------------------------------------------
    -- Click handling
    --------------------------------------------------

    button:SetScript(
        "OnClick",
        function(self, mouseButton)
            if self.suppressClickUntil
                and GetTime()
                    < self.suppressClickUntil
            then
                return
            end

            if mouseButton
                == "LeftButton"
            then
                if AL.UI then
                    AL.UI:ShowLoot()
                end

            elseif mouseButton
                == "RightButton"
            then
                if AL.UI then
                    AL.UI:ShowSettings(
                        "import"
                    )
                end
            end
        end
    )

    --------------------------------------------------
    -- Drag handling
    --------------------------------------------------

    button:SetScript(
        "OnDragStart",
        function(self)
            self.dragging = true

            self:SetScript(
                "OnUpdate",
                function()
                    MinimapButton:
                        UpdateFromCursor()
                end
            )
        end
    )

    button:SetScript(
        "OnDragStop",
        function(self)
            MinimapButton:
                UpdateFromCursor()

            self:SetScript(
                "OnUpdate",
                nil
            )

            self.dragging = false

            -- Prevent the drag release from also
            -- being interpreted as a left click.
            self.suppressClickUntil =
                GetTime() + 0.20
        end
    )

    self.button =
        button
end

--------------------------------------------------
-- Initialisation
--------------------------------------------------

function MinimapButton:Initialize()
    if self.initialized then
        self:UpdatePosition()
        return
    end

    if not Minimap then
        AL:Print(
            "The minimap button could not be created.",
            1,
            0.3,
            0.3
        )

        return
    end

    self:CreateButton()

    self.initialized = true

    --------------------------------------------------
    -- Recalculate after minimap size changes
    --------------------------------------------------

    if Minimap.HookScript then
        Minimap:HookScript(
            "OnSizeChanged",
            function()
                MinimapButton:
                    UpdatePosition()
            end
        )

        Minimap:HookScript(
            "OnShow",
            function()
                MinimapButton:
                    UpdatePosition()
            end
        )
    end

    --------------------------------------------------
    -- Recalculate after entering the world
    --------------------------------------------------

    local refreshFrame =
        CreateFrame("Frame")

    refreshFrame:RegisterEvent(
        "PLAYER_ENTERING_WORLD"
    )

    refreshFrame:SetScript(
        "OnEvent",
        function()
            MinimapButton:
                UpdatePosition()
        end
    )

    self.refreshFrame =
        refreshFrame

    self:UpdatePosition()
    self:RefreshVisibility()
end