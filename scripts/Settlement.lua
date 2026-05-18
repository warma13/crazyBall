-- ============================================================================
-- Settlement.lua - 落袋结算管线
-- 处理球落入口袋后的完整结算流程：
--   口袋倍率 → 口袋祝福 → 冲击加成 → 基础收益
--   → 弹钉共鸣/丰收 → 聚财 → 金币磁铁
--   → 暴击 → 连击风暴 → 入账 → 飘字
-- Physics.lua 在球落袋时仅调用 Settlement.OnBallLanded(ball)
-- ============================================================================

local Config = require("Config")
local State = require("State")
local Slots = require("Slots")
local Upgrades = require("Upgrades")
local PegEffects = require("PegEffects")
local BallEffects = require("BallEffects")
local Runes = require("Runes")

local CONFIG = Config.CONFIG
local gameState = State.gameState

local BigNum = require("BigNum")
-- BigNum 猴补丁的 math.floor/max/min（能处理 BigNum 和 number）
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
-- 原始版本（仅用于确定是 number 的调用，绕过类型检查开销）
local num_floor = BigNum._rawFloor
local num_max = BigNum._rawMax
local num_min = BigNum._rawMin
local math_random = math.random
local math_sqrt = math.sqrt

local M = {}

-- 帧级缓存：split_frenzy 分裂球计数（避免每次落袋遍历所有球）
local _splitBallCountCache = 0
local _splitBallCountGen = 0

-- 飘字对象池（避免每次落袋分配新表）
local _popupPool = {}
local _popupPoolSize = 0

--- 从池中获取或创建飘字对象
local function _acquirePopup()
    if _popupPoolSize > 0 then
        local p = _popupPool[_popupPoolSize]
        _popupPool[_popupPoolSize] = nil
        _popupPoolSize = _popupPoolSize - 1
        p.icon = nil  -- 清除残留字段，防止金币 popup 误显宝石图标
        p.iconType = nil
        p.skinKey = nil
        p.vx = 0
        p.vy = 0
        p.elapsed = 0
        return p
    end
    return { x = 0, y = 0, text = "", color = { 0, 0, 0, 255 }, timer = 0, fontSize = 14, vx = 0, vy = 0, elapsed = 0 }
end

--- 回收飘字对象到池中（由 Physics.UpdatePopups 调用）
function M.ReleasePopup(popup)
    _popupPoolSize = _popupPoolSize + 1
    _popupPool[_popupPoolSize] = popup
end

-- 空间网格查询注入（由 Physics.lua 初始化后调用 SetGridQuery 注入）
local queryNearbyPegs = nil

--- 注入空间网格查询函数（Physics.lua 调用）
function M.SetGridQuery(fn)
    queryNearbyPegs = fn
end

-- ============================================================================
-- 每帧更新：连击窗口倒计时
-- ============================================================================

--- 处理连击窗口计时器衰减（由 main.lua 每帧调用）
---@param dt number 帧间隔
function M.Update(dt)
    if gameState.comboTimer > 0 then
        gameState.comboTimer = gameState.comboTimer - dt
        if gameState.comboTimer <= 0 then
            gameState.comboTimer = 0
            gameState.comboCount = 0
        end
    end

    -- 聚财共享窗口倒计时
    if gameState.fortuneShareTimer > 0 then
        gameState.fortuneShareTimer = gameState.fortuneShareTimer - dt
        if gameState.fortuneShareTimer <= 0 then
            gameState.fortuneShareTimer = 0
            gameState.fortuneShareRatio = 0
        end
    end

    -- 口袋和声窗口倒计时
    if gameState.slotHarmonyTimer and gameState.slotHarmonyTimer > 0 then
        gameState.slotHarmonyTimer = gameState.slotHarmonyTimer - dt
        if gameState.slotHarmonyTimer <= 0 then
            gameState.slotHarmonyTimer = 0
        end
    end
end

-- ============================================================================
-- 核心管线：落袋结算
-- ============================================================================

--- 处理一次落袋的完整结算流程（由 Physics.lua 球触底时调用）
---@param ball table 球对象
function M.OnBallLanded(ball)
    -- ====== Step 1: 确定口袋 ======
    local slotCount = #gameState.slots
    -- 按实际分隔线边界判定落入哪个口袋
    local edges = gameState.slotEdges
    local slotIndex = slotCount  -- 默认最后一个
    if edges then
        for i = 1, slotCount do
            if ball.x < (edges[i + 1] or 1e9) then
                slotIndex = i
                break
            end
        end
    else
        local relX = ball.x - gameState.boardLeft
        slotIndex = num_floor(relX / gameState.slotWidth) + 1
    end
    slotIndex = num_max(1, num_min(slotIndex, slotCount))

    local slot = gameState.slots[slotIndex]
    local slotMult = Slots.GetSlotMult(slot)
    local slotColor = Slots.GetSlotColor(slot)
    local centerX = gameState.slotCenters and gameState.slotCenters[slotIndex]
        or (gameState.boardLeft + (slotIndex - 0.5) * gameState.slotWidth)

    local mult = slotMult
    -- 符文口袋加成（rune_slot: 全部口袋倍率+5%/级）
    local runeSlotBonus = Runes.GetRuneValue("rune_slot")
    if runeSlotBonus > 0 then
        mult = mult * (1 + runeSlotBonus)
    end

    -- ====== Step 2: 口袋祝福 ======
    -- 概率翻倍口袋倍率，倍数随等级增长
    local slotFortuneVal = Upgrades.GetEffectValue("slot_fortune")
    if slotFortuneVal > 0 and math.random() < slotFortuneVal then
        local sfLv = Upgrades.GetEffectLevel("slot_fortune")
        local fortuneMult = 2 + num_floor(sfLv / 5)  -- 每5级+1倍
        mult = mult * fortuneMult
    end

    -- ====== Step 2.5: 口袋回响（临时加成）======
    local echoBonus = Upgrades.GetEffectValue("slot_echo")
    if echoBonus > 0 and gameState.slotEchoBonuses then
        local echo = gameState.slotEchoBonuses[slotIndex]
        if echo and echo.timer > 0 then
            mult = mult * (1 + echo.bonus)
        end
    end

    -- ====== Step 2.6: 热门口袋 ======
    local hotSlotVal = Upgrades.GetEffectValue("hot_slot")
    if hotSlotVal > 0 then
        -- 更新本轮落袋计数
        gameState.slotHitCountThisRound[slotIndex] = (gameState.slotHitCountThisRound[slotIndex] or 0) + 1

        -- 找出最热门口袋
        local maxHits = 0
        local hotIndex = 0
        for si, count in pairs(gameState.slotHitCountThisRound) do
            if count > maxHits then
                maxHits = count
                hotIndex = si
            end
        end

        -- 当前口袋是最热门口袋时获得加成
        if slotIndex == hotIndex and maxHits > 1 then
            mult = mult * (1 + hotSlotVal * maxHits)
        end
    end

    -- ====== Step 3: 口袋连珠（连续落入同口袋加成）======
    local streakBonus = Upgrades.GetEffectValue("slot_streak")
    local streakCount = 0
    if streakBonus > 0 then
        if gameState.lastLandingSlot == slotIndex then
            gameState.slotStreakCount = (gameState.slotStreakCount or 0) + 1
        else
            gameState.slotStreakCount = 1
        end
        gameState.lastLandingSlot = slotIndex
        streakCount = gameState.slotStreakCount
        if streakCount > 1 then
            mult = mult * (1 + streakBonus * (streakCount - 1))
        end
    else
        gameState.lastLandingSlot = slotIndex
        gameState.slotStreakCount = 1
    end

    -- ====== Step 3.5: 口袋轮转（连续落入不同口袋加成）======
    local cycleVal = Upgrades.GetEffectValue("slot_cycle")
    local cycleCount = 0
    if cycleVal > 0 then
        local history = gameState.slotCycleHistory
        local hLen = #history
        -- 检查是否与前一个不同
        if hLen == 0 or history[hLen] ~= slotIndex then
            -- 限制历史长度（最多 slotCount * 2，防止无限增长）
            if hLen >= slotCount * 2 then
                -- 截断前半：把后半移到前面
                local half = slotCount
                for hi = 1, hLen - half do
                    history[hi] = history[hi + half]
                end
                for hi = hLen - half + 1, hLen do
                    history[hi] = nil
                end
                hLen = hLen - half
            end
            hLen = hLen + 1
            history[hLen] = slotIndex
            cycleCount = hLen
            if cycleCount > 1 then
                mult = mult * (1 + cycleVal * cycleCount)
            end
        else
            -- 重复 → 重置轮转（复用表，避免新建）
            for hi = 2, hLen do history[hi] = nil end
            history[1] = slotIndex
            cycleCount = 0
        end
    end

    -- ====== Step 3.6: 口袋大奖（全覆盖后爆发）+ 口袋和声 ======
    local slotHarmonyVal = Upgrades.GetEffectValue("slot_harmony")
    local jackpotVal = Upgrades.GetEffectValue("slot_jackpot")
    -- 只要有大奖或和声效果，就需要追踪口袋访问
    if jackpotVal > 0 or slotHarmonyVal > 0 then
        -- 更新已访问口袋
        gameState.slotVisitedThisRound[slotIndex] = true

        -- 检查是否全覆盖
        if gameState.slotJackpotReady then
            -- 触发大奖
            if jackpotVal > 0 then
                mult = mult * (2 + jackpotVal)
            end
            gameState.slotJackpotReady = false
            gameState.slotVisitedThisRound = {}
            -- 口袋和声：全覆盖后激活
            if slotHarmonyVal > 0 then
                gameState.slotHarmonyTimer = 3.0
            end
        else
            -- 检查是否达成全覆盖
            local allVisited = true
            for si = 1, slotCount do
                if not gameState.slotVisitedThisRound[si] then
                    allVisited = false
                    break
                end
            end
            if allVisited then
                gameState.slotJackpotReady = true
            end
        end
    end

    -- ====== Step 3.7: 口袋回响（落袋后给相邻口袋加 buff）======
    if echoBonus > 0 then
        gameState.slotEchoBonuses = gameState.slotEchoBonuses or {}
        -- 左邻
        if slotIndex > 1 then
            gameState.slotEchoBonuses[slotIndex - 1] = { bonus = echoBonus, timer = 3.0 }
        end
        -- 右邻
        if slotIndex < slotCount then
            gameState.slotEchoBonuses[slotIndex + 1] = { bonus = echoBonus, timer = 3.0 }
        end
    end

    -- ====== Step 3.8: 口袋和声（覆盖全部口袋后 +value% 持续3s）======
    if slotHarmonyVal > 0 and gameState.slotHarmonyTimer and gameState.slotHarmonyTimer > 0 then
        mult = mult * (1 + slotHarmonyVal)
    end

    -- ====== Step 4: 落袋倍率加成（重力落袋 + 冲击 + 陨石强化）======
    mult = mult * BallEffects.GetLandingMult(ball)

    -- ====== Step 4.1: 铁球坚韧加成 ======
    mult = mult * BallEffects.GetSturdyMult(ball)

    -- ====== Step 4.2: 珍珠球口袋大师加成 ======
    mult = mult * BallEffects.GetSlotMasterMult(ball)

    -- ====== Step 4.3: 琥珀球节律加成 ======
    mult = mult * BallEffects.GetTempoLandingMult(ball)

    -- ====== Step 5: 基础收益 ======
    local earning = math_floor(ball.value * mult)

    -- ====== Step 5.5: 黑曜石球蓄能释放 ======
    local chargeBonus = BallEffects.GetChargeBonus(ball)
    if chargeBonus > 0 then
        earning = earning + chargeBonus
    end

    -- ====== Step 6: 弹钉效果落袋管线 ======
    -- 共鸣（按撞钉次数加成）、丰收（总黄金产出加成）
    earning = PegEffects.OnBallLanded(ball, earning)

    -- ====== Step 6.5: 级联奖励（每 5 次撞钉 +value%）======
    local cascadeVal = Upgrades.GetEffectValue("cascade_bonus")
    if cascadeVal > 0 and (ball.pegHits or 0) >= 5 then
        local layers = num_floor(ball.pegHits / 5)
        earning = math_floor(earning * (1 + cascadeVal * layers))
    end

    -- ====== Step 7: 聚财奖金（聚财 + 翡翠强化 + 意外之财 + 聚财积累）======
    local fortuneRatio = BallEffects.GetFortuneBonusRatio(ball)
    -- 聚财积累加成
    if gameState.fortuneStackBonus > 0 then
        fortuneRatio = fortuneRatio + gameState.fortuneStackBonus
    end
    -- 聚财共享：非聚财球在共享窗口内也获得部分聚财
    local fortuneShareVal = Upgrades.GetEffectValue("fortune_share")
    if fortuneShareVal > 0 and gameState.fortuneShareTimer > 0 and gameState.fortuneShareRatio > 0 then
        local ballType = Config.BALL_TYPES[ball.typeIndex]
        local eff = ballType and ballType.effect
        local isFortuneBall = eff and eff.id == "fortune"
        if not isFortuneBall then
            fortuneRatio = fortuneRatio + fortuneShareVal * gameState.fortuneShareRatio
        end
    end
    local isFortuneHit = fortuneRatio > 0
    if fortuneRatio > 0 then
        earning = earning + math_floor(ball.value * fortuneRatio)
    end

    -- ====== Step 7.5: 聚财积累（聚财落袋后累加比例）======
    local fortuneStackVal = Upgrades.GetEffectValue("fortune_stack")
    if fortuneStackVal > 0 and isFortuneHit then
        gameState.fortuneStackBonus = (gameState.fortuneStackBonus or 0) + fortuneStackVal
    end

    -- ====== Step 7.6: 聚财共享（聚财球落袋后设置共享窗口）======
    if fortuneShareVal > 0 and isFortuneHit then
        local ballType = Config.BALL_TYPES[ball.typeIndex]
        local eff = ballType and ballType.effect
        local isFortuneBall = eff and eff.id == "fortune"
        if isFortuneBall then
            gameState.fortuneShareTimer = 3.0
            gameState.fortuneShareRatio = fortuneRatio
        end
    end

    -- ====== Step 8: 金币磁铁 ======
    -- 落袋奖励百分比加成
    local magnetBonus = Upgrades.GetEffectValue("coin_magnet")
    if magnetBonus > 0 then
        earning = math_floor(earning * (1 + magnetBonus))
    end

    -- ====== Step 9: 暴击判定（钻石暴击 + 通用暴击光环 + 暴击之力）======
    local isCrit, critMult = BallEffects.RollCrit(ball)

    -- ====== Step 9.1: 暴击连锁（连续暴击递增倍率）======
    local critStreakVal = Upgrades.GetEffectValue("crit_streak")
    if critStreakVal > 0 then
        if isCrit then
            gameState.critStreakCount = (gameState.critStreakCount or 0) + 1
            if gameState.critStreakCount > 1 then
                critMult = critMult + critStreakVal * (gameState.critStreakCount - 1)
            end
        else
            gameState.critStreakCount = 0
        end
    end

    if isCrit then
        earning = math_floor(earning * critMult)
    end

    -- ====== Step 9.2: 暴击震荡（暴击时范围产金）======
    local critShockVal = Upgrades.GetEffectValue("crit_shock")
    if critShockVal > 0 and isCrit then
        -- 使用空间网格查询附近钉子，避免遍历全部钉子
        local nearbyPegs = queryNearbyPegs and queryNearbyPegs(ball.x, ball.y) or gameState.pegs
        local shockGold = math_floor(ball.value * critShockVal)
        if shockGold > 0 then
            local count = 0
            for _, peg in ipairs(nearbyPegs) do
                local dx = peg.x - ball.x
                local dy = peg.y - ball.y
                if dx * dx + dy * dy <= 900 then  -- 30^2 = 900
                    count = count + 1
                end
            end
            if count > 0 then
                State.AddEarnings(shockGold * count)
            end
        end
    end

    -- ====== Step 9.5: 超载爆发（撞钉达阈值 ×3）======
    local overchargeVal = Upgrades.GetEffectValue("overcharge")
    if overchargeVal > 0 and (ball.pegHits or 0) >= overchargeVal and not ball.overcharged then
        ball.overcharged = true
        earning = earning * 3
    end

    -- ====== Step 9.6: 灼烧高潮（灼烧 N 钉后落袋 +50% 灼烧收益）======
    local burnClimaxVal = Upgrades.GetEffectValue("burn_climax")
    if burnClimaxVal > 0 and (ball.burnCount or 0) >= burnClimaxVal then
        local burnBonus = math_floor((ball.burnEarned or 0) * 0.5)
        if burnBonus > 0 then
            earning = earning + burnBonus
        end
    end

    -- ====== Step 9.7: 分裂狂潮（场上每颗分裂球 +value%）======
    local splitFrenzyVal = Upgrades.GetEffectValue("split_frenzy")
    if splitFrenzyVal > 0 then
        -- 帧级缓存：同一帧内多球落袋只计数一次
        local gen = Upgrades.GetFrameGeneration()
        if _splitBallCountGen ~= gen then
            _splitBallCountGen = gen
            local cnt = 0
            for _, b in ipairs(gameState.balls) do
                if b.alive and b.hasSplit then
                    cnt = cnt + 1
                end
            end
            _splitBallCountCache = cnt
        end
        if _splitBallCountCache > 0 then
            earning = math_floor(earning * (1 + splitFrenzyVal * _splitBallCountCache))
        end
    end

    -- ====== Step 9.8: 分裂活力（分裂球撞钉≥阈值 ×1.5）======
    local splitVitalityVal = Upgrades.GetEffectValue("split_vitality")
    if splitVitalityVal > 0 and ball.hasSplit and (ball.pegHits or 0) >= splitVitalityVal then
        earning = math_floor(earning * 1.5)
    end

    -- ====== Step 10: 连击风暴 + 连击狂热 + 连击宗师 ======
    local comboBonus = Upgrades.GetEffectValue("combo")
    local comboCount = 0
    if comboBonus > 0 then
        -- 连击窗口时间随等级递增：每2级+1秒，上限12秒
        local comboLevel = Upgrades.GetEffectLevel("combo")
        local comboWindow = num_min(12, 2 + num_floor(comboLevel / 2))

        -- 蓝宝石球连击宗师额外窗口
        local comboAmp, windowBonus = BallEffects.GetComboMasterBonus(ball)
        comboWindow = comboWindow + windowBonus

        if gameState.comboTimer > 0 then
            gameState.comboCount = gameState.comboCount + 1
        else
            gameState.comboCount = 1
        end
        gameState.comboTimer = comboWindow

        comboCount = gameState.comboCount
        if comboCount > 1 then
            -- 连击狂热加速增长率
            local frenzyVal = Upgrades.GetEffectValue("combo_frenzy")
            local effectiveBonus = comboBonus * (1 + frenzyVal)
            -- 连击宗师倍率放大
            effectiveBonus = effectiveBonus * comboAmp
            local comboMult = 1 + effectiveBonus * (comboCount - 1)
            earning = math_floor(earning * comboMult)
        end

        -- 连击回响：连击≥5时额外加成
        local comboEchoVal = Upgrades.GetEffectValue("combo_echo")
        if comboEchoVal > 0 and comboCount >= 5 then
            local comboEchoBonus = math_floor(earning * comboEchoVal * comboCount)
            earning = earning + comboEchoBonus
        end
    end

    -- ====== Step 10.5: 连击爆发（连击达阈值 ×2，每轮最多3次）======
    local comboBurstVal = Upgrades.GetEffectValue("combo_burst")
    if comboBurstVal > 0 and comboCount >= comboBurstVal then
        local burstCount = gameState.comboBurstCount or 0
        if burstCount < 3 then
            earning = earning * 2
            gameState.comboBurstCount = burstCount + 1
        end
    end

    -- ====== Step 11: 收益放大（最终乘区）======
    local ampVal = Upgrades.GetEffectValue("earning_amp")
    if ampVal > 0 then
        earning = math_floor(earning * (1 + ampVal))
    end

    -- ====== Step 11.5: 绝境爆发（剩余≤10s 收益加成）======
    local lastStandVal = Upgrades.GetEffectValue("last_stand")
    if lastStandVal > 0 and gameState.roundTimeLeft <= 10 then
        earning = math_floor(earning * (1 + lastStandVal))
    end

    -- ====== Step 11.6: 急速心流（前15s 收益加成）======
    local hasteVal = Upgrades.GetEffectValue("haste")
    if hasteVal > 0 then
        local elapsed = Config.ROUND.TIME_LIMIT - gameState.roundTimeLeft
        if elapsed <= 15 then
            earning = math_floor(earning * (1 + hasteVal))
        end
    end

    -- ====== Step 11.8: 碾压震颤（撞≥15钉落袋全场钉产金）======
    local massQuakeVal = Upgrades.GetEffectValue("mass_quake")
    if massQuakeVal > 0 then
        local hits = ball.pegHits or 0
        if hits >= 15 then
            -- 每颗钉产金相同，直接用 钉子总数 × 单颗金额，避免遍历
            local quakeGold = math_floor(ball.value * massQuakeVal)
            if quakeGold > 0 then
                local quakeTotal = quakeGold * #gameState.pegs
                State.AddEarnings(quakeTotal)
                gameState.screenShake = num_max(gameState.screenShake or 0, 0.25)
            end
        end
    end

    -- ====== Step 12: 入账 ======
    State.AddEarnings(earning)

    -- ====== Step 13: 飘字（使用对象池减少 GC）======
    local popupText = "+" .. State.FormatNumber(earning)
    if isCrit then
        popupText = popupText .. (critMult >= 3 and " 超暴击!" or " 暴击!")
    end
    if comboCount > 1 then
        popupText = popupText .. " " .. comboCount .. "连击!"
    end
    if streakCount > 1 then
        popupText = popupText .. " " .. streakCount .. "连珠"
    end

    local popup = _acquirePopup()
    popup.x = centerX
    popup.y = gameState.contentBottom - CONFIG.SLOT_HEIGHT * (gameState.boardScale or 1)
    popup.text = popupText
    popup.timer = CONFIG.POPUP_DURATION
    popup.elapsed = 0
    popup.iconType = "coin"
    popup.vx = (math.random() > 0.5 and 1 or -1) * (30 + math.random() * 30)
    popup.vy = -(80 + math.random() * 40)
    popup.fontSize = (isCrit or mult >= 10) and 20 or (mult >= 5 and 16 or 14)
    -- 复用 color 表，避免每次分配新表
    local pc = popup.color
    if isCrit then
        pc[1], pc[2], pc[3], pc[4] = 255, 80, 80, 255
    else
        pc[1], pc[2], pc[3], pc[4] = slotColor[1], slotColor[2], slotColor[3], slotColor[4]
    end
    table.insert(gameState.popups, popup)

    if mult >= 10 or isCrit then
        gameState.screenShake = 0.15
    end
end

return M
