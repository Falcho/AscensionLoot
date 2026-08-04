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

local function createCheckbox(parent, label, settingKey, y)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    checkbox:SetWidth(26)
    checkbox:SetHeight(26)
    checkbox.text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkbox.text:SetPoint("LEFT", checkbox, "RIGHT", 3, 0)
    checkbox.text:SetText(label)
    checkbox:SetScript("OnClick", function(self)
        AL.db.settings[settingKey] = self:GetChecked() and true or false
    end)
    checkbox.settingKey = settingKey
    return checkbox
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
        560,
        420
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

    rollPanel.finish = createButton(rollPanel, "Finish", 75, 22)
    rollPanel.finish:SetPoint("BOTTOMLEFT", rollPanel, "BOTTOMLEFT", 12, 10)
    rollPanel.finish:SetScript("OnClick", function() AL.Roll:Finish() end)

    rollPanel.cancel = createButton(rollPanel, "Cancel", 75, 22)
    rollPanel.cancel:SetPoint("LEFT", rollPanel.finish, "RIGHT", 8, 0)
    rollPanel.cancel:SetScript("OnClick", function() AL.Roll:Cancel() end)

    rollPanel.award = createButton(rollPanel, "Award Winners", 115, 22)
    rollPanel.award:SetPoint("LEFT", rollPanel.cancel, "RIGHT", 8, 0)
    rollPanel.award:SetScript("OnClick", function() if AL.Roll.active then
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

    row.roll = createButton(row, "Roll", 48, 18)
    row.roll:SetPoint("TOPRIGHT", row, "TOPRIGHT", -166, 0)
    row.roll:SetScript("OnClick", function() if row.item then AL.Roll:StartForItem(row.item) end end)

    row.award = createButton(row, "Award", 50, 18)
    row.award:SetPoint("LEFT", row.roll, "RIGHT", 4, 0)
    row.award:SetScript("OnClick", function()
            if not row.item then
                return
            end

            local active = AL.Roll.active

            if active
                and active.state == "finished"
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
        end
    )

    row.trade = createButton(row, "Trade", 50, 18)
    row.trade:SetPoint("LEFT", row.award, "RIGHT", 4, 0)
    row.trade:SetScript("OnClick", function()
        if not row.item then
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

        AL.Trade:TryStart(row.item)
    end)

    row.skip = createButton(row, "Skip", 44, 18)
    row.skip:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -39)
    row.skip:SetScript("OnClick", function()
        if row.item then row.item.skipped = true UI:RefreshLoot() end
    end)

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
        for _, item in ipairs(AL.LootSession:GetItems() or {}) do
            if not item.skipped then
                table.insert(visibleItems, item)
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
        for itemID, item in pairs(player.items) do
            local itemName, itemLink = GetItemInfo(itemID)
            local label = itemLink or itemName or ("Item #" .. itemID)
            if item.count > 1 then label = label .. " x" .. item.count end
            table.insert(items, { id = itemID, text = label })
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
    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    help:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -5)
    help:SetText("Paste BisBeard's RollFor export below, then click Import.")

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -32)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 80)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(610)
    edit:SetHeight(340)
    edit:SetTextInsets(8, 8, 8, 8)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self)
        local height = math.max(340, self:GetStringHeight() + 30)
        self:SetHeight(height)
    end)
    scroll:SetScrollChild(edit)
    panel.edit = edit

    panel.import = createButton(panel, "Import", 100, 25)
    panel.import:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 5, 40)
    panel.import:SetScript("OnClick", function()
        local success, message = AL.SoftReserve:Import(panel.edit:GetText())
        panel.status:SetText(message or "")
        if success then AL:Print(message) else AL:Print(message, 1, 0.3, 0.3) end
    end)

    panel.clear = createButton(panel, "Clear Data", 100, 25)
    panel.clear:SetPoint("LEFT", panel.import, "RIGHT", 10, 0)
    panel.clear:SetScript("OnClick", function()
        AL.SoftReserve:Clear()
        panel.status:SetText("Soft-reserve data cleared.")
    end)

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 5, 8)
    panel.status:SetPoint("RIGHT", panel, "RIGHT", -5, 0)
    panel.status:SetJustifyH("LEFT")
end

function UI:CreateHistoryPanel(panel)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(620)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    panel.child = child
    panel.lines = {}
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
    panel.checkboxes = {
        createCheckbox(panel, "Announce rolls in raid/party chat", "announceRolls", -10),
        createCheckbox(panel, "Confirm before awarding loot", "confirmAwards", -45),
        createCheckbox(panel, "Duplicate reserves grant extra rolls", "duplicateReservesGiveExtraRolls", -80),
        createCheckbox(panel, "Automatically loot coin slots", "autoLootCoins", -115),
        createCheckbox(panel, "Automatically loot poor-quality items", "autoLootPoor", -150),
        createCheckbox(panel, "Automatically loot common-quality items", "autoLootCommon", -185),
        createCheckbox(panel, "Never auto-loot reserved items", "protectReservedItems", -220),
        createCheckbox(panel, "Open this frame when loot opens", "autoShowLoot", -255),
    }

    local durationLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    durationLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -305)
    durationLabel:SetText("Roll duration (seconds):")

    local duration = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    duration:SetWidth(55)
    duration:SetHeight(24)
    duration:SetPoint("LEFT", durationLabel, "RIGHT", 12, 0)
    duration:SetAutoFocus(false)
    duration:SetNumeric(true)
    duration:SetMaxLetters(2)
    duration:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText()) or 12
        value = math.max(3, math.min(60, value))
        AL.db.settings.rollDuration = value
        self:SetText(value)
        self:ClearFocus()
    end)
    duration:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.duration = duration

    local demo = createButton(panel, "Load UI Demo", 130, 26)
    demo:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -355)
    demo:SetScript("OnClick", function() AL.Loot:LoadDemo() end)

    local resetLoot = createButton(
        panel,
        "Reset Loot Window",
        145,
        26
    )

    resetLoot:SetPoint(
        "LEFT",
        demo,
        "RIGHT",
        10,
        0
    )

    resetLoot:SetScript("OnClick", function()
        local settings = AL.db.windows.loot

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
        UI.lootFrame:ClearAllPoints()
        UI.lootFrame:SetPoint(
            "CENTER",
            UIParent,
            "CENTER",
            -250,
            0
        )

        UI:UpdateDynamicWidths()
    end)

    local resetSettings = createButton(
        panel,
        "Reset Settings Window",
        155,
        26
    )

    resetSettings:SetPoint(
        "TOPLEFT",
        demo,
        "BOTTOMLEFT",
        0,
        -12
    )

    resetSettings:SetScript("OnClick", function()
        local settings = AL.db.windows.settings

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
        UI.settingsFrame:ClearAllPoints()
        UI.settingsFrame:SetPoint(
            "CENTER",
            UIParent,
            "CENTER",
            250,
            0
        )

        UI:UpdateDynamicWidths()
    end)
end

function UI:RefreshSettings()
    local panel = self.panels and self.panels.settings
    if not panel then return end
    for _, checkbox in ipairs(panel.checkboxes) do
        checkbox:SetChecked(AL.db.settings[checkbox.settingKey] and true or false)
    end
    panel.duration:SetText(tostring(AL.db.settings.rollDuration or 12))
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

function UI:ToggleSettings()
    self:Create()

    if self.settingsFrame:IsShown() then
        self.settingsFrame:Hide()
    else
        self:ShowSettings()
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