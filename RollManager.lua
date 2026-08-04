local AL = AscensionLoot

AL.Roll = AL.Roll or {}
local Roll = AL.Roll

Roll.active = nil

local CATEGORY_PRIORITY = {
    SR = 1,
    MS = 2,
    OS = 3,
}

local CATEGORY_LABELS = {
    SR = "Soft Reserve",
    MS = "Main Spec",
    OS = "Off Spec",
}

local function buildLocalizedRollPattern()
    local format =
        RANDOM_ROLL_RESULT
        or "%s rolls %d (%d-%d)"

    local pattern = "^"
    local index = 1

    while index <= #format do
        local two = format:sub(index, index + 1)
        local character = format:sub(index, index)

        if two == "%s" then
            pattern = pattern .. "(.+)"
            index = index + 2

        elseif two == "%d" then
            pattern = pattern .. "(%d+)"
            index = index + 2

        else
            if character:match(
                "[%^%$%(%)%%%.%[%]%*%+%-%?]"
            ) then
                pattern = pattern .. "%" .. character
            else
                pattern = pattern .. character
            end

            index = index + 1
        end
    end

    return pattern .. "$"
end

local localizedRollPattern =
    buildLocalizedRollPattern()

local function parseRollMessage(message)
    if type(message) ~= "string" then
        return nil
    end

    local player, roll, minimum, maximum =
        message:match(localizedRollPattern)

    if player and roll and minimum and maximum then
        return player,
            tonumber(roll),
            tonumber(minimum),
            tonumber(maximum)
    end

    player, roll, minimum, maximum =
        message:match(
            "^(.+) rolls (%d+) %((%d+)%-(%d+)%)$"
        )

    if player then
        return player,
            tonumber(roll),
            tonumber(minimum),
            tonumber(maximum)
    end

    return nil
end

local function getBestRoll(rolls)
    local best = nil

    for _, value in ipairs(rolls or {}) do
        if not best or value > best then
            best = value
        end
    end

    return best
end

local function sameTieValue(left, right)
    if not left or not right then
        return false
    end

    return left.category == right.category
        and left.roll == right.roll
        and left.tieRoll == right.tieRoll
end

function Roll:GetAvailableCopyCount(item)
    if not item then
        return 1
    end

    if AL.LootSession
        and AL.LootSession.GetUnassignedCopies
    then
        local copies =
            AL.LootSession:GetUnassignedCopies(
                item.id,
                UnitName("player")
            )

        if #copies > 0 then
            return #copies
        end
    end

    return math.max(
        1,
        tonumber(item.quantity) or 1
    )
end

function Roll:BuildReserveMap(itemID)
    local result = {}

    for _, reserver in ipairs(
        AL.SoftReserve:GetReservers(itemID)
    ) do
        result[reserver.normalizedName] = reserver
    end

    return result
end

function Roll:ClassifyRoll(
    playerName,
    minimum,
    maximum
)
    if minimum ~= 1 then
        return nil
    end

    if maximum == 99 then
        return "OS"
    end

    if maximum ~= 100 then
        return nil
    end

    local active = self.active

    if not active then
        return nil
    end

    local normalized =
        AL:NormalizeName(playerName)

    if active.reserveMap[normalized] then
        return "SR"
    end

    return "MS"
end

function Roll:GetOrCreateEntry(
    playerName,
    category
)
    local active = self.active
    local normalized =
        AL:NormalizeName(playerName)

    active.rollsByPlayer[normalized] =
        active.rollsByPlayer[normalized] or {}

    local playerEntries =
        active.rollsByPlayer[normalized]

    if not playerEntries[category] then
        local maxRolls = 1
        local reserveCount = 0

        if category == "SR" then
            local reserver =
                active.reserveMap[normalized]

            reserveCount =
                reserver
                and tonumber(reserver.count)
                or 1

            if AL.db.settings
                .duplicateReservesGiveExtraRolls
            then
                maxRolls =
                    math.max(1, reserveCount)
            end
        end

        playerEntries[category] = {
            name = playerName,
            normalizedName = normalized,
            category = category,
            priority =
                CATEGORY_PRIORITY[category],
            rolls = {},
            maxRolls = maxRolls,
            reserveCount = reserveCount,
            tieRoll = nil,
        }
    end

    return playerEntries[category]
end

function Roll:GetSortedResults()
    local active = self.active

    if not active then
        return {}
    end

    local results = {}

    for normalizedName, playerEntries in pairs(active.rollsByPlayer or {}) do
        local selectedEntry = nil

        for _, category in ipairs({
            "SR",
            "MS",
            "OS",
        }) do
            local entry = playerEntries[category]

            if entry and getBestRoll(entry.rolls) then
                selectedEntry = entry
                break
            end
        end

        if selectedEntry then
            table.insert(results, {
                normalizedName = normalizedName,
                name = selectedEntry.name,
                category = selectedEntry.category,

                categoryLabel =
                    CATEGORY_LABELS[selectedEntry.category],

                priority = selectedEntry.priority,

                roll =
                    getBestRoll(selectedEntry.rolls),

                rolls = selectedEntry.rolls,
                tieRoll = selectedEntry.tieRoll,
                entry = selectedEntry,
            })
        end
    end

    table.sort(results, function(left, right)
        if left.priority ~= right.priority then
            return left.priority < right.priority
        end

        if left.roll ~= right.roll then
            return left.roll > right.roll
        end

        local leftTie = left.tieRoll or -1
        local rightTie = right.tieRoll or -1

        if leftTie ~= rightTie then
            return leftTie > rightTie
        end

        return string.lower(left.name)
            < string.lower(right.name)
    end)

    return results
end

function Roll:BuildWinners(results)
    local active = self.active
    local winners = {}
    local copyCount =
        tonumber(active.copyCount) or 1

    for _, result in ipairs(results) do
        if #winners >= copyCount then
            break
        end

        table.insert(winners, result)
    end

    return winners
end

function Roll:FindBoundaryTie(
    results,
    winners
)
    if #winners == 0 then
        return nil
    end

    if #winners >= #results then
        return nil
    end

    local boundary = winners[#winners]
    local firstExcluded =
        results[#winners + 1]

    if not sameTieValue(
        boundary,
        firstExcluded
    ) then
        return nil
    end

    local tied = {}

    for _, result in ipairs(results) do
        if sameTieValue(result, boundary) then
            table.insert(tied, result)
        end
    end

    return tied
end

function Roll:BeginTie(tiedResults)
    local active = self.active

    if not active or not tiedResults or #tiedResults < 2 then
        return
    end

    local category = tiedResults[1].category
    local expectedMaximum

    if category == "OS" then
        expectedMaximum = 99
    else
        expectedMaximum = 100
    end

    local candidateEntries = {}
    local names = {}

    for _, result in ipairs(tiedResults) do
        result.entry.tieRoll = nil

        candidateEntries[result.normalizedName] =
            result.entry

        table.insert(names, result.name)
    end

    table.sort(names)

    local duration =
        tonumber(AL.db.settings.rollDuration) or 12

    active.state = "tie"

    active.tie = {
        category = category,
        expectedMaximum = expectedMaximum,
        candidates = candidateEntries,
    }

    active.endsAt = GetTime() + duration

    active.message =
        "Tie between " .. table.concat(names, ", ")

    AL:Announce(string.format(
        "Tie between %s for %s. Reroll /roll %d.",
        table.concat(names, ", "),
        active.item.link or active.item.name,
        expectedMaximum
    ))

    if AL.UI then
        AL.UI:RefreshAll()
    end
end

function Roll:StartForItem(item)
    if not item then
        return
    end

    item.key =
        item.key or AL:GetItemKey(item)

    local duration =
        tonumber(
            AL.db.settings.rollDuration
        ) or 12

    local copyCount =
        self:GetAvailableCopyCount(item)

    self.active = {
        item = item,
        label = "Combined Roll",
        state = "rolling",
        copyCount = copyCount,

        reserveMap =
            self:BuildReserveMap(item.id),

        rollsByPlayer = {},

        startedAt = GetTime(),
        endsAt = GetTime() + duration,
        duration = duration,

        proposedWinner = nil,
        proposedWinners = {},
        results = {},
        tie = nil,
        message = "Waiting for rolls...",
    }

    AL:Announce(string.format(
        "Roll for %s — %d %s available. "
            .. "SR/MS: /roll 100. "
            .. "OS: /roll 99. "
            .. "Priority: SR > MS > OS.",
        item.link or item.name,
        copyCount,
        copyCount == 1 and "copy"
            or "copies"
    ))

    if AL.UI then
        AL.UI:RefreshAll()
    end
end

-- Kept so older UI code does not error.
-- The OS button should be removed or hidden.
function Roll:StartOffSpec(item)
    self:StartForItem(item)
end

function Roll:HandleTieRoll(
    playerName,
    value,
    minimum,
    maximum
)
    local active = self.active
    local tie = active and active.tie

    if not tie then
        return
    end

    if minimum ~= 1
        or maximum
            ~= tie.expectedMaximum
    then
        return
    end

    local normalized =
        AL:NormalizeName(playerName)

    local entry =
        tie.candidates[normalized]

    if not entry then
        return
    end

    if entry.tieRoll then
        AL:Print(
            playerName
                .. " has already submitted a tie-break roll.",
            1,
            0.4,
            0.2
        )

        return
    end

    entry.tieRoll = value

    active.message =
        string.format(
            "%s tie-break rolled %d",
            playerName,
            value
        )

    if AL.UI then
        AL.UI:RefreshRoll()
    end
end

function Roll:HandleSystemMessage(message)
    if type(message) ~= "string" then
        return
    end
    local active = self.active

    if not active then
        return
    end

    if active.state ~= "rolling"
        and active.state ~= "tie"
    then
        return
    end

    local playerName,
        value,
        minimum,
        maximum =
        parseRollMessage(message or "")

    if not playerName then
        return
    end

    if not AL:IsGroupMember(playerName) then
        return
    end

    if active.state == "tie" then
        self:HandleTieRoll(
            playerName,
            value,
            minimum,
            maximum
        )

        return
    end

    local category =
        self:ClassifyRoll(
            playerName,
            minimum,
            maximum
        )

    if not category then
        return
    end

    local entry =
        self:GetOrCreateEntry(
            playerName,
            category
        )

    if #entry.rolls
        >= (entry.maxRolls or 1)
    then
        AL:Print(
            playerName
                .. " has already used all allowed "
                .. category
                .. " rolls.",
            1,
            0.4,
            0.2
        )

        return
    end

    table.insert(entry.rolls, value)

    active.message = string.format(
        "%s rolled %d (%s)",
        playerName,
        value,
        category
    )

    if AL.UI then
        AL.UI:RefreshRoll()
    end
end

function Roll:Finish()
    local active = self.active

    if not active then
        return
    end

    if active.state ~= "rolling"
        and active.state ~= "tie"
    then
        return
    end

    local results =
        self:GetSortedResults()

    if #results == 0 then
        active.state = "finished"
        active.results = {}
        active.proposedWinner = nil
        active.proposedWinners = {}
        active.message = "No valid rolls"

        AL:Announce(string.format(
            "No valid rolls for %s.",
            active.item.link
                or active.item.name
        ))

        if AL.UI then
            AL.UI:RefreshAll()
        end

        return
    end

    local winners =
        self:BuildWinners(results)

    local tiedResults =
        self:FindBoundaryTie(
            results,
            winners
        )

    if tiedResults then
        self:BeginTie(tiedResults)
        return
    end

    active.state = "finished"
    active.tie = nil
    active.results = results
    active.proposedWinners = winners

    active.proposedWinner =
        winners[1]
        and winners[1].name
        or nil

    active.winningRoll =
        winners[1]
        and winners[1].roll
        or nil

    local winnerTexts = {}

    for _, winner in ipairs(winners) do
        local rollText =
            tostring(winner.roll)

        if winner.tieRoll then
            rollText =
                rollText
                .. ", tie "
                .. tostring(winner.tieRoll)
        end

        table.insert(
            winnerTexts,
            string.format(
                "%s (%s %s)",
                winner.name,
                winner.category,
                rollText
            )
        )
    end

    active.message = string.format(
        "%d winner%s selected",
        #winners,
        #winners == 1 and "" or "s"
    )

    AL:Announce(string.format(
        "%s winners: %s.",
        active.item.link
            or active.item.name,
        table.concat(winnerTexts, ", ")
    ))

    if AL.UI then
        AL.UI:RefreshAll()
    end
end

function Roll:Cancel()
    if self.active then
        AL:Print(
            "Roll cancelled for "
                .. tostring(
                    self.active.item.link
                    or self.active.item.name
                )
                .. "."
        )
    end

    self.active = nil

    if AL.UI then
        AL.UI:RefreshAll()
    end
end

function Roll:GetWinner()
    return self.active
        and self.active.proposedWinner
        or nil
end

function Roll:GetWinners()
    return self.active
        and self.active.proposedWinners
        or {}
end

function Roll:SelectWinner(name)
    if not self.active or not name then
        return
    end

    for _, result in ipairs(
        self:GetSortedResults()
    ) do
        if AL:NormalizeName(result.name)
            == AL:NormalizeName(name)
        then
            self.active.proposedWinners = {
                result,
            }

            self.active.proposedWinner =
                result.name

            self.active.message =
                "Selected: " .. result.name

            if AL.UI then
                AL.UI:RefreshAll()
            end

            return
        end
    end
end

function Roll:OnUpdate()
    local active = self.active

    if not active then
        return
    end

    if (
        active.state == "rolling"
        or active.state == "tie"
    )
        and GetTime() >= active.endsAt
    then
        self:Finish()

    elseif (
        active.state == "rolling"
        or active.state == "tie"
    )
        and AL.UI
    then
        AL.UI:RefreshRollTimer()
    end
end