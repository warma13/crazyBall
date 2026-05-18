-- ============================================================================
-- SecureValue.lua - XOR 混淆整数，防内存扫描
-- ============================================================================

local M = {}

local function randomKey()
    return math.random(0, 0x7FFFFFFF)
end

function M.new(plainValue)
    plainValue = plainValue or 0
    local key = randomKey()
    return {
        _sv = true,
        _xorVal = plainValue ~ key,
        _key = key,
    }
end

function M.get(sv)
    return sv._xorVal ~ sv._key
end

function M.set(sv, plainValue)
    local key = randomKey()
    sv._xorVal = plainValue ~ key
    sv._key = key
end

function M.add(sv, delta)
    M.set(sv, M.get(sv) + delta)
end

return M
