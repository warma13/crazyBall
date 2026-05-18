-- ============================================================================
-- Slots.lua - 坑位管理逻辑（无限升级版）
-- ============================================================================

local Config = require("Config")
local State = require("State")
local EventBus = require("EventBus")

local CONFIG = Config.CONFIG
local gameState = State.gameState

---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local M = {}

--- 获取口袋的倍率值（从 level 计算）
function M.GetSlotMult(slot)
    local level = slot.level or 1
    return Config.GetSlotMult(level)
end

--- 获取坑位显示颜色
function M.GetSlotColor(slot)
    return Config.GetMultColor(M.GetSlotMult(slot))
end

--- 获取坑位显示文字
function M.GetSlotLabel(slot)
    return "x" .. State.FormatNumber(M.GetSlotMult(slot))
end

--- 随机生成一个新坑位（初始等级由随机池决定）
function M.GenerateRandomSlot()
    local pool = { 1, 1, 2, 2, 3, 4, 5 }
    local level = pool[math.random(1, #pool)]
    return { kind = "good", level = level }
end

--- 获取解锁下一个坑位的费用（nil 表示已满）
function M.GetSlotUnlockCost()
    local nextCount = #gameState.slots + 1
    return Config.SLOT_UNLOCK_COSTS[nextCount]
end

--- 解锁新坑位
function M.UnlockNewSlot()
    local cost = M.GetSlotUnlockCost()
    if not cost then return end
    if gameState.coins < cost then return end

    gameState.coins = gameState.coins - cost
    local newSlot = M.GenerateRandomSlot()
    table.insert(gameState.slots, newSlot)

    local label = M.GetSlotLabel(newSlot)
    print("Unlocked new slot: " .. label)

    EventBus.emit("slot_added")
end

--- 获取口袋当前等级
function M.GetSlotLevel(slot)
    return slot.level or 1
end

--- 获取口袋升级费用
function M.GetSlotUpgradeCost(slot)
    local level = slot.level or 1
    return Config.GetSlotUpgradeCost(level)
end

--- 升级口袋（无限可升）
function M.UpgradeSlot(slotIndex)
    local slot = gameState.slots[slotIndex]
    if not slot then return end

    local level = slot.level or 1
    local cost = Config.GetSlotUpgradeCost(level)
    if gameState.coins < cost then return end

    gameState.coins = gameState.coins - cost
    slot.level = level + 1
    EventBus.emit("slot_changed", { index = slotIndex })
end

--- 广告升级口袋（不扣金币）
function M.AdUpgradeSlot(slotIndex)
    local slot = gameState.slots[slotIndex]
    if not slot then return end
    gameState.paused = true
    sdk:ShowRewardVideoAd(function(result)
        gameState.paused = false
        if result.success then
            slot.level = (slot.level or 1) + 1
            EventBus.emit("slot_changed", { index = slotIndex })
            EventBus.emit("save_trigger")
        end
    end)
end

--- 一键升级所有口袋（轮流升级，尽量均匀）
--- @return number 总升级次数
function M.BulkUpgradeSlots()
    local count = 0
    local upgraded = true
    while upgraded do
        upgraded = false
        for i = 1, #gameState.slots do
            local slot = gameState.slots[i]
            local cost = Config.GetSlotUpgradeCost(slot.level or 1)
            if gameState.coins >= cost then
                gameState.coins = gameState.coins - cost
                slot.level = (slot.level or 1) + 1
                count = count + 1
                upgraded = true
            end
        end
    end

    if count > 0 then
        EventBus.emit("slot_changed", { index = 1 })
        EventBus.emit("save_trigger")
    end
    return count
end

return M
