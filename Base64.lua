local AL = AscensionLoot

AL.Base64 = AL.Base64 or {}
local Base64 = AL.Base64

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decodeMap = {}
for index = 1, #alphabet do
    decodeMap[alphabet:sub(index, index)] = index - 1
end

function Base64.Decode(input)
    if type(input) ~= "string" then
        return nil, "The import must be text."
    end

    local cleaned = input:gsub("%s", "")
    if cleaned == "" then return nil, "The import is empty." end
    if cleaned:find("[^A-Za-z0-9%+/=]") then
        return nil, "The import contains characters that are not valid Base64."
    end
    if (#cleaned % 4) ~= 0 then
        return nil, "The Base64 length is invalid."
    end

    local output = {}
    local outputIndex = 1

    for position = 1, #cleaned, 4 do
        local c1 = cleaned:sub(position, position)
        local c2 = cleaned:sub(position + 1, position + 1)
        local c3 = cleaned:sub(position + 2, position + 2)
        local c4 = cleaned:sub(position + 3, position + 3)

        local b1 = decodeMap[c1]
        local b2 = decodeMap[c2]
        local b3 = c3 == "=" and 0 or decodeMap[c3]
        local b4 = c4 == "=" and 0 or decodeMap[c4]

        if b1 == nil or b2 == nil or b3 == nil or b4 == nil then
            return nil, "The Base64 data is malformed."
        end

        local combined = b1 * 262144 + b2 * 4096 + b3 * 64 + b4
        local byte1 = math.floor(combined / 65536) % 256
        local byte2 = math.floor(combined / 256) % 256
        local byte3 = combined % 256

        output[outputIndex] = string.char(byte1)
        outputIndex = outputIndex + 1
        if c3 ~= "=" then
            output[outputIndex] = string.char(byte2)
            outputIndex = outputIndex + 1
        end
        if c4 ~= "=" then
            output[outputIndex] = string.char(byte3)
            outputIndex = outputIndex + 1
        end
    end

    return table.concat(output)
end
