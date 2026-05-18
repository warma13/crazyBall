-- ============================================================================
-- IdleMode.lua - 放置模式自包含核心模块
-- 物理 / 渲染 / 升级 / 转生 全部内聚于此
-- ============================================================================

local Config = require("Config")
local BigNum = require("BigNum")
local State  = require("State")

local CONFIG   = Config.CONFIG
local gameState = State.gameState
local S        = State.S

local math_floor  = math.floor
local math_max    = math.max
local math_min    = math.min
local math_random = math.random
local math_sin    = math.sin
local math_cos    = math.cos
local math_abs    = math.abs
local math_ceil   = math.ceil
local math_sqrt   = math.sqrt

local M = {}

-- ============================================================================
-- 内部状态（不需要持久化，每次进入时重建）
-- ============================================================================
local pegs   = {}       -- 放置模式钉子
local balls  = {}       -- 放置模式弹珠
local popups = {}       -- 飘字
local slots  = {}       -- 指向 gameState.idleSlots 的引用

-- 棋盘布局
local boardLeft, boardRight, boardTop, boardBottom = 0, 0, 0, 0
local contentLeft, contentRight, contentTop, contentBottom = 0, 0, 0, 0
local boardScale = 1
local slotWidth  = 0
local splitY     = 0
local slotEdges   = {}  -- 每个 slot 的左边界数组
local slotCenters = {}  -- 每个 slot 的中心 x 坐标
local slotWidths  = {}  -- 每个 slot 的实际宽度
local screenW, screenH = 0, 0

-- 空间网格
local grid = {}
local gridCellSize = 0
local gridCols, gridRows = 0, 0
local gridOffsetX, gridOffsetY = 0, 0
local _nearbyResult = {}

-- UI 面板状态（TopBar 返回按钮仍用 NanoVG）
local backBtnRect = nil

-- 投放冷却
local dropCooldownTimer = 0  -- 剩余冷却时间
local skyDropTimer = 0       -- 天降弹珠计时器

-- 连击风暴状态
local comboCount = 0         -- 当前连击数
local comboTimer = 0         -- 连击窗口剩余时间

-- CD 主动技能运行时状态（不持久化，每次 Enter 重建）
local skillCooldowns = {}    -- { [skillId] = remainingCD }

-- 缓存的币种字符串
local cachedGoldStr = ""
local cachedGoldRef = nil
local cachedBallCoinStr = ""
local cachedBallCoinRef = nil

-- HUD 图标缓存（NanoVG image handle）
local hudGoldImg = nil        -- 金币图片
local hudBallImg = nil         -- 球皮肤图片
local hudBallSkinKey = nil     -- 当前缓存的球皮肤 key

-- 前向声明
local CheckSlotAutoUpgrade
local EnsureLevelData

-- ============================================================================
-- 工具函数
-- ============================================================================

local function HitRect(rect, lx, ly)
    if not rect then return false end
    return lx >= rect.x and lx <= rect.x + rect.w
       and ly >= rect.y and ly <= rect.y + rect.h
end

local function gridKey(col, row)
    return row * 1000 + col
end

-- ============================================================================
-- 布局 & 钉子初始化
-- ============================================================================

function M.RecalcLayout()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr   = graphics:GetDPR()
    local w = physW / dpr
    local h = physH / dpr

    screenW, screenH = w, h
    boardScale = w / 320

    splitY      = math_floor(h * CONFIG.BOARD_SPLIT_RATIO)
    boardLeft   = CONFIG.BOARD_PADDING_X
    boardRight  = w - CONFIG.BOARD_PADDING_X
    boardTop    = CONFIG.BOARD_MARGIN_TOP * boardScale + 30 * boardScale
    boardBottom = splitY

    -- 内容区域
    local cmx = CONFIG.CONTENT_MARGIN_X * boardScale
    local cmt = CONFIG.CONTENT_MARGIN_TOP * boardScale
    local cmb = CONFIG.CONTENT_MARGIN_BOT * boardScale
    contentLeft   = boardLeft + cmx
    contentRight  = boardRight - cmx
    contentTop    = boardTop + cmt
    contentBottom = boardBottom - cmb

    if #slots == 0 then return end
    -- 口袋边界和中心（按图片分隔线比例计算）
    local bW = boardRight - boardLeft
    local dividers = CONFIG.SLOT_DIVIDERS
    local innerL = CONFIG.SLOT_INNER_LEFT
    local innerR = CONFIG.SLOT_INNER_RIGHT
    slotEdges = { boardLeft + innerL * bW }
    for _, d in ipairs(dividers) do
        slotEdges[#slotEdges + 1] = boardLeft + d * bW
    end
    slotEdges[#slotEdges + 1] = boardLeft + innerR * bW
    slotCenters = {}
    slotWidths = {}
    local sc = #slots
    for i = 1, sc do
        local l = slotEdges[i] or slotEdges[1]
        local r = slotEdges[i + 1] or slotEdges[#slotEdges]
        slotCenters[i] = (l + r) / 2
        slotWidths[i] = r - l
    end
    slotWidth = bW / sc
end

function M.InitPegs()
    M.RecalcLayout()

    local cW = contentRight - contentLeft
    local cH = contentBottom - contentTop - CONFIG.SLOT_HEIGHT * boardScale
    if cH <= 0 or cW <= 0 then return end

    pegs = {}
    local rowSpacing = cH / (CONFIG.PEG_ROWS + 1)
    local slotCount  = #slots

    for row = 1, CONFIG.PEG_ROWS do
        local y = contentTop + row * rowSpacing
        local isOdd = (row % 2 == 1)
        local pegsInRow = isOdd and math_max(slotCount - 1, 2) or math_max(slotCount, 3)
        for col = 1, pegsInRow do
            local x
            if isOdd then
                x = contentLeft + col * (cW / (pegsInRow + 1))
            else
                x = contentLeft + (col - 0.5) * (cW / pegsInRow)
            end
            pegs[#pegs + 1] = { x = x, y = y, hitTimer = 0 }
        end
    end

    -- 重建空间网格
    grid = {}
    local pegR    = CONFIG.PEG_RADIUS * boardScale
    local maxBallR = CONFIG.BALL_RADIUS * boardScale * 2
    local cellSize = (pegR + maxBallR) * 2.5
    if cellSize < 10 then cellSize = 10 end
    gridCellSize = cellSize
    gridOffsetX  = contentLeft
    gridOffsetY  = contentTop
    gridCols = math_ceil(cW / cellSize) + 1
    gridRows = math_ceil(cH / cellSize) + 1

    for _, peg in ipairs(pegs) do
        local c = math_floor((peg.x - gridOffsetX) / cellSize)
        local r = math_floor((peg.y - gridOffsetY) / cellSize)
        local key = gridKey(c, r)
        if not grid[key] then grid[key] = {} end
        grid[key][#grid[key] + 1] = peg
    end
end

local function QueryNearbyPegs(bx, by)
    local col = math_floor((bx - gridOffsetX) / gridCellSize)
    local row = math_floor((by - gridOffsetY) / gridCellSize)
    local n = 0
    for dr = -1, 1 do
        for dc = -1, 1 do
            local cell = grid[gridKey(col + dc, row + dr)]
            if cell then
                for _, peg in ipairs(cell) do
                    n = n + 1
                    _nearbyResult[n] = peg
                end
            end
        end
    end
    for i = n + 1, #_nearbyResult do _nearbyResult[i] = nil end
    return _nearbyResult, n
end

-- ============================================================================
-- 球投放 & 物理
-- ============================================================================

-- ============================================================================
-- 全局升级系统（金币消费，永久生效，转生不重置）
-- ============================================================================

--- 获取指定升级的当前等级
---@param upgradeId string
---@return number
function M.GetUpgradeLevel(upgradeId)
    return gameState.idleUpgradeLevels[upgradeId] or 0
end

--- 购买一次升级（消耗金币）
---@param upgradeId string
---@return boolean
function M.PurchaseUpgrade(upgradeId)
    -- 查找配置
    local upgCfg
    for _, cfg in ipairs(Config.IDLE.UPGRADES) do
        if cfg.id == upgradeId then
            upgCfg = cfg
            break
        end
    end
    if not upgCfg then return false end

    -- 关卡解锁检查
    local reqLv = upgCfg.unlockLevel or 1
    if (gameState.idleMaxUnlockedLevel or 1) < reqLv then return false end

    local level = M.GetUpgradeLevel(upgradeId)
    if level >= upgCfg.maxLevel then return false end

    local cost = Config.GetUpgradeCost(upgCfg, level)
    if not State.SpendIdleCoins(BigNum.new(cost)) then return false end

    -- 升级
    gameState.idleUpgradeLevels[upgradeId] = level + 1
    local newLevel = level + 1

    -- 应用效果到全局变量
    M.ApplyUpgradeEffects()

    print(string.format("[IdleMode] Upgrade %s → Lv.%d", upgradeId, newLevel))
    return true
end

--- 根据 idleUpgradeLevels 重新计算所有全局加成
--- 进入放置模式时和每次升级后调用
function M.ApplyUpgradeEffects()
    local levels = gameState.idleUpgradeLevels

    -- base_value → idleGlobalBallValueBonus
    local baseValueLv = levels["base_value"] or 0
    gameState.idleGlobalBallValueBonus = baseValueLv * 0.5  -- perLevel=0.5

    -- slot_base → idleGlobalSlotMultBonus
    local slotBaseLv = levels["slot_base"] or 0
    gameState.idleGlobalSlotMultBonus = slotBaseLv * 1    -- perLevel=1

    -- drop_cooldown → 由 GetDropCooldown() 动态计算
    -- crit_chance / crit_mult → 由落袋逻辑动态计算
end

--- 获取当前掉落冷却时间（受 drop_cooldown 升级影响）
---@return number 冷却秒数
function M.GetDropCooldown()
    local lv = M.GetUpgradeLevel("drop_cooldown")
    -- 渐进递减: 3.5 / (1 + 0.15*lv)，前期降得快后期趋平，最低0.5s
    local val = 3.5 / (1 + 0.15 * lv)
    return math_max(0.5, val)
end

--- 获取暴击概率（百分比 0~100）
---@return number
function M.GetCritChance()
    local lv = M.GetUpgradeLevel("crit_chance")
    return lv * 1.5  -- perLevel=1.5%
end

--- 获取暴击倍率
---@return number
function M.GetCritMult()
    local lv = M.GetUpgradeLevel("crit_mult")
    return 2.0 + lv * 0.12  -- 基础2x + perLevel=0.12
end

--- 获取多重投放概率（受 multi_drop 影响）
function M.GetMultiDropChance()
    local lv = M.GetUpgradeLevel("multi_drop")
    return lv * 0.06
end

--- 获取转生加成倍率（受 prestige_boost 影响）
function M.GetPrestigeBoost()
    local lv = M.GetUpgradeLevel("prestige_boost")
    return 1.0 + lv * 0.15
end

--- 获取落袋奖励加成（受 coin_magnet 影响）
function M.GetCoinMagnetMult()
    local lv = M.GetUpgradeLevel("coin_magnet")
    return 1.0 + lv * 0.03
end

--- 获取撞钉奖励金币（受 peg_gold 影响）
function M.GetPegGold()
    local lv = M.GetUpgradeLevel("peg_gold")
    return lv * 0.5
end

--- 获取额外弹珠数（受 extra_ball 影响）
function M.GetExtraBalls()
    local lv = M.GetUpgradeLevel("extra_ball")
    return lv * 1
end

--- 获取天降弹珠间隔（受 sky_drop 影响）
function M.GetSkyDropInterval()
    local lv = M.GetUpgradeLevel("sky_drop")
    if lv <= 0 then return 0 end  -- 未激活
    local val = 8.0 / (1 + 0.12 * lv)
    return math_max(1.0, val)
end

--- 获取重力落袋加成倍率（受 heavy_landing 影响）
---@return number 加成倍率 (1.0+)
function M.GetHeavyLanding()
    local lv = M.GetUpgradeLevel("heavy_landing")
    return 1.0 + lv * 0.04
end

--- 获取连击风暴每次连击加成比例（受 combo_storm 影响）
---@return number 每次加成比例, number 连击窗口秒数
function M.GetComboStorm()
    local lv = M.GetUpgradeLevel("combo_storm")
    if lv <= 0 then return 0, 0 end
    return lv * 0.03, 3.0
end

--- 获取口袋祝福触发概率和倍数（受 slot_fortune 影响）
---@return number 概率 (0~0.50), number 倍数
function M.GetSlotFortune()
    local lv = M.GetUpgradeLevel("slot_fortune")
    if lv <= 0 then return 0, 1 end
    local chance = math_min(0.40, lv * 0.03)
    local mult = 2 + math_floor(lv / 6)
    return chance, mult
end

--- 获取收益放大最终倍率（受 earning_amp 影响）
---@return number 最终倍率 (1.0+)
function M.GetEarningAmp()
    local lv = M.GetUpgradeLevel("earning_amp")
    return 1.0 + lv * 0.05
end

-- ============================================================================
-- 弹珠能力升级系统（球币消费，永久生效，转生不重置）
-- ============================================================================

--- 获取当前关卡对应的弹珠类型索引（跟随当前关卡）
---@return number typeIndex
function M.GetCurrentBallType()
    return math_min(gameState.idleLevel, #Config.BALL_TYPES)
end

-- ============================================================================
-- 技能系统（通关三选一获取，CD 主动技能，转生不重置）
-- ============================================================================

--- 获取技能等级
---@param skillId string
---@return number
function M.GetSkillLevel(skillId)
    return gameState.idleSkills[skillId] or 0
end

--- 获取技能配置
---@param skillId string
---@return table|nil
function M.GetSkillConfig(skillId)
    for _, cfg in ipairs(Config.IDLE.SKILLS) do
        if cfg.id == skillId then return cfg end
    end
    return nil
end

--- 获取技能 CD（受等级影响）
---@param skillId string
---@return number CD 秒数
function M.GetSkillCooldown(skillId)
    local lv = M.GetSkillLevel(skillId)
    local cfg = M.GetSkillConfig(skillId)
    if not cfg then return 999 end
    return math_max(cfg.minCooldown or 5, cfg.cooldown - (lv - 1) * (cfg.cdPerLevel or 0))
end

--- 获取技能 CD 剩余时间
---@param skillId string
---@return number 剩余秒数（0=就绪）
function M.GetSkillCDRemaining(skillId)
    return skillCooldowns[skillId] or 0
end

--- 技能是否就绪（已获得 + CD 完毕）
---@param skillId string
---@return boolean
function M.IsSkillReady(skillId)
    if M.GetSkillLevel(skillId) <= 0 then return false end
    if (skillCooldowns[skillId] or 0) > 0 then return false end
    return true
end

--- 生成一组弹珠的辅助函数
---@param count number 数量
---@param opts table? { valueMult, radiusMult, startY, spread, vyBase, vxSpread }
local function SpawnBalls(count, opts)
    opts = opts or {}
    local typeIdx = M.GetCurrentBallType()
    local bt = Config.BALL_TYPES[typeIdx]
    if not bt then return end

    local valueMult = opts.valueMult or 1
    local radiusMult = opts.radiusMult or 1
    local startY = opts.startY or (contentTop - 5)
    local vyBase = opts.vyBase or 0
    local vxSpread = opts.vxSpread or 30
    local spread = opts.spread or 0.08

    local ballBaseVal = 1 + M.GetBallValueBonus()
    local ballCoinVal = ballBaseVal * M.GetBallMultiplier() * gameState.idlePrestigeMult * valueMult
    local goldBaseVal = M.GetBaseBallValue()
    local goldCoinVal = goldBaseVal * gameState.idlePrestigeMult * valueMult
    local val = math_max(ballCoinVal, goldCoinVal)
    local bs = boardScale
    local margin = (contentRight - contentLeft) * spread
    local baseR = CONFIG.BALL_RADIUS * bs * radiusMult

    for mi = 1, count do
        if #balls < CONFIG.MAX_BALLS then
            local bx = opts.x or (contentLeft + margin + math_random() * (contentRight - contentLeft - margin * 2))
            balls[#balls + 1] = {
                x = bx,
                y = startY - math_random() * 10,
                vx = (math_random() - 0.5) * vxSpread * bs,
                vy = vyBase,
                radius = baseR,
                typeIndex = typeIdx,
                value = val,
                ballCoinValue = ballCoinVal,
                goldCoinValue = goldCoinVal,
                trail = {},
                alive = true,
                pegHits = 0,
                aliveTime = 0,
                baseRadius = baseR,
                noPegCollision = opts.noPegCollision or false,
            }
            gameState.idleBallsDropped = gameState.idleBallsDropped + 1
        end
    end
end

--- 执行 instant 技能（所有特效技能统一入口）
local function ExecuteInstantSkill(skillId)
    local lv = M.GetSkillLevel(skillId)
    local cfg = M.GetSkillConfig(skillId)
    if not cfg then return end

    local bs = boardScale

    -- ── mass_drop / ball_rain：经典掉球 ──
    if skillId == "mass_drop" or skillId == "ball_rain" then
        local count = cfg.baseBallCount + (lv - 1) * (cfg.ballCountPerLv or 0)
        SpawnBalls(count)
        print(string.format("[IdleMode] Skill %s: dropped %d balls", skillId, count))

    -- ── giant_ball：投放一颗超大弹珠 ──
    elseif skillId == "giant_ball" then
        local sizeMult = cfg.baseSize + (lv - 1) * cfg.sizePerLv
        local valMult = cfg.baseValueMult + (lv - 1) * cfg.valueMultPerLv
        local cx = (contentLeft + contentRight) / 2
        SpawnBalls(1, {
            x = cx,
            radiusMult = sizeMult,
            valueMult = valMult,
            vxSpread = 10,
            noPegCollision = true,
        })
        print(string.format("[IdleMode] Skill giant_ball: size=%.1fx value=%dx", sizeMult, valMult))

    -- ── fireworks：从棋盘中心爆出多波弹珠，向四周扩散 ──
    elseif skillId == "fireworks" then
        local waves = cfg.baseWaves + (lv - 1) * cfg.wavesPerLv
        local perWave = cfg.ballsPerWave
        local cx = (contentLeft + contentRight) / 2
        local cy = (contentTop + contentBottom) / 2
        for w = 1, waves do
            for b = 1, perWave do
                if #balls < CONFIG.MAX_BALLS then
                    local angle = (b - 1) / perWave * math.pi * 2 + (w - 1) * 0.3
                    local speed = (60 + w * 20) * bs
                    local ballBaseVal = 1 + M.GetBallValueBonus()
                    local bCV = ballBaseVal * M.GetBallMultiplier() * gameState.idlePrestigeMult
                    local gCV = M.GetBaseBallValue() * gameState.idlePrestigeMult
                    local typeIdx = M.GetCurrentBallType()
                    local baseR = CONFIG.BALL_RADIUS * bs
                    balls[#balls + 1] = {
                        x = cx + math_cos(angle) * 10 * w,
                        y = cy + math_sin(angle) * 10 * w,
                        vx = math_cos(angle) * speed,
                        vy = math_sin(angle) * speed,
                        radius = baseR,
                        typeIndex = typeIdx,
                        value = math_max(bCV, gCV),
                        ballCoinValue = bCV,
                        goldCoinValue = gCV,
                        trail = {},
                        alive = true,
                        pegHits = 0,
                        aliveTime = 0,
                        baseRadius = baseR,
                    }
                    gameState.idleBallsDropped = gameState.idleBallsDropped + 1
                end
            end
        end
        print(string.format("[IdleMode] Skill fireworks: %d waves x %d = %d balls", waves, perWave, waves * perWave))

    -- ── golden_shower：从天上均匀降下一排高价值金色弹珠 ──
    elseif skillId == "golden_shower" then
        local count = cfg.baseBallCount + (lv - 1) * cfg.ballCountPerLv
        local valMult = cfg.baseValueMult + (lv - 1) * cfg.valueMultPerLv
        local margin = (contentRight - contentLeft) * 0.05
        for gi = 1, count do
            if #balls < CONFIG.MAX_BALLS then
                local frac = (gi - 0.5) / count
                local gx = contentLeft + margin + frac * (contentRight - contentLeft - margin * 2)
                SpawnBalls(1, {
                    x = gx,
                    valueMult = valMult,
                    startY = contentTop - 15 - math_random() * 20,
                    vxSpread = 5,
                })
            end
        end
        print(string.format("[IdleMode] Skill golden_shower: %d golden balls x%d value", count, valMult))

    -- ── peg_explosion：所有钉子爆炸，每颗钉产生金币 + 钉子闪烁 ──
    elseif skillId == "peg_explosion" then
        local goldPerPeg = cfg.baseGoldPerPeg + (lv - 1) * cfg.goldPerPegPerLv
        local pegCount = #pegs
        local totalGold = goldPerPeg * pegCount * gameState.idlePrestigeMult
        State.AddIdleEarnings(totalGold)
        -- 所有钉子视觉闪烁
        for _, peg in ipairs(pegs) do
            peg.hitTimer = 1.5  -- 比正常撞击更长的闪烁
        end
        -- 飘字显示总收益
        popups[#popups + 1] = {
            x = (contentLeft + contentRight) / 2,
            y = (contentTop + contentBottom) / 2,
            text = "+" .. State.FormatNumber(totalGold) .. " 爆破!",
            timer = 2.0,
            color = { 255, 80, 40, 255 },
            iconType = "gold",
            vx = 0,
            vy = -60,
            elapsed = 0,
        }
        print(string.format("[IdleMode] Skill peg_explosion: %d pegs x %d gold = %s total",
            pegCount, goldPerPeg, State.FormatNumber(totalGold)))

    -- ── split_burst：场上所有弹珠立即分裂 ──
    elseif skillId == "split_burst" then
        local splitCount = cfg.baseSplitCount + (lv - 1) * cfg.splitPerLv
        local currentBalls = {}
        for _, b in ipairs(balls) do
            if b.alive then
                currentBalls[#currentBalls + 1] = b
            end
        end
        local spawned = 0
        for _, b in ipairs(currentBalls) do
            for si = 1, splitCount do
                if #balls < CONFIG.MAX_BALLS then
                    local angle = (si - 1) / splitCount * math.pi * 2 + math_random() * 0.5
                    local speed = 40 * bs
                    balls[#balls + 1] = {
                        x = b.x + math_cos(angle) * b.radius,
                        y = b.y + math_sin(angle) * b.radius,
                        vx = b.vx * 0.5 + math_cos(angle) * speed,
                        vy = b.vy * 0.5 + math_sin(angle) * speed,
                        radius = b.radius * 0.8,
                        typeIndex = b.typeIndex,
                        value = b.value * 0.6,
                        ballCoinValue = (b.ballCoinValue or b.value) * 0.6,
                        goldCoinValue = (b.goldCoinValue or b.value) * 0.6,
                        trail = {},
                        alive = true,
                        pegHits = 0,
                        aliveTime = 0,
                        baseRadius = b.baseRadius * 0.8,
                    }
                    spawned = spawned + 1
                    gameState.idleBallsDropped = gameState.idleBallsDropped + 1
                end
            end
        end
        print(string.format("[IdleMode] Skill split_burst: %d balls x %d splits = %d new",
            #currentBalls, splitCount, spawned))

    -- ── slot_jackpot：所有底袋同时喷出金币奖励 ──
    elseif skillId == "slot_jackpot" then
        local multPerSlot = cfg.baseMultPerSlot + (lv - 1) * cfg.multPerSlotPerLv
        local totalGold = BigNum.new(0)
        for si = 1, #slots do
            local slot = slots[si]
            local slotMult = Config.GetSlotMult(slot.level or 1)
            local goldBase = M.GetBaseBallValue() * gameState.idlePrestigeMult
            local earn = math_floor(goldBase * slotMult * multPerSlot)
            if earn < 1 then earn = multPerSlot end
            totalGold = totalGold + earn
            -- 每个底袋单独飘字
            local sx = slotCenters[si] or (boardLeft + (si - 0.5) * slotWidth)
            local slotY = contentBottom - CONFIG.SLOT_HEIGHT * boardScale
            popups[#popups + 1] = {
                x = sx, y = slotY - 5,
                text = "+" .. State.FormatNumber(earn),
                timer = 1.8,
                color = { 255, 220, 80, 255 },
                iconType = "gold",
                vx = (math_random() - 0.5) * 20,
                vy = -(60 + math_random() * 40),
                elapsed = 0,
            }
        end
        State.AddIdleEarnings(totalGold)
        print(string.format("[IdleMode] Skill slot_jackpot: %d slots x %d mult = %s gold",
            #slots, multPerSlot, State.FormatNumber(totalGold)))
    end
end

--- 激活技能（玩家点击技能按钮时调用）
---@param skillId string
---@return boolean 是否成功激活
function M.ActivateSkill(skillId)
    if not M.IsSkillReady(skillId) then return false end

    local cfg = M.GetSkillConfig(skillId)
    if not cfg then return false end

    ExecuteInstantSkill(skillId)
    skillCooldowns[skillId] = M.GetSkillCooldown(skillId)

    print(string.format("[IdleMode] Activated skill: %s", skillId))
    return true
end

--- 每帧更新技能 CD 和 buff 计时器（CD 满后自动释放）
---@param dt number
function M.UpdateSkills(dt)
    -- 更新 CD 计时器
    for skillId, remaining in pairs(skillCooldowns) do
        if remaining > 0 then
            remaining = remaining - dt
            if remaining < 0 then remaining = 0 end
            skillCooldowns[skillId] = remaining
        end
    end
    -- CD 满后自动释放已获得的技能
    for _, cfg in ipairs(Config.IDLE.SKILLS) do
        if M.IsSkillReady(cfg.id) then
            M.ActivateSkill(cfg.id)
        end
    end
end

--- 获取所有已获得技能的运行时状态（供 UI 使用）
---@return table[] { id, cfg, level, cdRemaining, ready }
function M.GetSkillStates()
    local result = {}
    for _, cfg in ipairs(Config.IDLE.SKILLS) do
        local lv = M.GetSkillLevel(cfg.id)
        if lv > 0 then
            result[#result + 1] = {
                id = cfg.id,
                cfg = cfg,
                level = lv,
                cdRemaining = skillCooldowns[cfg.id] or 0,
                ready = M.IsSkillReady(cfg.id),
            }
        end
    end
    return result
end

--- 检查通关条件：所有球升级达到 goalLevel → 触发技能选择
--- 返回 true 表示刚刚触发了技能选择
function M.CheckSkillTrigger()
    local currentLevel = gameState.idleLevel
    if currentLevel ~= gameState.idleMaxUnlockedLevel then return false end
    local allDone, _, _ = M.CheckAllGoalsDone()
    if not allDone then return false end

    -- 触发三选一
    local choices = M.RollSkillChoices()
    if #choices == 0 then return false end
    local IdleUI = require("IdleUI")
    IdleUI.ShowSkillPickPopup(choices, function(skillId)
        M.ApplySkillChoice(skillId)
        IdleUI.RefreshCurrentTab()
    end)
    return true
end

--- 玩家选择技能后调用
---@param skillId string
function M.ApplySkillChoice(skillId)
    local cfg = M.GetSkillConfig(skillId)
    if not cfg then return end

    local curLv = M.GetSkillLevel(skillId)
    if curLv < cfg.maxLevel then
        gameState.idleSkills[skillId] = curLv + 1
    end

    -- 推进阶段
    gameState.idleSkillPickCount = gameState.idleSkillPickCount + 1

    -- 解锁新关 + 重置球升级
    local nextLevel = gameState.idleLevel + 1
    gameState.idleMaxUnlockedLevel = nextLevel
    gameState.idleBallAbilityLevels = {}   -- 球升级重置

    -- 自动切换到新关
    M.SwitchToLevel(nextLevel)

    -- 解锁触发锁，允许下一轮检测
    M._skillTriggerLock = false

    print(string.format("[IdleMode] Skill chosen: %s → Lv.%d, stage=%d",
        skillId, M.GetSkillLevel(skillId), gameState.idleSkillPickCount))

    State.uiDirty = true
    local SaveSystem = require("SaveSystem")
    SaveSystem.Save()
end

--- 随机抽取3个可选技能（优先未满级、未获得的技能）
---@return table[] 3个技能配置的数组
function M.RollSkillChoices()
    local pool = {}
    for _, cfg in ipairs(Config.IDLE.SKILLS) do
        local lv = M.GetSkillLevel(cfg.id)
        if lv < cfg.maxLevel then
            pool[#pool + 1] = cfg
        end
    end
    -- 如果可选不足3个，允许已满级重复出现（不会升级）
    if #pool < 3 then
        for _, cfg in ipairs(Config.IDLE.SKILLS) do
            local found = false
            for _, p in ipairs(pool) do
                if p.id == cfg.id then found = true; break end
            end
            if not found then pool[#pool + 1] = cfg end
            if #pool >= 3 then break end
        end
    end
    -- Fisher-Yates 洗牌后取前3
    for i = #pool, 2, -1 do
        local j = math_random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local choices = {}
    for i = 1, math_min(3, #pool) do
        choices[i] = pool[i]
    end
    return choices
end

--- 获取当前球类型的升级配置列表
---@return table[] 当前球类型的升级配置列表
function M.GetCurrentBallUpgrades()
    local typeIdx = M.GetCurrentBallType()
    local bt = Config.BALL_TYPES[typeIdx]
    if bt and bt.effect then
        return Config.GetBallUpgradesForType(bt.effect.id)
    end
    return Config.BALL_UPGRADES  -- fallback
end

--- 获取弹珠能力升级当前等级
---@param abilityId string
---@return number
function M.GetBallAbilityLevel(abilityId)
    return gameState.idleBallAbilityLevels[abilityId] or 0
end

--- 检查指定升级项是否已解锁（前一项等级 >= unlockReq）
---@param index number 升级项索引（1-based）
---@return boolean
function M.IsBallAbilityUnlocked(index)
    local upgrades = M.GetCurrentBallUpgrades()
    local cfg = upgrades[index]
    if not cfg then return false end
    if index == 1 then return true end  -- 第一项始终可用
    local prevCfg = upgrades[index - 1]
    if not prevCfg then return true end
    local prevLevel = M.GetBallAbilityLevel(prevCfg.id)
    return prevLevel >= (cfg.unlockReq or 0)
end

--- 检查所有升级项是否都达到 goalLevel（解锁下一关条件）
---@return boolean allDone, number doneCount, number totalCount
function M.CheckAllGoalsDone()
    local upgrades = M.GetCurrentBallUpgrades()
    local done = 0
    local total = #upgrades
    for i, cfg in ipairs(upgrades) do
        local lv = M.GetBallAbilityLevel(cfg.id)
        local goal = cfg.goalLevel or 1
        if lv >= goal then
            done = done + 1
        end
    end
    return done >= total, done, total
end

--- 购买弹珠能力升级（消耗球币）
---@param abilityId string
---@return boolean
function M.PurchaseBallAbility(abilityId)
    local upgrades = M.GetCurrentBallUpgrades()
    local abCfg, abIdx
    for i, cfg in ipairs(upgrades) do
        if cfg.id == abilityId then
            abCfg = cfg
            abIdx = i
            break
        end
    end
    if not abCfg then return false end

    -- 检查是否已解锁
    if not M.IsBallAbilityUnlocked(abIdx) then return false end

    local level = M.GetBallAbilityLevel(abilityId)
    if level >= abCfg.maxLevel then return false end

    local cost = Config.GetUpgradeCost(abCfg, level)
    if not State.SpendIdleBallCoins(BigNum.new(cost)) then return false end

    gameState.idleBallAbilityLevels[abilityId] = level + 1
    print(string.format("[IdleMode] Ball ability %s → Lv.%d", abilityId, level + 1))

    -- 购买后立即检查是否所有目标达成 → 触发三选一
    local allDone, done, total = M.CheckAllGoalsDone()
    print(string.format("[IdleMode] Goals: %d/%d allDone=%s lock=%s",
        done, total, tostring(allDone), tostring(M._skillTriggerLock)))
    if allDone and not M._skillTriggerLock then
        if M.CheckSkillTrigger() then
            M._skillTriggerLock = true
        end
    end

    return true
end

--- 获取弹珠自动掉落间隔（ball_auto_drop 能力，所有球通用）
---@return number 0=未激活
function M.GetBallAutoDropInterval()
    local lv = M.GetBallAbilityLevel("ball_auto_drop")
    if lv <= 0 then return 0 end
    local val = 5.0 / (1 + 0.18 * lv)
    return math_max(0.8, val)
end

--- 获取弹珠额外基础价值（ball_base_value 能力，所有球通用）
---@return number
function M.GetBallValueBonus()
    local lv = M.GetBallAbilityLevel("ball_base_value")
    return lv * 0.5
end

--- 获取弹珠收益倍率（通过专属升级中的倍率类升级获取）
---@return number
function M.GetBallMultiplier()
    -- 通用的 ball_multiplier 不再存在，从专属升级中汇总倍率
    local mult = 1.0
    local upgrades = M.GetCurrentBallUpgrades()
    for _, cfg in ipairs(upgrades) do
        -- 匹配所有倍率类专属升级（含 "multiplier"/"endurance"/"touch"/"landing" 等）
        if cfg.perLevel and (
            cfg.id == "sturdy_endurance" or
            cfg.id == "midas_touch" or
            cfg.id == "blaze_multiplier"
        ) then
            local lv = M.GetBallAbilityLevel(cfg.id)
            mult = mult + lv * cfg.perLevel
        end
    end
    return mult
end

--- 获取弹珠额外暴击概率（百分比，从专属升级中获取）
---@return number 百分比
function M.GetBallCritBoost()
    local lv = M.GetBallAbilityLevel("crit_chance_up")
    if lv > 0 then return lv * 1.5 end
    -- 穿透暴击按钉数计算，这里返回基础值 0
    return 0
end

--- 获取撞钉递增加成比例（从专属升级中获取）
---@return number 每钉加成比例
function M.GetBallPegChain()
    local lv = M.GetBallAbilityLevel("pierce_chain")
    if lv > 0 then return lv * 0.03 end
    -- sturdy 的撞钉触发在物理层处理，这里返回 0
    return 0
end

--- 获取弹珠弹性加成（从专属升级中获取）
---@return number 弹跳恢复加成
function M.GetBallElasticity()
    local lv = M.GetBallAbilityLevel("bouncy_elasticity")
    if lv > 0 then return math_min(0.35, lv * 0.02) end
    return 0
end

-- ============================================================================
-- 球投放 & 物理
-- ============================================================================

--- 投放一颗球
function M.DropBall(dropX)
    if dropCooldownTimer > 0 then return false end
    if #balls >= CONFIG.MAX_BALLS then return false end

    -- 随机投放位置（覆盖棋盘宽度，留一点边距避免贴边）
    if not dropX then
        local margin = (contentRight - contentLeft) * 0.08
        dropX = contentLeft + margin + math_random() * (contentRight - contentLeft - margin * 2)
    end

    -- 按关卡决定弹珠类型（不再使用 idleSelectedBall）
    local typeIdx = M.GetCurrentBallType()
    local bt = Config.BALL_TYPES[typeIdx]
    if not bt then return false end

    -- 球币价值 = (基础1 + 弹珠能力加成) × 弹珠倍率 × 转生倍率（只受球升级影响）
    local ballBaseVal = 1 + M.GetBallValueBonus()
    local ballCoinValue = ballBaseVal * M.GetBallMultiplier() * gameState.idlePrestigeMult
    -- 金币价值 = (基础1 + 全局base_value加成) × 转生倍率（只受全局升级影响）
    local goldBaseVal = M.GetBaseBallValue()
    local goldCoinValue = goldBaseVal * gameState.idlePrestigeMult
    -- 兼容旧字段（用于显示等）
    local value = math_max(ballCoinValue, goldCoinValue)

    local bs = boardScale
    local ballRadius = CONFIG.BALL_RADIUS * bs

    balls[#balls + 1] = {
        x = dropX,
        y = contentTop - 5,
        vx = (math_random() - 0.5) * 20 * bs,
        vy = 0,
        radius = ballRadius,
        typeIndex = typeIdx,
        value = value,
        ballCoinValue = ballCoinValue,
        goldCoinValue = goldCoinValue,
        trail = {},
        alive = true,
        pegHits = 0,
        aliveTime = 0,
        baseRadius = ballRadius,
    }
    -- 播放音效
    if State.sfxBallDrop then
        local vol = gameState.settings.sfxVolume
        if vol > 0 and State.sfxScene_ then
            local node = State.sfxScene_:CreateChild("SFX")
            local src = node:CreateComponent("SoundSource")
            src.soundType = "Effect"
            src.gain = 0.3 * vol
            src.autoRemoveMode = REMOVE_NODE
            src:Play(State.sfxBallDrop)
        end
    end
    -- 额外弹珠（extra_ball 升级）
    local extraCount = M.GetExtraBalls()
    for e = 1, extraCount do
        if #balls < CONFIG.MAX_BALLS then
            local eMargin = (contentRight - contentLeft) * 0.08
            local ex = contentLeft + eMargin + math_random() * (contentRight - contentLeft - eMargin * 2)
            balls[#balls + 1] = {
                x = ex,
                y = contentTop - 5,
                vx = (math_random() - 0.5) * 20 * bs,
                vy = 0,
                radius = ballRadius,
                typeIndex = typeIdx,
                value = value,
                ballCoinValue = ballCoinValue,
                goldCoinValue = goldCoinValue,
                trail = {},
                alive = true,
                pegHits = 0,
                aliveTime = 0,
                baseRadius = ballRadius,
            }
        end
    end

    -- (ball_rain 已改为 CD 主动技能，由 ActivateSkill 触发)

    -- 多重投放（multi_drop 升级：概率额外掉一颗）
    local multiChance = M.GetMultiDropChance()
    if multiChance > 0 and math_random() < multiChance and #balls < CONFIG.MAX_BALLS then
        local mMargin = (contentRight - contentLeft) * 0.08
        local mx = contentLeft + mMargin + math_random() * (contentRight - contentLeft - mMargin * 2)
        balls[#balls + 1] = {
            x = mx,
            y = contentTop - 5,
            vx = (math_random() - 0.5) * 20 * bs,
            vy = 0,
            radius = ballRadius,
            typeIndex = typeIdx,
            value = value,
            ballCoinValue = ballCoinValue,
            goldCoinValue = goldCoinValue,
            trail = {},
            alive = true,
            pegHits = 0,
            aliveTime = 0,
            baseRadius = ballRadius,
        }
        extraCount = extraCount + 1
    end

    -- 掉球计数（保留用于统计/关卡进度；per-slot 升级在落袋检测处执行）
    gameState.idleBallsDropped = gameState.idleBallsDropped + 1 + extraCount

    dropCooldownTimer = M.GetDropCooldown()
    return true
end

--- 获取冷却进度（0=冷却中 1=就绪）
function M.GetDropCooldownProgress()
    if dropCooldownTimer <= 0 then return 1 end
    return 1 - dropCooldownTimer / M.GetDropCooldown()
end

function M.GetBoardCenterX()
    return (contentLeft + contentRight) / 2
end

--- 更新弹珠物理
function M.UpdateBalls(dt)
    local pegR = CONFIG.PEG_RADIUS * boardScale
    local gravity = CONFIG.GRAVITY * boardScale
    local elasticity = M.GetBallElasticity()
    local damping = math_min(0.95, CONFIG.BOUNCE_DAMPING + elasticity)
    local nudge   = CONFIG.RANDOM_NUDGE * boardScale
    local pegGold = M.GetPegGold()
    local coinMagnetMult = M.GetCoinMagnetMult()
    local pegChainRate = M.GetBallPegChain()
    local slotY   = contentBottom - CONFIG.SLOT_HEIGHT * boardScale
    local slotH   = CONFIG.SLOT_HEIGHT * boardScale
    local slotCount = #slots

    local i = 1
    while i <= #balls do
        local ball = balls[i]
        if not ball.alive then
            table.remove(balls, i)
        else
            ball.vy = ball.vy + gravity * dt
            ball.x  = ball.x + ball.vx * dt
            ball.y  = ball.y + ball.vy * dt
            ball.aliveTime = ball.aliveTime + dt

            -- 墙壁反弹
            if ball.x - ball.radius < contentLeft then
                ball.x = contentLeft + ball.radius
                ball.vx = math_abs(ball.vx) * damping
            elseif ball.x + ball.radius > contentRight then
                ball.x = contentRight - ball.radius
                ball.vx = -math_abs(ball.vx) * damping
            end

            -- 钉子碰撞（穿透球跳过）
            if not ball.noPegCollision then
                local nearby, cnt = QueryNearbyPegs(ball.x, ball.y)
                for j = 1, cnt do
                    local peg = nearby[j]
                    local dx = ball.x - peg.x
                    local dy = ball.y - peg.y
                    local dist = math_sqrt(dx * dx + dy * dy)
                    local minDist = ball.radius + pegR

                    if dist < minDist and dist > 0.001 then
                        -- 分离
                        local overlap = minDist - dist
                        local nx, ny = dx / dist, dy / dist
                        ball.x = ball.x + nx * overlap
                        ball.y = ball.y + ny * overlap

                        -- 反射
                        local dot = ball.vx * nx + ball.vy * ny
                        ball.vx = (ball.vx - 2 * dot * nx) * damping
                        ball.vy = (ball.vy - 2 * dot * ny) * damping

                        -- 随机偏转
                        ball.vx = ball.vx + (math_random() - 0.5) * nudge
                        ball.vy = ball.vy + (math_random() - 0.5) * nudge * 0.3

                        ball.pegHits = ball.pegHits + 1
                        peg.hitTimer = CONFIG.PEG_HIT_DURATION

                        -- 撞钉奖励（peg_gold 全局升级 → 加金币）
                        if pegGold > 0 then
                            State.AddIdleEarnings(pegGold)
                        end

                        -- 撞钉音效（每帧最多1次）
                        if not M._pegSfxThisFrame and State.sfxPegHit then
                            M._pegSfxThisFrame = true
                            local vol = gameState.settings.sfxVolume
                            if vol > 0 and State.sfxScene_ then
                                local node = State.sfxScene_:CreateChild("SFX")
                                local src = node:CreateComponent("SoundSource")
                                src.soundType = "Effect"
                                src.gain = 0.15 * vol
                                src.autoRemoveMode = REMOVE_NODE
                                src:Play(State.sfxPegHit)
                            end
                        end
                    end
                end
            end

            -- 落袋检测
            if ball.y >= slotY and ball.y < contentBottom + ball.radius * 2 then
                -- 按实际分隔线边界判定落入哪个口袋
                local slotIdx = slotCount
                for si = 1, slotCount do
                    if ball.x < (slotEdges[si + 1] or 1e9) then
                        slotIdx = si
                        break
                    end
                end
                slotIdx = math_max(1, math_min(slotCount, slotIdx))

                local slot = slots[slotIdx]
                local mult = Config.GetSlotMult(slot.level or 1)

                -- ════════════════════════════════════════════
                -- 球币路径：只受弹珠升级影响
                -- ════════════════════════════════════════════
                -- 兼容旧球（没有 ballCoinValue 字段时回退到 value）
                local bCV = ball.ballCoinValue or ball.value or 1
                local gCV = ball.goldCoinValue or ball.value or 1
                local bcEarn = math_floor(bCV * mult)
                if bcEarn < 1 then bcEarn = 1 end

                -- ball_peg_chain（弹珠升级）：每撞一钉+X%
                if pegChainRate > 0 and ball.pegHits > 0 then
                    bcEarn = math_floor(bcEarn * (1 + ball.pegHits * pegChainRate))
                end

                -- ball_crit_boost（弹珠升级）：独立暴击判定
                local isBallCrit = false
                local ballCritChance = M.GetBallCritBoost()
                if ballCritChance > 0 and math_random(100) <= ballCritChance then
                    isBallCrit = true
                    bcEarn = math_floor(bcEarn * 2.0)  -- 球暴击固定2倍
                end

                local ballCoinEarnings = math_max(1, bcEarn)

                -- ════════════════════════════════════════════
                -- 金币路径：只受全局升级影响
                -- ════════════════════════════════════════════
                local gcEarn = math_floor(gCV * mult * coinMagnetMult)
                if gcEarn < 1 then gcEarn = 1 end

                -- heavy_landing（全局升级）
                local heavyMult = M.GetHeavyLanding()
                if heavyMult > 1 then
                    gcEarn = math_floor(gcEarn * heavyMult)
                end

                -- crit_chance + crit_mult（全局升级）：独立暴击判定
                local isCrit = false
                local critChance = M.GetCritChance()
                if critChance > 0 and math_random(100) <= critChance then
                    isCrit = true
                    local critMult = M.GetCritMult()
                    gcEarn = math_floor(gcEarn * critMult)
                end

                -- combo_storm（全局升级）
                local comboPerHit, comboWin = M.GetComboStorm()
                if comboPerHit > 0 then
                    if comboTimer > 0 then
                        comboCount = comboCount + 1
                    else
                        comboCount = 1
                    end
                    comboTimer = comboWin
                    if comboCount > 1 then
                        local comboBonus = 1 + (comboCount - 1) * comboPerHit
                        gcEarn = math_floor(gcEarn * comboBonus)
                    end
                end

                -- slot_fortune（全局升级）
                local fortuneChance, fortuneMult = M.GetSlotFortune()
                local isFortune = false
                if fortuneChance > 0 and math_random() < fortuneChance then
                    gcEarn = math_floor(gcEarn * fortuneMult)
                    isFortune = true
                end

                -- earning_amp（全局升级）
                local ampMult = M.GetEarningAmp()
                if ampMult > 1 then
                    gcEarn = math_floor(gcEarn * ampMult)
                end

                local goldCoinEarnings = math_max(1, gcEarn)
                -- 双倍底袋可能修改了球币，重新取整
                ballCoinEarnings = math_max(1, math_floor(bcEarn))

                -- 分离后的收益：球升级→球币，全局升级→金币
                State.AddIdleBallCoins(ballCoinEarnings)
                State.AddIdleEarnings(goldCoinEarnings)

                -- 用于显示的总收益（取较大值用于特效判定）
                local baseEarnings = math_max(ballCoinEarnings, goldCoinEarnings)

                -- per-slot 掉球计数 + 独立升级检查
                slot.drops = (slot.drops or 0) + 1
                local slotRequired = M.GetSlotUpgradeRequirement(slot.level or 1)
                if slot.drops >= slotRequired then
                    slot.drops = slot.drops - slotRequired
                    slot.level = (slot.level or 1) + 1
                    print(string.format("[IdleMode] Slot #%d upgraded to Lv.%d", slotIdx, slot.level))
                    State.uiDirty = true
                end

                -- 飘字（双币种拆为两个飘字，各带图标 + 抛物线）
                local sx = slotCenters[slotIdx] or (boardLeft + (slotIdx - 0.5) * slotWidth)
                local popupY = slotY - 5

                -- 球币飘字（向左抛物线）
                local bcText = "+" .. State.FormatNumber(ballCoinEarnings)
                local bcColor = Config.GetMultColor(mult)
                if isCrit or isBallCrit then
                    bcText = bcText .. " 暴击!"
                    bcColor = { 255, 60, 60, 255 }
                end
                if isFortune then
                    bcText = bcText .. " 祝福!"
                end
                if comboPerHit > 0 and comboCount > 1 then
                    bcText = bcText .. string.format(" ×%d连", comboCount)
                end
                local btIdx = M.GetCurrentBallType()
                local bt = Config.BALL_TYPES[btIdx]
                popups[#popups + 1] = {
                    x = sx, y = popupY,
                    text = bcText,
                    timer = CONFIG.POPUP_DURATION,
                    color = bcColor,
                    iconType = "ball",
                    skinKey = bt and bt.skinKey or "iron",
                    vx = -(30 + math.random() * 30),
                    vy = -(80 + math.random() * 40),
                    elapsed = 0,
                }

                -- 金币飘字（向右抛物线）
                local gcText = "+" .. State.FormatNumber(goldCoinEarnings)
                popups[#popups + 1] = {
                    x = sx, y = popupY,
                    text = gcText,
                    timer = CONFIG.POPUP_DURATION,
                    color = { 255, 200, 50, 255 },
                    iconType = "gold",
                    vx = 30 + math.random() * 30,
                    vy = -(80 + math.random() * 40),
                    elapsed = 0,
                }

                -- 落袋音效
                if State.sfxSlotLand then
                    local vol = gameState.settings.sfxVolume
                    if vol > 0 and State.sfxScene_ then
                        local node = State.sfxScene_:CreateChild("SFX")
                        local src = node:CreateComponent("SoundSource")
                        src.soundType = "Effect"
                        src.gain = 0.3 * vol
                        src.autoRemoveMode = REMOVE_NODE
                        src:Play(State.sfxSlotLand)
                    end
                end

                ball.alive = false
            end

            -- 超时移除
            if ball.aliveTime > 15 then
                ball.alive = false
            end

            i = i + 1
        end
    end
end

-- ============================================================================
-- 底袋自动升级系统（每N球+1倍率，N随倍率增加）
-- ============================================================================

--- 计算当前倍率下，升级到下一级需要掉多少球
---@param currentLevel number 当前底袋等级
---@return number 需要的球数
function M.GetSlotUpgradeRequirement(currentLevel)
    local baseN = Config.IDLE.SLOT_UPGRADE_BASE_N
    local growth = Config.IDLE.SLOT_UPGRADE_N_GROWTH
    -- 等级1→2需5球，2→3需7球，3→4需10球...
    return math_ceil(baseN * (growth ^ (currentLevel - 1)))
end

--- 获取指定口袋的升级进度（per-slot 独立升级）
---@param slotIndex number 口袋索引
---@return number drops 已掉入球数
---@return number required 升级所需球数
---@return number slotLevel 当前口袋等级
function M.GetSlotProgress(slotIndex)
    local slot = slots[slotIndex]
    if not slot then return 0, 1, 1 end
    local level = slot.level or 1
    local drops = slot.drops or 0
    local required = M.GetSlotUpgradeRequirement(level)
    return drops, required, level
end

--- 获取所有口袋进度摘要（用于 TopBar 显示）
---@return number minLevel 最低等级
---@return number maxLevel 最高等级
---@return number avgProgress 平均进度 (0~1)
function M.GetSlotUpgradeProgress()
    if #slots == 0 then return 1, 1, 0 end
    local minLv, maxLv = 999999, 0
    local totalPct = 0
    for i = 1, #slots do
        local slot = slots[i]
        local lv = slot.level or 1
        local dr = slot.drops or 0
        local req = M.GetSlotUpgradeRequirement(lv)
        if lv < minLv then minLv = lv end
        if lv > maxLv then maxLv = lv end
        totalPct = totalPct + dr / req
    end
    return minLv, maxLv, totalPct / #slots
end

--- 旧接口保留为空操作（per-slot 升级在落袋检测中即时执行）
CheckSlotAutoUpgrade = function() end

-- ============================================================================
-- 关卡系统（per-level 持久化、切换、解锁）
-- ============================================================================

--- 确保指定关卡的持久化数据存在（首次进入时初始化）
EnsureLevelData = function(level)
    if gameState.idleLevelData[level] then
        -- 兼容旧存档：补充 drops 字段
        local ld = gameState.idleLevelData[level]
        for i = 1, #ld.slots do
            if ld.slots[i].drops == nil then
                ld.slots[i].drops = 0
            end
        end
        -- 兼容旧存档：补充 ballCoins 字段（按关卡独立球币）
        if ld.ballCoins == nil then
            ld.ballCoins = BigNum.new(0)
        end
        return
    end
    local baseLevel = M.GetBaseSlotLevel()
    local newSlots = {}
    for i = 1, Config.IDLE.MAX_IDLE_SLOTS do
        newSlots[i] = { kind = "good", level = baseLevel, drops = 0 }
    end
    gameState.idleLevelData[level] = {
        slots = newSlots,
        ballsDropped = 0,
        levelBallCoins = BigNum.new(0),  -- 本关累计球币（统计用，判断解锁）
        ballCoins = BigNum.new(0),       -- 本关可消费球币余额
    }
end

--- 将当前关卡运行时数据写回 idleLevelData
local function SaveCurrentLevelData()
    local lv = gameState.idleLevel
    EnsureLevelData(lv)
    local ld = gameState.idleLevelData[lv]
    -- 先刷 pending 球币
    State.FlushIdleEarnings()
    -- 保存 slots 引用（直接共享 table 即可，无需深拷贝）
    ld.slots = gameState.idleSlots
    ld.ballsDropped = gameState.idleBallsDropped
    -- 保存当前关卡的可消费球币
    ld.ballCoins = gameState.idleBallCoins
end

--- 从 idleLevelData 加载指定关卡的数据到运行时字段
local function LoadLevelData(level)
    EnsureLevelData(level)
    local ld = gameState.idleLevelData[level]
    gameState.idleSlots = ld.slots
    gameState.idleBallsDropped = ld.ballsDropped
    gameState.idleLevel = level
    -- 恢复该关卡的可消费球币
    gameState.idleBallCoins = ld.ballCoins
    slots = gameState.idleSlots
end

--- 获取解锁第 level 关所需的累计球币门槛
---@param level number 要解锁的关卡编号（>=2）
---@return table BigNum
function M.GetLevelThreshold(level)
    if level <= 1 then return BigNum.new(0) end
    local base = Config.IDLE.LEVEL_THRESHOLD_BASE
    local growth = Config.IDLE.LEVEL_THRESHOLD_GROWTH
    -- level 2 需 base, level 3 需 base*growth, ...
    return BigNum.new(math_ceil(base * (growth ^ (level - 2))))
end

--- 获取当关累计球币
function M.GetCurrentLevelBallCoins()
    local ld = gameState.idleLevelData[gameState.idleLevel]
    if ld then return ld.levelBallCoins end
    return BigNum.new(0)
end

--- 检查并触发技能选择（每帧调用）
--- 当所有弹珠升级达到 goalLevel 时触发三选一弹窗
function M.CheckLevelUnlock()
    return M.CheckSkillTrigger()
end

--- 切换到指定关卡（玩家可自由切换已解锁关卡）
---@param targetLevel number
---@return boolean success
function M.SwitchToLevel(targetLevel)
    if targetLevel < 1 or targetLevel > gameState.idleMaxUnlockedLevel then
        return false
    end
    if targetLevel == gameState.idleLevel then return true end

    -- 保存当前关卡数据
    SaveCurrentLevelData()

    -- 清空运行时弹珠和飘字
    balls = {}
    popups = {}
    dropCooldownTimer = 0

    -- 加载目标关卡
    LoadLevelData(targetLevel)

    -- 重建钉子布局
    M.RecalcLayout()
    M.InitPegs()

    -- 切换关卡后重置技能触发锁（允许新关卡的目标检测）
    M._skillTriggerLock = false

    print("[IdleMode] Switched to level " .. targetLevel)
    State.uiDirty = true
    return true
end

--- 获取当前关卡的球初始价值（接口：受全局升级影响）
function M.GetBaseBallValue()
    return Config.IDLE.BASE_DROP_VALUE + gameState.idleGlobalBallValueBonus
end

--- 获取当前关卡的底袋初始等级（接口：受全局升级影响）
function M.GetBaseSlotLevel()
    return Config.IDLE.IDLE_SLOT_INIT_LV + gameState.idleGlobalSlotMultBonus
end

-- ============================================================================
-- 球升级（放置模式独立）
-- ============================================================================

--- 获取放置模式球升级费用（用球币支付）
function M.GetBallUpgradeCost(typeIdx)
    local bt = Config.BALL_TYPES[typeIdx]
    if not bt then return BigNum.new(999999999) end
    local level = gameState.idleBallLevels[typeIdx]
    if level <= 0 then
        -- 尚未解锁，费用=解锁费
        return M.GetBallUnlockCost(typeIdx)
    end
    -- 升级费 = baseCost × IDLE倍率 × (level + 1)（球币）
    local baseCost = bt.cost
    if baseCost == 0 then baseCost = 10 end  -- 铁球升级费
    return math_floor(BigNum.new(baseCost) * Config.IDLE.BALL_COST_MULT * (level + 1))
end

--- 升级/解锁放置模式球（消耗球币）
function M.UpgradeBall(typeIdx)
    local cost = M.GetBallUpgradeCost(typeIdx)
    if not State.SpendIdleBallCoins(cost) then return false end
    gameState.idleBallLevels[typeIdx] = (gameState.idleBallLevels[typeIdx] or 0) + 1
    return true
end

-- ============================================================================
-- 转生系统
-- ============================================================================

--- 检查是否可以转生
function M.CanPrestige()
    local threshold = BigNum.new(Config.IDLE.PRESTIGE_THRESHOLD)
    return gameState.idleTotalEarned >= threshold
end

--- 执行转生
function M.DoPrestige()
    if not M.CanPrestige() then return false end
    gameState.idlePrestigeCount = gameState.idlePrestigeCount + 1
    gameState.idlePrestigeMult = (1.0 + gameState.idlePrestigeCount * Config.IDLE.PRESTIGE_MULT_BONUS) * M.GetPrestigeBoost()
    State.ResetIdleEconomy()

    -- 重建口袋（ResetIdleEconomy 已清空 idleSlots）
    M.ResetSlots()
    M.InitPegs()
    balls  = {}
    popups = {}
    return true
end

-- ============================================================================
-- 初始化 / 进入 / 退出
-- ============================================================================

function M.InitSlots()
    -- 使用 per-level 持久化：确保当前关卡数据存在，然后加载
    local lv = gameState.idleLevel
    EnsureLevelData(lv)
    local ld = gameState.idleLevelData[lv]
    gameState.idleSlots = ld.slots
    gameState.idleBallsDropped = ld.ballsDropped
    gameState.idleBallCoins = ld.ballCoins  -- 恢复当前关卡球币
    slots = gameState.idleSlots
end

--- 重置底袋到初始状态（转生时调用——清空所有关卡数据）
function M.ResetSlots()
    gameState.idleLevelData = {}
    gameState.idleLevel = 1
    gameState.idleMaxUnlockedLevel = 1
    EnsureLevelData(1)
    local ld = gameState.idleLevelData[1]
    gameState.idleSlots = ld.slots
    gameState.idleBallsDropped = ld.ballsDropped
    gameState.idleBallCoins = ld.ballCoins  -- 重置球币为第1关初始值
    slots = gameState.idleSlots
end

function M.Enter()
    print("[IdleMode] Entering idle mode")
    M.ApplyUpgradeEffects()  -- 同步全局升级加成
    M.InitSlots()
    M.RecalcLayout()
    M.InitPegs()
    balls     = {}
    popups    = {}
    dropCooldownTimer = 0
    comboCount = 0
    comboTimer = 0
    M._ballAutoDropTimer = 0
    M._skillTriggerLock = false   -- 防止每帧重复弹窗
    skillCooldowns = {}           -- 重置技能冷却
    gameState.gamePhase = "idle"
    -- 创建下半屏 UI
    local IdleUI = require("IdleUI")
    IdleUI.CreateUI()
end

function M.Exit()
    print("[IdleMode] Exiting idle mode")
    -- 销毁下半屏 UI
    local IdleUI = require("IdleUI")
    IdleUI.DestroyUI()
    balls  = {}
    popups = {}
    pegs   = {}
    grid   = {}
    gameState.gamePhase = "menu"
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function M.Update(dt)
    S = State.S  -- 刷新缩放引用

    M._pegSfxThisFrame = false

    -- 冷却倒计时
    if dropCooldownTimer > 0 then
        dropCooldownTimer = dropCooldownTimer - dt
        if dropCooldownTimer < 0 then dropCooldownTimer = 0 end
    end

    -- 连击窗口倒计时
    if comboTimer > 0 then
        comboTimer = comboTimer - dt
        if comboTimer <= 0 then
            comboTimer = 0
            comboCount = 0
        end
    end

    -- 天降弹珠（sky_drop 升级）
    local skyInterval = M.GetSkyDropInterval()
    if skyInterval > 0 then
        skyDropTimer = skyDropTimer + dt
        if skyDropTimer >= skyInterval then
            skyDropTimer = skyDropTimer - skyInterval
            -- 随机位置自动投放一颗球（不受冷却限制）
            if #balls < CONFIG.MAX_BALLS then
                local typeIdx = M.GetCurrentBallType()
                local bt = Config.BALL_TYPES[typeIdx]
                if bt then
                    local baseVal = M.GetBaseBallValue() + M.GetBallValueBonus()
                    local val = baseVal * M.GetBallMultiplier() * gameState.idlePrestigeMult
                    local bs = boardScale
                    local sMargin = (contentRight - contentLeft) * 0.08
                    balls[#balls + 1] = {
                        x = contentLeft + sMargin + math_random() * (contentRight - contentLeft - sMargin * 2),
                        y = contentTop - 5,
                        vx = (math_random() - 0.5) * 20 * bs,
                        vy = 0,
                        radius = CONFIG.BALL_RADIUS * bs,
                        typeIndex = typeIdx,
                        value = val,
                        trail = {},
                        alive = true,
                        pegHits = 0,
                        aliveTime = 0,
                        baseRadius = CONFIG.BALL_RADIUS * bs,
                    }
                end
            end
        end
    end

    -- 弹珠自动掉落（ball_auto_drop 能力）
    local ballAutoInterval = M.GetBallAutoDropInterval()
    if ballAutoInterval > 0 then
        if not M._ballAutoDropTimer then M._ballAutoDropTimer = 0 end
        M._ballAutoDropTimer = M._ballAutoDropTimer + dt
        if M._ballAutoDropTimer >= ballAutoInterval then
            M._ballAutoDropTimer = M._ballAutoDropTimer - ballAutoInterval
            -- 绕过冷却直接投放
            if #balls < CONFIG.MAX_BALLS then
                local typeIdx = M.GetCurrentBallType()
                local bt = Config.BALL_TYPES[typeIdx]
                if bt then
                    local baseVal = M.GetBaseBallValue() + M.GetBallValueBonus()
                    local val = baseVal * M.GetBallMultiplier() * gameState.idlePrestigeMult
                    local bs = boardScale
                    local aMargin = (contentRight - contentLeft) * 0.08
                    balls[#balls + 1] = {
                        x = contentLeft + aMargin + math_random() * (contentRight - contentLeft - aMargin * 2),
                        y = contentTop - 5,
                        vx = (math_random() - 0.5) * 20 * bs,
                        vy = 0,
                        radius = CONFIG.BALL_RADIUS * bs,
                        typeIndex = typeIdx,
                        value = val,
                        trail = {},
                        alive = true,
                        pegHits = 0,
                        aliveTime = 0,
                        baseRadius = CONFIG.BALL_RADIUS * bs,
                    }
                    gameState.idleBallsDropped = gameState.idleBallsDropped + 1
                end
            end
        end
    end

    -- (mass_drop 已改为 CD 主动技能，由 ActivateSkill 触发)

    -- CD 主动技能更新
    M.UpdateSkills(dt)

    -- 物理
    M.UpdateBalls(dt)

    -- 钉子 hitTimer 衰减
    for _, peg in ipairs(pegs) do
        if peg.hitTimer > 0 then
            peg.hitTimer = peg.hitTimer - dt
        end
    end

    -- 飘字（衰减 timer + 累加 elapsed，位移由 Renderer.DrawPopups 计算）
    local i = 1
    while i <= #popups do
        local p = popups[i]
        p.timer = p.timer - dt
        p.elapsed = (p.elapsed or 0) + dt
        if p.timer <= 0 then
            table.remove(popups, i)
        else
            i = i + 1
        end
    end

    -- 刷新收益
    State.FlushIdleEarnings()

    -- 技能选择检查（防重复弹窗）
    if not M._skillTriggerLock then
        if M.CheckLevelUnlock() then
            M._skillTriggerLock = true
        end
    end

    -- 输入处理
    M.HandleInput()
end

-- ============================================================================
-- 输入处理
-- ============================================================================

function M.HandleInput()
    local dpr = graphics:GetDPR()

    -- 鼠标点击
    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        local mx = input.mousePosition.x / dpr
        local my = input.mousePosition.y / dpr
        M.HandleClick(mx, my)
    end

    -- 触摸
    for t = 0, input:GetNumTouches() - 1 do
        local touch = input:GetTouch(t)
        if touch and touch.pressure > 0 and touch.delta.x == 0 and touch.delta.y == 0 then
            local tx = touch.position.x / dpr
            local ty = touch.position.y / dpr
            M.HandleClick(tx, ty)
        end
    end

    -- 空格键投弹（随机位置）
    if input:GetKeyPress(KEY_SPACE) then
        M.DropBall(nil)
    end
end

function M.HandleClick(lx, ly)
    -- 返回按钮
    if HitRect(backBtnRect, lx, ly) then
        M.Exit()
        return
    end

    -- 棋盘区域 = 投放弹珠（随机位置）
    if ly >= contentTop and ly <= contentBottom and lx >= contentLeft and lx <= contentRight then
        M.DropBall(nil)
        return
    end
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

-- 静态保存表（避免每帧分配）
local _savedGS = {}

function M.Render(vg, w, h)
    S = State.S
    local Renderer = require("Renderer")  -- lazy require 避免循环依赖

    -- 更新缓存
    if gameState.idleCoins ~= cachedGoldRef then
        cachedGoldRef = gameState.idleCoins
        cachedGoldStr = State.FormatNumber(gameState.idleCoins)
    end
    if gameState.idleBallCoins ~= cachedBallCoinRef then
        cachedBallCoinRef = gameState.idleBallCoins
        cachedBallCoinStr = State.FormatNumber(gameState.idleBallCoins)
    end

    -- ======= 临时注入 idle 数据到 gameState，复用主游戏渲染 =======
    _savedGS.pegs       = gameState.pegs
    _savedGS.balls      = gameState.balls
    _savedGS.slots      = gameState.slots
    _savedGS.popups     = gameState.popups
    _savedGS.boardLeft  = gameState.boardLeft
    _savedGS.boardRight = gameState.boardRight
    _savedGS.boardTop   = gameState.boardTop
    _savedGS.boardBottom = gameState.boardBottom
    _savedGS.boardScale = gameState.boardScale
    _savedGS.splitY     = gameState.splitY
    _savedGS.slotWidth  = gameState.slotWidth
    _savedGS.slotEdges  = gameState.slotEdges
    _savedGS.slotCenters = gameState.slotCenters
    _savedGS.slotWidths = gameState.slotWidths
    _savedGS.contentLeft   = gameState.contentLeft
    _savedGS.contentRight  = gameState.contentRight
    _savedGS.contentTop    = gameState.contentTop
    _savedGS.contentBottom = gameState.contentBottom

    gameState.pegs       = pegs
    gameState.balls      = balls
    gameState.slots      = slots
    gameState.popups     = popups
    gameState.boardLeft  = boardLeft
    gameState.boardRight = boardRight
    gameState.boardTop   = boardTop
    gameState.boardBottom = boardBottom
    gameState.boardScale = boardScale
    gameState.splitY     = splitY
    gameState.slotWidth  = slotWidth
    gameState.slotEdges  = slotEdges
    gameState.slotCenters = slotCenters
    gameState.slotWidths = slotWidths
    gameState.contentLeft   = contentLeft
    gameState.contentRight  = contentRight
    gameState.contentTop    = contentTop
    gameState.contentBottom = contentBottom

    -- ======= 上半屏：棋盘（复用主游戏渲染） =======
    Renderer.DrawBackground(vg, w, h)

    nvgSave(vg)
    nvgScissor(vg, 0, 0, w, splitY + 2)
    Renderer.DrawSlots(vg)
    Renderer.DrawPegs(vg)
    Renderer.DrawBalls(vg)
    Renderer.DrawPopups(vg)
    nvgRestore(vg)

    Renderer.DrawSplitLine(vg, w)

    -- ======= 还原 gameState =======
    gameState.pegs       = _savedGS.pegs
    gameState.balls      = _savedGS.balls
    gameState.slots      = _savedGS.slots
    gameState.popups     = _savedGS.popups
    gameState.boardLeft  = _savedGS.boardLeft
    gameState.boardRight = _savedGS.boardRight
    gameState.boardTop   = _savedGS.boardTop
    gameState.boardBottom = _savedGS.boardBottom
    gameState.boardScale = _savedGS.boardScale
    gameState.splitY     = _savedGS.splitY
    gameState.slotWidth  = _savedGS.slotWidth
    gameState.slotEdges  = _savedGS.slotEdges
    gameState.slotCenters = _savedGS.slotCenters
    gameState.slotWidths = _savedGS.slotWidths
    gameState.contentLeft   = _savedGS.contentLeft
    gameState.contentRight  = _savedGS.contentRight
    gameState.contentTop    = _savedGS.contentTop
    gameState.contentBottom = _savedGS.contentBottom

    -- ======= TopBar（放置模式独有） =======
    M.DrawIdleTopBar(vg, w)

end

-- DrawDropRing 已移至 IdleUI.RenderDropRing（通过 UI.RegisterGlobalComponent 在 UI 层之上绘制）

-- ---- TopBar ----
function M.DrawIdleTopBar(vg, w)
    local fontNormal = State.fontNormal
    local bs = boardScale
    local barH = CONFIG.BOARD_MARGIN_TOP * bs

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, barH)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, 0, 0, barH,
        nvgRGBA(20, 25, 50, 240), nvgRGBA(15, 20, 40, 200)))
    nvgFill(vg)

    nvgFontFaceId(vg, fontNormal)

    -- 返回按钮（左侧）
    local btnW = S(48)
    local btnH = S(28)
    local btnX = S(8)
    local btnY = S(6)
    backBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }

    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, S(6))
    nvgFillColor(vg, nvgRGBA(60, 65, 90, 200))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnX, btnY, btnW, btnH, S(6))
    nvgStrokeColor(vg, nvgRGBA(100, 120, 180, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontSize(vg, S(13))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 240, 230))
    nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, "< 返回", nil)

    -- 标题
    nvgFontSize(vg, S(16))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 80, 255))
    nvgText(vg, w / 2, S(16), "放置模式", nil)

    -- 阶段信息（左侧中间）
    nvgFontSize(vg, S(10))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 阶段编号 + 底袋等级范围
    local minLv, maxLv, avgProg = M.GetSlotUpgradeProgress()
    local lvText
    if minLv == maxLv then
        lvText = string.format("Lv.%d", minLv)
    else
        lvText = string.format("Lv.%d~%d", minLv, maxLv)
    end
    local stage = gameState.idleSkillPickCount + 1
    nvgFillColor(vg, nvgRGBA(160, 220, 160, 200))
    nvgText(vg, S(64), S(8), string.format("阶段%d  底袋%s  %.0f%%", stage, lvText, avgProg * 100), nil)

    -- 技能进度
    local currentLevel = gameState.idleLevel
    local maxUnlocked = gameState.idleMaxUnlockedLevel
    if currentLevel == maxUnlocked then
        local _, done, total = M.CheckAllGoalsDone()
        nvgFillColor(vg, nvgRGBA(100, 200, 255, 200))
        nvgText(vg, S(64), S(18),
            string.format("技能进度: %d/%d 项达标", done, total), nil)
    else
        nvgFillColor(vg, nvgRGBA(200, 200, 160, 160))
        nvgText(vg, S(64), S(18),
            string.format("已通关  (最高: 阶段%d)", maxUnlocked), nil)
    end

    -- 已获技能数
    local skillCount = 0
    for _ in pairs(gameState.idleSkills) do skillCount = skillCount + 1 end
    if skillCount > 0 then
        nvgFillColor(vg, nvgRGBA(200, 160, 255, 200))
        local extraInfo = ""
        if gameState.idlePrestigeCount > 0 then
            extraInfo = string.format("  转生%d x%.1f", gameState.idlePrestigeCount, gameState.idlePrestigeMult)
        end
        nvgText(vg, S(64), S(28), string.format("技能%d种%s", skillCount, extraInfo), nil)
    elseif gameState.idlePrestigeCount > 0 then
        nvgFillColor(vg, nvgRGBA(200, 160, 255, 200))
        nvgText(vg, S(64), S(28), string.format("转生%d x%.1f", gameState.idlePrestigeCount, gameState.idlePrestigeMult), nil)
    end

end

return M
