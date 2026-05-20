-- ============================================================================
-- PegEffects.lua - 弹钉效果上下文管线
-- Physics.lua 仅在 3 个点调用本模块，所有弹钉效果逻辑集中于此
-- ============================================================================

local Config = require("Config")
local State = require("State")
local Upgrades = require("Upgrades")
local EventBus = require("EventBus")
local Enchantment = require("Enchantment")

local CONFIG = Config.CONFIG
local gameState = State.gameState

local BigNum = require("BigNum")
-- BigNum 猴补丁版本（能处理 BigNum，用于 earning/ball.value 相关计算）
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
-- 原始版本（仅用于确定是 number 的调用）
local num_floor = BigNum._rawFloor
local num_min = BigNum._rawMin
local num_max = BigNum._rawMax
local math_sqrt = math.sqrt
local math_random = math.random
local math_huge = math.huge

local M = {}

-- 帧级时间戳（由 main.lua 每帧调用 M.SetFrameTime 设置，替代每次 os.clock()）
local _frameTime = 0

--- 设置当前帧时间（由 main.lua HandleUpdate 调用一次）
function M.SetFrameTime(t)
    _frameTime = t
end

-- ============================================================================
-- 活跃处理器缓存（避免每次碰撞调用所有 ~28 个处理器）
-- ============================================================================
local _activeHandlers = nil      -- 已激活的处理器列表（轮次开始时构建）
local _activeHandlersDirty = true  -- 标记需要重建

--- 标记处理器列表需要重建（升级效果时调用）
function M.MarkHandlersDirty()
    _activeHandlersDirty = true
end

-- ============================================================================
-- 静态复用表（避免每次碰撞分配新表）
-- ============================================================================
local _staticCtx = {
    ball = nil, peg = nil, allPegs = nil, allBalls = nil,
    isSpark = false, pegHitBonus = 0, goldEarning = 0,
}
local _staticFindResult = {}  -- findPegsInRadius 复用表

-- ember 对象池（避免每次撞钉分配新 ember 表）
local _emberPool = {}
local _emberPoolSize = 0

local function _acquireEmber(amount, ticksLeft)
    if _emberPoolSize > 0 then
        local e = _emberPool[_emberPoolSize]
        _emberPool[_emberPoolSize] = nil
        _emberPoolSize = _emberPoolSize - 1
        e.amount = amount
        e.ticksLeft = ticksLeft
        e.timer = 0
        return e
    end
    return { amount = amount, ticksLeft = ticksLeft, timer = 0 }
end

local function _releaseEmber(ember)
    _emberPoolSize = _emberPoolSize + 1
    _emberPool[_emberPoolSize] = ember
end

-- ============================================================================
-- 脏钉集合（只追踪有活跃计时器的钉子，避免每帧遍历全部 ~90 颗）
-- ============================================================================
local _dirtyPegs = {}        -- { [peg] = true }
local _dirtyPegList = {}     -- 有序列表（用于迭代）
local _dirtyPegListDirty = true  -- 需要从 set 重建 list

local function _addDirtyPeg(peg)
    if not _dirtyPegs[peg] then
        _dirtyPegs[peg] = true
        _dirtyPegListDirty = true
    end
end

local function _removeDirtyPeg(peg)
    if _dirtyPegs[peg] then
        _dirtyPegs[peg] = nil
        _dirtyPegListDirty = true
    end
end

local function _getDirtyPegList()
    if _dirtyPegListDirty then
        local list = _dirtyPegList
        local n = 0
        for peg in pairs(_dirtyPegs) do
            n = n + 1
            list[n] = peg
        end
        for i = n + 1, #list do list[i] = nil end
        _dirtyPegListDirty = false
    end
    return _dirtyPegList
end

-- ============================================================================
-- 空间网格查询注入（由 Physics.lua 初始化后调用 SetGridQuery 注入）
-- ============================================================================
local queryNearbyPegs = nil  -- function(x, y) → pegs_table

--- 注入空间网格查询函数（Physics.lua 调用）
function M.SetGridQuery(fn)
    queryNearbyPegs = fn
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 两点距离
local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math_sqrt(dx * dx + dy * dy)
end

--- 两点距离平方（用于比较，避免 sqrt）
local function distSq(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return dx * dx + dy * dy
end

--- 查找最近的钉（排除自身）—— 使用空间网格加速
local function findNearestPeg(peg, allPegs)
    local pegsToSearch = queryNearbyPegs and queryNearbyPegs(peg.x, peg.y) or allPegs
    local best, bestDist2 = nil, math_huge
    local px, py = peg.x, peg.y
    for _, p in ipairs(pegsToSearch) do
        if p ~= peg then
            local d2 = distSq(px, py, p.x, p.y)
            if d2 < bestDist2 then
                bestDist2 = d2
                best = p
            end
        end
    end
    return best
end

--- 查找半径内的钉（排除自身）—— 使用空间网格加速 + 复用静态结果表
local function findPegsInRadius(peg, allPegs, radius)
    local pegsToSearch = queryNearbyPegs and queryNearbyPegs(peg.x, peg.y) or allPegs
    local result = _staticFindResult
    local n = 0
    local r2 = radius * radius
    local px, py = peg.x, peg.y
    for _, p in ipairs(pegsToSearch) do
        if p ~= peg and distSq(px, py, p.x, p.y) <= r2 then
            n = n + 1
            result[n] = p
        end
    end
    -- 清理尾部旧数据
    for i = n + 1, #result do result[i] = nil end
    return result
end

--- 查找最近的未被当前球撞过的钉 —— 使用空间网格加速
local function findNearestUnhitPeg(ball, allPegs)
    local pegsToSearch = queryNearbyPegs and queryNearbyPegs(ball.x, ball.y) or allPegs
    local best, bestDist2 = nil, math_huge
    local bx, by = ball.x, ball.y
    for _, p in ipairs(pegsToSearch) do
        local d2 = distSq(bx, by, p.x, p.y)
        if d2 < bestDist2 then
            bestDist2 = d2
            best = p
        end
    end
    return best
end

-- ============================================================================
-- 获取碰撞半径（供 Physics.lua 碰撞检测使用）
-- ============================================================================

--- 返回弹钉磁场加成后的碰撞半径
---@return number 碰撞判定用的钉子半径
function M.GetPegCollisionRadius()
    local pegMagnetVal = Upgrades.GetEffectValue("peg_magnet")
    if pegMagnetVal > 0 then
        return CONFIG.PEG_RADIUS * (gameState.boardScale or 1) * (1 + pegMagnetVal)
    end
    return CONFIG.PEG_RADIUS * (gameState.boardScale or 1)
end

-- ============================================================================
-- 核心管线：撞钉时触发
-- ============================================================================

--- 构建活跃处理器列表（仅包含玩家已拥有的效果）
--- 每个条目: { handler=function, needsNoSpark=bool }
local function _rebuildActiveHandlers()
    local handlers = {}
    local function add(fn, needsNoSpark)
        handlers[#handlers + 1] = { handler = fn, needsNoSpark = needsNoSpark or false }
    end

    -- Phase 1: 球价值修改（总是添加，内部检查很快）
    if Upgrades.GetEffectLevel("peg_value") > 0 then add(M._applyPegValue) end

    -- Phase 2: 黄金弹钉产金（peg_gold 是整条链的前提）
    if Upgrades.GetEffectLevel("peg_gold") > 0 then
        if Upgrades.GetEffectLevel("gold_stack") > 0 then add(M._applyGoldStack) end
        add(M._applyPegGold)
        if Upgrades.GetEffectLevel("gold_crit") > 0 then add(M._applyGoldCrit) end
        if Upgrades.GetEffectLevel("gold_streak") > 0 then add(M._applyGoldStreak) end
        if Upgrades.GetEffectLevel("gold_aura") > 0 then add(M._applyGoldAura) end
        if Upgrades.GetEffectLevel("gold_ember") > 0 then add(M._applyGoldEmber) end
        add(M._recordGoldEarned)
    end

    -- Phase 3: 其他即时收益
    if Upgrades.GetEffectLevel("chain_lightning") > 0 then add(M._applyChainLightning, true) end
    if Upgrades.GetEffectLevel("peg_chain") > 0 then add(M._applyPegChain) end
    if Upgrades.GetEffectLevel("peg_charge") > 0 then add(M._applyPegCharge) end
    if Upgrades.GetEffectLevel("peg_mark") > 0 then add(M._applyPegMark) end
    if Upgrades.GetEffectLevel("peg_sync") > 0 then add(M._applyPegSync) end
    if Upgrades.GetEffectLevel("peg_gem") > 0 then add(M._applyPegGem) end
    if Upgrades.GetEffectLevel("echo_hit") > 0 then add(M._applyEchoHit) end
    if Upgrades.GetEffectLevel("peg_spark") > 0 then add(M._applyPegSpark, true) end

    -- 球自带效果（总是添加，内部按球类型判断）
    add(M._applyBallPegEffects)

    if Upgrades.GetEffectLevel("peg_bonus") > 0 then add(M._applyPegBonus) end
    if Upgrades.GetEffectLevel("burn_spread") > 0 then add(M._applyBurnSpread) end
    if Upgrades.GetEffectLevel("burn_linger") > 0 then add(M._applyBurnLinger) end
    if Upgrades.GetEffectLevel("burn_empower") > 0 then add(M._applyBurnEmpower) end
    if Upgrades.GetEffectLevel("combo_extend") > 0 then add(M._applyComboExtend) end
    if Upgrades.GetEffectLevel("time_harvest") > 0 then add(M._applyTimeHarvest) end

    -- Phase 4: 物理修改
    if Upgrades.GetEffectLevel("peg_launch") > 0 then add(M._applyPegLaunch) end
    if Upgrades.GetEffectLevel("peg_slow") > 0 then add(M._applyPegSlow) end
    if Upgrades.GetEffectLevel("peg_wave") > 0 then add(M._applyPegWave) end
    if Upgrades.GetEffectLevel("growth_momentum") > 0 then add(M._applyGrowthMomentum) end

    _activeHandlers = handlers
    _activeHandlersDirty = false
end

--- 处理一次撞钉的所有效果（由 Physics.lua 碰撞检测后调用）
--- 不含物理弹跳本身，只处理效果逻辑
---@param ball table 球对象
---@param peg table 钉对象
---@param allPegs table 所有钉
---@param allBalls table 所有球
---@param isSpark boolean 是否由火花触发（防止递归）
function M.OnPegHit(ball, peg, allPegs, allBalls, isSpark)
    -- 懒重建活跃处理器列表
    if _activeHandlersDirty or not _activeHandlers then
        _rebuildActiveHandlers()
    end

    -- 复用静态 ctx（避免每次碰撞分配新表）
    local ctx = _staticCtx
    ctx.ball = ball
    ctx.peg = peg
    ctx.allPegs = allPegs
    ctx.allBalls = allBalls
    ctx.isSpark = isSpark or false
    ctx.pegHitBonus = 0
    ctx.goldEarning = 0

    -- 计数
    ball.pegHits = (ball.pegHits or 0) + 1

    -- 记录连锁时间（使用帧级时间戳，避免每次 os.clock() 系统调用）
    local now = _frameTime
    ball.timeSinceLastPeg = now - (ball.lastPegTime or 0)
    ball.lastPegTime = now

    -- 只调用活跃的处理器
    local isSp = ctx.isSpark
    for i = 1, #_activeHandlers do
        local entry = _activeHandlers[i]
        if not (entry.needsNoSpark and isSp) then
            entry.handler(ctx)
        end
    end
end

-- ============================================================================
-- 核心管线：落袋时触发
-- ============================================================================

--- 修改落袋收益（由 Physics.OnBallLanded 在基础 earning 计算后调用）
---@param ball table 球对象
---@param earning number 基础收益（ball.value * slotMult）
---@return number 修改后的收益
function M.OnBallLanded(ball, earning)
    -- 弹钉共鸣：按撞钉次数增加落袋收益
    local resonanceVal = Upgrades.GetEffectValue("peg_resonance")
    if resonanceVal > 0 and (ball.pegHits or 0) > 0 then
        earning = math_floor(earning * (1 + resonanceVal * ball.pegHits))
    end

    -- 黄金丰收：落袋时获得总黄金产出的额外比例
    local harvestVal = Upgrades.GetEffectValue("gold_harvest")
    if harvestVal > 0 and (ball.totalGoldEarned or 0) > 0 then
        local harvestBonus = math_floor(ball.totalGoldEarned * harvestVal)
        State.AddEarnings(harvestBonus)
    end

    return earning
end

-- ============================================================================
-- 核心管线：每帧更新（余烬 tick）
-- ============================================================================

--- 处理余烬持续产金和充能/印记计时器
---@param dt number 帧间隔
function M.Update(dt)
    -- 余烬 tick
    for _, ball in ipairs(gameState.balls) do
        if ball.alive and ball.embers then
            local embers = ball.embers
            local n = #embers
            local j = 1
            while j <= n do
                local ember = embers[j]
                ember.timer = ember.timer + dt
                if ember.timer >= 0.5 then
                    ember.timer = ember.timer - 0.5
                    State.AddEarnings(ember.amount)
                    ball.totalGoldEarned = (ball.totalGoldEarned or 0) + ember.amount
                    ember.ticksLeft = ember.ticksLeft - 1
                    if ember.ticksLeft <= 0 then
                        embers[j] = embers[n]
                        embers[n] = nil
                        n = n - 1
                        -- 回收到对象池
                        _releaseEmber(ember)
                    else
                        j = j + 1
                    end
                else
                    j = j + 1
                end
            end
        end
    end

    -- 钉子计时器衰减（只遍历有活跃计时器的脏钉，而非全部 ~90 颗）
    local dirtyList = _getDirtyPegList()
    for i = #dirtyList, 1, -1 do
        local peg = dirtyList[i]
        local stillDirty = false

        if peg.burnTimer then
            peg.burnTimer = peg.burnTimer - dt
            if peg.burnTimer <= 0 then
                peg.burning = nil
                peg.burnTimer = nil
                peg.burnGold = nil
            else
                stillDirty = true
            end
        end
        if peg.chargeTimer then
            peg.chargeTimer = peg.chargeTimer - dt
            if peg.chargeTimer <= 0 then
                peg.chargedBy = nil
                peg.chargeTimer = nil
            else
                stillDirty = true
            end
        end
        if peg.markTimer then
            peg.markTimer = peg.markTimer - dt
            if peg.markTimer <= 0 then
                peg.markedBy = nil
                peg.markTimer = nil
            else
                stillDirty = true
            end
        end

        if not stillDirty then
            _removeDirtyPeg(peg)
        end
    end

    -- 口袋回响计时器衰减
    if gameState.slotEchoBonuses then
        for si, echo in pairs(gameState.slotEchoBonuses) do
            echo.timer = echo.timer - dt
            if echo.timer <= 0 then
                gameState.slotEchoBonuses[si] = nil
            end
        end
    end
end

-- ============================================================================
-- Phase 1: 球价值修改
-- ============================================================================

function M._applyPegValue(ctx)
    local val = Upgrades.GetEffectValue("peg_value")
    if val > 0 then
        ctx.ball.value = ctx.ball.value + val
        -- 记录累计增值（供 split_inherit 使用）
        ctx.ball.addedValue = (ctx.ball.addedValue or 0) + val
    end
end

-- ============================================================================
-- Phase 2: 黄金弹钉产金
-- ============================================================================

function M._applyGoldStack(ctx)
    local val = Upgrades.GetEffectValue("gold_stack")
    if val > 0 then
        ctx.ball.goldStackBonus = (ctx.ball.goldStackBonus or 0) + val
    end
end

function M._applyPegGold(ctx)
    local pegGoldVal = Upgrades.GetEffectValue("peg_gold")
    if pegGoldVal <= 0 then return end

    -- 基础产出 + 积累加成
    ctx.goldEarning = pegGoldVal + (ctx.ball.goldStackBonus or 0)
end

function M._applyGoldCrit(ctx)
    if ctx.goldEarning <= 0 then return end
    local val = Upgrades.GetEffectValue("gold_crit")
    if val > 0 and math_random() < val then
        ctx.goldEarning = ctx.goldEarning * 3
    end
end

function M._applyGoldStreak(ctx)
    if ctx.goldEarning <= 0 then return end
    local val = Upgrades.GetEffectValue("gold_streak")
    if val <= 0 then return end

    local ball = ctx.ball
    if ball.timeSinceLastPeg < 0.5 then
        ball.streakCount = (ball.streakCount or 0) + 1
    else
        ball.streakCount = 1
    end

    if ball.streakCount > 1 then
        ctx.goldEarning = math_floor(ctx.goldEarning * (1 + val * ball.streakCount))
    end
end

function M._applyGoldAura(ctx)
    if ctx.goldEarning <= 0 then return end
    local val = Upgrades.GetEffectValue("gold_aura")
    if val <= 0 then return end

    local nearbyPegs = findPegsInRadius(ctx.peg, ctx.allPegs, 30)
    local auraGold = math_floor(ctx.goldEarning * val)
    if auraGold <= 0 then return end
    -- 批量计算总额，不再逐个 AddEarnings 也不再虚增 pegHits
    local totalAuraGold = auraGold * #nearbyPegs
    if totalAuraGold > 0 then
        State.AddEarnings(totalAuraGold)
        ctx.ball.totalGoldEarned = (ctx.ball.totalGoldEarned or 0) + totalAuraGold
    end
end

function M._applyGoldEmber(ctx)
    if ctx.goldEarning <= 0 then return end
    local val = Upgrades.GetEffectValue("gold_ember")
    if val <= 0 then return end

    local emberAmount = math_floor(ctx.goldEarning * val)
    if emberAmount > 0 then
        if not ctx.ball.embers then ctx.ball.embers = {} end
        table.insert(ctx.ball.embers, _acquireEmber(emberAmount, 4))
    end
end

--- 黄金弹钉产出入账 + 记录 totalGoldEarned
function M._recordGoldEarned(ctx)
    if ctx.goldEarning > 0 then
        State.AddEarnings(ctx.goldEarning)
        ctx.ball.totalGoldEarned = (ctx.ball.totalGoldEarned or 0) + ctx.goldEarning
        -- 记入 pegHitBonus 供印记/共振放大
        ctx.pegHitBonus = ctx.pegHitBonus + ctx.goldEarning
    end
end

-- ============================================================================
-- Phase 3: 其他即时收益
-- ============================================================================

function M._applyPegChain(ctx)
    local val = Upgrades.GetEffectValue("peg_chain")
    if val <= 0 then return end

    local ball = ctx.ball
    if ball.timeSinceLastPeg < 0.3 then
        ball.chainCount = (ball.chainCount or 0) + 1
    else
        ball.chainCount = 1
    end

    if ball.chainCount >= 2 then
        local chainBonus = math_floor(ball.chainCount * val * ball.value)
        if chainBonus > 0 then
            State.AddEarnings(chainBonus)
            ctx.pegHitBonus = ctx.pegHitBonus + chainBonus
        end
    end
end

function M._applyPegCharge(ctx)
    local val = Upgrades.GetEffectValue("peg_charge")
    if val <= 0 then
        return
    end

    local peg = ctx.peg
    local ball = ctx.ball

    if peg.chargedBy and peg.chargedBy ~= ball then
        -- 触发充能
        local chargeBonus = math_floor(ball.value * val)
        if chargeBonus > 0 then
            State.AddEarnings(chargeBonus)
            ctx.pegHitBonus = ctx.pegHitBonus + chargeBonus
        end
        peg.chargedBy = nil
        peg.chargeTimer = nil
        _removeDirtyPeg(peg)
    else
        -- 设置充能
        peg.chargedBy = ball
        peg.chargeTimer = 3.0
        _addDirtyPeg(peg)
    end
end

function M._applyPegMark(ctx)
    local val = Upgrades.GetEffectValue("peg_mark")
    if val <= 0 then return end

    local peg = ctx.peg
    local ball = ctx.ball

    -- 撞到印记钉时：放大本次所有即时收益
    if peg.markedBy and peg.markedBy ~= ball and ctx.pegHitBonus > 0 then
        local markBonus = math_floor(ctx.pegHitBonus * val)
        if markBonus > 0 then
            State.AddEarnings(markBonus)
            ctx.pegHitBonus = ctx.pegHitBonus + markBonus
        end
    end

    -- 标记钉
    peg.markedBy = ball
    peg.markTimer = 5.0
    _addDirtyPeg(peg)
end

function M._applyPegSync(ctx)
    local val = Upgrades.GetEffectValue("peg_sync")
    if val <= 0 then return end

    local otherBalls = #ctx.allBalls - 1
    if otherBalls > 0 and ctx.pegHitBonus > 0 then
        local syncBonus = math_floor(ctx.pegHitBonus * val * otherBalls)
        if syncBonus > 0 then
            State.AddEarnings(syncBonus)
        end
    end
end

function M._applyPegGem(ctx)
    local val = Upgrades.GetEffectValue("peg_gem")
    if val > 0 and math_random() < val then
        State.AddGems(1)
    end
end

function M._applyPegSpark(ctx)
    local val = Upgrades.GetEffectValue("peg_spark")
    if val <= 0 then return end

    if math_random() < val then
        local nearest = findNearestPeg(ctx.peg, ctx.allPegs)
        if nearest then
            -- 递归一次（isSpark=true）
            nearest.hitTimer = CONFIG.PEG_HIT_DURATION
            M.OnPegHit(ctx.ball, nearest, ctx.allPegs, ctx.allBalls, true)
        end
    end
end

function M._applyBallPegEffects(ctx)
    local ball = ctx.ball
    local ballType = Config.BALL_TYPES[ball.typeIndex]
    local eff = ballType and ballType.effect
    if not eff then return end

    local pegBonus = eff.pegBonus or 0
    if eff.id == "midas" then
        local goldBoost = Upgrades.GetEffectValue("gold_boost")
        pegBonus = pegBonus + goldBoost
        -- 金球宝石产出
        local gemChance = eff.gemChance or 0
        if gemChance > 0 and math_random() < gemChance then
            State.AddGems(1)
        end
    elseif eff.id == "blaze" then
        local rubyBoost = Upgrades.GetEffectValue("ruby_boost")
        if rubyBoost > 0 then
            pegBonus = pegBonus * rubyBoost
        end
    end

    if pegBonus > 0 then
        State.AddEarnings(pegBonus)
    end

    -- 节律变奏：琥珀球速度越快撞钉产金越多
    if eff.id == "tempo" then
        local tempoShiftVal = Upgrades.GetEffectValue("tempo_shift")
        if tempoShiftVal > 0 then
            local speedBonus = ball.tempoSpeedBonus or 0
            if speedBonus > 0 then
                -- 每 10% 速度加成产金 = tempoShiftVal% × 球价值
                local layers = speedBonus / 0.10
                local tempoGold = math_floor(ball.value * tempoShiftVal * layers)
                if tempoGold > 0 then
                    State.AddEarnings(tempoGold)
                end
            end
        end
    end
end

--- 弹钉奖金：每次撞钉额外获得球价值百分比的金币
function M._applyPegBonus(ctx)
    local val = Upgrades.GetEffectValue("peg_bonus")
    if val <= 0 then return end
    local bonus = math_floor(ctx.ball.value * val)
    if bonus > 0 then
        State.AddEarnings(bonus)
        ctx.pegHitBonus = ctx.pegHitBonus + bonus
    end
end

-- ============================================================================
-- Phase 4: 物理修改
-- ============================================================================

function M._applyPegLaunch(ctx)
    local val = Upgrades.GetEffectValue("peg_launch")
    if val > 0 then
        ctx.ball.vx = ctx.ball.vx * (1 + val)
        ctx.ball.vy = ctx.ball.vy * (1 + val)
    end
end

function M._applyPegSlow(ctx)
    local val = Upgrades.GetEffectValue("peg_slow")
    if val > 0 then
        ctx.ball.vx = ctx.ball.vx * (1 - val)
        ctx.ball.vy = ctx.ball.vy * (1 - val)
    end
end

function M._applyPegWave(ctx)
    local val = Upgrades.GetEffectValue("peg_wave")
    if val <= 0 then return end

    -- 单球早退：只有 1 个球时无需波动
    local allBalls = ctx.allBalls
    local ballCount = #allBalls
    if ballCount <= 1 then return end

    local ball = ctx.ball
    local bx, by = ball.x, ball.y
    local r2 = 1600  -- 40^2
    for bi = 1, ballCount do
        local other = allBalls[bi]
        if other ~= ball and other.alive then
            local dx = bx - other.x
            local dy = by - other.y
            local d2 = dx * dx + dy * dy
            -- 距离平方比较，避免 sqrt；d2 > 0.01 防止自身重叠
            if d2 < r2 and d2 > 0.01 then
                local nearestPeg = findNearestUnhitPeg(other, ctx.allPegs)
                if nearestPeg then
                    local dirX = nearestPeg.x - other.x
                    local dirY = nearestPeg.y - other.y
                    local dirLen2 = dirX * dirX + dirY * dirY
                    if dirLen2 > 0.01 then
                        local invLen = val / math_sqrt(dirLen2)
                        other.vx = other.vx + dirX * invLen
                        other.vy = other.vy + dirY * invLen
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 流派B：连锁反应
-- ============================================================================

--- 连锁闪电：撞钉时概率额外触发一颗未命中的钉
function M._applyChainLightning(ctx)
    if ctx.isSpark then return end  -- 防止递归
    local val = Upgrades.GetEffectValue("chain_lightning")
    if val <= 0 then return end

    if math_random() < val then
        -- 查找附近未被当前球撞过的钉（上方优先，用空间网格加速）
        local pegsToSearch = queryNearbyPegs and queryNearbyPegs(ctx.peg.x, ctx.peg.y) or ctx.allPegs
        local best, bestDist = nil, math_huge
        for _, p in ipairs(pegsToSearch) do
            if p ~= ctx.peg then
                local d = dist(ctx.peg.x, ctx.peg.y, p.x, p.y)
                -- 优先上方的钉（y 更小的）
                local bias = (p.y < ctx.peg.y) and 0.8 or 1.2
                if d * bias < bestDist then
                    bestDist = d * bias
                    best = p
                end
            end
        end
        if best then
            best.hitTimer = CONFIG.PEG_HIT_DURATION
            M.OnPegHit(ctx.ball, best, ctx.allPegs, ctx.allBalls, true)
        end
    end
end

--- 回响打击：撞钉≥10次后每次撞钉额外获得即时金币
function M._applyEchoHit(ctx)
    local val = Upgrades.GetEffectValue("echo_hit")
    if val <= 0 then return end

    if (ctx.ball.pegHits or 0) >= 10 then
        local bonus = math_floor(ctx.ball.value * val)
        if bonus > 0 then
            State.AddEarnings(bonus)
            ctx.pegHitBonus = ctx.pegHitBonus + bonus
        end
    end
end

-- ============================================================================
-- 流派D：灼烧蔓延
-- ============================================================================

--- 灼烧蔓延：灼烧球撞钉时概率点燃相邻钉
function M._applyBurnSpread(ctx)
    local val = Upgrades.GetEffectValue("burn_spread")
    if val <= 0 then return end

    -- 只有灼烧球才能触发
    local ballType = Config.BALL_TYPES[ctx.ball.typeIndex]
    local eff = ballType and ballType.effect
    if not eff or eff.id ~= "blaze" then return end

    if math_random() < val then
        -- 点燃相邻 1 颗未燃烧的钉
        local nearby = findPegsInRadius(ctx.peg, ctx.allPegs, 30)
        for _, p in ipairs(nearby) do
            if not p.burning then
                p.burning = true
                p.burnTimer = 3.0
                -- 记录灼烧金额（取灼烧球的 pegBonus）
                local pegBonus = eff.pegBonus or 2
                local rubyBoost = Upgrades.GetEffectValue("ruby_boost")
                if rubyBoost > 0 then pegBonus = pegBonus * rubyBoost end
                p.burnGold = num_floor(pegBonus)
                _addDirtyPeg(p)
                break  -- 只点燃 1 颗
            end
        end
    end
end

--- 灼烧余温：被灼烧的钉被任意球撞到时额外产金
function M._applyBurnLinger(ctx)
    local val = Upgrades.GetEffectValue("burn_linger")
    if val <= 0 then return end

    local peg = ctx.peg
    if peg.burning and peg.burnGold and peg.burnGold > 0 then
        local bonus = math_floor(peg.burnGold * val)
        if bonus > 0 then
            State.AddEarnings(bonus)
            ctx.pegHitBonus = ctx.pegHitBonus + bonus
            -- 记录到球的灼烧收益（供 burn_climax 使用）
            ctx.ball.burnEarned = (ctx.ball.burnEarned or 0) + bonus
            ctx.ball.burnCount = (ctx.ball.burnCount or 0) + 1
        end
    end
end

--- 灼烧淬炼：每灼烧 1 颗钉，球价值永久 +value%
function M._applyBurnEmpower(ctx)
    local val = Upgrades.GetEffectValue("burn_empower")
    if val <= 0 then return end

    -- 只有灼烧球撞钉时才累积
    local ballType = Config.BALL_TYPES[ctx.ball.typeIndex]
    local eff = ballType and ballType.effect
    if not eff or eff.id ~= "blaze" then return end

    -- 灼烧球每次撞钉都视为"灼烧 1 颗钉"
    ctx.ball.burnCount = (ctx.ball.burnCount or 0) + 1
    local empowerBonus = math_floor(ctx.ball.value * val)
    if empowerBonus > 0 then
        ctx.ball.value = ctx.ball.value + empowerBonus
    end
end

-- ============================================================================
-- 流派A：时间掌控
-- ============================================================================

--- 时间收割：每次撞钉延长轮次时间（上限不超过初始时间 ×2）
function M._applyTimeHarvest(ctx)
    local val = Upgrades.GetEffectValue("time_harvest")
    if val <= 0 then return end

    local maxTime = Config.ROUND.TIME_LIMIT * 2
    if gameState.roundTimeLeft < maxTime then
        gameState.roundTimeLeft = num_min(maxTime, gameState.roundTimeLeft + val)
    end
end

-- ============================================================================
-- 流派F：巨力碾压
-- ============================================================================

-- ============================================================================
-- 连击补强
-- ============================================================================

--- 连击延续：每次撞钉延长连击窗口 +value 秒
function M._applyComboExtend(ctx)
    local val = Upgrades.GetEffectValue("combo_extend")
    if val <= 0 then return end

    -- 只有连击风暴已激活且窗口开启时才有意义
    if gameState.comboTimer > 0 then
        gameState.comboTimer = gameState.comboTimer + val
    end
end

--- 成长动能：每撞 1 颗钉球价值 +value%（基于初始价值，线性叠加）
function M._applyGrowthMomentum(ctx)
    local val = Upgrades.GetEffectValue("growth_momentum")
    if val <= 0 then return end

    local ball = ctx.ball
    ball.baseValue = ball.baseValue or ball.value
    local bonus = math_floor(ball.baseValue * val * (ball.pegHits or 1))
    ball.value = ball.baseValue + bonus
end

-- ============================================================================
-- 事件订阅：效果变化时重建活跃处理器列表
-- ============================================================================
EventBus.on("effect_drawn", function() _activeHandlersDirty = true end)
EventBus.on("effect_upgraded", function() _activeHandlersDirty = true end)
EventBus.on("rune_upgraded", function() _activeHandlersDirty = true end)
EventBus.on("enchant_changed", function() _activeHandlersDirty = true end)
EventBus.on("round_started", function()
    -- 轮次开始时清空脏钉集合
    _dirtyPegs = {}
    _dirtyPegList = {}
    _dirtyPegListDirty = true
    -- 重建处理器（存档加载可能改变效果）
    _activeHandlersDirty = true
end)

return M
