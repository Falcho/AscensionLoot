local AL = AscensionLoot

AL.UI = AL.UI or {}
local UI = AL.UI

local backdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function createButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width or 90)
    button:SetHeight(height or 24)
    button:SetText(text)
    return button
end

StaticPopupDialogs[
    "ASCENSIONLOOT_CLEAR_HISTORY"
] = {
    text =
        "Clear all loot history?\n\n"
        .. "This permanently removes %s entries. "
        .. "Active loot, imported reserves and "
        .. "settings are not affected.",

    button1 = "Clear History",
    button2 = CANCEL,

    OnAccept = function()
        if not AL.db then
            return
        end

        AL.db.history =
            AL.db.history or {}

        local removed =
            #AL.db.history

        wipe(
            AL.db.history
        )

        if AL.UI then
            AL.UI:RefreshHistory()
        end

        AL:Print(string.format(
            "Cleared %d history %s.",
            removed,
            removed == 1
                and "entry"
                or "entries"
        ))
    end,

    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

local function createCheckbox(
    parent,
    label,
    settingKey,
    x,
    y,
    tooltip,
    onChanged
)
    local checkbox =
        CreateFrame(
            "CheckButton",
            nil,
            parent,
            "UICheckButtonTemplate"
        )

    checkbox:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        x or 18,
        y or -10
    )

    checkbox:SetWidth(26)
    checkbox:SetHeight(26)

    checkbox.text =
        parent:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    checkbox.text:SetPoint(
        "LEFT",
        checkbox,
        "RIGHT",
        3,
        0
    )

    checkbox.text:SetWidth(250)
    checkbox.text:SetJustifyH("LEFT")
    checkbox.text:SetText(label)

    checkbox.settingKey =
        settingKey

    checkbox.tooltip =
        tooltip

    checkbox:SetScript(
        "OnClick",
        function(self)
            local enabled =
                self:GetChecked()
                and true
                or false

            AL.db.settings[settingKey] =
                enabled

            if onChanged then
                onChanged(
                    enabled,
                    self
                )
            end

            if AL.UI
                and AL.UI.RefreshSettings
            then
                AL.UI:RefreshSettings()
            end
        end
    )

    checkbox:SetScript(
        "OnEnter",
        function(self)
            if not self.tooltip
                or self.tooltip == ""
            then
                return
            end

            GameTooltip:SetOwner(
                self,
                "ANCHOR_RIGHT"
            )

            GameTooltip:SetText(
                label,
                1,
                0.82,
                0
            )

            GameTooltip:AddLine(
                self.tooltip,
                1,
                1,
                1,
                true
            )

            GameTooltip:Show()
        end
    )

    checkbox:SetScript(
        "OnLeave",
        function()
            GameTooltip:Hide()
        end
    )

    return checkbox
end

local function createSectionTitle(
    parent,
    text,
    x,
    y
)
    local title =
        parent:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormalLarge"
        )

    title:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        x,
        y
    )

    title:SetText(text)

    return title
end

local function saveWindowGeometry(frame, databaseKey)
    if not frame or not AL.db or not AL.db.windows then
        return
    end

    local settings = AL.db.windows[databaseKey]
    if not settings then
        return
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)

    settings.point = point or "CENTER"
    settings.relativePoint = relativePoint or "CENTER"
    settings.x = x or 0
    settings.y = y or 0
    settings.width = frame:GetWidth()
    settings.height = frame:GetHeight()
    settings.scale = frame:GetScale()
end

local function applyWindowGeometry(frame, databaseKey)
    local settings = AL.db.windows[databaseKey]

    frame:SetWidth(settings.width or 700)
    frame:SetHeight(settings.height or 560)
    frame:SetScale(settings.scale or 1)

    frame:ClearAllPoints()
    frame:SetPoint(
        settings.point or "CENTER",
        UIParent,
        settings.relativePoint or "CENTER",
        settings.x or 0,
        settings.y or 0
    )
end

local function makeResizable(frame, databaseKey, minWidth, minHeight)
    frame:SetResizable(true)

    if frame.SetMinResize then
        frame:SetMinResize(minWidth or 500, minHeight or 350)
    end

    if frame.SetMaxResize then
        frame:SetMaxResize(1200, 900)
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetWidth(24)
    grip:SetHeight(24)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)

    grip:SetNormalTexture(
        "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
    )

    grip:SetHighlightTexture(
        "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"
    )

    grip:SetPushedTexture(
        "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
    )

    grip:RegisterForClicks("LeftButtonDown", "LeftButtonUp")

    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)

    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveWindowGeometry(frame, databaseKey)

        if UI then
            UI:UpdateDynamicWidths()
            UI:RefreshAll()
        end
    end)

    frame.resizeGrip = grip
end

--------------------------------------------------
-- ESC-close handling
--------------------------------------------------

local ESCAPE_FRAME_NAMES = {
    "AscensionLootLootFrame",
    "AscensionLootSettingsFrame",
}

local function removeSpecialFrame(
    frameName
)
    if not UISpecialFrames then
        return
    end

    for index =
        #UISpecialFrames,
        1,
        -1
    do
        if UISpecialFrames[index]
            == frameName
        then
            table.remove(
                UISpecialFrames,
                index
            )
        end
    end
end

function UI:RefreshEscapeCloseRegistration()
    if not UISpecialFrames then
        return
    end

    --------------------------------------------------
    -- Remove existing registrations first.
    --
    -- This prevents duplicates when the setting is
    -- toggled repeatedly.
    --------------------------------------------------

    for _, frameName in ipairs(
        ESCAPE_FRAME_NAMES
    ) do
        removeSpecialFrame(
            frameName
        )
    end

    local enabled =
        not AL.db
        or not AL.db.settings
        or AL.db.settings
            .closeWindowsWithEscape
            ~= false

    if not enabled then
        return
    end

    --------------------------------------------------
    -- UISpecialFrames is WoW's normal mechanism for
    -- windows that should close when ESC is pressed.
    --------------------------------------------------

    for _, frameName in ipairs(
        ESCAPE_FRAME_NAMES
    ) do
        table.insert(
            UISpecialFrames,
            frameName
        )
    end
end

local function createWindow(
    globalName,
    titleText,
    databaseKey,
    minWidth,
    minHeight
)
    local frame = CreateFrame("Frame", globalName, UIParent)

    frame:SetBackdrop(backdrop)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    applyWindowGeometry(frame, databaseKey)

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveWindowGeometry(self, databaseKey)
    end)

    frame:SetScript("OnSizeChanged", function()
        if UI then
            UI:UpdateDynamicWidths()
        end
    end)

    local title = frame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalLarge"
    )

    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -18)
    title:SetText(titleText)

    frame.title = title

    local version = frame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontDisableSmall"
    )

    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText("v" .. AL.version)

    local close = CreateFrame(
        "Button",
        nil,
        frame,
        "UIPanelCloseButton"
    )

    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

    makeResizable(
        frame,
        databaseKey,
        minWidth,
        minHeight
    )

    frame:Hide()

    return frame
end

local function setTooltip(button, itemLink)
    button:SetScript("OnEnter", function(self)
        if not itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI:Create()
    if self.created then
        return
    end

    self:CreateLootFrame()
    self:CreateSettingsFrame()

    self:RefreshEscapeCloseRegistration()

    StaticPopupDialogs["ASCENSIONLOOT_CONFIRM_AWARD"] = {
        text = "Award %s to %s?",
        button1 = YES,
        button2 = NO,

        OnAccept = function()
            AL.Loot:ConfirmAward()
        end,

        OnCancel = function()
            AL.Loot.confirmData = nil
        end,

        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    self.created = true

    -- Start on the Reserves tab, but do not show either window yet.
    self:ShowSettingsTab("reserves")
end

function UI:CreateLootFrame()
    if self.lootFrame then
        return
    end

    local frame = createWindow(
        "AscensionLootLootFrame",
        "Ascension Loot — Loot",
        "loot",
        500,
        350
    )

    self.lootFrame = frame

    local settingsButton = createButton(
        frame,
        "Settings",
        90,
        24
    )

    settingsButton:SetPoint(
        "TOPRIGHT",
        frame,
        "TOPRIGHT",
        -42,
        -12
    )

    settingsButton:SetScript("OnClick", function()
        UI:ShowSettings("settings")
    end)

    local panel = CreateFrame("Frame", nil, frame)

    panel:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        18,
        -52
    )

    panel:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -18,
        18
    )

    self.lootPanel = panel

    self:CreateLootPanel(panel)
end

function UI:CreateSettingsFrame()
    if self.settingsFrame then
        return
    end

    local frame = createWindow(
        "AscensionLootSettingsFrame",
        "Ascension Loot — Settings",
        "settings",
        650,
        520
    )

    self.settingsFrame = frame
    self.tabs = {}
    self.panels = {}

    local tabNames = {
        "reserves",
        "import",
        "history",
        "settings",
    }

    local tabLabels = {
        "Reserves",
        "Import",
        "History",
        "Settings",
    }

    for index, tabName in ipairs(tabNames) do
        local tab = createButton(
            frame,
            tabLabels[index],
            120,
            25
        )

        tab:SetPoint(
            "TOPLEFT",
            frame,
            "TOPLEFT",
            18 + ((index - 1) * 135),
            -50
        )

        tab:SetScript("OnClick", function()
            UI:ShowSettingsTab(tabName)
        end)

        self.tabs[tabName] = tab

        local panel = CreateFrame("Frame", nil, frame)

        panel:SetPoint(
            "TOPLEFT",
            frame,
            "TOPLEFT",
            18,
            -82
        )

        panel:SetPoint(
            "BOTTOMRIGHT",
            frame,
            "BOTTOMRIGHT",
            -18,
            18
        )

        panel:Hide()

        self.panels[tabName] = panel
    end

    self:CreateReservesPanel(self.panels.reserves)
    self:CreateImportPanel(self.panels.import)
    self:CreateHistoryPanel(self.panels.history)
    self:CreateSettingsPanel(self.panels.settings)
end

function UI:CreateLootPanel(panel)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -2)
    hint:SetText("Alt-click: start roll. Shift+Alt-click: assign directly to the sole soft reserver.")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -24)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 200)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(620)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    self.lootChild = child
    self.lootRows = {}

    local rollPanel = CreateFrame("Frame", nil, panel)
    rollPanel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    rollPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    rollPanel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    rollPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    rollPanel:SetHeight(190)
    self.rollPanel = rollPanel

    rollPanel.title = rollPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rollPanel.title:SetPoint("TOPLEFT", rollPanel, "TOPLEFT", 12, -10)
    rollPanel.title:SetText("No active roll")

    rollPanel.timer = rollPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rollPanel.timer:SetPoint("TOPRIGHT", rollPanel, "TOPRIGHT", -12, -10)

    rollPanel.results = rollPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rollPanel.results:SetPoint("TOPLEFT", rollPanel, "TOPLEFT", 12, -34)
    rollPanel.results:SetPoint("TOPRIGHT", rollPanel, "TOPRIGHT", -12, -34)
    rollPanel.results:SetJustifyH("LEFT")
    rollPanel.results:SetText("")

    --------------------------------------------------
    -- Loot-holder roll buttons
    --------------------------------------------------

    rollPanel.roll = createButton(rollPanel,"Roll",60,22)
    rollPanel.roll:SetPoint("BOTTOMLEFT", rollPanel, "BOTTOMLEFT", 12, 10)

    rollPanel.roll:SetScript(
        "OnClick",
        function()
            local active =
                AL.Roll
                and AL.Roll.active

            if not active then
                return
            end

            if active.state ~= "rolling"
                and active.state ~= "tie"
            then
                return
            end

            if active.state == "tie" then
                local expectedMaximum =
                    active.tie
                    and tonumber(
                        active.tie.expectedMaximum
                    )
                    or 100

                if expectedMaximum ~= 100 then
                    return
                end
            end

            RandomRoll(
                1,
                100
            )
        end
    )

    rollPanel.os = createButton(
        rollPanel,
        "OS",
        60,
        22
    )

    rollPanel.os:SetPoint(
        "LEFT",
        rollPanel.roll,
        "RIGHT",
        8,
        0
    )

    rollPanel.os:SetScript(
        "OnClick",
        function()
            local active =
                AL.Roll
                and AL.Roll.active

            if not active then
                return
            end

            if active.state ~= "rolling"
                and active.state ~= "tie"
            then
                return
            end

            if active.state == "tie" then
                local expectedMaximum =
                    active.tie
                    and tonumber(
                        active.tie.expectedMaximum
                    )
                    or 100

                if expectedMaximum ~= 99 then
                    return
                end
            end

            RandomRoll(
                1,
                99
            )
        end
    )

    --------------------------------------------------
    -- Roll controls
    --------------------------------------------------

    rollPanel.finish = createButton(
        rollPanel,
        "Finish",
        75,
        22
    )

    rollPanel.finish:SetPoint(
        "LEFT",
        rollPanel.os,
        "RIGHT",
        8,
        0
    )

    rollPanel.finish:SetScript(
        "OnClick",
        function()
            AL.Roll:Finish()
        end
    )

    rollPanel.cancel = createButton(
        rollPanel,
        "Cancel",
        75,
        22
    )

    rollPanel.cancel:SetPoint(
        "LEFT",
        rollPanel.finish,
        "RIGHT",
        8,
        0
    )

    rollPanel.cancel:SetScript(
        "OnClick",
        function()
            AL.Roll:Cancel()
        end
    )

    rollPanel.award = createButton(
        rollPanel,
        "Award Winners",
        115,
        22
    )

    rollPanel.award:SetPoint(
        "LEFT",
        rollPanel.cancel,
        "RIGHT",
        8,
        0
    )

    rollPanel.award:SetScript(
        "OnClick",
        function()
            if AL.Roll.active then
                AL.Loot:AwardActiveWinners(
                    AL.Roll.active.item
                )
            end
        end
    )
end

local LOOT_ROW_HEIGHT = 48
local LOOT_ROW_STEP = 52

function UI:CreateLootRow(index)
    local child = self.lootChild
    local row = CreateFrame("Button", nil, child)
    row:SetHeight(LOOT_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -((index - 1) * LOOT_ROW_STEP))
    row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
    row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    row:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
    row:RegisterForClicks("LeftButtonUp")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(32)
    row.icon:SetHeight(32)
    row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)

    row.name = row:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormal"
    )

    row.name:SetPoint(
        "TOPLEFT",
        row.icon,
        "TOPRIGHT",
        8,
        -1
    )

    row.name:SetPoint(
        "RIGHT",
        row,
        "RIGHT",
        -220,
        0
    )

    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.reserves = row:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlightSmall"
    )

    row.reserves:SetPoint(
        "TOPLEFT",
        row.name,
        "BOTTOMLEFT",
        0,
        -3
    )

    row.reserves:SetPoint(
        "RIGHT",
        row,
        "RIGHT",
        -220,
        0
    )

    row.reserves:SetJustifyH("LEFT")
    row.reserves:SetWordWrap(false)

    -- Roll button
    row.roll = createButton(
        row,
        "Roll",
        48,
        18
    )

    row.roll:SetScript("OnClick", function()
        if row.item and AL.Roll then
            AL.Roll:StartForItem(row.item)
        end
    end)

    -- Award button
    row.award = createButton(
        row,
        "Award",
        52,
        18
    )

    row.award:SetScript("OnClick", function()
        if not row.item or not AL.Loot then
            return
        end

        local active =
            AL.Roll and AL.Roll.active

        if active
            and active.state == "finished"
            and active.item
            and AL:GetItemKey(active.item)
                == AL:GetItemKey(row.item)
        then
            AL.Loot:AwardActiveWinners(
                row.item
            )
        else
            AL.Loot:DirectAward(
                row.item
            )
        end
    end)

    -- Trade button
    row.trade = createButton(
        row,
        "Trade",
        50,
        18
    )

    row.trade:SetScript("OnClick", function()
        if not row.item or not AL.Trade then
            return
        end

        if row.item.status ~= "awaiting_trade" then
            AL:Print(
                "This item is not awaiting trade.",
                1,
                0.5,
                0.2
            )

            return
        end

        AL.Trade:TryStart(
            row.item
        )
    end)

    -- Skip button
    -- Same width as Trade so they align exactly.
    row.skip = createButton(
        row,
        "Skip",
        50,
        18
    )

    row.skip:SetScript("OnClick", function()
        if not row.item then
            return
        end

        -- Demo and temporary loot-window items may not
        -- have a status yet, so nil is also allowed.
        if row.item.status
            and row.item.status ~= "unassigned"
        then
            AL:Print(
                "Only unassigned items can be skipped.",
                1,
                0.5,
                0.2
            )

            return
        end

        row.item.skipped = true
        UI:RefreshLoot()
    end)

    --------------------------------------------------
    -- Button positioning
    --------------------------------------------------

    -- Trade is anchored to the upper-right corner.
    row.trade:ClearAllPoints()
    row.trade:SetPoint(
        "TOPRIGHT",
        row,
        "TOPRIGHT",
        -8,
        -4
    )

    -- Award sits immediately to the left of Trade.
    row.award:ClearAllPoints()
    row.award:SetPoint(
        "RIGHT",
        row.trade,
        "LEFT",
        -4,
        0
    )

    -- Roll sits immediately to the left of Award.
    row.roll:ClearAllPoints()
    row.roll:SetPoint(
        "RIGHT",
        row.award,
        "LEFT",
        -4,
        0
    )

    -- Skip sits directly underneath Trade.
    -- TOPRIGHT to BOTTOMRIGHT keeps their right edges aligned.
    row.skip:ClearAllPoints()
    row.skip:SetPoint(
        "TOPRIGHT",
        row.trade,
        "BOTTOMRIGHT",
        0,
        -2
    )

    row:SetScript("OnClick", function()
        if not row.item then
            return
        end

        if IsAltKeyDown() and IsShiftKeyDown() then
            AL.Loot:DirectAward(row.item)

        elseif IsAltKeyDown() then
            AL.Roll:StartForItem(row.item)

        elseif IsShiftKeyDown()
            and row.item.link
            and ChatEdit_InsertLink
        then
            ChatEdit_InsertLink(row.item.link)
        end
    end)

    self.lootRows[index] = row
    return row
end

function UI:RefreshLoot()
    if not self.lootFrame or not AL.Loot then
        return
    end

    local visibleItems = {}

    -- Show items collected for later distribution.
    if AL.LootSession then
        for _, item in ipairs(
            AL.LootSession:GetItems() or {}
        ) do
            if not item.skipped
                and item.status ~= "traded"
                and item.status ~= "kept"
            then
                table.insert(
                    visibleItems,
                    item
                )
            end
        end
    end

    -- Keep demo items available for /al demo.
    for _, item in ipairs(AL.Loot.items or {}) do
        if item.demo and not item.skipped then
            table.insert(visibleItems, item)
        end
    end

    for index, item in ipairs(visibleItems) do
        local row = self.lootRows[index] or self:CreateLootRow(index)
        row.item = item
        if item.status
            and item.status ~= "unassigned"
        then
            row.skip:Disable()
        else
            row.skip:Enable()
        end
        row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(item.link or item.name or ("Item " .. tostring(item.id)))

        local reservers = AL.SoftReserve:GetReservers(item.id)

        local reserveText

        if AL.SoftReserve:IsHardReserved(item.id) then
            reserveText =
                "|cffff5555Hard reserved|r"

        elseif #reservers > 0 then
            local names = {}

            for _, reserver in ipairs(reservers) do
                local suffix = ""

                if reserver.count > 1 then
                    suffix = " x" .. reserver.count
                end

                table.insert(
                    names,
                    reserver.name .. suffix
                )
            end

            reserveText =
                "|cff66ff66SR:|r "
                .. table.concat(names, ", ")

        else
            reserveText =
                "|cff999999No soft reserves|r"
        end

        local secondaryText = reserveText

        local activeRollMatches =
            AL.Roll
            and AL.Roll.active
            and AL.Roll.active.item
            and AL:GetItemKey(AL.Roll.active.item)
                == AL:GetItemKey(item)

        if activeRollMatches then
            secondaryText =
                "|cffffff66"
                .. tostring(
                    AL.Roll.active.message
                        or (
                            AL.Roll.active.label
                            .. " roll active"
                        )
                )
                .. "|r"

        elseif item.status == "awaiting_trade" then
            local tradeMessage =
                "Awaiting trade to "
                .. tostring(
                    item.winner or "Unknown"
                )

            if item.tradeStatus == "waiting_for_range" then
                tradeMessage =
                    tostring(item.winner)
                    .. " is not in trade range"

            elseif item.tradeStatus == "waiting_for_player" then
                tradeMessage =
                    tostring(item.winner)
                    .. " is not currently in the group"

            elseif item.tradeStatus == "waiting_for_combat" then
                tradeMessage =
                    "Waiting until combat ends"

            elseif item.tradeStatus == "trade_requested" then
                tradeMessage =
                    "Trade requested with "
                    .. tostring(item.winner)

            elseif item.tradeStatus == "trade_cancelled" then
                tradeMessage =
                    "Trade cancelled — click Trade to retry"

            elseif item.tradeStatus == "item_not_found" then
                tradeMessage =
                    "Assigned item not found in bags"

            elseif item.tradeStatus == "pickup_failed" then
                tradeMessage =
                    "Could not place item in trade"
            end

            secondaryText =
                "|cffffcc66"
                .. tradeMessage
                .. "|r"

        elseif item.status == "in_trade" then
            secondaryText =
                "|cff66ccffIn trade window for "
                .. tostring(
                    item.winner or "Unknown"
                )
                .. "|r"

        elseif item.status == "traded" then
            secondaryText =
                "|cff66ff66Traded to "
                .. tostring(
                    item.tradedTo
                        or item.winner
                        or "Unknown"
                )
                .. "|r"
        end

        row.reserves:SetText(secondaryText)

        setTooltip(row, item.link)
        row:Show()
    end

    for index = #visibleItems + 1, #self.lootRows do
        self.lootRows[index]:Hide()
    end

    self.lootChild:SetHeight(math.max(1, #visibleItems * LOOT_ROW_STEP))
    self:RefreshRoll()
end

function UI:RefreshRollTimer()
    if not self.rollPanel or not AL.Roll then
        return
    end

    if not AL.Roll.active then
        self.rollPanel.timer:SetText("")
        return
    end

    local state =
        AL.Roll.active.state

    if state ~= "rolling"
        and state ~= "tie"
    then
        self.rollPanel.timer:SetText("")
        return
    end

    self.rollPanel.timer:SetText(
        math.max(
            0,
            math.ceil(
                AL.Roll.active.endsAt
                    - GetTime()
            )
        )
        .. "s"
    )
end

function UI:RefreshRoll()
    if not self.rollPanel then
        return
    end

    if not AL.Roll then
        self.rollPanel.title:SetText(
            "RollManager failed to load"
        )

        self.rollPanel.timer:SetText("")

        self.rollPanel.results:SetText(
            "Check the Lua errors in RollManager.lua."
        )

        self.rollPanel.roll:Disable()
        self.rollPanel.os:Disable()
        self.rollPanel.finish:Disable()
        self.rollPanel.cancel:Disable()
        self.rollPanel.award:Disable()

        return
    end

    local active = AL.Roll.active

    if not active then
        self.rollPanel.title:SetText(
            "No active roll"
        )

        self.rollPanel.timer:SetText("")

        self.rollPanel.results:SetText(
            "Alt-click an item to begin one combined "
                .. "SR / MS / OS roll."
        )

        self.rollPanel.roll:Disable()
        self.rollPanel.os:Disable()
        self.rollPanel.finish:Disable()
        self.rollPanel.cancel:Disable()
        self.rollPanel.award:Disable()

        return
    end

    self.rollPanel.title:SetText(
        string.format(
            "%s — %s — %d %s",
            active.label,
            active.item.link
                or active.item.name,
            active.copyCount or 1,
            (active.copyCount or 1) == 1
                and "copy"
                or "copies"
        )
    )

    self:RefreshRollTimer()

    local lines = {}
    local results =
        AL.Roll:GetSortedResults()

    local winningNames = {}

    for _, winner in ipairs(
        active.proposedWinners or {}
    ) do
        winningNames[
            winner.normalizedName
        ] = true
    end

    for index, result in ipairs(results) do
        local extraRollText = ""

        if #(result.rolls or {}) > 1 then
            local values = {}

            for _, value in ipairs(
                result.rolls
            ) do
                table.insert(
                    values,
                    tostring(value)
                )
            end

            extraRollText =
                " ["
                .. table.concat(values, ", ")
                .. "]"
        end

        local tieText = ""

        if result.tieRoll then
            tieText =
                " [tie: "
                .. tostring(result.tieRoll)
                .. "]"
        end

        local winnerMarker = ""

        if active.state == "finished"
            and winningNames[
                result.normalizedName
            ]
        then
            winnerMarker = " |cff66ff66WINNER|r"
        end

        table.insert(
            lines,
            string.format(
                "%d. %s — %d (%s)%s%s%s",
                index,
                result.name,
                result.roll,
                result.category,
                extraRollText,
                tieText,
                winnerMarker
            )
        )

        if #lines >= 8 then
            break
        end
    end

    if #results > 8 then
        table.insert(
            lines,
            string.format(
                "... and %d more",
                #results - 8
            )
        )
    end

    if #lines == 0 then
        table.insert(
            lines,
            active.message
                or "Waiting for rolls..."
        )
    end

    self.rollPanel.results:SetText(
        table.concat(lines, "\n")
    )

    --------------------------------------------------
    -- Loot-holder Roll / OS availability
    --------------------------------------------------

    if active.state == "rolling" then
        self.rollPanel.roll:Enable()
        self.rollPanel.os:Enable()

    elseif active.state == "tie" then
        local expectedMaximum =
            active.tie
            and tonumber(
                active.tie.expectedMaximum
            )
            or 100

        if expectedMaximum == 99 then
            self.rollPanel.roll:Disable()
            self.rollPanel.os:Enable()
        else
            self.rollPanel.roll:Enable()
            self.rollPanel.os:Disable()
        end

    else
        self.rollPanel.roll:Disable()
        self.rollPanel.os:Disable()
    end

    --------------------------------------------------
    -- Distributor controls
    --------------------------------------------------

    if active.state == "rolling"
        or active.state == "tie"
    then
        self.rollPanel.finish:Enable()
    else
        self.rollPanel.finish:Disable()
    end

    self.rollPanel.cancel:Enable()

    if active.state == "finished"
        and #(active.proposedWinners or {}) > 0
    then
        self.rollPanel.award:Enable()
    else
        self.rollPanel.award:Disable()
    end
end

function UI:CreateReservesPanel(panel)
    panel.summary = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.summary:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -5)
    panel.summary:SetPoint("RIGHT", panel, "RIGHT", -5, 0)
    panel.summary:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -35)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(620)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    panel.child = child
    panel.lines = {}
end

function UI:UpdateDynamicWidths()
    if self.lootPanel and self.lootChild then
        local width = self.lootPanel:GetWidth() - 35

        if width > 1 then
            self.lootChild:SetWidth(width)
        end
    end

    local reservesPanel =
        self.panels and self.panels.reserves

    if reservesPanel and reservesPanel.child then
        local width = reservesPanel:GetWidth() - 35

        if width > 1 then
            reservesPanel.child:SetWidth(width)

            for _, line in ipairs(
                reservesPanel.lines or {}
            ) do
                line:SetWidth(width - 10)
            end
        end
    end

    local historyPanel =
        self.panels and self.panels.history

    if historyPanel and historyPanel.child then
        local width = historyPanel:GetWidth() - 35

        if width > 1 then
            historyPanel.child:SetWidth(width)

            for _, line in ipairs(
                historyPanel.lines or {}
            ) do
                line:SetWidth(width - 10)
            end
        end
    end

    local importPanel =
        self.panels and self.panels.import

    if importPanel and importPanel.edit then
        local width = importPanel:GetWidth() - 35

        if width > 1 then
            importPanel.edit:SetWidth(width)
        end
    end
end

function UI:RefreshReserves()
    local panel = self.panels and self.panels.reserves
    if not panel then return end
    panel.summary:SetText(AL.SoftReserve:GetSummaryText())

    local lineIndex = 1
    for _, player in ipairs(AL.SoftReserve:GetSortedPlayers()) do
        local items = {}
        for itemID, item in pairs(
            player.items
        ) do
            local itemInfo =
                AL.SoftReserve:
                    GetDisplayItemInfo(
                        itemID
                    )

            local label

            if itemInfo.link
                or itemInfo.name
            then
                label =
                    itemInfo.link
                    or itemInfo.name

            elseif itemInfo.failed then
                label =
                    "Item #"
                    .. tostring(itemID)
                    .. " (details unavailable)"

            else
                label =
                    string.format(
                        "Loading item %s... (%d/%d)",
                        tostring(itemID),
                        tonumber(
                            itemInfo.attempt
                        ) or 1,
                        tonumber(
                            itemInfo.maxAttempts
                        ) or 3
                    )
            end

            if item.count > 1 then
                label =
                    label
                    .. " x"
                    .. item.count
            end

            table.insert(
                items,
                {
                    id =
                        itemID,

                    text =
                        label,
                }
            )
        end
        table.sort(items, function(left, right) return left.id < right.id end)

        local line = panel.lines[lineIndex]
        if not line then
            line = panel.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line:SetWidth(610)
            line:SetJustifyH("LEFT")
            line:SetPoint("TOPLEFT", panel.child, "TOPLEFT", 2, -((lineIndex - 1) * 24))
            panel.lines[lineIndex] = line
        end
        local texts = {}
        for _, item in ipairs(items) do table.insert(texts, item.text) end
        line:SetText("|cff33ff99" .. player.name .. ":|r " .. table.concat(texts, ", "))
        line:Show()
        lineIndex = lineIndex + 1
    end

    if lineIndex == 1 then
        local line = panel.lines[1]
        if not line then
            line = panel.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line:SetPoint("TOPLEFT", panel.child, "TOPLEFT", 2, 0)
            panel.lines[1] = line
        end
        line:SetText("No soft-reserve data imported.")
        line:Show()
        lineIndex = 2
    end

    for index = lineIndex, #panel.lines do panel.lines[index]:Hide() end
    panel.child:SetHeight(math.max(1, (lineIndex - 1) * 24))
end

function UI:CreateImportPanel(panel)
    --------------------------------------------------
    -- Help text
    --------------------------------------------------

    local help =
        panel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    help:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        5,
        -5
    )

    help:SetText(
        "Paste BisBeard's RollFor export below, then click Import."
    )

    --------------------------------------------------
    -- Import text area
    --------------------------------------------------

    local scroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            panel,
            "UIPanelScrollFrameTemplate"
        )

    scroll:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        0,
        -32
    )

    scroll:SetPoint(
        "BOTTOMRIGHT",
        panel,
        "BOTTOMRIGHT",
        -30,
        80
    )

    -- Give the text area a clearly visible background.
    scroll:SetBackdrop({
        bgFile =
            "Interface\\Tooltips\\UI-Tooltip-Background",

        edgeFile =
            "Interface\\Tooltips\\UI-Tooltip-Border",

        tile = true,
        tileSize = 16,
        edgeSize = 12,

        insets = {
            left = 3,
            right = 3,
            top = 3,
            bottom = 3,
        },
    })

    scroll:SetBackdropColor(
        0.02,
        0.02,
        0.02,
        0.95
    )

    scroll:SetBackdropBorderColor(
        0.55,
        0.55,
        0.55,
        1
    )

    local edit =
        CreateFrame(
            "EditBox",
            nil,
            scroll
        )

    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)

    edit:SetWidth(610)
    edit:SetHeight(340)

    edit:SetTextInsets(
        8,
        8,
        8,
        8
    )

    edit:SetTextColor(
        1,
        1,
        1
    )

    edit:SetJustifyH("LEFT")
    edit:SetJustifyV("TOP")

    edit:SetScript(
        "OnEscapePressed",
        function(self)
            self:ClearFocus()
        end
    )

    --------------------------------------------------
    -- 3.3.5-compatible height calculation
    --------------------------------------------------

    local function updateEditHeight()
        local text =
            edit:GetText()
            or ""

        local availableWidth =
            math.max(
                (edit:GetWidth() or 610) - 20,
                100
            )

        -- Approximate the number of characters fitting
        -- on a line using ChatFontNormal.
        local charactersPerLine =
            math.max(
                math.floor(
                    availableWidth / 6
                ),
                1
            )

        local visualLineCount = 0

        -- Appending a newline ensures that the final
        -- line is included in the calculation.
        for line in (
            text .. "\n"
        ):gmatch("(.-)\n") do
            visualLineCount =
                visualLineCount
                + math.max(
                    1,
                    math.ceil(
                        #line
                        / charactersPerLine
                    )
                )
        end

        local calculatedHeight =
            visualLineCount * 14 + 30

        edit:SetHeight(
            math.max(
                340,
                calculatedHeight
            )
        )
    end

    edit:SetScript(
        "OnTextChanged",
        function()
            updateEditHeight()
        end
    )

    scroll:SetScrollChild(edit)

    -- Adapt the edit box to resized Settings windows.
    scroll:SetScript(
        "OnSizeChanged",
        function(self)
            local width =
                self:GetWidth()

            if width
                and width > 40
            then
                edit:SetWidth(
                    width - 12
                )

                updateEditHeight()
            end
        end
    )

    panel.edit = edit
    panel.importScroll = scroll

    --------------------------------------------------
    -- Import button
    --------------------------------------------------

    panel.import =
        createButton(
            panel,
            "Import",
            100,
            25
        )

    panel.import:SetPoint(
        "BOTTOMLEFT",
        panel,
        "BOTTOMLEFT",
        5,
        40
    )

    panel.import:SetScript(
        "OnClick",
        function()
            local importText =
                panel.edit:GetText()
                or ""

            if AL:Trim(importText) == "" then
                local message =
                    "Paste a BisBeard RollFor export before importing."

                panel.status:SetText(
                    message
                )

                AL:Print(
                    message,
                    1,
                    0.3,
                    0.3
                )

                return
            end

            local success,
                message =
                AL.SoftReserve:Import(
                    importText
                )

            panel.status:SetText(
                message or ""
            )

            if success then
                AL:Print(message)
            else
                AL:Print(
                    message,
                    1,
                    0.3,
                    0.3
                )
            end
        end
    )

    --------------------------------------------------
    -- Clear Data button
    --------------------------------------------------

    panel.clear =
        createButton(
            panel,
            "Clear Data",
            100,
            25
        )

    panel.clear:SetPoint(
        "LEFT",
        panel.import,
        "RIGHT",
        10,
        0
    )

    panel.clear:SetScript(
        "OnClick",
        function()
            --------------------------------------------------
            -- Clear imported reserve data
            --------------------------------------------------

            if AL.SoftReserve
                and AL.SoftReserve.Clear
            then
                AL.SoftReserve:Clear()
            end

            --------------------------------------------------
            -- Clear the pasted import string
            --------------------------------------------------

            panel.edit:SetText("")
            panel.edit:ClearFocus()

            panel.importScroll:
                SetVerticalScroll(0)

            updateEditHeight()

            --------------------------------------------------
            -- Refresh other panels using reserve data
            --------------------------------------------------

            if UI.RefreshAll then
                UI:RefreshAll()
            end

            panel.status:SetText(
                "Soft-reserve data and import text cleared."
            )

            AL:Print(
                "Soft-reserve data and import text cleared."
            )
        end
    )

    --------------------------------------------------
    -- Status text
    --------------------------------------------------

    panel.status =
        panel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlightSmall"
        )

    panel.status:SetPoint(
        "BOTTOMLEFT",
        panel,
        "BOTTOMLEFT",
        5,
        8
    )

    panel.status:SetPoint(
        "RIGHT",
        panel,
        "RIGHT",
        -5,
        0
    )

    panel.status:SetJustifyH("LEFT")

    --------------------------------------------------
    -- Initial layout
    --------------------------------------------------

    updateEditHeight()
end

function UI:ShowClearHistoryConfirmation()
    local history =
        AL.db
        and AL.db.history
        or {}

    local count =
        #history

    if count == 0 then
        AL:Print(
            "Loot history is already empty."
        )

        return
    end

    StaticPopup_Show(
        "ASCENSIONLOOT_CLEAR_HISTORY",
        tostring(count)
    )
end

function UI:CreateHistoryPanel(panel)
    local scroll =
        CreateFrame(
            "ScrollFrame",
            nil,
            panel,
            "UIPanelScrollFrameTemplate"
        )

    scroll:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        0,
        0
    )

    -- Leave room for the Clear History button.
    scroll:SetPoint(
        "BOTTOMRIGHT",
        panel,
        "BOTTOMRIGHT",
        -30,
        38
    )

    local child =
        CreateFrame(
            "Frame",
            nil,
            scroll
        )

    child:SetWidth(620)
    child:SetHeight(1)

    scroll:SetScrollChild(
        child
    )

    panel.child = child
    panel.lines = {}

    panel.clearHistory =
        createButton(
            panel,
            "Clear History",
            120,
            26
        )

    panel.clearHistory:SetPoint(
        "BOTTOMLEFT",
        panel,
        "BOTTOMLEFT",
        5,
        3
    )

    panel.clearHistory:SetScript(
        "OnClick",
        function()
            UI:
                ShowClearHistoryConfirmation()
        end
    )
end

function UI:RefreshHistory()
    local panel = self.panels and self.panels.history
    if not panel then return end

    local history = AL.db and AL.db.history or {}
    for index, entry in ipairs(history) do
        local line = panel.lines[index]
        if not line then
            line = panel.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line:SetWidth(610)
            line:SetJustifyH("LEFT")
            line:SetPoint("TOPLEFT", panel.child, "TOPLEFT", 2, -((index - 1) * 24))
            panel.lines[index] = line
        end
        local rollText = entry.winningRoll and (" — " .. entry.winningRoll) or ""
        line:SetText(string.format("%s  %s → |cff33ff99%s|r — %s%s", date("%H:%M", entry.timestamp), entry.itemLink or ("Item #" .. tostring(entry.itemID)), entry.winner or "Unknown", entry.reason or "Manual", rollText))
        line:Show()
    end

    if #history == 0 then
        local line = panel.lines[1]
        if not line then
            line = panel.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line:SetPoint("TOPLEFT", panel.child, "TOPLEFT", 2, 0)
            panel.lines[1] = line
        end
        line:SetText("No awarded loot has been recorded yet.")
        line:Show()
    end

    local startHide = math.max(1, #history + 1)
    for index = startHide, #panel.lines do panel.lines[index]:Hide() end
    panel.child:SetHeight(math.max(1, math.max(1, #history) * 24))
end

function UI:CreateSettingsPanel(panel)
    panel.checkboxes = {}
    panel.checkboxByKey = {}

    local function addCheckbox(
        label,
        settingKey,
        x,
        y,
        tooltip,
        onChanged
    )
        local checkbox =
            createCheckbox(
                panel,
                label,
                settingKey,
                x,
                y,
                tooltip,
                onChanged
            )

        table.insert(
            panel.checkboxes,
            checkbox
        )

        panel.checkboxByKey[settingKey] =
            checkbox

        return checkbox
    end

    --------------------------------------------------
    -- Left column: Tracking
    --------------------------------------------------

    createSectionTitle(
        panel,
        "Loot tracking",
        18,
        -5
    )

    addCheckbox(
        "Track Rare Bind-on-Pickup items",
        "trackRareBindOnPickup",
        18,
        -28,
        "Includes rare-quality items when they are Bind on Pickup."
    )

    addCheckbox(
        "Detect eligible Group Loot items",
        "trackEligibleBagLoot",
        18,
        -56,
        "Adds newly received bag items only when they display the temporary raid-trade timer."
    )

    addCheckbox(
        "Open loot window for tracked items",
        "autoShowLoot",
        18,
        -84,
        "Automatically opens the active loot window when an eligible item is registered."
    )

    --------------------------------------------------
    -- Left column: Master Loot
    --------------------------------------------------

    createSectionTitle(
        panel,
        "Master Loot",
        18,
        -120
    )

    addCheckbox(
        "Automatically collect tracked loot",
        "autoCollectTrackedLoot",
        18,
        -143,
        "Assigns eligible tracked Master Loot items to the configured loot holder."
    )

    addCheckbox(
        "Auto-loot all Master Loot to me",
        "autoMasterLootToSelf",
        18,
        -171,
        "During auto-loot, assigns every Master Loot item directly to the current Master Looter.",
        function(enabled)
            if not enabled then
                AL.db.settings
                    .autoConfirmMasterLootToSelf =
                    false
            end
        end
    )

    addCheckbox(
        "Auto-confirm addon BoP warnings",
        "autoConfirmMasterLootToSelf",
        18,
        -199,
        "Only confirms Bind-on-Pickup warnings for Master Loot assignments initiated by AscensionLoot."
    )

    --------------------------------------------------
    -- Left column: Ordinary autoloot
    --------------------------------------------------

    createSectionTitle(
        panel,
        "Ordinary autoloot",
        18,
        -235
    )

    addCheckbox(
        "Automatically loot coins",
        "autoLootCoins",
        18,
        -258,
        "Automatically collects money slots."
    )

    addCheckbox(
        "Automatically loot poor items",
        "autoLootPoor",
        18,
        -286,
        "Automatically collects grey-quality items."
    )

    addCheckbox(
        "Automatically loot common items",
        "autoLootCommon",
        18,
        -314,
        "Automatically collects white-quality items."
    )

    addCheckbox(
        "Protect reserved items from autoloot",
        "protectReservedItems",
        18,
        -342,
        "Prevents ordinary autoloot rules from collecting items listed as soft reserved or hard reserved."
    )

    --------------------------------------------------
    -- Right column: Rolls
    --------------------------------------------------

    createSectionTitle(
        panel,
        "Rolls and announcements",
        330,
        -5
    )

    addCheckbox(
        "Announce rolls to the group",
        "announceRolls",
        330,
        -28,
        "Sends roll starts, countdowns, ties and results to raid or party chat. When disabled, they are shown locally."
    )

    addCheckbox(
        "Announce item assignments",
        "announceAssignments",
        330,
        -56,
        "Announces the selected recipient after an item is assigned."
    )

    addCheckbox(
        "Duplicate SRs grant extra attempts",
        "duplicateReservesGiveExtraRolls",
        330,
        -84,
        "A player who reserved the same item more than once may roll once per reserve."
    )

    addCheckbox(
        "Confirm manual awards",
        "confirmAwards",
        330,
        -112,
        "Shows a confirmation before manually awarding an item from an open loot window."
    )

    --------------------------------------------------
    -- Right column: Trading
    --------------------------------------------------

    createSectionTitle(
        panel,
        "Trade assistance",
        330,
        -148
    )

    addCheckbox(
        "Automatically open trade",
        "autoOpenTrade",
        330,
        -171,
        "Attempts to open a trade with the assigned winner automatically."
    )

    addCheckbox(
        "Automatically place item in trade",
        "autoFillTrade",
        330,
        -199,
        "Places the correct temporarily tradeable bag item into an addon-initiated trade."
    )

    addCheckbox(
        "Announce completed trades",
        "announceCompletedTrades",
        330,
        -227,
        "Sends completed-trade messages to raid or party chat. When disabled, the message is local only."
    )

    --------------------------------------------------
    -- Right column: Interface
    --------------------------------------------------

    createSectionTitle(
        panel,
        "Interface",
        330,
        -263
    )

    addCheckbox(
        "Show minimap button",
        "showMinimapButton",
        330,
        -286,
        "Shows the movable minimap button. Slash commands remain available while it is hidden.",
        function()
            if AL.MinimapButton
                and AL.MinimapButton
                    .RefreshVisibility
            then
                AL.MinimapButton:
                    RefreshVisibility()
            end
        end
    )

    addCheckbox(
        "Show player roll window in parties",
        "showPlayerRollWindowInParty",
        330,
        -314,
        "Allows the compact Roll / OS / Pass window in normal parties. The window is always enabled in raids and never shown while solo.",
        function()
            if AL.PlayerRollUI then
                AL.PlayerRollUI:
                    RefreshGroupVisibility()
            end
        end
    )

    addCheckbox(
        "Close Loot and Settings with ESC",
        "closeWindowsWithEscape",
        330,
        -342,
        "Allows the ESC key to close the main Loot and Settings windows.",
        function()
            if AL.UI
                and AL.UI
                    .RefreshEscapeCloseRegistration
            then
                AL.UI:
                    RefreshEscapeCloseRegistration()
            end
        end
    )

    --------------------------------------------------
    -- Roll duration
    --------------------------------------------------

    local durationLabel =
        panel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontNormal"
        )

    durationLabel:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        335,
        -376
    )

    durationLabel:SetText(
        "Roll duration:"
    )

    local duration =
        CreateFrame(
            "EditBox",
            nil,
            panel,
            "InputBoxTemplate"
        )

    duration:SetWidth(50)
    duration:SetHeight(24)

    duration:SetPoint(
        "LEFT",
        durationLabel,
        "RIGHT",
        12,
        0
    )

    duration:SetAutoFocus(false)
    duration:SetNumeric(true)
    duration:SetMaxLetters(2)

    duration:SetScript(
        "OnEnterPressed",
        function(self)
            local value =
                tonumber(
                    self:GetText()
                ) or 30

            value =
                math.max(
                    3,
                    math.min(
                        60,
                        value
                    )
                )

            AL.db.settings.rollDuration =
                value

            self:SetText(value)
            self:ClearFocus()
        end
    )

    duration:SetScript(
        "OnEditFocusLost",
        function(self)
            local value =
                tonumber(
                    self:GetText()
                ) or 30

            value =
                math.max(
                    3,
                    math.min(
                        60,
                        value
                    )
                )

            AL.db.settings.rollDuration =
                value

            self:SetText(value)
        end
    )

    duration:SetScript(
        "OnEscapePressed",
        function(self)
            self:SetText(
                tostring(
                    AL.db.settings
                        .rollDuration
                        or 30
                )
            )

            self:ClearFocus()
        end
    )

    panel.duration =
        duration

    local durationSuffix =
        panel:CreateFontString(
            nil,
            "OVERLAY",
            "GameFontHighlight"
        )

    durationSuffix:SetPoint(
        "LEFT",
        duration,
        "RIGHT",
        7,
        0
    )

    durationSuffix:SetText(
        "seconds"
    )

    --------------------------------------------------
    -- Utility buttons
    --------------------------------------------------

    local demo =
        createButton(
            panel,
            "Load UI demo",
            125,
            26
        )

    demo:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        20,
        -414
    )

    demo:SetScript(
        "OnClick",
        function()
            AL.Loot:LoadDemo()
        end
    )

    local clearDemo =
    createButton(
        panel,
        "Clear UI demo",
        125,
        26
    )

    clearDemo:SetPoint(
        "TOPLEFT",
        demo,
        "BOTTOMLEFT",
        10,
        0
    )

    clearDemo:SetScript(
        "OnClick",
        function()
            if AL.Loot
                and AL.Loot.ClearDemo
            then
                AL.Loot:ClearDemo()
            end
        end
    )

    local resetLoot =
        createButton(
            panel,
            "Reset loot window",
            145,
            26
        )

    resetLoot:SetPoint(
        "LEFT",
        clearDemo,
        "RIGHT",
        10,
        0
    )

    resetLoot:SetScript(
        "OnClick",
        function()
            local settings =
                AL.db.windows.loot

            settings.point = "CENTER"
            settings.relativePoint = "CENTER"
            settings.x = -250
            settings.y = 0
            settings.width = 700
            settings.height = 560
            settings.scale = 1

            UI.lootFrame:SetScale(1)
            UI.lootFrame:SetWidth(700)
            UI.lootFrame:SetHeight(560)

            UI.lootFrame:
                ClearAllPoints()

            UI.lootFrame:SetPoint(
                "CENTER",
                UIParent,
                "CENTER",
                -250,
                0
            )

            UI:UpdateDynamicWidths()
        end
    )

    local resetSettings =
        createButton(
            panel,
            "Reset Settings Window",
            160,
            26
        )

    resetSettings:SetPoint(
        "LEFT",
        resetLoot,
        "RIGHT",
        10,
        0
    )

    resetSettings:SetScript(
        "OnClick",
        function()
            local settings =
                AL.db.windows.settings

            settings.point = "CENTER"
            settings.relativePoint = "CENTER"
            settings.x = 250
            settings.y = 0
            settings.width = 700
            settings.height = 560
            settings.scale = 1

            UI.settingsFrame:SetScale(1)
            UI.settingsFrame:SetWidth(700)
            UI.settingsFrame:SetHeight(560)

            UI.settingsFrame:
                ClearAllPoints()

            UI.settingsFrame:SetPoint(
                "CENTER",
                UIParent,
                "CENTER",
                250,
                0
            )

            UI:UpdateDynamicWidths()
        end
    )
end

function UI:RefreshSettings()
    local panel =
        self.panels
        and self.panels.settings

    if not panel then
        return
    end

    for _, checkbox in ipairs(
        panel.checkboxes or {}
    ) do
        local enabled =
            AL.db.settings[
                checkbox.settingKey
            ]

        checkbox:SetChecked(
            enabled
            and true
            or false
        )

        checkbox.text:SetTextColor(
            1,
            0.82,
            0
        )
    end

    panel.duration:SetText(
        tostring(
            AL.db.settings.rollDuration
                or 30
        )
    )

    --------------------------------------------------
    -- Dependent Master Loot option
    --------------------------------------------------

    local autoConfirm =
        panel.checkboxByKey
        and panel.checkboxByKey[
            "autoConfirmMasterLootToSelf"
        ]

    if autoConfirm then
        if AL.db.settings
            .autoMasterLootToSelf
        then
            autoConfirm:Enable()

            autoConfirm.text:SetTextColor(
                1,
                0.82,
                0
            )
        else
            autoConfirm:Disable()
            autoConfirm:SetChecked(false)

            autoConfirm.text:SetTextColor(
                0.5,
                0.5,
                0.5
            )
        end
    end
end

function UI:ShowSettingsTab(tabName)
    if not self.settingsFrame then
        return
    end

    if not self.panels[tabName] then
        tabName = "settings"
    end

    for name, panel in pairs(self.panels) do
        if name == tabName then
            panel:Show()
        else
            panel:Hide()
        end
    end

    for name, tab in pairs(self.tabs) do
        if name == tabName then
            tab:Disable()
        else
            tab:Enable()
        end
    end

    self.currentSettingsTab = tabName

    self:UpdateDynamicWidths()
    self:RefreshAll()
end

function UI:ShowLoot()
    self:Create()
    self.lootFrame:Show()
    self:UpdateDynamicWidths()
    self:RefreshLoot()
    self:RefreshRoll()
end

function UI:ShowSettings(tabName)
    self:Create()

    self:ShowSettingsTab(
        tabName or self.currentSettingsTab or "settings"
    )

    self.settingsFrame:Show()
    self:UpdateDynamicWidths()
    self:RefreshAll()
end

function UI:ToggleLoot()
    self:Create()

    if self.lootFrame:IsShown() then
        self.lootFrame:Hide()
    else
        self:ShowLoot()
    end
end

function UI:ToggleSettings(
    tabName
)
    self:Create()

    if self.settingsFrame:IsShown() then
        self.settingsFrame:Hide()
    else
        self:ShowSettings(
            tabName
        )
    end
end

-- Compatibility with the current Events.lua until point 10 is completed.
function UI:Show(tabName)
    if tabName == "loot" then
        self:ShowLoot()
    else
        self:ShowSettings(tabName)
    end
end

-- /al currently calls UI:Toggle(), so make that toggle the loot window.
function UI:Toggle()
    self:ToggleLoot()
end

function UI:RefreshAll()
    if not self.created then
        return
    end

    self:UpdateDynamicWidths()
    self:RefreshLoot()
    self:RefreshReserves()
    self:RefreshHistory()
    self:RefreshSettings()
end