local AL = AscensionLoot

AL.RollSync =
    AL.RollSync or {}

local Sync =
    AL.RollSync

--------------------------------------------------
-- Addon-message protocol
--------------------------------------------------

local PREFIX =
    "AscLootRoll"

local FIELD_SEPARATOR =
    "\031"

local MAX_MESSAGE_BYTES =
    240

--------------------------------------------------
-- Local state
--------------------------------------------------

Sync.initialized =
    false

Sync.remote =
    nil

Sync.rollCounter =
    0

-- Temporary testing aid.
-- Enable with:
--
-- /run AscensionLoot.RollSync.debugEnabled=true
--
Sync.debugEnabled =
    false

--------------------------------------------------
-- Helpers
--------------------------------------------------

local function cleanField(value)
    value =
        tostring(
            value or ""
        )

    return (
        value:gsub(
            FIELD_SEPARATOR,
            " "
        )
    )
end

local function buildMessage(...)
    local fields = {
        ...
    }

    for index = 1, #fields do
        fields[index] =
            cleanField(
                fields[index]
            )
    end

    return table.concat(
        fields,
        FIELD_SEPARATOR
    )
end

local function splitMessage(message)
    local result = {}

    local position = 1

    while true do
        local separatorStart =
            string.find(
                message,
                FIELD_SEPARATOR,
                position,
                true
            )

        if not separatorStart then
            table.insert(
                result,
                message:sub(position)
            )

            break
        end

        table.insert(
            result,
            message:sub(
                position,
                separatorStart - 1
            )
        )

        position =
            separatorStart
            + #FIELD_SEPARATOR
    end

    return result
end

local function samePlayer(
    left,
    right
)
    if not left
        or not right
    then
        return false
    end

    return AL:NormalizeName(left)
        == AL:NormalizeName(right)
end

--------------------------------------------------
-- Debugging
--------------------------------------------------

function Sync:Debug(message)
    if not self.debugEnabled then
        return
    end

    AL:Print(
        "[RollSync] "
        .. tostring(message)
    )
end

--------------------------------------------------
-- Initialisation
--------------------------------------------------

function Sync:Initialize()
    if self.initialized then
        return
    end

    self.initialized =
        true

    --------------------------------------------------
    -- WotLK uses RegisterAddonMessagePrefix.
    -- Some custom clients may not require it, so
    -- absence of the function is not fatal.
    --------------------------------------------------

    if RegisterAddonMessagePrefix then
        local success =
            RegisterAddonMessagePrefix(
                PREFIX
            )

        if success == false then
            AL:Print(
                "Could not register the roll-sync "
                .. "addon-message prefix.",
                1,
                0.3,
                0.3
            )
        end
    end
end

--------------------------------------------------
-- Roll IDs
--------------------------------------------------

function Sync:CreateRollID()
    self.rollCounter =
        (
            self.rollCounter
            or 0
        )
        + 1

    return string.format(
        "%d-%d",
        time(),
        self.rollCounter
    )
end

--------------------------------------------------
-- Sending
--------------------------------------------------

function Sync:Send(...)
    local channel =
        AL:GetGroupChannel()

    if not channel then
        return false
    end

    if not SendAddonMessage then
        return false
    end

    local message =
        buildMessage(...)

    if #message
        > MAX_MESSAGE_BYTES
    then
        self:Debug(
            "Message was too large and was not sent: "
            .. tostring(
                message:sub(1, 20)
            )
        )

        return false
    end

    local success,
        errorMessage =
            pcall(
                SendAddonMessage,
                PREFIX,
                message,
                channel
            )

    if not success then
        self:Debug(
            "SendAddonMessage failed: "
            .. tostring(
                errorMessage
            )
        )

        return false
    end

    return true
end

--------------------------------------------------
-- START
--------------------------------------------------

function Sync:BroadcastStart(active)
    if not active
        or not active.item
    then
        return
    end

    active.syncID =
        active.syncID
        or self:CreateRollID()

    active.syncSequence =
        0

    self:Send(
        "S",
        active.syncID,
        active.item.id or "",
        active.duration or 0,
        active.copyCount or 1,
        active.item.name or ""
    )

    --------------------------------------------------
    -- Send the link separately.
    --
    -- Item hyperlinks can be considerably longer than
    -- ordinary fields, so keeping them separate prevents
    -- the START packet from becoming too large.
    --------------------------------------------------

    if active.item.link
        and active.item.link ~= ""
    then
        self:Send(
            "L",
            active.syncID,
            active.item.link
        )
    end
end

--------------------------------------------------
-- Accepted ordinary roll
--------------------------------------------------

function Sync:BroadcastRoll(
    active,
    playerName,
    value,
    category,
    rollIndex
)
    if not active
        or not active.syncID
    then
        return
    end

    active.syncSequence =
        (
            active.syncSequence
            or 0
        )
        + 1

    self:Send(
        "R",
        active.syncID,
        active.syncSequence,
        playerName or "",
        value or 0,
        category or "",
        rollIndex or 1
    )
end

--------------------------------------------------
-- Tie begins
--------------------------------------------------

function Sync:BroadcastTie(
    active,
    expectedMaximum,
    duration
)
    if not active
        or not active.syncID
    then
        return
    end

    --------------------------------------------------
    -- First announce that the tie phase has begun.
    --------------------------------------------------

    self:Send(
        "T",
        active.syncID,
        duration or 0,
        expectedMaximum or 100
    )

    --------------------------------------------------
    -- Then send one small eligibility packet for each
    -- tied player.
    --
    -- Sending players separately avoids exceeding the
    -- addon-message size limit when several players tie.
    --------------------------------------------------

    local names = {}

    local candidates =
        active.tie
        and active.tie.candidates
        or {}

    for normalizedName,
        entry in pairs(
            candidates
        )
    do
        table.insert(
            names,
            entry.name
                or normalizedName
        )
    end

    table.sort(
        names
    )

    for _, playerName in ipairs(
        names
    ) do
        self:Send(
            "E",
            active.syncID,
            playerName
        )
    end
end

--------------------------------------------------
-- Accepted tie-break roll
--------------------------------------------------

function Sync:BroadcastTieRoll(
    active,
    playerName,
    value,
    maximum
)
    if not active
        or not active.syncID
    then
        return
    end

    active.syncSequence =
        (
            active.syncSequence
            or 0
        )
        + 1

    self:Send(
        "B",
        active.syncID,
        active.syncSequence,
        playerName or "",
        value or 0,
        maximum or 100
    )
end

--------------------------------------------------
-- Roll finished
--------------------------------------------------

function Sync:BroadcastFinish(active)
    if not active
        or not active.syncID
    then
        return
    end

    self:Send(
        "F",
        active.syncID
    )
end

--------------------------------------------------
-- Roll cancelled
--------------------------------------------------

function Sync:BroadcastCancel(active)
    if not active
        or not active.syncID
    then
        return
    end

    self:Send(
        "C",
        active.syncID
    )
end

--------------------------------------------------
-- Remote-state helpers
--------------------------------------------------

function Sync:IsCurrentRemoteRoll(
    rollID,
    sender
)
    local remote =
        self.remote

    if not remote then
        return false
    end

    if remote.id
        ~= rollID
    then
        return false
    end

    if not samePlayer(
        remote.authority,
        sender
    ) then
        return false
    end

    return true
end

function Sync:NotifyChanged()
    --------------------------------------------------
    -- PlayerRollUI does not exist yet.
    --
    -- We deliberately leave this hook here so the UI
    -- can be added without changing the protocol later.
    --------------------------------------------------

    if AL.PlayerRollUI
        and AL.PlayerRollUI
            .OnSyncChanged
    then
        AL.PlayerRollUI:
            OnSyncChanged(
                self.remote
            )
    end
end

--------------------------------------------------
-- Receiving
--------------------------------------------------

function Sync:OnAddonMessage(
    prefix,
    message,
    distribution,
    sender
)
    if prefix ~= PREFIX then
        return
    end

    if type(message)
        ~= "string"
    then
        return
    end

    if not sender
        or sender == ""
    then
        return
    end

    --------------------------------------------------
    -- Do not process our own broadcasts.
    --------------------------------------------------

    if samePlayer(
        sender,
        UnitName("player")
    ) then
        return
    end

    --------------------------------------------------
    -- Only accept synchronization from a current
    -- party/raid member.
    --------------------------------------------------

    if not AL:IsGroupMember(
        sender
    ) then
        return
    end

    local fields =
        splitMessage(
            message
        )

    local messageType =
        fields[1]

    --------------------------------------------------
    -- START
    --------------------------------------------------

    if messageType == "S" then
        local rollID =
            fields[2]

        local itemID =
            tonumber(
                fields[3]
            )

        local duration =
            tonumber(
                fields[4]
            ) or 0

        local copyCount =
            tonumber(
                fields[5]
            ) or 1

        local itemName =
            fields[6]

        if not rollID
            or rollID == ""
            or not itemID
        then
            return
        end

        --------------------------------------------------
        -- A raid member cannot create a legitimate
        -- synchronized roll unless they are leader
        -- or assistant.
        --------------------------------------------------

        if AL.IsRollAuthority
            and not AL:IsRollAuthority(
                sender
            )
        then
            self:Debug(
                "Rejected START from unauthorized "
                .. tostring(sender)
            )

            return
        end

        self.remote = {
            id =
                rollID,

            authority =
                sender,

            itemID =
                itemID,

            itemName =
                itemName,

            itemLink =
                nil,

            copyCount =
                copyCount,

            state =
                "rolling",

            duration =
                duration,

            receivedAt =
                GetTime(),

            endsAt =
                GetTime()
                + duration,

            expectedMaximum =
                nil,

            rolls =
                {},

            tieRolls =
                {},

            tieCandidates =
                {},


            seenSequences =
                {},
        }

        self:Debug(
            string.format(
                "START from %s: %s "
                .. "(item %d), %d sec, "
                .. "%d copies.",
                tostring(sender),
                tostring(
                    itemName
                ),
                itemID,
                duration,
                copyCount
            )
        )

        self:NotifyChanged()

        return
    end

    --------------------------------------------------
    -- Everything below requires an existing matching
    -- START packet from the same distributor.
    --------------------------------------------------

    local rollID =
        fields[2]

    if not self:IsCurrentRemoteRoll(
        rollID,
        sender
    ) then
        return
    end

    local remote =
        self.remote

    --------------------------------------------------
    -- ITEM LINK
    --------------------------------------------------

    if messageType == "L" then
        remote.itemLink =
            fields[3]

        self:Debug(
            "Received item link for "
            .. tostring(
                remote.itemName
            )
        )

        self:NotifyChanged()

        return
    end

    --------------------------------------------------
    -- NORMAL ACCEPTED ROLL
    --------------------------------------------------

    if messageType == "R" then
        local sequence =
            tonumber(
                fields[3]
            )

        local playerName =
            fields[4]

        local value =
            tonumber(
                fields[5]
            )

        local category =
            fields[6]

        local rollIndex =
            tonumber(
                fields[7]
            ) or 1

        if not sequence
            or not playerName
            or playerName == ""
            or not value
        then
            return
        end

        if remote.seenSequences[
            sequence
        ] then
            return
        end

        remote.seenSequences[
            sequence
        ] =
            true

        table.insert(
            remote.rolls,
            {
                sequence =
                    sequence,

                playerName =
                    playerName,

                value =
                    value,

                category =
                    category,

                rollIndex =
                    rollIndex,
            }
        )

        self:Debug(
            string.format(
                "ROLL: %s rolled %d (%s).",
                tostring(
                    playerName
                ),
                value,
                tostring(
                    category
                )
            )
        )

        self:NotifyChanged()

        return
    end

    --------------------------------------------------
    -- TIE START
    --------------------------------------------------

    if messageType == "T" then
        local duration =
            tonumber(
                fields[3]
            ) or 0

        local expectedMaximum =
            tonumber(
                fields[4]
            ) or 100

        remote.state =
            "tie"

        remote.duration =
            duration

        remote.receivedAt =
            GetTime()

        remote.endsAt =
            GetTime()
            + duration

        remote.expectedMaximum =
            expectedMaximum

        remote.tieRolls =
            {}

        remote.tieCandidates =
            {}

        self:Debug(
            string.format(
                "TIE started: /roll %d, "
                .. "%d seconds.",
                expectedMaximum,
                duration
            )
        )

        self:NotifyChanged()

        return
    end

    --------------------------------------------------
    -- TIE ELIGIBILITY
    --------------------------------------------------

    if messageType == "E" then
        local playerName =
            fields[3]

        if not playerName
            or playerName == ""
        then
            return
        end

        remote.tieCandidates =
            remote.tieCandidates
            or {}

        local normalized =
            AL:NormalizeName(
                playerName
            )

        if not normalized then
            return
        end

        remote.tieCandidates[
            normalized
        ] =
            playerName

        self:Debug(
            "TIE ELIGIBLE: "
            .. tostring(
                playerName
            )
        )

        self:NotifyChanged()

        return
    end

    --------------------------------------------------
    -- TIE-BREAK ROLL
    --------------------------------------------------

    if messageType == "B" then
        local sequence =
            tonumber(
                fields[3]
            )

        local playerName =
            fields[4]

        local value =
            tonumber(
                fields[5]
            )

        local maximum =
            tonumber(
                fields[6]
            ) or 100

        if not sequence
            or not playerName
            or playerName == ""
            or not value
        then
            return
        end

        if remote.seenSequences[
            sequence
        ] then
            return
        end

        remote.seenSequences[
            sequence
        ] =
            true

        table.insert(
            remote.tieRolls,
            {
                sequence =
                    sequence,

                playerName =
                    playerName,

                value =
                    value,

                maximum =
                    maximum,
            }
        )

        self:Debug(
            string.format(
                "TIE ROLL: %s rolled %d.",
                tostring(
                    playerName
                ),
                value
            )
        )

        self:NotifyChanged()

        return
    end

    --------------------------------------------------
    -- FINISH
    --------------------------------------------------

    if messageType == "F" then
        remote.state =
            "finished"

        remote.endsAt =
            GetTime()

        self:Debug(
            "FINISH for "
            .. tostring(
                remote.itemName
            )
        )

        self:NotifyChanged()

        return
    end

    --------------------------------------------------
    -- CANCEL
    --------------------------------------------------

    if messageType == "C" then
        remote.state =
            "cancelled"

        remote.endsAt =
            GetTime()

        self:Debug(
            "CANCEL for "
            .. tostring(
                remote.itemName
            )
        )

        self:NotifyChanged()
    end
end