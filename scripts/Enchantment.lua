-- ============================================================================
-- Enchantment.lua - 附魔系统核心模块
-- 附魔可叠加（同球多种附魔），重复抽到同一附魔则升级。
-- 每次附魔需观看一次广告，随机从附魔池中获得一个。
-- 本局有效，新游戏重置。
-- ============================================================================

local Config = require("Config")
local State = require("State")
local EventBus = require("EventBus")
local AdHelper = require("AdHelper")
local SaveSystem = require("SaveSystem")
---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local gameState = State.gameState

local M = {}

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 获取指定球的全部附魔 { [enchantId] = level }（不存在则返回空表）
---@param ballIndex number
---@return table
function M.GetAll(ballIndex)
    return gameState.ballEnchantments[ballIndex] or {}
end

--- 获取指定球的某附魔等级（0 = 未拥有）
---@param ballIndex number
---@param enchantId string
---@return number
function M.GetLevel(ballIndex, enchantId)
    local map = gameState.ballEnchantments[ballIndex]
    return map and map[enchantId] or 0
end

--- 获取指定球的某附魔实际数值
--- add: baseValue * level, mul: 1 - (1 - baseValue)^level
---@param ballIndex number
---@param enchantId string
---@return number
function M.GetValue(ballIndex, enchantId)
    local level = M.GetLevel(ballIndex, enchantId)
    if level <= 0 then return 0 end
    local cfg = Config.GetEnchantConfig(enchantId)
    if not cfg then return 0 end
    if cfg.stacking == "add" then
        return cfg.baseValue * level
    else  -- "mul"
        return 1 - (1 - cfg.baseValue) ^ level
    end
end

--- 获取指定球的附魔总条数
---@param ballIndex number
---@return number
function M.GetCount(ballIndex)
    local map = gameState.ballEnchantments[ballIndex]
    if not map then return 0 end
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

--- 获取指定球的附魔总等级数（所有附魔等级之和）
---@param ballIndex number
---@return number
function M.GetTotalLevel(ballIndex)
    local map = gameState.ballEnchantments[ballIndex]
    if not map then return 0 end
    local total = 0
    for _, lv in pairs(map) do total = total + lv end
    return total
end

-- ============================================================================
-- 广告附魔
-- ============================================================================

--- 通过广告为当前选中球附魔（异步回调）
function M.AdEnchant()
    local ballIndex = gameState.selectedBallType
    local level = gameState.ballLevels[ballIndex]
    if level == 0 then return end  -- 未解锁的球不能附魔

    AdHelper.ShowRewardAd(function(result)
        if result.success then
            -- 随机选一种附魔
            local pool = Config.ENCHANTMENTS
            local chosen = pool[math.random(1, #pool)]

            -- 确保 map 存在
            if not gameState.ballEnchantments[ballIndex] then
                gameState.ballEnchantments[ballIndex] = {}
            end
            local map = gameState.ballEnchantments[ballIndex]

            -- 已有则升级，否则新增
            local oldLevel = map[chosen.id] or 0
            map[chosen.id] = oldLevel + 1
            local isUpgrade = oldLevel > 0

            EventBus.emit("enchant_changed", {
                ballIndex = ballIndex,
                enchant = chosen,
                newLevel = oldLevel + 1,
                isUpgrade = isUpgrade,
            })
            -- 附魔后立刻保存，防止丢失
            SaveSystem.Save()
            SaveSystem.Flush()
        end
    end)
end

return M
