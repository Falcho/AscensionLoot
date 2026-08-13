local AL = AscensionLoot

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("LOOT_CLOSED")
eventFrame:RegisterEvent("LOOT_SLOT_CLEARED")
eventFrame:RegisterEvent("LOOT_SLOT_CHANGED")
eventFrame:RegisterEvent("LOOT_BIND_CONFIRM")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("TRADE_SHOW")
eventFrame:RegisterEvent("TRADE_CLOSED")
eventFrame:RegisterEvent("UI_INFO_MESSAGE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName ~= "AscensionLoot" then return end
        AL:InitializeDatabase()
        AL.SoftReserve:LoadFromDatabase()
    elseif event == "PLAYER_LOGIN" then
        AL.UI:Create()

        if AL.RollSync then
            AL.RollSync:Initialize()
        end
        if AL.PlayerRollUI then
            AL.PlayerRollUI:Initialize()
        end
        if AL.BagHooks then
            AL.BagHooks:Initialize()
        end
        if AL.MinimapButton then
            AL.MinimapButton:Initialize()
        end

        AL:Print(
            "Loaded v"
                .. AL.version
                .. ". Type /al for the loot frame."
        )
    elseif event == "LOOT_OPENED" then
        local autoLoot =
            select(1, ...)

        AL.Loot:OnOpened(autoLoot)
    elseif event == "LOOT_CLOSED" then
        AL.Loot:OnClosed()
    elseif event == "LOOT_SLOT_CLEARED" then
        local slot = ...
        AL.Loot:OnSlotCleared(slot)
    elseif event == "LOOT_SLOT_CHANGED" then
        AL.Loot:Refresh()
    elseif event == "LOOT_BIND_CONFIRM" then
        local slot =
            select(1, ...)

        if AL.Loot then
            AL.Loot:OnBindConfirm(slot)
        end
    elseif event == "BAG_UPDATE" then
        if AL.BagHooks then
            AL.BagHooks:OnBagUpdate()
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local systemMessage = select(1, ...)

        if AL.Roll and type(systemMessage) == "string" then
            AL.Roll:HandleSystemMessage(systemMessage)
        end
            elseif event == "CHAT_MSG_ADDON" then
        local prefix,
            message,
            distribution,
            sender =
                ...

        if AL.RollSync then
            AL.RollSync:OnAddonMessage(
                prefix,
                message,
                distribution,
                sender
            )
        end
    elseif event == "UI_ERROR_MESSAGE" then
        local message = ...
        if AL.Loot.pendingAward then
            AL:Print(message or "The item could not be awarded.", 1, 0.3, 0.3)
            AL.Loot.pendingAward = nil
        end
    elseif event == "RAID_ROSTER_UPDATE"
        or event == "PARTY_MEMBERS_CHANGED"
    then
        if AL.UI then
            AL.UI:RefreshAll()
        end

        if AL.PlayerRollUI then
            AL.PlayerRollUI:
                RefreshGroupVisibility()
        end
    elseif event == "TRADE_SHOW" then
        if AL.Trade then
            AL.Trade:OnTradeShow()
        end
    elseif event == "TRADE_CLOSED" then
        if AL.Trade then
            AL.Trade:OnTradeClosed()
        end 
    elseif event == "UI_INFO_MESSAGE" then
        if AL.Trade then
            AL.Trade:OnUIInfoMessage(...)
        end    
    elseif event == "PLAYER_REGEN_ENABLED" then
        if AL.Trade then
            AL.Trade:OnCombatEnded()
        end
    end
end)

eventFrame:SetScript(
    "OnUpdate",
    function(self, elapsed)
        if AL.Roll then
            AL.Roll:OnUpdate(elapsed)
        end
        if AL.Loot then
            AL.Loot:OnUpdate()
        end
        if AL.BagHooks then
            AL.BagHooks:OnUpdate()
        end
        if AL.SoftReserve then
            AL.SoftReserve:OnUpdate()
        end
        if AL.Trade then
            AL.Trade:OnUpdate(elapsed)
        end
    end
)

local function showHelp()
    AL:Print("Commands:")
    AL:Print("/al — toggle the main frame")
    AL:Print("/al loot | reserves | import | history | settings")
    AL:Print("/al finish | cancel — control the active roll")
    AL:Print("/al trade — trade the next awarded item")
    AL:Print("/al clear — clear imported soft reserves")
    AL:Print("/al clearhistory — clear recorded loot history")
    AL:Print("/al demo — load a safe UI demo")
end

SLASH_ASCENSIONLOOT1 = "/al"
SLASH_ASCENSIONLOOT2 = "/ascloot"
SlashCmdList["ASCENSIONLOOT"] = function(message)
    local command = AL:NormalizeName(AL:Trim(message)) or ""
    if command == "" then
        AL.UI:Toggle()
    elseif command == "loot" or command == "reserves" or command == "import" or command == "history" or command == "settings" then
        AL.UI:Show(command)
    elseif command == "finish" then
        AL.Roll:Finish()
    elseif command == "cancel" then
        AL.Roll:Cancel()
    elseif command == "clear" then
        AL.SoftReserve:Clear()
        AL:Print("Soft-reserve data cleared.")
    elseif command == "demo" then
        AL.Loot:LoadDemo()
    elseif command == "trade" then
        if AL.Trade then
            AL.Trade:TryStart()
        end
    elseif command == "clearhistory" then
        if AL.UI then
            AL.UI:
                ShowClearHistoryConfirmation()
        end
    elseif command == "help" then
        showHelp()
    else
        showHelp()
    end
end
