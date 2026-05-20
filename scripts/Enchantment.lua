-- ============================================================================
-- Enchantment.lua - 附魔系统核心模块
-- 附魔全局生效（不绑定具体球），重复抽到同一附魔则升级。
-- 每次附魔需观看一次广告，随机从附魔池中获得一个。
-- 转生时重置。
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

--- 获取全部附魔 { [enchantId] = level }（不存在则返回空表）
---@return table
function M.GetAll()
    return gameState.idleEnchantments or {}
end

--- 获取某附魔等级（0 = 未拥有）
---@param enchantId string
---@return number
function M.GetLevel(enchantId)
    return (gameState.idleEnchantments or {})[enchantId] or 0
end

--- 获取某附魔实际数值
--- add: baseValue * level, mul: 1 - (1 - baseValue)^level
---@param enchantId string
---@return number
function M.GetValue(enchantId)
    local level = M.GetLevel(enchantId)
    if level <= 0 then return 0 end
    local cfg = Config.GetEnchantConfig(enchantId)
    if not cfg then return 0 end
    if cfg.stacking == "add" then
        return cfg.baseValue * level
    else  -- "mul"
        return 1 - (1 - cfg.baseValue) ^ level
    end
end

--- 获取附魔总条数
---@return number
function M.GetCount()
    local map = gameState.idleEnchantments
    if not map then return 0 end
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    return n
end

--- 获取附魔总等级数（所有附魔等级之和）
---@return number
function M.GetTotalLevel()
    local map = gameState.idleEnchantments
    if not map then return 0 end
    local total = 0
    for _, lv in pairs(map) do total = total + lv end
    return total
end

-- ============================================================================
-- 广告附魔
-- ============================================================================

--- 通过广告附魔（异步回调）
function M.AdEnchant()
    AdHelper.ShowRewardAd(function(result)
        if result.success then
            -- 随机选一种附魔
            local pool = Config.ENCHANTMENTS
            local chosen = pool[math.random(1, #pool)]

            -- 确保 map 存在
            if not gameState.idleEnchantments then
                gameState.idleEnchantments = {}
            end
            local map = gameState.idleEnchantments

            -- 已有则升级，否则新增
            local oldLevel = map[chosen.id] or 0
            map[chosen.id] = oldLevel + 1
            local isUpgrade = oldLevel > 0

            EventBus.emit("enchant_changed", {
                enchant = chosen,
                newLevel = oldLevel + 1,
                isUpgrade = isUpgrade,
            })
            -- 附魔后保存（30s 节流写入云端）
            SaveSystem.Save()
        end
    end)
end

return M
