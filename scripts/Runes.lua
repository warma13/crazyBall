-- ============================================================================
-- Runes.lua - 符文系统（Meta 进阶层）
-- 永久升级，不随游戏重置而丢失
-- 全部符文单页可滚动显示
-- ============================================================================

local State = require("State")
local EventBus = require("EventBus")

local gameState = State.gameState
local math_floor = math.floor
local math_min = math.min
local math_max = math.max

local M = {}

-- 滚动偏移量（像素）
M.scrollY = 0

-- ============================================================================
-- 符文定义
-- ============================================================================

--[[
  消耗公式统一: floor(baseCost * rate^(lv-1))
  产出公式: 每轮 max(1, floor(0.01 * r^1.5))
           超越最高轮 100%，未超越部分 10%
]]

M.RUNE_DEFS = {
    {
        id       = "rune_time",
        name     = "时光符文",
        icon     = "image/rune_time_20260409140313.png",
        color    = { 80, 200, 255, 255 },
        baseCost = 200,
        costRate = 1.55,
        valueFunc = function(level) return level * 2 end,
        descFunc  = function(level, value)
            if level == 0 then return "每轮额外时间 +2s" end
            return string.format("每轮额外时间 +%ds", value)
        end,
    },
    {
        id       = "rune_speed",
        name     = "加速符文",
        icon     = "image/rune_speed_20260413032615.png",
        color    = { 100, 180, 255, 255 },
        baseCost = 250,
        costRate = 1.55,
        valueFunc = function(level) return math_min(0.60, level * 0.06) end,
        descFunc  = function(level, value)
            if level == 0 then return "弹珠下落加速 +6% (上限60%)" end
            return string.format("弹珠下落加速 +%d%%", math_floor(value * 100))
        end,
    },
    {
        id       = "rune_bounce",
        name     = "弹力符文",
        icon     = "image/rune_bounce_20260413032622.png",
        color    = { 80, 230, 200, 255 },
        baseCost = 300,
        costRate = 1.55,
        valueFunc = function(level) return math_min(0.35, level * 0.03) end,
        descFunc  = function(level, value)
            if level == 0 then return "弹跳能量保留 +3%" end
            return string.format("弹跳能量保留 +%d%%", math_floor(value * 100))
        end,
    },
    {
        id       = "rune_wealth",
        name     = "财富符文",
        icon     = "image/rune_wealth_20260409140511.png",
        color    = { 255, 220, 80, 255 },
        baseCost = 300,
        costRate = 1.6,
        valueFunc = function(level) return math_floor(15 * 1.5 ^ (level - 1)) end,
        descFunc  = function(level, value)
            if level == 0 then return "重置后起始金币 +15" end
            return string.format("重置后起始金币 +%d", value)
        end,
    },
    {
        id       = "rune_value",
        name     = "增值符文",
        icon     = "image/rune_value_20260413032620.png",
        color    = { 255, 200, 60, 255 },
        baseCost = 120,
        costRate = 1.55,
        -- 线性增长: +8%/级
        valueFunc = function(level) return level * 0.08 end,
        descFunc  = function(level, value)
            if level == 0 then return "全部球基础价值 +8%" end
            return string.format("全部球基础价值 +%d%%", math_floor(value * 100))
        end,
    },
    {
        id       = "rune_slot",
        name     = "口袋符文",
        icon     = "image/rune_slot_20260413032621.png",
        color    = { 255, 180, 60, 255 },
        baseCost = 120,
        costRate = 1.55,
        -- 线性增长: +5%/级
        valueFunc = function(level) return level * 0.05 end,
        descFunc  = function(level, value)
            if level == 0 then return "口袋倍率 +5%" end
            return string.format("口袋倍率 +%d%%", math_floor(value * 100))
        end,
    },
    {
        id       = "rune_tenacity",
        name     = "坚韧符文",
        icon     = "image/rune_tenacity_20260409140304.png",
        color    = { 60, 220, 140, 255 },
        baseCost = 500,
        costRate = 1.65,
        valueFunc = function(level) return math_min(0.9, 1 - 0.85 ^ level) end,
        descFunc  = function(level, value)
            if level == 0 then return "轮次目标 -15%" end
            return string.format("轮次目标 -%d%%", math_floor(value * 100 + 0.5))
        end,
    },
    {
        id       = "rune_essence",
        name     = "精粹符文",
        icon     = "image/rune_essence_20260409140302.png",
        color    = { 180, 80, 255, 255 },
        baseCost = 100,
        costRate = 1.55,
        -- 线性增长: +10%/级
        valueFunc = function(level) return level * 0.10 end,
        descFunc  = function(level, value)
            if level == 0 then return "精粹获取 +10%" end
            return string.format("精粹获取 +%d%%", math_floor(value * 100))
        end,
    },
    {
        id       = "rune_luck",
        name     = "幸运符文",
        icon     = "image/rune_luck_20260413032612.png",
        color    = { 100, 220, 120, 255 },
        baseCost = 600,
        costRate = 1.7,
        valueFunc = function(level) return math_floor(level / 4) end,
        descFunc  = function(level, value)
            if level == 0 then return "抽取效果初始等级 +1 (4级)" end
            if value == 0 then
                return string.format("再升%d级 → 效果初始+1", 4 - (level % 4))
            end
            local nextAt = 4 - (level % 4)
            if level % 4 == 0 then
                return string.format("抽取效果初始等级 +%d", value)
            end
            return string.format("效果初始+%d (再升%d级+1)", value, nextAt)
        end,
    },
    {
        id       = "rune_crit",
        name     = "暴击符文",
        icon     = "image/rune_crit_20260413032619.png",
        color    = { 255, 100, 80, 255 },
        baseCost = 450,
        costRate = 1.6,
        valueFunc = function(level) return math_min(0.30, level * 0.015) end,
        descFunc  = function(level, value)
            if level == 0 then return "全局暴击概率 +1.5%" end
            return string.format("全局暴击概率 +%.1f%%", value * 100)
        end,
    },
}

-- 缓存: id -> config
local _configCache = {}

-- ============================================================================
-- 访问器
-- ============================================================================

--- 查找符文配置（带缓存）
local function FindRuneConfig(runeId)
    if _configCache[runeId] then return _configCache[runeId] end
    for _, def in ipairs(M.RUNE_DEFS) do
        if def.id == runeId then
            _configCache[runeId] = def
            return def
        end
    end
    return nil
end

--- 获取符文等级
---@param runeId string
---@return number
function M.GetRuneLevel(runeId)
    return gameState.runeLevels[runeId] or 0
end

--- 获取符文当前效果值（level==0 返回 0）
---@param runeId string
---@return number
function M.GetRuneValue(runeId)
    local level = M.GetRuneLevel(runeId)
    if level == 0 then return 0 end
    local cfg = FindRuneConfig(runeId)
    if not cfg then return 0 end
    return cfg.valueFunc(level)
end

--- 获取升级到下一级的费用
---@param runeId string
---@return number
function M.GetUpgradeCost(runeId)
    local cfg = FindRuneConfig(runeId)
    if not cfg then return 999999 end
    local nextLevel = M.GetRuneLevel(runeId) + 1
    return math_floor(cfg.baseCost * cfg.costRate ^ (nextLevel - 1))
end

--- 尝试升级符文
---@param runeId string
---@return boolean 是否成功
function M.UpgradeRune(runeId)
    local cost = M.GetUpgradeCost(runeId)
    if gameState.runeEssence < cost then return false end

    gameState.runeEssence = gameState.runeEssence - cost
    gameState.runeLevels[runeId] = M.GetRuneLevel(runeId) + 1

    print(string.format("[Rune] Upgraded %s to level %d, cost=%d, remaining=%d",
        runeId, gameState.runeLevels[runeId], cost, gameState.runeEssence))

    EventBus.emit("rune_upgraded", { id = runeId })
    return true
end

-- ============================================================================
-- 精粹产出
-- ============================================================================

local function BaseEssencePerRound(r)
    return math_max(1, math_floor(0.01 * r ^ 1.5))
end

--- 预览精粹奖励（不修改 bestRound）
function M.PreviewEssenceReward(roundNum)
    local bestRound = gameState.bestRound or 0
    local beyondBest = 0
    local belowBest = 0
    for r = 1, roundNum do
        local base = BaseEssencePerRound(r)
        if r <= bestRound then
            belowBest = belowBest + base
        else
            beyondBest = beyondBest + base
        end
    end
    local rawTotal = beyondBest + math_max(1, math_floor(belowBest * 0.1))
    local essenceBonus = M.GetRuneValue("rune_essence")
    return math_floor(rawTotal * (1 + essenceBonus))
end

function M.CalcEssenceReward(roundNum)
    local bestRound = gameState.bestRound or 0

    local beyondBest = 0
    local belowBest = 0

    for r = 1, roundNum do
        local base = BaseEssencePerRound(r)
        if r <= bestRound then
            belowBest = belowBest + base
        else
            beyondBest = beyondBest + base
        end
    end

    local rawTotal = beyondBest + math_max(1, math_floor(belowBest * 0.1))

    local essenceBonus = M.GetRuneValue("rune_essence")
    local finalTotal = math_floor(rawTotal * (1 + essenceBonus))

    if roundNum > bestRound then
        gameState.bestRound = roundNum
        print(string.format("[Rune] New best round: %d (was %d)", roundNum, bestRound))
    end

    return finalTotal
end

return M
