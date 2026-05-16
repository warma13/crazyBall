-- ============================================================================
-- BallEffects.lua - 球效果计算管线
--
-- 统一公式模板（两层六槽位）：
--   内层 = base × (1+Σ加算基础) × Π(1+乘算基础_i) × Π直乘基础_i + 额外基础
--   最终 = 内层 × (1+Σ加算最终) × Π(1+乘算最终_i) × Π直乘最终_i
--
-- 效果只需声明属于哪个槽位，公式引擎统一计算。
-- Physics.lua 调用本模块获取球属性和物理参数，不直接访问效果配置。
-- ============================================================================

local Config = require("Config")
local BigNum = require("BigNum")
local State = require("State")
local Slots = require("Slots")
local Upgrades = require("Upgrades")
local Runes = require("Runes")
local Enchantment = require("Enchantment")

local CONFIG = Config.CONFIG
local gameState = State.gameState

-- 使用原始 math 函数绕过 BigNum 猴子补丁（热路径不涉及 BigNum 参数）
local math_floor = BigNum._rawFloor
local math_max = BigNum._rawMax
local math_min = BigNum._rawMin
local math_abs = math.abs
local math_random = math.random

local M = {}

-- ============================================================================
-- 公式引擎
-- ============================================================================

--- 统一计算公式
---@param base number 基础值
---@param slots table 槽位表
---@return number 计算结果（未取整）
---
--- slots 结构（所有字段可选，缺省为不修改）:
---   addBase     number     加算基础（多个效果先求和，再 ×(1+sum) 一次）
---   multBase    {number}   乘算基础（各自独立 ×(1+v)）
---   directBase  {number}   直乘基础（各自独立 ×v）
---   flatExtra   number     额外基础（加法，内层末尾）
---   addFinal    number     加算最终
---   multFinal   {number}   乘算最终
---   directFinal {number}   直乘最终
local function calcFormula(base, slots)
    -- 内层
    local val = base
    if slots.addBase and slots.addBase ~= 0 then
        val = val * (1 + slots.addBase)
    end
    if slots.multBase then
        for _, v in ipairs(slots.multBase) do
            val = val * (1 + v)
        end
    end
    if slots.directBase then
        for _, v in ipairs(slots.directBase) do
            val = val * v
        end
    end
    if slots.flatExtra and slots.flatExtra ~= 0 then
        val = val + slots.flatExtra
    end
    -- 外层
    if slots.addFinal and slots.addFinal ~= 0 then
        val = val * (1 + slots.addFinal)
    end
    if slots.multFinal then
        for _, v in ipairs(slots.multFinal) do
            val = val * (1 + v)
        end
    end
    if slots.directFinal then
        for _, v in ipairs(slots.directFinal) do
            val = val * v
        end
    end
    return val
end

--- 辅助：求和多个效果值（用于加算槽位）
---@return number 所有效果值之和
local function sumEffects(...)
    local sum = 0
    for i = 1, select("#", ...) do
        local val = Upgrades.GetEffectValue(select(i, ...))
        if val > 0 then sum = sum + val end
    end
    return sum
end

--- 辅助：收集多个效果值到静态列表（用于乘算槽位，复用表避免每调用分配）
local _listBuf = {}
---@return table|nil 非空列表或 nil（注意：返回的表会被下次调用覆盖）
local function listEffects(...)
    local n = 0
    for i = 1, select("#", ...) do
        local val = Upgrades.GetEffectValue(select(i, ...))
        if val > 0 then
            n = n + 1
            _listBuf[n] = val
        end
    end
    for i = n + 1, #_listBuf do _listBuf[i] = nil end
    return n > 0 and _listBuf or nil
end

--- 静态 slots 表（calcFormula 参数复用，避免每次调用 GetBallValue/GetGravity 等分配新表）
local _staticSlots = {}
local _staticSlots2 = {}  -- GetLandingMult 专用
local _listBuf2 = {}      -- GetLandingMult 的 multBase 专用

-- ============================================================================
-- 球创建属性（供 Physics.DropBall / DropSkyBall 使用）
-- ============================================================================

--- 计算球的实际价值
--- base = baseValue × 里程碑倍率 × level
--- 里程碑: 每4级触发一次, 倍率 = 4^floor(level/4)
--- 加算基础: multi_value
--- 额外基础: ball_polish（弹珠打磨，固定加值）
--- 加算最终: ball_refine（弹珠精炼，百分比最终加成）
---@param typeIndex number 球类型索引
---@param level number 球等级
---@return number 实际价值（取整）
function M.GetBallValue(typeIndex, level)
    local milestones = math_floor(level / 8)
    local milestoneMult = (milestones > 0) and (BigNum.new(2) ^ milestones) or BigNum.new(1)
    local base = BigNum.new(Config.BALL_TYPES[typeIndex].baseValue) * milestoneMult * level
    -- calcFormula 返回 BigNum，需要用被补丁过的 math.floor 来处理
    -- 符文增值加成（rune_value: 全部球基础价值+8%/级）
    -- 附魔增值加成（ball_value: 加算，每级+100%）
    local addBaseVal = sumEffects("multi_value") + Runes.GetRuneValue("rune_value")
        + Enchantment.GetValue(typeIndex, "ball_value")
    local result = math.floor(calcFormula(base, {
        addBase = addBaseVal,
        flatExtra = sumEffects("ball_polish"),
        addFinal = sumEffects("ball_refine"),
    }))
    -- 小数值降级为原生 number（≤1e15），下游全程原生算术，零 BigNum 开销
    return BigNum.compact(result)
end

--- 计算铁球坚韧加成（撞钉越多价值越高）
--- 每 hitScale 次撞钉 +bonusPct 球价值，铁球强化降低间隔并增加效果
---@param ball table 球对象
---@return number 坚韧倍率（>=1.0）
function M.GetSturdyMult(ball)
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect
    if not eff or eff.id ~= "sturdy" then return 1.0 end

    local hits = ball.pegHits or 0
    if hits <= 0 then return 1.0 end

    local ironBoostVal = Upgrades.GetEffectValue("iron_boost")
    -- 铁球强化降低间隔：每级 -1 钉（最低 2）
    local ironBoostLv = Upgrades.GetEffectLevel("iron_boost")
    local interval = math_max(2, eff.hitScale - ironBoostLv)
    -- 铁球强化增加效果
    local bonusPct = eff.bonusPct * (1 + ironBoostVal)

    local stacks = math_floor(hits / interval)
    return 1.0 + bonusPct * stacks
end

--- 计算球的实际半径
--- base = BALL_RADIUS（固定，不再有增大效果）
---@return number 实际半径
function M.GetBallRadius()
    local bs = gameState.boardScale or 1
    return CONFIG.BALL_RADIUS * bs
end

-- ============================================================================
-- 每帧物理修改（供 Physics.UpdateBalls 使用）
-- ============================================================================

-- 帧级缓存：按球类型缓存 gravity/damping（非 tempo 球同类型值相同）
local _gravityCache = {}       -- { [typeIndex] = gravity }
local _gravityCacheGen = 0     -- 当前帧代数
local _dampingCache = {}       -- { [typeIndex] = damping }
local _dampingCacheGen = 0

--- 计算球的实际重力
--- base = GRAVITY
--- 加算基础: speed_up
--- 乘算基础: impact(陨石球 gravityMult), tempo(琥珀球随时间加速)
---@param ball table 球对象
---@return number 实际重力加速度
function M.GetGravity(ball)
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect

    -- 符文加速加成（rune_speed: 重力+6%/级）
    local runeSpeedBonus = Runes.GetRuneValue("rune_speed")

    -- tempo 球需要逐球计算（依赖 aliveTime），不走缓存
    if eff and eff.id == "tempo" then
        local slots = _staticSlots
        slots.addBase = sumEffects("speed_up") + runeSpeedBonus
        slots.multBase = nil
        slots.directBase = nil
        slots.flatExtra = nil
        slots.addFinal = nil
        slots.multFinal = nil
        slots.directFinal = nil

        local aliveTime = ball.aliveTime or 0
        local speedGrowth = eff.speedGrowth
        local amberBoostVal = Upgrades.GetEffectValue("amber_boost")
        speedGrowth = speedGrowth * (1 + amberBoostVal)
        local tempoMult = speedGrowth * aliveTime
        _listBuf[1] = tempoMult
        for i = 2, #_listBuf do _listBuf[i] = nil end
        slots.multBase = _listBuf
        ball.tempoSpeedBonus = tempoMult
        return calcFormula(CONFIG.GRAVITY * (gameState.boardScale or 1), slots)
    end

    -- 非 tempo 球：同类型值相同，使用帧级缓存
    local gen = Upgrades.GetFrameGeneration()
    if _gravityCacheGen ~= gen then
        _gravityCacheGen = gen
        -- 清空缓存（新帧）
        for k in pairs(_gravityCache) do _gravityCache[k] = nil end
    end

    local ti = ball.typeIndex
    local cached = _gravityCache[ti]
    if cached then return cached end

    -- 计算并缓存
    local slots = _staticSlots
    slots.addBase = sumEffects("speed_up") + runeSpeedBonus
    slots.multBase = nil
    slots.directBase = nil
    slots.flatExtra = nil
    slots.addFinal = nil
    slots.multFinal = nil
    slots.directFinal = nil

    if eff and eff.id == "impact" then
        _listBuf[1] = eff.gravityMult - 1
        for i = 2, #_listBuf do _listBuf[i] = nil end
        slots.multBase = _listBuf
    end

    local result = calcFormula(CONFIG.GRAVITY * (gameState.boardScale or 1), slots)
    _gravityCache[ti] = result
    return result
end

--- 计算球的实际弹跳衰减
--- base = BOUNCE_DAMPING（铜球替换为 eff.damping）
--- 加算基础: copper_boost（仅铜球）
---@param ball table 球对象
---@return number 实际衰减系数
function M.GetDamping(ball)
    -- damping 完全不依赖 ball 实例属性（只依赖类型），使用帧级缓存
    local gen = Upgrades.GetFrameGeneration()
    if _dampingCacheGen ~= gen then
        _dampingCacheGen = gen
        for k in pairs(_dampingCache) do _dampingCache[k] = nil end
    end

    local ti = ball.typeIndex
    local cached = _dampingCache[ti]
    if cached then return cached end

    local ballType = Config.BALL_TYPES[ti]
    local eff = ballType and ballType.effect
    local base = CONFIG.BOUNCE_DAMPING

    if eff and eff.id == "bouncy" then
        base = eff.damping
        local cb = sumEffects("copper_boost")
        if cb ~= 0 then
            base = base * (1 + cb)
        end
    end

    -- 符文弹力加成（rune_bounce: 弹跳能量保留+3%/级，上限35%）
    local runeBounceBonus = Runes.GetRuneValue("rune_bounce")
    if runeBounceBonus > 0 then
        base = math_min(0.95, base + runeBounceBonus)
    end

    _dampingCache[ti] = base
    return base
end

-- ============================================================================
-- 落袋属性（供 Settlement.OnBallLanded 使用）
-- ============================================================================

--- 计算球的落袋倍率加成
--- base = 1.0（无加成）
--- 加算基础: heavy_landing（重力落袋，所有球通用）
--- 乘算基础: impact.multBonus + meteor_boost（陨石球专属）
--- 副作用: 高等级陨石强化触发震屏
---@param ball table 球对象
---@return number 落袋倍率乘数（>=1.0）
function M.GetLandingMult(ball)
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect

    -- 复用静态 slots 表（避免每次调用分配新表）
    local slots = _staticSlots2
    slots.addBase = sumEffects("heavy_landing")
    slots.multBase = nil
    slots.directBase = nil
    slots.flatExtra = nil
    slots.addFinal = nil
    slots.multFinal = nil
    slots.directFinal = nil

    -- 冲击效果（陨石球专属）→ 乘算基础（复用静态列表）
    if eff and eff.id == "impact" and eff.multBonus then
        _listBuf2[1] = eff.multBonus + sumEffects("meteor_boost")
        for i = 2, #_listBuf2 do _listBuf2[i] = nil end
        slots.multBase = _listBuf2
    end

    -- 质量冲击：每撞 5 钉，落袋倍率额外 +value%
    local massVal = Upgrades.GetEffectValue("mass_impact")
    if massVal > 0 then
        local hits = ball.pegHits or 0
        local layers = math_floor(hits / 5)
        if layers > 0 then
            local massBonus = massVal * layers
            slots.addBase = (slots.addBase or 0) + massBonus
        end
    end

    local result = calcFormula(1.0, slots)

    -- 副作用：陨石强化震屏
    local meteorLv = Upgrades.GetEffectLevel("meteor_boost")
    if meteorLv >= 3 then
        local shakeStr = math_min(1.5, 0.2 + meteorLv * 0.12)
        gameState.screenShake = math_max(gameState.screenShake or 0, shakeStr)
    end

    return result
end

--- 计算球的聚财奖金比例
--- 聚财球: base = eff.bonusRatio, 加算基础 = emerald_boost
--- 所有球: 额外基础 = windfall（意外之财，通用聚财）
---@param ball table 球对象
---@return number 奖金比例（0 = 无聚财效果）
function M.GetFortuneBonusRatio(ball)
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect

    local base = 0
    local slots = {
        flatExtra = sumEffects("windfall"),
    }

    -- 聚财球专属
    if eff and eff.id == "fortune" and eff.bonusRatio then
        base = eff.bonusRatio
        slots.addBase = sumEffects("emerald_boost")
    end

    return calcFormula(base, slots)
end

--- 暴击判定（钻石暴击 + 钻石强化 + 通用暴击光环 + 暴击之力）
--- 返回 isCrit 和 critMult，Settlement 直接使用结果
---@param ball table 球对象
---@return boolean isCrit 是否暴击
---@return number critMult 暴击倍率（未暴击时也返回倍率供参考）
function M.RollCrit(ball)
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect

    local critChance = 0
    local critMult = 2  -- 默认双倍

    -- 球自带暴击（钻石球）
    if eff and eff.id == "crit" then
        critChance = eff.chance
        -- 钻石强化
        local diamondBoost = Upgrades.GetEffectValue("diamond_boost")
        if diamondBoost > 0 then
            critChance = critChance + diamondBoost
            -- 每5级+1倍
            local dbLv = Upgrades.GetEffectLevel("diamond_boost")
            critMult = math_max(critMult, 2 + math_floor(dbLv / 5))
        end
    end

    -- 通用暴击光环
    local globalCritChance = Upgrades.GetEffectValue("critical")
    if globalCritChance > 0 then
        critChance = critChance + globalCritChance
        local critLv = Upgrades.GetEffectLevel("critical")
        critMult = math_max(critMult, 2 + math_floor(critLv / 5))
    end

    -- 暴击之力（独立倍率加成，不影响概率）
    local critPower = Upgrades.GetEffectValue("crit_power")
    if critPower > 0 then
        critMult = critMult + critPower
    end

    -- 符文暴击加成（rune_crit: 全局暴击概率+1.5%/级，上限30%）
    local runeCritBonus = Runes.GetRuneValue("rune_crit")
    if runeCritBonus > 0 then
        critChance = critChance + runeCritBonus
    end

    local isCrit = critChance > 0 and math_random() < critChance
    return isCrit, critMult
end

-- ============================================================================
-- 行为效果（不适用公式模板）
-- ============================================================================

--- 计算蓄能释放收益（黑曜石球专属）
--- 撞钉数^exponent × 球价值% 作为额外收益
---@param ball table 球对象
---@return number 蓄能额外收益
function M.GetChargeBonus(ball)
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect
    if not eff or eff.id ~= "charge" then return 0 end

    local hits = ball.pegHits or 0
    if hits <= 0 then return 0 end

    local chargeBase = (hits ^ eff.exponent) * ball.value * 0.01
    -- 黑曜石强化增加释放倍率
    local obsidianBoostVal = Upgrades.GetEffectValue("obsidian_boost")
    chargeBase = chargeBase * (1 + obsidianBoostVal)

    -- 蓄能爆裂：撞钉≥阈值时 ×2
    local chargeBurstVal = Upgrades.GetEffectValue("charge_burst")
    if chargeBurstVal > 0 and hits >= chargeBurstVal then
        chargeBase = chargeBase * 2
    end

    -- chargeBase 含 ball.value（可能是 BigNum 或 number），用补丁版 floor 后 compact
    return BigNum.compact(math.floor(chargeBase))
end

--- 计算口袋大师加成（珍珠球专属）
--- 根据本轮落入不同口袋种类数计算加成
---@param ball table 球对象
---@return number 口袋多样性倍率（>=1.0）
function M.GetSlotMasterMult(ball)
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect
    if not eff or eff.id ~= "slot_master" then return 1.0 end

    -- 统计本轮落入了多少种不同口袋
    local visited = gameState.slotVisitedThisRound or {}
    local diversity = 0
    for _ in pairs(visited) do
        diversity = diversity + 1
    end

    if diversity <= 0 then return 1.0 end

    local bonusPerSlot = eff.diversityBonus
    -- 珍珠强化增加每种加成
    local pearlBoostVal = Upgrades.GetEffectValue("pearl_boost")
    bonusPerSlot = bonusPerSlot + pearlBoostVal

    return 1.0 + bonusPerSlot * diversity
end

--- 计算连击宗师加成（蓝宝石球专属）
--- 返回连击乘数和额外窗口时间
---@param ball table 球对象
---@return number comboAmp 连击倍率放大系数
---@return number windowBonus 额外连击窗口秒数
function M.GetComboMasterBonus(ball)
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect
    if not eff or eff.id ~= "combo_master" then return 1.0, 0 end

    local amp = eff.comboAmp
    -- 蓝宝石强化增加倍率
    local sapphireBoostVal = Upgrades.GetEffectValue("sapphire_boost")
    amp = amp * (1 + sapphireBoostVal)

    return amp, eff.windowBonus
end

--- 计算琥珀球节律落袋加成
--- 速度越快，落袋奖励越高
---@param ball table 球对象
---@return number 节律倍率（>=1.0）
function M.GetTempoLandingMult(ball)
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect
    if not eff or eff.id ~= "tempo" then return 1.0 end

    local speedBonus = ball.tempoSpeedBonus or 0
    if speedBonus <= 0 then return 1.0 end

    return 1.0 + speedBonus * eff.rewardScale
end

--- 应用幸运弹跳（行为效果，不适用公式模板）
--- 在接近底部时施加水平力偏向高倍口袋
---@param ball table 球对象
---@param dt number 帧间隔
---@param bottomY number 底部 Y 坐标
function M.ApplyLuckyBounce(ball, dt, bottomY)
    local luckyVal = Upgrades.GetEffectValue("lucky_bounce")
    if luckyVal <= 0 then return end
    if ball.y <= (bottomY - 60) then return end

    local bestMult = 0
    local bestCenterX = ball.x
    for si = 1, #gameState.slots do
        local sMult = Slots.GetSlotMult(gameState.slots[si])
        if sMult > bestMult then
            bestMult = sMult
            bestCenterX = gameState.boardLeft + (si - 0.5) * gameState.slotWidth
        end
    end

    local pullDir = bestCenterX - ball.x
    if math_abs(pullDir) > 5 then
        ball.vx = ball.vx + (pullDir > 0 and 1 or -1) * luckyVal * 80 * dt
    end
end

return M
