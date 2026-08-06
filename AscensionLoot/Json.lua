local AL = AscensionLoot

AL.Json = AL.Json or {}
local Json = AL.Json

local function utf8FromCodepoint(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        local b1 = 0xC0 + math.floor(codepoint / 0x40)
        local b2 = 0x80 + (codepoint % 0x40)
        return string.char(b1, b2)
    elseif codepoint <= 0xFFFF then
        local b1 = 0xE0 + math.floor(codepoint / 0x1000)
        local b2 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
        local b3 = 0x80 + (codepoint % 0x40)
        return string.char(b1, b2, b3)
    end
    return "?"
end

function Json.Decode(text)
    if type(text) ~= "string" then return nil, "JSON input must be text." end

    local position = 1
    local length = #text

    local function fail(message)
        error(string.format("%s at character %d", message, position), 0)
    end

    local function skipWhitespace()
        while position <= length do
            local char = text:sub(position, position)
            if char == " " or char == "\t" or char == "\r" or char == "\n" then
                position = position + 1
            else
                break
            end
        end
    end

    local parseValue

    local function parseString()
        if text:sub(position, position) ~= '"' then fail("Expected a string") end
        position = position + 1
        local output = {}

        while position <= length do
            local char = text:sub(position, position)
            if char == '"' then
                position = position + 1
                return table.concat(output)
            elseif char == "\\" then
                position = position + 1
                local escaped = text:sub(position, position)
                local replacements = {
                    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
                    ['b'] = '\b', ['f'] = '\f', ['n'] = '\n',
                    ['r'] = '\r', ['t'] = '\t',
                }
                if replacements[escaped] then
                    table.insert(output, replacements[escaped])
                    position = position + 1
                elseif escaped == "u" then
                    local hex = text:sub(position + 1, position + 4)
                    if not hex:match("^%x%x%x%x$") then fail("Invalid Unicode escape") end
                    table.insert(output, utf8FromCodepoint(tonumber(hex, 16)))
                    position = position + 5
                else
                    fail("Invalid escape sequence")
                end
            else
                if string.byte(char) < 32 then fail("Control character in string") end
                table.insert(output, char)
                position = position + 1
            end
        end

        fail("Unterminated string")
    end

    local function parseNumber()
        local start = position
        local char = text:sub(position, position)
        if char == "-" then position = position + 1 end

        if text:sub(position, position) == "0" then
            position = position + 1
        else
            if not text:sub(position, position):match("%d") then fail("Invalid number") end
            while text:sub(position, position):match("%d") do position = position + 1 end
        end

        if text:sub(position, position) == "." then
            position = position + 1
            if not text:sub(position, position):match("%d") then fail("Invalid decimal number") end
            while text:sub(position, position):match("%d") do position = position + 1 end
        end

        local exponent = text:sub(position, position)
        if exponent == "e" or exponent == "E" then
            position = position + 1
            local sign = text:sub(position, position)
            if sign == "+" or sign == "-" then position = position + 1 end
            if not text:sub(position, position):match("%d") then fail("Invalid exponent") end
            while text:sub(position, position):match("%d") do position = position + 1 end
        end

        local number = tonumber(text:sub(start, position - 1))
        if number == nil then fail("Invalid number") end
        return number
    end

    local function parseArray()
        position = position + 1
        skipWhitespace()
        local result = {}
        if text:sub(position, position) == "]" then
            position = position + 1
            return result
        end

        while true do
            table.insert(result, parseValue())
            skipWhitespace()
            local char = text:sub(position, position)
            if char == "]" then
                position = position + 1
                return result
            elseif char ~= "," then
                fail("Expected ',' or ']' in array")
            end
            position = position + 1
            skipWhitespace()
        end
    end

    local function parseObject()
        position = position + 1
        skipWhitespace()
        local result = {}
        if text:sub(position, position) == "}" then
            position = position + 1
            return result
        end

        while true do
            if text:sub(position, position) ~= '"' then fail("Expected an object key") end
            local key = parseString()
            skipWhitespace()
            if text:sub(position, position) ~= ":" then fail("Expected ':' after object key") end
            position = position + 1
            skipWhitespace()
            result[key] = parseValue()
            skipWhitespace()
            local char = text:sub(position, position)
            if char == "}" then
                position = position + 1
                return result
            elseif char ~= "," then
                fail("Expected ',' or '}' in object")
            end
            position = position + 1
            skipWhitespace()
        end
    end

    function parseValue()
        skipWhitespace()
        local char = text:sub(position, position)
        if char == '"' then return parseString() end
        if char == "{" then return parseObject() end
        if char == "[" then return parseArray() end
        if char == "-" or char:match("%d") then return parseNumber() end
        if text:sub(position, position + 3) == "true" then position = position + 4 return true end
        if text:sub(position, position + 4) == "false" then position = position + 5 return false end
        if text:sub(position, position + 3) == "null" then position = position + 4 return nil end
        fail("Unexpected JSON value")
    end

    local success, result = pcall(function()
        local value = parseValue()
        skipWhitespace()
        if position <= length then fail("Unexpected trailing data") end
        return value
    end)

    if not success then return nil, result end
    return result
end
