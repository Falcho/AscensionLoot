local AL = AscensionLoot

AL.TierTokens =
    AL.TierTokens or {}

local TT =
    AL.TierTokens

--------------------------------------------------
-- Storage
--------------------------------------------------

TT.tokens =
    TT.tokens or {}

TT.pieceToToken =
    TT.pieceToToken or {}

--------------------------------------------------
-- Slot layouts
--------------------------------------------------

local FULL_TIER_SLOTS = {
    "WRIST",
    "LEGS",
    "HANDS",
    "HEAD",
    "WAIST",
    "SHOULDERS",
    "CHEST",
    "BOOTS",
}

local AQ40_SLOTS = {
    "BOOTS",
    "LEGS",
    "SHOULDERS",
    "HEAD",
    "CHEST",
}

local AQ20_SLOTS = {
    "CLOAK",
    "NECK",
    "RING",
}

--------------------------------------------------
-- Registration helpers
--------------------------------------------------

function TT:RegisterToken(
    itemID,
    tier,
    raid,
    difficulty,
    slot
)
    itemID =
        tonumber(itemID)

    if not itemID then
        return
    end

    self.tokens[itemID] = {
        itemID = itemID,
        tier = tier,
        raid = raid,
        difficulty = difficulty,
        slot = slot,

        rewards = {},
    }
end

function TT:RegisterTokenSet(
    tier,
    raid,
    difficulty,
    slots,
    itemIDs
)
    if type(slots) ~= "table"
        or type(itemIDs) ~= "table"
    then
        return
    end

    if #slots ~= #itemIDs then
        AL:Print(
            "Tier token mapping error for "
                .. tostring(tier)
                .. " "
                .. tostring(difficulty)
                .. ": slot/token count does not match.",
            1,
            0.3,
            0.3
        )

        return
    end

    for index,
        itemID in ipairs(
            itemIDs
        )
    do
        self:RegisterToken(
            itemID,
            tier,
            raid,
            difficulty,
            slots[index]
        )
    end
end

--------------------------------------------------
-- Tier-piece mappings
--------------------------------------------------

function TT:AddReward(
    tokenID,
    pieceID
)
    tokenID =
        tonumber(tokenID)

    pieceID =
        tonumber(pieceID)

    if not tokenID
        or not pieceID
    then
        return false
    end

    local token =
        self.tokens[tokenID]

    if not token then
        return false
    end

    --------------------------------------------------
    -- A physical tier piece may belong to exactly
    -- one token.
    --
    -- Never silently overwrite an existing mapping.
    --------------------------------------------------

    local existingTokenID =
        self.pieceToToken[
            pieceID
        ]

    if existingTokenID
        and tonumber(existingTokenID)
            ~= tokenID
    then
        local existingToken =
            self.tokens[
                existingTokenID
            ]

        AL:Print(
            string.format(
                "Tier mapping conflict: item %d already "
                    .. "maps to token %d (%s %s %s), "
                    .. "cannot also map to token %d.",
                pieceID,
                existingTokenID,
                existingToken
                    and tostring(
                        existingToken.tier
                    )
                    or "?",
                existingToken
                    and tostring(
                        existingToken.difficulty
                    )
                    or "?",
                existingToken
                    and tostring(
                        existingToken.slot
                    )
                    or "?",
                tokenID
            ),
            1,
            0.3,
            0.3
        )

        return false
    end
    --------------------------------------------------
    -- Prevent duplicate entries.
    --------------------------------------------------

    for _, existingID in ipairs(
        token.rewards
    ) do
        if tonumber(existingID)
            == pieceID
        then
            return true
        end
    end

    table.insert(
        token.rewards,
        pieceID
    )

    self.pieceToToken[
        pieceID
    ] =
        tokenID

    return true
end

function TT:AddRewards(
    tokenID,
    pieceIDs
)
    local added = 0

    for _, pieceID in ipairs(
        pieceIDs or {}
    ) do
        if self:AddReward(
            tokenID,
            pieceID
        )
        then
            added =
                added + 1
        end
    end

    return added
end

--------------------------------------------------
-- Lookups
--------------------------------------------------

function TT:IsToken(
    itemID
)
    return self.tokens[
        tonumber(itemID)
    ] ~= nil
end

function TT:GetToken(
    tokenID
)
    return self.tokens[
        tonumber(tokenID)
    ]
end

function TT:GetTokenIDForPiece(
    pieceID
)
    return self.pieceToToken[
        tonumber(pieceID)
    ]
end

function TT:GetTokenForPiece(
    pieceID
)
    local tokenID =
        self:GetTokenIDForPiece(
            pieceID
        )

    return tokenID
        and self.tokens[tokenID]
        or nil
end

function TT:GetRewards(
    tokenID
)
    local token =
        self:GetToken(
            tokenID
        )

    return token
        and token.rewards
        or {}
end

function TT:GetMappingSummary()
    local tokenCount = 0
    local mappedTokenCount = 0
    local rewardCount = 0

    for _, token in pairs(
        self.tokens
    ) do
        tokenCount =
            tokenCount + 1

        local rewards =
            token.rewards or {}

        if #rewards > 0 then
            mappedTokenCount =
                mappedTokenCount + 1
        end

        rewardCount =
            rewardCount
            + #rewards
    end

    return {
        tokens =
            tokenCount,

        mappedTokens =
            mappedTokenCount,

        unmappedTokens =
            tokenCount
            - mappedTokenCount,

        rewards =
            rewardCount,
    }
end

--------------------------------------------------
-- Tier 1 - Molten Core
--
-- Order:
-- Wrist, Legs, Hands, Head,
-- Waist, Shoulders, Chest, Boots
--------------------------------------------------

TT:RegisterTokenSet(
    "T1",
    "Molten Core",
    "NORMAL",
    FULL_TIER_SLOTS,
    {
        2522362,
        2522359,
        2522364,
        2522360,
        2522363,
        2522361,
        2522350,
        2522365,
    }
)

TT:RegisterTokenSet(
    "T1",
    "Molten Core",
    "HEROIC",
    FULL_TIER_SLOTS,
    {
        2622362,
        2622359,
        2622364,
        2622360,
        2622363,
        2622361,
        2622350,
        2622365,
    }
)

TT:RegisterTokenSet(
    "T1",
    "Molten Core",
    "MYTHIC",
    FULL_TIER_SLOTS,
    {
        3722362,
        3722359,
        3722364,
        3722360,
        3722363,
        3722361,
        3722350,
        3722365,
    }
)

TT:RegisterTokenSet(
    "T1",
    "Molten Core",
    "ASCENDED",
    FULL_TIER_SLOTS,
    {
        2722362,
        2722359,
        2722364,
        2722360,
        2722363,
        2722361,
        2722350,
        2722365,
    }
)

--------------------------------------------------
-- Tier 2 - Blackwing Lair
--
-- Heroic/Mythic/Ascended IDs below are filled from
-- the difficulty-prefix pattern in the supplied IDs.
--------------------------------------------------

TT:RegisterTokenSet(
    "T2",
    "Blackwing Lair",
    "NORMAL",
    FULL_TIER_SLOTS,
    {
        2522462,
        2522459,
        2522464,
        2522460,
        2522463,
        2522461,
        2522450,
        2522465,
    }
)

TT:RegisterTokenSet(
    "T2",
    "Blackwing Lair",
    "HEROIC",
    FULL_TIER_SLOTS,
    {
        2622462,
        2622459,
        2622464,
        2622460,
        2622463,
        2622461,
        2622450,
        2622465,
    }
)

TT:RegisterTokenSet(
    "T2",
    "Blackwing Lair",
    "MYTHIC",
    FULL_TIER_SLOTS,
    {
        3722462,
        3722459,
        3722464,
        3722460,
        3722463,
        3722461,
        3722450,
        3722465,
    }
)

TT:RegisterTokenSet(
    "T2",
    "Blackwing Lair",
    "ASCENDED",
    FULL_TIER_SLOTS,
    {
        2722462,
        2722459,
        2722464,
        2722460,
        2722463,
        2722461,
        2722450,
        2722465,
    }
)

--------------------------------------------------
-- Tier 3 - Naxxramas
--------------------------------------------------

TT:RegisterTokenSet(
    "T3",
    "Naxxramas",
    "NORMAL",
    FULL_TIER_SLOTS,
    {
        22355,
        22352,
        22357,
        22353,
        22356,
        22354,
        22349,
        22358,
    }
)

TT:RegisterTokenSet(
    "T3",
    "Naxxramas",
    "HEROIC",
    FULL_TIER_SLOTS,
    {
        322355,
        322352,
        322357,
        322353,
        322356,
        322354,
        322349,
        322358,
    }
)

--------------------------------------------------
-- Mythic T3 does NOT use the simple prefix scheme.
-- These are the explicit IDs supplied for Mythic.
--------------------------------------------------

TT:RegisterTokenSet(
    "T3",
    "Naxxramas",
    "MYTHIC",
    FULL_TIER_SLOTS,
    {
        1402262,
        1402284,
        1402268,
        1402278,
        1402300,
        1402286,
        1402264,
        1402290,
    }
)

TT:RegisterTokenSet(
    "T3",
    "Naxxramas",
    "ASCENDED",
    FULL_TIER_SLOTS,
    {
        222355,
        222352,
        222357,
        222353,
        222356,
        222354,
        222349,
        222358,
    }
)

--------------------------------------------------
-- Tier 2.5 - Temple of Ahn'Qiraj / AQ40
--
-- Order:
-- Boots, Legs, Shoulders, Head, Chest
--------------------------------------------------

TT:RegisterTokenSet(
    "T2.5",
    "Temple of Ahn'Qiraj",
    "NORMAL",
    AQ40_SLOTS,
    {
        20928,
        20931,
        20932,
        20930,
        20933,
    }
)

TT:RegisterTokenSet(
    "T2.5",
    "Temple of Ahn'Qiraj",
    "HEROIC",
    AQ40_SLOTS,
    {
        320928,
        320931,
        320932,
        320930,
        320933,
    }
)

TT:RegisterTokenSet(
    "T2.5",
    "Temple of Ahn'Qiraj",
    "MYTHIC",
    AQ40_SLOTS,
    {
        1320928,
        1320931,
        1320932,
        1320930,
        1320933,
    }
)

TT:RegisterTokenSet(
    "T2.5",
    "Temple of Ahn'Qiraj",
    "ASCENDED",
    AQ40_SLOTS,
    {
        220928,
        220931,
        220932,
        220930,
        220933,
    }
)

--------------------------------------------------
-- AQ20 class sets - Ruins of Ahn'Qiraj
--
-- Order:
-- Cloak, Neck, Ring
--------------------------------------------------

TT:RegisterTokenSet(
    "AQ20",
    "Ruins of Ahn'Qiraj",
    "NORMAL",
    AQ20_SLOTS,
    {
        1506051,
        1506053,
        1506052,
    }
)

TT:RegisterTokenSet(
    "AQ20",
    "Ruins of Ahn'Qiraj",
    "HEROIC",
    AQ20_SLOTS,
    {
        1806051,
        1806053,
        1806052,
    }
)

TT:RegisterTokenSet(
    "AQ20",
    "Ruins of Ahn'Qiraj",
    "MYTHIC",
    AQ20_SLOTS,
    {
        2806051,
        2806053,
        2806052,
    }
)

TT:RegisterTokenSet(
    "AQ20",
    "Ruins of Ahn'Qiraj",
    "ASCENDED",
    AQ20_SLOTS,
    {
        1706051,
        1706053,
        1706052,
    }
)

--------------------------------------------------
-- Tier-piece reward mappings
--------------------------------------------------

--------------------------------------------------
-- Tier 1 - Ascended
--------------------------------------------------

-- Legs
TT:AddReward(
    2722359,
    212569 -- Charred Defender's Legguards
)