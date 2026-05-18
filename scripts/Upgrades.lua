-- ============================================================================
-- Upgrades.lua - 升级逻辑
-- ============================================================================

local Config = require("Config")
local BigNum = require("BigNum")
local State = require("State")
local EventBus = require("EventBus")
local Runes = require("Runes")
local Enchantment = require("Enchantment")
---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local gameState = State.gameState

local M = {}

-- ============================================================================
-- 每帧缓存：避免热路径上重复调用 GetEffectLevel/GetEffectValue
-- 使用代计数器（generation counter）替代每帧遍历清空：
--   BeginFrame() 只需 +1 代号，命中时检查代号是否当前代
--   缓存未命中时写入新值 + 当前代号
-- ============================================================================
local _frameLevelCache = {}    -- { [effectId] = level }
local _frameLevelGen = {}      -- { [effectId] = generation }
local _frameValueCache = {}    -- { [effectId] = value }
local _frameValueGen = {}      -- { [effectId] = generation }
local _frameGeneration = 0     -- 当前帧代号
local _frameCacheValid = false

--- 每帧开始时调用，递增代号（O(1) 替代 O(n) 遍历清空）
function M.BeginFrame()
    _frameGeneration = _frameGeneration + 1
    _frameCacheValid = true
end

--- 获取当前帧代号（供外部模块按帧缓存使用）
---@return number 当前帧代号
function M.GetFrameGeneration()
    return _frameGeneration
end

--- 计算钢珠升级费用（返回 BigNum）
function M.GetBallUpgradeCost(index)
    local bt = Config.BALL_TYPES[index]
    local level = gameState.ballLevels[index]
    if level == 0 then return BigNum.new(bt.cost) end
    local base = math.max(bt.cost, 8)
    local cost = math.floor(BigNum.new(base) * BigNum.new(1.4) ^ (level - 1))
    -- 附魔折扣（upgrade_discount: 乘算，每级-5%）
    local discount = Enchantment.GetValue(index, "upgrade_discount")
    if discount > 0 then
        cost = math.floor(cost * (1 - discount))
        if cost < 1 then cost = BigNum.new(1) end
    end
    return cost
end

--- 钢珠按钮点击（选择/解锁/升级）
function M.OnBallButtonClick(index)
    local level = gameState.ballLevels[index]
    local cost = M.GetBallUpgradeCost(index)
    local prevSelected = gameState.selectedBallType
    local coinsSpent = false

    if level == 0 then
        if gameState.coins >= cost then
            gameState.coins = gameState.coins - cost
            gameState.ballLevels[index] = 1
            gameState.selectedBallType = index
            coinsSpent = true
        else
            return
        end
    elseif index == gameState.selectedBallType then
        if gameState.coins >= cost then
            gameState.coins = gameState.coins - cost
            gameState.ballLevels[index] = level + 1
            coinsSpent = true
        else
            return
        end
    else
        gameState.selectedBallType = index
    end

    EventBus.emit("ball_changed", { index = index, prevSelected = prevSelected, coinsSpent = coinsSpent })
    if coinsSpent then
        EventBus.emit("save_trigger")
    end
end



--- 广告解锁/升级球（不扣金币，需顺序解锁）
function M.AdBallUpgrade(index)
    local level = gameState.ballLevels[index]
    -- 顺序解锁检查：前一个球必须已解锁
    if level == 0 and index > 1 and gameState.ballLevels[index - 1] == 0 then
        return
    end
    gameState.paused = true
    sdk:ShowRewardVideoAd(function(result)
        gameState.paused = false
        if result.success then
            local prevSelected = gameState.selectedBallType
            if gameState.ballLevels[index] == 0 then
                gameState.ballLevels[index] = 1
                gameState.selectedBallType = index
            else
                gameState.ballLevels[index] = gameState.ballLevels[index] + 1
            end
            EventBus.emit("ball_changed", { index = index, prevSelected = prevSelected, coinsSpent = false })
            EventBus.emit("save_trigger")
        end
    end)
end

--- 广告升级效果（不扣宝石）
function M.AdUpgradeEffect(effectId)
    local level = M.GetEffectLevel(effectId)
    if level == 0 then return end
    gameState.paused = true
    sdk:ShowRewardVideoAd(function(result)
        gameState.paused = false
        if result.success then
            gameState.drawnEffects[effectId] = (gameState.drawnEffects[effectId] or 0) + 1
            EventBus.emit("effect_upgraded", { id = effectId })
            EventBus.emit("save_trigger")
        end
    end)
end

--- 广告抽取效果（不扣宝石，使用普通池）
function M.AdDrawEffect()
    local pool = M.BuildNormalPool()
    if #pool == 0 then return end
    gameState.paused = true
    sdk:ShowRewardVideoAd(function(result)
        gameState.paused = false
        if result.success then
            local freshPool = M.BuildNormalPool()
            if #freshPool == 0 then return end
            -- 使用与普通抽取相同的加权随机逻辑
            local totalWeight = 0
            for _, e in ipairs(freshPool) do
                local tier = Config.GetQualityTier(e.quality or "common")
                totalWeight = totalWeight + (tier and tier.weight or 1)
            end
            local roll = math.random() * totalWeight
            local acc = 0
            local chosen = freshPool[1]
            for _, e in ipairs(freshPool) do
                local tier = Config.GetQualityTier(e.quality or "common")
                acc = acc + (tier and tier.weight or 1)
                if roll <= acc then chosen = e; break end
            end
            -- 符文幸运加成（rune_luck: 每4级初始等级+1）
            local initLevel = 1 + Runes.GetRuneValue("rune_luck")
            gameState.drawnEffects[chosen.id] = initLevel
            gameState.drawCount = gameState.drawCount + 1
            EventBus.emit("effect_drawn", { id = chosen.id, quality = chosen.quality })
            EventBus.emit("save_trigger")
        end
    end)
end

--- 获取当前抽取费用
function M.GetDrawCost()
    return math.floor(Config.DRAW_COST * (Config.DRAW_COST_MULTIPLIER ^ gameState.drawCount))
end

--- 检查某效果是否已拥有
function M.HasEffect(effectId)
    return (gameState.drawnEffects[effectId] or 0) >= 1
end

--- 获取某效果当前等级（0 = 未拥有），带帧缓存（代计数器版）
function M.GetEffectLevel(effectId)
    if _frameCacheValid and _frameLevelGen[effectId] == _frameGeneration then
        return _frameLevelCache[effectId]
    end
    local val = gameState.drawnEffects[effectId] or 0
    if _frameCacheValid then
        _frameLevelCache[effectId] = val
        _frameLevelGen[effectId] = _frameGeneration
    end
    return val
end

--- 通过 id 查找效果配置（带缓存，避免每次线性查找）
local effectConfigCache = {}
function M.FindEffectConfig(effectId)
    local cached = effectConfigCache[effectId]
    if cached ~= nil then return cached end
    for _, eff in ipairs(Config.DRAW_EFFECTS) do
        if eff.id == effectId then
            effectConfigCache[effectId] = eff
            return eff
        end
    end
    effectConfigCache[effectId] = false  -- 标记不存在，避免重复遍历
    return nil
end

--- 获取某效果当前等级的数值，带帧缓存（代计数器版）
function M.GetEffectValue(effectId)
    if _frameCacheValid and _frameValueGen[effectId] == _frameGeneration then
        return _frameValueCache[effectId]
    end
    local level = M.GetEffectLevel(effectId)
    local val
    if level == 0 then
        val = 0
    else
        local cfg = M.FindEffectConfig(effectId)
        val = cfg and cfg.valueFunc(level) or 0
    end
    if _frameCacheValid then
        _frameValueCache[effectId] = val
        _frameValueGen[effectId] = _frameGeneration
    end
    return val
end

--- 获取效果升级费用（无限升级，永远可升）
function M.GetEffectUpgradeCost(effectId)
    local level = M.GetEffectLevel(effectId)
    if level == 0 then return nil end
    local cfg = M.FindEffectConfig(effectId)
    if not cfg then return nil end
    return cfg.costFunc(level)
end

--- 升级某个已拥有的效果
function M.OnUpgradeEffect(effectId)
    local level = M.GetEffectLevel(effectId)
    if level == 0 then return false end

    local cfg = M.FindEffectConfig(effectId)
    if not cfg then return false end

    local cost = cfg.costFunc(level)
    if State.GetGems() < cost then return false end

    State.SpendGems(cost)
    gameState.drawnEffects[effectId] = level + 1

    EventBus.emit("effect_upgraded", { id = effectId })
    EventBus.emit("save_trigger")
    return true
end

--- 构建普通池（排除 mythic + 已拥有 + requires 未满足）
function M.BuildNormalPool()
    local pool = {}
    for _, eff in ipairs(Config.DRAW_EFFECTS) do
        if eff.quality ~= "mythic" and not M.HasEffect(eff.id) then
            if not eff.requires or M.HasEffect(eff.requires) then
                table.insert(pool, eff)
            end
        end
    end
    return pool
end

--- 构建广告池（仅 mythic + 排除已拥有）
function M.BuildAdPool()
    local pool = {}
    for _, eff in ipairs(Config.DRAW_EFFECTS) do
        if eff.quality == "mythic" and not M.HasEffect(eff.id) then
            table.insert(pool, eff)
        end
    end
    return pool
end

--- 普通池效果总数（不含 mythic）
function M.GetNormalPoolTotal()
    local count = 0
    for _, eff in ipairs(Config.DRAW_EFFECTS) do
        if eff.quality ~= "mythic" then count = count + 1 end
    end
    return count
end

--- 已拥有的非 mythic 效果数
function M.GetNormalPoolOwned()
    local count = 0
    for _, eff in ipairs(Config.DRAW_EFFECTS) do
        if eff.quality ~= "mythic" and M.HasEffect(eff.id) then
            count = count + 1
        end
    end
    return count
end

--- 是否可以进行广告抽取（无限次，直到广告池抽空）
function M.CanAdDraw()
    return #M.BuildAdPool() > 0
end

--- 加权随机抽取（普通池，宝石消耗）
function M.OnDrawEffect()
    local normalPool = M.BuildNormalPool()
    if #normalPool == 0 then return nil end

    local cost = M.GetDrawCost()
    if State.GetGems() < cost then return nil end

    State.SpendGems(cost)
    gameState.drawCount = gameState.drawCount + 1

    -- 按品质分组
    local qualityPools = {}
    for _, eff in ipairs(normalPool) do
        local q = eff.quality or "common"
        if not qualityPools[q] then qualityPools[q] = {} end
        table.insert(qualityPools[q], eff)
    end

    -- 检查保底：连续 PITY_THRESHOLD 次未出 epic+
    local forcePity = gameState.pityCounter >= Config.PITY_THRESHOLD

    local chosenQuality
    if forcePity then
        -- 保底：强制 epic 或更高
        local pityQualities = {}
        for _, q in ipairs({ "legend", "epic" }) do
            if qualityPools[q] and #qualityPools[q] > 0 then
                table.insert(pityQualities, q)
            end
        end
        if #pityQualities > 0 then
            chosenQuality = pityQualities[math.random(1, #pityQualities)]
        end
    end

    if not chosenQuality then
        -- 正常加权随机选品质
        local candidates = {}
        local totalWeight = 0
        for _, q in ipairs({ "common", "rare", "epic", "legend" }) do
            if qualityPools[q] and #qualityPools[q] > 0 then
                local tier = Config.GetQualityTier(q)
                table.insert(candidates, { quality = q, weight = tier.weight })
                totalWeight = totalWeight + tier.weight
            end
        end
        if #candidates == 0 then return nil end

        local roll = math.random() * totalWeight
        local acc = 0
        for _, c in ipairs(candidates) do
            acc = acc + c.weight
            if roll <= acc then
                chosenQuality = c.quality
                break
            end
        end
        if not chosenQuality then
            chosenQuality = candidates[#candidates].quality
        end
    end

    -- 从选中品质的池中随机选一个效果
    local qPool = qualityPools[chosenQuality]
    local chosen = qPool[math.random(1, #qPool)]
    -- 符文幸运加成（rune_luck: 每4级初始等级+1）
    gameState.drawnEffects[chosen.id] = 1 + Runes.GetRuneValue("rune_luck")

    -- 更新保底计数器
    if chosenQuality == "epic" or chosenQuality == "legend" then
        gameState.pityCounter = 0
    else
        gameState.pityCounter = gameState.pityCounter + 1
    end

    local val = chosen.valueFunc(1)
    local tier = Config.GetQualityTier(chosenQuality)
    print("Drew [" .. tier.name .. "] " .. chosen.name .. " - " .. chosen.descFunc(1, val))

    EventBus.emit("effect_drawn", { id = chosen.id, quality = chosenQuality })
    EventBus.emit("save_trigger")
    return chosen
end

--- 广告抽取（传说池）
function M.OnAdDrawEffect()
    if not M.CanAdDraw() then return nil end

    local adPool = M.BuildAdPool()
    if #adPool == 0 then return nil end

    -- 调用广告 SDK
    gameState.paused = true
    sdk:ShowRewardVideoAd(function(result)
        gameState.paused = false
        if result.success then
            -- 重新获取池（防止异步期间状态变化）
            local pool = M.BuildAdPool()
            if #pool == 0 then return end

            local chosen = pool[math.random(1, #pool)]
            -- 符文幸运加成（rune_luck: 每4级初始等级+1）
            local initLevel = 1 + Runes.GetRuneValue("rune_luck")
            gameState.drawnEffects[chosen.id] = initLevel

            local val = chosen.valueFunc(initLevel)
            print("Ad drew [传说] " .. chosen.name .. " - " .. chosen.descFunc(initLevel, val))

            EventBus.emit("effect_drawn", { id = chosen.id, quality = "mythic" })
            EventBus.emit("save_trigger")
        else
            print("[Ad] Reward video failed: " .. tostring(result.msg))
        end
    end)

    return true  -- 表示广告已发起（实际结果异步回调）
end

--- 一键升级当前选中的钢珠（花光金币）
--- @return number 升级次数
function M.BulkUpgradeBall()
    local index = gameState.selectedBallType
    local level = gameState.ballLevels[index]
    if level == 0 then return 0 end

    local count = 0
    while true do
        local cost = M.GetBallUpgradeCost(index)
        if gameState.coins < cost then break end
        gameState.coins = gameState.coins - cost
        gameState.ballLevels[index] = gameState.ballLevels[index] + 1
        count = count + 1
    end

    if count > 0 then
        EventBus.emit("ball_changed", { index = index, coinsSpent = true })
        EventBus.emit("save_trigger")
    end
    return count
end

--- 统计已拥有的效果总数
function M.GetOwnedEffectCount()
    local count = 0
    for _, _ in pairs(gameState.drawnEffects) do
        count = count + 1
    end
    return count
end

return M
