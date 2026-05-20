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

-- NanoVG 图片缓存
local imgTopBarBtn = nil   -- 顶部关卡进度按钮背景
local imgBackBtn   = nil   -- 返回按钮图片
local imgRankBg    = nil   -- 排行榜胶囊背景

-- 放置模式排行榜
local IDLE_RANK_KEY = "idle_rank"
local idleMyRank = nil       -- 我的排名（number 或 nil=未上榜/未查询）
local idleRankUploaded = -1  -- 已上传的分数（避免重复上传相同值）

-- UI 面板状态（TopBar 返回按钮仍用 NanoVG）
local backBtnRect = nil
local rankBtnRect = nil  -- 排行榜点击区域

-- 投放冷却
local dropCooldownTimer = 0  -- 剩余冷却时间
local skyDropTimer = 0       -- 天降弹珠计时器

-- 连击风暴状态
local comboCount = 0         -- 当前连击数
local comboTimer = 0         -- 连击窗口剩余时间

-- CD 主动技能运行时状态（不持久化，每次 Enter 重建）
local skillCooldowns = {}    -- { [skillId] = remainingCD }
local skillBuffTimers = {}   -- { [skillId] = remainingDuration } 持续型技能 buff
local splitWaveTimer  = 0    -- 分裂风暴：距下一波分裂的倒计时

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
        local pegsInRow = isOdd and math_max(slotCount + 1, 4) or math_max(slotCount + 2, 5)
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
    local base = lv * 1.5  -- perLevel=1.5%
    -- 暴击星辰加成
    local critExtra, _ = M.GetCritStarBonus()
    return base + critExtra
end

--- 获取暴击倍率
---@return number
function M.GetCritMult()
    local lv = M.GetUpgradeLevel("crit_mult")
    local base = 2.0 + lv * 0.12  -- 基础2x + perLevel=0.12
    -- 暴击星辰加成
    local _, multExtra = M.GetCritStarBonus()
    return base + multExtra
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
    if lv <= 0 and M.GetPrestigeAbilityLevel("combo_resonance") <= 0 then return 0, 0 end
    local basePerHit = lv * 0.03
    local baseWindow = lv > 0 and 3.0 or 0
    -- 连击共鸣加成
    local extraWindow, extraPercent = M.GetComboResonanceBonus()
    return basePerHit + extraPercent, baseWindow + extraWindow
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
    local base = 1.0 + lv * 0.05
    -- 星云倍增加成
    local nebulaLv = M.GetPrestigeAbilityLevel("nebula_multiply")
    return base + nebulaLv * 0.08
end

-- ============================================================================
-- 转生能力系统（星尘消费，永久生效）
-- ============================================================================

--- 获取转生能力等级
---@param abilityId string
---@return number
function M.GetPrestigeAbilityLevel(abilityId)
    return gameState.idlePrestigeAbilities[abilityId] or 0
end

--- 检查 tier 是否已解锁
---@param tier number
---@return boolean
function M.IsTierUnlocked(tier)
    if tier <= 1 then return true end
    -- tier N 需要任一 tier(N-1) 的能力 >= Lv.3
    local prevTier = tier - 1
    for _, cfg in ipairs(Config.IDLE.PRESTIGE_ABILITIES) do
        if cfg.tier == prevTier then
            local lv = M.GetPrestigeAbilityLevel(cfg.id)
            if lv >= 3 then return true end
        end
    end
    return false
end

--- 计算转生可获得的星尘数量
---@return number
function M.GetStardustReward()
    local threshold = BigNum.new(Config.IDLE.PRESTIGE_THRESHOLD)
    -- 虚空之力降低门槛
    local voidLv = M.GetPrestigeAbilityLevel("void_force")
    if voidLv > 0 then
        local reduction = 1.0 - voidLv * 0.04
        threshold = threshold * math_max(0.50, reduction)
    end
    local totalEarned = gameState.idleTotalEarned
    if totalEarned < threshold then return 0 end
    -- ratio = totalEarned / threshold (BigNum -> number)
    local ratio = BigNum.toNumber(totalEarned / threshold)
    if ratio <= 0 then return 0 end
    local logVal = math.log(ratio, 10)
    local countBonus = math_floor(gameState.idlePrestigeCount / 3)
    local base = math_floor(logVal * (1 + gameState.idlePrestigeCount * 0.25)) + 1 + countBonus
    -- 超新星加成
    local supernovaLv = M.GetPrestigeAbilityLevel("supernova")
    if supernovaLv > 0 then
        base = math_floor(base * (1 + supernovaLv * 0.15))
    end
    return math_max(1, base)
end

--- 购买转生能力
---@param abilityId string
---@return boolean 是否购买成功
function M.PurchasePrestigeAbility(abilityId)
    local cfg = Config.GetPrestigeAbilityConfig(abilityId)
    if not cfg then return false end
    -- 检查 tier 解锁
    if not M.IsTierUnlocked(cfg.tier) then return false end
    local currentLv = M.GetPrestigeAbilityLevel(abilityId)
    -- 检查等级上限
    if cfg.maxLevel and currentLv >= cfg.maxLevel then return false end
    local cost = Config.GetPrestigeAbilityCost(cfg, currentLv)
    if cost == math.huge then return false end
    if gameState.idleStardust < cost then return false end
    gameState.idleStardust = gameState.idleStardust - cost
    gameState.idlePrestigeAbilities[abilityId] = currentLv + 1
    -- 保存
    local SaveSystem = require("SaveSystem")
    SaveSystem.Save()
    State.uiDirty = true
    return true
end

--- 获取转生后初始金币（星光积蓄效果）
---@return number
function M.GetPrestigeStartCoins()
    local lv = M.GetPrestigeAbilityLevel("starlight_savings")
    if lv <= 0 then return 0 end
    return lv * 500 * math_max(1, gameState.idlePrestigeCount)
end

--- 获取弹珠精通有效等级加成
---@return number
function M.GetBallMasteryBonus()
    return M.GetPrestigeAbilityLevel("ball_mastery")
end

--- 获取技能余烬 CD 减免比例（0~0.40）
---@return number
function M.GetSkillEmberCDReduction()
    local lv = M.GetPrestigeAbilityLevel("skill_ember")
    return math_min(0.40, lv * 0.04)
end

--- 获取技能超载效果加成倍率
---@return number 1.0+
function M.GetSkillOverloadMult()
    local lv = M.GetPrestigeAbilityLevel("skill_overload")
    return 1.0 + lv * 0.10
end

--- 获取分裂共鸣额外分裂数
---@return number 分裂球额外数, number 风暴额外数
function M.GetSplitResonanceBonus()
    local lv = M.GetPrestigeAbilityLevel("split_resonance")
    return lv * 1, lv * 2
end

--- 获取暴击星辰加成
---@return number 额外暴击率%, number 额外暴击倍率
function M.GetCritStarBonus()
    local lv = M.GetPrestigeAbilityLevel("crit_star")
    return lv * 2, lv * 0.15
end

--- 获取连击共鸣加成
---@return number 额外窗口秒数, number 额外加成比例
function M.GetComboResonanceBonus()
    local lv = M.GetPrestigeAbilityLevel("combo_resonance")
    return lv * 0.4, lv * 0.05
end

-- ============================================================================
-- 弹珠能力升级系统（球币消费，永久生效，转生不重置）
-- ============================================================================

--- 获取当前关卡对应的弹珠类型索引（循环：13关一轮）
---@return number typeIndex
function M.GetCurrentBallType()
    local total = #Config.BALL_TYPES
    return ((gameState.idleLevel - 1) % total) + 1
end

--- 获取当前已完成的循环轮数（0=第一轮，1=第二轮...）
---@return number cycleCount
function M.GetCycleCount()
    local total = #Config.BALL_TYPES
    return math_floor((gameState.idleLevel - 1) / total)
end

--- 获取循环倍率（每轮初始价值翻倍: 2^cycleCount）
---@return number multiplier
function M.GetCycleMultiplier()
    local cycle = M.GetCycleCount()
    if cycle <= 0 then return 1 end
    return 2 ^ cycle
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

--- 获取技能 CD（渐进递减公式，受等级和技能余烬影响）
--- 公式: minCD + (baseCD - minCD) / (1 + k * (lv-1))
---@param skillId string
---@return number CD 秒数
function M.GetSkillCooldown(skillId)
    local lv = M.GetSkillLevel(skillId)
    local cfg = M.GetSkillConfig(skillId)
    if not cfg then return 999 end
    local minCD = cfg.minCooldown or 5
    local k = cfg.cdDiminishK or 0.15
    local cd = minCD + (cfg.cooldown - minCD) / (1 + k * (lv - 1))
    -- 技能余烬 CD 减免
    local emberReduction = M.GetSkillEmberCDReduction()
    if emberReduction > 0 then
        cd = cd * (1 - emberReduction)
        cd = math_max(minCD, cd)
    end
    return cd
end

--- 获取技能 CD 剩余时间
---@param skillId string
---@return number 剩余秒数（0=就绪）
function M.GetSkillCDRemaining(skillId)
    return skillCooldowns[skillId] or 0
end

--- 导出所有技能 CD（供存档序列化）
---@return table<string, number>
function M.ExportSkillCooldowns()
    local out = {}
    for id, cd in pairs(skillCooldowns) do
        if cd > 0 then out[id] = cd end
    end
    return out
end

--- 导入技能 CD（存档反序列化后调用）
---@param data table<string, number>?
function M.ImportSkillCooldowns(data)
    skillCooldowns = {}
    if data then
        for id, cd in pairs(data) do
            skillCooldowns[id] = cd
        end
    end
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

    -- 技能超载倍率（所有技能效果 +10%/lv）
    local overload = M.GetSkillOverloadMult()

    -- ── mass_drop / ball_rain：经典掉球 ──
    if skillId == "mass_drop" or skillId == "ball_rain" then
        local count = cfg.baseBallCount + (lv - 1) * (cfg.ballCountPerLv or 0)
        count = math_floor(count * overload)
        SpawnBalls(count)
        print(string.format("[IdleMode] Skill %s: dropped %d balls (overload x%.2f)", skillId, count, overload))

    -- ── giant_ball：投放一颗超大弹珠 ──
    elseif skillId == "giant_ball" then
        local sizeMult = cfg.baseSize + (lv - 1) * cfg.sizePerLv
        local valMult = cfg.baseValueMult * (cfg.valueGrowth or 1.12) ^ (lv - 1) * overload
        local cx = (contentLeft + contentRight) / 2
        SpawnBalls(1, {
            x = cx,
            radiusMult = sizeMult,
            valueMult = valMult,
            vxSpread = 10,
            noPegCollision = true,
        })
        print(string.format("[IdleMode] Skill giant_ball: size=%.1fx value=%.0fx", sizeMult, valMult))

    -- ── fireworks：从棋盘中心爆出多波弹珠，向四周扩散 ──
    elseif skillId == "fireworks" then
        local waves = math_floor((cfg.baseWaves + (lv - 1) * cfg.wavesPerLv) * overload)
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
        local count = math_floor((cfg.baseBallCount + (lv - 1) * cfg.ballCountPerLv) * overload)
        local valMult = cfg.baseValueMult * (cfg.valueGrowth or 1.12) ^ (lv - 1) * overload
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
        print(string.format("[IdleMode] Skill golden_shower: %d golden balls x%.0f value", count, valMult))

    -- ── peg_explosion：所有钉子爆炸，每颗钉产生金币 + 钉子闪烁 ──
    elseif skillId == "peg_explosion" then
        local goldPerPeg = math_floor(cfg.baseGoldPerPeg * (cfg.goldGrowth or 1.15) ^ (lv - 1) * overload)
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

    -- ── split_burst：现在是持续型技能，不再走瞬发路径 ──
    elseif skillId == "split_burst" then
        M._doSplitWave(cfg, lv)

    -- ── slot_jackpot：所有底袋同时喷出金币奖励 ──
    elseif skillId == "slot_jackpot" then
        local multPerSlot = cfg.baseMultPerSlot * (cfg.multGrowth or 1.15) ^ (lv - 1) * overload
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
        print(string.format("[IdleMode] Skill slot_jackpot: %d slots x %.0f mult = %s gold",
            #slots, multPerSlot, State.FormatNumber(totalGold)))
    end
end

--- 分裂风暴：执行一波分裂（仅分裂非分裂子弹）
---@param cfg table 技能配置
---@param lv number 技能等级
---@param isStorm boolean? 是否为风暴持续期间的波次（区分分裂共鸣加成）
function M._doSplitWave(cfg, lv, isStorm)
    local splitCount = cfg.baseSplitCount + (lv - 1) * (cfg.splitPerLv or 0)
    -- 分裂共鸣：普通分裂 +1/lv，风暴分裂 +2/lv
    local regularExtra, stormExtra = M.GetSplitResonanceBonus()
    if isStorm then
        splitCount = splitCount + stormExtra
    else
        splitCount = splitCount + regularExtra
    end
    -- 技能超载
    splitCount = math_floor(splitCount * M.GetSkillOverloadMult())
    local bs = boardScale or 1
    local currentBalls = {}
    for _, b in ipairs(balls) do
        if b.alive and not b.splitChild then
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
                    splitChild = true,  -- 标记为分裂子弹，不可再分裂
                }
                spawned = spawned + 1
                gameState.idleBallsDropped = gameState.idleBallsDropped + 1
            end
        end
    end
    print(string.format("[IdleMode] Split wave: %d balls x %d splits = %d new", #currentBalls, splitCount, spawned))
end

--- 激活技能（玩家点击技能按钮时调用）
---@param skillId string
---@return boolean 是否成功激活
function M.ActivateSkill(skillId)
    if not M.IsSkillReady(skillId) then return false end

    local cfg = M.GetSkillConfig(skillId)
    if not cfg then return false end

    if cfg.skillType == "duration" then
        -- 持续型技能：启动 buff 计时器
        local lv = M.GetSkillLevel(skillId)
        local dur = (cfg.baseDuration or 5) + (lv - 1) * (cfg.durationPerLv or 1)
        skillBuffTimers[skillId] = dur
        -- 分裂风暴：立即执行第一波，并重置波次计时器
        if skillId == "split_burst" then
            M._doSplitWave(cfg, lv, true)  -- isStorm=true
            splitWaveTimer = cfg.splitInterval or 2.0
        end
        print(string.format("[IdleMode] Activated duration skill: %s (%.1fs)", skillId, dur))
    else
        -- 瞬发型技能
        ExecuteInstantSkill(skillId)
    end
    skillCooldowns[skillId] = M.GetSkillCooldown(skillId)

    print(string.format("[IdleMode] Activated skill: %s", skillId))
    return true
end

--- 查询持续型技能 buff 剩余时间
---@param skillId string
---@return number 剩余秒数（0=未激活）
function M.GetBuffRemaining(skillId)
    return skillBuffTimers[skillId] or 0
end

--- 每帧更新技能 CD 和 buff 计时器（CD 满后自动释放）
---@param dt number
function M.UpdateSkills(dt)
    -- 更新 buff 持续时间
    for skillId, remaining in pairs(skillBuffTimers) do
        if remaining > 0 then
            remaining = remaining - dt
            if remaining <= 0 then
                remaining = 0
                print(string.format("[IdleMode] Buff expired: %s", skillId))
            end
            skillBuffTimers[skillId] = remaining
        end
    end
    -- 分裂风暴：buff 期间周期性分裂
    if (skillBuffTimers["split_burst"] or 0) > 0 then
        splitWaveTimer = splitWaveTimer - dt
        if splitWaveTimer <= 0 then
            local cfg = M.GetSkillConfig("split_burst")
            local lv = M.GetSkillLevel("split_burst")
            if cfg and lv > 0 then
                M._doSplitWave(cfg, lv, true)  -- isStorm=true
                splitWaveTimer = cfg.splitInterval or 2.0
            end
        end
    end
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
---@return table[] { id, cfg, level, cdRemaining, ready, buffRemaining }
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
                buffRemaining = skillBuffTimers[cfg.id] or 0,
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
    gameState.idleSkills[skillId] = curLv + 1

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

--- 随机抽取3个可选技能（无满级限制，所有技能都可被选择升级）
---@return table[] 3个技能配置的数组
function M.RollSkillChoices()
    local pool = {}
    for _, cfg in ipairs(Config.IDLE.SKILLS) do
        pool[#pool + 1] = cfg
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

--- 获取弹珠能力升级当前等级（含弹珠精通加成）
---@param abilityId string
---@param raw boolean? 是否返回原始等级（忽略精通加成）
---@return number
function M.GetBallAbilityLevel(abilityId, raw)
    local lv = gameState.idleBallAbilityLevels[abilityId] or 0
    if raw then return lv end
    -- 弹珠精通：所有已解锁的弹珠能力有效等级 +N
    if lv > 0 then
        lv = lv + M.GetBallMasteryBonus()
    end
    return lv
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
    local prevLevel = M.GetBallAbilityLevel(prevCfg.id, true)  -- raw: 进度判断用原始等级
    return prevLevel >= (cfg.unlockReq or 0)
end

--- 检查所有升级项是否都达到 goalLevel（解锁下一关条件）
---@return boolean allDone, number doneCount, number totalCount
function M.CheckAllGoalsDone()
    local upgrades = M.GetCurrentBallUpgrades()
    local done = 0
    local total = #upgrades
    for i, cfg in ipairs(upgrades) do
        local lv = M.GetBallAbilityLevel(cfg.id, true)  -- raw: 进度判断用原始等级
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

    local level = M.GetBallAbilityLevel(abilityId, true)  -- raw=true 用原始等级判断费用
    if level >= abCfg.maxLevel then return false end

    local cost = Config.GetUpgradeCost(abCfg, level)
    if not State.SpendIdleBallCoins(BigNum.new(cost)) then return false end

    gameState.idleBallAbilityLevels[abilityId] = level + 1
    State.uiDirty = true
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
        local ld = gameState.idleLevelData[level]
        -- 瘦身 v3: 非当前关卡不保存 slots，加载后为空表，需重新初始化
        if not ld.slots or #ld.slots == 0 then
            local baseLevel = M.GetBaseSlotLevel()
            local newSlots = {}
            for i = 1, Config.IDLE.MAX_IDLE_SLOTS do
                newSlots[i] = { kind = "good", level = baseLevel, drops = 0 }
            end
            ld.slots = newSlots
        end
        -- 兼容旧存档：补充 drops 字段
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

    -- 旧关卡数据不保留，直接丢弃
    -- 清空运行时弹珠和飘字
    balls = {}
    popups = {}
    dropCooldownTimer = 0

    -- 清空所有旧关卡数据，只保留新关卡
    gameState.idleLevelData = {}
    LoadLevelData(targetLevel)

    -- 重建钉子布局
    M.RecalcLayout()
    M.InitPegs()

    -- 切换关卡后重置技能触发锁（允许新关卡的目标检测）
    M._skillTriggerLock = false

    print("[IdleMode] Switched to level " .. targetLevel)
    State.uiDirty = true
    M.UploadIdleRank()  -- 阶段变化后刷新排行榜
    return true
end

--- 获取当前关卡的球初始价值（接口：受全局升级 + 循环倍率影响）
function M.GetBaseBallValue()
    return (Config.IDLE.BASE_DROP_VALUE + gameState.idleGlobalBallValueBonus) * M.GetCycleMultiplier()
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

--- 获取当前有效转生门槛（受虚空之力影响）
---@return table BigNum
function M.GetPrestigeThreshold()
    local threshold = BigNum.new(Config.IDLE.PRESTIGE_THRESHOLD)
    local voidLv = M.GetPrestigeAbilityLevel("void_force")
    if voidLv > 0 then
        local reduction = 1.0 - voidLv * 0.04
        threshold = threshold * math_max(0.50, reduction)
    end
    return threshold
end

--- 检查是否可以转生
function M.CanPrestige()
    return gameState.idleTotalEarned >= M.GetPrestigeThreshold()
end

--- 执行转生
function M.DoPrestige()
    if not M.CanPrestige() then return false end
    -- 计算并发放星尘
    local stardust = M.GetStardustReward()
    gameState.idleStardust = gameState.idleStardust + stardust
    gameState.idlePrestigeCount = gameState.idlePrestigeCount + 1
    gameState.idlePrestigeMult = (1.0 + gameState.idlePrestigeCount * Config.IDLE.PRESTIGE_MULT_BONUS) * M.GetPrestigeBoost()
    State.ResetIdleEconomy()

    -- 星光积蓄：转生后给予初始金币
    local startCoins = M.GetPrestigeStartCoins()
    if startCoins > 0 then
        gameState.idleCoins = BigNum.new(startCoins)
    end

    -- 重建口袋（ResetIdleEconomy 已清空 idleSlots）
    M.ResetSlots()
    M.InitPegs()
    balls  = {}
    popups = {}
    print("[IdleMode] Prestige #" .. gameState.idlePrestigeCount .. " stardust+" .. stardust .. " total=" .. gameState.idleStardust)
    M.UploadIdleRank()  -- 转生后刷新排行榜
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

--- 存档加载完成后的实际初始化
-- ============================================================================
-- 放置模式排行榜（转生×10000 + 阶段 组合分数）
-- ============================================================================

--- 计算当前排行榜分数（转生次数优先，阶段次之）
function M.GetIdleRankScore()
    return (gameState.idlePrestigeCount or 0) * 10000 + (gameState.idleLevel or 1)
end

--- 上传排行榜分数（仅当分数变化时）
function M.UploadIdleRank()
    local score = M.GetIdleRankScore()
    if score <= idleRankUploaded then return end
    idleRankUploaded = score

    clientCloud:SetInt(IDLE_RANK_KEY, score, {
        ok = function()
            print("[IdleRank] Upload OK: " .. score)
            -- 上传成功后刷新自己的排名
            M.FetchMyIdleRank()
        end,
        error = function(code, reason)
            print("[IdleRank] Upload error: " .. tostring(reason))
            idleRankUploaded = -1  -- 失败允许重试
        end,
    })
end

--- 查询自己的排名
function M.FetchMyIdleRank()
    clientCloud:GetUserRank(clientCloud.userId, IDLE_RANK_KEY, {
        ok = function(rank, scoreValue)
            idleMyRank = rank
            print("[IdleRank] My rank: " .. tostring(rank))
        end,
        error = function(code, reason)
            print("[IdleRank] GetUserRank error: " .. tostring(reason))
        end,
    })
end

--- 获取缓存的排名（供 UI 显示）
function M.GetMyIdleRank()
    return idleMyRank
end

-- ======= 放置模式排行榜面板 =======
local idleLeaderboardShown = false

function M.ShowIdleLeaderboard()
    if idleLeaderboardShown then return end
    local IdleUI = require("IdleUI")
    local root = IdleUI.GetRoot()
    if not root then return end
    idleLeaderboardShown = true

    -- 加载排行榜数据
    local rankEntries = {}
    local loading = true

    local function BuildPanel()
        -- 移除旧面板
        local old = root:FindById("idleRankOverlay")
        if old then old:Remove() end

        local UI = require("urhox-libs/UI")
        local rows = {}

        if loading then
            table.insert(rows, UI.Label {
                text = "加载中...", fontSize = 14,
                fontColor = { 160, 170, 200, 200 },
                textAlign = "center", marginTop = 20,
            })
        elseif #rankEntries == 0 then
            table.insert(rows, UI.Label {
                text = "暂无排行数据", fontSize = 14,
                fontColor = { 160, 170, 200, 200 },
                textAlign = "center", marginTop = 20,
            })
        else
            for _, e in ipairs(rankEntries) do
                local rankColor
                if e.rank == 1 then rankColor = { 255, 215, 0, 255 }
                elseif e.rank == 2 then rankColor = { 200, 210, 225, 255 }
                elseif e.rank == 3 then rankColor = { 205, 133, 63, 255 }
                else rankColor = { 160, 170, 200, 220 } end

                local nameColor = e.isMe and { 120, 220, 255, 255 } or { 210, 220, 240, 240 }
                local name = (e.nickname or "玩家")
                if e.isMe then name = name .. " (我)" end
                if #name > 14 then name = string.sub(name, 1, 11) .. "..." end

                local prestige = math_floor(e.score / 10000)
                local stage = e.score % 10000
                local scoreText = prestige > 0
                    and string.format("转生%d 阶段%d", prestige, stage)
                    or string.format("阶段%d", stage)

                table.insert(rows, UI.Panel {
                    width = "100%", flexDirection = "row",
                    padding = { 4, 6, 4, 6 },
                    backgroundColor = e.isMe and { 40, 60, 100, 120 } or { 0, 0, 0, 0 },
                    borderRadius = 4, alignItems = "center",
                    children = {
                        UI.Label { text = tostring(e.rank), fontSize = 14,
                            fontColor = rankColor, width = 24, textAlign = "center" },
                        UI.Label { text = name, fontSize = 13,
                            fontColor = nameColor, flexGrow = 1, flexShrink = 1 },
                        UI.Label { text = scoreText, fontSize = 12,
                            fontColor = { 255, 230, 140, 240 }, textAlign = "right" },
                    },
                })
            end
        end

        -- 我的排名
        local myInfo = {}
        if idleMyRank then
            table.insert(myInfo, UI.Label {
                text = "我的排名: #" .. tostring(idleMyRank),
                fontSize = 13, fontColor = { 120, 200, 255, 220 },
                textAlign = "center", marginTop = 4,
            })
        end

        local function closePanel()
            local o = root:FindById("idleRankOverlay")
            if o then o:Remove() end
            idleLeaderboardShown = false
        end

        local overlay = UI.Panel {
            id = "idleRankOverlay",
            position = "absolute", top = 0, left = 0,
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            backgroundColor = { 0, 0, 0, 140 },
            pointerEvents = "auto",
            onClick = function() closePanel() end,
            children = {
                UI.Panel {
                    width = "85%", height = "55%",
                    backgroundColor = { 20, 25, 50, 245 },
                    borderColor = { 80, 110, 180, 200 },
                    borderWidth = 2, borderRadius = 12,
                    padding = { 10, 12, 8, 12 },
                    pointerEvents = "auto",
                    onClick = function() end,
                    children = {
                        -- 关闭按钮
                        UI.Panel {
                            position = "absolute", top = 6, right = 8,
                            width = 26, height = 26, borderRadius = 13,
                            backgroundColor = { 50, 55, 80, 200 },
                            justifyContent = "center", alignItems = "center",
                            pointerEvents = "auto",
                            onClick = function() closePanel() end,
                            children = {
                                UI.Label { text = "×", fontSize = 19,
                                    fontColor = { 180, 190, 220, 240 }, textAlign = "center" },
                            },
                        },
                        -- 标题
                        UI.Label {
                            text = "🏆 放置排行榜", fontSize = 17,
                            fontColor = { 255, 220, 120, 255 },
                            textAlign = "center", marginBottom = 8,
                        },
                        -- 滚动列表
                        UI.ScrollView {
                            width = "100%", flexGrow = 1, flexShrink = 1,
                            children = rows,
                        },
                        -- 底部我的排名
                        table.unpack(myInfo),
                    },
                },
            },
        }
        root:AddChild(overlay)
    end

    -- 先显示加载中
    BuildPanel()

    -- 请求排行数据
    clientCloud:GetRankList(IDLE_RANK_KEY, 0, 20, {
        ok = function(rankList)
            loading = false
            local userIds = {}
            for i, item in ipairs(rankList) do
                local score = (item.iscore and item.iscore[IDLE_RANK_KEY]) or 0
                table.insert(rankEntries, {
                    rank = i,
                    userId = item.userId,
                    nickname = nil,
                    score = score,
                    isMe = (item.userId == clientCloud.userId),
                })
                table.insert(userIds, item.userId)
            end
            if #userIds == 0 then
                BuildPanel()
                return
            end
            GetUserNickname({
                userIds = userIds,
                onSuccess = function(nicknames)
                    local map = {}
                    for _, info in ipairs(nicknames) do
                        map[info.userId] = info.nickname or ""
                    end
                    for _, entry in ipairs(rankEntries) do
                        entry.nickname = map[entry.userId] or "玩家"
                    end
                    BuildPanel()
                end,
                onError = function()
                    for _, entry in ipairs(rankEntries) do
                        entry.nickname = "玩家"
                    end
                    BuildPanel()
                end,
            })
        end,
        error = function(code, reason)
            print("[IdleRank] GetRankList error: " .. tostring(reason))
            loading = false
            BuildPanel()
        end,
    })
end

function M._DoEnter()
    print("[IdleMode] _DoEnter: initializing idle mode")
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
    -- 恢复技能冷却（存档中有则恢复，否则清空）
    if gameState._savedSkillCooldowns then
        M.ImportSkillCooldowns(gameState._savedSkillCooldowns)
        gameState._savedSkillCooldowns = nil
    else
        skillCooldowns = {}
    end
    skillBuffTimers = {}          -- 重置技能 buff
    gameState.gamePhase = "idle"
    -- 创建下半屏 UI
    local IdleUI = require("IdleUI")
    IdleUI.CreateUI()

    -- 上报排行榜 + 查询排名
    M.UploadIdleRank()
end

function M.Enter()
    print("[IdleMode] Entering idle mode (loading saves...)")
    local SaveSystem = require("SaveSystem")

    -- 先标记 gamePhase 防止重复点击
    gameState.gamePhase = "idle_loading"

    -- 对比本地与云端存档，取更新的（带超时+重试）
    local localData = SaveSystem.LoadLocal()

    SaveSystem.LoadCloudKeys({ "shared", "idle" }, function(cloudResult, allFailed)
        if allFailed then
            -- 所有重试耗尽，返回菜单而非用空数据覆盖
            print("[IdleMode] Cloud load FAILED after all retries, returning to menu")
            gameState.gamePhase = "menu"
            gameState.cloudLoadFailed = "idle"
            return
        end

        local cloudShared = cloudResult.shared
        local localCount  = (localData and localData.saveCount) or 0
        local cloudCount  = (cloudShared and cloudShared.saveCount) or 0

        if cloudShared and cloudCount >= localCount then
            -- 云端更新，使用云端分 key 数据
            SaveSystem.DeserializeShared(cloudShared)
            SaveSystem.DeserializeIdle(cloudResult.idle)
            SaveSystem.SaveLocal()  -- 同步到本地
            print("[IdleMode] Using cloud save (saveCount=" .. cloudCount .. " >= local=" .. localCount .. ")")
        elseif localData then
            -- 本地更新，用本地大 blob 数据
            SaveSystem.DeserializeShared(localData)
            SaveSystem.DeserializeIdle(localData)
            SaveSystem.Save()  -- 标脏，30s 后同步到云端
            print("[IdleMode] Using local save (saveCount=" .. localCount .. " > cloud=" .. cloudCount .. ")")
        else
            print("[IdleMode] No save found, using defaults")
        end

        -- 迁移
        if cloudResult._migrated then
            SaveSystem.MigrateLegacyToSplitKeys()
        end

        SaveSystem.MarkCloudLoadSucceeded()
        M._DoEnter()
    end)
end

function M.Exit()
    print("[IdleMode] Exiting idle mode")
    -- 退出前保存当前关卡数据（30s 节流写入云端）
    local SaveSystem = require("SaveSystem")
    SaveSystem.Save()
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

    -- 排行榜按钮
    if HitRect(rankBtnRect, lx, ly) then
        M.ShowIdleLeaderboard()
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

    -- ======= 上半屏：棋盘（复用主游戏渲染，含街机边框） =======
    Renderer.DrawBackground(vg, w, h)

    nvgSave(vg)
    nvgScissor(vg, 0, 0, w, splitY + 2)
    Renderer.DrawBoard(vg, w, h)
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

    -- ======= 返回按钮（左侧，图片） =======
    if not imgBackBtn then
        imgBackBtn = nvgCreateImage(vg, "image/btn_back_20260520134345.png", 0)
    end
    local btnH = S(28)
    local btnW = S(32)
    local btnX = S(6)
    local btnY = S(5)
    backBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }

    if imgBackBtn then
        nvgBeginPath(vg)
        nvgRect(vg, btnX, btnY, btnW, btnH)
        nvgFillPaint(vg, nvgImagePattern(vg, btnX, btnY, btnW, btnH, 0, imgBackBtn, 1.0))
        nvgFill(vg)
    end

    -- ======= 中央关卡进度徽章（angular 按钮图片） =======
    if not imgTopBarBtn then
        imgTopBarBtn = nvgCreateImage(vg, "image/btn_bg_angular.png", 0)
    end

    local cycle = M.GetCycleCount()
    local cycleMult = M.GetCycleMultiplier()
    local _, done, total = M.CheckAllGoalsDone()

    local badgeW = S(90)
    local badgeH = S(30)
    local badgeX = (w - badgeW) / 2
    local badgeY = S(4)

    if imgTopBarBtn then
        nvgBeginPath(vg)
        nvgRect(vg, badgeX, badgeY, badgeW, badgeH)
        nvgFillPaint(vg, nvgImagePattern(vg, badgeX, badgeY, badgeW, badgeH, 0, imgTopBarBtn, 1.0))
        nvgFill(vg)
    end

    local centerX = w / 2
    local line1Y = badgeY + badgeH * 0.38
    local line2Y = badgeY + badgeH * 0.72

    local cycleTag = cycle > 0 and string.format(" x%d", cycleMult) or ""
    nvgFontSize(vg, S(10))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 220, 120, 255))
    nvgText(vg, centerX, line1Y, string.format("阶段 %d%s", gameState.idleLevel, cycleTag), nil)

    nvgFontSize(vg, S(8))
    nvgFillColor(vg, nvgRGBA(140, 200, 255, 220))
    nvgText(vg, centerX, line2Y, string.format("目标 %d/%d", done, total), nil)

    -- ======= 排名显示（关卡徽章左侧，胶囊背景） =======
    if not imgRankBg then
        imgRankBg = nvgCreateImage(vg, "image/btn_bg_capsule.png", 0)
    end
    local rankBgW = S(58)
    local rankBgH = badgeH          -- 与关卡徽章等高
    local rankBgX = btnX + btnW + S(3)
    local rankBgY = badgeY          -- 与关卡徽章同 Y
    rankBtnRect = { x = rankBgX, y = rankBgY, w = rankBgW, h = rankBgH }

    local rankCX = rankBgX + rankBgW / 2
    local rankCY = rankBgY + rankBgH / 2

    -- 绘制胶囊背景
    if imgRankBg then
        nvgBeginPath(vg)
        nvgRect(vg, rankBgX, rankBgY, rankBgW, rankBgH)
        nvgFillPaint(vg, nvgImagePattern(vg, rankBgX, rankBgY, rankBgW, rankBgH, 0, imgRankBg, 0.85))
        nvgFill(vg)
    end

    -- 排名文字
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if idleMyRank then
        nvgFontSize(vg, S(10))
        nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
        nvgText(vg, rankCX, rankCY, "🏆#" .. tostring(idleMyRank), nil)
    else
        nvgFontSize(vg, S(9))
        nvgFillColor(vg, nvgRGBA(120, 130, 160, 180))
        nvgText(vg, rankCX, rankCY, "排行--", nil)
    end
end

return M
