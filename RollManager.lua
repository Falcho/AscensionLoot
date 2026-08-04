local AL = AscensionLoot

AL.Roll = AL.Roll or {}
local Roll = AL.Roll

Roll.active = nil

local function buildLocalizedRollPattern()
    local format = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    local captures = 0
    local pattern = "^"
    local index = 1

    while index <= #format do
        local two = format:sub(index, index + 1)
        local char = format:sub(index, index)
        if two == "%s" then
            captures = captures + 1
            pattern = pattern .. "(.+)"
            index = index + 2
        elseif two == "%d" then
            captures = captures + 1
            pattern = pattern .. "(%d+)"
            index = index + 2
        else
            if char:match("[%^%$%(%)%%%.%[%]%*%+%-%?]") then
                pattern = pattern .. "%" .. char
            else
                pattern = pattern .. char
            end
            index = index + 1
        end
    end

    return pattern .. "$", captures
end

local localizedPattern = buildLocalizedRollPattern()

local function parseRollMessage(message)
    local player, roll, minimum, maximum = message:match(localizedPattern)
    if player and roll and minimum and maximum then
        return player, tonumber(roll), tonumber(minimum), tonumber(maximum)
    end

    player, roll, minimum, maximum = message:match("^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")
    if player then return player, tonumber(roll), tonumber(minimum), tonumber(maximum) end
    return nil
end

local function sortedResults(active)
    local results = {}
    for normalized, entry in pairs(active.eligible or {}) do
        local best
        for _, value in ipairs(entry.rolls or {}) do
            if not best or value > best then best = value end
        end
        if best then
            table.insert(results, {
                normalizedName = normalized,
                name = entry.name,
                roll = best,
                rolls = entry.rolls,
            })
        end
    end
    table.sort(results, function(left, right)
        if left.roll == right.roll then return string.lower(left.name) < string.lower(right.name) end
        return left.roll > right.roll
    end)
    return results
end

function Roll:BuildEligibleFromReserves(itemID)
    local eligible = {}
    for _, reserver in ipairs(AL.SoftReserve:GetReservers(itemID)) do
        local maxRolls = 1
        if AL.db.settings.duplicateReservesGiveExtraRolls then
            maxRolls = math.max(1, reserver.count or 1)
        end
        eligible[reserver.normalizedName] = {
            name = reserver.name,
            maxRolls = maxRolls,
            rolls = {},
            reserveCount = reserver.count or 1,
        }
    end
    return eligible
end

function Roll:BuildOpenEligible()
    return {}
end

function Roll:StartForItem(item)
    item.key = item.key or AL:GetItemKey(item)
    if not item then return end
    local reservers = AL.SoftReserve:GetReservers(item.id)

    if #reservers == 1 then
        local reserver = reservers[1]
        self.active = {
            item = item,
            rollType = "SR",
            label = "Soft Reserve",
            state = "ready",
            eligible = self:BuildEligibleFromReserves(item.id),
            proposedWinner = reserver.name,
            startedAt = GetTime(),
            message = "Sole soft reserver",
        }
        AL:Announce(string.format("%s is soft reserved by %s.", item.link or item.name, reserver.name))
        AL:Print("Winner proposed: " .. reserver.name .. ". Use Award or Shift+Alt-click to confirm.")
        if AL.UI then AL.UI:RefreshAll() end
        return
    end

    if #reservers > 1 then
        self:Start(item, "SR", self:BuildEligibleFromReserves(item.id))
    else
        self:Start(item, "MS", self:BuildOpenEligible())
    end
end

function Roll:Start(item, rollType, eligible, labelOverride)
    item.key = item.key or AL:GetItemKey(item)
    if not item then return end
    local labels = { SR = "Soft Reserve", MS = "Main Spec", OS = "Off Spec", TIE = "Tie" }
    local label = labelOverride or labels[rollType] or rollType
    local duration = tonumber(AL.db.settings.rollDuration) or 12

    self.active = {
        item = item,
        rollType = rollType,
        label = label,
        state = "rolling",
        eligible = eligible or {},
        startedAt = GetTime(),
        endsAt = GetTime() + duration,
        duration = duration,
        proposedWinner = nil,
        message = nil,
    }

    local instruction = "/roll 100"
    if rollType == "OS" then instruction = "/roll 99" end

    if rollType == "SR" then
        local names = {}
        for _, entry in pairs(self.active.eligible) do
            local suffix = entry.maxRolls > 1 and (" x" .. entry.maxRolls) or ""
            table.insert(names, entry.name .. suffix)
        end
        table.sort(names)
        AL:Announce(string.format("%s roll for %s. Eligible: %s. %s", label, item.link or item.name, table.concat(names, ", "), instruction))
    else
        AL:Announce(string.format("%s roll for %s. %s", label, item.link or item.name, instruction))
    end

    if AL.UI then AL.UI:RefreshAll() end
end

function Roll:StartOffSpec(item)
    self:Start(item, "OS", self:BuildOpenEligible())
end

function Roll:IsEligible(playerName)
    local active = self.active
    if not active then return false end
    local normalized = AL:NormalizeName(playerName)

    if active.rollType == "SR" or active.rollType == "TIE" then
        return active.eligible[normalized] ~= nil
    end

    return AL:IsGroupMember(playerName)
end

function Roll:GetOrCreateOpenEntry(playerName)
    local active = self.active
    local normalized = AL:NormalizeName(playerName)
    if not active.eligible[normalized] then
        active.eligible[normalized] = {
            name = playerName,
            maxRolls = 1,
            rolls = {},
        }
    end
    return active.eligible[normalized]
end

function Roll:HandleSystemMessage(message)
    local active = self.active
    if not active or active.state ~= "rolling" then return end

    local playerName, value, minimum, maximum = parseRollMessage(message or "")
    if not playerName then return end
    if not self:IsEligible(playerName) then return end

    local expectedMaximum = active.rollType == "OS" and 99 or 100
    if minimum ~= 1 or maximum ~= expectedMaximum then return end

    local normalized = AL:NormalizeName(playerName)
    local entry = active.eligible[normalized] or self:GetOrCreateOpenEntry(playerName)
    if #entry.rolls >= (entry.maxRolls or 1) then
        AL:Print(playerName .. " has already used all allowed rolls.", 1, 0.4, 0.2)
        return
    end

    table.insert(entry.rolls, value)
    active.message = string.format("%s rolled %d", playerName, value)
    if AL.UI then AL.UI:RefreshRoll() end
end

function Roll:Finish()
    local active = self.active
    if not active or active.state ~= "rolling" then return end

    local results = sortedResults(active)
    if #results == 0 then
        active.state = "finished"
        active.message = "No valid rolls"
        active.proposedWinner = nil
        AL:Announce(string.format("No valid rolls for %s.", active.item.link or active.item.name))
        if AL.UI then AL.UI:RefreshAll() end
        return
    end

    local topRoll = results[1].roll
    local tied = {}
    for _, result in ipairs(results) do
        if result.roll == topRoll then table.insert(tied, result) end
    end

    if #tied > 1 then
        local tieEligible = {}
        local names = {}
        for _, result in ipairs(tied) do
            tieEligible[result.normalizedName] = {
                name = result.name,
                maxRolls = 1,
                rolls = {},
            }
            table.insert(names, result.name)
        end
        local item = active.item
        AL:Announce(string.format("Tie on %d between %s. Reroll /roll 100.", topRoll, table.concat(names, ", ")))
        self:Start(item, "TIE", tieEligible, "Tie")
        return
    end

    active.state = "finished"
    active.results = results
    active.proposedWinner = results[1].name
    active.winningRoll = results[1].roll
    active.message = string.format("Winner: %s (%d)", results[1].name, results[1].roll)
    AL:Announce(string.format("%s wins %s with %d.", results[1].name, active.item.link or active.item.name, results[1].roll))
    if AL.UI then AL.UI:RefreshAll() end
end

function Roll:Cancel()
    if self.active then
        AL:Print("Roll cancelled for " .. tostring(self.active.item.link or self.active.item.name) .. ".")
    end
    self.active = nil
    if AL.UI then AL.UI:RefreshAll() end
end

function Roll:GetWinner()
    return self.active and self.active.proposedWinner or nil
end

function Roll:SelectWinner(name)
    if not self.active or not name then return end
    self.active.proposedWinner = name
    self.active.message = "Selected: " .. name
    if AL.UI then AL.UI:RefreshAll() end
end

function Roll:OnUpdate()
    if self.active and self.active.state == "rolling" and GetTime() >= self.active.endsAt then
        self:Finish()
    elseif self.active and self.active.state == "rolling" and AL.UI then
        AL.UI:RefreshRollTimer()
    end
end

function Roll:GetSortedResults()
    if not self.active then return {} end
    return sortedResults(self.active)
end
