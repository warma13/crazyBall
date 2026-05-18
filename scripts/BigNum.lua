-- ============================================================================
-- BigNum.lua - 大数模块（尾数+指数表示，无限精度）
--
-- 内部表示: { _isBigNum=true, m=尾数, e=指数 }
--   m ∈ [1, 10)，e 为任意整数
--   值 = m × 10^e
--   特殊: 零 = {m=0, e=0}
--
-- 格式化: Clicker Titans 风格
--   K(1e3) M(1e6) B(1e9) T(1e12)
--   aa(1e15) ab(1e18) ac(1e21) ... az(1e90) ba(1e93) ... zz(1e2040)
-- ============================================================================

local M = {}

local mt = {}
mt.__index = mt

-- 缓存原始 math 函数（在猴补丁之前捕获）
local _rawFloor = math.floor
local _rawMax = math.max
local _rawMin = math.min
local _rawAbs = math.abs

-- ============================================================================
-- 构造 / 工具
-- ============================================================================

--- 检查是否为 BigNum
---@param v any
---@return boolean
function M.is(v)
    return type(v) == "table" and v._isBigNum == true
end

--- 规范化：确保 m ∈ [1, 10)，处理零、NaN、Inf
local function normalize(bn)
    if bn.m == 0 or bn.m ~= bn.m then
        bn.m = 0; bn.e = 0
        return bn
    end
    if bn.m == math.huge or bn.m == -math.huge then
        return bn
    end
    -- 处理负数
    local sign = 1
    if bn.m < 0 then sign = -1; bn.m = -bn.m end
    -- 调整到 [1, 10)
    if bn.m >= 10 then
        local shift = math.floor(math.log(bn.m, 10))
        bn.m = bn.m / (10 ^ shift)
        bn.e = bn.e + shift
        -- 浮点修正
        if bn.m >= 10 then bn.m = bn.m / 10; bn.e = bn.e + 1 end
    elseif bn.m > 0 and bn.m < 1 then
        local shift = math.floor(-math.log(bn.m, 10)) + 1
        bn.m = bn.m * (10 ^ shift)
        bn.e = bn.e - shift
        -- 浮点修正
        if bn.m >= 10 then bn.m = bn.m / 10; bn.e = bn.e + 1 end
        if bn.m < 1 and bn.m > 0 then bn.m = bn.m * 10; bn.e = bn.e - 1 end
    end
    bn.m = sign * bn.m
    return bn
end

-- ============================================================================
-- 对象池（减少 GC 压力）
-- ============================================================================

local _pool = {}       -- BigNum 空闲表池
local _poolSize = 0    -- 当前池中可用表数量
local _POOL_MAX = 128  -- 池上限，防止内存泄漏

--- 从池中获取 BigNum 表（或创建新表）
---@param m number 尾数
---@param e number 指数
---@return table BigNum
local function _acquire(m, e)
    if _poolSize > 0 then
        local bn = _pool[_poolSize]
        _pool[_poolSize] = nil
        _poolSize = _poolSize - 1
        bn.m = m
        bn.e = e
        return bn
    end
    return setmetatable({ _isBigNum = true, m = m, e = e }, mt)
end

--- 将不再使用的 BigNum 归还池中
---@param bn table BigNum
function M.release(bn)
    if _poolSize < _POOL_MAX and M.is(bn) then
        _poolSize = _poolSize + 1
        _pool[_poolSize] = bn
    end
end

-- ============================================================================
-- compact：小数值降级为原生 number
-- ============================================================================

--- 当 BigNum 的值可以用 Lua double 精确表示（≤1e15 的整数）时，返回原生 number
--- 否则返回原 BigNum 不变
---@param bn table|number BigNum 或已经是 number
---@return table|number 原生 number 或原 BigNum
function M.compact(bn)
    if type(bn) == "number" then return bn end
    if not M.is(bn) then return bn end
    if bn.m == 0 then return 0 end
    -- e >= 15 时值超出 double 精确整数范围，保持 BigNum
    if bn.e >= 15 or bn.e < 0 then return bn end
    -- 计算实际值：m * 10^e
    local val = bn.m * (10 ^ bn.e)
    -- 2^53 ≈ 9.007e15，我们保守用 1e15 以确保精确
    if val <= 1e15 and val >= -1e15 then
        -- 归还表到池中
        M.release(bn)
        return _rawFloor(val)
    end
    return bn
end

--- 创建 BigNum
---@param val number|table|nil 初始值（数字或已有 BigNum）
---@return table BigNum
function M.new(val)
    if M.is(val) then
        return _acquire(val.m, val.e)
    end
    val = tonumber(val) or 0
    if val == 0 then
        return _acquire(0, 0)
    end
    local bn = _acquire(val, 0)
    return normalize(bn)
end

--- 确保值是 BigNum（如果已经是就直接返回，否则转换）
---@param v number|table
---@return table BigNum
function M.ensure(v)
    if M.is(v) then return v end
    return M.new(v)
end

--- 复制 BigNum
function M.copy(bn)
    return _acquire(bn.m, bn.e)
end

--- 转为普通 number（可能丢失精度或溢出）
function M.toNumber(bn)
    bn = M.ensure(bn)
    if bn.m == 0 then return 0 end
    if bn.e > 308 then return math.huge end
    if bn.e < -308 then return 0 end
    return bn.m * (10 ^ bn.e)
end

--- 转为 log10 值（不经过 toNumber，不会溢出）
--- 返回普通 number，保序且适合排行榜存储
function M.toLog10(bn)
    bn = M.ensure(bn)
    if bn.m <= 0 then return 0 end  -- 零或负数返回 0
    return math.log(bn.m, 10) + bn.e
end

--- 从 log10 值还原为 BigNum（log10 的逆运算）
function M.fromLog10(log10val)
    if not log10val or log10val <= 0 then return M.new(0) end
    local e = math.floor(log10val)
    local m = 10 ^ (log10val - e)
    return normalize(_acquire(m, e))
end

--- 是否为零
function M.isZero(bn)
    return bn.m == 0
end

--- 绝对值
function M.abs(bn)
    bn = M.ensure(bn)
    return _acquire(_rawAbs(bn.m), bn.e)
end

--- 符号
function M.sign(bn)
    if bn.m > 0 then return 1
    elseif bn.m < 0 then return -1
    else return 0 end
end

-- ============================================================================
-- 算术运算
-- ============================================================================

--- 加法（对齐指数）
local function add(a, b)
    a = M.ensure(a)
    b = M.ensure(b)
    if a.m == 0 then return M.copy(b) end
    if b.m == 0 then return M.copy(a) end
    -- 对齐到较大指数
    local diff = a.e - b.e
    if diff > 17 then return M.copy(a) end      -- b 忽略不计
    if diff < -17 then return M.copy(b) end      -- a 忽略不计
    local result
    if diff >= 0 then
        result = _acquire(a.m + b.m / (10 ^ diff), a.e)
    else
        result = _acquire(a.m / (10 ^ (-diff)) + b.m, b.e)
    end
    return normalize(result)
end

--- 减法
local function sub(a, b)
    b = M.ensure(b)
    local neg = _acquire(-b.m, b.e)
    return add(a, neg)
end

--- 乘法
local function mul(a, b)
    a = M.ensure(a)
    b = M.ensure(b)
    if a.m == 0 or b.m == 0 then return M.new(0) end
    local result = _acquire(a.m * b.m, a.e + b.e)
    return normalize(result)
end

--- 除法
local function div(a, b)
    a = M.ensure(a)
    b = M.ensure(b)
    if b.m == 0 then
        -- 除以零
        if a.m >= 0 then return M.new(math.huge) end
        return M.new(-math.huge)
    end
    if a.m == 0 then return M.new(0) end
    local result = _acquire(a.m / b.m, a.e - b.e)
    return normalize(result)
end

--- 幂运算（BigNum ^ number）
local function pow(a, n)
    a = M.ensure(a)
    n = tonumber(n) or 0
    if n == 0 then return M.new(1) end
    if a.m == 0 then return M.new(0) end
    if n == 1 then return M.copy(a) end
    -- 使用对数: (m*10^e)^n = 10^(n*(log10(m)+e))
    local absM = math.abs(a.m)
    local totalLog = n * (math.log(absM, 10) + a.e)
    local newE = math.floor(totalLog)
    local newM = 10 ^ (totalLog - newE)
    -- 处理符号：负数的整数次幂
    if a.m < 0 and n == math.floor(n) then
        if n % 2 ~= 0 then newM = -newM end
    end
    local result = _acquire(newM, newE)
    return normalize(result)
end

--- 取模
local function mod(a, b)
    a = M.ensure(a)
    b = M.ensure(b)
    if b.m == 0 then return M.new(0) end
    -- a mod b = a - floor(a/b) * b
    local quotient = div(a, b)
    quotient = M.floor(quotient)
    return sub(a, mul(quotient, b))
end

--- 取负
local function unm(a)
    a = M.ensure(a)
    return _acquire(-a.m, a.e)
end

-- ============================================================================
-- 比较运算
-- ============================================================================

--- 比较: 返回 -1, 0, 1
function M.cmp(a, b)
    a = M.ensure(a)
    b = M.ensure(b)
    -- 处理符号
    local sa, sb = M.sign(a), M.sign(b)
    if sa ~= sb then
        if sa > sb then return 1 else return -1 end
    end
    if sa == 0 then return 0 end
    -- 同号，比较指数和尾数
    if a.e ~= b.e then
        if sa > 0 then
            return a.e > b.e and 1 or -1
        else
            return a.e > b.e and -1 or 1
        end
    end
    -- 指数相同，比较尾数
    if a.m == b.m then return 0 end
    return a.m > b.m and 1 or -1
end

local function lt(a, b)
    return M.cmp(a, b) < 0
end

local function le(a, b)
    return M.cmp(a, b) <= 0
end

local function eq(a, b)
    -- 只有两个都是 BigNum 才判等
    if not M.is(a) or not M.is(b) then return false end
    return M.cmp(a, b) == 0
end

-- ============================================================================
-- floor / ceil
-- ============================================================================

--- BigNum 的 floor
function M.floor(bn)
    bn = M.ensure(bn)
    if bn.m == 0 then return M.new(0) end
    -- 如果指数足够大（>=15），尾数精度已不足以表示小数部分，直接返回
    if bn.e >= 15 then return M.copy(bn) end
    -- 如果值 < 1 (e < 0 或 e == 0 且 m < 1)
    if bn.e < 0 then
        return bn.m >= 0 and M.new(0) or M.new(-1)
    end
    -- 转为 number 做 floor
    local num = M.toNumber(bn)
    if num == math.huge or num == -math.huge then return M.copy(bn) end
    return M.new(math.floor(num))
end

-- ============================================================================
-- 格式化（Clicker Titans 风格）
-- ============================================================================

-- 基础后缀（tierIndex 0-4）
local BASE_SUFFIXES = { "", "K", "M", "B", "T" }

--- 根据 tierIndex 获取后缀
--- tierIndex 0="", 1="K", 2="M", 3="B", 4="T"
--- tierIndex 5="aa", 6="ab", ..., 30="az", 31="ba", ...
local function getSuffix(tierIndex)
    if tierIndex < 5 then
        return BASE_SUFFIXES[tierIndex + 1]
    end
    local letterIdx = tierIndex - 5
    local first = string.char(97 + math.floor(letterIdx / 26))
    local second = string.char(97 + (letterIdx % 26))
    return first .. second
end

--- 格式化 BigNum 为可读字符串
function M.format(bn)
    bn = M.ensure(bn)
    -- 特殊值
    if bn.m ~= bn.m then return "0" end
    if bn.m == math.huge then return "∞" end
    if bn.m == -math.huge then return "-∞" end
    -- 负数
    if bn.m < 0 then
        local pos = _acquire(-bn.m, bn.e)
        return "-" .. M.format(pos)
    end
    if bn.m == 0 then return "0" end

    -- 小于 1000：直接显示整数
    if bn.e < 3 then
        local num = M.toNumber(bn)
        return tostring(math.floor(num))
    end

    -- tierIndex = floor(e / 3)
    local tierIndex = math.floor(bn.e / 3)
    local suffix = getSuffix(tierIndex)

    -- 显示值 = m × 10^(e - tierIndex*3)
    local remainder = bn.e - tierIndex * 3
    local displayVal = bn.m * (10 ^ remainder)

    if displayVal >= 100 then
        return string.format("%.0f%s", displayVal, suffix)
    elseif displayVal >= 10 then
        return string.format("%.1f%s", displayVal, suffix)
    else
        return string.format("%.2f%s", displayVal, suffix)
    end
end

-- ============================================================================
-- 序列化 / 反序列化（存档用）
-- ============================================================================

--- 转为可 JSON 序列化的 table
function M.serialize(bn)
    if not M.is(bn) then return bn end  -- 普通数字不转换
    return { _bn = 1, m = bn.m, e = bn.e }
end

--- 从序列化数据恢复 BigNum（兼容旧存档的普通数字）
function M.deserialize(val)
    if type(val) == "table" and val._bn == 1 then
        return _acquire(val.m, val.e)
    end
    -- 旧存档：普通数字
    return M.new(tonumber(val) or 0)
end

-- ============================================================================
-- 元方法绑定
-- ============================================================================

mt.__add = add
mt.__sub = sub
mt.__mul = mul
mt.__div = div
mt.__pow = pow
mt.__mod = mod
mt.__unm = unm
mt.__lt = lt
mt.__le = le
mt.__eq = eq

function mt:__tostring()
    return M.format(self)
end

function mt:__concat(other)
    return tostring(self) .. tostring(other)
end

-- 当 number .. BigNum 时也需要处理
-- Lua 5.4 在 concat 时会先检查左操作数的 __concat，如果左操作数是 string/number
-- 则检查右操作数的 __concat。上面的 mt.__concat 已覆盖。

-- ============================================================================
-- 猴子补丁（math.floor, math.max, math.min）
-- ============================================================================

-- 导出原始 math 函数供热路径模块使用（绕过猴子补丁的类型检查开销）
M._rawFloor = _rawFloor
M._rawMax = _rawMax
M._rawMin = _rawMin

math.floor = function(v)
    if M.is(v) then return M.floor(v) end
    return _rawFloor(v)
end

math.max = function(a, b, ...)
    -- 处理 BigNum 参与的 max
    if M.is(a) or M.is(b) then
        a = M.ensure(a)
        b = M.ensure(b)
        local result = M.cmp(a, b) >= 0 and a or b
        if select("#", ...) > 0 then
            return math.max(result, ...)
        end
        return result
    end
    -- 检查可变参数中是否有 BigNum
    local nArgs = select("#", ...)
    if nArgs > 0 then
        for i = 1, nArgs do
            if M.is(select(i, ...)) then
                a = M.ensure(a)
                b = M.ensure(b)
                local result = M.cmp(a, b) >= 0 and a or b
                return math.max(result, ...)
            end
        end
    end
    return _rawMax(a, b, ...)
end

math.min = function(a, b, ...)
    -- 处理 BigNum 参与的 min
    if M.is(a) or M.is(b) then
        a = M.ensure(a)
        b = M.ensure(b)
        local result = M.cmp(a, b) <= 0 and a or b
        if select("#", ...) > 0 then
            return math.min(result, ...)
        end
        return result
    end
    -- 检查可变参数中是否有 BigNum
    local nArgs = select("#", ...)
    if nArgs > 0 then
        for i = 1, nArgs do
            if M.is(select(i, ...)) then
                a = M.ensure(a)
                b = M.ensure(b)
                local result = M.cmp(a, b) <= 0 and a or b
                return math.min(result, ...)
            end
        end
    end
    return _rawMin(a, b, ...)
end

return M
