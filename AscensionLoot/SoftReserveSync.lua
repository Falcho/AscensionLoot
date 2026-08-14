local AL =
    AscensionLoot

AL.SoftReserveSync =
    AL.SoftReserveSync
    or {}

local Sync =
    AL.SoftReserveSync

--------------------------------------------------
-- Protocol
--------------------------------------------------

local PREFIX =
    "AscLootSR"

local FIELD_SEPARATOR =
    "\031"

--------------------------------------------------
-- Leave generous room below the addon-message
-- limit for our protocol fields.
--------------------------------------------------

local CHUNK_SIZE =
    180

local MAX_CHUNKS =
    500

--------------------------------------------------
-- Pace a large SR export rather than firing dozens
-- of SendAddonMessage calls in one frame.
--------------------------------------------------

local SEND_INTERVAL =
    0.10

local TRANSFER_TIMEOUT =
    30

--------------------------------------------------
-- Runtime state
--------------------------------------------------

Sync.initialized =
    false

Sync.transferCounter =
    0

Sync.outgoing =
    Sync.outgoing
    or {}

Sync.incoming =
    Sync.incoming
    or {}

Sync.nextSendAt =
    0

--------------------------------------------------
-- Helpers
--------------------------------------------------

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

local function buildMessage(
    messageType,
    transferID,
    index,
    total,
    payload
)
    return table.concat(
        {
            tostring(
                messageType
                or ""
            ),

            tostring(
                transferID
                or ""
            ),

            tostring(
                index
                or ""
            ),

            tostring(
                total
                or ""
            ),

            tostring(
                payload
                or ""
            ),
        },
        FIELD_SEPARATOR
    )
end

local function splitMessage(
    message
)
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
                message:sub(
                    position
                )
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

--------------------------------------------------
-- Initialisation
--------------------------------------------------

function Sync:Initialize()
    if self.initialized then
        return
    end

    self.initialized =
        true

    if RegisterAddonMessagePrefix then
        local success =
            RegisterAddonMessagePrefix(
                PREFIX
            )

        if success == false then
            AL:Print(
                "Could not register the "
                    .. "soft-reserve sync prefix.",
                1,
                0.3,
                0.3
            )
        end
    end
end

--------------------------------------------------
-- Sender
--------------------------------------------------

function Sync:CanBroadcast()
    return AL:IsSoftReserveAuthority(
        UnitName("player")
    )
end

function Sync:CreateTransferID()
    self.transferCounter =
        (
            self.transferCounter
            or 0
        )
        + 1

    return string.format(
        "%d-%d",
        time(),
        self.transferCounter
    )
end

function Sync:Broadcast(
    encoded
)
    if not self:
        CanBroadcast()
    then
        return false
    end

    encoded =
        tostring(
            encoded
            or ""
        ):gsub(
            "%s",
            ""
        )

    if encoded == "" then
        return false
    end

    local total =
        math.ceil(
            #encoded
            / CHUNK_SIZE
        )

    if total < 1 then
        return false
    end

    if total > MAX_CHUNKS then
        AL:Print(
            "The soft-reserve export is too large "
                .. "to synchronize safely.",
            1,
            0.3,
            0.3
        )

        return false
    end

    local transferID =
        self:
            CreateTransferID()

    --------------------------------------------------
    -- A newer import supersedes any older transfer
    -- that had not finished sending yet.
    --------------------------------------------------

    self.outgoing = {}

    for index = 1,
        total
    do
        local firstByte =
            (
                index - 1
            )
            * CHUNK_SIZE
            + 1

        local lastByte =
            math.min(
                #encoded,
                firstByte
                    + CHUNK_SIZE
                    - 1
            )

        local chunk =
            encoded:sub(
                firstByte,
                lastByte
            )

        table.insert(
            self.outgoing,
            buildMessage(
                "D",
                transferID,
                index,
                total,
                chunk
            )
        )
    end

    self.nextSendAt =
        0

    AL:Print(
        string.format(
            "Sharing soft reserves with "
                .. "AscensionLoot users in the raid "
                .. "(%d %s).",
            total,
            total == 1
                and "packet"
                or "packets"
        )
    )

    return true
end

--------------------------------------------------
-- Receiver
--------------------------------------------------

function Sync:CompleteTransfer(
    transferKey,
    transfer
)
    if not transfer
        or not transfer.total
    then
        return
    end

    local chunks = {}

    for index = 1,
        transfer.total
    do
        local chunk =
            transfer.chunks[
                index
            ]

        if not chunk then
            return
        end

        table.insert(
            chunks,
            chunk
        )
    end

    self.incoming[
        transferKey
    ] = nil

    local encoded =
        table.concat(
            chunks
        )

    --------------------------------------------------
    -- Run the exact same Base64/JSON/structure
    -- validation as a manual import.
    --
    -- The second argument prevents the received import
    -- from being broadcast again.
    --------------------------------------------------

    local success,
        message =
            AL.SoftReserve:
                Import(
                    encoded,
                    true
                )

    if not success then
        AL:Print(
            "Rejected synchronized soft reserves "
                .. "from "
                .. tostring(
                    transfer.sender
                )
                .. ": "
                .. tostring(
                    message
                        or "invalid data"
                ),
            1,
            0.3,
            0.3
        )

        return
    end

    AL:Print(
        "Received soft reserves from "
            .. tostring(
                transfer.sender
            )
            .. ". "
            .. tostring(
                message
                or ""
            )
    )
end

function Sync:OnAddonMessage(
    prefix,
    message,
    distribution,
    sender
)
    if prefix ~= PREFIX then
        return
    end

    --------------------------------------------------
    -- SR synchronization is raid-only.
    --------------------------------------------------

    if distribution ~= "RAID"
        or not AL:IsInRaid()
    then
        return
    end

    if not sender
        or sender == ""
        or samePlayer(
            sender,
            UnitName("player")
        )
    then
        return
    end

    --------------------------------------------------
    -- SECURITY / AUTHORITY:
    --
    -- Assistants are intentionally NOT accepted.
    --------------------------------------------------

    if not AL:
        IsSoftReserveAuthority(
            sender
        )
    then
        return
    end

    local fields =
        splitMessage(
            tostring(
                message
                or ""
            )
        )

    if fields[1] ~= "D" then
        return
    end

    local transferID =
        fields[2]

    local index =
        tonumber(
            fields[3]
        )

    local total =
        tonumber(
            fields[4]
        )

    local payload =
        fields[5]

    if not transferID
        or transferID == ""
        or not index
        or not total
        or not payload
    then
        return
    end

    if index < 1
        or total < 1
        or index > total
        or total > MAX_CHUNKS
    then
        return
    end

    local senderKey =
        AL:NormalizeName(
            sender
        )

    if not senderKey then
        return
    end

    local transferKey =
        senderKey
        .. ":"
        .. transferID

    local transfer =
        self.incoming[
            transferKey
        ]

    if not transfer then
        transfer = {
            sender =
                sender,

            total =
                total,

            chunks =
                {},

            received =
                0,

            lastReceivedAt =
                GetTime(),
        }

        self.incoming[
            transferKey
        ] =
            transfer
    end

    --------------------------------------------------
    -- A transfer ID may never change its declared
    -- packet count.
    --------------------------------------------------

    if transfer.total ~= total then
        self.incoming[
            transferKey
        ] = nil

        return
    end

    transfer.lastReceivedAt =
        GetTime()

    --------------------------------------------------
    -- Ignore duplicate packets.
    --------------------------------------------------

    if not transfer.chunks[
        index
    ] then
        transfer.chunks[
            index
        ] =
            payload

        transfer.received =
            transfer.received
            + 1
    end

    if transfer.received
        >= transfer.total
    then
        self:
            CompleteTransfer(
                transferKey,
                transfer
            )
    end
end

--------------------------------------------------
-- Runtime sending / cleanup
--------------------------------------------------

function Sync:OnUpdate()
    local now =
        GetTime()

    --------------------------------------------------
    -- Discard incomplete transfers rather than keeping
    -- them forever.
    --------------------------------------------------

    for transferKey,
        transfer in pairs(
            self.incoming
        )
    do
        if now
            - (
                transfer.lastReceivedAt
                or now
            )
            >= TRANSFER_TIMEOUT
        then
            self.incoming[
                transferKey
            ] = nil
        end
    end

    if #self.outgoing == 0 then
        return
    end

    --------------------------------------------------
    -- Stop a queued share if we leave the raid or lose
    -- both allowed authority roles while it is sending.
    --------------------------------------------------

    if not self:
        CanBroadcast()
    then
        self.outgoing = {}
        return
    end

    if now
        < (
            self.nextSendAt
            or 0
        )
    then
        return
    end

    local message =
        table.remove(
            self.outgoing,
            1
        )

    if not message then
        return
    end

    local success =
        pcall(
            SendAddonMessage,
            PREFIX,
            message,
            "RAID"
        )

    if not success then
        self.outgoing = {}

        AL:Print(
            "Soft-reserve synchronization "
                .. "could not be sent.",
            1,
            0.3,
            0.3
        )

        return
    end

    self.nextSendAt =
        now
        + SEND_INTERVAL
end